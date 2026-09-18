import CoreGraphics
import SwiftUI

struct ItemChooserPanel: View {
    static let width: CGFloat = 180
    static let pane = Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let accent = Color(red: 0xa5 / 255, green: 0xe9 / 255, blue: 0x3f / 255)
    static let dir = Color(red: 0xac / 255, green: 0x81 / 255, blue: 0x2b / 255)

    var onPick: (Item) -> Void

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
                case .items(let pack, let dir):
                    itemsList(pack: pack, dir: dir)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.pane)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .task {
            packs = await Manifest.shared.queryPacks(.empty())
        }
        .onReceive(NotificationCenter.default.publisher(for: .customItemsDidChange)) { _ in
            Task { await refreshCustomPack() }
        }
    }

    private var packsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(packs, id: \.name) { pack in
                    Button {
                        openPack(pack.name)
                    } label: {
                        VStack(spacing: 6) {
                            Image(decorative: packLogo(pack.name), scale: UIScreen.main.scale)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
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
                }
            }
            .padding(5)
        }
    }

    private func itemsList(pack: Pack, dir: String?) -> some View {
        let visible = pack.items.filter { !$0.readOnly }
        let dirs: [String] = {
            if dir != nil { return [] }
            return Array(Set(visible.map(\.setName).filter { !$0.isEmpty })).sorted()
        }()
        let items: [Item] = {
            if let dir {
                return visible.filter { $0.setName == dir }.sorted { $0.systemName < $1.systemName }
            }
            return visible.filter { $0.setName.isEmpty }.sorted { $0.systemName < $1.systemName }
        }()
        return ScrollView {
            LazyVStack(spacing: 0) {
                Button {
                    if dir == nil {
                        level = .packs
                    } else {
                        level = .items(pack: pack, dir: nil)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("<")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                ForEach(dirs, id: \.self) { name in
                    Button {
                        level = .items(pack: pack, dir: name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Self.dir)
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
                            Image(decorative: itemThumb(item), scale: UIScreen.main.scale)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
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
        }
    }

    private func openPack(_ name: String) {
        Task {
            let matched = await Manifest.shared.queryPacks(Query(name))
            guard let pack = matched.first else {
                fatalError("ItemChooser pack '\(name)' missing")
            }
            if matched.count != 1 {
                fatalError("ItemChooser Query(\(name)) returned \(matched.map(\.name))")
            }
            level = .items(pack: pack, dir: nil)
        }
    }

    private func refreshCustomPack() async {
        _ = await Manifest.shared.requestReloadCustomPack()
        packs = await Manifest.shared.queryPacks(.empty())
        if case .items(let pack, let dir) = level, pack.name == Pack.customName {
            guard let updated = packs.first(where: { $0.name == Pack.customName }) else {
                fatalError("ItemChooser custom pack missing after reload")
            }
            level = .items(pack: updated, dir: dir)
        }
    }

    private func packLogo(_ packName: String) -> CGImage {
        PNGImage.cgImage(from: Manifest.shared.packLogo(packName), name: "\(packName)/logo.png")
    }

    private func itemThumb(_ item: Item) -> CGImage {
        let zip = Manifest.shared.itemZip(fullname: item.makeFullName())
        return ItemLoader.thumb(from: zip, name: item.makeFullName())
    }

    private enum Level {
        case packs
        case items(pack: Pack, dir: String?)
    }
}
