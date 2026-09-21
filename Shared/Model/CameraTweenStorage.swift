import Foundation

struct CameraAutoTweenRange: Equatable {
    var fromFrame: Int
    var toFrame: Int
    var easingType: TweenEasing
    var easingStrength: Float
    var shakeFrequency: Float
    var segmentNumber: Int

    init(
        fromFrame: Int,
        toFrame: Int,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        segmentNumber: Int
    ) {
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.easingType = easingType
        self.easingStrength = min(max(easingStrength, 0), 1)
        self.shakeFrequency = UnitTweenStorage.clampFrequency(easingType, shakeFrequency)
        self.segmentNumber = segmentNumber
    }

    func contains(_ frameIndex: Int) -> Bool {
        frameIndex >= fromFrame && frameIndex <= toFrame
    }

    func containsInterior(_ frameIndex: Int) -> Bool {
        frameIndex > fromFrame && frameIndex < toFrame
    }

    func containsSpan(from: Int, to: Int) -> Bool {
        from >= fromFrame && to <= toFrame
    }

    func intersects(from: Int, to: Int) -> Bool {
        fromFrame < to && from < toFrame
    }
}

struct CameraTweenStorage: Equatable {
    static let ownerType = "camera"
    static let archiveName = "camera_tweens_v1.txt"

    var ranges: [CameraAutoTweenRange] = []
    var nextSegmentNumber = 1

    var isEmpty: Bool { ranges.isEmpty }

    mutating func register(
        fromFrame: Int,
        toFrame: Int,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        frameCount: Int
    ) {
        let from = min(fromFrame, toFrame)
        let to = max(fromFrame, toFrame)
        if from < 0 || to >= frameCount {
            fatalError("Camera tween range \(from)..\(to) out of \(frameCount)")
        }
        if from >= to {
            fatalError("Camera tween range must cover at least 2 frames")
        }
        ranges.removeAll { $0.intersects(from: from, to: to) }
        let segment = nextSegmentNumber
        nextSegmentNumber += 1
        ranges.append(
            CameraAutoTweenRange(
                fromFrame: from,
                toFrame: to,
                easingType: easingType,
                easingStrength: easingStrength,
                shakeFrequency: shakeFrequency,
                segmentNumber: segment
            )
        )
        ensureValid(frameCount: frameCount)
    }

    func findContaining(frameIndex: Int) -> CameraAutoTweenRange? {
        ranges.first { $0.contains(frameIndex) }
    }

    func findExact(from: Int, to: Int) -> CameraAutoTweenRange? {
        ranges.first { $0.fromFrame == from && $0.toFrame == to }
    }

