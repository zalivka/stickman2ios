import Combine
import SwiftUI

struct FullscreenPreviewScreen: View {
    let source: StickmanScene
    let assets: UnitAssets
    var backgrounds: BackgroundAssets = BackgroundAssets()

    @State private var movie: StickmanScene?
    @State private var phase: Phase = .generating
    @State private var percent = 0
    @State private var generation = UUID()

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
            if phase == .generating {
                ReplayOverlay(text: overlayText, onTap: tapOverlay)
            }
        }
        .background(SkeletonCanvas.previewBackdrop)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(besideMainPanel: false)
        }
        .overlay(alignment: .bottomLeading) {
            if let movie, phase != .generating {
                originFrameBadge(current: movie.currentFrame.originFrameIndex + 1)
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: startGenerate)
        .onDisappear(perform: dismissGenerate)
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard phase == .playing else { return }
            tick()
        }
    }

    private func originFrameBadge(current: Int) -> some View {
        if source.frames.isEmpty {
            fatalError("FullscreenPreviewScreen origin badge has no source frames")
        }
        let digits = String(source.frames.count).count
        let probe = String(repeating: "8", count: digits)
        return ZStack {
            Text(probe)
                .hidden()
            Text("\(current)")
        }
        .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(Self.frameNumber)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Self.frameNumberBack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    fatalError("FullscreenPreviewScreen seek with no movie")
                }
                if movie.frames.isEmpty {
                    fatalError("FullscreenPreviewScreen movie has no frames")
                }
                return Double(movie.currentIndex) / Double(movie.frames.count)
            },
            set: { value in
                guard var playing = movie else {
                    fatalError("FullscreenPreviewScreen seek with no movie")
                }
                if playing.frames.isEmpty {
                    fatalError("FullscreenPreviewScreen movie has no frames")
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
        let units = movie.currentFrame.units
        return SkeletonCanvas(
            unit: units.first.map { first in
                Binding(
                    get: { first },
                    set: { _ in
                        fatalError("FullscreenPreviewScreen canvas is not interactive")
                    }
                )
            },
            frameUnits: units,
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

    private func startPlaying() {
        guard var playing = movie else {
            fatalError("FullscreenPreviewScreen play with no movie")
        }
        playing.currentIndex = 0
        movie = playing
        phase = .playing
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
}
