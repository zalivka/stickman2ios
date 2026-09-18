import Combine
import Foundation

/// Android `SceneUndoManager` — selection snapshots plus lean insert/delete. Cap 12.
final class SceneUndo: ObservableObject {
    static let cap = 12

    enum Entry {
        case selection([StickmanFrame])
        case inserted(ids: [Int], currentIndex: Int, animations: [String: FBFAnimation])
        case deleted(frames: [StickmanFrame], at: Int, currentIndex: Int, animations: [String: FBFAnimation])
    }

    @Published private(set) var stack: [Entry] = []
    private var rangeBaseline = false

    var canUndo: Bool { !stack.isEmpty }

    func commitSelection(from scene: StickmanScene, indices: [Int]) {
        if rangeBaseline {
            return
        }
        push(.selection(Self.cloneFrames(scene, indices: indices)))
    }

    func commitEnteringRange(from scene: StickmanScene, indices: [Int]) {
        if indices.count < 2 {
            rangeBaseline = false
            return
        }
        if rangeBaseline, case .selection = stack.last {
            stack.removeLast()
        }
        push(.selection(Self.cloneFrames(scene, indices: indices)))
        rangeBaseline = true
    }

    func clearRangeBaseline() {
        rangeBaseline = false
    }

    func commitFramesInserted(
        ids: [Int],
        currentIndex: Int,
        animations: [String: FBFAnimation]
    ) {
        if ids.isEmpty {
            fatalError("SceneUndo commitFramesInserted empty")
        }
        push(.inserted(ids: ids, currentIndex: currentIndex, animations: animations))
    }

    func commitFramesDeleted(
        frames: [StickmanFrame],
        at: Int,
        currentIndex: Int,
        animations: [String: FBFAnimation]
    ) {
        if frames.isEmpty {
            fatalError("SceneUndo commitFramesDeleted empty")
        }
        push(.deleted(frames: frames, at: at, currentIndex: currentIndex, animations: animations))
    }

    func restore(into scene: inout StickmanScene) {
        guard let entry = stack.popLast() else {
            fatalError("SceneUndo restore empty")
        }
        switch entry {
        case .selection(let frames):
            rangeBaseline = false
            for src in frames {
                guard let index = scene.frames.firstIndex(where: { $0.id == src.id }) else {
                    fatalError("SceneUndo missing frame id \(src.id)")
                }
                scene.frames[index] = src.clone()
            }
        case .inserted(let ids, let currentIndex, let animations):
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
            scene.currentIndex = min(max(currentIndex, 0), scene.frames.count - 1)
        case .deleted(let frames, let at, let currentIndex, let animations):
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
            if currentIndex < 0 || currentIndex >= scene.frames.count {
                fatalError("SceneUndo delete restore currentIndex \(currentIndex) out of \(scene.frames.count)")
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
