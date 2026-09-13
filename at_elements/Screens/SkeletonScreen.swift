import SwiftUI

struct SkeletonScreen: View {
    let title: String
    @State private var scene: StickmanScene

    init(title: String, unit: StickmanUnit) {
        self.title = title
        _scene = State(initialValue: ItemConstructor.scene(unit: unit))
    }

    var body: some View {
        HStack(spacing: 0) {
            MainPanel()
            SkeletonCanvas(
                unit: unitBinding,
                sceneWidth: scene.width,
                sceneHeight: scene.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                FullscreenBackButton()
            }
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                let frame = scene.currentFrame
                if frame.units.isEmpty {
                    fatalError("StickmanScene frame \(frame.id) has no units")
                }
                return frame.units[0]
            },
            set: { newUnit in
                let frameIndex = scene.currentIndex
                if scene.frames[frameIndex].units.isEmpty {
                    fatalError("StickmanScene frame \(scene.frames[frameIndex].id) has no units")
                }
                scene.frames[frameIndex].units[0] = newUnit
            }
        )
    }
}

#Preview {
    NavigationStack {
        SkeletonScreen(title: "Skeleton", unit: ItemConstructor.spider())
    }
}
