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

    /// A different `meta.txt` version replaces `templates/<name>.atp` and `meta.txt`.
    /// Same version keeps those files. The bytes are the pack's `items/<name>.ati`.
    static func prepare() {
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        let bundled = PackMeta.parse(ZipStore.data(named: "meta.txt", in: zip), source: "\(packName)/meta.txt")
        if bundled.mSysName != packName {
            fatalError("AssetTemplates meta.mSysName '\(bundled.mSysName)' != '\(packName)'")
        }
        let items = flatItems(in: zip)
        if installedVersion() == bundled.version, installedItemNames() == Set(items.map(\.name)) {
            return
        }
        let fm = FileManager.default
        let dest = directory()
        let tmp = dest.appendingPathExtension("unpacking")
        if fm.fileExists(atPath: tmp.path) {
            do {
                try fm.removeItem(at: tmp)
            } catch {
                fatalError("AssetTemplates could not replace \(tmp.path): \(error)")
            }
        }
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            fatalError("AssetTemplates could not create \(tmp.path): \(error)")
        }
        for item in items {
            let url = tmp.appendingPathComponent("\(item.name).atp")
            do {
                try item.data.write(to: url, options: .atomic)
            } catch {
                fatalError("AssetTemplates could not write \(url.path): \(error)")
            }
        }
        let metaURL = tmp.appendingPathComponent("meta.txt")
        do {
            try ZipStore.data(named: "meta.txt", in: zip).write(to: metaURL, options: .atomic)
        } catch {
            fatalError("AssetTemplates could not write \(metaURL.path): \(error)")
        }
        if fm.fileExists(atPath: dest.path) {
            do {
                try fm.removeItem(at: dest)
            } catch {
                fatalError("AssetTemplates could not replace \(dest.path): \(error)")
            }
        }
        do {
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            fatalError("AssetTemplates could not move \(tmp.path) to \(dest.path): \(error)")
        }
    }

    static func itemData(_ systemName: String) throws -> Data {
        let url = directory().appendingPathComponent("\(systemName).atp")
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ItemLoadError("AssetTemplates '\(systemName)' \(url.path): \(error)")
        }
    }

    /// Kingfisher keeps posters across launches. The key follows the pack that `prepare` installed.
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
            .appendingPathComponent("templates", isDirectory: true)
    }

    private static func flatItems(in zip: Data) -> [(name: String, data: Data)] {
        var items: [(name: String, data: Data)] = []
        for entry in ZipStore.names(in: zip) {
            guard entry.hasPrefix("items/"), entry.hasSuffix(".ati"), !entry.hasSuffix("/") else { continue }
            let name = String(entry.dropFirst("items/".count).dropLast(".ati".count))
            if name.isEmpty || name.contains("/") || name.contains("..") {
                fatalError("AssetTemplates refuses entry '\(entry)'")
            }
            items.append((name, ZipStore.data(named: entry, in: zip)))
        }
        if items.isEmpty {
            fatalError("AssetTemplates \(packName) has no items/*.ati")
        }
        return items
    }

    private static func installedItemNames() -> Set<String> {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(urls.filter { $0.pathExtension == "atp" }.map { $0.deletingPathExtension().lastPathComponent })
    }

    private static func installedVersion() -> Int {
        let url = directory().appendingPathComponent("meta.txt")
        guard let data = try? Data(contentsOf: url) else {
            return 0
        }
        return PackMeta.parse(data, source: url.path).version
    }
}
