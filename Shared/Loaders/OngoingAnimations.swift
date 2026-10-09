import Foundation

nonisolated enum OngoingAnimations {
    private struct Log {
        var assetsState = 0
        var backward = false
        var counter = 0
    }

    static func apply(source: StickmanScene, frames: inout [StickmanFrame], stateLists: [String: [Int]]) {
        if source.unitAnimations.isEmpty {
            return
        }
        var running: [String: Log] = [:]
        // A unit whose animation cannot advance is dropped for the whole clip: one bad FBF
        // unit must not stop the rest of the scene from playing.
        var dropped: Set<String> = []
        for index in frames.indices {
            apply(source: source, frame: &frames[index], stateLists: stateLists, running: &running, dropped: &dropped)
        }
    }

    private static func apply(
        source: StickmanScene,
        frame: inout StickmanFrame,
        stateLists: [String: [Int]],
        running: inout [String: Log],
        dropped: inout Set<String>
    ) {
        for (unitName, animation) in source.unitAnimations {
            if dropped.contains(unitName) {
                continue
            }
            guard let unitIndex = frame.units.firstIndex(where: { $0.name == unitName }) else {
                continue
            }
            let range = animation.toIndices(scene: source)
            var start = false
            if animation.hasNoRange {
                start = true
            } else if range.start == frame.originFrameIndex {
                start = true
            } else if running[unitName] != nil {
                start = true
            }
            if start {
                do {
                    guard let states = stateLists[unitName] else {
                        throw SceneLoadError(message: "OngoingAnimations missing states for '\(unitName)'")
                    }
                    try tick(unit: &frame.units[unitIndex], animation: animation, states: states, running: &running)
                } catch {
                    print("OngoingAnimations dropping '\(unitName)': \(error)")
                    dropped.insert(unitName)
                    running.removeValue(forKey: unitName)
                }
            }
            if frame.originFrameIndex == range.end {
                running.removeValue(forKey: unitName)
            }
        }
    }

    private static func tick(
        unit: inout StickmanUnit,
        animation: FBFAnimation,
        states: [Int],
        running: inout [String: Log]
    ) throws {
        var log = running[unit.name] ?? Log()
        if (log.counter + 1) % animation.period == 0 {
            let next = try unit.nextState(
                states: states,
                current: log.assetsState,
                backward: log.backward,
                loop: animation.loop
            )
            log.assetsState = next.state
            log.backward = next.backward
            log.counter = 0
        } else {
            unit.assetsState = log.assetsState
            log.counter += 1
        }
        running[unit.name] = log
    }
}
