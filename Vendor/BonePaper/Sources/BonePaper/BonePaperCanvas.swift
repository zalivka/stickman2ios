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
    var zoom: Binding<CGFloat>
    var fitInsets: UIEdgeInsets

    func makeUIView(context: Context) -> BonePaperScrollView {
        let scroll = BonePaperScrollView()
        apply(scroll)
        return scroll
    }

    func updateUIView(_ scroll: BonePaperScrollView, context: Context) {
        apply(scroll)
    }

    private func apply(_ scroll: BonePaperScrollView) {
        scroll.paper.document = document
        scroll.paper.tool = tool
        scroll.paper.color = color
        scroll.paper.brushSize = brushSize
        scroll.paper.opacity = opacity
        scroll.paper.boneStart = boneStart
        scroll.paper.boneTip = boneTip
        scroll.paper.onion = onion
        scroll.onZoom = { zoom.wrappedValue = $0 }
        scroll.setPanMode(tool == .pan)
        scroll.fitInsets = fitInsets
        scroll.layoutPaper(side: CGFloat(document.worldSize))
        scroll.paper.show(document)
    }
}

final class BonePaperScrollView: UIScrollView, UIScrollViewDelegate {
    let paper = BonePaperDrawView()
    var onZoom: ((CGFloat) -> Void)?
    var fitInsets: UIEdgeInsets = .zero {
        didSet {
            if oldValue == fitInsets {
                return
            }
            didFit = false
            setNeedsLayout()
        }
    }
    private var didFit = false
    private var paperSide: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(paper)
        minimumZoomScale = 0.1
        maximumZoomScale = 8
        delegate = self
        delaysContentTouches = false
        panGestureRecognizer.minimumNumberOfTouches = 2
        pinchGestureRecognizer?.isEnabled = true
        pinchGestureRecognizer?.addTarget(self, action: #selector(pinchMayStealStroke))
        bouncesZoom = true
        backgroundColor = BonePaperDrawView.paneGray
        contentInsetAdjustmentBehavior = .never
    }

