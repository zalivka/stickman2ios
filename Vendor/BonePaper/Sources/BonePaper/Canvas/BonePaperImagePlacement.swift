import CoreGraphics
import UIKit

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
