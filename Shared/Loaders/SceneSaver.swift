import Foundation

enum SceneSaver {
    static let ext = "ats"

    nonisolated private static let illegal = ["/", "\n", "\r", "\t", "\0", "\u{000C}", "`", "?", "*", "\\", "<", ">", "|", "\"", ":", "#"]

    static func savedDirectory() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // platform precondition: Application Support always resolves on a real device
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

    nonisolated static func isGoodFileName(_ name: String) -> Bool {
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
            throw SceneLoadError(message: "SceneSaver illegal name '\(rawName)'")
        }
        let name = rawName.replacingOccurrences(of: " ", with: "_")
        if scene.frames.isEmpty {
            throw SceneLoadError(message: "SceneSaver scene has no frames")
        }
        let thumbs = try SceneThumbRenderer.pair(scene: scene, assets: assets, backgrounds: backgrounds)
        var files: [(name: String, data: Data)] = [
            (name: "model.xml", data: try SceneXML.serialize(scene)),
            (name: "thumb.png", data: thumbs.small),
            (name: "thumb_big.png", data: thumbs.big),
            (name: "metadata.txt", data: try metadata(name: name, scene: scene))
        ]
        var seenItems = Set<String>()
        for frame in scene.frames {
            for unit in frame.units {
                let key = UnitAssets.removeNumber(unit.name)
                if seenItems.contains(key) {
                    continue
                }
                seenItems.insert(key)
                // A unit whose archive never loaded cannot be embedded; the scene still saves.
                guard let stored = assets.archive(for: key) else {
                    print("SceneSaver skipping unit '\(key)': no archive")
                    continue
                }
                files.append((name: stored.entryName, data: stored.zip))
            }
        }
        if seenItems.isEmpty {
            throw SceneLoadError(message: "SceneSaver scene has no units")
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
            // A background that never installed is skipped; frames referencing it draw the fill.
            if let archive = backgrounds.archive(for: bgName) {
                files.append((name: "_bgs/\(own).zip", data: archive))
            }
        }
        if !scene.unitAnimations.isEmpty {
            files.append((name: "animations_v2.txt", data: try encodeAnimations(scene.unitAnimations)))
        }
        if !scene.unitTweens.isEmpty {
            files.append((name: UnitTweenStorage.archiveName, data: try scene.unitTweens.encodeArchive(scene: scene)))
        }
        if !scene.cameraTweens.isEmpty {
            files.append((name: CameraTweenStorage.archiveName, data: try scene.cameraTweens.encodeArchive(scene: scene)))
        }
        files.append(contentsOf: try SceneAudioArchive.files(scene: scene))
        for font in StickmanFonts.customFontsUsed(in: scene) {
            files.append((name: "fonts/\(font.file)", data: font.data))
        }
        let zip = try ZipStore.archive(files)
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
    /// Nil when serialization fails: callers treat nil as dirty, so the user gets
    /// prompted to save instead of losing edits to a silent comparison miss.
    static func documentBytes(scene: StickmanScene) -> Data? {
        guard var bytes = try? SceneXML.serialize(scene) else {
            return nil
        }
        let animations = scene.unitAnimations.values.sorted { $0.unitname < $1.unitname }
        if !animations.isEmpty {
            do {
                bytes.append(try JSONEncoder().encode(animations))
            } catch {
                return nil
            }
        }
        if !scene.unitTweens.isEmpty {
            guard let archive = try? scene.unitTweens.encodeArchive(scene: scene) else {
                return nil
            }
            bytes.append(archive)
        }
        if !scene.cameraTweens.isEmpty {
            guard let archive = try? scene.cameraTweens.encodeArchive(scene: scene) else {
                return nil
            }
            bytes.append(archive)
        }
        if !scene.audio.isEmpty {
            guard let files = try? SceneAudioArchive.files(scene: scene) else {
                return nil
            }
            for file in files {
                bytes.append(file.data)
            }
        }
        return bytes
    }

    static func incomingName(from zip: Data) -> String {
        // A garbage archive simply has no readable metadata; fall back to the timestamp name.
        if let data = try? ZipStore.dataThrowing(named: "metadata.txt", in: zip),
           let meta = try? JSONDecoder().decode(SceneMetadataFile.self, from: data) {
            let name = meta.mName.replacingOccurrences(of: " ", with: "_")
            if !name.isEmpty {
                return name
            }
        }
        return "\(Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)))"
    }

    private static func ensureSavedDirectory() throws -> URL {
        let dir = savedDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func metadata(name: String, scene: StickmanScene) throws -> Data {
        guard let appName = Bundle.main.bundleIdentifier, !appName.isEmpty else {
            // Info.plist: a failure here ships broken, fires on first debug run
            fatalError("SceneSaver missing bundle identifier")
        }
        guard let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !appVersion.isEmpty
        else {
            // Info.plist: a failure here ships broken, fires on first debug run
            fatalError("SceneSaver missing CFBundleShortVersionString")
        }
        let payload = SceneMetadataFile(
            mAuthor: "<no author>",
            mName: name,
            mCreatedAt: Int64((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)),
            mAppName: appName,
            mAppVersion: appVersion,
            mContentVersion: 0,
            // Android `SceneMetadata.audioFormat`: 1 = multiple audio bites,
            // which is what `audio_v1/` always writes.
            audioFormat: 1,
            speechUsed: scene.audio.hasSpeech
        )
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            throw SceneLoadError(message: "SceneSaver metadata JSON: \(error)")
        }
    }

    private static func encodeAnimations(_ animations: [String: FBFAnimation]) throws -> Data {
        let list = Array(animations.values)
        do {
            return try JSONEncoder().encode(list)
        } catch {
            throw SceneLoadError(message: "SceneSaver animations_v2.txt JSON: \(error)")
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
