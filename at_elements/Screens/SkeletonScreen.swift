import BonePaper
import SwiftUI

struct SkeletonScreen: View {
    enum Source {
        case custom(CustomItems.Item)
        case template(Item)
        case unit(StickmanUnit)
    }

    let title: String
    let source: Source
    @State private var scene: StickmanScene?
    @State private var assets: UnitAssets?
    /// The archive the item came from. Saving copies non-bone entries; bone PNGs come from live bitmaps.
    @State private var sourceZip: Data?
    @State private var toolsPanel: SkeletonToolsPanel = .bones
    @State private var showingMenu = false
    @State private var boneCreateHoldMode = false
    @State private var selectedPointId: Int?
    @State private var layerEpoch = 0
    @State private var exposeVacantPoints = false
    @State private var showingPreview = false
    @State private var bonePaperEdit: BonePaperEdit?
    @State private var editSession = SkeletonEditSession()
    @State private var canUndo = false
    @State private var canRedo = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    init(item: CustomItems.Item) {
        title = item.name
        source = .custom(item)
    }

    init(template: Item) {
        title = template.humanName
        source = .template(template)
    }

    init(title: String, unit: StickmanUnit) {
        self.title = title
        source = .unit(unit)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let scene, let assets {
                SkeletonCanvas(
                    unit: unitBinding,
                    assets: assets,
                    sceneWidth: scene.width,
                    sceneHeight: scene.height,
                    mode: .skeleton,
                    editSession: editSession,
                    selectedPointId: $selectedPointId,
                    layerEpoch: layerEpoch,
                    exposeVacantPoints: exposeVacantPoints,
                    onPrepareUndo: { prepareUndo() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 0) {
                SkeletonLeftPanel(
                    panel: toolsPanel,
                    onMenu: toggleMenu,
                    onSelect: { next in
                        if next != .bones {
                            setHoldMode(false)
                        }
                        toolsPanel = next
                    },
                    menuActivated: showingMenu,
                    editEnabled: canEditBone,
                    onEdit: openBonePaper,
                    canUndo: canUndo,
                    onUndo: performUndo,
                    canRedo: canRedo,
                    onRedo: performRedo
                )
                if toolsPanel == .bones {
                    SkeletonSecondaryPanel(
                        accent: SkeletonChrome.bonesAccent,
                        content: .bones(
                            onBoneHoldStart: { setHoldMode(true) },
                            onBoneHoldEnd: { setHoldMode(false) },
                            onDelete: deleteSelected,
                            onMoveDown: { moveSelected(up: false) },
                            onMoveUp: { moveSelected(up: true) }
                        )
                    )
                } else if toolsPanel == .draw {
                    SkeletonSecondaryPanel(accent: SkeletonChrome.drawAccent)
                }
                // Keep the open canvas area pass-through for touches under this chrome stack.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if boneCreateHoldMode {
                Text("Hold the button and drag from a point to add a bone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(SkeletonChrome.holdBanner)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, SkeletonChrome.leadingWidth(panel: toolsPanel))
                    .padding(.trailing, SkeletonChrome.galleryWidth(horizontalSizeClass: horizontalSizeClass))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }

            if showingMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showingMenu = false }
                SkeletonSideMenu(
                    onPick: { showingMenu = false },
                    onSaveAs: saveAs,
                    onPreview: openPreview
                )
                .transition(.move(edge: .leading))
            }
        }
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(
                besideMainPanel: false,
                extraLeading: SkeletonChrome.leadingWidth(panel: toolsPanel),
                action: {
                    if showingMenu {
                        showingMenu = false
                    } else {
                        dismiss()
                    }
                }
            )
        }
        .overlay(alignment: .trailing) {
            if scene != nil, assets != nil {
                BonesGalleryPanel(
                    bones: galleryBones,
                    highlightedBmName: highlightedBmName,
                    onNewBone: createNewGalleryBone,
                    onAttach: attachBone
                )
            }
        }
        .background(SkeletonCanvas.checkerLight)
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .ignoresSafeArea()
        .accessibilityLabel(title)
        .onAppear(perform: loadIfNeeded)
        .fullScreenCover(isPresented: $showingPreview) {
            previewScreen
        }
        .fullScreenCover(item: $bonePaperEdit) { session in
            BonePaperScreen(
                source: session.source,
                boneStart: session.boneStart,
                boneTip: session.boneTip,
                onion: session.onion,
                onApply: { export in
                    applyBonePaper(bmName: session.bmName, export: export)
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var galleryBones: [UnitAssets.GalleryBone] {
        _ = layerEpoch
        guard let assets, let unit = optionalUnit else { return [] }
        return assets.galleryBones(unitName: unit.name)
    }

    private var highlightedBmName: String? {
        _ = layerEpoch
        guard let assets, let unit = optionalUnit, let id = selectedPointId else { return nil }
        guard let edge = unit.upperEdge(of: id) else { return nil }
        return assets.bmName(forEdge: edge.from, end: edge.to, unitName: unit.name)
    }

    private var canEditBone: Bool {
        guard let unit = optionalUnit, let id = selectedPointId else { return false }
        return unit.upperEdge(of: id) != nil
    }

    private struct BonePaperEdit: Identifiable {
        let id = UUID()
        let source: CGImage
        let boneStart: CGPoint
        let boneTip: CGPoint
        let onion: CGImage?
        let bmName: String
    }

    private func openBonePaper() {
        guard let unit = optionalUnit, let assets else {
            fatalError("SkeletonScreen '\(title)' edit with no unit")
        }
        guard let id = selectedPointId, let edge = unit.upperEdge(of: id) else {
            fatalError("SkeletonScreen '\(title)' edit with no selected edge")
        }
        let from = unit.point(id: edge.from)
        let to = unit.point(id: edge.to)
        if unit.scale <= 0 {
            fatalError("SkeletonScreen '\(title)' scale is \(unit.scale)")
        }
        // PNG offsets are item-pixel units. Scene points already include unit.scale
        // (Android skeleton editor stores unscaled model coords, so getLength() is 1:1).
        let length = hypot(to.x - from.x, to.y - from.y) / unit.scale
        let asset = assets.ensureDrawable(
            start: edge.from,
            end: edge.to,
            unitName: unit.name,
            length: length
        )
        let start = CGPoint(x: -asset.xOffset, y: -asset.yOffset)
        let onion = SkeletonOnion.worldOverlay(
            unit: unit,
            assets: assets,
            excludeFrom: edge.from,
            excludeTo: edge.to,
            worldSize: BonePaperScreen.worldSide,
            pngWidth: asset.bitmap.width,
            pngHeight: asset.bitmap.height,
            boneStartPNG: start
        )
        layerEpoch += 1
        presentBonePaper(asset: asset, length: length, onion: onion)
    }

    /// Android gallery NEW BONE: dummy picture at `DEFAULT_LENGTH`, then Kurwa with pen.
    private func createNewGalleryBone() {
        guard let unit = optionalUnit, let assets else {
            fatalError("SkeletonScreen '\(title)' new bone with no unit")
        }
        prepareUndo(includeAssets: true)
        let length = UnitAssets.defaultBoneLength
        let asset = assets.createEmptyGalleryBone(unitName: unit.name, length: length)
        layerEpoch += 1
        presentBonePaper(asset: asset, length: length, onion: nil)
    }

    private func presentBonePaper(asset: UnitAssets.EdgeAsset, length: CGFloat, onion: CGImage?) {
        if asset.bitmap.width < 1 || asset.bitmap.height < 1 {
            fatalError("SkeletonScreen '\(title)' bone '\(asset.bmName)' size \(asset.bitmap.width)x\(asset.bitmap.height)")
        }
        let start = CGPoint(x: -asset.xOffset, y: -asset.yOffset)
        let tip = CGPoint(x: length - asset.xOffset, y: -asset.yOffset)
        bonePaperEdit = BonePaperEdit(
            source: asset.bitmap,
            boneStart: start,
            boneTip: tip,
            onion: onion,
            bmName: asset.bmName
        )
    }

    private func applyBonePaper(bmName: String, export: BonePaperExport) {
        guard let assets else {
            fatalError("SkeletonScreen '\(title)' apply with no assets")
        }
        prepareUndo(includeAssets: true)
        assets.replaceBitmap(
            bmName: bmName,
            image: export.image,
            extraLeft: export.extraLeft,
            extraTop: export.extraTop
        )
        layerEpoch += 1
    }

    private func setHoldMode(_ on: Bool) {
        editSession.boneCreateHoldMode = on
        boneCreateHoldMode = on
    }

    private func attachBone(_ bmName: String) {
        guard var unit = optionalUnit, let assets else { return }
        guard let parentId = selectedPointId else {
            pulseVacantPoints()
            return
        }
        prepareUndo(includeAssets: true)
        let newId = unit.addGalleryBonePoint(parentId: parentId, length: UnitAssets.defaultBoneLength)
        assets.attachBone(bmName: bmName, toEdge: parentId, end: newId, unitName: unit.name)
        writeUnit(unit)
        selectedPointId = newId
        editSession.select(newId)
        layerEpoch += 1
    }

    /// Android Handler pulse: on 0, off 200, on 400, off 600.
    private func pulseVacantPoints() {
        Task { @MainActor in
            let steps: [(Bool, UInt64)] = [
                (true, 0),
                (false, 200_000_000),
                (true, 200_000_000),
                (false, 200_000_000),
            ]
            for (on, delay) in steps {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                exposeVacantPoints = on
                editSession.setExposeVacantPoints(on)
            }
        }
    }

    private func deleteSelected() {
        guard var unit = optionalUnit, let id = selectedPointId else { return }
        if unit.point(id: id).isBase {
            return
        }
        prepareUndo(includeAssets: true)
        unit.deletePointSubtree(id: id)
        selectedPointId = nil
        writeUnit(unit)
        layerEpoch += 1
    }

    private func moveSelected(up: Bool) {
        guard let unit = optionalUnit, let id = selectedPointId, let assets else { return }
        guard let edge = unit.upperEdge(of: id) else { return }
        prepareUndo(includeAssets: true)
        if assets.moveEdgeOrder(unitName: unit.name, start: edge.from, end: edge.to, moveUp: up) {
            layerEpoch += 1
        }
    }

    private var optionalUnit: StickmanUnit? {
        guard let scene, !scene.currentFrame.units.isEmpty else { return nil }
        return scene.currentFrame.units[0]
    }

    private func captureUndoEntry(includeAssets: Bool) -> SkeletonUndo.Entry? {
        guard let unit = optionalUnit else {
            return nil
        }
        let snap: UnitAssets.Snapshot?
        if includeAssets {
            guard let assets else {
                return nil
            }
            snap = assets.snapshot()
        } else {
            snap = nil
        }
        return SkeletonUndo.Entry(unit: unit, selectedPointId: selectedPointId, assets: snap)
    }

    private func applyUndoEntry(_ entry: SkeletonUndo.Entry) {
        if let snap = entry.assets {
            guard let assets else {
                fatalError("SkeletonScreen '\(title)' undo with no assets")
            }
            assets.restore(snap)
        }
        writeUnit(entry.unit)
        selectedPointId = entry.selectedPointId
        editSession.select(entry.selectedPointId)
        layerEpoch += 1
    }

    private func prepareUndo(includeAssets: Bool = false) {
        guard let entry = captureUndoEntry(includeAssets: includeAssets) else {
            return
        }
        editSession.undo.push(unit: entry.unit, selectedPointId: entry.selectedPointId, assets: entry.assets)
        refreshUndoChrome(async: true)
    }

    private func performUndo() {
        guard let previous = editSession.undo.peek() else {
            return
        }
        guard let current = captureUndoEntry(includeAssets: previous.assets != nil) else {
            return
        }
        _ = editSession.undo.pop()
        editSession.undo.setRedo(current)
        applyUndoEntry(previous)
        refreshUndoChrome(async: false)
    }

    private func performRedo() {
        guard let next = editSession.undo.takeRedo() else {
            return
        }
        guard let current = captureUndoEntry(includeAssets: next.assets != nil) else {
            editSession.undo.setRedo(next)
            return
        }
        editSession.undo.push(unit: current.unit, selectedPointId: current.selectedPointId, assets: current.assets)
        applyUndoEntry(next)
        refreshUndoChrome(async: false)
    }

    private func refreshUndoChrome(async: Bool) {
        let nextUndo = editSession.undo.canUndo
        let nextRedo = editSession.undo.canRedo
        if canUndo == nextUndo && canRedo == nextRedo {
            return
        }
        let apply = {
            canUndo = nextUndo
            canRedo = nextRedo
        }
        if async {
            DispatchQueue.main.async(execute: apply)
        } else {
            apply()
        }
    }

    private func writeUnit(_ unit: StickmanUnit) {
        guard var loaded = scene else {
            fatalError("SkeletonScreen '\(title)' has no scene loaded")
        }
        let frameIndex = loaded.currentIndex
        loaded.frames[frameIndex].units[0] = unit
        scene = loaded
    }

    private func toggleMenu() {
        showingMenu.toggle()
    }

    private func openPreview() {
        showingMenu = false
        guard scene != nil, assets != nil else {
            fatalError("SkeletonScreen '\(title)' preview before load")
        }
        showingPreview = true
    }

    private var previewScreen: SkeletonPreviewScreen {
        guard let scene, let assets else {
            fatalError("SkeletonScreen '\(title)' preview cover with no scene")
        }
        if scene.currentFrame.units.isEmpty {
            fatalError("SkeletonScreen '\(title)' preview with no unit")
        }
        return SkeletonPreviewScreen(
            unit: scene.currentFrame.units[0],
            assets: assets,
            sceneWidth: scene.width,
            sceneHeight: scene.height
        )
    }

    private func saveAs() {
        showingMenu = false
        guard let scene else {
            fatalError("SkeletonScreen '\(title)' save before load")
        }
        guard let sourceZip else {
            fatalError("SkeletonScreen '\(title)' has no source archive to save from")
        }
        guard let assets else {
            fatalError("SkeletonScreen '\(title)' has no assets to save")
        }
        let unit = scene.currentFrame.units[0]
        let name = ItemSaver.freeName()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ItemSaver.save(unit: unit, assets: assets, source: sourceZip, name: name)
            } catch {
                fatalError("SkeletonScreen could not save '\(name)': \(error)")
            }
        }
    }

    private func loadIfNeeded() {
        if scene != nil {
            return
        }
        let source = source
        DispatchQueue.global(qos: .userInitiated).async {
            let built = Self.load(source)
            DispatchQueue.main.async {
                scene = built.scene
                assets = built.assets
                sourceZip = built.zip
            }
        }
    }

    private struct Loaded {
        var scene: StickmanScene
        var assets: UnitAssets
        var zip: Data?
    }

    private static func load(_ source: Source) -> Loaded {
        switch source {
        case .custom(let item):
            let zip: Data
            do {
                zip = try Data(contentsOf: item.url)
            } catch {
                fatalError("SkeletonScreen could not read \(item.url.path): \(error)")
            }
            return build(zip: zip, defaultScale: 1)
        case .template(let template):
            return build(
                zip: Manifest.shared.itemZip(fullname: template.makeFullName()),
                defaultScale: template.scale
            )
        case .unit(let unit):
            return Loaded(scene: ItemConstructor.scene(unit: unit), assets: UnitAssets(), zip: nil)
        }
    }

    private static func build(zip: Data, defaultScale: CGFloat) -> Loaded {
        let unit = ItemLoader.unit(from: zip)
        let assets = UnitAssets()
        // A skeleton with no bone pictures yet is a valid state here, so assets.xml may be absent.
        if ZipStore.contains("assets.xml", in: zip) {
            assets.loadItemFromArchive(
                zip,
                entryName: UnitAssets.atiEntryName(for: unit.name),
                forceReload: false
            )
        }
        var scale = defaultScale
        if ZipStore.contains("meta.txt", in: zip) {
            let atiScale = ItemMeta.scale(from: ZipStore.data(named: "meta.txt", in: zip))
            if atiScale > 0.01 {
                scale = atiScale
            }
        }
        return Loaded(scene: ItemConstructor.scene(unit: unit, scale: scale), assets: assets, zip: zip)
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                guard let scene else {
                    fatalError("SkeletonScreen '\(title)' has no scene loaded")
                }
                let frame = scene.currentFrame
                if frame.units.isEmpty {
                    fatalError("StickmanScene frame \(frame.id) has no units")
                }
                return frame.units[0]
            },
            set: { newUnit in
                guard var loaded = scene else {
                    fatalError("SkeletonScreen '\(title)' has no scene loaded")
                }
                let frameIndex = loaded.currentIndex
                if loaded.frames[frameIndex].units.isEmpty {
                    fatalError("StickmanScene frame \(loaded.frames[frameIndex].id) has no units")
                }
                loaded.frames[frameIndex].units[0] = newUnit
                scene = loaded
            }
        )
    }
}

#Preview {
    NavigationStack {
        SkeletonScreen(title: "Skeleton", unit: ItemConstructor.spider())
    }
}
