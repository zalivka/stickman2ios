import Foundation

enum AssetTemplates {
    static let packName = "template.basic"

    private static let order = [
        "sword",
        "man2",
        "shark",
        "trex",
        "gun",
        "man1",
        "dog",
        "catapult",
    ]

    static func list() -> [Item] {
        guard let pack = Manifest.shared.pack(named: packName) else {
            fatalError("AssetTemplates missing pack '\(packName)'")
        }
        var byName: [String: Item] = [:]
        for item in pack.items {
            byName[item.systemName] = item
        }
        var templates: [Item] = []
        for name in order {
            if let item = byName[name] {
                templates.append(item)
            }
        }
        let extras = pack.items
            .filter { !order.contains($0.systemName) }
            .sorted { $0.systemName < $1.systemName }
        templates.append(contentsOf: extras)
        return templates
    }

    /// Android `ExternalPack.unpackEmbedded`: a different `meta.txt` version deletes the
    /// unpacked tree and writes the bundle archive over it. Same version keeps the files.
    static func sync() {
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        let bundled = PackMeta.parse(ZipStore.data(named: "meta.txt", in: zip), source: "\(packName)/meta.txt")
        if bundled.mSysName != packName {
            fatalError("AssetTemplates meta.mSysName '\(bundled.mSysName)' != '\(packName)'")
        }
        if installedVersion() == bundled.version, FileManager.default.fileExists(atPath: itemsDirectory().path) {
            return
        }
        let parent = directory().deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            fatalError("AssetTemplates could not create \(parent.path): \(error)")
        }
        ZipStore.unpack(zip, to: directory())
    }

    static func itemData(_ systemName: String) throws -> Data {
        let url = itemsDirectory().appendingPathComponent("\(systemName).ati")
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ItemLoadError("AssetTemplates '\(systemName)' \(url.path): \(error)")
        }
    }

    /// Kingfisher keeps posters across launches. The key follows the pack that `sync` installed.
    static func revision() -> String {
        guard let pack = Manifest.shared.pack(named: packName) else {
            fatalError("AssetTemplates missing pack '\(packName)'")
        }
        let url = ExternalPack.bundleArchive(packName)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        } catch {
            fatalError("AssetTemplates could not stat \(url.path): \(error)")
        }
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            fatalError("AssetTemplates \(url.lastPathComponent) has no size or modification date")
        }
        return "\(pack.version)|\(size)|\(Int(modified.timeIntervalSince1970))"
    }

    static func poster(fullname: String) throws -> Data {
        let zip = try Manifest.shared.itemZip(fullname: fullname)
        let names = try ZipStore.namesThrowing(in: zip)
        if names.contains("poster.png") {
            return try ZipStore.dataThrowing(named: "poster.png", in: zip)
        }
        if names.contains("thumb.png") {
            return try ZipStore.dataThrowing(named: "thumb.png", in: zip)
        }
        throw ItemLoadError("AssetTemplates '\(fullname)' missing poster.png and thumb.png")
    }

    private static func directory() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("AssetTemplates has no Application Support")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent(packName, isDirectory: true)
    }

    private static func itemsDirectory() -> URL {
        directory().appendingPathComponent("items", isDirectory: true)
    }

    private static func installedVersion() -> Int {
        let url = directory().appendingPathComponent("meta.txt")
        guard let data = try? Data(contentsOf: url) else {
            return 0
        }
        return PackMeta.parse(data, source: url.path).version
    }
}
