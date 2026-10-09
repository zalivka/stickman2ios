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
    @State private var shiftHoldMode = false
    @State private var toast = ""
    @State private var selectedPointId: Int?
    @State private var layerEpoch = 0
    @State private var exposeVacantPoints = false
    @State private var previewTicket: PreviewTicket?
    @State private var showingSettings = false
    @State private var showingSave = false
    @State private var bonePaperEdit: BonePaperEdit?
    @State private var editSession = SkeletonEditSession()
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var pointProps: PointPropsEdit?
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
                    onPrepareUndo: { prepareUndo() },
                    onApplyBoneShift: applyBoneShift
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
                        if next != .draw {
                            setShiftHold(false)
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
                            onProps: openPointProps,
                            canProps: selectedPointId != nil,
                            onDelete: deleteSelected,
                            onMoveDown: { moveSelected(up: false) },
                            onMoveUp: { moveSelected(up: true) }
                        )
                    )
                } else if toolsPanel == .draw {
                    SkeletonSecondaryPanel(
                        accent: SkeletonChrome.drawAccent,
                        content: .draw(
                            onShiftHoldStart: { setShiftHold(true) },
                            onShiftHoldEnd: { setShiftHold(false) },
                            onClear: clearArtwork
                        )
                    )
                }
                // Keep the open canvas area pass-through for touches under this chrome stack.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !toast.isEmpty {
                Text(toast)
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

            if showingMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showingMenu = false }
                SkeletonSideMenu(
                    onSaveAs: saveAs,
                    onPreview: openPreview,
                    onSettings: openSettings
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
                    onAttach: attachBone,
                    onEdit: editGalleryBone
                )
                .paddingTrailingIsland()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let banner = holdBannerText {
                Text(banner)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(SkeletonChrome.holdBanner)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(SkeletonCanvas.checkerLight)
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .modifier(StatusBarClearance())
        .accessibilityLabel(title)
        .onAppear(perform: loadIfNeeded)
        .fullScreenCover(item: $previewTicket) { _ in
            previewScreen
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsSheet()
        }
        .sheet(isPresented: $showingSave) {
            SkeletonSaveScreen(
                onClose: { showingSave = false },
                onSaveNew: { name in
                    saveItem(name: name) {
                        showingSave = false
                        showToast("Saved!")
                    }
                },
                onOverwrite: { item in
                    saveItem(name: item.systemName) {
                        showingSave = false
                        showToast("Saved!")
                    }
                }
            )
        }
        .fullScreenCover(item: $bonePaperEdit) { session in
            BonePaperScreen(
                source: session.source,
                boneStart: session.boneStart,
                boneTip: session.boneTip,
                onion: session.onion,
                placement: session.placement,
                buffer: session.buffer,
                onApply: { export in
                    applyBonePaper(bmName: session.bmName, export: export)
                },
                onClose: session.placement == nil ? nil : {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        bonePaperEdit = nil
                    }
                }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $pointProps) { draft in
            EditPointDialog(
                isBase: draft.isBase,
                attachable: draft.attachable,
                fixed: draft.fixed
            ) { attachable, fixed in
                applyPointProps(id: draft.pointId, attachable: attachable, fixed: fixed)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        /// Decoded paint buffer for `source`, validated at open. Nil opens from the upscaled 1x path.
        let buffer: CGImage?
        let boneStart: CGPoint
        let boneTip: CGPoint
        let onion: CGImage?
        let placement: BonePaperPlacement?
        let bmName: String
    }

    /// Present-attempt marker: existence means the fatal preview guards already passed.
    private struct PreviewTicket: Identifiable {
        let id = UUID()
    }

    private struct PointPropsEdit: Identifiable {
        var id: Int { pointId }
        let pointId: Int
        let isBase: Bool
        let attachable: Attachable
        let fixed: Bool
    }

    private func openBonePaper() {
        guard let unit = optionalUnit else {
            bail("edit with no unit")
            return
        }
        guard let id = selectedPointId, let edge = unit.upperEdge(of: id) else {
            bail("edit with no selected edge")
            return
        }
        openBonePaper(from: edge.from, to: edge.to)
    }

    /// Android gallery long-press Edit: Kurwa for that picture; onion if some edge uses it.
    private func editGalleryBone(_ bmName: String) {
        guard let unit = optionalUnit, let assets else {
            bail("gallery edit with no unit")
            return
        }
        if bmName.isEmpty {
            bail("gallery edit empty bmName")
            return
        }
        if let ends = assets.firstEdgeUsing(bmName: bmName, unitName: unit.name) {
            openBonePaper(from: ends.start, to: ends.end)
            return
        }
        guard let asset = assets.firstAsset(bmName: bmName, unitName: unit.name) else {
            bail("gallery edit unknown bm '\(bmName)'")
            return
        }
        presentBonePaper(asset: asset, length: UnitAssets.defaultBoneLength, onion: nil, placement: nil)
    }

    private func openBonePaper(from: Int, to: Int) {
        guard let unit = optionalUnit, let assets else {
            bail("edit with no unit")
            return
        }
        guard let startPt = unit.point(optionalId: from), let endPt = unit.point(optionalId: to) else {
            bail("edit missing points \(from)/\(to)")
            return
        }
        if unit.scale <= 0 {
            bail("scale is \(unit.scale)")
            return
        }
        // PNG offsets are item-pixel units. Scene points already include unit.scale
        // (Android skeleton editor stores unscaled model coords, so getLength() is 1:1).
        let length = hypot(endPt.x - startPt.x, endPt.y - startPt.y) / unit.scale
        let asset = assets.ensureDrawable(
            start: from,
            end: to,
            unitName: unit.name,
            length: length
        )
        let start = CGPoint(x: -asset.xOffset, y: -asset.yOffset)
        let drawnKey = UnitAssets.EdgeKey(
            unitName: UnitAssets.removeNumber(unit.name),
            start: from,
            end: to,
            flipped: unit.flipped
        )
        let nativeFlipped = assets.getDrawable(drawnKey, state: unit.assetsState)?.nativeFlipped ?? false
        let mirror = FeatureFlags.bonePaperKeepsBoneAngle && unit.flipped && !nativeFlipped
        let onion = SkeletonOnion.worldOverlay(
            unit: unit,
            assets: assets,
            excludeFrom: from,
            excludeTo: to,
            worldSize: BonePaperScreen.worldSide,
            pngWidth: asset.bitmap.width,
            pngHeight: asset.bitmap.height,
            boneStartPNG: start,
            mirror: mirror
        )
        layerEpoch += 1
        presentBonePaper(
            asset: asset,
            length: length,
            onion: onion,
            placement: FeatureFlags.bonePaperKeepsBoneAngle
                ? bonePaperPlacement(start: startPt, end: endPt, mirror: mirror, unitScale: unit.scale)
                : nil
        )
    }

    private func bonePaperPlacement(start: StickmanPoint, end: StickmanPoint, mirror: Bool, unitScale: CGFloat) -> BonePaperPlacement? {
        guard let layout = editSession.layout else {
            print("SkeletonScreen '\(title)' placement before the canvas laid out; opening without placement")
            return nil
        }
        let joint = layout.screenPoint(x: start.x, y: start.y)
        return BonePaperPlacement(
            jointScreen: CGPoint(
                x: editSession.canvasOrigin.x + joint.x,
                y: editSession.canvasOrigin.y + joint.y
            ),
            angle: atan2(end.y - start.y, end.x - start.x),
            mirror: mirror,
            pointsPerPixel: layout.scale * unitScale
        )
    }

    /// Android gallery NEW BONE: dummy picture at `DEFAULT_LENGTH`, then Kurwa with pen.
    private func createNewGalleryBone() {
        guard let unit = optionalUnit, let assets else {
            bail("new bone with no unit")
            return
        }
        prepareUndo(includeAssets: true)
        let length = UnitAssets.defaultBoneLength
        let asset = assets.createEmptyGalleryBone(unitName: unit.name, length: length)
        layerEpoch += 1
        presentBonePaper(asset: asset, length: length, onion: nil, placement: nil)
    }

    private func presentBonePaper(
        asset: UnitAssets.EdgeAsset,
        length: CGFloat,
        onion: CGImage?,
        placement: BonePaperPlacement?
    ) {
        if asset.bitmap.width < 1 || asset.bitmap.height < 1 {
            showToast("This bone picture is invalid.")
            return
        }
        let limit = BonePaperScreen.worldSide
        if asset.bitmap.width > limit || asset.bitmap.height > limit {
            showToast("This picture is too big (\(asset.bitmap.width)×\(asset.bitmap.height)). Maximum side is \(limit).")
            return
        }
        let start = CGPoint(x: -asset.xOffset, y: -asset.yOffset)
        let tip = CGPoint(x: length - asset.xOffset, y: -asset.yOffset)
        let edit = BonePaperEdit(
            source: asset.bitmap,
            buffer: validatedBuffer(asset: asset),
            boneStart: start,
            boneTip: tip,
            onion: onion,
            placement: placement,
            bmName: asset.bmName
        )
        var transaction = Transaction()
        transaction.disablesAnimations = placement != nil
        withTransaction(transaction) {
            bonePaperEdit = edit
        }
    }

    /// Decoded paint buffer for `asset`, or nil with a log when it is missing or stale.
    /// Nil reopens from the upscaled 1x path, same as before this feature.
    private func validatedBuffer(asset: UnitAssets.EdgeAsset) -> CGImage? {
        guard let data = asset.paintBuffer, !data.isEmpty else { return nil }
        guard let image = UnitAssets.pngImage(from: data) else {
            print("SkeletonScreen '\(title)' dropped unreadable paint buffer for '\(asset.bmName)'")
            return nil
        }
        let sample = BonePaperDocument.sample
        guard image.width == asset.bitmap.width * sample,
              image.height == asset.bitmap.height * sample else {
            print("SkeletonScreen '\(title)' dropped paint buffer for '\(asset.bmName)': \(image.width)x\(image.height) != \(asset.bitmap.width * sample)x\(asset.bitmap.height * sample)")
            return nil
        }
        return image
    }

    private func applyBonePaper(bmName: String, export: BonePaperExport) {
        guard let assets else {
            bail("apply with no assets")
            return
        }
        prepareUndo(includeAssets: true)
        assets.replaceBitmap(
            bmName: bmName,
            image: export.image,
            buffer: export.buffer.map { UnitAssets.pngData(from: $0, name: bmName) },
            extraLeft: export.extraLeft,
            extraTop: export.extraTop
        )
        layerEpoch += 1
    }

    private var holdBannerText: String? {
        if boneCreateHoldMode {
            return "Hold the button and drag from a point to add a bone"
        }
        if shiftHoldMode {
            return "Hold the button and drag the bone picture"
        }
        return nil
    }

    private func setHoldMode(_ on: Bool) {
        editSession.boneCreateHoldMode = on
        boneCreateHoldMode = on
    }

    private func setShiftHold(_ on: Bool) {
        editSession.shiftHoldMode = on
        shiftHoldMode = on
    }

    private func clearArtwork() {
        guard let unit = optionalUnit, let assets else {
            bail("clear with no unit")
            return
        }
        guard let id = selectedPointId, let edge = unit.upperEdge(of: id) else {
            showToast("Select a point")
            return
        }
        prepareUndo(includeAssets: true)
        assets.clearEdgeArtwork(start: edge.from, end: edge.to, unitName: unit.name)
        layerEpoch += 1
    }

    private func applyBoneShift(from: Int, to: Int, dx: CGFloat, dy: CGFloat, scale: CGFloat, rotation: CGFloat) {
        guard let unit = optionalUnit, let assets else {
            bail("shift with no unit")
            return
        }
        if scale <= 0 {
            bail("shift scale \(scale)")
            return
        }
        guard let bmName = assets.bmName(forEdge: from, end: to, unitName: unit.name) else {
            return
        }
        prepareUndo(includeAssets: true)
        assets.applyShift(bmName: bmName, dx: dx, dy: dy, scale: scale, rotation: rotation)
        layerEpoch += 1
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text {
                toast = ""
            }
        }
    }

    /// Log, toast, and close the screen: an unexpected state that used to be
    /// `fatalError` now ends the session instead of killing the app.
    private func bail(_ text: String) {
        print("SkeletonScreen '\(title)': \(text)")
        showToast(text)
        DispatchQueue.main.async { dismiss() }
    }

    private func bail(_ error: Error) {
        bail(ItemLoadError.text(error))
    }

    private func attachBone(_ bmName: String) {
        guard var unit = optionalUnit, let assets else { return }
        guard let parentId = selectedPointId else {
            pulseVacantPoints()
            return
        }
        prepareUndo(includeAssets: true)
        let newId: Int
        do {
            newId = try unit.addGalleryBonePoint(parentId: parentId, length: UnitAssets.defaultBoneLength)
        } catch {
            bail(error)
            return
        }
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

    private func openPointProps() {
        guard let unit = optionalUnit, let id = selectedPointId else {
            return
        }
        guard let point = unit.point(optionalId: id) else {
            return
        }
        pointProps = PointPropsEdit(
            pointId: id,
            isBase: point.isBase,
            attachable: point.attachable,
            fixed: point.fixed
        )
    }

    private func applyPointProps(id: Int, attachable: Attachable, fixed: Bool) {
        guard var unit = optionalUnit else {
            bail("point props with no unit")
            return
        }
        prepareUndo()
        do {
            try unit.applyPointProps(id: id, attachable: attachable, fixed: fixed)
        } catch {
            bail(error)
            return
        }
        writeUnit(unit)
        layerEpoch += 1
    }

    private func deleteSelected() {
        guard var unit = optionalUnit, let id = selectedPointId else { return }
        guard let point = unit.point(optionalId: id) else {
            return
        }
        if point.isBase {
            return
        }
        prepareUndo(includeAssets: true)
        do {
            try unit.deletePointSubtree(id: id)
        } catch {
            bail(error)
            return
        }
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
        guard let scene, let frame = scene.currentFrameOrNil, !frame.units.isEmpty else { return nil }
        return frame.units[0]
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
                bail("undo with no assets")
                return
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
            bail("has no scene loaded")
            return
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
        guard let scene, let frame = scene.currentFrameOrNil, assets != nil else {
            bail("preview before load")
            return
        }
        if frame.units.isEmpty {
            bail("preview with no unit")
            return
        }
        // Android SkeletonActivity.readyToSave: a base point alone is not a bone.
        if frame.units[0].points.count < 2 {
            showToast("Add more points")
            return
        }
        previewTicket = PreviewTicket()
    }

    private func openSettings() {
        showingMenu = false
        showingSettings = true
    }

    private var previewScreen: some View {
        guard let scene, let frame = scene.currentFrameOrNil, let assets else {
            // Cover content is only built while previewTicket exists, which openPreview
            // sets only after these checks; the fallback just avoids a fatalError.
            bail("preview cover with no scene")
            return AnyView(Color.clear)
        }
        if frame.units.isEmpty {
            bail("preview with no unit")
            return AnyView(Color.clear)
        }
        return AnyView(
            SkeletonPreviewScreen(
                unit: frame.units[0],
                assets: assets,
                sceneWidth: scene.width,
                sceneHeight: scene.height
            )
        )
    }

    private func saveAs() {
        showingMenu = false
        guard scene != nil else {
            bail("save before load")
            return
        }
        guard assets != nil else {
            bail("has no assets to save")
            return
        }
        showingSave = true
    }

    private func saveItem(name: String, then finish: @escaping () -> Void) {
        guard let scene, let frame = scene.currentFrameOrNil else {
            bail("save before load")
            return
        }
        guard let assets else {
            bail("has no assets to save")
            return
        }
        if frame.units.isEmpty {
            bail("save with no unit")
            return
        }
        let unit = frame.units[0]
        let source = sourceZip
        let images = SceneThumbRenderer.itemPair(unit: unit, assets: assets)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ItemSaver.save(
                    unit: unit,
                    assets: assets,
                    source: source,
                    name: name,
                    thumb: images.thumb,
                    poster: images.poster
                )
            } catch {
                DispatchQueue.main.async {
                    showingSave = false
                    showToast("Could not save: \(ItemLoadError.text(error))")
                }
            }
            DispatchQueue.main.async(execute: finish)
        }
    }

    private func loadIfNeeded() {
        if scene != nil {
            return
        }
        let source = source
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let built = try Self.load(source)
                DispatchQueue.main.async {
                    scene = built.scene
                    assets = built.assets
                    sourceZip = built.zip
                }
            } catch {
                let message = ItemLoadError.text(error)
                DispatchQueue.main.async {
                    ToastCenter.show(message)
                    dismiss()
                }
            }
        }
    }

    private struct Loaded {
        var scene: StickmanScene
        var assets: UnitAssets
        var zip: Data?
    }

    private static func load(_ source: Source) throws -> Loaded {
        switch source {
        case .custom(let item):
            let zip: Data
            do {
                zip = try Data(contentsOf: item.url)
            } catch {
                throw ItemLoadError("SkeletonScreen could not read \(item.url.path): \(error)")
            }
            return try build(zip: zip, defaultScale: 1)
        case .template(let template):
            let zip = try Manifest.shared.itemZip(fullname: template.makeFullName())
            return try build(zip: zip, defaultScale: template.scale)
        case .unit(let unit):
            return Loaded(scene: try ItemConstructor.scene(unit: unit), assets: UnitAssets(), zip: nil)
        }
    }

    private static func build(zip: Data, defaultScale: CGFloat) throws -> Loaded {
        let unit = try ItemLoader.unit(from: zip)
        let assets = UnitAssets()
        // A skeleton with no bone pictures yet is a valid state here, so assets.xml may be absent.
        let names = try ZipStore.namesThrowing(in: zip)
        if names.contains("assets.xml") {
            try assets.loadItemFromArchive(
                zip,
                entryName: UnitAssets.atiEntryName(for: unit.name),
                forceReload: false
            )
        }
        var scale = defaultScale
        if names.contains("meta.txt") {
            let atiScale = try ItemMeta.scale(from: try ZipStore.dataThrowing(named: "meta.txt", in: zip))
            if atiScale > 0.01 {
                scale = atiScale
            }
        }
        return Loaded(scene: try ItemConstructor.scene(unit: unit, scale: scale), assets: assets, zip: zip)
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                guard let scene, let frame = scene.currentFrameOrNil else {
                    bail("has no scene loaded")
                    return StickmanUnit(name: optionalUnit?.name ?? title, points: [], edges: [])
                }
                if frame.units.isEmpty {
                    bail("frame \(frame.id) has no units")
                    return StickmanUnit(name: title, points: [], edges: [])
                }
                return frame.units[0]
            },
            set: { newUnit in
                guard var loaded = scene else {
                    bail("has no scene loaded")
                    return
                }
                let frameIndex = loaded.currentIndex
                if loaded.frames[frameIndex].units.isEmpty {
                    bail("frame \(loaded.frames[frameIndex].id) has no units")
                    return
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
