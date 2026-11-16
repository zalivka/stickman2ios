import QuartzCore
import UIKit

/// Holds the paper under one transform: joint at `anchorScreen`, turned by `angle`, optionally mirrored, scaled by `zoom`.
final class BonePaperStageView: UIView, UIGestureRecognizerDelegate {
    static let transitionDuration: TimeInterval = 0.3
    static let fadeOutDuration: TimeInterval = 0.2
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 8

    let paper = BonePaperDrawView()
    var onZoom: ((CGFloat) -> Void)?
    var onImagePlacementChanged: ((Bool) -> Void)?
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
    private let placementBoxHaloLayer = CAShapeLayer()
    private let placementBoxStrokeLayer = CAShapeLayer()
    private let placementCornerHandlesLayer = CAShapeLayer()
    private let placementRotateHandleLayer = CAShapeLayer()
    private let cursorHaloLayer = CAShapeLayer()
    private let cursorStrokeLayer = CAShapeLayer()
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
    private var panModeRequested = false
    private(set) var imagePlacement: BonePaperImagePlacement?

    var hasImagePlacement: Bool {
        imagePlacement != nil
    }

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
        paper.stageView = self

        placementBoxHaloLayer.fillColor = nil
        placementBoxHaloLayer.strokeColor = UIColor.white.withAlphaComponent(220.0 / 255.0).cgColor
        placementBoxHaloLayer.lineWidth = 3
        placementBoxHaloLayer.lineCap = .round
        placementBoxHaloLayer.lineJoin = .round
        placementBoxHaloLayer.isHidden = true
        layer.addSublayer(placementBoxHaloLayer)

        placementBoxStrokeLayer.fillColor = nil
        placementBoxStrokeLayer.strokeColor = BonePaperImagePlacement.boxColor.cgColor
        placementBoxStrokeLayer.lineWidth = 1.5
        placementBoxStrokeLayer.lineCap = .round
        placementBoxStrokeLayer.lineJoin = .round
        placementBoxStrokeLayer.isHidden = true
        layer.addSublayer(placementBoxStrokeLayer)

        placementCornerHandlesLayer.fillColor = UIColor.white.cgColor
        placementCornerHandlesLayer.strokeColor = BonePaperImagePlacement.boxColor.cgColor
        placementCornerHandlesLayer.lineWidth = 2
        placementCornerHandlesLayer.isHidden = true
        layer.addSublayer(placementCornerHandlesLayer)

        placementRotateHandleLayer.fillColor = BonePaperImagePlacement.rotateColor.cgColor
        placementRotateHandleLayer.strokeColor = UIColor.white.cgColor
        placementRotateHandleLayer.lineWidth = 2
        placementRotateHandleLayer.isHidden = true
        layer.addSublayer(placementRotateHandleLayer)

        cursorHaloLayer.fillColor = nil
        cursorHaloLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        cursorHaloLayer.lineWidth = 3
        cursorHaloLayer.lineCap = .round
        cursorHaloLayer.isHidden = true
        layer.addSublayer(cursorHaloLayer)

