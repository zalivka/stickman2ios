import Combine
import Foundation

final class VideoExport: ObservableObject {
    enum Failure: Equatable {
        case photosDenied
        case exportFailed(String)
    }

    enum Phase: Equatable {
        case idle
        case saving
        case saved
        case failed(Failure)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0

    private var stop: JpegWriteStop?
    private var outcomeTaken = false
    private var generation = 0

    func start(scene: StickmanScene, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if phase == .saving {
            return
        }
        let snapshot = scene
        let active = JpegWriteStop()
        stop = active
        outcomeTaken = false
        generation += 1
        progress = 0
        phase = .saving
        JpegSequenceWriter.write(
            scene: snapshot,
            assets: assets,
            backgrounds: backgrounds,
            stop: active,
            progress: { [weak self] value in
                self?.progress = min(max(Double(value) / 100.0, 0), 1)
            },
            completion: { result in
                Task { @MainActor in
                    switch result {
                    case .failure(let error):
                        JpegSequenceWriter.clean()
                        if case .cancelled = error as? JpegWriteError {
                            self.finish(.cancelled)
                            return
                        }
                        self.finish(.failed(.exportFailed(Self.failureText(error))))
                    case .success(let rendered):
                        if active.isCancelled {
                            JpegSequenceWriter.clean()
                            self.finish(.cancelled)
                            return
                        }
                        if rendered.count < 1 {
                            JpegSequenceWriter.clean()
                            self.finish(.failed(.exportFailed("VideoExport write produced \(rendered.count) files")))
                            return
                        }
                        // ffmpeg runs for seconds; Android merges on
                        // `Schedulers.io()`, never on the main thread.
                        let count = rendered.count
                        let movie = rendered.movie
                        DispatchQueue.global(qos: .userInitiated).async {
                            let merged: URL?
                            do {
                                merged = try Self.mergeSoundtrack(movie)
                            } catch {
                                DispatchQueue.main.async {
                                    JpegSequenceWriter.clean()
                                    self.finish(.failed(.exportFailed(Self.failureText(error))))
                                }
                                return
                            }
                            JpegVideoAssembler.assemble(frameCount: count, audio: merged) { assembleResult in
                                Task { @MainActor in
                                    JpegSequenceWriter.clean()
                                    if let merged {
                                        try? FileManager.default.removeItem(at: merged)
                                    }
                                    if active.isCancelled {
                                        self.finish(.cancelled)
                                        return
                                    }
                                    switch assembleResult {
                                    case .success:
                                        self.finish(.saved)
                                    case .failure(let assembleError):
                                        if let assemblerError = assembleError as? JpegVideoAssembler.AssemblerError,
                                           case .photosDenied = assemblerError {
                                            self.finish(.failed(.photosDenied))
                                        } else {
                                            self.finish(.failed(.exportFailed(Self.failureText(assembleError))))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        )
    }

    /// Stops an in-flight export. The writer/assembler completions may still
    /// arrive later; `finish` dedups via `outcomeTaken` so they are no-ops.
    func cancel() {
        guard phase == .saving else { return }
        stop?.cancel()
        JpegVideoAssembler.cancel()
        finish(.cancelled)
    }

    /// Android `StageAudio.mergeAudioBlocking` on the generated movie: offsets
    /// come from generated `originFrameIndex`, not source keyframes.
    private static func mergeSoundtrack(_ movie: StickmanScene) throws -> URL? {
        let timed = try movie.audio.timedFiles(movie: movie)
        if timed.isEmpty {
            return nil
        }
        return try AudioMerger.merge(timed)
    }

    private static func failureText(_ error: Error) -> String {
        if let write = error as? JpegWriteError, case .failed(let message) = write {
            return message
        }
        if error is JpegVideoAssembler.AssemblerError {
            return "Export failed"
        }
        return error.localizedDescription
    }

    private func finish(_ next: Phase) {
        if outcomeTaken {
            return
        }
        outcomeTaken = true
        stop = nil
        phase = next
        scheduleIdleReset()
    }

    private func scheduleIdleReset() {
        let gen = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if gen == self.generation, self.phase != .saving {
                self.phase = .idle
            }
        }
    }
}
