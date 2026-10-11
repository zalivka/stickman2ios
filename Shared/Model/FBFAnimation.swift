import Foundation

nonisolated struct FBFAnimation: Codable, Sendable {
    static let noRange = -1
    static let minPeriod = 3
    static let maxPeriod = 53
    static let speedMax = 10

    var unitname: String
    var loop: Bool
    var period: Int
    var startFrameId: Int
    var endFrameId: Int

    static func period(speed: Int) -> Int {
        let clamped = min(max(speed, 0), speedMax)
        if clamped != speed {
            assertionFailure("FBFAnimation speed \(speed) out of 0...\(speedMax) — clamped")
        }
        return maxPeriod - clamped * 5
    }

    static func speed(period: Int) -> Int {
        let clamped = min(max(period, minPeriod), maxPeriod)
        if clamped != period {
            assertionFailure("FBFAnimation period \(period) out of \(minPeriod)...\(maxPeriod) — clamped")
        }
        return speedMax - (clamped - minPeriod) / 5
    }

    var hasNoRange: Bool {
        startFrameId == Self.noRange || endFrameId == Self.noRange
    }

    func inRange(scene: StickmanScene, index: Int) -> Bool {
        if hasNoRange { return true }
        let span = toIndices(scene: scene)
        return index >= span.start && index <= span.end
    }

    func toIndices(scene: StickmanScene) -> (start: Int, end: Int) {
        guard !scene.frames.isEmpty else {
            assertionFailure("FBFAnimation '\(unitname)' scene has no frames")
            return (0, 0)
        }
        let last = scene.frames.count - 1
        if hasNoRange {
            return (0, last)
        }
        let start = indexOf(startFrameId, scene: scene, label: "start") ?? 0
        let end = indexOf(endFrameId, scene: scene, label: "end") ?? last
        return (min(start, end), max(start, end))
    }

    private func indexOf(_ frameId: Int, scene: StickmanScene, label: String) -> Int? {
        guard let index = scene.frames.firstIndex(where: { $0.id == frameId }) else {
            print("FBFAnimation '\(unitname)' \(label) frame id \(frameId) is not in the scene")
            return nil
        }
        return index
    }
}
