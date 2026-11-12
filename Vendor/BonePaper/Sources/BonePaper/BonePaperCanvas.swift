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

/// Floating image state and 1-finger move/scale/rotate gesture handler for `BonePaperStageView`.
/// Center coordinates are stored in world space so page growth does not shift the image.
final class BonePaperImagePlacement {
    static let boxColor = UIColor(red: 0x45 / 255.0, green: 0x96 / 255.0, blue: 0xFF / 255.0, alpha: 1)
    static let rotateColor = UIColor(red: 1.0, green: 0x91 / 255.0, blue: 0, alpha: 1)
    static let initialMaxPageFraction: CGFloat = 0.7
    static let minSidePagePx: CGFloat = 8
    static let rotateStemPt: CGFloat = 28
    static let cornerHandleRadiusPt: CGFloat = 8
    static let rotateHandleRadiusPt: CGFloat = 10
    static let handleHitRadiusPt: CGFloat = 24

    private enum GestureMode {
        case none
        case move
        case scale
        case rotate
    }

    let image: CGImage
    private(set) var centerWorld: CGPoint
    private(set) var scale: CGFloat
    private(set) var angleRadians: CGFloat

    private var gestureMode: GestureMode = .none
    private var downCenterWorld: CGPoint = .zero
    private var downScale: CGFloat = 1
    private var downAngleRadians: CGFloat = 0
    private var downTouchWorld: CGPoint = .zero
    private var downCenterScreen: CGPoint = .zero
    private var downDistScreen: CGFloat = 1
    private var downAngleScreenRad: CGFloat = 0

    private var screenCorners: [CGPoint] = Array(repeating: .zero, count: 4)
    private var screenTopMid: CGPoint = .zero
    private var screenCenter: CGPoint = .zero
    private var screenRotateHandle: CGPoint = .zero

    private init(
        image: CGImage,
        centerWorld: CGPoint,
        scale: CGFloat,
        angleRadians: CGFloat
    ) {
        self.image = image
        self.centerWorld = centerWorld
        self.scale = scale
        self.angleRadians = angleRadians
    }

    static func create(
        image: CGImage,
        document: BonePaperDocument,
        boneStart: CGPoint?,
        boneTip: CGPoint?,
        stageAngle: CGFloat,
        stageMirror: Bool
    ) -> BonePaperImagePlacement {
        if image.width < 1 || image.height < 1 {
            fatalError("BonePaperImagePlacement invalid image size \(image.width)x\(image.height)")
        }
        let centerWorld: CGPoint
        if let start = boneStart, let tip = boneTip {
            centerWorld = CGPoint(
                x: CGFloat(document.originX + document.extraLeft) + (start.x + tip.x) * 0.5,
                y: CGFloat(document.originY + document.extraTop) + (start.y + tip.y) * 0.5
            )
        } else {
            centerWorld = CGPoint(
                x: CGFloat(document.originX) + CGFloat(document.width) * 0.5,
                y: CGFloat(document.originY) + CGFloat(document.height) * 0.5
            )
        }
        let maxW = CGFloat(document.width) * initialMaxPageFraction
        let maxH = CGFloat(document.height) * initialMaxPageFraction
        let fitScale = min(1, min(maxW / CGFloat(image.width), maxH / CGFloat(image.height)))
        let initialScale = clampScale(for: image, candidate: fitScale)
        let initialAngle = stageMirror ? stageAngle : -stageAngle

        return BonePaperImagePlacement(
            image: image,
            centerWorld: centerWorld,
            scale: initialScale,
            angleRadians: initialAngle
        )
    }

