import SwiftUI

struct SkeletonPreviewScreen: View {
    @State private var unit: StickmanUnit
    @State private var canvasPane = SkeletonCanvas.pane
    var assets: UnitAssets
    var sceneWidth: CGFloat
    var sceneHeight: CGFloat
    @Environment(\.dismiss) private var dismiss

    init(unit: StickmanUnit, assets: UnitAssets, sceneWidth: CGFloat, sceneHeight: CGFloat) {
        _unit = State(initialValue: unit)
        self.assets = assets
        self.sceneWidth = sceneWidth
        self.sceneHeight = sceneHeight
    }

    var body: some View {
        ZStack(alignment: .leading) {
            SkeletonCanvas(
                unit: $unit,
                assets: assets,
                sceneWidth: sceneWidth,
                sceneHeight: sceneHeight,
                sceneFill: canvasPane,
                canvasPane: canvasPane,
                mode: .editor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SkeletonPreviewPanel(canvasPane: $canvasPane, onBack: { dismiss() })
        }
        .background(canvasPane)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
