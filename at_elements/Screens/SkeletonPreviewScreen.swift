import SwiftUI

struct SkeletonPreviewScreen: View {
    @State private var unit: StickmanUnit
    @State private var canvasPane = SkeletonCanvas.pane
    @State private var stretchHold = false
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

    private var availableStates: [Int] {
        assets.states(for: unit.name)
    }

    private var hasMultipleStates: Bool {
        availableStates.count > 1
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
                mode: .editor,
                stretchHold: $stretchHold,
                onMessage: { ToastCenter.show($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                SkeletonPreviewPanel(canvasPane: $canvasPane, onBack: { dismiss() })
                if hasMultipleStates {
                    SkeletonPreviewStatesList(
                        states: availableStates,
                        activeState: unit.assetsState,
                        onSelectState: { unit.assetsState = $0 }
                    )
                }
            }

            if stretchHold || BoneStretch.hasStretchablePoint(unit) {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        StretchHoldButton(
                            leading: SkeletonChrome.sidebarWidth + (hasMultipleStates ? SkeletonPreviewStatesList.width : 0) + 8,
                            isActive: stretchHold,
                            onHoldStart: { stretchHold = true },
                            onHoldEnd: { stretchHold = false }
                        )
                        .paddingBottomSafeArea()
                        .paddingLeadingIsland()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .background(canvasPane)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .modifier(StatusBarClearance())
        .toolbar(.hidden, for: .navigationBar)
    }
}
