import Foundation

/// Shared mutable editor session so canvas touch callbacks always see live hold/selection state.
final class SkeletonEditSession {
    var boneCreateHoldMode = false
    var selectedPointId: Int?
    /// Bumped to force SwiftUI refresh when selection or hold mode changes outside @State.
    var revision = 0

    func setHoldMode(_ on: Bool) {
        boneCreateHoldMode = on
        revision += 1
    }

    func select(_ id: Int?) {
        selectedPointId = id
        revision += 1
    }
}
