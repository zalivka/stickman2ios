import Foundation

enum SceneSaver {
    static let ext = "ats"

    private static let illegal = ["/", "\n", "\r", "\t", "\0", "\u{000C}", "`", "?", "*", "\\", "<", ">", "|", "\"", ":", "#"]

    static func savedDirectory() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("SceneSaver has no Application Support")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("saved", isDirectory: true)
    }

    static func generateName() -> String {
        let millis = Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))
        return String(format: "Cartoon_%d", millis % 1000)
    }

    static func isGoodFileName(_ name: String) -> Bool {
        if name.isEmpty {
            return false
        }
        for token in illegal where name.contains(token) {
            return false
        }
        return true
    }

    @MainActor
    static func save(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        name rawName: String
    ) throws -> String {
        if !isGoodFileName(rawName) {
            fatalError("SceneSaver illegal name '\(rawName)'")
        }
        let name = rawName.replacingOccurrences(of: " ", with: "_")
        if scene.frames.isEmpty {
            fatalError("SceneSaver scene has no frames")
        }
        let thumbs = SceneThumbRenderer.pair(scene: scene, assets: assets, backgrounds: backgrounds)
        var files: [(name: String, data: Data)] = [
            (name: "model.xml", data: SceneXML.serialize(scene)),
            (name: "thumb.png", data: thumbs.small),
            (name: "thumb_big.png", data: thumbs.big),
            (name: "metadata.txt", data: metadata(name: name))
        ]
        var seenItems = Set<String>()
        for frame in scene.frames {
            for unit in frame.units {
                let key = UnitAssets.removeNumber(unit.name)
                if seenItems.contains(key) {
                    continue
                }
                seenItems.insert(key)
                let stored = assets.archive(for: key)
                files.append((name: stored.entryName, data: stored.zip))
            }
        }
        if seenItems.isEmpty {
            fatalError("SceneSaver scene has no units")
        }
        var seenBgs = Set<String>()
        for frame in scene.frames {
            guard let bgName = frame.bgName, bgName.hasPrefix("usermade:") else {
                continue
            }
            if seenBgs.contains(bgName) {
                continue
            }
            seenBgs.insert(bgName)
            let own = SceneLoader.ownName(bgName)
            files.append((name: "_bgs/\(own).zip", data: backgrounds.archive(for: bgName)))
        }
        if !scene.unitAnimations.isEmpty {
            files.append((name: "animations_v2.txt", data: encodeAnimations(scene.unitAnimations)))
        }
        for font in StickmanFonts.customFontsUsed(in: scene) {
            files.append((name: "fonts/\(font.file)", data: font.data))
        }
        let zip = ZipStore.archive(files)
        let dir = try ensureSavedDirectory()
        let url = dir.appendingPathComponent("\(name).\(Self.ext)")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try zip.write(to: url, options: .atomic)
        return name
    }

    /// Saved document without thumbs/metadata — used to detect unsaved edits.
    static func documentBytes(scene: StickmanScene) -> Data {
        var bytes = SceneXML.serialize(scene)
        let animations = scene.unitAnimations.values.sorted { $0.unitname < $1.unitname }
        if !animations.isEmpty {
            do {
                bytes.append(try JSONEncoder().encode(animations))
            } catch {
                fatalError("SceneSaver documentBytes animations JSON: \(error)")
            }
        }
        return bytes
    }

    static func incomingName(from zip: Data) -> String {
        if ZipStore.contains("metadata.txt", in: zip) {
            let data = ZipStore.data(named: "metadata.txt", in: zip)
            if let meta = try? JSONDecoder().decode(SceneMetadataFile.self, from: data) {
                let name = meta.mName.replacingOccurrences(of: " ", with: "_")
                if !name.isEmpty {
                    return name
                }
            }
        }
        return "\(Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)))"
    }

    private static func ensureSavedDirectory() throws -> URL {
        let dir = savedDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func metadata(name: String) -> Data {
        guard let appName = Bundle.main.bundleIdentifier, !appName.isEmpty else {
            fatalError("SceneSaver missing bundle identifier")
        }
        guard let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !appVersion.isEmpty
        else {
            fatalError("SceneSaver missing CFBundleShortVersionString")
        }
        let payload = SceneMetadataFile(
            mAuthor: "<no author>",
            mName: name,
            mCreatedAt: Int64((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)),
            mAppName: appName,
            mAppVersion: appVersion,
            mContentVersion: 0,
            audioFormat: 1,
            speechUsed: false
        )
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            fatalError("SceneSaver metadata JSON: \(error)")
        }
    }

    private static func encodeAnimations(_ animations: [String: FBFAnimation]) -> Data {
        let list = Array(animations.values)
        do {
            return try JSONEncoder().encode(list)
        } catch {
            fatalError("SceneSaver animations_v2.txt JSON: \(error)")
        }
    }
}

private struct SceneMetadataFile: Codable {
    var mAuthor: String
    var mName: String
    var mCreatedAt: Int64
    var mAppName: String
    var mAppVersion: String
    var mContentVersion: Int
    var audioFormat: Int
    var speechUsed: Bool
}
