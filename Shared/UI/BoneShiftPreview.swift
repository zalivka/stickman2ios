import CoreGraphics

/// Live Shift nudge for one bone picture. Owned as `@State` so the canvas redraws while the skeleton stays put.
struct BoneShiftPreview: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// 1 leaves the bitmap unchanged.
    var scale: CGFloat = 1
    /// Extra rotation around the joint, in radians. 0 leaves the bitmap unchanged.
    var rotation: CGFloat = 0

    var isIdentity: Bool { dx == 0 && dy == 0 && scale == 1 && rotation == 0 }

    mutating func reset() {
        self = BoneShiftPreview()
    }

    /// Factor is the increment since the last pinch event.
    mutating func pinch(_ factor: CGFloat) {
        if factor <= 0 {
            fatalError("BoneShiftPreview pinch factor \(factor)")
        }
        scale = min(max(scale * factor, 0.25), 4)
    }

    /// Radians since the last rotate event. Positive matches `UIRotationGestureRecognizer` (counterclockwise).
    mutating func twist(_ radians: CGFloat) {
        rotation += radians
    }

    /// Project a scene-space drag onto the bone and its perpendicular, in item pixels.
    mutating func addDrag(move: CGPoint, edgeFrom: CGPoint, edgeTo: CGPoint, unitScale: CGFloat) {
        if unitScale <= 0 {
            fatalError("BoneShiftPreview unit scale \(unitScale)")
        }
        let edgeVec = CGPoint(x: edgeTo.x - edgeFrom.x, y: edgeTo.y - edgeFrom.y)
        let edgeLen2 = edgeVec.x * edgeVec.x + edgeVec.y * edgeVec.y
        if edgeLen2 == 0 {
            return
        }
        let ortho = CGPoint(x: edgeVec.y, y: -edgeVec.x)
        let onX = Self.project(move, onto: edgeVec)
        let onY = Self.project(move, onto: ortho)
        var stepX = hypot(onX.x, onX.y) * Self.signum(onX.x)
        var stepY = hypot(onY.x, onY.y) * Self.signum(onY.y)
        if edgeVec.x < 0 {
            stepX *= -1
            stepY *= -1
        }
        dx += stepX / unitScale
        dy += stepY / unitScale
    }

    func live(
        assetStart: Int,
        assetEnd: Int,
        edgeFrom: Int,
        edgeTo: Int,
        active: Bool
    ) -> (dx: CGFloat, dy: CGFloat, scale: CGFloat, rotation: CGFloat) {
        guard active || !isIdentity else {
            return (0, 0, 1, 0)
        }
        let same = (assetStart == edgeFrom && assetEnd == edgeTo)
            || (assetStart == edgeTo && assetEnd == edgeFrom)
        return same ? (dx, dy, scale, rotation) : (0, 0, 1, 0)
    }

    private static func project(_ vector: CGPoint, onto axis: CGPoint) -> CGPoint {
        let mag2 = axis.x * axis.x + axis.y * axis.y
        if mag2 == 0 {
            return .zero
        }
        let k = (vector.x * axis.x + vector.y * axis.y) / mag2
        return CGPoint(x: axis.x * k, y: axis.y * k)
    }

    private static func signum(_ value: CGFloat) -> CGFloat {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }
}
