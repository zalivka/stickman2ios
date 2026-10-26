import AVFoundation
import Foundation
import ffmpegkit
import os

/// Android `AudioUtils` for the iOS sound library: durations, the size cap and
/// where placed sounds are copied to.
enum AudioFiles {
    static let supportedExtensions = SceneAudioArchive.supportedExtensions

    /// `StageAudio.registerClipPoint` probes the source when no duration is known.
    /// `MediaMetadataRetriever` has no exact AVFoundation twin, so ffprobe stays
    /// the fallback for containers AVFoundation cannot open (ogg).
    static func durationMs(url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SceneLoadError(message: "Audio file missing: \(url.path)")
        }
        if let fast = avFoundationDurationMs(url: url) {
            return fast
        }
        let session = FFprobeKit.getMediaInformation(url.path)
        let duration = session?.getMediaInformation()?.getDuration()
        guard let duration, !duration.isEmpty, let seconds = Double(duration), seconds > 0 else {
            throw SceneLoadError(
                message: "Audio duration unreadable: \(url.lastPathComponent) (\(duration ?? "nil"))"
            )
        }
        let ms = Int64((seconds * 1000).rounded())
        if ms <= 0 {
            throw SceneLoadError(message: "Audio duration \(ms)ms for \(url.lastPathComponent)")
        }
        return ms
    }

    /// ffprobe spins up a process per file (~600 ms), which is far too slow for
    /// the palette list; AVAudioFile reads the header in microseconds.
    private static func avFoundationDurationMs(url: URL) -> Int64? {
        guard url.pathExtension.lowercased() != "ogg" else {
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else {
            return nil
        }
        let ms = Int64((Double(file.length) / rate * 1000).rounded())
        return ms > 0 ? ms : nil
    }

    /// Android `SoundEffectsRepository.libraryDir`, seeded from the bundle.
    static func libraryDirectory() throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // platform precondition: Application Support always resolves on a real device
            fatalError("AudioFiles has no Application Support")
        }
        let dir = root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw SceneLoadError(message: "AudioFiles create \(dir.path): \(error)")
            }
        }
        return dir
    }

    /// Bundled sounds, copied into the library once so the palette has content
    /// without the (out of scope) importer.
    static let seedNames: [(name: String, ext: String)] = [
        ("notif", "wav"),
        ("mac", "mp3"),
        ("rec", "mp3"),
        ("say_wifi", "wav"),
    ]

    /// Test sounds that must always show in the palette; Android has a library
    /// screen that finds them, iOS has no importer yet.
    static let alwaysInPalette = ["rec", "say_wifi"]

    static func seedLibrary() throws {
        let dir = try libraryDirectory()
        var copied = false
        for (name, ext) in seedNames {
            guard let src = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "sounds")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            else {
                throw SceneLoadError(message: "AudioFiles seed sound '\(name).\(ext)' is not in the bundle")
            }
            let dest = dir.appendingPathComponent("\(name).\(ext)", isDirectory: false)
            if FileManager.default.fileExists(atPath: dest.path) {
                continue
            }
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                copied = true
            } catch {
                throw SceneLoadError(message: "AudioFiles seed \(name): \(error)")
            }
        }
        if copied {
            invalidateLibrary()
        }
    }

    /// Library entries for `alwaysInPalette`; fails loudly when a seed is missing.
    static func testPaletteEntries() throws -> [LibraryEntry] {
        let all = library()
        return try alwaysInPalette.map { audioId in
            guard let entry = all.first(where: { $0.audioId == audioId }) else {
                throw SceneLoadError(message: "AudioFiles test sound '\(audioId)' was not seeded")
            }
            return entry
        }
    }

    struct LibraryEntry: Identifiable, Hashable {
        var id: String { url.lastPathComponent }
        var audioId: String
        var displayName: String
        var url: URL
        var durationMs: Int64
    }

    /// Duration probing costs milliseconds per file and the palette/chips call
    /// `library()` on every SwiftUI pass, so read the directory once per process.
    private static var cachedLibrary: [LibraryEntry]?

    /// Every playable file in the library, newest id first like Android.
    static func library() -> [LibraryEntry] {
        if let cachedLibrary {
            return cachedLibrary
        }
        let entries = readLibrary()
        cachedLibrary = entries
        return entries
    }

    /// Drops the probe cache; `seedLibrary` copies files, so the next `library()`
    /// must see them.
    static func invalidateLibrary() {
        cachedLibrary = nil
    }

    private static func readLibrary() -> [LibraryEntry] {
        let dir: URL
        do {
            dir = try libraryDirectory()
        } catch {
            print("AudioFiles library: \(error)")
            return []
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("AudioFiles library list \(dir.path): \(error)")
            return []
        }
        return urls.compactMap { url -> LibraryEntry? in
            guard supportedExtensions.contains(extensionOf(url.lastPathComponent)) else {
                return nil
            }
            let audioId = url.deletingPathExtension().lastPathComponent
            guard !audioId.isEmpty else {
                return nil
            }
            let nameFile = dir.appendingPathComponent("\(audioId).name", isDirectory: false)
            let displayName = (try? String(contentsOf: nameFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = (try? durationMs(url: url)) ?? 0
            guard duration > 0 else {
                print("AudioFiles library skipping \(url.lastPathComponent): no duration")
                return nil
            }
            return LibraryEntry(
                audioId: audioId,
                displayName: displayName?.isEmpty == false ? displayName! : audioId,
                url: url,
                durationMs: duration
            )
        }
        .sorted { $0.durationMs > $1.durationMs }
    }

    static func libraryEntry(audioId: String) -> LibraryEntry? {
        library().first { $0.audioId == audioId }
    }
}

private func extensionOf(_ filename: String) -> String {
    filename.audioExtension()
}
