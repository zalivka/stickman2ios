import BonePaper
import SwiftUI
import UIKit

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
    @State private var showingSpeedEffects = false
    @State private var showingTweenRange = false
    @State private var showingTweenEasing = false
    @State private var tweenDraftRange: ClosedRange<Int> = 0...0
    @State private var tweenApplyRange: ClosedRange<Int>?
    @State private var showingInsert = false
    @State private var showingEditUnit = false
    @State private var editUnitBackTick = 0
    @State private var showingEditFrame = false
    @State private var showingMenu = false
    @State private var scenePropsSheet: ScenePropsSheet?
    @State private var selectedUnitName: String?
    @State private var capturedUnitName: String?
    @State private var showingSave = false
    @State private var saveName = ""
    @State private var saveError = ""
    @State private var lastSavedName: String?
    @State private var saveToast = ""
    @State private var showingFBF = false
    @State private var showingAdvanced = false
    @State private var showingSetText = false
    @State private var setTextDraft = ""
    @State private var setTextColor = Color.black
    @State private var setTextError = ""
    @State private var showingLeaveAlert = false
    @State private var dismissAfterSave = false
    @State private var savedDocument: Data
    @StateObject private var clipboard = CopyPasteBuffer()
    @StateObject private var undo = SceneUndo()
    @State private var frameInsertFlash = 0
    @Environment(\.dismiss) private var dismiss

    init(scene: StickmanScene, assets: UnitAssets, backgrounds: BackgroundAssets = BackgroundAssets()) {
        if scene.frames.isEmpty {
            fatalError("SceneEditorScreen has no frames")
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
        _tweenDraftRange = State(
            initialValue: RangePicker.suggestedTweenRange(
                current: scene.currentIndex,
                frameCount: scene.frames.count
            )
        )
        _selectedUnitName = State(initialValue: nil)
        _savedDocument = State(initialValue: SceneSaver.documentBytes(scene: scene))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    onInsert: toggleInsert,
                    onEditUnit: toggleEditUnit,
                    onEditFrame: toggleEditFrame,
                    onUndo: performUndo,
                    undoEnabled: undo.canUndo,
                    onMenu: toggleMenu,
                    insertActivated: showingInsert,
                    editUnitActivated: showingEditUnit,
                    editFrameActivated: showingEditFrame,
                    menuActivated: showingMenu
                )
                SkeletonCanvas(
                    unit: scene.currentFrame.units.isEmpty ? nil : unitBinding,
                    frameUnits: scene.currentFrame.units,
                    assets: assets,
                    backgrounds: backgrounds,
                    bgName: scene.currentFrame.bgName,
                    bgMove: scene.currentFrame.bgMove,
                    cameraMove: scene.currentFrame.cameraMove,
                    sceneWidth: scene.width,
                    sceneHeight: scene.height,
                    currentIndex: scene.currentIndex,
                    selectedUnitName: $selectedUnitName,
                    capturedUnitName: $capturedUnitName,
                    onPrepareUndo: prepareSelectionUndo,
                    canMutatePoseFor: { name in
                        !scene.isPoseLocked(unitName: name, frameIndex: scene.currentIndex)
                    },
                    onLockedEdit: { showToast("Locked") },
                    onPoseEditEnded: {
                        retweenSelectedAfterPoseEdit(frames: [scene.currentIndex])
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SkeletonCanvas.pane)
            }
            if showingInsert {
                ItemChooserPanel(onPick: insert, onClose: { showingInsert = false })
                    .padding(.leading, MainPanel.width)
            }
            if showingEditFrame {
                FrameOpsPanel(
                    canDelete: scene.canDeleteFrames(at: rearrangeFrames),
                    canPaste: clipboard.hasFrames,
                    onAdd: addFrame,
                    onDelete: deleteSelectedFrames,
                    onCopy: copySelectedFrames,
                    onPaste: pasteFrames
                )
                .padding(.leading, MainPanel.width)
            }
            if showingEditUnit {
                Group {
                    if let selectedUnit {
                        UnitPropertiesPanel(
                            unit: selectedUnit,
                            assets: assets,
                            availableStates: assets.states(for: selectedUnit.name),
                            animationActive: fbfActive(for: selectedUnit.name),
                            onDeselect: { selectedUnitName = nil },
                            onDelete: deleteSelectedUnit,
                            onFlip: flipSelectedUnit,
                            onDetach: detachSelectedUnit,
                            onMoveForward: { moveSelectedUnit(forward: true) },
                            onMoveBackward: { moveSelectedUnit(forward: false) },
                            canMoveForward: canMoveSelectedUnit(forward: true),
                            canMoveBackward: canMoveSelectedUnit(forward: false),
                            onSelectState: setSelectedUnitState,
                            onOpenAnimation: { showingFBF = true },
                            onCopy: copySelectedUnit,
                            onSetText: selectedUnit.unitType == .bubble ? { openSetText() } : nil,
                            poseLocked: scene.isPoseLocked(
                                unitName: selectedUnit.name,
                                frameIndex: scene.currentIndex
                            ),
                            structureOwned: scene.isStructureLocked(
                                unitName: selectedUnit.name,
                                frameIndex: scene.currentIndex
                            ),
                            tweenEnabled: tweenButtonEnabled(for: selectedUnit),
                            onTween: openTweenRange,
                            onMore: { showingAdvanced = true },
                            onOpacityDragBegan: prepareSelectionUndo,
                            onOpacityPreview: previewSelectedOpacity,
                            onOpacityCommit: commitSelectedOpacity,
                            backTick: editUnitBackTick,
                            onClose: { showingEditUnit = false }
                        )
                    } else {
                        PresentUnitsPanel(
                            units: scene.currentFrame.units,
                            selectedName: nil,
                            assets: assets,
                            onSelect: { selectedUnitName = $0 },
                            onMove: movePresentUnits,
                            canPaste: clipboard.hasUnits,
                            onPaste: pasteUnits
                        )
                    }
                }
                .padding(.leading, MainPanel.width)
            }
            if showingMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .padding(.leading, MainPanel.width)
                    .onTapGesture { showingMenu = false }
                SideMenu(onPick: pickMenu)
                    .padding(.leading, MainPanel.width)
                    .transition(.move(edge: .leading))
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $mode,
                onEnterRange: {
                    undo.commitEnteringRange(from: scene, indices: Array(range))
                },
                onLeaveRange: {
                    undo.clearRangeBaseline()
                },
                onNextAtEnd: addFrame,
                onHoldCopy: copyHeldStructure,
                flashToken: frameInsertFlash,
                stickStyle: tweenStickStyle
            )
        }
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .onChange(of: range) { _, _ in
            if mode == .range {
                undo.commitEnteringRange(from: scene, indices: Array(range))
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if let chip = selectedUnitTweenSpan {
                HStack(spacing: 0) {
                    Button {
                        openTweenEasing(for: chip)
                    } label: {
                        Text(chip.easingType.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 40)
                    }
                    .background(chip.easingType.chipColor)
                    Button {
                        deleteSelectedTween()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .background(Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 10)
            }
        }
        .overlay(alignment: .topLeading) {
            if !showingInsert {
                FullscreenBackButton(
                    extraLeading: backExtraLeading,
                    action: screenBack
                )
            }
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
        .fullScreenCover(isPresented: $showingSpeedEffects) {
            SpeedEffectsScreen(scene: $scene, assets: assets, backgrounds: backgrounds)
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
                onCancel: cancelSave,
                onSave: confirmSave
            )
        }
        .alert(leaveAlertTitle, isPresented: $showingLeaveAlert) {
            Button("Save") { saveFromLeave() }
            Button("Don't Save", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you don't save, your changes will be lost.")
        }
        .sheet(isPresented: $showingFBF) {
            if let selectedUnit {
                FBFAnimationSheet(
                    unitName: selectedUnit.name,
                    scene: scene,
                    assets: assets,
                    unit: selectedUnit,
                    existing: scene.unitAnimations[selectedUnit.name]
                ) { next in
                    if let next {
                        scene.unitAnimations[selectedUnit.name] = next
                    } else {
                        scene.unitAnimations.removeValue(forKey: selectedUnit.name)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdvanced) {
            if let selectedUnit {
                AdvancedUnitSheet(currentNumber: UnitName.number(selectedUnit.name)) { number in
                    applyUnitNumber(number)
                }
            }
        }
        .sheet(isPresented: $showingSetText) {
            SetTextSheet(
                text: $setTextDraft,
                color: $setTextColor,
                error: $setTextError,
                onCancel: { showingSetText = false },
                onApply: applySetText
            )
        }
        .sheet(isPresented: $showingTweenRange) {
            RangePicker(
                title: "Tweening",
                frameCount: scene.frames.count,
                initialRange: tweenDraftRange,
                preview: { index in
                    AnyView(
                        RangeFramePreview(
                            scene: scene,
                            index: index,
                            assets: assets,
                            backgrounds: backgrounds
                        )
                    )
                },
                canApply: canApplyTween(range:),
                onApply: { next in
                    showingTweenRange = false
                    tweenApplyRange = next
                    showingTweenEasing = true
                }
            )
            .id("\(tweenDraftRange.lowerBound):\(tweenDraftRange.upperBound):\(scene.frames.count)")
        }
        .sheet(isPresented: $showingTweenEasing) {
            let span = tweenEasingInitial
            EasingChoiceSheet(
                initialType: span.type,
                initialStrength: span.strength,
                initialFrequency: span.frequency,
                onApply: applyTweenEasing
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
            showingEditFrame = false
        }
    }

    private func toggleInsert() {
        showingInsert.toggle()
        if showingInsert {
            showingMenu = false
            showingEditUnit = false
            showingEditFrame = false
        }
    }

    private func toggleEditUnit() {
        showingEditUnit.toggle()
        if showingEditUnit {
            showingMenu = false
            showingInsert = false
            showingEditFrame = false
        }
    }

    private func toggleEditFrame() {
        showingEditFrame.toggle()
        if showingEditFrame {
            showingMenu = false
            showingInsert = false
            showingEditUnit = false
        }
    }

    /// Android list is arrange-desc; after move, arrange = count-1-index.
    private func movePresentUnits(from: IndexSet, to: Int) {
        prepareSelectionUndo()
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
        prepareSelectionUndo()
        for frameIndex in rearrangeFrames where scene.frames[frameIndex].units.contains(where: { $0.name == selectedUnitName }) {
            scene.breakTweensTouching(unitName: selectedUnitName, frameIndex: frameIndex)
            scene.frames[frameIndex].deleteConnectedUnit(named: selectedUnitName)
        }
        self.selectedUnitName = nil
    }

    private func setSelectedUnitState(_ state: Int) {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen set state without selected unit")
        }
        if rearrangeFrames.contains(where: { scene.isPoseLocked(unitName: selectedUnitName, frameIndex: $0) }) {
            showToast("Locked")
            return
        }
        prepareSelectionUndo()
        for frameIndex in rearrangeFrames {
            guard let index = scene.frames[frameIndex].units.firstIndex(where: { $0.name == selectedUnitName }) else {
                continue
            }
            scene.frames[frameIndex].units[index].assetsState = state
        }
    }

    private func fbfActive(for name: String) -> Bool {
        guard let animation = scene.unitAnimations[name] else { return false }
        return animation.inRange(scene: scene, index: scene.currentIndex)
    }

    private func previewSelectedOpacity(_ alpha: CGFloat) {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen opacity preview without selected unit")
        }
        scene.frames[scene.currentIndex].setUnitAlpha(alpha, unitNamed: selectedUnitName)
    }

    /// Android seek-up: snap under 5% to 0, write the selected frames, rebake AUTO.
    /// An interior lock leaves the live preview and returns false.
    private func commitSelectedOpacity(_ alpha: CGFloat) -> Bool {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen opacity commit without selected unit")
        }
        if let locked = rearrangeFrames.first(where: {
            scene.unitTweens.isPoseLocked(unitName: selectedUnitName, frameIndex: $0)
        }) {
            showToast(scene.unitTweens.poseLockMessage(unitName: selectedUnitName, frameIndex: locked))
            return false
        }
        for frameIndex in rearrangeFrames
        where scene.frames[frameIndex].units.contains(where: { $0.name == selectedUnitName }) {
            scene.frames[frameIndex].setUnitAlpha(alpha, unitNamed: selectedUnitName)
        }
        retweenSelectedAfterPoseEdit(frames: rearrangeFrames)
        return true
    }

    /// Android `AdvancedUnitProperties` number picker. Returns false when the number is taken.
    private func applyUnitNumber(_ number: Int) -> Bool {
        guard let oldName = selectedUnitName else {
            fatalError("SceneEditorScreen unit number without selected unit")
        }
        let newName = UnitName.withNumber(oldName, number)
        if newName == oldName {
            return true
        }
        for frameIndex in rearrangeFrames {
            let units = scene.frames[frameIndex].units
            if units.contains(where: { $0.name == oldName }) && units.contains(where: { $0.name == newName }) {
                showToast("Number \(number) already used on a frame")
                return false
            }
        }
        undo.commitTimeline(from: scene)
        for frameIndex in rearrangeFrames where scene.frames[frameIndex].units.contains(where: { $0.name == oldName }) {
            scene.frames[frameIndex].renameUnit(from: oldName, to: newName)
        }
        let stillHasOld = scene.frames.contains { $0.units.contains { $0.name == oldName } }
        if !stillHasOld, var animation = scene.unitAnimations.removeValue(forKey: oldName) {
            if scene.unitAnimations[newName] != nil {
                fatalError("SceneEditorScreen animation already exists for '\(newName)'")
            }
            animation.unitname = newName
            scene.unitAnimations[newName] = animation
        }
        selectedUnitName = newName
        if capturedUnitName == oldName {
            capturedUnitName = newName
        }
        return true
    }

    private func flipSelectedUnit() {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen flip without selected unit")
        }
        if rearrangeFrames.contains(where: { scene.isPoseLocked(unitName: selectedUnitName, frameIndex: $0) }) {
            showToast("Locked")
            return
        }
        prepareSelectionUndo()
        for frameIndex in rearrangeFrames {
            guard scene.frames[frameIndex].units.contains(where: { $0.name == selectedUnitName }) else {
                continue
            }
            scene.frames[frameIndex].flipUnit(named: selectedUnitName)
        }
        retweenSelectedAfterPoseEdit(frames: rearrangeFrames)
    }

    private func detachSelectedUnit() {
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen detach without selected unit")
        }
        if rearrangeFrames.contains(where: { scene.isStructureLocked(unitName: selectedUnitName, frameIndex: $0) }) {
            showToast("Locked")
            return
        }
        prepareSelectionUndo()
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
        prepareSelectionUndo()
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

    /// Android `MainEditor.copyTouchHeldStructureToFrameIfNoConflicts`.
    private func copyHeldStructure(from sourceIndex: Int, to destIndex: Int) {
        guard let capturedUnitName else {
            return
        }
        if sourceIndex < 0 || sourceIndex >= scene.frames.count {
            fatalError("SceneEditorScreen hold-copy source \(sourceIndex) out of \(scene.frames.count)")
        }
        if destIndex < 0 || destIndex >= scene.frames.count {
            fatalError("SceneEditorScreen hold-copy dest \(destIndex) out of \(scene.frames.count)")
        }
        let source = scene.frames[sourceIndex]
        guard let captured = source.units.first(where: { $0.name == capturedUnitName }) else {
            fatalError("SceneEditorScreen captured '\(capturedUnitName)' missing on source frame \(sourceIndex)")
        }
        let root = SlavesRegistry.rootMaster(of: captured, in: source.units)
        if scene.isPoseLocked(unitName: capturedUnitName, frameIndex: destIndex) {
            showToast("Locked")
            return
        }
        scene.ensureStructureOnRange(root: root, in: source.units, range: destIndex...destIndex)
        if scene.frames[destIndex].units.contains(where: { $0.name == capturedUnitName }) {
            selectedUnitName = capturedUnitName
        } else {
            selectedUnitName = nil
            self.capturedUnitName = nil
        }
    }

    private func addFrame() {
        let currentIndex = scene.currentIndex
        let animations = scene.unitAnimations
        let tweens = scene.unitTweens
        let cameraTweens = scene.cameraTweens
        scene.addFrame()
        undo.commitFramesInserted(
            ids: [scene.currentFrame.id],
            currentIndex: currentIndex,
            animations: animations,
            tweens: tweens,
            cameraTweens: cameraTweens
        )
        collapseRangeToCurrent()
        frameInsertFlash += 1
    }

    private func deleteSelectedFrames() {
        let indices = rearrangeFrames
        if !scene.canDeleteFrames(at: indices) {
            return
        }
        let deleted = indices.map { scene.frames[$0].clone() }
        let at = indices.min()!
        let currentIndex = scene.currentIndex
        let animations = scene.unitAnimations
        let tweens = scene.unitTweens
        let cameraTweens = scene.cameraTweens
        scene.removeFrames(at: indices)
        undo.commitFramesDeleted(
            frames: deleted,
            at: at,
            currentIndex: currentIndex,
            animations: animations,
            tweens: tweens,
            cameraTweens: cameraTweens
        )
        collapseRangeToCurrent()
        let names = Set(scene.currentFrame.units.map(\.name))
        if let selectedUnitName, !names.contains(selectedUnitName) {
            self.selectedUnitName = nil
        }
        if let capturedUnitName, !names.contains(capturedUnitName) {
            self.capturedUnitName = nil
        }
    }

    private func copySelectedFrames() {
        let indices = rearrangeFrames
        clipboard.copyFrames(from: scene, indices: indices)
        showToast("Copied \(indices.count) frames")
    }

    private func pasteFrames() {
        if !clipboard.hasFrames {
            return
        }
        if scene.wouldPasteSplitTweens() {
            showToast("Can't paste inside a tween span")
            return
        }
        let currentIndex = scene.currentIndex
        let animations = scene.unitAnimations
        let tweens = scene.unitTweens
        let cameraTweens = scene.cameraTweens
        let inserted = clipboard.pasteFrames(into: &scene)
        let ids = inserted.map { scene.frames[$0].id }
        undo.commitFramesInserted(
            ids: ids,
            currentIndex: currentIndex,
            animations: animations,
            tweens: tweens,
            cameraTweens: cameraTweens
        )
        clampRange()
    }

    private func openSetText() {
        guard let selectedUnit else {
            fatalError("SceneEditorScreen set text with no selection")
        }
        guard let bubble = selectedUnit.bubble else {
            fatalError("SceneEditorScreen unit '\(selectedUnit.name)' type=bubble missing meta")
        }
        setTextDraft = bubble.text
        let rgba = bubble.rgba
        setTextColor = Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
        setTextError = ""
        showingSetText = true
    }

    private func applySetText() {
        if setTextDraft.isEmpty {
            setTextError = "Text is empty"
            return
        }
        guard let selectedUnitName else {
            fatalError("SceneEditorScreen set text without selected unit")
        }
        prepareSelectionUndo()
        for frameIndex in rearrangeFrames {
            guard let index = scene.frames[frameIndex].units.firstIndex(where: { $0.name == selectedUnitName }) else {
                continue
            }
            if scene.frames[frameIndex].units[index].unitType != .bubble {
                fatalError("SceneEditorScreen unit '\(selectedUnitName)' is not bubble")
            }
            guard var bubble = scene.frames[frameIndex].units[index].bubble else {
                fatalError("SceneEditorScreen unit '\(selectedUnitName)' bubble missing meta")
            }
            bubble.text = setTextDraft
            bubble.color = Self.bubbleARGB(setTextColor)
            scene.frames[frameIndex].units[index].bubble = bubble
        }
        showingSetText = false
    }

    /// Android `BubbleMeta.setColor` writes `#` + ARGB hex, for example `#ff000000`.
    private static func bubbleARGB(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            guard let converted = ui.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            ) else {
                fatalError("Set text color is not RGB")
            }
            if !UIColor(cgColor: converted).getRed(&r, green: &g, blue: &b, alpha: &a) {
                fatalError("Set text color is not RGB")
            }
        }
        func byte(_ channel: CGFloat) -> Int {
            min(max(Int((channel * 255).rounded()), 0), 255)
        }
        return String(format: "#%02x%02x%02x%02x", byte(a), byte(r), byte(g), byte(b))
    }

    private func copySelectedUnit() {
        guard let selectedUnit else {
            fatalError("SceneEditorScreen copy unit with no selection")
        }
        let connected = SlavesRegistry.allConnected(of: selectedUnit, in: scene.currentFrame.units)
        clipboard.copyUnits(connected)
        selectedUnitName = nil
    }

    private func pasteUnits() {
        if !clipboard.hasUnits {
            return
        }
        prepareSelectionUndo()
        clipboard.pasteUnits(into: &scene, at: rearrangeFrames)
    }

    private func prepareSelectionUndo() {
        if let name = selectedUnitName,
           let span = scene.unitTweens.findContaining(unitName: name, frameIndex: scene.currentIndex)
        {
            undo.commitSelection(from: scene, indices: Array(span.fromFrame...span.toFrame))
            return
        }
        undo.commitSelection(from: scene, indices: rearrangeFrames)
    }

    private func performUndo() {
        if !undo.canUndo {
            return
        }
        undo.restore(into: &scene)
        clampRange()
    }

    private func collapseRangeToCurrent() {
        let index = scene.currentIndex
        range = index...index
        clampRange()
    }

    private func clampRange() {
        let last = scene.frames.count - 1
        if last < 0 {
            fatalError("SceneEditorScreen clampRange empty scene")
        }
        if scene.currentIndex < 0 || scene.currentIndex > last {
            fatalError("SceneEditorScreen currentIndex \(scene.currentIndex) out of \(scene.frames.count)")
        }
        let low = min(max(range.lowerBound, 0), last)
        let high = min(max(range.upperBound, 0), last)
        range = min(low, high)...max(low, high)
    }

    private func pickMenu(_ action: SideMenuAction) {
        print("menu: \(action.rawValue)")
        showingMenu = false
        if action == .save {
            dismissAfterSave = false
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
        if action == .speedEffects {
            if scene.frames.count < 3 {
                showToast("Add more frames first")
                return
            }
            showingSpeedEffects = true
        }
    }

    private var backExtraLeading: CGFloat {
        if showingMenu {
            return SideMenu.width
        }
        if showingInsert {
            return ItemChooserPanel.width
        }
        if showingEditUnit {
            return selectedUnit == nil ? PresentUnitsPanel.width : UnitPropertiesPanel.width
        }
        if showingEditFrame {
            return FrameOpsPanel.width
        }
        return 0
    }

    private func screenBack() {
        if showingEditUnit {
            if selectedUnit == nil {
                showingEditUnit = false
            } else {
                editUnitBackTick += 1
            }
            return
        }
        if showingEditFrame {
            showingEditFrame = false
            return
        }
        goBack()
    }

    private func goBack() {
        if showingMenu {
            showingMenu = false
            return
        }
        if SceneSaver.documentBytes(scene: scene) == savedDocument {
            dismiss()
            return
        }
        showingLeaveAlert = true
    }

    private var leaveAlertTitle: String {
        if let lastSavedName {
            return "Do you want to save the changes to “\(lastSavedName)”?"
        }
        return "Do you want to save the changes to this scene?"
    }

    private func saveFromLeave() {
        dismissAfterSave = true
        if let lastSavedName {
            saveName = lastSavedName
            confirmSave()
            return
        }
        saveError = ""
        saveName = SceneSaver.generateName()
        showingSave = true
    }

    private func cancelSave() {
        dismissAfterSave = false
        showingSave = false
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
            savedDocument = SceneSaver.documentBytes(scene: scene)
            showingSave = false
            if dismissAfterSave {
                dismissAfterSave = false
                dismiss()
                return
            }
            showToast("The project has been saved as  \(saved)")
        } catch {
            showingSave = false
            dismissAfterSave = false
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
        undo.commitSceneProps(from: scene)
        scene.width = draft.width
        scene.height = draft.height
        scene.interframes = draft.interframes
        scene.noInterpolation = draft.noInterpolation
        scene.noInterpolationFrames = draft.noInterpolationFrames
        scenePropsSheet = nil
    }

    private func applySceneSize(_ size: SceneSize) {
        undo.commitSceneProps(from: scene)
        scene.width = size.width
        scene.height = size.height
        scenePropsSheet = nil
    }

    private func insert(_ item: Item) {
        prepareSelectionUndo()
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

    private func tweenButtonEnabled(for unit: StickmanUnit) -> Bool {
        if scene.frames.count < 2 {
            return false
        }
        if SlavesRegistry.isEnslaved(unit) {
            return false
        }
        if scene.isStructureLocked(unitName: unit.name, frameIndex: scene.currentIndex) {
            return false
        }
        return true
    }

    private var selectedUnitTweenSpan: AutoTweenRange? {
        guard let selectedUnit else { return nil }
        return scene.unitTweens.findContaining(unitName: selectedUnit.name, frameIndex: scene.currentIndex)
    }

    private func tweenStickStyle(_ index: Int) -> (color: Color?, scale: CGFloat) {
        guard let selectedUnit else {
            return (nil, 1)
        }
        guard let span = scene.unitTweens.findContaining(unitName: selectedUnit.name, frameIndex: index) else {
            return (nil, 1)
        }
        let scale: CGFloat
        if index == span.fromFrame || index == span.toFrame {
            scale = 1.5
        } else if span.containsInterior(index) {
            scale = 1 / 1.5
        } else {
            scale = 1
        }
        return (span.easingType.chipColor, scale)
    }

    private func openTweenRange() {
        guard let selectedUnit else {
            return
        }
        if SlavesRegistry.isEnslaved(selectedUnit) {
            return
        }
        if scene.frames.count < 2 {
            return
        }
        tweenDraftRange = resolveTweenInitialRange(unitName: selectedUnit.name)
        showingTweenRange = true
    }

    private func resolveTweenInitialRange(unitName: String) -> ClosedRange<Int> {
        if mode == .range, range.upperBound - range.lowerBound >= 2 {
            return range
        }
        if let existing = scene.unitTweens.findContaining(unitName: unitName, frameIndex: scene.currentIndex) {
            return existing.fromFrame...existing.toFrame
        }
        return RangePicker.suggestedTweenRange(current: scene.currentIndex, frameCount: scene.frames.count)
    }

    private func canApplyTween(range: ClosedRange<Int>) -> Bool {
        guard let selectedUnit else {
            return false
        }
        if range.upperBound - range.lowerBound < 2 {
            return false
        }
        let name = rootTweenName(of: selectedUnit)
        if scene.frames[range.lowerBound].units.first(where: { $0.name == name }) == nil {
            return false
        }
        if scene.frames[range.upperBound].units.first(where: { $0.name == name }) == nil {
            return false
        }
        if let intersecting = scene.unitTweens.findIntersecting(
            unitName: name,
            from: range.lowerBound,
            to: range.upperBound
        ), intersecting.fromFrame != range.lowerBound || intersecting.toFrame != range.upperBound {
            return false
        }
        return true
    }

    private var tweenEasingInitial: (type: TweenEasing, strength: Float, frequency: Float) {
        let range = tweenApplyRange ?? tweenDraftRange
        if let selectedUnit,
           let span = scene.unitTweens.findExact(
            unitName: rootTweenName(of: selectedUnit),
            from: range.lowerBound,
            to: range.upperBound
           )
        {
            return (span.easingType, span.easingStrength, span.shakeFrequency)
        }
        return (.NO, Easing.defaultStrength, UnitTweenStorage.defaultShakeFrequency)
    }

    private func openTweenEasing(for span: AutoTweenRange) {
        tweenApplyRange = span.fromFrame...span.toFrame
        showingTweenEasing = true
    }

    private func applyTweenEasing(type: TweenEasing, strength: Float, frequency: Float) {
        guard let selectedUnit else {
            return
        }
        let range = tweenApplyRange ?? tweenDraftRange
        let from = range.lowerBound
        let to = range.upperBound
        if to - from < 2 {
            fatalError("SceneEditorScreen tween range \(from)..\(to) too short")
        }
        let rootName = rootTweenName(of: selectedUnit)
        if !canApplyTween(range: from...to) {
            showToast("Select frames that both contain the unit")
            return
        }
        undo.commitTimeline(from: scene)
        if !UnitInbetweener.propagate(
            scene: &scene,
            rootName: rootName,
            from: from,
            to: to,
            easing: type,
            strength: strength,
            shakeFrequency: frequency
        ) {
            showToast("Can't tween inconsistent items")
            return
        }
        scene.currentIndex = to
        clampRange()
        tweenApplyRange = nil
    }

    private func deleteSelectedTween() {
        guard let selectedUnit else {
            return
        }
        if scene.unitTweens.findContaining(unitName: selectedUnit.name, frameIndex: scene.currentIndex) == nil {
            return
        }
        undo.commitTimeline(from: scene)
        if scene.removeUnitTweenContaining(unitName: selectedUnit.name, frameIndex: scene.currentIndex) != nil {
            showToast("Tweening removed")
        }
    }

    private func retweenSelectedAfterPoseEdit(frames: [Int]) {
        guard let selectedUnit else {
            return
        }
        let root = SlavesRegistry.rootMaster(of: selectedUnit, in: scene.currentFrame.units)
        scene.retweenEndpoints(unitName: root.name, frames: frames)
    }

    private func rootTweenName(of unit: StickmanUnit) -> String {
        SlavesRegistry.rootMaster(of: unit, in: scene.currentFrame.units).name
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

private struct SetTextSheet: View {
    @Binding var text: String
    @Binding var color: Color
    @Binding var error: String
    var onCancel: () -> Void
    var onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Text")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SkeletonChrome.toolLabel)
                        .textCase(.uppercase)
                    TextField("Text", text: $text, axis: .vertical)
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                        .tint(.black)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .lineLimit(1...6)
                    Text("Color")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SkeletonChrome.toolLabel)
                        .textCase(.uppercase)
                    BonePaperColorRow(color: $color)
                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackCircleButton(action: onCancel)
                Text("Set text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onApply) {
                    Text("Apply")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .background(SkeletonChrome.boneNew)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }
}

private struct SaveProjectSheet: View {
    @Binding var name: String
    @Binding var error: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Name")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SkeletonChrome.toolLabel)
                        .textCase(.uppercase)
                    TextField("Name", text: $name)
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                        .tint(.black)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BackCircleButton(action: onCancel)
                Text("Save project as")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .background(SkeletonChrome.boneNew)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
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
