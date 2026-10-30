import CoreGraphics

/// Android `BonePictureStretch`: the horizontal factor a bone picture must be drawn at so it
/// still covers its bone after the bone is stretched away from its model rest length.
enum BoneStretch {
    /// Android `MainEditor.hasSelectedUnitWithStretchableBone` / `ItemPreview`:
    /// a kinematic start drives the bone through IK, so its own stretch flag is ignored.
    static func hasStretchablePoint(_ unit: StickmanUnit) -> Bool {
        unit.points.contains { $0.stretchable && !$0.kinematicStart }
    }

    /// Nil when the edge must be drawn as authored: the tip is not stretchable, the tip is a
    /// kinematic start, `model.xml` rest length is unknown, the unit has no scale, or the bone
    /// sits exactly at rest length.
    static func ratio(unit: StickmanUnit, edge: StickmanEdge, assets: UnitAssets) -> CGFloat? {
        guard let tip = unit.point(optionalId: edge.to),
              let from = unit.point(optionalId: edge.from)
        else {
            return nil
        }
        if tip.isBase || !tip.stretchable || tip.kinematicStart {
            return nil
        }
        if unit.scale <= 0 {
            assertionFailure("BoneStretch '\(unit.name)' scale is \(unit.scale)")
            return nil
        }
        let rest = assets.restLength(unitName: unit.name, endId: edge.to)
        if rest <= 0 {
            return nil
        }
        let restWorld = rest * unit.scale
        let length = hypot(tip.x - from.x, tip.y - from.y)
        if length <= 0 || restWorld <= 0 {
            return nil
        }
        let ratio = length / restWorld
        if !ratio.isFinite || ratio <= 0 {
            return nil
        }
        if abs(ratio - 1) < 0.0005 {
            return nil
        }
        return ratio
    }
}
