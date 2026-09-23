import CoreGraphics
import Foundation

/// Shared mutable editor session so canvas touch callbacks always see live hold/selection state.
final class SkeletonEditSession {
    let undo = SkeletonUndo()
    var boneCreateHoldMode = false
    var shiftHoldMode = false
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

    func select(_ id: Int?) {
        selectedPointId = id
        revision += 1
    }

    func setExposeVacantPoints(_ on: Bool) {
        exposeVacantPoints = on
        revision += 1
    }
}
