import AVFoundation
import Foundation
import ffmpegkit
import os

/// Android `AudioUtils` + `SoundEffectsRepository` for the iOS sound library:
/// durations, the size cap, and where sounds are stored, imported, and deleted.
enum AudioFiles {
    static let supportedExtensions = SceneAudioArchive.supportedExtensions
    static let maxSoundFileBytes = 20 * 1024 * 1024

    enum Failure: Error, CustomStringConvertible, LocalizedError {
        case invalidIdentifier(String)
        case unsupportedFormat(String)
        case emptyFile(String)
        case fileTooLarge(String, Int)
        case unreadableAudio(String)
        case ioFailed(String, Error)

        var description: String {
            switch self {
            case .invalidIdentifier(let id):
                return "Invalid sound id '\(id)'"
            case .unsupportedFormat(let ext):
                return "Unsupported sound format '.\(ext)' (use wav, mp3, m4a, or ogg)"
            case .emptyFile(let name):
                return "Sound file '\(name)' is empty"
            case .fileTooLarge(let name, _):
                return "Sound file '\(name)' exceeds 20 MB limit"
            case .unreadableAudio(let name):
                return "Could not read audio duration for '\(name)'"
            case .ioFailed(let label, let error):
                return "Audio library error (\(label)): \(error.localizedDescription)"
            }
        }

        var errorDescription: String? { description }
    }

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

    /// Bundled sounds, copied into the library once so the sound library has initial content.
    static let seedNames: [(name: String, ext: String)] = [
        ("notif", "wav"),
        ("mac", "mp3"),
        ("rec", "mp3"),
        ("say_wifi", "wav"),
    ]

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

    /// Android `SoundEffectsRepository.ingestAudio`: copies a sound file into the library,
    /// probes its duration, writes `<id>.name`, and invalidates the cache.
    static func ingest(url: URL, in directory: URL? = nil) throws -> LibraryEntry {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let filename = url.lastPathComponent
        let ext = extensionOf(filename)
        guard supportedExtensions.contains(ext) else {
            throw Failure.unsupportedFormat(ext.isEmpty ? filename : ext)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.ioFailed(filename, error)
        }
        if data.isEmpty {
            throw Failure.emptyFile(filename)
        }
        if data.count > maxSoundFileBytes {
            throw Failure.fileTooLarge(filename, data.count)
        }

        let dir = try resolveDirectory(directory)
        let audioId = allocateId(in: dir)
        let dest = dir.appendingPathComponent("\(audioId).\(ext)", isDirectory: false)
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            throw Failure.ioFailed(audioId, error)
        }

        let duration: Int64
        do {
            duration = try durationMs(url: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw Failure.unreadableAudio(filename)
        }
        if duration <= 0 {
            try? FileManager.default.removeItem(at: dest)
            throw Failure.unreadableAudio(filename)
        }

        let rawStem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = rawStem.isEmpty ? audioId : rawStem
        let nameFile = dir.appendingPathComponent("\(audioId).name", isDirectory: false)
        do {
            try Data(displayName.utf8).write(to: nameFile, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.removeItem(at: nameFile)
            throw Failure.ioFailed("\(audioId).name", error)
        }

        if directory == nil {
            invalidateLibrary()
        }
        return LibraryEntry(
            audioId: audioId,
            displayName: displayName,
            url: dest,
            durationMs: duration
        )
    }

    /// Android `SoundEffectsRepository.delete`: removes `<audioId>.<ext>` and `<audioId>.name`.
    static func delete(audioId: String, in directory: URL? = nil) throws {
        if audioId.isEmpty || audioId.contains("/") {
            throw Failure.invalidIdentifier(audioId)
        }
        let dir = try resolveDirectory(directory)
        let fm = FileManager.default
        for ext in supportedExtensions {
            let file = dir.appendingPathComponent("\(audioId).\(ext)", isDirectory: false)
            if fm.fileExists(atPath: file.path) {
                do {
                    try fm.removeItem(at: file)
                } catch {
                    throw Failure.ioFailed(file.lastPathComponent, error)
                }
            }
        }
        let nameFile = dir.appendingPathComponent("\(audioId).name", isDirectory: false)
        if fm.fileExists(atPath: nameFile.path) {
            do {
                try fm.removeItem(at: nameFile)
            } catch {
                throw Failure.ioFailed(nameFile.lastPathComponent, error)
            }
        }
        if directory == nil {
            invalidateLibrary()
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
    static func library(in directory: URL? = nil) -> [LibraryEntry] {
        if let directory {
            return readLibrary(in: directory)
        }
        if let cachedLibrary {
            return cachedLibrary
        }
        let entries = readLibrary(in: nil)
        cachedLibrary = entries
        return entries
    }

    /// Drops the probe cache; `seedLibrary` and `ingest` write files, so the next `library()`
    /// must see them.
    static func invalidateLibrary() {
        cachedLibrary = nil
    }

    private static func readLibrary(in customDirectory: URL?) -> [LibraryEntry] {
        let dir: URL
        do {
            dir = try resolveDirectory(customDirectory)
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
        .sorted { $0.audioId > $1.audioId }
    }

    static func libraryEntry(audioId: String) -> LibraryEntry? {
        library().first { $0.audioId == audioId }
    }

    // MARK: - Private

    private static func resolveDirectory(_ custom: URL?) throws -> URL {
        if let custom {
            if !FileManager.default.fileExists(atPath: custom.path) {
                do {
                    try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
                } catch {
                    throw Failure.ioFailed(custom.path, error)
                }
            }
            return custom
        }
        return try libraryDirectory()
    }

    private static func allocateId(in directory: URL) -> String {
        let fm = FileManager.default
        var ts = Int64((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))
        while hasAnyFile(audioId: String(ts), in: directory, fm: fm) {
            ts += 1
        }
        return String(ts)
    }

    private static func hasAnyFile(audioId: String, in directory: URL, fm: FileManager) -> Bool {
        for ext in supportedExtensions {
            let url = directory.appendingPathComponent("\(audioId).\(ext)", isDirectory: false)
            if fm.fileExists(atPath: url.path) {
                return true
            }
        }
        let nameURL = directory.appendingPathComponent("\(audioId).name", isDirectory: false)
        return fm.fileExists(atPath: nameURL.path)
    }
}

private func extensionOf(_ filename: String) -> String {
    filename.audioExtension()
}
