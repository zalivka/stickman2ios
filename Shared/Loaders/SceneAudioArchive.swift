import Foundation

/// `audio_v1/` archive entries produced and consumed by Android `AudioHelper`.
/// Speech entries (`dialogue.json`, `viseme_v1/`) are carried through byte for
/// byte so a scene opened here and saved back does not lose its speech.
enum SceneAudioArchive {
    static let prefix = "audio_v1/"
    static let visemePrefix = "viseme_v1/"
    static let paletteEntry = "audio_v1/palette.json"
    static let clipsEntry = "audio_v1/clips.json"
    static let dialogueEntry = "audio_v1/dialogue.json"

    /// Android `AudioUtils.SUPPORTED_FORMATS`, minus `.uaudio` (its own thing).
    static let supportedExtensions: Set<String> = [".wav", ".mp3", ".ogg", ".m4a"]

    // MARK: - Read

    static func load(zip: Data, names: [String], sceneKey: String) throws -> SceneAudio {
        if names.contains(where: { $0.hasPrefix(prefix) }) {
            return try loadV1(zip: zip, names: names, sceneKey: sceneKey)
        }
        return try loadLegacy(zip: zip, names: names, sceneKey: sceneKey)
    }

    private struct PaletteFile: Decodable {
        var key: String
        var filename: String
        var durationMs: Int64
    }

    private struct ClipFile: Decodable {
        var key: String
        var frameIndex: Int
        var filename: String
        var durationMs: Int64
        /// Absent in older archives: allocated on load.
        var colorIndex: Int?
        /// Absent in older archives: full volume.
        var volume: Float?
    }

    /// Android `AudioHelper.SpeechCacheEntry`: the speech audio itself lives in
    /// `audio_v1/<filename>` and its lipsync in `viseme_v1/<viseme>`.
    private struct SpeechFile: Decodable {
        var key: String
        var filename: String
        var viseme: String?
    }

    private static func loadV1(zip: Data, names: [String], sceneKey: String) throws -> SceneAudio {
        var audio = SceneAudio()

        // Speech is opaque to iOS: carry every byte to the next save. Android
        // keeps the wavs under `audio_v1/` and only the lipsync has its own prefix.
        var carried = Set<String>()
        for name in names where name.hasPrefix(visemePrefix) {
            carried.insert(name)
            audio.passThrough.append(
                SceneAudioPassThrough(name: name, data: try ZipStore.dataThrowing(named: name, in: zip))
            )
        }
        // Android `StageAudio.mSpeechByDefault` is whatever `speechUsed` said last
        // save. Derive it from the speech itself so an empty `dialogue.json`
        // (a sidecar worth preserving, but nothing to say) does not claim speech.
        var hasSpeech = !carried.isEmpty
        if names.contains(dialogueEntry) {
            let dialogue = try ZipStore.dataThrowing(named: dialogueEntry, in: zip)
            audio.passThrough.append(SceneAudioPassThrough(name: dialogueEntry, data: dialogue))
            let speech: [SpeechFile]
            do {
                speech = try JSONDecoder().decode([SpeechFile].self, from: dialogue)
            } catch {
                throw SceneLoadError(message: "Scene \(dialogueEntry) is not speech JSON: \(error)")
            }
            hasSpeech = hasSpeech || !speech.isEmpty
            for item in speech {
                if item.filename.isEmpty {
                    throw SceneLoadError(message: "Scene \(dialogueEntry) entry has empty filename")
                }
                let entry = prefix + item.filename
                guard names.contains(entry) else {
                    throw SceneLoadError(message: "Scene speech audio '\(item.filename)' is missing")
                }
                if carried.insert(entry).inserted {
                    audio.passThrough.append(
                        SceneAudioPassThrough(name: entry, data: try ZipStore.dataThrowing(named: entry, in: zip))
                    )
                }
            }
        }

        audio.hasSpeech = hasSpeech

        let hasPalette = names.contains(paletteEntry)
        let hasClips = names.contains(clipsEntry)
        if !hasPalette && !hasClips {
            return audio
        }

        // Extract each referenced file once; two entries with the same filename
        // share bytes, exactly like Android's `unpackedFiles` map.
        var unpacked: [String: URL] = [:]
        func fileURL(_ filename: String) throws -> URL {
            if let cached = unpacked[filename] {
                return cached
            }
            let entry = prefix + filename
            guard names.contains(entry) else {
                throw SceneLoadError(message: "Scene audio_v1 entry '\(filename)' is missing")
            }
            let url = try SceneAudioStorage.extract(
                data: try ZipStore.dataThrowing(named: entry, in: zip),
                filename: filename,
                sceneKey: sceneKey
            )
            guard supportedExtensions.contains(extensionOf(filename)) else {
                throw SceneLoadError(message: "Scene audio_v1 '\(filename)' has unsupported format")
            }
            unpacked[filename] = url
            return url
        }

        if hasPalette {
            let palette: [PaletteFile] = try decode(
                ZipStore.dataThrowing(named: paletteEntry, in: zip),
                what: paletteEntry
            )
            for item in palette {
                if item.key.isEmpty {
                    throw SceneLoadError(message: "Scene audio_v1 palette entry has empty key")
                }
                if item.durationMs <= 0 {
                    throw SceneLoadError(
                        message: "Scene audio_v1 palette '\(item.key)' duration \(item.durationMs)"
                    )
                }
                if item.filename.isEmpty {
                    throw SceneLoadError(message: "Scene audio_v1 palette '\(item.key)' has empty filename")
                }
                audio.addPalette(
                    audioId: item.key,
                    durationMs: item.durationMs,
                    url: try fileURL(item.filename)
                )
            }
        }

        if hasClips {
            let clips: [ClipFile] = try decode(
                ZipStore.dataThrowing(named: clipsEntry, in: zip),
                what: clipsEntry
            )
            for item in clips {
                guard audio.contains(item.key) else {
                    throw SceneLoadError(
                        message: "Scene audio_v1 clip '\(item.key)' has no palette entry"
                    )
                }
                if item.durationMs <= 0 {
                    throw SceneLoadError(
                        message: "Scene audio_v1 clip '\(item.key)' duration \(item.durationMs)"
                    )
                }
                // Placement validity needs the frame count, which only the scene
                // knows; SceneLoader calls `validate(scene:)` right after parse.
                audio.clips.append(
                    SceneAudioClip(
                        audioId: item.key,
                        frameIndex: item.frameIndex,
                        durationMs: item.durationMs,
                        colorIndex: item.colorIndex ?? -1,
                        volume: item.volume ?? SceneAudioClip.defaultVolume
                    )
                )
                // `filename` is informational; the palette already resolved the sound.
                _ = try fileURL(item.filename)
            }
        }

        return audio
    }

