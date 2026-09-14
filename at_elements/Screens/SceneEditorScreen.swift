import SwiftUI

private enum ScenePropsSheet: String, Identifiable {
    case edit
    case customSize
    var id: String { rawValue }
}

struct SceneEditorScreen: View {
    @State private var scene: StickmanScene
    @State private var assets: UnitAssets
    @State private var backgrounds: BackgroundAssets
    @State private var mode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false
    @State private var showingCamera = false
    @State private var showingInsert = false
    @State private var showingMenu = false
    @State private var scenePropsSheet: ScenePropsSheet?
    @State private var selectedUnitName: String

    init(scene: StickmanScene, assets: UnitAssets, backgrounds: BackgroundAssets = BackgroundAssets()) {
        if scene.frames.isEmpty {
            fatalError("SceneEditorScreen has no frames")
        }
        let frame = scene.frames[scene.currentIndex]
        if frame.units.isEmpty {
            fatalError("SceneEditorScreen frame \(frame.id) has no units")
        }
        _scene = State(initialValue: scene)
        _assets = State(initialValue: assets)
        _backgrounds = State(initialValue: backgrounds)
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.currentIndex,
                frameCount: scene.frames.count
            )
        )
        _selectedUnitName = State(initialValue: frame.units[0].name)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    onInsert: toggleInsert,
                    onMenu: toggleMenu,
                    insertActivated: showingInsert,
                    menuActivated: showingMenu
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
                    currentIndex: scene.currentIndex
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SkeletonCanvas.pane)
            }
            if showingInsert {
                ItemChooserPanel(onPick: insert)
                    .padding(.leading, MainPanel.width)
            }
            if showingMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showingMenu = false }
                SideMenu(onPick: pickMenu)
                    .transition(.move(edge: .leading))
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $mode
            )
        }
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(
                extraLeading: 0,
                action: showingMenu ? { showingMenu = false } : nil
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showingPreview) {
            FullscreenPreviewScreen(source: scene, assets: assets, backgrounds: backgrounds)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraAnimatorScreen(scene: $scene, assets: assets, backgrounds: backgrounds)
        }
        .sheet(item: $scenePropsSheet) { sheet in
            switch sheet {
            case .edit:
                EditSceneSheet(
                    draft: editSceneDraft,
                    onAddCustom: { scenePropsSheet = .customSize },
                    onApply: applySceneProps
                )
            case .customSize:
                CustomSceneSizeSheet { size in
                    applySceneSize(size)
                }
            }
        }
    }

    private func toggleMenu() {
        showingMenu.toggle()
        if showingMenu {
            showingInsert = false
        }
    }

    private func toggleInsert() {
        showingInsert.toggle()
        if showingInsert {
            showingMenu = false
        }
    }

    private func pickMenu(_ action: SideMenuAction) {
        print("menu: \(action.rawValue)")
        showingMenu = false
        if action == .editScene {
            scenePropsSheet = .edit
        }
        if action == .camera {
            showingCamera = true
        }
    }

    private var editSceneDraft: EditSceneDraft {
        EditSceneDraft(
            width: scene.width,
            height: scene.height,
            interframes: scene.interframes,
            noInterpolation: scene.noInterpolation,
            noInterpolationFrames: scene.noInterpolationFrames
        )
    }

    private func applySceneProps(_ draft: EditSceneDraft) {
        scene.width = draft.width
        scene.height = draft.height
        scene.interframes = draft.interframes
        scene.noInterpolation = draft.noInterpolation
        scene.noInterpolationFrames = draft.noInterpolationFrames
        scenePropsSheet = nil
    }

    private func applySceneSize(_ size: SceneSize) {
        scene.width = size.width
        scene.height = size.height
        scenePropsSheet = nil
    }

    private func insert(_ item: Item) {
        selectedUnitName = InstantiateUnit.insert(
            item: item,
            into: &scene,
            assets: assets,
            frameIndices: insertFrames
        )
    }

    private var insertFrames: [Int] {
        switch mode {
        case .range:
            return Array(range)
        case .frames:
            return [scene.currentIndex]
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
                if let unit = frame.units.first(where: { $0.name == selectedUnitName }) {
                    return unit
                }
                return frame.units[0]
            },
            set: { newUnit in
                let frameIndex = scene.currentIndex
                let units = scene.frames[frameIndex].units
                if units.isEmpty {
                    fatalError("SceneEditorScreen frame \(scene.frames[frameIndex].id) has no units")
                }
                if let index = units.firstIndex(where: { $0.name == selectedUnitName }) {
                    scene.frames[frameIndex].units[index] = newUnit
                    selectedUnitName = newUnit.name
                    return
                }
                if let index = units.firstIndex(where: { $0.name == newUnit.name }) {
                    scene.frames[frameIndex].units[index] = newUnit
                    selectedUnitName = newUnit.name
                    return
                }
                fatalError("SceneEditorScreen frame \(scene.frames[frameIndex].id) missing unit '\(selectedUnitName)'")
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
    var body: some View {
        DemoSceneScreen(resource: "demo_stonedummy")
    }
}

struct DemoSceneScreen: View {
    private let load: () -> (StickmanScene, UnitAssets, BackgroundAssets)
    @State private var loaded: (StickmanScene, UnitAssets, BackgroundAssets)?

    init(resource: String, subdirectory: String = "demo") {
        load = { SceneLoader.load(resource: resource, subdirectory: subdirectory) }
    }

    init(url: URL) {
        load = { SceneLoader.load(url: url) }
    }

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
            let built = load()
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
