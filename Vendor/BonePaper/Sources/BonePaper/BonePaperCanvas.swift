import SwiftUI
import UIKit

/// Where the bone sat on the caller's screen. BonePaper opens with the bitmap exactly there, then only zooms.
public struct BonePaperPlacement {
    /// Joint pixel (bone start) in window coordinates.
    public var jointScreen: CGPoint
    /// Bone direction on screen, radians, y down (`atan2(dy, dx)`).
    public var angle: CGFloat
    /// The bitmap is drawn with y negated around the bone.
    public var mirror: Bool
    /// Screen points per bitmap pixel.
    public var pointsPerPixel: CGFloat

    public init(jointScreen: CGPoint, angle: CGFloat, mirror: Bool, pointsPerPixel: CGFloat) {
        if pointsPerPixel <= 0 {
            fatalError("BonePaperPlacement pointsPerPixel \(pointsPerPixel)")
        }
        self.jointScreen = jointScreen
        self.angle = angle
        self.mirror = mirror
        self.pointsPerPixel = pointsPerPixel
    }
}

/// Lets the screen run the exit zoom on the UIKit stage.
final class BonePaperStage {
    weak var view: BonePaperStageView?

    func zoomBack(duration: TimeInterval, completion: @escaping () -> Void) {
        guard let view else {
            fatalError("BonePaperStage zoomBack with no view")
        }
        view.zoomBack(duration: duration, completion: completion)
    }
}

struct BonePaperCanvas: UIViewRepresentable {
    @ObservedObject var document: BonePaperDocument
    var tool: BonePaperTool
    var color: UIColor
    var brushSize: CGFloat
    var opacity: CGFloat
    var boneStart: CGPoint?
    var boneTip: CGPoint?
    var onion: CGImage?
    var placement: BonePaperPlacement?
    var stage: BonePaperStage
    var zoom: Binding<CGFloat>
    var fitInsets: UIEdgeInsets

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
        view.onZoom = { zoom.wrappedValue = $0 }
        view.setPanMode(tool == .pan)
        view.fitInsets = fitInsets
        view.layoutPaper(side: CGFloat(document.worldSize))
        view.paper.show(document)
    }
}

/// Holds the paper under one transform: joint at `anchorScreen`, turned by `angle`, optionally mirrored, scaled by `zoom`.
final class BonePaperStageView: UIView, UIGestureRecognizerDelegate {
    static let transitionDuration: TimeInterval = 0.3
    static let fadeOutDuration: TimeInterval = 0.2
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 8

    let paper = BonePaperDrawView()
    var onZoom: ((CGFloat) -> Void)?
    var fitInsets: UIEdgeInsets = .zero {
        didSet {
            if oldValue == fitInsets {
                return
            }
            needsFit = true
            setNeedsLayout()
        }
    }

    private let placement: BonePaperPlacement?
    private let backdrop = UIView()
    private let pan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private var paperSide: CGFloat = 0
    private let angle: CGFloat
    private let mirror: Bool
    /// World point (bitmap pixel units) pinned to `anchorScreen`.
    private var anchorWorld: CGPoint = .zero
    private var anchorScreen: CGPoint = .zero
    private var zoom: CGFloat = 1
    private var placed = false
    private var needsFit = true
    private var entryScreen: CGPoint = .zero
    private var entryZoom: CGFloat = 1

