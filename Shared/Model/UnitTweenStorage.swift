import Foundation

struct AutoTweenRange: Equatable {
    var unitName: String
    var fromFrame: Int
    var toFrame: Int
    var easingType: TweenEasing
    var easingStrength: Float
    var shakeFrequency: Float

    init(
        unitName: String,
        fromFrame: Int,
        toFrame: Int,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float
    ) {
        if unitName.isEmpty {
            fatalError("AutoTweenRange empty unitName")
        }
        self.unitName = unitName
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.easingType = easingType
        self.easingStrength = min(max(easingStrength, 0), 1)
        self.shakeFrequency = UnitTweenStorage.clampFrequency(easingType, shakeFrequency)
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

struct UnitTweenStorage: Equatable {
    static let ownerType = "unit"
    static let archiveName = "unit_tweens_v1.txt"
    static let defaultShakeFrequency: Float = 6
    static let minShakeFrequency: Float = 2
    static let maxShakeFrequency: Float = 12
    static let defaultCartwheelTurns: Float = 3
    static let minCartwheelTurns: Float = 1
    static let maxCartwheelTurns: Float = 12

    var ranges: [AutoTweenRange] = []

    var isEmpty: Bool { ranges.isEmpty }

    mutating func register(
        unitName: String,
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
            fatalError("Auto tween range \(from)..\(to) out of \(frameCount)")
        }
        if from >= to {
            fatalError("Auto tween range must cover at least 2 frames")
        }
        ranges.removeAll { $0.unitName == unitName && $0.intersects(from: from, to: to) }
        ranges.append(
            AutoTweenRange(
                unitName: unitName,
                fromFrame: from,
                toFrame: to,
                easingType: easingType,
                easingStrength: easingStrength,
                shakeFrequency: shakeFrequency
            )
        )
        sort()
    }

    func findContaining(unitName: String, frameIndex: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.contains(frameIndex) }
    }

