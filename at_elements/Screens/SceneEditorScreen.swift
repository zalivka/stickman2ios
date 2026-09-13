import SwiftUI

struct SceneEditorScreen: View {
    @State private var scene: StickmanScene
    @State private var assets: UnitAssets
    @State private var backgrounds: BackgroundAssets
    @State private var mode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false

    init(scene: StickmanScene, assets: UnitAssets, backgrounds: BackgroundAssets = BackgroundAssets()) {
        _scene = State(initialValue: scene)
        _assets = State(initialValue: assets)
        _backgrounds = State(initialValue: backgrounds)
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.currentIndex,
                frameCount: scene.frames.count
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            MainPanel(onPlay: { showingPreview = true })
            SkeletonCanvas(
                unit: unitBinding,
                assets: assets,
                backgrounds: backgrounds,
                bgName: scene.currentFrame.bgName,
                bgMove: scene.currentFrame.bgMove,
                sceneWidth: scene.width,
                sceneHeight: scene.height,
                currentIndex: scene.currentIndex
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $mode
            )
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton()
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showingPreview) {
            FullscreenPreviewScreen(source: scene, assets: assets, backgrounds: backgrounds)
        }
    }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { scene.currentIndex },
            set: { newIndex in
                if newIndex < 0 || newIndex >= scene.frames.count {
                    fatalError("SceneEditorScreen currentIndex \(newIndex) out of \(scene.frames.count)")
                }
                scene.currentIndex = newIndex
            }
        )
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                let frame = scene.currentFrame
                if frame.units.isEmpty {
                    fatalError("SceneEditorScreen frame \(frame.id) has no units")
                }
                return frame.units[0]
            },
            set: { newUnit in
                let frameIndex = scene.currentIndex
                if scene.frames[frameIndex].units.isEmpty {
                    fatalError("SceneEditorScreen frame \(scene.frames[frameIndex].id) has no units")
                }
                scene.frames[frameIndex].units[0] = newUnit
            }
        )
    }
}

struct Ter2Screen: View {
    @State private var loaded: (StickmanScene, UnitAssets, BackgroundAssets)?

    var body: some View {
        Group {
            if let loaded {
                SceneEditorScreen(scene: loaded.0, assets: loaded.1, backgrounds: loaded.2)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        FullscreenBackButton()
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        if loaded != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let built = SceneLoader.load(resource: "ter2", subdirectory: "testdata")
            DispatchQueue.main.async {
                loaded = built
            }
        }
    }
}

struct StonedummyScreen: View {
    @State private var loaded: (StickmanScene, UnitAssets, BackgroundAssets)?

    var body: some View {
        Group {
            if let loaded {
                SceneEditorScreen(scene: loaded.0, assets: loaded.1, backgrounds: loaded.2)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        FullscreenBackButton()
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        if loaded != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let built = SceneLoader.load(resource: "demo_stonedummy", subdirectory: "demo")
            DispatchQueue.main.async {
                loaded = built
            }
        }
    }
}

#Preview {
    NavigationStack {
        Ter2Screen()
    }
}
