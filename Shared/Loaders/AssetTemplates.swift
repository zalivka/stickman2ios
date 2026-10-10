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

    static func list() throws -> [Item] {
        guard let pack = Manifest.shared.pack(named: packName) else {
            throw ZipError(message: "AssetTemplates missing pack '\(packName)'")
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
        // Reading the bundled pack: failure means the IPA shipped broken.
        let zip: Data
        let bundled: PackMeta
        let items: [(name: String, data: Data)]
        do {
            zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
            bundled = try PackMeta.parse(
                ZipStore.dataThrowing(named: "meta.txt", in: zip),
                source: "\(packName)/meta.txt"
            )
            guard bundled.mSysName == packName else {
                throw ZipError(message: "AssetTemplates meta.mSysName '\(bundled.mSysName)' != '\(packName)'")
            }
            items = try flatItems(in: zip)
        } catch {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("AssetTemplates '\(packName)' is broken: \(error)")
        }
        if installedVersion() == bundled.version, installedItemNames() == Set(items.map(\.name)) {
            return
        }
        // Installing into Application Support: disk IO can fail on a live device.
        // Templates stay uninstalled; `itemData` toasts on the next request.
        let fm = FileManager.default
        let dest = directory()
        let tmp = dest.appendingPathExtension("unpacking")
        do {
            if fm.fileExists(atPath: tmp.path) {
                try fm.removeItem(at: tmp)
            }
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            for item in items {
                try item.data.write(to: tmp.appendingPathComponent("\(item.name).atp"), options: .atomic)
            }
            try ZipStore.dataThrowing(named: "meta.txt", in: zip).write(
                to: tmp.appendingPathComponent("meta.txt"),
                options: .atomic
            )
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            print("AssetTemplates prepare: \(error)")
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
    static func revision() throws -> String {
        guard let pack = Manifest.shared.pack(named: packName) else {
            throw ZipError(message: "AssetTemplates missing pack '\(packName)'")
        }
        let url = ExternalPack.bundleArchive(packName)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        } catch {
            throw ZipError(message: "AssetTemplates could not stat \(url.path): \(error)")
        }
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            throw ZipError(message: "AssetTemplates \(url.lastPathComponent) has no size or modification date")
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
            // platform precondition: Application Support always resolves on a real device
            fatalError("AssetTemplates has no Application Support")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("templates", isDirectory: true)
    }

    private static func flatItems(in zip: Data) throws -> [(name: String, data: Data)] {
        var items: [(name: String, data: Data)] = []
        for entry in try ZipStore.namesThrowing(in: zip) {
            guard entry.hasPrefix("items/"), entry.hasSuffix(".ati"), !entry.hasSuffix("/") else { continue }
            let name = String(entry.dropFirst("items/".count).dropLast(".ati".count))
            if name.isEmpty || name.contains("/") || name.contains("..") {
                throw ZipError(message: "AssetTemplates refuses entry '\(entry)'")
            }
            items.append((name, try ZipStore.dataThrowing(named: entry, in: zip)))
        }
        if items.isEmpty {
            throw ZipError(message: "AssetTemplates \(packName) has no items/*.ati")
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
        guard let data = try? Data(contentsOf: url),
              let meta = try? PackMeta.parse(data, source: url.path)
        else {
            return 0
        }
        return meta.version
    }
}
