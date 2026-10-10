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
            throw SceneLoadError(message: "ItemSaver illegal name '\(rawName)'")
        }
        let name = rawName.replacingOccurrences(of: " ", with: "_")
        let fullName = "\(pack):\(name)"

        var files: [(name: String, data: Data)] = [
            (name: "model.xml", data: try ModelXML.serialize(unit, fullName: fullName))
        ]

        let rows = assets.exportRows(unitName: unit.name)
        let livePngs = try assets.pngFiles(unitName: unit.name)
        let liveNames = Set(livePngs.map(\.name))
        if !rows.isEmpty {
            if livePngs.isEmpty {
                throw SceneLoadError(message: "ItemSaver '\(fullName)' has asset rows but no live PNGs")
            }
            for row in rows where !liveNames.contains(row.bmName) {
                throw SceneLoadError(message: "ItemSaver '\(fullName)' edge \(row.start)-\(row.end) bm '\(row.bmName)' has no live PNG")
            }
            files.append((name: "assets.xml", data: try AssetsXML.serialize(rows: rows, fullName: fullName)))
            files.append(contentsOf: livePngs)
            files.append(
                contentsOf: try assets.sidecarFiles(
                    unitName: unit.name,
                    pngs: Dictionary(uniqueKeysWithValues: livePngs.map { ($0.name, $0.data) })
                )
            )
        } else if let source, try ZipStore.namesThrowing(in: source).contains("assets.xml") {
            throw SceneLoadError(message: "ItemSaver '\(fullName)' live assets empty but source has assets.xml")
        }

        if let source {
            for entry in try ZipStore.namesThrowing(in: source) where !regenerated.contains(entry) {
                if liveNames.contains(entry) {
                    continue
                }
                // Sidecars are written from live buffers above; stale ones never carry forward.
                if entry.hasSuffix(".x2.png") || entry == UnitAssets.sidecarManifest {
                    continue
                }
                if entry.hasSuffix(".name") || entry.hasSuffix("/") {
                    continue
                }
                files.append((name: entry, data: try ZipStore.dataThrowing(named: entry, in: source)))
            }
        }
        files.append((name: "\(name).name", data: Data()))
        files.append((name: "meta.txt", data: try meta(name: name, scale: unit.scale)))
        files.append((name: "thumb.png", data: thumb))
        files.append((name: "poster.png", data: poster))

        let zip = try ZipStore.archive(files)
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

    private static func meta(name: String, scale: CGFloat) throws -> Data {
        // Android reads meta.txt appVersion as an int.
        guard let appVersion = Int(XMLWrite.versionCode()) else {
            // Info.plist: a failure here ships broken, fires on first debug run
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
            throw SceneLoadError(message: "ItemSaver meta.txt JSON: \(error)")
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
