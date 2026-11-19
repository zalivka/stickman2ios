import CoreGraphics
import UIKit

/// Full-canvas transform session for `BonePaperStageView` / `BonePaperDrawView`:
/// - 1 finger: translates the drawing (paint + active mask).
/// - 2 fingers: rotates and scales around the pinch midpoint without translation.
/// - Double-tap: cancels and exits transform mode.
final class BonePaperCanvasTransform {
    static let minScale: CGFloat = 0.05
    static let maxScale: CGFloat = 16
    static let touchSlopPt: CGFloat = 8
    static let doubleTapSlopPt: CGFloat = 24
    static let doubleTapTimeoutSec: TimeInterval = 0.3

    let initialOriginX: Int
    let initialOriginY: Int
    let initialWidth: Int
    let initialHeight: Int
    let initialWorldCorners: [CGPoint]

    private(set) var worldTransform: CGAffineTransform = .identity
    private var cumulativeScale: CGFloat = 1

    // 1-finger and 2-finger gesture state
    private var twoFingerMode = false
    private var ignoreUntilUp = false
    private var movedDuringDown = false
    private var multiTouchDuringDown = false
    private var downScreen: CGPoint = .zero
    private var lastOneFingerWorld: CGPoint = .zero
    private var lastTwoFingerSpan: CGFloat = 1
    private var lastTwoFingerAngleRad: CGFloat = 0

    // Double-tap state
    private var lastTapUpTime: TimeInterval = 0
    private var lastTapUpScreen: CGPoint = .zero

    private init(document: BonePaperDocument, contentBoundsWorld: CGRect) {
        self.initialOriginX = document.originX
        self.initialOriginY = document.originY
        self.initialWidth = document.width
        self.initialHeight = document.height
        self.initialWorldCorners = [
            CGPoint(x: contentBoundsWorld.minX, y: contentBoundsWorld.minY),
            CGPoint(x: contentBoundsWorld.maxX, y: contentBoundsWorld.minY),
            CGPoint(x: contentBoundsWorld.maxX, y: contentBoundsWorld.maxY),
            CGPoint(x: contentBoundsWorld.minX, y: contentBoundsWorld.maxY)
        ]
    }

    static func create(document: BonePaperDocument) -> BonePaperCanvasTransform? {
        guard let bounds = document.computeContentBoundsWorld() else {
            return nil
        }
        return BonePaperCanvasTransform(document: document, contentBoundsWorld: bounds)
    }

    func computeScreenCorners(worldToScreen: (CGPoint) -> CGPoint) -> [CGPoint] {
        initialWorldCorners.map { corner in
            worldToScreen(corner.applying(worldTransform))
        }
    }

    func onTouchesBegan(
        touches: Set<UITouch>,
        event: UIEvent?,
        stageView: BonePaperStageView
    ) {
        let allTouches = Array(event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? touches)
        if allTouches.count == 1, !multiTouchDuringDown {
            let touch = allTouches[0]
            twoFingerMode = false
            ignoreUntilUp = false
            movedDuringDown = false
            multiTouchDuringDown = false
            downScreen = touch.location(in: stageView)
            lastOneFingerWorld = stageView.worldPoint(fromStage: downScreen)
        } else if allTouches.count >= 2 {
            multiTouchDuringDown = true
            lastTapUpTime = 0
            twoFingerMode = true
            ignoreUntilUp = false
            rememberTwoFingerState(touches: allTouches, in: stageView)
        }
    }

    func onTouchesMoved(
        touches: Set<UITouch>,
        event: UIEvent?,
        stageView: BonePaperStageView
    ) {
        let allTouches = Array(event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? touches)
        if twoFingerMode, allTouches.count >= 2 {
            handleTwoFingerMove(touches: allTouches, stageView: stageView)
        } else if !twoFingerMode, !ignoreUntilUp, allTouches.count == 1 {
            let touch = allTouches[0]
            let screenPt = touch.location(in: stageView)
            let dxScreen = screenPt.x - downScreen.x
            let dyScreen = screenPt.y - downScreen.y
            if hypot(dxScreen, dyScreen) > Self.touchSlopPt {
                movedDuringDown = true
            }
            let worldPt = stageView.worldPoint(fromStage: screenPt)
            let dxWorld = worldPt.x - lastOneFingerWorld.x
            let dyWorld = worldPt.y - lastOneFingerWorld.y
            if dxWorld != 0 || dyWorld != 0 {
                worldTransform = worldTransform.concatenating(
                    CGAffineTransform(translationX: dxWorld, y: dyWorld)
                )
                lastOneFingerWorld = worldPt
            }
        }
    }

