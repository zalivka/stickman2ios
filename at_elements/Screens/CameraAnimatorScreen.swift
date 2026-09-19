import SwiftUI

struct CameraAnimatorScreen: View {
    @Binding var scene: StickmanScene
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    @State private var navMode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false

    init(scene: Binding<StickmanScene>, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if scene.wrappedValue.frames.isEmpty {
            fatalError("CameraAnimatorScreen has no frames")
        }
        _scene = scene
        self.assets = assets
        self.backgrounds = backgrounds
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.wrappedValue.currentIndex,
                frameCount: scene.wrappedValue.frames.count
            )
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    playEnabled: scene.frames.count >= 2,
                    onReset: resetCamera
                )
                SkeletonCanvas(
                    unit: unitBinding,
                    frameUnits: scene.currentFrame.units,
                    assets: assets,
                    backgrounds: backgrounds,
                    bgName: scene.currentFrame.bgName,
                    bgMove: scene.currentFrame.bgMove,
                    cameraMove: scene.currentFrame.cameraMove,
                    sceneWidth: scene.width,
                    sceneHeight: scene.height,
                    currentIndex: scene.currentIndex,
                    mode: .camera,
                    showSkeleton: false,
                    onCameraChange: applyCamera
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SkeletonCanvas.pane)
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $navMode
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

    private func applyCamera(_ move: PictureMove) {
        switch navMode {
        case .frames:
            let index = scene.currentIndex
            if index < 0 || index >= scene.frames.count {
                fatalError("CameraAnimatorScreen currentIndex \(index) out of \(scene.frames.count)")
            }
            scene.frames[index].cameraMove = move
        case .range:
            if range.lowerBound < 0 || range.upperBound >= scene.frames.count {
                fatalError("CameraAnimatorScreen range \(range) out of \(scene.frames.count)")
            }
            for index in range {
                scene.frames[index].cameraMove = move
            }
        }
    }

    private func resetCamera() {
        applyCamera(.identity)
    }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { scene.currentIndex },
            set: { newIndex in
                if newIndex < 0 || newIndex >= scene.frames.count {
                    fatalError("CameraAnimatorScreen currentIndex \(newIndex) out of \(scene.frames.count)")
                }
                scene.currentIndex = newIndex
            }
        )
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                let frame = scene.currentFrame
                guard let first = frame.units.first else {
                    fatalError("CameraAnimatorScreen frame \(frame.id) read unit")
                }
                return first
            },
            set: { _ in
                fatalError("CameraAnimatorScreen canvas is not an editor")
            }
        )
    }
}
