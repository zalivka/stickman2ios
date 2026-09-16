import SwiftUI
import UIKit

struct BonePaperCanvas: UIViewRepresentable {
    @ObservedObject var document: BonePaperDocument
    var tool: BonePaperTool
    var color: UIColor
    var brushSize: CGFloat

    func makeUIView(context: Context) -> BonePaperScrollView {
        let scroll = BonePaperScrollView()
        scroll.paper.document = document
        scroll.paper.tool = tool
        scroll.paper.color = color
        scroll.paper.brushSize = brushSize
        return scroll
    }

    func updateUIView(_ scroll: BonePaperScrollView, context: Context) {
        scroll.paper.document = document
        scroll.paper.tool = tool
        scroll.paper.color = color
        scroll.paper.brushSize = brushSize
        scroll.paper.preview = document.preview
        scroll.paper.setNeedsDisplay()
    }
}

final class BonePaperScrollView: UIScrollView, UIScrollViewDelegate {
    let paper = BonePaperDrawView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let side = CGFloat(BonePaperDocument.side)
        paper.frame = CGRect(x: 0, y: 0, width: side, height: side)
        addSubview(paper)
        contentSize = paper.bounds.size
        minimumZoomScale = 0.4
        maximumZoomScale = 8
        delegate = self
        delaysContentTouches = false
        panGestureRecognizer.minimumNumberOfTouches = 2
        pinchGestureRecognizer?.isEnabled = true
        bouncesZoom = true
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BonePaperScrollView coder")
    }

    private var didFit = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if !didFit, bounds.width > 0, bounds.height > 0 {
            let side = CGFloat(BonePaperDocument.side)
            let fit = min(bounds.width / side, bounds.height / side)
            zoomScale = min(max(fit, minimumZoomScale), 1)
            didFit = true
        }
        centerPaper()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        paper
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPaper()
    }

    private func centerPaper() {
        let boundsSize = bounds.size
        var frame = paper.frame
        frame.origin.x = frame.size.width < boundsSize.width
            ? (boundsSize.width - frame.size.width) / 2
            : 0
        frame.origin.y = frame.size.height < boundsSize.height
            ? (boundsSize.height - frame.size.height) / 2
            : 0
        paper.frame = frame
    }
}

final class BonePaperDrawView: UIView {
    var document: BonePaperDocument?
    var tool: BonePaperTool = .pen
    var color: UIColor = .black
    var brushSize: CGFloat = 16
    var preview: CGImage?

    private var lastPoint: CGPoint?
    private var stroking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BonePaperDrawView coder")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        drawCheckerboard(ctx)
        if let preview {
            UIImage(cgImage: preview).draw(in: bounds)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if event?.allTouches?.count != 1 { return }
        guard let touch = touches.first, let document else { return }
        document.beginStroke()
        let point = bitmapPoint(touch)
        lastPoint = point
        stroking = true
        document.stampDot(at: point, color: color, size: brushSize, erase: tool == .eraser)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !stroking { return }
        if event?.allTouches?.count != 1 {
            lastPoint = nil
            stroking = false
            return
        }
        guard let touch = touches.first, let document, let last = lastPoint else { return }
        let point = bitmapPoint(touch)
        document.stamp(from: last, to: point, color: color, size: brushSize, erase: tool == .eraser)
        lastPoint = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoint = nil
        stroking = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoint = nil
        stroking = false
    }

    private func bitmapPoint(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        let side = CGFloat(BonePaperDocument.side)
        return CGPoint(
            x: p.x / bounds.width * side,
            y: (1 - p.y / bounds.height) * side
        )
    }

    private func drawCheckerboard(_ ctx: CGContext) {
        let cell: CGFloat = 16
        var y: CGFloat = 0
        var row = 0
        while y < bounds.height {
            var x: CGFloat = 0
            var col = 0
            while x < bounds.width {
                let light = (row + col) % 2 == 0
                ctx.setFillColor(UIColor(white: light ? 0.93 : 0.86, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
                x += cell
                col += 1
            }
            y += cell
            row += 1
        }
    }
}
