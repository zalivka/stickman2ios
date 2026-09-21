import Combine
import Foundation

/// Android `SceneUndoManager` — selection snapshots plus lean insert/delete. Cap 12.
final class SceneUndo: ObservableObject {
    static let cap = 12

    enum Entry {
        case selection(frames: [StickmanFrame], tweens: UnitTweenStorage, cameraTweens: CameraTweenStorage)
        case inserted(
            ids: [Int],
            currentIndex: Int,
            animations: [String: FBFAnimation],
            tweens: UnitTweenStorage,
            cameraTweens: CameraTweenStorage
        )
        case deleted(
            frames: [StickmanFrame],
            at: Int,
            currentIndex: Int,
            animations: [String: FBFAnimation],
            tweens: UnitTweenStorage,
            cameraTweens: CameraTweenStorage
        )
        case timeline(
            frames: [StickmanFrame],
            currentIndex: Int,
            animations: [String: FBFAnimation],
            speed: SpeedModifier,
            tweens: UnitTweenStorage,
            cameraTweens: CameraTweenStorage
        )
    }

    @Published private(set) var stack: [Entry] = []
    private var rangeBaseline = false

    var canUndo: Bool { !stack.isEmpty }

    func commitSelection(from scene: StickmanScene, indices: [Int]) {
        if rangeBaseline {
            return
        }
        push(.selection(
            frames: Self.cloneFrames(scene, indices: indices),
            tweens: scene.unitTweens,
            cameraTweens: scene.cameraTweens
        ))
    }

    func commitEnteringRange(from scene: StickmanScene, indices: [Int]) {
        if indices.count < 2 {
            rangeBaseline = false
            return
        }
        if rangeBaseline, case .selection = stack.last {
            stack.removeLast()
        }
        push(.selection(
            frames: Self.cloneFrames(scene, indices: indices),
            tweens: scene.unitTweens,
            cameraTweens: scene.cameraTweens
        ))
        rangeBaseline = true
    }

    func clearRangeBaseline() {
        rangeBaseline = false
    }

    func commitFramesInserted(
        ids: [Int],
        currentIndex: Int,
        animations: [String: FBFAnimation],
        tweens: UnitTweenStorage,
        cameraTweens: CameraTweenStorage
    ) {
        if ids.isEmpty {
            fatalError("SceneUndo commitFramesInserted empty")
        }
        push(.inserted(
            ids: ids,
            currentIndex: currentIndex,
            animations: animations,
            tweens: tweens,
            cameraTweens: cameraTweens
        ))
    }

    func commitFramesDeleted(
        frames: [StickmanFrame],
        at: Int,
        currentIndex: Int,
        animations: [String: FBFAnimation],
        tweens: UnitTweenStorage,
        cameraTweens: CameraTweenStorage
    ) {
        if frames.isEmpty {
            fatalError("SceneUndo commitFramesDeleted empty")
        }
        push(.deleted(
            frames: frames,
            at: at,
            currentIndex: currentIndex,
            animations: animations,
            tweens: tweens,
            cameraTweens: cameraTweens
        ))
    }

    func commitTimeline(from scene: StickmanScene) {
        push(.timeline(
            frames: scene.frames.map { $0.clone() },
            currentIndex: scene.currentIndex,
            animations: scene.unitAnimations,
            speed: scene.speedModifier,
            tweens: scene.unitTweens,
            cameraTweens: scene.cameraTweens
        ))
    }

    func restore(into scene: inout StickmanScene) {
        guard let entry = stack.popLast() else {
            fatalError("SceneUndo restore empty")
        }
        switch entry {
        case .selection(let frames, let tweens, let cameraTweens):
            rangeBaseline = false
            for src in frames {
                guard let index = scene.frames.firstIndex(where: { $0.id == src.id }) else {
                    fatalError("SceneUndo missing frame id \(src.id)")
                }
                scene.frames[index] = src.clone()
            }
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
        case .inserted(let ids, let currentIndex, let animations, let tweens, let cameraTweens):
            for id in ids {
                if !scene.frames.contains(where: { $0.id == id }) {
                    fatalError("SceneUndo inserted id \(id) missing")
                }
            }
            scene.frames.removeAll { ids.contains($0.id) }
            if scene.frames.isEmpty {
                fatalError("SceneUndo undo insert left no frames")
            }
            scene.unitAnimations = animations
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            scene.currentIndex = min(max(currentIndex, 0), scene.frames.count - 1)
            scene.speedModifier.adjustTo(frameCount: scene.frames.count)
        case .deleted(let frames, let at, let currentIndex, let animations, let tweens, let cameraTweens):
            if at < 0 || at > scene.frames.count {
                fatalError("SceneUndo delete restore at \(at) out of \(scene.frames.count)")
            }
            var cursor = at
            for frame in frames {
                if scene.frames.contains(where: { $0.id == frame.id }) {
                    fatalError("SceneUndo delete restore id \(frame.id) already present")
                }
                scene.frames.insert(frame.clone(), at: cursor)
                cursor += 1
            }
            scene.unitAnimations = animations
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            if currentIndex < 0 || currentIndex >= scene.frames.count {
                fatalError("SceneUndo delete restore currentIndex \(currentIndex) out of \(scene.frames.count)")
            }
            scene.currentIndex = currentIndex
            scene.speedModifier.adjustTo(frameCount: scene.frames.count)
        case .timeline(let frames, let currentIndex, let animations, let speed, let tweens, let cameraTweens):
            if frames.isEmpty {
                fatalError("SceneUndo timeline restore empty")
            }
            scene.frames = frames.map { $0.clone() }
            scene.unitAnimations = animations
            scene.speedModifier = speed
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            if currentIndex < 0 || currentIndex >= scene.frames.count {
                fatalError("SceneUndo timeline restore currentIndex \(currentIndex) out of \(scene.frames.count)")
            }
            scene.currentIndex = currentIndex
        }
    }

    private func push(_ entry: Entry) {
        stack.append(entry)
        if stack.count > Self.cap {
            stack.removeFirst()
        }
    }

    private static func cloneFrames(_ scene: StickmanScene, indices: [Int]) -> [StickmanFrame] {
        if indices.isEmpty {
            fatalError("SceneUndo selection empty")
        }
        return indices.map { index in
            if index < 0 || index >= scene.frames.count {
                fatalError("SceneUndo selection \(index) out of \(scene.frames.count)")
            }
            return scene.frames[index].clone()
        }
    }
}
