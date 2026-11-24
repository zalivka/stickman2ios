import CoreGraphics
import SwiftUI

struct ItemChooserPanel: View, Equatable {
    static let width: CGFloat = 180
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0xa5 / 255, green: 0xe9 / 255, blue: 0x3f / 255)
    static let dir = Color(red: 0xac / 255, green: 0x81 / 255, blue: 0x2b / 255)
    private static let displayScale = UIScreen.main.scale

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }

    var onPick: (Item) -> Void
    var onClose: () -> Void
    var onCreateItems: () -> Void

    @State private var level: Level = .packs
    @State private var packs: [Pack] = []

    var body: some View {
        HStack(spacing: 0) {
            Self.accent
                .frame(width: 2)
            Group {
                switch level {
                case .packs:
                    packsList
                case .items(let pack, let dir, let dirs, let items):
                    itemsList(pack: pack, dir: dir, dirs: dirs, items: items)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            backButton(action: goBack)
                .padding(.leading, 8)
                .padding(.top, 8)
        }
        .task {
            packs = await Manifest.shared.queryPacks(.empty())
        }
        .onReceive(NotificationCenter.default.publisher(for: .customItemsDidChange)) { _ in
            Task { await refreshCustomPack() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .installedPacksDidChange)) { _ in
            Task { await refreshPacks() }
        }
    }

    private var packsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(packs, id: \.name) { pack in
                    packTile(pack)
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .padding(.top, Self.listTop)
        }
    }

    private func itemsList(pack: Pack, dir: String?, dirs: [String], items: [Item]) -> some View {
        let showsCreate = pack.name == Pack.customName && dir == nil
        return ScrollView {
            LazyVStack(spacing: 0) {
                if showsCreate {
                    createItemsRow
                }
                ForEach(dirs, id: \.self) { name in
                    Button {
                        level = Level.makeItems(pack: pack, dir: name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(decorative: Self.folderIcon, scale: 80.0 / 48)
                                .frame(width: 48, height: 44)
                            Text(name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Self.dir)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(items, id: \.systemName) { item in
                    Button {
                        onPick(item)
                    } label: {
                        HStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                ItemChooserThumbView(fullName: item.makeFullName(), scale: Self.displayScale)
                                if item.multiframed {
                                    Image(decorative: Self.multiframedBadgeIcon, scale: 2)
                                }
                            }
                            .frame(width: 50, height: 50, alignment: .topLeading)
                            .background(Color.white)
                            Text(item.humanName)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 60)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Self.listTop)
        }
    }

    /// Android `in_list_offer`: blue row, `magic_wand2`, "Create items".
    /// Shown only at the root of the custom pack, above its folders and items.
    private var createItemsRow: some View {
        Button(action: onCreateItems) {
            HStack(spacing: 10) {
                Image(decorative: Self.wandIcon, scale: 2)
                Text("Create items")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CreateItemsButtonStyle())
    }

    /// Clears the pinned Back control. 8 top inset + 44 circle + 8 gap.
    private static let listTop: CGFloat = 60

    private func goBack() {
        switch level {
        case .packs:
            onClose()
        case .items(_, nil, _, _):
            level = .packs
        case .items(let pack, _?, _, _):
            level = Level.makeItems(pack: pack, dir: nil)
        }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        BackCircleButton(showsCaption: true, action: action)
    }

    private static let wandIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "magic_wand2", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "magic_wand2", withExtension: "png")
        else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel missing chrome/magic_wand2.png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/magic_wand2.png")
        } catch {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel could not read \(url.path): \(error)")
        }
    }()

    private static let folderIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "dir2", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "dir2", withExtension: "png")
        else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel missing chrome/dir2.png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/dir2.png")
        } catch {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel could not read \(url.path): \(error)")
        }
    }()

    private static let multiframedBadgeIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "multiframed_badge", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "multiframed_badge", withExtension: "png")
        else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel missing chrome/multiframed_badge.png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "chrome/multiframed_badge.png")
        } catch {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("ItemChooserPanel could not read \(url.path): \(error)")
        }
    }()

    @ViewBuilder
    private func packTile(_ pack: Pack) -> some View {
        let tile = Button {
            openPack(pack.name)
        } label: {
            VStack(spacing: 6) {
                if let logo = packLogo(pack.name) {
                    Image(decorative: logo, scale: Self.displayScale)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                } else {
                    Color.white.frame(width: 150, height: 150)
                }
                Text(pack.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.25))
                    .multilineTextAlignment(.center)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .buttonStyle(.plain)
        if InstalledPacks.contains(pack.name) {
            tile.contextMenu {
                Button("Delete", role: .destructive) {
                    deletePack(pack.name)
                }
            }
        } else {
            tile
        }
    }

    private func deletePack(_ name: String) {
        Task {
            do {
                try InstalledPacks.delete(name)
                ThumbCache.drop(packName: name)
                _ = await Manifest.shared.requestReload()
                NotificationCenter.default.post(name: .installedPacksDidChange, object: nil)
                ToastCenter.show("Pack deleted")
            } catch {
                ToastCenter.show(ItemLoadError.text(error))
            }
        }
    }

    private func refreshPacks() async {
        packs = await Manifest.shared.queryPacks(.empty())
        if case .items(let pack, let dir, _, _) = level {
            guard let updated = packs.first(where: { $0.name == pack.name }) else {
                level = .packs
                return
            }
            level = Level.makeItems(pack: updated, dir: dir)
        }
    }

    private func openPack(_ name: String) {
        Task {
            let matched = await Manifest.shared.queryPacks(Query(name))
            guard matched.count == 1, let pack = matched.first else {
                // Pack vanished mid-session (external pack removed). Stay on the current level.
                assertionFailure("ItemChooser Query(\(name)) returned \(matched.map(\.name))")
                return
            }
            level = Level.makeItems(pack: pack, dir: nil)
        }
    }

    private func refreshCustomPack() async {
        _ = await Manifest.shared.requestReloadCustomPack()
        packs = await Manifest.shared.queryPacks(.empty())
        if case .items(let pack, let dir, _, _) = level, pack.name == Pack.customName {
            guard let updated = packs.first(where: { $0.name == Pack.customName }) else {
                assertionFailure("ItemChooser custom pack missing after reload")
                return
            }
            level = Level.makeItems(pack: updated, dir: dir)
        }
    }

    private func packLogo(_ packName: String) -> CGImage? {
        ThumbCache.imageIfPresent("logo:" + packName) {
            let data = try Manifest.shared.packLogo(packName)
            if InstalledPacks.contains(packName) {
                return try PNGImage.loaded(from: data, name: "\(packName)/logo.png")
            }
            return PNGImage.cgImage(from: data, name: "\(packName)/logo.png")
        }
    }

    private enum Level {
        case packs
        case items(pack: Pack, dir: String?, dirs: [String], items: [Item])

        static func makeItems(pack: Pack, dir: String?) -> Level {
            let visible = pack.items.filter { !$0.readOnly }
            let dirs: [String]
            let items: [Item]
            if let dir {
                dirs = []
                items = visible.filter { $0.setName == dir }.sorted { $0.systemName < $1.systemName }
            } else {
                dirs = Array(Set(visible.map(\.setName).filter { !$0.isEmpty })).sorted()
                items = visible.filter { $0.setName.isEmpty }.sorted { $0.systemName < $1.systemName }
            }
            return .items(pack: pack, dir: dir, dirs: dirs, items: items)
        }
    }
}

