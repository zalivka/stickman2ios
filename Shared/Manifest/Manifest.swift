import Foundation

struct MissingManifestItem: Error {
    let fullname: String

    var message: String {
        guard let colon = fullname.firstIndex(of: ":") else { return "Missing item: \(fullname)" }
        let pack = String(fullname[..<colon])
        let item = String(fullname[fullname.index(after: colon)...])
        guard !pack.isEmpty, !item.isEmpty else { return "Missing item: \(fullname)" }
        return "Missing item: \(item) from \(pack)"
    }
}

nonisolated final class Manifest: @unchecked Sendable {
    static let shared = Manifest()

    private let queue = DispatchQueue(label: "manifest.queue")
    private let lock = NSLock()
    private let bootLock = NSLock()
    private var bootReloadStarted = false
    private var packsByName: [String: Pack] = [:]
    private var packArchives: [String: ZipStore.Index] = [:]
    private var itemsByFullName: [String: Item] = [:]
    private var userPackNames: Set<String> = []
    private var customsObserver: NSObjectProtocol?

    private init() {
        // Reload the cached `@` pack on every customs change, no matter which
        // screen made it. Otherwise a deleted file stays indexed until some
        // visible panel happens to reload, and itemZip dies reading it.
        customsObserver = NotificationCenter.default.addObserver(
            forName: .customItemsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                _ = self.reloadCustomPack()
            }
        }
    }

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

    func scheduleThrowing<T>(_ task: @escaping () throws -> T) async throws -> T {
        BootLog.say("Manifest.schedule enqueue")
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                BootLog.say("Manifest.schedule run")
                do {
                    continuation.resume(returning: try task())
                } catch {
                    continuation.resume(throwing: error)
                }
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
        AssetTemplates.prepare()
        let urls = ExternalPack.bundleArchives()
        BootLog.say("reloadAll \(urls.count) bundle .atp")
        var loaded: [String: Pack] = [:]
        var archives: [String: ZipStore.Index] = [:]
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            print("manifest: obtaining \(name)")
            let start = ProcessInfo.processInfo.systemUptime
            let (pack, index) = obtainBundlePack(url)
            loaded[name] = pack
            archives[name] = index
            let ms = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            BootLog.say("obtain \(name) \(ms)ms items=\(loaded[name]!.items.count)")
        }
        var userPacks = Set<String>()
        var failed: [String] = []
        for url in InstalledPacks.archives() {
            let name = url.deletingPathExtension().lastPathComponent
            if loaded[name] != nil {
                print("manifest: skipping user pack \(name), bundled name")
                continue
            }
            print("manifest: obtaining user \(name)")
            do {
                let (pack, index) = try obtainUserPack(url)
                loaded[name] = pack
                archives[name] = index
                userPacks.insert(name)
            } catch {
                print("manifest: skipping user pack \(name): \(error)")
                failed.append(name)
            }
        }
        loaded[Pack.customName] = obtainCustomPack()
        onPacksReloaded(loaded, archives: archives, userPacks: userPacks)
        toastLoadFailures(failed)
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
        if name == AssetTemplates.packName {
            AssetTemplates.prepare()
        }
        print("manifest: requestReloadPack \(name)")
        if InstalledPacks.contains(name) {
            do {
                let (pack, index) = try obtainUserPack(InstalledPacks.file(sysName: name))
                lock.lock()
                userPackNames.insert(name)
                lock.unlock()
                onPackUpdated(name, pack, archive: index)
                print("manifest: updated \(name) \"\(pack.title)\" items=\(pack.items.count)")
            } catch {
                print("manifest: skipping user pack \(name): \(error)")
                toastLoadFailures([name])
            }
            return packs().count
        }
        let (pack, index) = obtainBundlePack(ExternalPack.bundleArchive(name))
        onPackUpdated(name, pack, archive: index)
        print("manifest: updated \(name) \"\(pack.title)\" items=\(pack.items.count)")
        return packs().count
    }

    func reloadCustomPack() -> Int {
        print("manifest: requestReloadCustomPack")
        onPackUpdated(Pack.customName, obtainCustomPack(), archive: nil)
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

    func itemZip(fullname: String) throws -> Data {
        guard let item = findItem(fullname: fullname) else {
            throw MissingManifestItem(fullname: fullname)
        }
        return try loadZip(item: item, fullname: fullname)
    }

    private func loadZip(item: Item, fullname: String) throws -> Data {
        if item.packName == Pack.customName {
            // Read directly: a fileExists check followed by a read is a TOCTOU
            // pair (a delete landing between them still crashes). A nil read
            // means the customs directory changed under the cached pack, so
            // reload and retry once; report missing only if still unreadable.
            if let zip = try? Data(contentsOf: CustomItems.file(systemName: item.systemName)) {
                return zip
            }
            _ = reloadCustomPack()
            guard let fresh = findItem(fullname: fullname), fresh.packName == Pack.customName else {
                throw MissingManifestItem(fullname: fullname)
            }
            guard let zip = try? Data(contentsOf: CustomItems.file(systemName: fresh.systemName)) else {
                throw MissingManifestItem(fullname: fullname)
            }
            return zip
        }
        if item.packName == AssetTemplates.packName {
            return try AssetTemplates.itemData(item.systemName)
        }
        let archive = try packArchive(named: item.packName)
        return try archive.dataAtiThrowing(file: "\(item.systemName).ati")
    }

    func packLogo(_ packName: String) throws -> Data {
        if packName == Pack.customName {
            guard let url = Bundle.main.url(forResource: "angry_cat", withExtension: "png", subdirectory: "chrome")
                ?? Bundle.main.url(forResource: "angry_cat", withExtension: "png")
            else {
                // bundled resource: a failure here ships broken, fires on first debug run
                fatalError("Manifest missing chrome/angry_cat.png")
            }
            do {
                return try Data(contentsOf: url)
            } catch {
                // bundled resource: a failure here ships broken, fires on first debug run
                fatalError("Manifest could not read \(url.path): \(error)")
            }
        }
        let archive = try packArchive(named: packName)
        return try archive.dataThrowing(named: "logo.png")
    }

    private func packArchive(named packName: String) throws -> ZipStore.Index {
        lock.lock()
        if let cached = packArchives[packName] {
            lock.unlock()
            return cached
        }
        let isUser = userPackNames.contains(packName)
        lock.unlock()
        let zip: Data
        if isUser || InstalledPacks.contains(packName) {
            zip = try InstalledPacks.read(InstalledPacks.file(sysName: packName), packName: packName)
        } else {
            zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        }
        let index = try ZipStore.indexThrowing(in: zip)
        lock.lock()
        if packsByName[packName] != nil, packArchives[packName] == nil {
            packArchives[packName] = index
        }
        let stored = packArchives[packName] ?? index
        lock.unlock()
        return stored
    }

    static func parsePack(zip: Data, packName: String) throws -> Pack {
        let meta = try PackMeta.parse(ZipStore.dataThrowing(named: "meta.txt", in: zip), source: "\(packName)/meta.txt")
        if meta.mSysName != packName {
            throw ZipError(message: "Manifest \(packName).atp meta.mSysName '\(meta.mSysName)' != '\(packName)'")
        }
        let translations = try PackTranslator.load(from: zip, packName: packName)
        let parsed = try ManifestXML.parse(
            ZipStore.dataThrowing(named: "manifest.xml", in: zip),
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

    /// Same structural checks as install. A throw here skips this pack and leaves the others loading.
    static func validateUserPack(zip: Data, packName: String) throws -> Pack {
        let index = try ZipStore.indexThrowing(in: zip)
        return try validateUserPack(index: index, zip: zip, packName: packName)
    }

    private static func validateUserPack(index: ZipStore.Index, zip: Data, packName: String) throws -> Pack {
        for required in ["meta.txt", "manifest.xml", "translate_en.xml", "logo.png"] {
            if !index.contains(required) {
                throw ZipError(message: "missing \(required)")
            }
        }
        let pack = try parsePack(zip: zip, packName: packName)
        let logo = try index.dataThrowing(named: "logo.png")
        _ = try PNGImage.loaded(from: logo, name: "\(packName)/logo.png")
        for item in pack.items {
            let ati = try index.dataAtiThrowing(file: "\(item.systemName).ati")
            let atiNames = try ZipStore.namesThrowing(in: ati)
            if !atiNames.contains("model.xml") {
                throw ZipError(message: "item '\(item.systemName)' has no model.xml")
            }
        }
        return pack
    }

    private func obtainBundlePack(_ url: URL) -> (Pack, ZipStore.Index) {
        let packName = url.deletingPathExtension().lastPathComponent
        let zip = ExternalPack.mappedZip(url)
        do {
            let index = try ZipStore.indexThrowing(in: zip)
            let pack = try Self.parsePack(zip: zip, packName: packName)
            return (pack, index)
        } catch {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest pack '\(packName)' is broken: \(error)")
        }
    }

    private func obtainUserPack(_ url: URL) throws -> (Pack, ZipStore.Index) {
        let packName = url.deletingPathExtension().lastPathComponent
        if !InstalledPacks.isPackSysName(packName) {
            throw ZipError(message: "mSysName '\(packName)' is not a pack name")
        }
        let zip = try InstalledPacks.read(url, packName: packName)
        let index = try ZipStore.indexThrowing(in: zip)
        let pack = try Self.validateUserPack(index: index, zip: zip, packName: packName)
        return (pack, index)
    }

    private func toastLoadFailures(_ names: [String]) {
        if names.isEmpty {
            return
        }
        let message = "Could not load \(names.joined(separator: ", "))"
        DispatchQueue.main.async {
            ToastCenter.show(message)
        }
    }

    /// Android `ReloadCustomPackTask` — `@` pack is the customs directory, not an `.atp`.
    private func obtainCustomPack() -> Pack {
        let files = CustomItems.collect()
        var items: [Item] = []
        for file in files {
            // The file can vanish between collect() and this read (delete racing
            // a reload). Skip it; the next collect will not list it at all.
            guard let zip = try? Data(contentsOf: file.url) else { continue }
            let fullName = Pack.customName + ":" + file.systemName
            items.append(
                Item(
                    systemName: file.systemName,
                    humanName: file.name,
                    packName: Pack.customName,
                    fullName: fullName,
                    setName: "",
                    scale: customScale(zip: zip),
                    faceable: false,
                    multiframed: customMultiframed(zip: zip),
                    hidden: false,
                    readOnly: false
                )
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
        let names: [String]
        let data: Data
        do {
            names = try ZipStore.namesThrowing(in: zip)
            if !names.contains("meta.txt") {
                return 1
            }
            data = try ZipStore.dataThrowing(named: "meta.txt", in: zip)
        } catch {
            if ZipStore.isArchive(zip) {
                let message = ItemLoadError.text(error)
                DispatchQueue.main.async {
                    ToastCenter.show(message)
                }
            }
            return 1
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["scale"] as? NSNumber
        else {
            return 1
        }
        let scale = CGFloat(truncating: number)
        return scale > 0.01 ? scale : 1
    }

    private func customMultiframed(zip: Data) -> Bool {
        guard let names = try? ZipStore.namesThrowing(in: zip), names.contains("meta.txt"),
              let data = try? ZipStore.dataThrowing(named: "meta.txt", in: zip),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        if let flag = object["multiframed"] as? Bool {
            return flag
        }
        if let number = object["multiframed"] as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private func onPacksReloaded(_ content: [String: Pack], archives: [String: ZipStore.Index], userPacks: Set<String>) {
        lock.lock()
        packsByName = content
        packArchives = archives
        userPackNames = userPacks
        itemsByFullName = [:]
        for pack in content.values {
            index(pack)
        }
        lock.unlock()
    }

    private func onPackUpdated(_ packName: String, _ pack: Pack, archive: ZipStore.Index?) {
        lock.lock()
        if let old = packsByName[packName] {
            for item in old.items {
                itemsByFullName.removeValue(forKey: item.makeFullName())
            }
        }
        packsByName[packName] = pack
        if let archive {
            packArchives[packName] = archive
        } else {
            packArchives.removeValue(forKey: packName)
        }
        index(pack)
        lock.unlock()
    }

    private func index(_ pack: Pack) {
        for item in pack.items {
            itemsByFullName[item.makeFullName()] = item
        }
    }

    /// Android `PacksAdapterPresenter` weights, highest first. Unlisted packs follow, by name.
    /// `christmas`, `irr.intro`, `stickman`, and `common` are hidden there and stay out of this list.
    private static let chooserRank = [
        "jungle",
        "zalivka.farm",
        "newstickman",
        "template.basic",
        "community.pack",
        "vk.gr1",
        "vk.gr2",
        "ayxan.alim",
        "farid.things",
        "puppet",
        "zalivka.vio",
        "zalivka.space1",
    ]
    private static let chooserHidden: Set<String> = ["irr.intro", "stickman", "christmas", "common", "assorted.bgs", "abstract.stuff"]

    private func packsMatching(_ query: Query) -> [Pack] {
        if query.isEmpty {
            return packs()
                .filter { $0.name == Pack.customName || !Self.chooserHidden.contains($0.name) }
                .sorted { chooserOrder($0.name) < chooserOrder($1.name) }
        }
        return query.requestedPacks.compactMap { pack(named: $0) }.sorted { $0.name < $1.name }
    }

    /// Custom items stand in for Android's `~custom_agg`, which is pinned to the top.
    private func chooserOrder(_ name: String) -> (Int, String) {
        if name == Pack.customName {
            return (0, name)
        }
        if let index = Self.chooserRank.firstIndex(of: name) {
            return (index + 1, name)
        }
        return (Self.chooserRank.count + 1, name)
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

}