    /// Android `readPlainAudio`: old scenes embed one audio file with no
    /// `audio_v1/` prefix. It plays from frame 0 for its full length.
    private static func loadLegacy(zip: Data, names: [String], sceneKey: String) throws -> SceneAudio {
        let candidates = names
            .filter { !$0.hasSuffix("/") }
            .filter { supportedExtensions.contains(extensionOf($0)) }
            .sorted()
        guard let filename = candidates.first else {
            return SceneAudio()
        }
        let url = try SceneAudioStorage.extract(
            data: try ZipStore.dataThrowing(named: filename, in: zip),
            filename: (filename as NSString).lastPathComponent,
            sceneKey: sceneKey
        )
        let duration = try AudioFiles.durationMs(url: url)
        let audioId = (filename as NSString).lastPathComponent
            .split(separator: ".")
            .dropLast()
            .joined(separator: ".")
        guard !audioId.isEmpty else {
            throw SceneLoadError(message: "Scene audio legacy '\(filename)' has no name")
        }
        var audio = SceneAudio()
        audio.addPalette(audioId: audioId, durationMs: duration, url: url)
        audio.clips.append(
            SceneAudioClip(audioId: audioId, frameIndex: 0, durationMs: duration, colorIndex: 0)
        )
        return audio
    }

    /// Frame-count and color checks that need the parsed scene. Called by
    /// `SceneLoader` once `StickmanScene` exists.
    static func validate(scene: inout StickmanScene) throws {
        guard !scene.audio.clips.isEmpty else {
            return
        }
        for index in scene.audio.clips.indices {
            let clip = scene.audio.clips[index]
            if clip.frameIndex < 0 || clip.frameIndex >= scene.frames.count {
                throw SceneLoadError(
                    message: "Scene audio clip '\(clip.audioId)' frame \(clip.frameIndex) out of \(scene.frames.count)"
                )
            }
            if clip.durationMs <= 0 {
                throw SceneLoadError(
                    message: "Scene audio clip '\(clip.audioId)' duration \(clip.durationMs)"
                )
            }
            if clip.colorIndex < 0 || clip.colorIndex >= SceneAudio.colorCount {
                // Old archives wrote -1; give them a real palette slot.
                scene.audio.clips[index].colorIndex = scene.audio.allocateColorIndex()
            }
            let atFrame = scene.audio.clipsAt(frameIndex: clip.frameIndex)
            if atFrame.count > SceneAudio.maxClipsPerFrame {
                throw SceneLoadError(
                    message: "Scene audio has \(atFrame.count) clips at frame \(clip.frameIndex)"
                )
            }
        }
    }

    // MARK: - Write

    private struct PaletteOut: Encodable {
        var key: String
        var filename: String
        var durationMs: Int64
    }

    private struct ClipOut: Encodable {
        var key: String
        var frameIndex: Int
        var filename: String
        var durationMs: Int64
        var colorIndex: Int
        var volume: Float
    }

