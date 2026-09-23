import Foundation

enum ItemSaver {
    static let pack = "@"

    /// Entries regenerated from the edited unit. Everything else is copied from the source archive.
    /// `thumb.png` and `poster.png` are redrawn; copying them kept the picture from before the edit.
    private static let regenerated: Set<String> = [
        "model.xml", "assets.xml", "meta.txt", "thumb.png", "poster.png"
    ]

    static func generateName() -> String {
        let millis = Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))
        return String(format: "Item_%d", millis % 1000)
    }

    static func save(
        unit: StickmanUnit,
        assets: UnitAssets,
        source: Data?,
        name rawName: String,
        thumb: Data,
        poster: Data
    ) throws -> URL {
        if !SceneSaver.isGoodFileName(rawName) {
            fatalError("ItemSaver illegal name '\(rawName)'")
        }
        let name = rawName.replacingOccurrences(of: " ", with: "_")
        let fullName = "\(pack):\(name)"

        var files: [(name: String, data: Data)] = [
            (name: "model.xml", data: ModelXML.serialize(unit, fullName: fullName))
        ]

        let rows = assets.exportRows(unitName: unit.name)
        let livePngs = assets.pngFiles(unitName: unit.name)
        let liveNames = Set(livePngs.map(\.name))
        if !rows.isEmpty {
            if livePngs.isEmpty {
                fatalError("ItemSaver '\(fullName)' has asset rows but no live PNGs")
            }
            for row in rows where !liveNames.contains(row.bmName) {
                fatalError("ItemSaver '\(fullName)' edge \(row.start)-\(row.end) bm '\(row.bmName)' has no live PNG")
            }
            files.append((name: "assets.xml", data: AssetsXML.serialize(rows: rows, fullName: fullName)))
            files.append(contentsOf: livePngs)
        } else if let source, ZipStore.contains("assets.xml", in: source) {
            fatalError("ItemSaver '\(fullName)' live assets empty but source has assets.xml")
        }

        if let source {
            for entry in ZipStore.names(in: source) where !regenerated.contains(entry) {
                if liveNames.contains(entry) {
                    continue
                }
                if entry.hasSuffix(".name") || entry.hasSuffix("/") {
                    continue
                }
                files.append((name: entry, data: ZipStore.data(named: entry, in: source)))
            }
        }
        files.append((name: "\(name).name", data: Data()))
        files.append((name: "meta.txt", data: meta(name: name, scale: unit.scale)))
        files.append((name: "thumb.png", data: thumb))
        files.append((name: "poster.png", data: poster))

        let zip = ZipStore.archive(files)
        let fm = FileManager.default
        let dir = CustomItems.directory()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).\(CustomItems.ext)")
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try zip.write(to: url, options: .atomic)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
        }
        return url
    }

    /// A name not taken in the customs directory, so a save never silently replaces another item.
    static func freeName() -> String {
        let fm = FileManager.default
        let dir = CustomItems.directory()
        let base = generateName()
        var candidate = base
        var suffix = 1
        while fm.fileExists(atPath: dir.appendingPathComponent("\(candidate).\(CustomItems.ext)").path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func meta(name: String, scale: CGFloat) -> Data {
        // Android reads meta.txt appVersion as an int.
        guard let appVersion = Int(XMLWrite.versionCode()) else {
            fatalError("ItemSaver CFBundleVersion '\(XMLWrite.versionCode())' is not an integer")
        }
        let payload = ItemMetaFile(
            pack: pack,
            name: name,
            author: "",
            appVersion: appVersion,
            scale: Double(scale)
        )
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            fatalError("ItemSaver meta.txt JSON: \(error)")
        }
    }
}

private struct ItemMetaFile: Codable {
    var pack: String
    var name: String
    var author: String
    var appVersion: Int
    var scale: Double
}