    func worldTransform() -> CGAffineTransform {
        CGAffineTransform(translationX: centerWorld.x, y: centerWorld.y)
            .rotated(by: angleRadians)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -CGFloat(image.width) * 0.5, y: -CGFloat(image.height) * 0.5)
    }

    func computeScreenGeometry(worldToScreen: (CGPoint) -> CGPoint) -> (
        corners: [CGPoint],
        topMid: CGPoint,
        rotateHandle: CGPoint
    ) {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let m = worldTransform()
        let localCorners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: w, y: 0),
            CGPoint(x: w, y: h),
            CGPoint(x: 0, y: h)
        ]
        for i in 0..<4 {
            screenCorners[i] = worldToScreen(localCorners[i].applying(m))
        }
        screenTopMid = worldToScreen(CGPoint(x: w * 0.5, y: 0).applying(m))
        screenCenter = worldToScreen(CGPoint(x: w * 0.5, y: h * 0.5).applying(m))

        let dirX = screenTopMid.x - screenCenter.x
        let dirY = screenTopMid.y - screenCenter.y
        let len = hypot(dirX, dirY)
        if len > 1e-3 {
            screenRotateHandle = CGPoint(
                x: screenTopMid.x + (dirX / len) * Self.rotateStemPt,
                y: screenTopMid.y + (dirY / len) * Self.rotateStemPt
            )
        } else {
            screenRotateHandle = CGPoint(
                x: screenTopMid.x,
                y: screenTopMid.y - Self.rotateStemPt
            )
        }
        return (screenCorners, screenTopMid, screenRotateHandle)
    }

    func onDown(
        screenPoint: CGPoint,
        worldToScreen: (CGPoint) -> CGPoint,
        screenToWorld: (CGPoint) -> CGPoint
    ) {
        _ = computeScreenGeometry(worldToScreen: worldToScreen)
        downCenterWorld = centerWorld
        downScale = scale
        downAngleRadians = angleRadians
        downCenterScreen = screenCenter

        if hypot(screenPoint.x - screenRotateHandle.x, screenPoint.y - screenRotateHandle.y) <= Self.handleHitRadiusPt {
            gestureMode = .rotate
            downAngleScreenRad = atan2(
                screenPoint.y - downCenterScreen.y,
                screenPoint.x - downCenterScreen.x
            )
            return
        }

        for corner in screenCorners {
            if hypot(screenPoint.x - corner.x, screenPoint.y - corner.y) <= Self.handleHitRadiusPt {
                gestureMode = .scale
                downDistScreen = max(
                    1,
                    hypot(screenPoint.x - downCenterScreen.x, screenPoint.y - downCenterScreen.y)
                )
                return
            }
        }

        gestureMode = .move
        downTouchWorld = screenToWorld(screenPoint)
    }

    func onMove(
        screenPoint: CGPoint,
        stageMirror: Bool,
        screenToWorld: (CGPoint) -> CGPoint
    ) {
        switch gestureMode {
        case .none:
            return
        case .rotate:
            let angleRad = atan2(
                screenPoint.y - downCenterScreen.y,
                screenPoint.x - downCenterScreen.x
            )
            let delta = angleRad - downAngleScreenRad
            angleRadians = downAngleRadians + (stageMirror ? -delta : delta)
        case .scale:
            let dist = max(
                1,
                hypot(screenPoint.x - downCenterScreen.x, screenPoint.y - downCenterScreen.y)
            )
            scale = Self.clampScale(for: image, candidate: downScale * (dist / downDistScreen))
        case .move:
            let touchWorld = screenToWorld(screenPoint)
            centerWorld = CGPoint(
                x: downCenterWorld.x + (touchWorld.x - downTouchWorld.x),
                y: downCenterWorld.y + (touchWorld.y - downTouchWorld.y)
            )
        }
    }

    func endGesture() {
        gestureMode = .none
    }

    func cancelGesture() {
        if gestureMode != .none {
            centerWorld = downCenterWorld
            scale = downScale
            angleRadians = downAngleRadians
            gestureMode = .none
        }
    }

    private static func clampScale(for image: CGImage, candidate: CGFloat) -> CGFloat {
        let minSide = CGFloat(max(1, min(image.width, image.height)))
        let maxSide = CGFloat(max(1, max(image.width, image.height)))
        let minScale = minSidePagePx / minSide
        let maxScale = (CGFloat(BonePaperDocument.maxSide) * 2) / maxSide
        return max(minScale, min(maxScale, candidate))
    }
}

/// Lets the screen run the exit zoom on the UIKit stage.
final class BonePaperStage {
    weak var view: BonePaperStageView?

    var hasImagePlacement: Bool {
        view?.hasImagePlacement ?? false
    }

    func startImagePlacement(_ image: CGImage) {
        view?.startImagePlacement(image)
    }

    func commitImagePlacement() -> Bool {
        view?.commitImagePlacement() ?? false
    }

    func cancelImagePlacement() {
        view?.cancelImagePlacement()
    }

    func zoomBack(duration: TimeInterval, completion: @escaping () -> Void) {
        guard let view else {
            fatalError("BonePaperStage zoomBack with no view")
        }
        view.zoomBack(duration: duration, completion: completion)
    }

    /// Colour under a window point. Black when the point misses the picture. Nil on a clear pixel.
    func sampleColor(atWindow point: CGPoint) -> UIColor? {
        guard let view else {
            return nil
        }
        return view.sampleColor(atWindow: point)
    }

