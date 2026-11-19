import SwiftUI
import UIKit

struct BonePaperCanvas: UIViewRepresentable {
    @ObservedObject var document: BonePaperDocument
    var tool: BonePaperTool
    var color: UIColor
    var brushSize: CGFloat
    var opacity: CGFloat
    var boneStart: CGPoint?
    var boneTip: CGPoint?
    var onion: CGImage?
    var paper: UIColor?
    var placement: BonePaperPlacement?
    var stage: BonePaperStage
    var zoom: Binding<CGFloat>
    var fitInsets: UIEdgeInsets
    var onCommitStroke: () -> Void
    var onImagePlacementChanged: ((Bool) -> Void)? = nil
    var onCanvasTransformChanged: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> BonePaperStageView {
        let view = BonePaperStageView(placement: placement)
        stage.view = view
        apply(view)
        return view
    }

    func updateUIView(_ view: BonePaperStageView, context: Context) {
        apply(view)
    }

    private func apply(_ view: BonePaperStageView) {
        view.paper.document = document
        view.paper.tool = tool
        view.paper.color = color
        view.paper.brushSize = brushSize
        view.paper.opacity = opacity
        view.paper.boneStart = boneStart
        view.paper.boneTip = boneTip
        view.paper.onion = onion
        view.paper.paperColor = paper
        view.paper.onCommitStroke = onCommitStroke
        view.onZoom = { zoom.wrappedValue = $0 }
        view.onImagePlacementChanged = onImagePlacementChanged
        view.onCanvasTransformChanged = onCanvasTransformChanged
        view.setPanMode(tool == .pan)
        view.fitInsets = fitInsets
        view.layoutPaper(side: CGFloat(document.worldSize))
        view.paper.show(document)
        view.syncImagePlacement()
        view.syncCanvasTransform()
    }
}
