import Foundation

struct BackgroundAutoTweenRange: TweenSpanProtocol {
    var fromFrame: Int
    var toFrame: Int
    var bgName: String
    var easingType: TweenEasing
    var easingStrength: Float
    var shakeFrequency: Float
    var segmentNumber: Int

    init(
        fromFrame: Int,
        toFrame: Int,
        bgName: String,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        segmentNumber: Int
    ) {
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.bgName = bgName
        self.easingType = easingType
        self.easingStrength = min(max(easingStrength, 0), 1)
        self.shakeFrequency = UnitTweenStorage.clampFrequency(easingType, shakeFrequency)
        self.segmentNumber = segmentNumber
    }

    func remapped(from: Int, to: Int) -> BackgroundAutoTweenRange {
        BackgroundAutoTweenRange(
            fromFrame: from,
            toFrame: to,
            bgName: bgName,
            easingType: easingType,
            easingStrength: easingStrength,
            shakeFrequency: shakeFrequency,
            segmentNumber: segmentNumber
        )
    }
}

struct BackgroundTweenStorage: Equatable {
    static let ownerType = "background"
    static let archiveName = "background_tweens_v1.txt"

    var ranges: [BackgroundAutoTweenRange] = []
    var nextSegmentNumber = 1

    var isEmpty: Bool { ranges.isEmpty }

    mutating func register(
        fromFrame: Int,
        toFrame: Int,
        bgName: String,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        frameCount: Int
    ) {
        let from = min(fromFrame, toFrame)
        let to = max(fromFrame, toFrame)
        if from < 0 || to >= frameCount {
            assertionFailure("Background tween range \(from)..\(to) out of \(frameCount)")
            return
        }
        if from >= to {
            assertionFailure("Background tween range must cover at least 2 frames")
            return
        }
        ranges.removeAll { $0.intersects(from: from, to: to) }
        let segment = nextSegmentNumber
        nextSegmentNumber += 1
        ranges.append(
            BackgroundAutoTweenRange(
                fromFrame: from,
                toFrame: to,
                bgName: bgName,
                easingType: easingType,
                easingStrength: easingStrength,
                shakeFrequency: shakeFrequency,
                segmentNumber: segment
            )
        )
        ensureValid(frameCount: frameCount)
    }

    func findContaining(frameIndex: Int) -> BackgroundAutoTweenRange? {
        ranges.first { $0.contains(frameIndex) }
    }

    func findExact(from: Int, to: Int) -> BackgroundAutoTweenRange? {
        ranges.first { $0.fromFrame == from && $0.toFrame == to }
    }

    func findForSpan(from: Int, to: Int) -> BackgroundAutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return ranges.first { $0.containsSpan(from: start, to: end) }
    }

    func findIntersecting(from: Int, to: Int) -> BackgroundAutoTweenRange? {
        ranges.first { $0.intersects(from: from, to: to) }
    }

    func isPoseLocked(frameIndex: Int) -> Bool {
        ranges.contains { $0.containsInterior(frameIndex) }
    }

    func lockMessage(frameIndex: Int) -> String {
        if let range = findContaining(frameIndex: frameIndex) {
            return "AUTO background tween lock: frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO background tween lock: frame \(frameIndex)"
    }

    mutating func removeContaining(frameIndex: Int) -> BackgroundAutoTweenRange? {
        guard let range = findContaining(frameIndex: frameIndex) else {
            return nil
        }
        ranges.removeAll { $0 == range }
        return range
    }

    mutating func removeExact(from: Int, to: Int) -> BackgroundAutoTweenRange? {
        guard let index = ranges.firstIndex(where: { $0.fromFrame == from && $0.toFrame == to }) else {
            return nil
        }
        return ranges.remove(at: index)
    }

    mutating func removeSpans(named bgName: String) {
        ranges.removeAll { $0.bgName == bgName }
    }

    mutating func retargetSpans(from oldName: String, to newName: String) {
        for index in ranges.indices where ranges[index].bgName == oldName {
            ranges[index].bgName = newName
        }
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

    mutating func reconcileInsert(at index: Int, oldFrameCount: Int) -> [BackgroundAutoTweenRange] {
        let (next, retween) = TweenSpanReconciler.reconcileInsert(
            spans: ranges,
            at: index,
            oldFrameCount: oldFrameCount,
            owner: "BackgroundTweenStorage"
        )
        ranges = next
        if oldFrameCount >= 1 && index >= 0 && index <= oldFrameCount {
            ensureValid(frameCount: oldFrameCount + 1)
        }
        return retween
    }

    mutating func reconcileDelete(deleted: [Int], oldFrameCount: Int) -> [BackgroundAutoTweenRange] {
        let (next, retween) = TweenSpanReconciler.reconcileDelete(
            spans: ranges,
            deleted: deleted,
            oldFrameCount: oldFrameCount,
            owner: "BackgroundTweenStorage"
        )
        ranges = next
        if oldFrameCount >= 1 {
            ensureValid(frameCount: oldFrameCount - Set(deleted).count)
        }
        return retween
    }

    func encodeArchive(scene: StickmanScene) throws -> Data {
        let spans = ranges.compactMap { span -> PersistedSpan? in
            if span.fromFrame < 0 || span.toFrame >= scene.frames.count {
                return nil
            }
            return PersistedSpan(
                ownerType: Self.ownerType,
                segmentNumber: span.segmentNumber,
                fromFrameId: scene.frames[span.fromFrame].id,
                toFrameId: scene.frames[span.toFrame].id,
                bgName: span.bgName,
                easingType: span.easingType,
                easingStrength: span.easingStrength,
                shakeFrequency: span.shakeFrequency,
                params: ["shakeFrequency": span.shakeFrequency]
            )
        }
        do {
            return try JSONEncoder().encode(Archive(spans: spans))
        } catch {
            throw SceneLoadError(message: "BackgroundTweenStorage encode: \(error)")
        }
    }

    mutating func importArchive(_ data: Data, scene: StickmanScene) throws {
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            throw SceneLoadError(message: "BackgroundTweenStorage background_tweens_v1.txt JSON: \(error)")
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
                BackgroundAutoTweenRange(
                    fromFrame: from,
                    toFrame: to,
                    bgName: persisted.bgName,
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
        let before = ranges.count
        ranges.removeAll { $0.fromFrame < 0 || $0.toFrame >= frameCount || $0.fromFrame >= $0.toFrame }
        if ranges.count != before {
            assertionFailure("dropped \(before - ranges.count) invalid background tween spans for \(frameCount) frames")
        }
        sort()
        var kept: [BackgroundAutoTweenRange] = []
        for current in ranges {
            if let prev = kept.last, prev.intersects(from: current.fromFrame, to: current.toFrame) {
                assertionFailure(
                    "Overlapping background spans: [\(prev.fromFrame)..\(prev.toFrame)] and [\(current.fromFrame)..\(current.toFrame)] — dropping later span"
                )
                continue
            }
            kept.append(current)
        }
        ranges = kept
        let maxSegment = ranges.map(\.segmentNumber).max() ?? 0
        nextSegmentNumber = max(nextSegmentNumber, maxSegment + 1)
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
        var bgName: String
        var easingType: TweenEasing
        var easingStrength: Float
        var shakeFrequency: Float?
        var params: [String: Float]?
    }
}