    /// Returns `true` if the user double-tapped to cancel and exit transform mode.
    func onTouchesEnded(
        touches: Set<UITouch>,
        event: UIEvent?,
        stageView: BonePaperStageView
    ) -> Bool {
        let remaining = Array(
            (event?.allTouches ?? touches).filter {
                !touches.contains($0) && $0.phase != .ended && $0.phase != .cancelled
            }
        )
        if !remaining.isEmpty {
            if remaining.count < 2 {
                twoFingerMode = false
                ignoreUntilUp = true
            } else {
                rememberTwoFingerState(touches: remaining, in: stageView)
            }
            return false
        }

        let wasTap = !multiTouchDuringDown && !movedDuringDown && !ignoreUntilUp
        twoFingerMode = false
        ignoreUntilUp = false
        multiTouchDuringDown = false
        movedDuringDown = false

        if wasTap, let touch = touches.first {
            let now = touch.timestamp
            let screenPt = touch.location(in: stageView)
            if lastTapUpTime > 0,
               (now - lastTapUpTime) <= Self.doubleTapTimeoutSec,
               hypot(screenPt.x - lastTapUpScreen.x, screenPt.y - lastTapUpScreen.y) <= Self.doubleTapSlopPt {
                lastTapUpTime = 0
                return true
            }
            lastTapUpTime = now
            lastTapUpScreen = screenPt
        } else {
            lastTapUpTime = 0
        }
        return false
    }

    func onTouchesCancelled() {
        twoFingerMode = false
        ignoreUntilUp = false
        multiTouchDuringDown = false
        movedDuringDown = false
        lastTapUpTime = 0
    }

    private func rememberTwoFingerState(touches: [UITouch], in stageView: BonePaperStageView) {
        guard touches.count >= 2 else { return }
        let p0 = touches[0].location(in: stageView)
        let p1 = touches[1].location(in: stageView)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        lastTwoFingerSpan = max(1, hypot(dx, dy))
        lastTwoFingerAngleRad = atan2(dy, dx)
    }

    private func handleTwoFingerMove(touches: [UITouch], stageView: BonePaperStageView) {
        guard touches.count >= 2 else { return }
        let p0 = touches[0].location(in: stageView)
        let p1 = touches[1].location(in: stageView)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let span = max(1, hypot(dx, dy))
        let angleRad = atan2(dy, dx)

        let midScreen = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        let pivotWorld = stageView.worldPoint(fromStage: midScreen)

        if lastTwoFingerSpan > 1 && span > 1 {
            let rawScaleFactor = span / lastTwoFingerSpan
            let nextScale = max(Self.minScale, min(Self.maxScale, cumulativeScale * rawScaleFactor))
            let appliedScale = nextScale / cumulativeScale
            if abs(appliedScale - 1) > 1e-5 {
                let scaleAroundPivot = CGAffineTransform(translationX: -pivotWorld.x, y: -pivotWorld.y)
                    .concatenating(CGAffineTransform(scaleX: appliedScale, y: appliedScale))
                    .concatenating(CGAffineTransform(translationX: pivotWorld.x, y: pivotWorld.y))
                worldTransform = worldTransform.concatenating(scaleAroundPivot)
                cumulativeScale = nextScale
            }
        }

        var deltaRad = angleRad - lastTwoFingerAngleRad
        while deltaRad > .pi {
            deltaRad -= 2 * .pi
        }
        while deltaRad < -.pi {
            deltaRad += 2 * .pi
        }
        let worldDeltaRad = stageView.isStageMirrored ? -deltaRad : deltaRad
        if abs(worldDeltaRad) > 1e-5 {
            let rotateAroundPivot = CGAffineTransform(translationX: -pivotWorld.x, y: -pivotWorld.y)
                .concatenating(CGAffineTransform(rotationAngle: worldDeltaRad))
                .concatenating(CGAffineTransform(translationX: pivotWorld.x, y: pivotWorld.y))
            worldTransform = worldTransform.concatenating(rotateAroundPivot)
        }

        lastTwoFingerSpan = span
        lastTwoFingerAngleRad = angleRad
    }
}
