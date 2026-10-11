import Combine
import Foundation

/// Android `CopyPasteBuffer` — independent unit and frame slots.
final class CopyPasteBuffer: ObservableObject {
    @Published private(set) var units: [StickmanUnit] = []
    @Published private(set) var frames: [StickmanFrame] = []
    @Published private(set) var animations: [String: FBFAnimation] = [:]

    var hasUnits: Bool { !units.isEmpty }
    var hasFrames: Bool { !frames.isEmpty }
    var framesInBuffer: Int { frames.count }

    func copyUnits(_ structure: [StickmanUnit]) {
        if structure.isEmpty {
            assertionFailure("CopyPasteBuffer copyUnits empty")
            return
        }
        units = structure
    }

    func copyFrames(from scene: StickmanScene, indices: [Int]) throws {
        if indices.isEmpty {
            assertionFailure("CopyPasteBuffer copyFrames empty")
            return
        }
        var copied: [StickmanFrame] = []
        copied.reserveCapacity(indices.count)
        for index in indices {
            if index < 0 || index >= scene.frames.count {
                assertionFailure("CopyPasteBuffer copyFrames \(index) out of \(scene.frames.count)")
                continue
            }
            copied.append(try scene.frames[index].clone())
        }
        guard !copied.isEmpty else {
            return
        }
        frames = copied
        animations = Self.animations(from: scene, copied: copied)
    }

    @discardableResult
    func pasteFrames(into scene: inout StickmanScene) throws -> [Int] {
        if frames.isEmpty {
            assertionFailure("CopyPasteBuffer pasteFrames empty")
            return []
        }
        return try scene.pasteFrames(frames, animations: animations)
    }

    func pasteUnits(into scene: inout StickmanScene, at indices: [Int]) throws {
        if units.isEmpty {
            assertionFailure("CopyPasteBuffer pasteUnits empty")
            return
        }
        if indices.isEmpty {
            assertionFailure("CopyPasteBuffer pasteUnits no frames")
            return
        }
        for index in indices {
            if index < 0 || index >= scene.frames.count {
                assertionFailure("CopyPasteBuffer pasteUnits \(index) out of \(scene.frames.count)")
                continue
            }
            try scene.frames[index].pasteStructure(units)
        }
    }

    private static func animations(
        from scene: StickmanScene,
        copied: [StickmanFrame]
    ) -> [String: FBFAnimation] {
        let copiedIds = Set(copied.map(\.id))
        var result: [String: FBFAnimation] = [:]
        for (name, animation) in scene.unitAnimations {
            if !copied.contains(where: { $0.units.contains(where: { $0.name == name }) }) {
                continue
            }
            if animation.hasNoRange {
                if copied.count != scene.frames.count {
                    continue
                }
            } else if !copiedIds.contains(animation.startFrameId) || !copiedIds.contains(animation.endFrameId) {
                continue
            }
            result[name] = animation
        }
        return result
    }
}
