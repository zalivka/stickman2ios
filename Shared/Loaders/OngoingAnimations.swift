import Foundation

nonisolated enum OngoingAnimations {
    fileprivate struct Log {
        var assetsState = 0
        var backward = false
        var counter = 0
    }

    struct State {
        fileprivate var running: [String: Log] = [:]
        fileprivate var dropped: Set<String> = []
    }

    static func apply(source: StickmanScene, frames: inout [StickmanFrame], stateLists: [String: [Int]]) {
        if source.unitAnimations.isEmpty {
            return
        }
        var state = State()
        for index in frames.indices {
            apply(source: source, frame: &frames[index], stateLists: stateLists, state: &state)
        }
    }

    static func apply(
        source: StickmanScene,
        frame: inout StickmanFrame,
        stateLists: [String: [Int]],
        state: inout State
    ) {
        if source.unitAnimations.isEmpty {
            return
        }
        // A unit whose animation cannot advance is dropped for the whole clip: one bad FBF
        // unit must not stop the rest of the scene from playing.
        for (unitName, animation) in source.unitAnimations {
            if state.dropped.contains(unitName) {
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
            } else if state.running[unitName] != nil {
                start = true
            }
            if start {
                do {
                    guard let states = stateLists[unitName] else {
                        throw SceneLoadError(message: "OngoingAnimations missing states for '\(unitName)'")
                    }
                    try tick(unit: &frame.units[unitIndex], animation: animation, states: states, running: &state.running)
                } catch {
                    print("OngoingAnimations dropping '\(unitName)': \(error)")
                    state.dropped.insert(unitName)
                    state.running.removeValue(forKey: unitName)
                }
            }
            if frame.originFrameIndex == range.end {
                state.running.removeValue(forKey: unitName)
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
