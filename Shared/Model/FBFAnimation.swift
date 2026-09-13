import Foundation

nonisolated struct FBFAnimation: Codable, Sendable {
    static let noRange = -1

    var unitname: String
    var loop: Bool
    var period: Int
    var startFrameId: Int
    var endFrameId: Int

    var hasNoRange: Bool {
        startFrameId == Self.noRange || endFrameId == Self.noRange
    }

    func toIndices(scene: StickmanScene) -> (start: Int, end: Int) {
        if period < 1 {
            fatalError("FBFAnimation '\(unitname)' period is \(period)")
        }
        if scene.frames.isEmpty {
            fatalError("FBFAnimation '\(unitname)' scene has no frames")
        }
        if hasNoRange {
            return (0, scene.frames.count - 1)
        }
        return (indexOf(startFrameId, scene: scene, label: "start"), indexOf(endFrameId, scene: scene, label: "end"))
    }

    private func indexOf(_ frameId: Int, scene: StickmanScene, label: String) -> Int {
        guard let index = scene.frames.firstIndex(where: { $0.id == frameId }) else {
            fatalError("FBFAnimation '\(unitname)' \(label) frame id \(frameId) is not in the scene")
        }
        return index
    }
}