    // ScrollView owns the pinch; the paper view may not see the second finger.
    @objc private func pinchMayStealStroke(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .began || pinch.state == .changed {
            paper.abortStroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BonePaperScrollView coder")
    }

    func setPanMode(_ on: Bool) {
        paper.isUserInteractionEnabled = !on
        panGestureRecognizer.minimumNumberOfTouches = on ? 1 : 2
    }

    func layoutPaper(side: CGFloat) {
        if paperSide == side {
            return
        }
        paperSide = side
        paper.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        paper.center = CGPoint(x: side / 2, y: side / 2)
        contentSize = CGSize(width: side, height: side)
        didFit = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !didFit, bounds.width > 0, bounds.height > 0, paperSide > 0 {
            didFit = true
            fitDrawing()
            paper.setZoom(zoomScale)
            onZoom?(zoomScale)
            return
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        paper
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        paper.setZoom(zoomScale)
        centerPaper()
        onZoom?(zoomScale)
    }

    private func fitDrawing() {
        guard let document = paper.document else {
            fatalError("BonePaperScrollView fit with no document")
        }
        let drawW = CGFloat(document.width)
        let drawH = CGFloat(document.height)
        let availW = max(bounds.width - fitInsets.left - fitInsets.right, 1)
        let availH = max(bounds.height - fitInsets.top - fitInsets.bottom, 1)
        let raw = min(availW / drawW, availH / drawH)
        zoomScale = min(max(raw, minimumZoomScale), maximumZoomScale)
        let center: CGPoint
        if let start = paper.boneStart, let tip = paper.boneTip {
            center = CGPoint(
                x: CGFloat(document.originX) + CGFloat(document.extraLeft) + (start.x + tip.x) / 2,
                y: CGFloat(document.originY) + CGFloat(document.extraTop) + (start.y + tip.y) / 2
            )
        } else {
            center = CGPoint(
                x: CGFloat(document.originX) + drawW / 2,
                y: CGFloat(document.originY) + drawH / 2
            )
        }
        centerWorld(center)
    }

    private func centerWorld(_ world: CGPoint) {
        let desired = CGPoint(
            x: world.x * zoomScale - (bounds.width + fitInsets.left - fitInsets.right) / 2,
            y: world.y * zoomScale - (bounds.height + fitInsets.top - fitInsets.bottom) / 2
        )
        let zoomedW = paper.bounds.width * zoomScale
        let zoomedH = paper.bounds.height * zoomScale
        contentInset = UIEdgeInsets(
            top: max(-desired.y, 0),
            left: max(-desired.x, 0),
            bottom: max(desired.y + bounds.height - zoomedH, 0),
            right: max(desired.x + bounds.width - zoomedW, 0)
        )
        contentOffset = desired
    }

    private func centerPaper() {
        let zoomedW = paper.bounds.width * zoomScale
        let zoomedH = paper.bounds.height * zoomScale
        let insetX = max((bounds.width - zoomedW) * 0.5, 0)
        let insetY = max((bounds.height - zoomedH) * 0.5, 0)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}

final class BonePaperDrawView: UIView {
    var document: BonePaperDocument?
    var tool: BonePaperTool = .pen
    var color: UIColor = .black
    var brushSize: CGFloat = 16
    var opacity: CGFloat = 1
    var boneStart: CGPoint?
    var boneTip: CGPoint?
    var onion: CGImage?

    private let checker = UIView()
    private let onionView = UIImageView()
    private let bitmap = UIImageView()
    private let frameLayer = CAShapeLayer()
    private let boneLayer = CAShapeLayer()
    private var lastWorld: CGPoint?
    private var pendingView: CGPoint?
    private var stroking = false
    private var zoomScale: CGFloat = 1
    // Screen points before a brush/eraser stroke starts. Lets a still finger wait for pinch.
    private static let strokeSlop: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isOpaque = true
        backgroundColor = Self.paneGray
        checker.isUserInteractionEnabled = false
        checker.backgroundColor = Self.checkerColor
        onionView.isUserInteractionEnabled = false
        onionView.contentMode = .scaleToFill
        onionView.backgroundColor = .clear
        bitmap.isUserInteractionEnabled = false
        bitmap.contentMode = .scaleToFill
        bitmap.backgroundColor = .clear
        frameLayer.fillColor = nil
        frameLayer.strokeColor = UIColor(red: 1, green: 0.35, blue: 0.72, alpha: 1).cgColor
        frameLayer.lineWidth = 1
        boneLayer.fillColor = UIColor(red: 0, green: 0.75, blue: 1, alpha: 1).cgColor
        boneLayer.strokeColor = UIColor(red: 0, green: 0.75, blue: 1, alpha: 1).cgColor
        boneLayer.lineWidth = 3
        addSubview(checker)
        addSubview(onionView)
        addSubview(bitmap)
        layer.addSublayer(frameLayer)
        layer.addSublayer(boneLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BonePaperDrawView coder")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        checker.frame = bounds
        onionView.frame = bounds
    }

    func setZoom(_ zoom: CGFloat) {
        zoomScale = zoom
        frameLayer.lineWidth = 1 / max(zoom, 0.01)
        if let document {
            layoutMarks(document)
        }
    }

    func show(_ document: BonePaperDocument) {
        onionView.frame = bounds
        if let onion {
            onionView.image = UIImage(cgImage: onion)
            onionView.isHidden = false
        } else {
            onionView.image = nil
            onionView.isHidden = true
        }
        let rect = bitmapRect(document)
        bitmap.frame = rect
        bitmap.image = UIImage(cgImage: document.preview)
        layoutMarks(document)
    }

    private func layoutMarks(_ document: BonePaperDocument) {
        let rect = bitmapRect(document)
        let inset = frameLayer.lineWidth / 2
        frameLayer.path = CGPath(rect: rect.insetBy(dx: inset, dy: inset), transform: nil)
        guard let start = boneStart, let tip = boneTip else {
            boneLayer.path = nil
            return
        }
        let from = viewPoint(start, document: document, bitmap: rect)
        let to = viewPoint(tip, document: document, bitmap: rect)
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        path.addEllipse(in: CGRect(x: from.x - 6, y: from.y - 6, width: 12, height: 12))
        path.addEllipse(in: CGRect(x: to.x - 6, y: to.y - 6, width: 12, height: 12))
        boneLayer.path = path
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if tool == .pan { return }
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first else { return }
        lastWorld = worldPoint(touch)
        if tool == .fill {
            return
        }
        pendingView = touch.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first, let document else { return }
        let point = worldPoint(touch)
        if tool == .fill {
            lastWorld = point
            return
        }
        let view = touch.location(in: self)
        if !stroking {
            guard let startView = pendingView, let startWorld = lastWorld else { return }
            let dx = view.x - startView.x
            let dy = view.y - startView.y
            if hypot(dx, dy) < Self.strokeSlop {
                return
            }
            document.beginStroke(erase: tool == .eraser, opacity: opacity)
            stroking = true
            document.stampDotWorld(at: startWorld, color: color, size: brushSize, erase: tool == .eraser)
            document.stampWorld(from: startWorld, to: point, color: color, size: brushSize, erase: tool == .eraser)
            lastWorld = point
            return
        }
        guard let last = lastWorld else { return }
        document.stampWorld(from: last, to: point, color: color, size: brushSize, erase: tool == .eraser)
        lastWorld = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        abortStroke()
    }

    // Second finger or pinch: discard, do not endStroke() which would keep the speck.
    func abortStroke() {
        if stroking {
            document?.cancelStroke()
        }
        lastWorld = nil
        pendingView = nil
        stroking = false
    }

    private func finishStroke() {
        if tool == .fill {
            if let point = lastWorld {
                document?.fillWorld(at: point, color: color, opacity: opacity)
            }
        } else if stroking {
            document?.endStroke()
        }
        lastWorld = nil
        pendingView = nil
        stroking = false
    }

    private func worldPoint(_ touch: UITouch) -> CGPoint {
        guard let document else {
            fatalError("BonePaperDrawView worldPoint with no document")
        }
        let p = touch.location(in: self)
        let side = CGFloat(document.worldSize)
        return CGPoint(
            x: p.x / bounds.width * side,
            y: p.y / bounds.height * side
        )
    }

    private func bitmapRect(_ document: BonePaperDocument) -> CGRect {
        let side = CGFloat(document.worldSize)
        return CGRect(
            x: CGFloat(document.originX) / side * bounds.width,
            y: CGFloat(document.originY) / side * bounds.height,
            width: CGFloat(document.width) / side * bounds.width,
            height: CGFloat(document.height) / side * bounds.height
        )
    }

    private func viewPoint(_ png: CGPoint, document: BonePaperDocument, bitmap: CGRect) -> CGPoint {
        let x = png.x + CGFloat(document.extraLeft)
        let y = png.y + CGFloat(document.extraTop)
        return CGPoint(
            x: bitmap.minX + x / CGFloat(document.width) * bitmap.width,
            y: bitmap.minY + y / CGFloat(document.height) * bitmap.height
        )
    }

    static let paneGray = UIColor(white: 0.78, alpha: 1)

    private static let checkerColor: UIColor = {
        let cell: CGFloat = 16
        let size = CGSize(width: cell * 2, height: cell * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            paneGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.86, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: cell, height: cell))
            ctx.fill(CGRect(x: cell, y: cell, width: cell, height: cell))
        }
        return UIColor(patternImage: image)
    }()
}
