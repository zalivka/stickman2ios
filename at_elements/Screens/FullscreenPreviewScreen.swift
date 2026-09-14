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

    private enum Phase {
        case generating, playing, paused, finished
    }

    var body: some View {
        ZStack {
            if let movie {
                canvas(movie)
                HStack(spacing: 0) {
                    if phase != .generating {
                        PreviewSeekBar(progress: progressBinding)
                            .frame(maxHeight: .infinity)
                    }
                    if phase == .finished {
                        ReplayOverlay(text: overlayText, onTap: tapOverlay)
                    } else {
                        Color.clear.allowsHitTesting(false)
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
                .padding(.leading, phase != .generating && movie != nil ? PreviewSeekBar.width : 0)
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
        SkeletonCanvas(
            unit: Binding(
                get: {
                    let frame = movie.currentFrame
                    if frame.units.isEmpty {
                        fatalError("FullscreenPreviewScreen frame \(frame.id) has no units")
                    }
                    return frame.units[0]
                },
                set: { _ in
                    fatalError("FullscreenPreviewScreen canvas is not interactive")
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