    /// Entries for `SceneSaver`, matching Android's `storeAudio_v1`.
    static func files(scene: StickmanScene) throws -> [(name: String, data: Data)] {
        let audio = scene.audio
        if audio.palette.isEmpty && audio.clips.isEmpty {
            return audio.passThrough.map { (name: $0.name, data: $0.data) }
        }

        var filenames: [String: String] = [:]
        var seen = Set<String>()
        var files: [(name: String, data: Data)] = []

        for entry in audio.palette {
            guard entry.audioId.isEmpty == false else {
                throw SceneLoadError(message: "Scene audio palette entry has empty id")
            }
            guard entry.durationMs > 0 else {
                throw SceneLoadError(message: "Scene audio palette '\(entry.audioId)' duration \(entry.durationMs)")
            }
            let ext = extensionOf(entry.url.lastPathComponent)
            guard supportedExtensions.contains(ext) else {
                throw SceneLoadError(
                    message: "Scene audio palette '\(entry.audioId)' unsupported format '\(ext)'"
                )
            }
            // Android `GeneralAudioRepository.ensureOwnedClipFile`: `clip_<id>`
            // with every non-alphanumeric id character mapped to `_`.
            let filename = "clip_\(safeStem(entry.audioId))\(ext)"
            if !seen.insert(filename).inserted {
                throw SceneLoadError(message: "Scene audio duplicate file name '\(filename)'")
            }
            guard FileManager.default.fileExists(atPath: entry.url.path) else {
                throw SceneLoadError(message: "Scene audio file missing: \(entry.url.path)")
            }
            do {
                files.append((name: prefix + filename, data: try Data(contentsOf: entry.url)))
            } catch {
                throw SceneLoadError(message: "Scene audio read \(entry.url.lastPathComponent): \(error)")
            }
            filenames[entry.audioId] = filename
        }

        let palette = audio.palette.map {
            PaletteOut(
                key: $0.audioId,
                filename: filenames[$0.audioId] ?? "",
                durationMs: $0.durationMs
            )
        }
        let clips = try audio.clips.map { clip -> ClipOut in
            guard let filename = filenames[clip.audioId] else {
                throw SceneLoadError(message: "Scene audio clip '\(clip.audioId)' has no palette entry")
            }
            return ClipOut(
                key: clip.audioId,
                frameIndex: clip.frameIndex,
                filename: filename,
                durationMs: clip.durationMs,
                colorIndex: clip.colorIndex,
                volume: clip.volume
            )
        }

        files.append((name: paletteEntry, data: try encode(palette, what: paletteEntry)))
        files.append((name: clipsEntry, data: try encode(clips, what: clipsEntry)))
        for item in audio.passThrough {
            if item.name.hasPrefix(prefix), seen.contains(String(item.name.dropFirst(prefix.count))) {
                throw SceneLoadError(
                    message: "Scene audio '\(item.name)' collides with a palette file"
                )
            }
            files.append((name: item.name, data: item.data))
        }
        return files    }

    // MARK: - Helpers

    /// Android ids may contain `:`, `@` or spaces; a zip entry name may not.
    private static func safeStem(_ audioId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let mapped = String(
            audioId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        )
        return mapped.isEmpty ? "sound" : mapped
    }

    private static func decode<T: Decodable>(_ data: Data, what: String) throws -> T {        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SceneLoadError(message: "Scene \(what) is not valid JSON: \(error)")
        }
    }

    private static func encode<T: Encodable>(_ value: T, what: String) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SceneLoadError(message: "Scene \(what) encode failed: \(error)")
        }
    }
}

/// Where unpacked scene audio lives between load and save.
enum SceneAudioStorage {
    static func directory() -> URL {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            // platform precondition: Caches always resolves on a real device
            fatalError("SceneAudioStorage has no Caches directory")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
    }

    /// Writes one unpacked audio entry. Existing identical bytes are reused so
    /// repeated loads of the same scene do not grow the cache. The scene key
    /// carries a content hash: two different scenes can share a name.
    static func extract(data: Data, filename: String, sceneKey: String) throws -> URL {
        let dir = directory().appendingPathComponent(sceneKey, isDirectory: true)
        let root = directory()
        do {
            if !FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        } catch {
            throw SceneLoadError(message: "SceneAudioStorage create \(dir.path): \(error)")
        }
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        if let existing = try? Data(contentsOf: url), existing == data {
            return url
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SceneLoadError(message: "SceneAudioStorage write \(url.path): \(error)")
        }
        return url
    }

    /// Reaper hook: drop a scene's unpacked audio when it is closed.
    static func clean(sceneKey: String) {
        let dir = directory().appendingPathComponent(sceneKey, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            print("SceneAudioStorage clean \(dir.path): \(error)")
        }
    }

    /// Directory name for one archive: readable stem plus a stable content hash.
    static func key(resource: String, zip: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in zip {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let stem = resource.isEmpty ? "scene" : resource
        return "\(stem)-\(String(hash, radix: 16))"
    }
}

extension String {
    /// Shared with `AudioFiles`: lowercase extension including the dot.
    func audioExtension() -> String {
        let dot = lastIndex(of: ".")
        guard let dot else {
            return ""
        }
        return String(self[dot...]).lowercased()
    }
}

private func extensionOf(_ filename: String) -> String {
    filename.audioExtension()
}
