import Kingfisher
import SwiftUI

struct SavedScenesScreen: View {
    var body: some View {
        SavedScenesGrid(showsChrome: true)
    }
}

/// Android `SavedFragment` grid. Landing LOAD embeds this without the nav chrome.
struct SavedScenesGrid: View {
    var showsChrome = true
    @State private var items: [SavedScenes.Item] = []
    @StateObject private var opener = SceneOpener()
    @State private var shareItem: SavedScenes.Item?
    @State private var deleteItem: SavedScenes.Item?
    private let thumbWidth: CGFloat = 160
    private let thumbHeight: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let columns = max(Int(proxy.size.width / thumbWidth), 1)
            let leftover = proxy.size.width - CGFloat(columns) * thumbWidth
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(thumbWidth), spacing: 1), count: columns),
                    spacing: 1
                ) {
                    ForEach(items) { item in
                        Button {
                            opener.open(item.name) {
                                try SceneLoader.load(url: item.url)
                            }
                        } label: {
                            SavedSceneCell(item: item, width: thumbWidth, height: thumbHeight)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { deleteItem = item }
                            Button("Share") { shareItem = item }
                        }
                    }
                }
                .padding(.horizontal, leftover / 2)
            }
        }
        .background((showsChrome ? Color.white : LandingScreen.pane).ignoresSafeArea())
        .modifier(SavedScenesChrome(enabled: showsChrome))
        .sceneLoadingOverlay(name: opener.loadingName)
        .sceneEditorDestination(opener)
        .onAppear {
            items = SavedScenes.collect()
        }
        .onReceive(NotificationCenter.default.publisher(for: .savedScenesDidChange)) { _ in
            items = SavedScenes.collect()
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(url: item.url)
        }
        .confirmationDialog(
            "Delete “\(deleteItem?.name ?? "")”?",
            isPresented: Binding(
                get: { deleteItem != nil },
                set: { if !$0 { deleteItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = deleteItem {
                    confirmDelete(item)
                }
            }
            Button("Cancel", role: .cancel) { deleteItem = nil }
        }
    }

    private func confirmDelete(_ item: SavedScenes.Item) {
        do {
            try FileManager.default.removeItem(at: item.url)
            items.removeAll { $0.id == item.id }
            deleteItem = nil
        } catch {
            ToastCenter.show("Could not delete \(item.name): \(error.localizedDescription)")
        }
    }
}

private struct SavedScenesChrome: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle("Saved Scenes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct SavedSceneCell: View {
    let item: SavedScenes.Item
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KFImage.dataProvider(SavedSceneThumbProvider(item: item))
                .fade(duration: 0.2)
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
            Text(item.name)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255).opacity(0x55 / 255))
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
