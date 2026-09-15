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
        if speed < 0 || speed > speedMax {
            fatalError("FBFAnimation speed \(speed) out of 0...\(speedMax)")
        }
        return maxPeriod - speed * 5
    }

    static func speed(period: Int) -> Int {
        if period < minPeriod || period > maxPeriod {
            fatalError("FBFAnimation period \(period) out of \(minPeriod)...\(maxPeriod)")
        }
        return speedMax - (period - minPeriod) / 5
    }

    var hasNoRange: Bool {
        startFrameId == Self.noRange || endFrameId == Self.noRange
    }

    func inRange(scene: StickmanScene, index: Int) -> Bool {
        if hasNoRange { return true }
        let span = toIndices(scene: scene)
        return index >= span.start && index <= span.end
    }

    mutating func setIdsFromIndices(scene: StickmanScene, start: Int, end: Int) {
        if start < 0 || end >= scene.frames.count || start > end {
            fatalError("FBFAnimation '\(unitname)' range \(start)...\(end) out of \(scene.frames.count)")
        }
        startFrameId = scene.frames[start].id
        endFrameId = scene.frames[end].id
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