    func clearCursor() {
        view?.hideOffsetCursor()
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
    var paper: UIColor?
    var placement: BonePaperPlacement?
    var stage: BonePaperStage
    var zoom: Binding<CGFloat>
    var fitInsets: UIEdgeInsets
    var onCommitStroke: () -> Void
    var onImagePlacementChanged: ((Bool) -> Void)? = nil

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
        view.setPanMode(tool == .pan)
        view.fitInsets = fitInsets
        view.layoutPaper(side: CGFloat(document.worldSize))
        view.paper.show(document)
        view.syncImagePlacement()
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

final class BonePaperDrawView: UIView {
    weak var stageView: BonePaperStageView?
    var document: BonePaperDocument?
    var tool: BonePaperTool = .pen
    var color: UIColor = .black
    var brushSize: CGFloat = 16
    var opacity: CGFloat = 1
    var boneStart: CGPoint?
    var boneTip: CGPoint?
    var onion: CGImage?
    /// Sheet colour drawn under the bitmap rect in place of the checker.
    var paperColor: UIColor?
    var onCommitStroke: (() -> Void)?

    private let checker = UIView()
    private let paperView = UIView()
    private let onionView = UIImageView()
    private weak var displayedOnion: CGImage?
    private let bitmap = UIImageView()
    private let placementClipView = UIView()
    private let placementImageView = UIImageView()
    private weak var displayedPlacementImage: CGImage?
    /// Displays `document.maskOverlay` above the drawing to dim the area outside the active mask.
    /// Named `maskOverlayView` to avoid colliding with `UIView.mask`.
    private let maskOverlayView = UIImageView()
    private weak var displayedMaskOverlay: CGImage?
    private let frameLayer = CAShapeLayer()
    private let boneLayer = CAShapeLayer()
    private var lastWorld: CGPoint?
    private var strokeStartWorld: CGPoint?
    private var leftCloseZone = false
    private var pendingView: CGPoint?
    private var stroking = false
    private var zoomScale: CGFloat = 1
    // Screen points before a brush/eraser stroke starts. Lets a still finger wait for pinch.
    // Divided by zoom when zoomed in, so the same gap is not a long stretch of the paper.
    private static let strokeSlop: CGFloat = 12
    private static let closeRadius: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isOpaque = false
        backgroundColor = .clear
        checker.isUserInteractionEnabled = false
        checker.backgroundColor = Self.checkerColor
        paperView.isUserInteractionEnabled = false
        paperView.isHidden = true
        onionView.isUserInteractionEnabled = false
        onionView.contentMode = .scaleToFill
        onionView.backgroundColor = .clear
        bitmap.isUserInteractionEnabled = false
        bitmap.contentMode = .scaleToFill
        bitmap.backgroundColor = .clear
        placementClipView.isUserInteractionEnabled = false
        placementClipView.clipsToBounds = true
        placementClipView.backgroundColor = .clear
        placementClipView.isHidden = true
        placementImageView.isUserInteractionEnabled = false
        placementImageView.contentMode = .scaleToFill
        placementImageView.backgroundColor = .clear
        placementClipView.addSubview(placementImageView)
        maskOverlayView.isUserInteractionEnabled = false
        maskOverlayView.contentMode = .scaleToFill
        maskOverlayView.backgroundColor = .clear
        maskOverlayView.isHidden = true
        frameLayer.fillColor = nil
        frameLayer.strokeColor = UIColor(red: 1, green: 0.35, blue: 0.72, alpha: 1).cgColor
        frameLayer.lineWidth = 1
        boneLayer.fillColor = UIColor(red: 0, green: 0.75, blue: 1, alpha: 1).cgColor
        boneLayer.strokeColor = UIColor(red: 0, green: 0.75, blue: 1, alpha: 1).cgColor
        boneLayer.lineWidth = 3
        addSubview(checker)
        addSubview(paperView)
        addSubview(onionView)
        addSubview(bitmap)
        addSubview(placementClipView)
        addSubview(maskOverlayView)
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
        maskOverlayView.alpha = alpha
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
        document?.recorder.zoom = zoom
        frameLayer.lineWidth = 1 / max(zoom, 0.01)
        if let document {
            layoutMarks(document)
        }
    }

    func show(_ document: BonePaperDocument) {
        onionView.frame = bounds
        if displayedOnion !== onion {
            displayedOnion = onion
            if let onion {
                onionView.image = UIImage(cgImage: onion)
                onionView.isHidden = false
            } else {
                onionView.image = nil
                onionView.isHidden = true
            }
        }
        let rect = bitmapRect(document)
        bitmap.frame = rect
        bitmap.image = UIImage(cgImage: document.preview)
        maskOverlayView.frame = rect
        if displayedMaskOverlay !== document.maskOverlay {
            displayedMaskOverlay = document.maskOverlay
            if let overlay = document.maskOverlay {
                maskOverlayView.image = UIImage(cgImage: overlay)
                maskOverlayView.isHidden = false
            } else {
                maskOverlayView.image = nil
                maskOverlayView.isHidden = true
            }
        }
        paperView.frame = rect
        paperView.backgroundColor = paperColor
        paperView.isHidden = paperColor == nil
        layoutMarks(document)
        updatePlacementLayer(stageView?.imagePlacement)
    }

    func updatePlacementLayer(_ placement: BonePaperImagePlacement?) {
        guard let placement, let document else {
            placementClipView.isHidden = true
            placementImageView.image = nil
            displayedPlacementImage = nil
            return
        }
        let clipRect = (boneStart != nil && boneTip != nil) ? bounds : bitmapRect(document)
        placementClipView.frame = clipRect
        placementClipView.isHidden = false
        if displayedPlacementImage !== placement.image {
            displayedPlacementImage = placement.image
            placementImageView.image = UIImage(cgImage: placement.image)
            placementImageView.bounds = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(placement.image.width),
                height: CGFloat(placement.image.height)
            )
        }
        let side = CGFloat(document.worldSize)
        let scaleFactor = bounds.width > 0 ? bounds.width / side : 1
        placementImageView.transform = CGAffineTransform(
            scaleX: placement.scale * scaleFactor,
            y: placement.scale * scaleFactor
        ).rotated(by: placement.angleRadians)
        placementImageView.center = CGPoint(
            x: placement.centerWorld.x * scaleFactor - clipRect.minX,
            y: placement.centerWorld.y * scaleFactor - clipRect.minY
        )
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
        if let stageView, let placement = stageView.imagePlacement {
            if event?.allTouches?.count != 1 {
                placement.cancelGesture()
                stageView.syncImagePlacement()
                return
            }
            guard let touch = touches.first else { return }
            let screenPt = touch.location(in: stageView)
            placement.onDown(
                screenPoint: screenPt,
                worldToScreen: { stageView.stagePoint(fromWorld: $0) },
                screenToWorld: { stageView.worldPoint(fromStage: $0) }
            )
            stageView.syncImagePlacement()
            return
        }
        if tool == .pan { return }
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first else { return }
        updateStageCursor(for: touch)
        document?.recorder.touchDown(samples(touch, event), input: touch.type)
        let start = worldPoint(touch)
        lastWorld = start
        strokeStartWorld = start
        leftCloseZone = false
        if tool == .bucket {
            return
        }
        pendingView = touch.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if document?.filling == true { return }
        if let stageView, let placement = stageView.imagePlacement {
            if event?.allTouches?.count != 1 {
                placement.cancelGesture()
                stageView.syncImagePlacement()
                return
            }
            guard let touch = touches.first else { return }
            let screenPt = touch.location(in: stageView)
            placement.onMove(
                screenPoint: screenPt,
                stageMirror: stageView.isStageMirrored,
                screenToWorld: { stageView.worldPoint(fromStage: $0) }
            )
            stageView.syncImagePlacement()
            return
        }
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first, let document else { return }
        updateStageCursor(for: touch)
        document.recorder.touchMoved(samples(touch, event))
        let point = worldPoint(touch)
        if tool == .bucket {
            lastWorld = point
            return
        }
        let closeThresholdWorld = Self.closeRadius / max(zoomScale, 0.01)
        let view = touch.location(in: self)
        if !stroking {
            guard let startView = pendingView, let startWorld = lastWorld else { return }
            let dx = view.x - startView.x
            let dy = view.y - startView.y
            let slop = Self.strokeSlop / max(zoomScale, 1)
            if hypot(dx, dy) < slop {
                return
            }
            if (tool == .pen || tool == .brushfill), color.cgColor.alpha == 0 {
                return
            }
            if tool == .brushfill {
                document.beginBrushfillStroke(color: color, opacity: opacity)
                stroking = true
                strokeStartWorld = startWorld
                document.stampBrushfillWorld(from: startWorld, to: point)
                lastWorld = point
                return
            }
            document.beginStroke(erase: tool == .eraser, opacity: opacity)
            stroking = true
            strokeStartWorld = startWorld
            if hypot(point.x - startWorld.x, point.y - startWorld.y) > closeThresholdWorld {
                leftCloseZone = true
            }
            document.stampDotWorld(at: startWorld, color: color, size: brushSize, erase: tool == .eraser)
            document.stampWorld(from: startWorld, to: point, color: color, size: brushSize, erase: tool == .eraser)
            lastWorld = point
            return
        }
        guard let last = lastWorld else { return }
        if tool == .brushfill {
            document.stampBrushfillWorld(from: last, to: point)
            lastWorld = point
            return
        }
        if !leftCloseZone, let startWorld = strokeStartWorld,
           hypot(point.x - startWorld.x, point.y - startWorld.y) > closeThresholdWorld {
            leftCloseZone = true
        }
        document.stampWorld(from: last, to: point, color: color, size: brushSize, erase: tool == .eraser)
        lastWorld = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let stageView, let placement = stageView.imagePlacement {
            placement.endGesture()
            stageView.syncImagePlacement()
            return
        }
        if let touch = touches.first {
            document?.recorder.touchMoved(samples(touch, event))
        }
        finishStroke()
        document?.recorder.touchUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        abortStroke()
    }

