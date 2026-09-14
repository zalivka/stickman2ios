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
                    mode: .skeleton
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 0) {
                SkeletonLeftPanel(
                    panel: toolsPanel,
                    onMenu: toggleMenu,
                    onSelect: { toolsPanel = $0 },
                    menuActivated: showingMenu
                )
                if toolsPanel == .bones {
                    SkeletonSecondaryPanel(accent: SkeletonChrome.bonesAccent)
                } else if toolsPanel == .draw {
                    SkeletonSecondaryPanel(accent: SkeletonChrome.drawAccent)
                }
                Spacer(minLength: 0)
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
        .background(SkeletonCanvas.checkerLight)
        .animation(.easeInOut(duration: 0.2), value: showingMenu)
        .ignoresSafeArea()
        .accessibilityLabel(title)
        .onAppear(perform: loadIfNeeded)
        .overlay(alignment: .topLeading) {
            FullscreenBackButton(
                besideMainPanel: true,
                extraLeading: SkeletonChrome.leadingWidth(panel: toolsPanel) - MainPanel.width,
                action: showingMenu ? { showingMenu = false } : nil
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
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
        let unit = scene.currentFrame.units[0]
        let name = ItemSaver.freeName()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try ItemSaver.save(unit: unit, source: sourceZip, name: name)
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
