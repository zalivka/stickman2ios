import Combine
import Foundation

/// Merged soundtrack for one generated movie. Android `StageAudio`'s
/// `lastMergedFile` plus `AudioPlaybackUseCase`, without speech: the merge
/// finishes before the movie starts, exactly like `SimplePreviewPresenter`.
final class PreviewSoundtrack: ObservableObject {
    private let playback = AudioPlayback()
    private var merged: URL?
    private var generation = 0

    /// Merges off the main thread, then calls back on the main thread. Silent
    /// scenes call back immediately with no file.
    func prepare(movie: StickmanScene, completion: @escaping (Bool) -> Void) {
        generation += 1
        let token = generation
        stop()
        if let previous = merged {
            try? FileManager.default.removeItem(at: previous)
        }
        merged = nil
        let timed: [TimedAudioFile]
        do {
            timed = try movie.audio.timedFiles(movie: movie)
        } catch {
            print("PreviewSoundtrack timed files: \(error)")
            completion(false)
            return
        }
        if timed.isEmpty {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AudioMerger.merge(timed) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.generation else {
                    if case .success(let url) = result {
                        try? FileManager.default.removeItem(at: url)
                    }
                    return
                }
                switch result {
                case .success(let url):
                    self.merged = url
                    completion(true)
                case .failure(let error):
                    print("PreviewSoundtrack merge: \(error)")
                    completion(false)
                }
            }
        }
    }

    /// Android `AudioPlaybackUseCase.startAt`: the offset is movie time.
    func play(fromMs offsetMs: Int64) {
        guard let merged else {
            return
        }
        playback.play(url: merged, offsetMs: offsetMs)
    }

    func pause() {
        playback.stop()
    }

    func stop() {
        playback.stop()
    }

    func invalidate() {
        generation += 1
        stop()
        if let merged {
            try? FileManager.default.removeItem(at: merged)
        }
        merged = nil
    }
}
