import Foundation

nonisolated final class Manifest: @unchecked Sendable {
    static let shared = Manifest()

    private let queue = DispatchQueue(label: "manifest.queue")
    private let lock = NSLock()
    private let bootLock = NSLock()
    private var bootReloadStarted = false
    private var packsByName: [String: Pack] = [:]
    private var itemsByFullName: [String: Item] = [:]

    private init() {}

    func startBootReload() {
        bootLock.lock()
        defer { bootLock.unlock() }
        if bootReloadStarted {
            return
        }
        bootReloadStarted = true
        BootLog.say("Manifest.startBootReload")
        queue.async {
            BootLog.say("Manifest.boot queue run")
            _ = self.reloadAll()
        }
    }

    func awaitBootReload() async -> Int {
        startBootReload()
        return await schedule { self.packs().count }
    }

    func schedule<T>(_ task: @escaping () -> T) async -> T {
        BootLog.say("Manifest.schedule enqueue")
        return await withCheckedContinuation { continuation in
            queue.async {
                BootLog.say("Manifest.schedule run")
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

    func requestReloadCustomPack() async -> Int {
        await schedule { self.reloadCustomPack() }
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
        BootLog.say("reloadAll start")
        let urls = ExternalPack.bundleArchives()
        BootLog.say("reloadAll \(urls.count) bundle .atp")
        var loaded: [String: Pack] = [:]
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            print("manifest: obtaining \(name)")
            let start = ProcessInfo.processInfo.systemUptime
            loaded[name] = obtainBundlePack(url)
            let ms = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            BootLog.say("obtain \(name) \(ms)ms items=\(loaded[name]!.items.count)")
        }
        loaded[Pack.customName] = obtainCustomPack()
        onPacksReloaded(loaded)
        let count = packs().count
        print("manifest: reloaded \(count) pack(s), \(countItems()) item(s)")
        for pack in packs() {
            print("manifest:   \(pack.name) \"\(pack.title)\" items=\(pack.items.count)")
        }
        BootLog.say("reloadAll done")
        return count
    }

    func reloadPack(_ name: String) -> Int {
        if name == Pack.customName {
            return reloadCustomPack()
        }
        print("manifest: requestReloadPack \(name)")
        let pack = obtainBundlePack(ExternalPack.bundleArchive(name))
        onPackUpdated(name, pack)
        print("manifest: updated \(name) \"\(pack.title)\" items=\(pack.items.count)")
        return packs().count
    }

    func reloadCustomPack() -> Int {
        print("manifest: requestReloadCustomPack")
        onPackUpdated(Pack.customName, obtainCustomPack())
        print("manifest: updated \(Pack.customName) items=\(pack(named: Pack.customName)?.items.count ?? 0)")
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
        let key = PackAlias.resolveUnitName(UnitAssets.removeNumber(fullname))
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
        if item.packName == Pack.customName {
            return CustomItems.zipData(systemName: item.systemName)
        }
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(item.packName))
        return ZipStore.data(atiNamed: "\(item.systemName).ati", in: zip)
    }

    func packLogo(_ packName: String) -> Data {
        if packName == Pack.customName {
            guard let url = Bundle.main.url(forResource: "angry_cat", withExtension: "png", subdirectory: "chrome")
                ?? Bundle.main.url(forResource: "angry_cat", withExtension: "png")
            else {
                fatalError("Manifest missing chrome/angry_cat.png")
            }
            do {
                return try Data(contentsOf: url)
            } catch {
                fatalError("Manifest could not read \(url.path): \(error)")
            }
        }
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        return ZipStore.data(named: "logo.png", in: zip)
    }

    private func obtainBundlePack(_ url: URL) -> Pack {
        let packName = url.deletingPathExtension().lastPathComponent
        let zip = ExternalPack.mappedZip(url)
        let meta = PackMeta.parse(ZipStore.data(named: "meta.txt", in: zip), source: "\(packName)/meta.txt")
        if meta.mSysName != packName {
            fatalError("Manifest \(url.lastPathComponent) meta.mSysName '\(meta.mSysName)' != '\(packName)'")
        }
        let translations = PackTranslator.load(from: zip, packName: packName)
        let parsed = ManifestXML.parse(
            ZipStore.data(named: "manifest.xml", in: zip),
            packName: packName,
            translations: translations,
            archive: zip
        )
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

    /// Android `ReloadCustomPackTask` — `@` pack is the customs directory, not an `.atp`.
    private func obtainCustomPack() -> Pack {
        let files = CustomItems.collect()
        let items = files.map { file -> Item in
            let zip = CustomItems.zipData(systemName: file.systemName)
            let fullName = Pack.customName + ":" + file.systemName
            return Item(
                systemName: file.systemName,
                humanName: file.name,
                packName: Pack.customName,
                fullName: fullName,
                setName: "",
                scale: customScale(zip: zip),
                faceable: false,
                multiframed: false,
                hidden: false,
                readOnly: false
            )
        }
        return Pack(
            name: Pack.customName,
            humanName: Pack.customTitle,
            version: 0,
            defScale: 1,
            editableItems: true,
            useCommonBg: true,
            items: items,
            translations: ["pack_name": Pack.customTitle]
        )
    }

    private func customScale(zip: Data) -> CGFloat {
        if !ZipStore.contains("meta.txt", in: zip) {
            return 1
        }
        guard let object = try? JSONSerialization.jsonObject(with: ZipStore.data(named: "meta.txt", in: zip)) as? [String: Any],
              let number = object["scale"] as? NSNumber
        else {
            return 1
        }
        let scale = CGFloat(truncating: number)
        return scale > 0.01 ? scale : 1
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
        if let old = packsByName[packName] {
            for item in old.items {
                itemsByFullName.removeValue(forKey: item.makeFullName())
            }
        }
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
            let all = packs()
            let custom = all.filter { $0.name == Pack.customName }
            let rest = all.filter { $0.name != Pack.customName }
            return custom + rest
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