    // Second finger or pinch: discard, do not endStroke() which would keep the speck.
    func abortStroke() {
        stageView?.hideOffsetCursor()
        if let stageView, let placement = stageView.imagePlacement {
            placement.cancelGesture()
            stageView.syncImagePlacement()
        }
        if stroking {
            document?.cancelStroke()
        }
        document?.recorder.touchAbort()
        lastWorld = nil
        strokeStartWorld = nil
        leftCloseZone = false
        pendingView = nil
        stroking = false
    }

    private func finishStroke() {
        stageView?.hideOffsetCursor()
        if document?.filling == true {
            lastWorld = nil
            strokeStartWorld = nil
            leftCloseZone = false
            pendingView = nil
            stroking = false
            return
        }
        if tool == .bucket {
            if let point = lastWorld {
                let fill: BonePaperFill = color.cgColor.alpha == 0
                    ? .clear
                    : .color(color, opacity: opacity)
                document?.fillWorld(at: point, fill: fill, onCommitted: onCommitStroke)
            }
        } else if stroking {
            if BonePaperFlags.autoCloseStroke,
               tool == .pen,
               leftCloseZone,
               let startWorld = strokeStartWorld,
               let endWorld = lastWorld,
               endWorld != startWorld,
               hypot(endWorld.x - startWorld.x, endWorld.y - startWorld.y) <= Self.closeRadius / max(zoomScale, 0.01) {
                document?.stampWorld(from: endWorld, to: startWorld, color: color, size: brushSize, erase: false)
            }
            document?.endStroke()
            onCommitStroke?()
        }
        lastWorld = nil
        strokeStartWorld = nil
        leftCloseZone = false
        pendingView = nil
        stroking = false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let stageView, let placement = stageView.imagePlacement {
            let screenPt = convert(point, to: stageView)
            let geom = placement.computeScreenGeometry { stageView.stagePoint(fromWorld: $0) }
            let r = BonePaperImagePlacement.handleHitRadiusPt
            if hypot(screenPt.x - geom.rotateHandle.x, screenPt.y - geom.rotateHandle.y) <= r {
                return true
            }
            for corner in geom.corners {
                if hypot(screenPt.x - corner.x, screenPt.y - corner.y) <= r {
                    return true
                }
            }
            return true
        }
        return super.point(inside: point, with: event)
    }

    /// Every coalesced sample of `touch` in this event (up to 240 Hz), in world coordinates with touch timestamps.
    private func samples(_ touch: UITouch, _ event: UIEvent?) -> [(CGPoint, TimeInterval)] {
        let all = event?.coalescedTouches(for: touch) ?? [touch]
        return all.map { (worldPoint($0), $0.timestamp) }
    }

    private func updateStageCursor(for touch: UITouch) {
        guard let stageView else { return }
        let rawStage = touch.location(in: stageView)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - BonePaperFlags.brushOffset)
        stageView.updateOffsetCursor(atStage: targetStage, tool: tool, brushSize: brushSize)
    }

    private func offsetLocation(for touch: UITouch) -> CGPoint {
        let offset = BonePaperFlags.brushOffset
        guard offset > 0, let stageView else {
            return touch.location(in: self)
        }
        let rawStage = touch.location(in: stageView)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - offset)
        return convert(targetStage, from: stageView)
    }

    private func worldPoint(_ touch: UITouch) -> CGPoint {
        guard let document else {
            fatalError("BonePaperDrawView worldPoint with no document")
        }
        let p = offsetLocation(for: touch)
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
