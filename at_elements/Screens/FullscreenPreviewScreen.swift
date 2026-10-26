import Combine
import SwiftUI

struct FullscreenPreviewScreen: View {
    let source: StickmanScene
    let assets: UnitAssets
    var backgrounds: BackgroundAssets = BackgroundAssets()
    /// Tutorial Play: the finished screen offers "Start editing" and "Replay".
    var finishesTutorial = false

    @Environment(\.dismiss) private var dismiss
    @State private var movie: StickmanScene?
    @State private var phase: Phase = .generating
    @State private var percent = 0
    @State private var generation = UUID()
    @StateObject private var soundtrack = PreviewSoundtrack()

    /// Playback clock. Reset whenever playback (re)starts.
    @State private var playAnchor: CFTimeInterval = 0
    /// Movie time already consumed by earlier segments of this playback.
    @State private var playedBeforeMs: Double = 0

    private static let frameNumber = Color(red: 0xfd / 255, green: 0xda / 255, blue: 0x0d / 255)
    private static let frameNumberBack = Color(white: 0.16, opacity: 0.88)

    private enum Phase {
        case generating, playing, paused, finished
    }

    var body: some View {
        ZStack {
            if let movie {
                canvas(movie)
                if phase == .finished {
                    if finishesTutorial {
                        TutorialFinishOverlay(onStart: { dismiss() }, onReplay: { startPlaying() })
                    } else {
                        ReplayOverlay(text: overlayText, onTap: tapOverlay)
                    }
                }
                if phase != .generating {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PreviewSeekBar(progress: progressBinding)
                            .frame(maxHeight: .infinity)
                            .padding(16)
                    }
                    .paddingTrailingIsland()
                }
            } else {
                SkeletonCanvas.previewBackdrop
            }
            if phase == .generating {
                ReplayOverlay(text: overlayText, onTap: tapOverlay)
            }
        }
        .background(SkeletonCanvas.previewBackdrop)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .modifier(StatusBarClearance())
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(besideMainPanel: false)
        }
        .overlay(alignment: .bottomLeading) {
            if let movie, phase != .generating {
                originFrameBadge(current: (movie.currentFrameOrNil?.originFrameIndex ?? -1) + 1)
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: startGenerate)
        .onDisappear(perform: dismissGenerate)
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard phase == .playing else { return }
            tick()
        }
    }

    private func originFrameBadge(current: Int) -> some View {
        if source.frames.isEmpty {
            assertionFailure("FullscreenPreviewScreen origin badge has no source frames")
            return AnyView(EmptyView())
        }
        let digits = String(source.frames.count).count
        let probe = String(repeating: "8", count: digits)
        return AnyView(
            ZStack {
                Text(probe)
                    .hidden()
                Text("\(current)")
            }
            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(Self.frameNumber)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Self.frameNumberBack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        )
    }

    private var overlayText: String {
        switch phase {
        case .generating:
            return "Preparing… \(percent)%"
        case .finished:
            return "TAP HERE TO REPLAY"
        case .playing, .paused:
            return ""
        }
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                guard let movie else {
                    assertionFailure("FullscreenPreviewScreen seek with no movie")
                    return 0
                }
                if movie.frames.isEmpty {
                    assertionFailure("FullscreenPreviewScreen movie has no frames")
                    return 0
                }
                return Double(movie.currentIndex) / Double(movie.frames.count)
            },
            set: { value in
                guard var playing = movie else {
                    assertionFailure("FullscreenPreviewScreen seek with no movie")
                    return
                }
                if playing.frames.isEmpty {
                    assertionFailure("FullscreenPreviewScreen movie has no frames")
                    return
                }
                let index = Int(Double(playing.frames.count) * value)
                playing.currentIndex = min(max(index, 0), playing.frames.count - 1)
                movie = playing
                if phase == .playing || phase == .finished {
                    phase = .paused
                    soundtrack.pause()
                }
            }
        )
    }

    private func canvas(_ movie: StickmanScene) -> some View {
        let units = movie.currentFrameOrNil?.units ?? []
        return SkeletonCanvas(
            unit: units.first.map { first in
                Binding(
                    get: { first },
                    set: { _ in
                        assertionFailure("FullscreenPreviewScreen canvas is not interactive")
                    }
                )
            },
            frameUnits: units,
            assets: assets,
            backgrounds: backgrounds,
            bgName: movie.currentFrameOrNil?.bgName,
            bgMove: movie.currentFrameOrNil?.bgMove ?? .identity,
            cameraMove: movie.currentFrameOrNil?.cameraMove ?? .identity,
            sceneWidth: movie.width,
            sceneHeight: movie.height,
            currentIndex: movie.currentIndex,
            mode: .preview,
            showSkeleton: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: tapCanvas)
    }

    private func startGenerate() {
        let token = UUID()
        generation = token
        phase = .generating
        percent = 0
        MovieGenerator.generate(
            scene: source,
            assets: assets,
            progress: { value in
                guard generation == token else { return }
                percent = value
            },
            failure: { error in
                guard generation == token else { return }
                print("FullscreenPreviewScreen: \(error)")
                ToastCenter.show(ItemLoadError.text(error))
                dismiss()
            },
            completion: { generated in
                guard generation == token else { return }
                // Android merges the soundtrack before the first frame shows.
                soundtrack.prepare(movie: generated) { hasAudio in
                    guard generation == token else { return }
                    movie = generated
                    startPlaying(hasAudio: hasAudio)
                }
            }
        )
    }

    private func dismissGenerate() {
        generation = UUID()
        phase = .generating
    }

    private func tapOverlay() {
        if phase == .finished {
            startPlaying()
        }
    }

    private func tapCanvas() {
        switch phase {
        case .playing:
            phase = .paused
            soundtrack.pause()
        case .paused:
            if let movie {
                resume(fromIndex: movie.currentIndex)
                soundtrack.play(fromMs: SceneAudioTimeline.storedOffsetMs(frameIndex: movie.currentIndex))
            }
        case .generating, .finished:
            break
        }
    }

    private func startPlaying(hasAudio: Bool = true) {
        guard var playing = movie else {
            assertionFailure("FullscreenPreviewScreen play with no movie")
            return
        }
        playing.currentIndex = 0
        movie = playing
        resume(fromIndex: 0)
        if hasAudio {
            soundtrack.play(fromMs: 0)
        }
    }

    /// Restart the clock so that `index` is the frame on screen now.
    private func resume(fromIndex index: Int) {
        playAnchor = CACurrentMediaTime()
        playedBeforeMs = SceneAudioTimeline.exactTimeMs(frameIndex: index)
        phase = .playing
    }

    private func tick() {
        guard var playing = movie else { return }
        let elapsed = playedBeforeMs + (CACurrentMediaTime() - playAnchor) * 1000
        // Match the export: the last frame stays on screen for its full frameMs,
        // so the movie ends at frameCount * frameMs, not (frameCount - 1) * frameMs.
        if elapsed >= SceneAudioTimeline.durationMs(frameCount: playing.frames.count) {
            playing.currentIndex = playing.frames.count - 1
            movie = playing
            phase = .finished
            soundtrack.stop()
            return
        }
        let index = SceneAudioTimeline.index(atMs: elapsed, frameCount: playing.frames.count)
        if playing.currentIndex != index {
            playing.currentIndex = index
            movie = playing
        }
    }
}
