import Foundation
import ffmpegkit

/// One `-i` input with its mix parameters. Android `TimedAudioFile`.
struct TimedAudioFile {
    var file: URL
    var offsetMs: Int64
    var volume: Float = 1
    /// Play this many ms from the file start; negative = the whole file.
    var durationMs: Int64 = -1
}

/// Android `AudioMerger`: mixes placed clips into one WAV with ffmpeg.
enum AudioMerger {
    static func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("at_elements_merged.wav", isDirectory: false)
    }

    /// `AudioMerger.mergeTimedFiles`.
    static func merge(_ files: [TimedAudioFile]) throws -> URL {
        if files.isEmpty {
            throw SceneLoadError(message: "AudioMerger has no files to merge")
        }
        for item in files where !FileManager.default.fileExists(atPath: item.file.path) {
            throw SceneLoadError(message: "AudioMerger missing input: \(item.file.path)")
        }
        let output = outputURL()
        try? FileManager.default.removeItem(at: output)
        let args = makeArguments(files, output: output)
        let session = FFmpegKit.execute(withArguments: args)
        guard let session else {
            throw SceneLoadError(message: "AudioMerger ffmpeg did not start")
        }
        let code = session.getReturnCode()
        guard ReturnCode.isSuccess(code) else {
            throw SceneLoadError(
                message: "AudioMerger ffmpeg failed (\(code?.getValue() ?? -1)): \(session.getFailStackTrace() ?? "")"
            )
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0
        guard size > 0 else {
            throw SceneLoadError(message: "AudioMerger produced no output")
        }
        return output
    }

    /// Same filter chain as Android `makeMergeAudioCommand`.
    static func makeArguments(_ files: [TimedAudioFile], output: URL) -> [String] {
        var args = ["-y"]
        for item in files {
            args.append(contentsOf: ["-i", item.file.path])
        }
        var chains: [String] = []
        var mixInputs = ""
        for (index, item) in files.enumerated() {
            let volume = SceneAudioClip.clampVolume(item.volume)
            var chain = ""
            if item.durationMs >= 0 {
                let playMs = item.durationMs == 0 ? 1 : item.durationMs
                chain += String(format: "atrim=start=0:duration=%.6f,asetpts=PTS-STARTPTS,", Double(playMs) / 1000)
            }
            chain += String(format: "volume=%.4f", volume)
            chain += ",adelay=\(item.offsetMs)|\(item.offsetMs)"
            chains.append("[\(index):a]\(chain)[a\(index)]")
            mixInputs += "[a\(index)]"
        }
        let filter = chains.joined(separator: "; ")
            + "; " + mixInputs
            + "amix=inputs=\(files.count):duration=longest"
        args.append(contentsOf: ["-filter_complex", filter, output.path])
        return args
    }
}
