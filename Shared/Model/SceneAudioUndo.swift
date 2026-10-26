import Combine
import Foundation

/// Screen-local undo for clip placements only. Android `AudioPointsUndoManager`:
/// palette add/remove is not tracked.
final class SceneAudioUndo: ObservableObject {
    static let cap = 12

    @Published private(set) var stack: [[SceneAudioClip]] = []

    var canUndo: Bool { !stack.isEmpty }

    func commit(_ audio: SceneAudio) {
        if !stack.isEmpty, stack.last == audio.clips {
            return
        }
        stack.append(audio.clips)
        if stack.count > Self.cap {
            stack.removeFirst(stack.count - Self.cap)
        }
    }

    func undo(audio: inout SceneAudio) -> Bool {
        guard let previous = stack.popLast() else {
            return false
        }
        audio.replaceClips(previous)
        return true
    }

    func clear() {
        stack.removeAll()
    }
}
