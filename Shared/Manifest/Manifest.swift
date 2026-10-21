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
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            print("manifest: obtaining \(name)")
            let start = ProcessInfo.processInfo.systemUptime
            loaded[name] = obtainBundlePack(url)
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
                loaded[name] = try obtainUserPack(url)
                userPacks.insert(name)
            } catch {
                print("manifest: skipping user pack \(name): \(error)")
                failed.append(name)
            }
        }
        loaded[Pack.customName] = obtainCustomPack()
        onPacksReloaded(loaded, userPacks: userPacks)
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
                let pack = try obtainUserPack(InstalledPacks.file(sysName: name))
                lock.lock()
                userPackNames.insert(name)
                lock.unlock()
                onPackUpdated(name, pack)
                print("manifest: updated \(name) \"\(pack.title)\" items=\(pack.items.count)")
            } catch {
                print("manifest: skipping user pack \(name): \(error)")
                toastLoadFailures([name])
            }
            return packs().count
        }
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
        if isUserPack(item.packName) || InstalledPacks.contains(item.packName) {
            let zip = try InstalledPacks.read(InstalledPacks.file(sysName: item.packName), packName: item.packName)
            return try ZipStore.dataAtiThrowing(file: "\(item.systemName).ati", in: zip)
        }
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(item.packName))
        return try ZipStore.dataAtiThrowing(file: "\(item.systemName).ati", in: zip)
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
        if isUserPack(packName) || InstalledPacks.contains(packName) {
            let zip = try InstalledPacks.read(InstalledPacks.file(sysName: packName), packName: packName)
            return try ZipStore.dataThrowing(named: "logo.png", in: zip)
        }
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        return try ZipStore.dataThrowing(named: "logo.png", in: zip)
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
        let names = try ZipStore.namesThrowing(in: zip)
        for required in ["meta.txt", "manifest.xml", "translate_en.xml", "logo.png"] {
            if !names.contains(required) {
                throw ZipError(message: "missing \(required)")
            }
        }
        let pack = try parsePack(zip: zip, packName: packName)
        let logo = try ZipStore.dataThrowing(named: "logo.png", in: zip)
        _ = try PNGImage.loaded(from: logo, name: "\(packName)/logo.png")
        for item in pack.items {
            let ati = try ZipStore.dataAtiThrowing(file: "\(item.systemName).ati", in: zip)
            let atiNames = try ZipStore.namesThrowing(in: ati)
            if !atiNames.contains("model.xml") {
                throw ZipError(message: "item '\(item.systemName)' has no model.xml")
            }
        }
        return pack
    }

    private func obtainBundlePack(_ url: URL) -> Pack {
        let packName = url.deletingPathExtension().lastPathComponent
        let zip = ExternalPack.mappedZip(url)
        do {
            return try Self.parsePack(zip: zip, packName: packName)
        } catch {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest pack '\(packName)' is broken: \(error)")
        }
    }

    private func obtainUserPack(_ url: URL) throws -> Pack {
        let packName = url.deletingPathExtension().lastPathComponent
        if !InstalledPacks.isPackSysName(packName) {
            throw ZipError(message: "mSysName '\(packName)' is not a pack name")
        }
        let zip = try InstalledPacks.read(url, packName: packName)
        return try Self.validateUserPack(zip: zip, packName: packName)
    }

    private func isUserPack(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return userPackNames.contains(name)
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

    private func onPacksReloaded(_ content: [String: Pack], userPacks: Set<String>) {
        lock.lock()
        packsByName = content
        userPackNames = userPacks
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
