import Foundation

/// Android `SkeletonUndoManager` + old `UndoEditManager.MAX_SIZE = 10`, plus one redo slot.
final class SkeletonUndo {
    static let cap = 10

    struct Entry {
        var unit: StickmanUnit
        var selectedPointId: Int?
        var assets: UnitAssets.Snapshot?
    }

    private var stack: [Entry] = []
    private var redoSlot: Entry?

    var canUndo: Bool { !stack.isEmpty }
    var canRedo: Bool { redoSlot != nil }

    func push(unit: StickmanUnit, selectedPointId: Int?, assets: UnitAssets.Snapshot?) {
        stack.append(Entry(unit: unit, selectedPointId: selectedPointId, assets: assets))
        if stack.count > Self.cap {
            stack.removeFirst()
        }
        redoSlot = nil
    }

    func peek() -> Entry? {
        stack.last
    }

    func pop() -> Entry? {
        stack.popLast()
    }

    func setRedo(_ entry: Entry) {
        redoSlot = entry
    }

    func takeRedo() -> Entry? {
        let entry = redoSlot
        redoSlot = nil
        return entry
    }
}
