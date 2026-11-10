import CoreGraphics

/// Live Shift nudge for one bone picture. Owned as `@State` so the canvas redraws while the skeleton stays put.
struct BoneShiftPreview: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0

    var isIdentity: Bool { dx == 0 && dy == 0 }

    mutating func reset() {
        self = BoneShiftPreview()
    }

    /// Project a scene-space drag onto the bone and its perpendicular, in item pixels.
    /// Android `EditView.processShiftTouch` — bone-space (dx, dy) -> bitmap xOffset/yOffset.
    mutating func addDrag(move: CGPoint, edgeFrom: CGPoint, edgeTo: CGPoint, unitScale: CGFloat) {
        guard unitScale > 0, unitScale.isFinite else {
            assertionFailure("BoneShiftPreview unit scale \(unitScale)")
            return
        }
        let edgeVec = CGPoint(x: edgeTo.x - edgeFrom.x, y: edgeTo.y - edgeFrom.y)
        let edgeLen2 = edgeVec.x * edgeVec.x + edgeVec.y * edgeVec.y
        if edgeLen2 == 0 {
            return
        }
        let ortho = CGPoint(x: edgeVec.y, y: -edgeVec.x)
        // Android: dx = len(projX) * sign(projX.x), dy = len(projY) * sign(projY.y).
        // signum on x collapses to 0 for a vertical bone, so only one axis ever moves.
        // Keep the sign in the drag direction instead of the component:
        // step = dot(move, axis) / |axis| — full 2D movement along the bone.
        // iOS y is inverted vs Android bitmap space, so dy is negated.
        let len = hypot(edgeVec.x, edgeVec.y)
        let stepX = (move.x * edgeVec.x + move.y * edgeVec.y) / len
        let stepY = (move.x * ortho.x + move.y * ortho.y) / len
        let sign: CGFloat = edgeVec.x < 0 ? -1 : 1
        dx += stepX * sign / unitScale
        dy -= stepY * sign / unitScale
    }

    func live(
        assetStart: Int,
        assetEnd: Int,
        edgeFrom: Int,
        edgeTo: Int,
        active: Bool
    ) -> (dx: CGFloat, dy: CGFloat) {
        guard active || !isIdentity else {
            return (0, 0)
        }
        let same = (assetStart == edgeFrom && assetEnd == edgeTo)
            || (assetStart == edgeTo && assetEnd == edgeFrom)
        return same ? (dx, dy) : (0, 0)
    }
}