    func findExact(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.fromFrame == from && $0.toFrame == to }
    }

    func findContainingSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.containsSpan(from: from, to: to) }
    }

    func findForSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return findContainingSpan(unitName: unitName, from: start, to: end)
    }

    func findIntersecting(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.intersects(from: from, to: to) }
    }

    func isPoseLocked(unitName: String, frameIndex: Int) -> Bool {
        ranges.contains { $0.unitName == unitName && $0.containsInterior(frameIndex) }
    }

    func isOwned(unitName: String, frameIndex: Int) -> Bool {
        findContaining(unitName: unitName, frameIndex: frameIndex) != nil
    }

    func poseLockMessage(unitName: String, frameIndex: Int) -> String {
        if let range = findContaining(unitName: unitName, frameIndex: frameIndex) {
            return "AUTO tween lock: \(unitName) frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO tween lock: \(unitName) frame \(frameIndex)"
    }

    func structureLockMessage(unitName: String, frameIndex: Int) -> String {
        if let range = findContaining(unitName: unitName, frameIndex: frameIndex) {
            return "AUTO tween structure lock: \(unitName) frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO tween structure lock: \(unitName) frame \(frameIndex)"
    }

    mutating func removeContaining(unitName: String, frameIndex: Int) -> AutoTweenRange? {
        guard let range = findContaining(unitName: unitName, frameIndex: frameIndex) else {
            return nil
        }
        ranges.removeAll { $0 == range }
        return range
    }

    mutating func removeExact(unitName: String, from: Int, to: Int) {
        ranges.removeAll { $0.unitName == unitName && $0.fromFrame == from && $0.toFrame == to }
    }

    mutating func clear() {
        ranges.removeAll()
    }

    mutating func replace(_ next: [AutoTweenRange], frameCount: Int) {
        ranges = next
        ensureValid(frameCount: frameCount)
    }

    mutating func ensureValid(frameCount: Int) {
        ensureNonOverlapping()
        for span in ranges {
            if span.fromFrame < 0 || span.toFrame >= frameCount || span.fromFrame >= span.toFrame {
                fatalError("unit span [\(span.fromFrame)..\(span.toFrame)] invalid for \(frameCount) frames")
            }
        }
        sort()
    }

    func copy() -> UnitTweenStorage {
        UnitTweenStorage(ranges: ranges)
    }

    func encodeArchive(scene: StickmanScene) -> Data {
        let spans = ranges.compactMap { span -> PersistedSpan? in
            if span.fromFrame < 0 || span.toFrame >= scene.frames.count {
                return nil
            }
            return PersistedSpan(
                ownerType: Self.ownerType,
                unitName: span.unitName,
                fromFrameId: scene.frames[span.fromFrame].id,
                toFrameId: scene.frames[span.toFrame].id,
                easingType: span.easingType,
                easingStrength: span.easingStrength,
                params: ["shakeFrequency": span.shakeFrequency]
            )
        }
        do {
            return try JSONEncoder().encode(Archive(spans: spans))
        } catch {
            fatalError("UnitTweenStorage encode: \(error)")
        }
    }

    mutating func importArchive(_ data: Data, scene: StickmanScene) {
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            fatalError("UnitTweenStorage unit_tweens_v1.txt JSON: \(error)")
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
            let unitName = PackAlias.resolveUnitName(persisted.unitName)
            if unitName.isEmpty {
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
            if findIntersecting(unitName: unitName, from: from, to: to) != nil {
                continue
            }
            if scene.frames[from].units.first(where: { $0.name == unitName }) == nil {
                continue
            }
            if scene.frames[to].units.first(where: { $0.name == unitName }) == nil {
                continue
            }
            let frequency = persisted.params?["shakeFrequency"] ?? Self.defaultShakeFrequency
            register(
                unitName: unitName,
                fromFrame: from,
                toFrame: to,
                easingType: persisted.easingType,
                easingStrength: persisted.easingStrength,
                shakeFrequency: frequency,
                frameCount: scene.frames.count
            )
        }
        ensureValid(frameCount: scene.frames.count)
    }

    static func clampFrequency(_ easing: TweenEasing, _ frequency: Float) -> Float {
        if easing.isCartwheel {
            return min(max(frequency, minCartwheelTurns), maxCartwheelTurns)
        }
        return min(max(frequency, minShakeFrequency), maxShakeFrequency)
    }

    mutating func reconcileInsert(at index: Int, oldFrameCount: Int) -> [AutoTweenRange] {
        if oldFrameCount < 1 {
            fatalError("UnitTweenStorage insert oldFrameCount \(oldFrameCount)")
        }
        if index < 0 || index > oldFrameCount {
            fatalError("UnitTweenStorage insert \(index) out of \(oldFrameCount)")
        }
        var retween: [AutoTweenRange] = []
        var next: [AutoTweenRange] = []
        for span in ranges {
            let remapped: AutoTweenRange
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

    mutating func reconcileDelete(deleted: [Int], oldFrameCount: Int) -> [AutoTweenRange] {
        if oldFrameCount < 1 {
            fatalError("UnitTweenStorage delete oldFrameCount \(oldFrameCount)")
        }
        let deletedSet = Set(deleted)
        var retween: [AutoTweenRange] = []
        var next: [AutoTweenRange] = []
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

    func wouldInsertSplit(after index: Int) -> Bool {
        if index < 0 {
            return false
        }
        return ranges.contains { $0.fromFrame <= index && index < $0.toFrame }
    }

    private func remap(_ span: AutoTweenRange, from: Int, to: Int) -> AutoTweenRange {
        AutoTweenRange(
            unitName: span.unitName,
            fromFrame: from,
            toFrame: to,
            easingType: span.easingType,
            easingStrength: span.easingStrength,
            shakeFrequency: span.shakeFrequency
        )
    }

    private mutating func sort() {
        ranges.sort {
            if $0.unitName != $1.unitName {
                return $0.unitName < $1.unitName
            }
            if $0.fromFrame != $1.fromFrame {
                return $0.fromFrame < $1.fromFrame
            }
            return $0.toFrame < $1.toFrame
        }
    }

    private func ensureNonOverlapping() {
        var byUnit: [String: [AutoTweenRange]] = [:]
        for span in ranges {
            byUnit[span.unitName, default: []].append(span)
        }
        for (name, spans) in byUnit {
            let ordered = spans.sorted {
                $0.fromFrame == $1.fromFrame ? $0.toFrame < $1.toFrame : $0.fromFrame < $1.fromFrame
            }
            for i in 1..<ordered.count {
                let prev = ordered[i - 1]
                let current = ordered[i]
                if prev.intersects(from: current.fromFrame, to: current.toFrame) {
                    fatalError(
                        "Overlapping unit spans for \(name): [\(prev.fromFrame)..\(prev.toFrame)] and [\(current.fromFrame)..\(current.toFrame)]"
                    )
                }
            }
        }
    }

    private struct Archive: Codable {
        var spans: [PersistedSpan]
    }

    private struct PersistedSpan: Codable {
        var ownerType: String
        var unitName: String
        var fromFrameId: Int
        var toFrameId: Int
        var easingType: TweenEasing
        var easingStrength: Float
        var params: [String: Float]?
    }
}
