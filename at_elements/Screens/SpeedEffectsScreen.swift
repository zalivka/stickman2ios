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
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case generating, playing, paused, finished
    }

    var body: some View {
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
                }
            } else {
                SkeletonCanvas.previewBackdrop
            }
            if phase != .generating {
                SpeedCurveEditor(
                    frameCount: scene.frames.count,
                    points: scene.speedModifier.points,
                    highlightIndex: highlightIndex,
                    onChange: applyCurve
                )
                .padding(.trailing, PreviewSeekBar.width + 16)
                .allowsHitTesting(phase != .playing)
            }
            if phase == .generating {
                ReplayOverlay(text: overlayText, onTap: {})
            }
        }
        .background(SkeletonCanvas.previewBackdrop)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            HStack(alignment: .center, spacing: 16) {
                if showPlay {
                    speedButton(title: "Play", icon: "main_btn_play", action: playOrApply)
                }
                FullscreenBackButton(besideMainPanel: false, padded: false, action: { dismiss() })
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            if showUndo {
                speedButton(title: "Undo", icon: "main_btn_undo", color: MainPanel.undo, action: undoCurve)
                    .padding(.leading, 8)
                    .padding(.bottom, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: open)
        .onDisappear(perform: dismissGenerate)
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard phase == .playing else { return }
            tick()
        }
    }

    private var canUndo: Bool { undoStack.count > 1 }

    private var chromeIdle: Bool { phase != .generating && phase != .playing }

    private var showPlay: Bool { chromeIdle && (needsApply || phase != .finished) }

    private var showUndo: Bool { chromeIdle && canUndo }

    private var highlightIndex: Int {
        movie?.currentFrame.originFrameIndex ?? 0
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
                    fatalError("SpeedEffectsScreen seek with no movie")
                }
                if movie.frames.isEmpty {
                    fatalError("SpeedEffectsScreen movie has no frames")
                }
                return Double(movie.currentIndex) / Double(movie.frames.count)
            },
            set: { value in
                guard var playing = movie else {
                    fatalError("SpeedEffectsScreen seek with no movie")
                }
                if playing.frames.isEmpty {
                    fatalError("SpeedEffectsScreen movie has no frames")
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
        SkeletonCanvas(
            unit: Binding(
                get: {
                    let frame = movie.currentFrame
                    guard let first = frame.units.first else {
                        fatalError("SpeedEffectsScreen frame \(frame.id) read unit")
                    }
                    return first
                },
                set: { _ in
                    fatalError("SpeedEffectsScreen canvas is not interactive")
                }
            ),
            frameUnits: movie.currentFrame.units,
            assets: assets,
            backgrounds: backgrounds,
            bgName: movie.currentFrame.bgName,
            bgMove: movie.currentFrame.bgMove,
            cameraMove: movie.currentFrame.cameraMove,
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
            fatalError("SpeedEffectsScreen needs 3 frames, got \(scene.frames.count)")
        }
        if scene.speedModifier.isEmpty {
            scene.speedModifier.resetFor(frameCount: scene.frames.count)
        }
        undoStack = [scene.speedModifier.copy()]
        regenerate()
    }

    private func applyCurve(_ points: [SpeedPoint]) {
        if points.count < 2 {
            fatalError("SpeedEffectsScreen curve has \(points.count) points")
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
            fatalError("SpeedEffectsScreen undo empty")
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
            phase = .playing
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

    private func startPlaying() {
        guard var playing = movie else {
            fatalError("SpeedEffectsScreen play with no movie")
        }
        playing.currentIndex = 0
        movie = playing
        phase = .playing
        needsApply = false
    }

    private func tick() {
        guard var playing = movie else { return }
        if playing.currentIndex >= playing.frames.count - 1 {
            phase = .finished
            return
        }
        playing.currentIndex += 1
        movie = playing
    }

    private static func chrome(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("SpeedEffectsScreen missing chrome/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/\(name).png")
        } catch {
            fatalError("SpeedEffectsScreen could not read \(url.path): \(error)")
        }
    }
}
