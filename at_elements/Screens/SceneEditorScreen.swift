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
    @State private var showingBackground = false
    @State private var showingInsert = false
    @State private var showingEditUnit = false
    @State private var showingMenu = false
    @State private var scenePropsSheet: ScenePropsSheet?
    @State private var selectedUnitName: String?
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var saveError = ""
    @State private var lastSavedName: String?
    @State private var saveToast = ""

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
        _selectedUnitName = State(initialValue: nil)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    onInsert: toggleInsert,
                    onEditUnit: toggleEditUnit,
                    onMenu: toggleMenu,
                    insertActivated: showingInsert,
                    editUnitActivated: showingEditUnit,
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
                    currentIndex: scene.currentIndex,
                    selectedUnitName: $selectedUnitName
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SkeletonCanvas.pane)
            }
            if showingInsert {
                ItemChooserPanel(onPick: insert)
                    .padding(.leading, MainPanel.width)
            }
            if showingEditUnit {
                Group {
                    if let selectedUnit {
                        UnitPropertiesPanel(
                            unit: selectedUnit,
                            assets: assets,
                            onDeselect: { selectedUnitName = nil },
                            onDelete: deleteSelectedUnit,
                            onFlip: flipSelectedUnit,
                            onDetach: detachSelectedUnit,
                            onMoveForward: { moveSelectedUnit(forward: true) },
                            onMoveBackward: { moveSelectedUnit(forward: false) },
                            canMoveForward: canMoveSelectedUnit(forward: true),
                            canMoveBackward: canMoveSelectedUnit(forward: false)
                        )
                    } else {
                        PresentUnitsPanel(
                            frameNumber: scene.currentIndex + 1,
                            units: scene.currentFrame.units,
                            selectedName: nil,
                            assets: assets,
                            onSelect: { selectedUnitName = $0 },
                            onMove: movePresentUnits
                        )
                    }
                }
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
        .fullScreenCover(isPresented: $showingBackground) {
            BgAnimatorScreen(scene: $scene, assets: assets, backgrounds: backgrounds)
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
        .sheet(isPresented: $showingSave) {
            SaveProjectSheet(
                name: $saveName,
                error: $saveError,
                onCancel: { showingSave = false },
                onSave: confirmSave
            )
        }
        .overlay {
            if !saveToast.isEmpty {
                Text(saveToast)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private func toggleMenu() {
        showingMenu.toggle()
        if showingMenu {
            showingInsert = false
            showingEditUnit = false
        }
    }

    private func toggleInsert() {
        showingInsert.toggle()
        if showingInsert {
            showingMenu = false
            showingEditUnit = false
        }
    }

    private func toggleEditUnit() {
        showingEditUnit.toggle()
        if showingEditUnit {
            showingMenu = false
            showingInsert = false
        }
    }

    /// Android list is arrange-desc; after move, arrange = count-1-index.
    private func movePresentUnits(from: IndexSet, to: Int) {
        var names = scene.currentFrame.units
            .sorted {
                if $0.arrange != $1.arrange { return $0.arrange > $1.arrange }
                return $0.name < $1.name
            }
            .map(\.name)
        names.move(fromOffsets: from, toOffset: to)
        let weights = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
            (name, names.count - 1 - index)
        })
        for frameIndex in rearrangeFrames {
            for i in scene.frames[frameIndex].units.indices {
                let name = scene.frames[frameIndex].units[i].name
                if let arrange = weights[name] {
                    scene.frames[frameIndex].units[i].arrange = arrange
                }
            }
        }
    }

    private var selectedUnit: StickmanUnit? {
        guard let selectedUnitName else { return nil }
        return scene.currentFrame.units.first { $0.name == selectedUnitName }
    }

    private func deleteSelectedUnit() {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen delete without selected unit")
        }
        for frameIndex in rearrangeFrames where scene.frames[frameIndex].units.contains(where: { $0.name == selectedUnitName }) {
            scene.frames[frameIndex].deleteConnectedUnit(named: selectedUnitName)
        }
        self.selectedUnitName = nil
    }

    private func flipSelectedUnit() {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen flip without selected unit")
        }
        for frameIndex in rearrangeFrames {
            guard let index = scene.frames[frameIndex].units.firstIndex(where: { $0.name == selectedUnitName }) else {
                continue
            }
            scene.frames[frameIndex].units[index].flipped.toggle()
        }
    }

    private func detachSelectedUnit() {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen detach without selected unit")
        }
        for frameIndex in rearrangeFrames {
            guard let index = scene.frames[frameIndex].units.firstIndex(where: { $0.name == selectedUnitName }) else {
                continue
            }
            scene.frames[frameIndex].units[index].stripAttachment()
            scene.frames[frameIndex].refreshAttachments()
        }
    }

    private func canMoveSelectedUnit(forward: Bool) -> Bool {
        guard let selectedUnitName else { return false }
        return scene.currentFrame.canRearrange(unitNamed: selectedUnitName, forward: forward)
    }

    private func moveSelectedUnit(forward: Bool) {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen rearrange without selected unit")
        }
        for frameIndex in rearrangeFrames where scene.frames[frameIndex].units.contains(where: { $0.name == selectedUnitName }) {
            scene.frames[frameIndex].rearrange(unitNamed: selectedUnitName, forward: forward)
        }
    }

    private var rearrangeFrames: [Int] {
        switch mode {
        case .range:
            return Array(range)
        case .frames:
            return [scene.currentIndex]
        }
    }

    private func pickMenu(_ action: SideMenuAction) {
        print("menu: \(action.rawValue)")
        showingMenu = false
        if action == .save {
            saveError = ""
            saveName = lastSavedName ?? SceneSaver.generateName()
            showingSave = true
        }
        if action == .editScene {
            scenePropsSheet = .edit
        }
        if action == .camera {
            showingCamera = true
        }
        if action == .background {
            showingBackground = true
        }
    }

    private func confirmSave() {
        if !SceneSaver.isGoodFileName(saveName) {
            saveError = "Illegal symbols"
            return
        }
        do {
            let saved = try SceneSaver.save(
                scene: scene,
                assets: assets,
                backgrounds: backgrounds,
                name: saveName
            )
            lastSavedName = saved
            showingSave = false
            showToast("The project has been saved as  \(saved)")
        } catch {
            showingSave = false
            showToast("error")
        }
    }

    private func showToast(_ text: String) {
        saveToast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveToast == text {
                saveToast = ""
            }
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
                let units = scene.frames[newIndex].units
                if let selectedUnitName, units.contains(where: { $0.name == selectedUnitName }) {
                    self.selectedUnitName = selectedUnitName
                } else {
                    selectedUnitName = nil
                }
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
                if let selectedUnitName, let unit = frame.units.first(where: { $0.name == selectedUnitName }) {
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
                if let index = units.firstIndex(where: { $0.name == newUnit.name }) {
                    scene.frames[frameIndex].units[index] = newUnit
                    selectedUnitName = newUnit.name
                    return
                }
                if let activeName = selectedUnitName,
                   let index = units.firstIndex(where: { $0.name == activeName }) {
                    scene.frames[frameIndex].units[index] = newUnit
                    selectedUnitName = newUnit.name
                    return
                }
                fatalError("SceneEditorScreen frame \(scene.frames[frameIndex].id) missing unit '\(newUnit.name)'")
            }
        )
    }
}

private struct SaveProjectSheet: View {
    @Binding var name: String
    @Binding var error: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save project as")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            TextField("Name", text: $name)
                .font(.system(size: 22))
                .foregroundStyle(.black)
                .tint(.black)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 16))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                Spacer()
                Button("Save", action: onSave)
                    .font(.system(size: 17, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0x85 / 255, green: 0xb8 / 255, blue: 0x39 / 255))
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.15))
        .presentationBackground(Color(white: 0.15))
        .presentationDetents([.medium])
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
