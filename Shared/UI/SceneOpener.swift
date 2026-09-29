import Combine
import Foundation
import SwiftUI

/// Loads a cartoon behind a spinner overlay and navigates only when ready.
/// BonePaper parity: the current screen stays put with a dim + spinner
/// (see `BonePaperScreen` filling overlay) instead of pushing a loading screen.
final class SceneOpener: ObservableObject {
    struct Loaded {
        var scene: StickmanScene
        var assets: UnitAssets
        var backgrounds: BackgroundAssets
        var tutorial: Bool
    }

    @Published private(set) var loadingName: String?
    @Published private(set) var opened: Loaded?

    func open(
        _ displayName: String,
        tutorial: Bool = false,
        load: @escaping () throws -> (StickmanScene, UnitAssets, BackgroundAssets)
    ) {
        guard loadingName == nil, opened == nil else { return }
        loadingName = displayName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let built = try load()
                DispatchQueue.main.async {
                    self?.opened = Loaded(scene: built.0, assets: built.1, backgrounds: built.2, tutorial: tutorial)
                    self?.loadingName = nil
                }
            } catch let missing as MissingManifestItem {
                self?.fail(missing.message)
            } catch {
                self?.fail(String(describing: error))
            }
        }
    }

    func close() {
        opened = nil
    }

    private func fail(_ text: String) {
        print("Scene load failed: \(text)")
        DispatchQueue.main.async { [weak self] in
            self?.loadingName = nil
            ToastCenter.show(text)
        }
    }
}

extension View {
    func sceneLoadingOverlay(name: String?) -> some View {
        modifier(SceneLoadingOverlay(name: name))
    }

    func sceneEditorDestination(_ opener: SceneOpener) -> some View {
        modifier(SceneEditorDestination(opener: opener))
    }
}

private struct SceneLoadingOverlay: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        content.overlay {
            if let name {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Loading \(name)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct SceneEditorDestination: ViewModifier {
    @ObservedObject var opener: SceneOpener

    func body(content: Content) -> some View {
        content.navigationDestination(
            isPresented: Binding(
                get: { opener.opened != nil },
                set: { if !$0 { opener.close() } }
            )
        ) {
            if let opened = opener.opened {
                SceneEditorScreen(
                    scene: opened.scene,
                    assets: opened.assets,
                    backgrounds: opened.backgrounds,
                    tutorial: opened.tutorial
                )
            } else {
                ProgressView()
            }
        }
    }
}
