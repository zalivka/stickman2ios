import Combine
import SwiftUI

struct FullscreenPreviewScreen: View {
    let source: StickmanScene
    let assets: UnitAssets

    @State private var movie: StickmanScene?
    @State private var phase: Phase = .generating
    @State private var percent = 0
    @State private var generation = UUID()

    private enum Phase {
        case generating, playing, finished
    }

    var body: some View {
        ZStack {
            if let movie {
                canvas(movie)
            } else {
                Color.white
            }
            if phase != .playing {
                ReplayOverlay(text: overlayText, onTap: tapOverlay)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(besideMainPanel: false)
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
        case .playing:
            return ""
        }
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
            assets: assets,
            sceneWidth: movie.width,
            sceneHeight: movie.height,
            currentIndex: movie.currentIndex,
            sceneFill: fillColor(movie),
            interactive: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fillColor(_ movie: StickmanScene) -> Color {
        guard let name = movie.currentFrame.bgName else {
            return SkeletonCanvas.sceneFill
        }
        let rgb = HexRGB.parse(name)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private func startGenerate() {
        let token = UUID()
        generation = token
        phase = .generating
        percent = 0
        MovieGenerator.generate(
            scene: source,
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
