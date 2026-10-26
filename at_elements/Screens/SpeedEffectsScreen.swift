import Combine
import SwiftUI

struct SpeedEffectsScreen: View {
    @Binding var scene: StickmanScene
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    @State private var movie: StickmanScene?
    @State private var phase: Phase = .generating
    @State private var percent = 0
    @State private var generation = UUID()
    @State private var undoStack: [SpeedModifier] = []
    @State private var needsApply = false
    /// Playback clock. Reset whenever playback (re)starts.
    @State private var playAnchor: CFTimeInterval = 0
    /// Movie time already consumed by earlier segments of this playback.
    @State private var playedBeforeMs: Double = 0
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case generating, playing, paused, finished
    }

    var body: some View {
        HStack(spacing: 0) {
            sidePanel
            ZStack {
                if let movie {
                    canvas(movie)
                    if phase == .finished {
                        ReplayOverlay(text: overlayText, onTap: tapOverlay)
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
                if phase != .generating {
                    SpeedCurveEditor(
                        frameCount: scene.frames.count,
                        points: scene.speedModifier.points,
                        highlightIndex: highlightIndex,
                        interactive: phase != .playing,
                        onChange: applyCurve
                    )
                    .padding(.trailing, PreviewSeekBar.width + 16)
                    .paddingTrailingIsland()
                    .allowsHitTesting(phase != .playing)
                }
                if phase == .generating {
                    ReplayOverlay(text: overlayText, onTap: {})
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SkeletonCanvas.previewBackdrop)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .modifier(StatusBarClearance())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: open)
        .onDisappear(perform: dismissGenerate)
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard phase == .playing else { return }
            tick()
        }
    }

    private var canUndo: Bool { undoStack.count > 1 }

    private var chromeIdle: Bool { phase != .generating && phase != .playing }

    /// Android `VarSpeedFragment.showPlaybackStopped` — Play is visible whenever playback is idle.
    private var showPlay: Bool { chromeIdle }

    private var showUndo: Bool { chromeIdle && canUndo }

    private var sidePanel: some View {
        VStack(spacing: 24) {
            BackCircleButton(action: { dismiss() })
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            if showPlay {
                speedButton(title: "Play", icon: "main_btn_play", action: playOrApply)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            if showUndo {
                speedButton(title: "Undo", icon: "main_btn_undo", color: MainPanel.undo, action: undoCurve)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: MainPanel.width)
        .frame(maxHeight: .infinity)
        .background(MainPanel.pane)
    }

    private var highlightIndex: Int {
        movie?.currentFrameOrNil?.originFrameIndex ?? 0
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
                    assertionFailure("SpeedEffectsScreen seek with no movie")
                    return 0
                }
                if movie.frames.isEmpty {
                    assertionFailure("SpeedEffectsScreen movie has no frames")
                    return 0
                }
                return Double(movie.currentIndex) / Double(movie.frames.count)
            },
            set: { value in
                guard var playing = movie else {
                    assertionFailure("SpeedEffectsScreen seek with no movie")
                    return
                }
                if playing.frames.isEmpty {
                    assertionFailure("SpeedEffectsScreen movie has no frames")
                    return
                }
                let index = Int(Double(playing.frames.count) * value)
                playing.currentIndex = min(max(index, 0), playing.frames.count - 1)
                movie = playing
                if phase == .playing || phase == .finished {
                    phase = .paused
                }
            }
        )
    }

    private func canvas(_ movie: StickmanScene) -> some View {
        let frame = movie.currentFrameOrNil
        return SkeletonCanvas(
            unit: Binding(
                get: {
                    guard let first = frame?.units.first else {
                        return StickmanUnit(name: "", points: [], edges: [])
                    }
                    return first
                },
                set: { _ in
                    assertionFailure("SpeedEffectsScreen canvas is not interactive")
                }
            ),
            frameUnits: frame?.units ?? [],
            assets: assets,
            backgrounds: backgrounds,
            bgName: frame?.bgName,
            bgMove: frame?.bgMove ?? .identity,
            cameraMove: frame?.cameraMove ?? .identity,
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

    private func speedButton(
        title: String,
        icon: String,
        color: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(decorative: Self.chrome(icon), scale: UIScreen.main.scale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func open() {
        if scene.frames.count < 3 {
            assertionFailure("SpeedEffectsScreen needs 3 frames, got \(scene.frames.count)")
            dismiss()
            return
        }
        if scene.speedModifier.isEmpty {
            scene.speedModifier.resetFor(frameCount: scene.frames.count)
        }
        undoStack = [scene.speedModifier.copy()]
        regenerate()
    }

    private func applyCurve(_ points: [SpeedPoint]) {
        if points.count < 2 {
            assertionFailure("SpeedEffectsScreen curve has \(points.count) points")
            return
        }
        scene.speedModifier.setPoints(points)
        if undoStack.last != scene.speedModifier {
            undoStack.append(scene.speedModifier.copy())
        }
        needsApply = true
        if phase == .playing || phase == .finished {
            phase = .paused
        }
    }

    private func undoCurve() {
        if undoStack.count < 2 {
            return
        }
        undoStack.removeLast()
        guard let previous = undoStack.last else {
            assertionFailure("SpeedEffectsScreen undo empty")
            return
        }
        scene.speedModifier = previous.copy()
        needsApply = true
        if phase == .playing || phase == .finished {
            phase = .paused
        }
    }

    private func regenerate() {
        let token = UUID()
        generation = token
        phase = .generating
        percent = 0
        needsApply = false
        MovieGenerator.generate(
            scene: scene,
            assets: assets,
            progress: { value in
                guard generation == token else { return }
                percent = value
            },
            failure: { error in
                guard generation == token else { return }
                print("SpeedEffectsScreen: \(error)")
                ToastCenter.show(ItemLoadError.text(error))
                // Leave with the scene untouched; staying here would strand the screen
                // in .generating with no movie to play.
                dismiss()
            },
            completion: { generated in
                guard generation == token else { return }
                movie = generated
                startPlaying()
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
        case .paused:
            guard let movie else { return }
            resume(fromIndex: movie.currentIndex)
        case .generating, .finished:
            break
        }
    }

    private func playOrApply() {
        if needsApply {
            regenerate()
        } else {
            startPlaying()
        }
    }

    /// Android `doStartPlayback(..., fromStart: false)`: resume unless already on the last frame.
    private func startPlaying() {
        guard var playing = movie else {
            assertionFailure("SpeedEffectsScreen play with no movie")
            return
        }
        if playing.frames.isEmpty {
            assertionFailure("SpeedEffectsScreen play with no frames")
            return
        }
        if playing.currentIndex >= playing.frames.count - 1 {
            playing.currentIndex = 0
            movie = playing
        }
        resume(fromIndex: playing.currentIndex)
        needsApply = false
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
        // Match the export: the last frame holds for its full frameMs.
        if elapsed >= SceneAudioTimeline.durationMs(frameCount: playing.frames.count) {
            playing.currentIndex = playing.frames.count - 1
            movie = playing
            phase = .finished
            return
        }
        let index = SceneAudioTimeline.index(atMs: elapsed, frameCount: playing.frames.count)
        if playing.currentIndex != index {
            playing.currentIndex = index
            movie = playing
        }
    }

    private static func chrome(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("SpeedEffectsScreen missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("SpeedEffectsScreen could not read \(url.path): \(error)")
        }
    }
}
