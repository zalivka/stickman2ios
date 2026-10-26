import AVFoundation
import Combine
import Foundation
import ffmpegkit

/// Plays one file at a time: Android `AudioPlaybackUseCase` and the MediaPlayer
/// preview in `AudioActivity`. `.ogg` cannot be decoded by AVFoundation, so those
/// files are played through the merged WAV path instead.
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?
    private static var sessionConfigured = false

    /// `AudioPlaybackUseCase.start`: play `url` from `offsetMs`.
    func play(url: URL, offsetMs: Int64 = 0, volume: Float = SceneAudioClip.defaultVolume, onFinish: (() -> Void)? = nil) {
        if !FileManager.default.fileExists(atPath: url.path) {
            assertionFailure("AudioPlayback missing file \(url.path)")
            return
        }
        stop()
        Self.configureSession()
        let source: URL
        do {
            source = try Self.decodable(url: url)
        } catch {
            print("AudioPlayback decode \(url.path): \(error)")
            return
        }
        do {
            let next = try AVAudioPlayer(contentsOf: source)
            next.delegate = self
            next.volume = SceneAudioClip.clampVolume(volume)
            next.prepareToPlay()
            if offsetMs > 0 {
                let seconds = Double(offsetMs) / 1000
                // Past the end: nothing to play, same as Android's length check.
                guard seconds < next.duration else {
                    return
                }
                next.currentTime = seconds
            }
            guard next.play() else {
                throw SceneLoadError(message: "AudioPlayback refused \(url.lastPathComponent)")
            }
            player = next
            self.onFinish = onFinish
        } catch {
            print("AudioPlayback play \(url.path): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        onFinish = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finish = onFinish
        self.player = nil
        onFinish = nil
        finish?()
    }

    /// AVFoundation has no Ogg Vorbis/Opus decoder; ffmpeg does. Transcodes once
    /// into a cached WAV so repeated plays do not re-run ffmpeg.
    private static func decodable(url: URL) throws -> URL {
        if url.pathExtension.lowercased() != "ogg" {
            return url
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("at_elements_ogg", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let out = dir.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + ".wav",
            isDirectory: false
        )
        if FileManager.default.fileExists(atPath: out.path) {
            return out
        }
        let args = ["-y", "-i", url.path, out.path]
        let session = FFmpegKit.execute(withArguments: args)
        guard let session, ReturnCode.isSuccess(session.getReturnCode()),
              FileManager.default.fileExists(atPath: out.path)
        else {
            try? FileManager.default.removeItem(at: out)
            throw SceneLoadError(message: "AudioPlayback could not decode \(url.lastPathComponent)")
        }
        return out
    }

    private static func configureSession() {
        if sessionConfigured {
            return
        }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            // Playback still works for most sessions; do not crash the editor.
            print("AudioPlayback session: \(error)")
        }
    }
}
