import Foundation

nonisolated final class Manifest: @unchecked Sendable {
    static let shared = Manifest()

    private let queue = DispatchQueue(label: "manifest.queue")
    private let lock = NSLock()
    private var packsByName: [String: Pack] = [:]
    private var itemsByFullName: [String: Item] = [:]

    private init() {}

    func schedule<T>(_ task: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: task())
            }
        }
    }

    func schedule<T, E>(_ task: @escaping () -> T, then continuation: @escaping () -> E) async -> T {
        await withCheckedContinuation { done in
            let box = ResultBox<T>()
            queue.async {
                box.value = task()
            }
            queue.async {
                _ = continuation()
                done.resume(returning: box.value)
            }
        }
    }

    func requestReload() async -> Int {
        await schedule { self.reloadAll() }
    }

    func requestReloadPack(_ name: String) async -> Int {
        await schedule { self.reloadPack(name) }
    }

    func queryPacks(_ query: Query) async -> [Pack] {
        await schedule { self.packsMatching(query) }
    }

    func search(_ string: String) async -> [Item] {
        await schedule { self.searchItems(string) }
    }

    func onAllTasksCompleted() async {
        _ = await schedule { 0 }
    }

    func reloadAll() -> Int {
        print("manifest: requestReload")
        ExternalPack.unpackEmbeddedIfNeeded()
        var loaded: [String: Pack] = [:]
        for name in ExternalPack.installedPackNames() {
            print("manifest: obtaining \(name)")
            loaded[name] = obtainExternalPack(name)
        }
        onPacksReloaded(loaded)
        let count = packs().count
        print("manifest: reloaded \(count) pack(s), \(countItems()) item(s)")
        for pack in packs() {
            print("manifest:   \(pack.name) \"\(pack.title)\" items=\(pack.items.count)")
        }
        return count
    }

    func reloadPack(_ name: String) -> Int {
        print("manifest: requestReloadPack \(name)")
        let pack = obtainExternalPack(name)
        onPackUpdated(name, pack)
        print("manifest: updated \(name) \"\(pack.title)\" items=\(pack.items.count)")
        return packs().count
    }

    func packs() -> [Pack] {
        lock.lock()
        defer { lock.unlock() }
        return packsByName.values.sorted { $0.name < $1.name }
    }

    func pack(named name: String) -> Pack? {
        lock.lock()
        defer { lock.unlock() }
        return packsByName[name]
    }

    func allItems() -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        return itemsByFullName.values.sorted { $0.makeFullName() < $1.makeFullName() }
    }

    func countItems() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return itemsByFullName.count
    }

    func findItem(fullname: String) -> Item? {
        let key = UnitAssets.removeNumber(fullname)
        lock.lock()
        defer { lock.unlock() }
        if let item = itemsByFullName[key] {
            return item
        }
        return itemsByFullName.values.first { $0.makeFullName() == key }
    }

    func itemZip(fullname: String) -> Data {
        guard let item = findItem(fullname: fullname) else {
            fatalError("Manifest missing item '\(fullname)'")
        }
        if !item.isAvailable {
            fatalError("Manifest item '\(fullname)' is locked")
        }
        let url = ExternalPack.itemFile(packName: item.packName, systemName: item.systemName)
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("Manifest could not read \(url.path): \(error)")
        }
    }

    private func obtainExternalPack(_ packName: String) -> Pack {
        let dir = ExternalPack.packDir(packName)
        let metaURL = dir.appendingPathComponent("meta.txt")
        let manifestURL = dir.appendingPathComponent("manifest.xml")
        if !FileManager.default.fileExists(atPath: metaURL.path) {
            fatalError("Manifest pack '\(packName)' missing meta.txt")
        }
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
            fatalError("Manifest pack '\(packName)' missing manifest.xml")
        }
        let meta: PackMeta
        let manifest: Data
        do {
            meta = PackMeta.parse(try Data(contentsOf: metaURL), source: metaURL.path)
            manifest = try Data(contentsOf: manifestURL)
        } catch {
            fatalError("Manifest could not read pack '\(packName)': \(error)")
        }
        let translations = PackTranslator.load(packName: packName)
        let parsed = ManifestXML.parse(manifest, packName: packName, translations: translations)
        return Pack(
            name: packName,
            humanName: meta.mHumanName,
            version: meta.version,
            defScale: parsed.defScale,
            editableItems: parsed.editableItems,
            useCommonBg: parsed.useCommonBg,
            items: parsed.items,
            translations: translations
        )
    }

    private func onPacksReloaded(_ content: [String: Pack]) {
        lock.lock()
        packsByName = content
        itemsByFullName = [:]
        for pack in content.values {
            index(pack)
        }
        lock.unlock()
    }

    private func onPackUpdated(_ packName: String, _ pack: Pack) {
        lock.lock()
        packsByName[packName] = pack
        index(pack)
        lock.unlock()
    }

    private func index(_ pack: Pack) {
        for item in pack.items {
            itemsByFullName[item.makeFullName()] = item
        }
    }

    private func packsMatching(_ query: Query) -> [Pack] {
        if query.isEmpty {
            return packs()
        }
        return query.requestedPacks.compactMap { pack(named: $0) }.sorted { $0.name < $1.name }
    }

    private func searchItems(_ string: String) -> [Item] {
        let query = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return []
        }
        return allItems().filter { item in
            if item.hidden || item.readOnly {
                return false
            }
            return item.systemName.lowercased().contains(query)
                || item.humanName.lowercased().contains(query)
        }
    }

    private final class ResultBox<T> {
        var storage: T?
        var value: T {
            get {
                guard let storage else {
                    fatalError("Manifest schedule continuation ran before task")
                }
                return storage
            }
            set { storage = newValue }
        }
    }
}
