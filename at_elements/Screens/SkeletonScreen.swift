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
    /// The archive the item came from. Saving reuses its art entries verbatim.
    @State private var sourceZip: Data?
    @State private var toolsPanel: SkeletonToolsPanel = .bones
    @State private var showingMenu = false
    @State private var boneCreateHoldMode = false
    @State private var selectedPointId: Int?
    @State private var layerEpoch = 0
    @State private var exposeVacantPoints = false
    @State private var editSession = SkeletonEditSession()
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
                    exposeVacantPoints: exposeVacantPoints
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
                    onBack: {
                        if showingMenu {
                            showingMenu = false
                        } else {
                            dismiss()
                        }
                    }
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
                    onSaveAs: saveAs
                )
                .transition(.move(edge: .leading))
            }
        }
        .overlay(alignment: .trailing) {
            if scene != nil, assets != nil {
                BonesGalleryPanel(
                    bones: galleryBones,
                    highlightedBmName: highlightedBmName,
                    onNewBone: {},
                    onAttach: attachBone
                )
            }
        }
        .background(SkeletonCanvas.checkerLight)
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .ignoresSafeArea()
        .accessibilityLabel(title)
        .onAppear(perform: loadIfNeeded)
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
        let newId = unit.addGalleryBonePoint(parentId: parentId, length: 200)
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
        unit.deletePointSubtree(id: id)
        selectedPointId = nil
        writeUnit(unit)
        layerEpoch += 1
    }

    private func moveSelected(up: Bool) {
        guard let unit = optionalUnit, let id = selectedPointId, let assets else { return }
        guard let edge = unit.upperEdge(of: id) else { return }
        if assets.moveEdgeOrder(unitName: unit.name, start: edge.from, end: edge.to, moveUp: up) {
            layerEpoch += 1
        }
    }

    private var optionalUnit: StickmanUnit? {
        guard let scene, !scene.currentFrame.units.isEmpty else { return nil }
        return scene.currentFrame.units[0]
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