        cursorStrokeLayer.fillColor = nil
        cursorStrokeLayer.strokeColor = UIColor.black.withAlphaComponent(0.88).cgColor
        cursorStrokeLayer.lineWidth = 1.5
        cursorStrokeLayer.lineCap = .round
        cursorStrokeLayer.isHidden = true
        layer.addSublayer(cursorStrokeLayer)

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
        panModeRequested = on
        let effectivePan = on && imagePlacement == nil
        paper.isUserInteractionEnabled = !effectivePan
        pan.minimumNumberOfTouches = effectivePan ? 1 : 2
    }

    func startImagePlacement(_ image: CGImage) {
        guard let document = paper.document else { return }
        if document.filling { return }
        paper.abortStroke()
        imagePlacement = BonePaperImagePlacement.create(
            image: image,
            document: document,
            boneStart: paper.boneStart,
            boneTip: paper.boneTip,
            stageAngle: angle,
            stageMirror: mirror
        )
        setPanMode(panModeRequested)
        syncImagePlacement()
        onImagePlacementChanged?(true)
    }

    @discardableResult
    func commitImagePlacement() -> Bool {
        guard let currentPlacement = imagePlacement, let document = paper.document else {
            return false
        }
        if document.filling {
            return false
        }
        currentPlacement.cancelGesture()
        document.stampBitmapWorld(
            currentPlacement.image,
            centerWorld: currentPlacement.centerWorld,
            scale: currentPlacement.scale,
            angleRadians: currentPlacement.angleRadians
        )
        imagePlacement = nil
        setPanMode(panModeRequested)
        paper.show(document)
        syncImagePlacement()
        onImagePlacementChanged?(false)
        return true
    }

    func cancelImagePlacement() {
        guard let currentPlacement = imagePlacement else { return }
        currentPlacement.cancelGesture()
        imagePlacement = nil
        setPanMode(panModeRequested)
        syncImagePlacement()
        onImagePlacementChanged?(false)
    }

    func syncImagePlacement() {
        paper.updatePlacementLayer(imagePlacement)
        updatePlacementOverlay()
    }

    func updatePlacementOverlay() {
        guard let currentPlacement = imagePlacement else {
            if !placementBoxHaloLayer.isHidden {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                placementBoxHaloLayer.isHidden = true
                placementBoxStrokeLayer.isHidden = true
                placementCornerHandlesLayer.isHidden = true
                placementRotateHandleLayer.isHidden = true
                CATransaction.commit()
            }
            return
        }
        let geom = currentPlacement.computeScreenGeometry { world in
            screenPoint(world)
        }
        let boxPath = CGMutablePath()
        if geom.corners.count == 4 {
            boxPath.move(to: geom.corners[0])
            boxPath.addLine(to: geom.corners[1])
            boxPath.addLine(to: geom.corners[2])
            boxPath.addLine(to: geom.corners[3])
            boxPath.closeSubpath()
        }
        boxPath.move(to: geom.topMid)
        boxPath.addLine(to: geom.rotateHandle)

        let cornersPath = CGMutablePath()
        let cr = BonePaperImagePlacement.cornerHandleRadiusPt
        for corner in geom.corners {
            cornersPath.addEllipse(in: CGRect(x: corner.x - cr, y: corner.y - cr, width: cr * 2, height: cr * 2))
        }

        let rr = BonePaperImagePlacement.rotateHandleRadiusPt
        let rotatePath = CGPath(
            ellipseIn: CGRect(
                x: geom.rotateHandle.x - rr,
                y: geom.rotateHandle.y - rr,
                width: rr * 2,
                height: rr * 2
            ),
            transform: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placementBoxHaloLayer.path = boxPath
        placementBoxStrokeLayer.path = boxPath
        placementCornerHandlesLayer.path = cornersPath
        placementRotateHandleLayer.path = rotatePath
        placementBoxHaloLayer.isHidden = false
        placementBoxStrokeLayer.isHidden = false
        placementCornerHandlesLayer.isHidden = false
        placementRotateHandleLayer.isHidden = false
        CATransaction.commit()
    }

    func worldPoint(fromStage stagePt: CGPoint) -> CGPoint {
        guard let document = paper.document else {
            return .zero
        }
        let side = paper.bounds.width
        if side <= 0 {
            return .zero
        }
        let local = paper.convert(stagePt, from: self)
        let world = CGFloat(document.worldSize)
        return CGPoint(
            x: local.x / side * world,
            y: local.y / side * world
        )
    }

    func stagePoint(fromWorld worldPt: CGPoint) -> CGPoint {
        screenPoint(worldPt)
    }

    var isStageMirrored: Bool {
        mirror
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
        if gesture.state == .began || gesture.state == .changed {
            paper.abortStroke()
        }
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

    func updateOffsetCursor(atStage targetStage: CGPoint, tool: BonePaperTool, brushSize: CGFloat) {
        guard BonePaperFlags.brushOffset > 0 else {
            hideOffsetCursor()
            return
        }
        let path = CGMutablePath()
        switch tool {
        case .pen, .eraser:
            let radius = max((brushSize * zoom) / 2, 4)
            path.addEllipse(in: CGRect(
                x: targetStage.x - radius,
                y: targetStage.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            let cross: CGFloat = 5
            path.move(to: CGPoint(x: targetStage.x - cross, y: targetStage.y))
            path.addLine(to: CGPoint(x: targetStage.x + cross, y: targetStage.y))
            path.move(to: CGPoint(x: targetStage.x, y: targetStage.y - cross))
            path.addLine(to: CGPoint(x: targetStage.x, y: targetStage.y + cross))
        case .brushfill:
            let cross: CGFloat = 5
            path.move(to: CGPoint(x: targetStage.x - cross, y: targetStage.y))
            path.addLine(to: CGPoint(x: targetStage.x + cross, y: targetStage.y))
            path.move(to: CGPoint(x: targetStage.x, y: targetStage.y - cross))
            path.addLine(to: CGPoint(x: targetStage.x, y: targetStage.y + cross))
        case .bucket, .pan:
            let radius: CGFloat = 6
            let cross: CGFloat = 9
            path.addEllipse(in: CGRect(
                x: targetStage.x - radius,
                y: targetStage.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            path.move(to: CGPoint(x: targetStage.x - cross, y: targetStage.y))
            path.addLine(to: CGPoint(x: targetStage.x + cross, y: targetStage.y))
            path.move(to: CGPoint(x: targetStage.x, y: targetStage.y - cross))
            path.addLine(to: CGPoint(x: targetStage.x, y: targetStage.y + cross))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorHaloLayer.path = path
        cursorStrokeLayer.path = path
        cursorHaloLayer.isHidden = false
        cursorStrokeLayer.isHidden = false
        CATransaction.commit()
    }

    func hideOffsetCursor() {
        if cursorHaloLayer.isHidden && cursorStrokeLayer.isHidden {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorHaloLayer.isHidden = true
        cursorStrokeLayer.isHidden = true
        CATransaction.commit()
    }

    /// Window point → paint-buffer pixel, through the same transform that draws the paper.
    /// A point outside the picture is black. A clear pixel is nil.
    func sampleColor(atWindow point: CGPoint) -> UIColor? {
        guard let document = paper.document else {
            return nil
        }
        let side = paper.bounds.width
        if side <= 0 {
            return nil
        }
        let rawStage = convert(point, from: nil)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - BonePaperFlags.brushOffset)
        updateOffsetCursor(atStage: targetStage, tool: .bucket, brushSize: paper.brushSize)
        let local = paper.convert(targetStage, from: self)
        let world = CGFloat(document.worldSize)
        let at = CGPoint(x: local.x / side * world, y: local.y / side * world)
        let scale = CGFloat(BonePaperDocument.sample)
        let px = Int(floor((at.x - CGFloat(document.originX)) * scale))
        let py = Int(floor((at.y - CGFloat(document.originY)) * scale))
        if px < 0 || py < 0 || px >= document.pixelWidth || py >= document.pixelHeight {
            return .black
        }
        return document.color(atPixel: px, y: py)
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
        updatePlacementOverlay()
    }
}
