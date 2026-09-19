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
                        NavigationLink {
                            DemoSceneScreen(url: item.url)
                        } label: {
                            SavedSceneCell(item: item, width: thumbWidth, height: thumbHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, leftover / 2)
            }
        }
        .background((showsChrome ? Color.white : LandingScreen.pane).ignoresSafeArea())
        .modifier(SavedScenesChrome(enabled: showsChrome))
        .onAppear {
            items = SavedScenes.collect()
        }
        .onReceive(NotificationCenter.default.publisher(for: .savedScenesDidChange)) { _ in
            items = SavedScenes.collect()
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
