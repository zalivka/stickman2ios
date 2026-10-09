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
        case sceneProps(
            width: CGFloat,
            height: CGFloat,
            interframes: Int,
            noInterpolation: Bool,
            noInterpolationFrames: Int
        )
    }

    @Published private(set) var stack: [Entry] = []
    private var rangeBaseline = false

    var canUndo: Bool { !stack.isEmpty }

    func commitSelection(from scene: StickmanScene, indices: [Int]) throws {
        if rangeBaseline {
            return
        }
        push(.selection(
            frames: try Self.cloneFrames(scene, indices: indices),
            tweens: scene.unitTweens,
            cameraTweens: scene.cameraTweens
        ))
    }

    func commitEnteringRange(from scene: StickmanScene, indices: [Int]) throws {
        if indices.count < 2 {
            rangeBaseline = false
            return
        }
        if rangeBaseline, case .selection = stack.last {
            stack.removeLast()
        }
        push(.selection(
            frames: try Self.cloneFrames(scene, indices: indices),
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

    func commitSceneProps(from scene: StickmanScene) {
        push(.sceneProps(
            width: scene.width,
            height: scene.height,
            interframes: scene.interframes,
            noInterpolation: scene.noInterpolation,
            noInterpolationFrames: scene.noInterpolationFrames
        ))
    }

    func commitTimeline(from scene: StickmanScene) throws {
        push(.timeline(
            frames: try scene.frames.map { try $0.clone() },
            currentIndex: scene.currentIndex,
            animations: scene.unitAnimations,
            speed: scene.speedModifier,
            tweens: scene.unitTweens,
            cameraTweens: scene.cameraTweens
        ))
    }

    func restore(into scene: inout StickmanScene) throws {
        guard let entry = stack.popLast() else {
            throw SceneLoadError(message: "SceneUndo restore empty")
        }
        switch entry {
        case .selection(let frames, let tweens, let cameraTweens):
            rangeBaseline = false
            for src in frames {
                guard let index = scene.frames.firstIndex(where: { $0.id == src.id }) else {
                    throw SceneLoadError(message: "SceneUndo missing frame id \(src.id)")
                }
                scene.frames[index] = try src.clone()
            }
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
        case .inserted(let ids, let currentIndex, let animations, let tweens, let cameraTweens):
            for id in ids {
                if !scene.frames.contains(where: { $0.id == id }) {
                    throw SceneLoadError(message: "SceneUndo inserted id \(id) missing")
                }
            }
            scene.frames.removeAll { ids.contains($0.id) }
            if scene.frames.isEmpty {
                throw SceneLoadError(message: "SceneUndo undo insert left no frames")
            }
            scene.unitAnimations = animations
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            scene.currentIndex = min(max(currentIndex, 0), scene.frames.count - 1)
            scene.speedModifier.adjustTo(frameCount: scene.frames.count)
        case .deleted(let frames, let at, let currentIndex, let animations, let tweens, let cameraTweens):
            if at < 0 || at > scene.frames.count {
                throw SceneLoadError(message: "SceneUndo delete restore at \(at) out of \(scene.frames.count)")
            }
            var cursor = at
            for frame in frames {
                if scene.frames.contains(where: { $0.id == frame.id }) {
                    throw SceneLoadError(message: "SceneUndo delete restore id \(frame.id) already present")
                }
                scene.frames.insert(try frame.clone(), at: cursor)
                cursor += 1
            }
            scene.unitAnimations = animations
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            if currentIndex < 0 || currentIndex >= scene.frames.count {
                throw SceneLoadError(message: "SceneUndo delete restore currentIndex \(currentIndex) out of \(scene.frames.count)")
            }
            scene.currentIndex = currentIndex
            scene.speedModifier.adjustTo(frameCount: scene.frames.count)
        case .timeline(let frames, let currentIndex, let animations, let speed, let tweens, let cameraTweens):
            if frames.isEmpty {
                throw SceneLoadError(message: "SceneUndo timeline restore empty")
            }
            scene.frames = frames
            scene.unitAnimations = animations
            scene.speedModifier = speed
            scene.unitTweens = tweens
            scene.cameraTweens = cameraTweens
            if currentIndex < 0 || currentIndex >= scene.frames.count {
                throw SceneLoadError(message: "SceneUndo timeline restore currentIndex \(currentIndex) out of \(scene.frames.count)")
            }
            scene.currentIndex = currentIndex
        case .sceneProps(let width, let height, let interframes, let noInterpolation, let noInterpolationFrames):
            scene.width = width
            scene.height = height
            scene.interframes = interframes
            scene.noInterpolation = noInterpolation
            scene.noInterpolationFrames = noInterpolationFrames
        }
    }

    private func push(_ entry: Entry) {
        stack.append(entry)
        if stack.count > Self.cap {
            stack.removeFirst()
        }
    }

    private static func cloneFrames(_ scene: StickmanScene, indices: [Int]) throws -> [StickmanFrame] {
        if indices.isEmpty {
            fatalError("SceneUndo selection empty")
        }
        return try indices.map { index in
            if index < 0 || index >= scene.frames.count {
                fatalError("SceneUndo selection \(index) out of \(scene.frames.count)")
            }
            return try scene.frames[index].clone()
        }
    }
}
