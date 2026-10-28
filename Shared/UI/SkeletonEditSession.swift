import CoreGraphics
import Foundation

enum BoneSplitShape: CaseIterable, Equatable {
    case circle
    case square
    case line
}

struct BoneSplitDraft: Equatable {
    /// Minimum distance from either bone endpoint in unscaled item-pixel units.
    static let minEndMargin: CGFloat = 10
    static let minRadius: CGFloat = 4
    static let maxRadiusCap: CGFloat = 125

    var edgeFrom: Int
    var edgeTo: Int
    /// Normalized position along `edgeFrom → edgeTo` in `(0, 1)`.
    var t: CGFloat
    /// Joint circle/square half-extent in unscaled item-pixel units.
    var radius: CGFloat
    var shape: BoneSplitShape = .circle

    static func clampT(_ raw: CGFloat, boneLength: CGFloat) -> CGFloat {
        guard boneLength > minEndMargin * 2 else { return 0.5 }
        let marginT = minEndMargin / boneLength
        return min(max(raw, marginT), 1 - marginT)
    }

    static func clampRadius(_ raw: CGFloat, boneLength: CGFloat) -> CGFloat {
        let maxR = max(minRadius, min(boneLength * 0.9, maxRadiusCap))
        return min(max(raw, minRadius), maxR)
    }
}

/// Shared mutable editor session so canvas touch callbacks always see live hold/selection state.
final class SkeletonEditSession {
    let undo = SkeletonUndo()
    var boneCreateHoldMode = false
    var shiftHoldMode = false
    var boneSplit: BoneSplitDraft?
    var selectedPointId: Int?
    /// When true, canvas draws green vacant-point circles (Android `toggleVacantPoints`).
    var exposeVacantPoints = false
    /// Bumped to force SwiftUI refresh when selection or hold mode changes outside @State.
    var revision = 0
    /// Canvas zoom and pan as last drawn, so BonePaper can open with the bone where it was on screen.
    var layout: SkeletonLayout?
    /// Canvas top-left in window coordinates.
    var canvasOrigin: CGPoint = .zero

    func setHoldMode(_ on: Bool) {
        boneCreateHoldMode = on
        revision += 1
    }

    func setShiftHold(_ on: Bool) {
        shiftHoldMode = on
        revision += 1
    }

    func setBoneSplit(_ draft: BoneSplitDraft?) {
        boneSplit = draft
        revision += 1
    }

    func select(_ id: Int?) {
        selectedPointId = id
        revision += 1
    }

    func setExposeVacantPoints(_ on: Bool) {
        exposeVacantPoints = on
        revision += 1
    }
}