private struct ItemChooserThumbView: View {
    let fullName: String
    let scale: CGFloat

    @State private var loaded: CGImage?

    private var cacheKey: String {
        "chooser:" + fullName
    }

    var body: some View {
        let key = cacheKey
        if let image = loaded ?? ThumbCache.cached(key) {
            Image(decorative: image, scale: scale)
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
        } else {
            Color.clear
                .frame(width: 50, height: 50)
                .task(id: fullName) {
                    let fullName = self.fullName
                    let key = "chooser:" + fullName
                    if let existing = ThumbCache.cached(key) {
                        loaded = existing
                        return
                    }
                    let decoded = await Task.detached(priority: .userInitiated) {
                        ThumbCache.imageIfPresent(key) {
                            let zip = try Manifest.shared.itemZip(fullname: fullName)
                            return try ItemLoader.thumb(from: zip, name: fullName)
                        }
                    }.value
                    if !Task.isCancelled {
                        loaded = decoded
                    }
                }
        }
    }
}

/// Android `items_editor_ad`: `#23aae2`, pressed `#2599c8`.
private struct CreateItemsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Self.pressed : Self.normal)
    }

    private static let normal = Color(red: 0x23 / 255, green: 0xaa / 255, blue: 0xe2 / 255)
    private static let pressed = Color(red: 0x25 / 255, green: 0x99 / 255, blue: 0xc8 / 255)
}
