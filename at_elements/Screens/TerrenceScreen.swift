import SwiftUI

struct TerrenceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: (StickmanScene, UnitAssets)?

    var body: some View {
        Group {
            if let loaded {
                SceneEditorScreen(scene: loaded.0, assets: loaded.1)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        FullscreenBackButton()
                    }
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        if loaded != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let item = try ItemLoader.load(resource: "terrence", subdirectory: "testdata")
                let built = ItemConstructor.scene(unit: item.0, scale: item.2, frameCount: 5)
                DispatchQueue.main.async {
                    loaded = (built, item.1)
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
}

#Preview {
    NavigationStack {
        TerrenceScreen()
    }
}