    func findForSpan(from: Int, to: Int) -> CameraAutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return ranges.first { $0.containsSpan(from: start, to: end) }
    }

    func findIntersecting(from: Int, to: Int) -> CameraAutoTweenRange? {
        ranges.first { $0.intersects(from: from, to: to) }
    }

    func isPoseLocked(frameIndex: Int) -> Bool {
        ranges.contains { $0.containsInterior(frameIndex) }
    }

    func lockMessage(frameIndex: Int) -> String {
        if let range = findContaining(frameIndex: frameIndex) {
            return "AUTO camera tween lock: frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO camera tween lock: frame \(frameIndex)"
    }

    mutating func removeContaining(frameIndex: Int) -> CameraAutoTweenRange? {
        guard let range = findContaining(frameIndex: frameIndex) else {
            return nil
        }
        ranges.removeAll { $0 == range }
        return range
    }

    mutating func removeExact(from: Int, to: Int) -> CameraAutoTweenRange? {
        guard let index = ranges.firstIndex(where: { $0.fromFrame == from && $0.toFrame == to }) else {
            return nil
        }
        return ranges.remove(at: index)
    }

    mutating func clear() {
        ranges.removeAll()
        nextSegmentNumber = 1
    }

    func wouldInsertSplit(after index: Int) -> Bool {
        if index < 0 {
            return false
        }
        return ranges.contains { $0.fromFrame <= index && index < $0.toFrame }
    }

    mutating func reconcileInsert(at index: Int, oldFrameCount: Int) -> [CameraAutoTweenRange] {
        if oldFrameCount < 1 {
            fatalError("CameraTweenStorage insert oldFrameCount \(oldFrameCount)")
        }
        if index < 0 || index > oldFrameCount {
            fatalError("CameraTweenStorage insert \(index) out of \(oldFrameCount)")
        }
        var retween: [CameraAutoTweenRange] = []
        var next: [CameraAutoTweenRange] = []
        for span in ranges {
            let remapped: CameraAutoTweenRange
            if index <= span.fromFrame {
                remapped = remap(span, from: span.fromFrame + 1, to: span.toFrame + 1)
            } else if index <= span.toFrame {
                remapped = remap(span, from: span.fromFrame, to: span.toFrame + 1)
                retween.append(remapped)
            } else {
                remapped = span
            }
            next.append(remapped)
        }
        ranges = next
        ensureValid(frameCount: oldFrameCount + 1)
        return retween
    }

    mutating func reconcileDelete(deleted: [Int], oldFrameCount: Int) -> [CameraAutoTweenRange] {
        if oldFrameCount < 1 {
            fatalError("CameraTweenStorage delete oldFrameCount \(oldFrameCount)")
        }
        let deletedSet = Set(deleted)
        var retween: [CameraAutoTweenRange] = []
        var next: [CameraAutoTweenRange] = []
        for span in ranges {
            if (span.fromFrame...span.toFrame).allSatisfy({ deletedSet.contains($0) }) {
                continue
            }
            if deletedSet.contains(span.fromFrame) || deletedSet.contains(span.toFrame) {
                continue
            }
            let from = span.fromFrame - deletedSet.filter { $0 < span.fromFrame }.count
            let to = span.toFrame - deletedSet.filter { $0 < span.toFrame }.count
            if from >= to {
                continue
            }
            let remapped = remap(span, from: from, to: to)
            if (span.fromFrame + 1..<span.toFrame).contains(where: { deletedSet.contains($0) }) {
                retween.append(remapped)
            }
            next.append(remapped)
        }
        ranges = next
        ensureValid(frameCount: oldFrameCount - deletedSet.count)
        return retween
    }

    func encodeArchive(scene: StickmanScene) -> Data {
        let spans = ranges.compactMap { span -> PersistedSpan? in
            if span.fromFrame < 0 || span.toFrame >= scene.frames.count {
                return nil
            }
            return PersistedSpan(
                ownerType: Self.ownerType,
                segmentNumber: span.segmentNumber,
                fromFrameId: scene.frames[span.fromFrame].id,
                toFrameId: scene.frames[span.toFrame].id,
                easingType: span.easingType,
                easingStrength: span.easingStrength,
                shakeFrequency: span.shakeFrequency,
                params: ["shakeFrequency": span.shakeFrequency]
            )
        }
        do {
            return try JSONEncoder().encode(Archive(spans: spans))
        } catch {
            fatalError("CameraTweenStorage encode: \(error)")
        }
    }

    mutating func importArchive(_ data: Data, scene: StickmanScene) {
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            fatalError("CameraTweenStorage camera_tweens_v1.txt JSON: \(error)")
        }
        clear()
        var idToIndex: [Int: Int] = [:]
        for (index, frame) in scene.frames.enumerated() {
            idToIndex[frame.id] = index
        }
        for persisted in archive.spans {
            if persisted.ownerType != Self.ownerType {
                continue
            }
            guard let fromIndex = idToIndex[persisted.fromFrameId],
                  let toIndex = idToIndex[persisted.toFrameId]
            else {
                continue
            }
            let from = min(fromIndex, toIndex)
            let to = max(fromIndex, toIndex)
            if from >= to {
                continue
            }
            if findIntersecting(from: from, to: to) != nil {
                continue
            }
            let frequency = persisted.shakeFrequency
                ?? persisted.params?["shakeFrequency"]
                ?? UnitTweenStorage.defaultShakeFrequency
            let segment = persisted.segmentNumber > 0 ? persisted.segmentNumber : nextSegmentNumber
            ranges.append(
                CameraAutoTweenRange(
                    fromFrame: from,
                    toFrame: to,
                    easingType: persisted.easingType,
                    easingStrength: persisted.easingStrength,
                    shakeFrequency: frequency,
                    segmentNumber: segment
                )
            )
            nextSegmentNumber = max(nextSegmentNumber, segment + 1)
        }
        ensureValid(frameCount: scene.frames.count)
    }

    mutating func ensureValid(frameCount: Int) {
        sort()
        for i in 1..<ranges.count {
            let prev = ranges[i - 1]
            let current = ranges[i]
            if prev.intersects(from: current.fromFrame, to: current.toFrame) {
                fatalError(
                    "Overlapping camera spans: [\(prev.fromFrame)..\(prev.toFrame)] and [\(current.fromFrame)..\(current.toFrame)]"
                )
            }
        }
        for span in ranges {
            if span.fromFrame < 0 || span.toFrame >= frameCount || span.fromFrame >= span.toFrame {
                fatalError("camera span [\(span.fromFrame)..\(span.toFrame)] invalid for \(frameCount) frames")
            }
        }
        let maxSegment = ranges.map(\.segmentNumber).max() ?? 0
        nextSegmentNumber = max(nextSegmentNumber, maxSegment + 1)
    }

    private func remap(_ span: CameraAutoTweenRange, from: Int, to: Int) -> CameraAutoTweenRange {
        CameraAutoTweenRange(
            fromFrame: from,
            toFrame: to,
            easingType: span.easingType,
            easingStrength: span.easingStrength,
            shakeFrequency: span.shakeFrequency,
            segmentNumber: span.segmentNumber
        )
    }

    private mutating func sort() {
        ranges.sort {
            if $0.fromFrame != $1.fromFrame {
                return $0.fromFrame < $1.fromFrame
            }
            return $0.toFrame < $1.toFrame
        }
    }

    private struct Archive: Codable {
        var spans: [PersistedSpan]
    }

    private struct PersistedSpan: Codable {
        var ownerType: String
        var segmentNumber: Int
        var fromFrameId: Int
        var toFrameId: Int
        var easingType: TweenEasing
        var easingStrength: Float
        var shakeFrequency: Float?
        var params: [String: Float]?
    }
}
