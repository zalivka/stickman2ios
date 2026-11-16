import QuartzCore
import UIKit

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
