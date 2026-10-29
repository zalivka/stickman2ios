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
        let onX = Self.project(move, onto: edgeVec)
        let onY = Self.project(move, onto: ortho)
        var stepX = hypot(onX.x, onX.y) * Self.signum(onX.x)
        var stepY = hypot(onY.x, onY.y) * Self.signum(onY.x)
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
    ) -> (dx: CGFloat, dy: CGFloat) {
        guard active || !isIdentity else {
            return (0, 0)
        }
        let same = (assetStart == edgeFrom && assetEnd == edgeTo)
            || (assetStart == edgeTo && assetEnd == edgeFrom)
        return same ? (dx, dy) : (0, 0)
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