    init(placement: BonePaperPlacement?) {
        self.placement = placement
        angle = placement?.angle ?? 0
        mirror = placement?.mirror ?? false
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        backdrop.backgroundColor = BonePaperDrawView.paneGray
        backdrop.isUserInteractionEnabled = false
        addSubview(backdrop)
        addSubview(paper)
        pan.addTarget(self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
        pinch.addTarget(self, action: #selector(handlePinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        if placement != nil {
            backdrop.alpha = 0
            paper.setBackdropAlpha(0)
            paper.setFrameOpacity(0, duration: 0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BonePaperStageView coder")
    }

    func setPanMode(_ on: Bool) {
        paper.isUserInteractionEnabled = !on
        pan.minimumNumberOfTouches = on ? 1 : 2
    }

    func layoutPaper(side: CGFloat) {
        if paperSide == side {
            return
        }
        paperSide = side
        paper.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        needsFit = true
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        guard bounds.width > 0, bounds.height > 0, paperSide > 0, window != nil else {
            return
        }
        if !placed {
            placed = true
            needsFit = false
            if let placement {
                enter(placement)
            } else {
                fitLevel()
            }
            return
        }
        if needsFit {
            needsFit = false
            fitLevel()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pan && other === pinch) || (gestureRecognizer === pinch && other === pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        anchorScreen.x += delta.x
        anchorScreen.y += delta.y
        applyTransform()
    }

    // Stage owns the pinch; the paper view may not see the second finger.
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began || gesture.state == .changed {
            paper.abortStroke()
        }
        let focus = gesture.location(in: self)
        let next = min(max(zoom * gesture.scale, Self.minZoom), Self.maxZoom)
        gesture.scale = 1
        let factor = next / zoom
        anchorScreen = CGPoint(
            x: focus.x + (anchorScreen.x - focus.x) * factor,
            y: focus.y + (anchorScreen.y - focus.y) * factor
        )
        zoom = next
        applyTransform()
        paper.setZoom(zoom)
        onZoom?(zoom)
    }

    func zoomBack(duration: TimeInterval, completion: @escaping () -> Void) {
        if placement == nil {
            fatalError("BonePaperStageView zoomBack without placement")
        }
        anchorWorld = jointWorld()
        anchorScreen = entryScreen
        zoom = entryZoom
        paper.setFrameOpacity(0, duration: duration)
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut]) {
            self.backdrop.alpha = 0
            self.paper.setBackdropAlpha(0)
            self.applyTransform()
        } completion: { _ in
            // Cross-fade into the caller's picture underneath; the cover may still slide, but it is empty by then.
            UIView.animate(withDuration: Self.fadeOutDuration, delay: 0, options: [.curveEaseOut]) {
                self.paper.alpha = 0
            } completion: { _ in
                completion()
            }
        }
    }

    private func enter(_ placement: BonePaperPlacement) {
        guard paper.boneStart != nil, paper.boneTip != nil else {
            fatalError("BonePaperStageView placement without a bone")
        }
        anchorWorld = jointWorld()
        entryScreen = convert(placement.jointScreen, from: nil)
        entryZoom = placement.pointsPerPixel
        anchorScreen = entryScreen
        zoom = entryZoom
        applyTransform()
        paper.setZoom(zoom)

        let mid = boneMidWorld()
        let midScreen = screenPoint(mid)
        let target = fitZoom()
        anchorScreen = CGPoint(
            x: midScreen.x - offset(mid, zoom: target).x,
            y: midScreen.y - offset(mid, zoom: target).y
        )
        zoom = target
        keepDrawingInside()
        paper.setZoom(zoom)
        onZoom?(zoom)
        paper.setFrameOpacity(1, duration: Self.transitionDuration)
        UIView.animate(withDuration: Self.transitionDuration, delay: 0, options: [.curveEaseInOut]) {
            self.backdrop.alpha = 1
            self.paper.setBackdropAlpha(1)
            self.applyTransform()
        }
    }

    private func fitLevel() {
        guard let document = paper.document else {
            fatalError("BonePaperStageView fit with no document")
        }
        zoom = fitZoom()
        let avail = availRect()
        if paper.boneStart != nil, paper.boneTip != nil {
            anchorWorld = boneMidWorld()
        } else {
            anchorWorld = CGPoint(
                x: CGFloat(document.originX) + CGFloat(document.width) / 2,
                y: CGFloat(document.originY) + CGFloat(document.height) / 2
            )
        }
        anchorScreen = CGPoint(x: avail.midX, y: avail.midY)
        applyTransform()
        paper.setZoom(zoom)
        onZoom?(zoom)
    }

    private func fitZoom() -> CGFloat {
        guard let document = paper.document else {
            fatalError("BonePaperStageView fit with no document")
        }
        let box = rotatedSize(width: CGFloat(document.width), height: CGFloat(document.height))
        let avail = availRect()
        let raw = min(avail.width / box.width, avail.height / box.height)
        return min(max(raw, Self.minZoom), Self.maxZoom)
    }

    /// Slide the anchor so the turned drawing box stays in the free area, centered where it is larger.
    private func keepDrawingInside() {
        guard let document = paper.document else {
            fatalError("BonePaperStageView clamp with no document")
        }
        let avail = availRect()
        let box = rotatedSize(width: CGFloat(document.width), height: CGFloat(document.height))
        let center = screenPoint(CGPoint(
            x: CGFloat(document.originX) + CGFloat(document.width) / 2,
            y: CGFloat(document.originY) + CGFloat(document.height) / 2
        ))
        let halfW = box.width * zoom / 2
        let halfH = box.height * zoom / 2
        anchorScreen.x += Self.shift(center: center.x, half: halfW, low: avail.minX, high: avail.maxX)
        anchorScreen.y += Self.shift(center: center.y, half: halfH, low: avail.minY, high: avail.maxY)
    }

    private static func shift(center: CGFloat, half: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        if half * 2 >= high - low {
            return (low + high) / 2 - center
        }
        if center - half < low {
            return low - (center - half)
        }
        if center + half > high {
            return high - (center + half)
        }
        return 0
    }

    private func availRect() -> CGRect {
        CGRect(
            x: fitInsets.left,
            y: fitInsets.top,
            width: max(bounds.width - fitInsets.left - fitInsets.right, 1),
            height: max(bounds.height - fitInsets.top - fitInsets.bottom, 1)
        )
    }

    private func rotatedSize(width: CGFloat, height: CGFloat) -> CGSize {
        let c = abs(cos(angle))
        let s = abs(sin(angle))
        return CGSize(width: c * width + s * height, height: s * width + c * height)
    }

    private func jointWorld() -> CGPoint {
        guard let document = paper.document, let start = paper.boneStart else {
            fatalError("BonePaperStageView joint with no bone")
        }
        return CGPoint(
            x: CGFloat(document.originX + document.extraLeft) + start.x,
            y: CGFloat(document.originY + document.extraTop) + start.y
        )
    }

    private func boneMidWorld() -> CGPoint {
        guard let document = paper.document, let start = paper.boneStart, let tip = paper.boneTip else {
            fatalError("BonePaperStageView midpoint with no bone")
        }
        return CGPoint(
            x: CGFloat(document.originX + document.extraLeft) + (start.x + tip.x) / 2,
            y: CGFloat(document.originY + document.extraTop) + (start.y + tip.y) / 2
        )
    }

    private func linear(zoom: CGFloat) -> CGAffineTransform {
        let c = cos(angle) * zoom
        let s = sin(angle) * zoom
        let m: CGFloat = mirror ? -1 : 1
        return CGAffineTransform(a: c, b: s, c: -m * s, d: m * c, tx: 0, ty: 0)
    }

    /// Screen offset of `world` from the anchor at `zoom`.
    private func offset(_ world: CGPoint, zoom: CGFloat) -> CGPoint {
        CGPoint(x: world.x - anchorWorld.x, y: world.y - anchorWorld.y).applying(linear(zoom: zoom))
    }

    private func screenPoint(_ world: CGPoint) -> CGPoint {
        let d = offset(world, zoom: zoom)
        return CGPoint(x: anchorScreen.x + d.x, y: anchorScreen.y + d.y)
    }

    private func applyTransform() {
        let t = linear(zoom: zoom)
        let half = paperSide / 2
        let fromCenter = CGPoint(x: anchorWorld.x - half, y: anchorWorld.y - half).applying(t)
        paper.transform = t
        paper.center = CGPoint(x: anchorScreen.x - fromCenter.x, y: anchorScreen.y - fromCenter.y)
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
        isOpaque = false
        backgroundColor = .clear
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

    /// Checker and onion; the bitmap and bone marks stay visible through the transition. Animatable inside `UIView.animate`.
    func setBackdropAlpha(_ alpha: CGFloat) {
        checker.alpha = alpha
        onionView.alpha = alpha
    }

    /// The pink frame is a bare layer, so `UIView.animate` does not drive it.
    func setFrameOpacity(_ opacity: Float, duration: TimeInterval) {
        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
        } else {
            CATransaction.setDisableActions(true)
        }
        frameLayer.opacity = opacity
        CATransaction.commit()
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
        if document?.filling == true { return }
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
        if document?.filling == true { return }
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
        if document?.filling == true {
            lastWorld = nil
            pendingView = nil
            stroking = false
            return
        }
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
