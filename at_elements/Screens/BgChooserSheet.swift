import SwiftUI
import UIKit

/// Android `BgChooserFragment`: folders on the left, backgrounds of the selected folder on the right.
/// Picking materializes the sized cache archive and installs it into `backgrounds` before `onPick`.
struct BgChooserSheet: View {
    var sceneWidth: CGFloat
    var sceneHeight: CGFloat
    var backgrounds: BackgroundAssets
    var colorInitial: UIColor
    /// `bgName`s on the open scene. Delete stays off for these.
    var usedNames: Set<String>
    var onPick: (String) -> Void
    var onEdit: (BackgroundEntry) -> Void
    var onDelete: (BackgroundEntry) -> Bool
    var onCancel: () -> Void

    @State private var folders: [BackgroundCatalog.Folder]?
    @State private var selected: String?
    @State private var showingColor = false
    @State private var toast = ""

    private static let thumbSize: CGFloat = 110

    var body: some View {
        NavigationStack {
            content
                .background(MainPanel.pane.ignoresSafeArea())
                .navigationTitle("Backgrounds")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 17))
                            }
                        }
                    }
                }
                .toolbarBackground(MainPanel.pane, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .overlay {
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
        }
        .onAppear(perform: loadFolders)
        .sheet(isPresented: $showingColor) {
            FlexColorPickerSheet(initial: colorInitial) { color in
                showingColor = false
                onPick(SolidBackgrounds.hex(from: color))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let folders {
            HStack(spacing: 0) {
                folderList(folders)
                Rectangle()
                    .fill(Color(white: 0.35))
                    .frame(width: 1)
                if let folder = folders.first(where: { $0.packName == (selected ?? folders.first?.packName) }) {
                    entryGrid(folder)
                } else {
                    Text("No backgrounds")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func folderList(_ folders: [BackgroundCatalog.Folder]) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                actionRow("Pick", fill: Self.pickFill, ink: Self.pickInk, symbol: "photo")
                actionRow("Draw", fill: Self.drawFill, ink: Self.drawInk, symbol: "paintbrush.pointed")
                actionRow("Color", fill: Self.colorFill, ink: Self.colorInk, symbol: "paintpalette") {
                    showingColor = true
                }
                ForEach(folders) { folder in
                    Button {
                        selected = folder.packName
                    } label: {
                        Text(folder.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected(folder, in: folders) ? Color(white: 0.3) : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 180)
    }

    /// Android chooser action colors: Pick Image `#38BDF8`, Draw `#F59E0B`.
    private static let pickFill = Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255)
    private static let pickInk = Color(red: 0x07 / 255, green: 0x23 / 255, blue: 0x3A / 255)
    private static let drawFill = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    private static let drawInk = Color(red: 0x38 / 255, green: 0x21 / 255, blue: 0)
    private static let colorFill = Color(red: 0xC4 / 255, green: 0xB5 / 255, blue: 0xFD / 255)
    private static let colorInk = Color(red: 0x2E / 255, green: 0x10 / 255, blue: 0x65 / 255)

    private func actionRow(
        _ title: String,
        fill: Color,
        ink: Color,
        symbol: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func entryGrid(_ folder: BackgroundCatalog.Folder) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.thumbSize, maximum: Self.thumbSize + 20), spacing: 8)],
                spacing: 8
            ) {
                ForEach(folder.entries) { entry in
                    entryButton(entry)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func entryButton(_ entry: BackgroundEntry) -> some View {
        let button = Button {
            pick(entry)
        } label: {
            thumb(entry)
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipped()
                .background(Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.id)
        if case .user = entry.source {
            button.contextMenu {
                Button("Edit") { onEdit(entry) }
                Button("Delete", role: .destructive) { remove(entry) }
                    .disabled(usedNames.contains(entry.id))
            }
        } else {
            button
        }
    }

    private func remove(_ entry: BackgroundEntry) {
        if !onDelete(entry) {
            return
        }
        guard var folders else { return }
        for index in folders.indices {
            folders[index].entries.removeAll { $0.id == entry.id }
        }
        let kept = folders.filter { !$0.entries.isEmpty }
        self.folders = kept
        if let selected, !kept.contains(where: { $0.packName == selected }) {
            self.selected = kept.first?.packName
        }
    }

    @ViewBuilder
    private func thumb(_ entry: BackgroundEntry) -> some View {
        if let image = entry.thumb {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color(white: 0.8)
        }
    }

    private func isSelected(_ folder: BackgroundCatalog.Folder, in folders: [BackgroundCatalog.Folder]) -> Bool {
        (selected ?? folders.first?.packName) == folder.packName
    }

    private func loadFolders() {
        if folders != nil {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = [BackgroundCatalog.userFolder()].compactMap { $0 } + BackgroundCatalog.packFolders()
            DispatchQueue.main.async {
                folders = loaded
            }
        }
    }

    private func pick(_ entry: BackgroundEntry) {
        do {
            let bgName = try BackgroundResolver.materialize(entry, sceneWidth: sceneWidth, sceneHeight: sceneHeight)
            try BackgroundResolver.install(bgName, into: backgrounds)
            onPick(bgName)
        } catch {
            print("BgChooserSheet \(entry.id): \(error)")
            showToast("Cannot process the background \(entry.id)")
        }
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
}
