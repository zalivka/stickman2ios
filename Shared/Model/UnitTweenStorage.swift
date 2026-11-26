import Foundation

enum TweenChannel: String, Codable, CaseIterable, Equatable {
    case both = "BOTH"
    case motion = "MOTION"
    case color = "COLOR"

    var displayName: String {
        switch self {
        case .both: return "Both"
        case .motion: return "Motion"
        case .color: return "Color"
        }
    }

    var includesMotion: Bool {
        self == .both || self == .motion
    }

    var includesColor: Bool {
        self == .both || self == .color
    }

    func conflicts(with other: TweenChannel) -> Bool {
        (includesMotion && other.includesMotion) || (includesColor && other.includesColor)
    }
}

protocol TweenSpanProtocol: Equatable {
    var fromFrame: Int { get }
    var toFrame: Int { get }
    func remapped(from: Int, to: Int) -> Self
}

extension TweenSpanProtocol {
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

    func progress(originIndex: Int, localProgress: Float) -> Float {
        let sourcePosition = Float(originIndex) + localProgress
        let raw = (sourcePosition - Float(fromFrame)) / Float(toFrame - fromFrame)
        return min(max(raw, 0), 1)
    }
}

enum TweenSpanReconciler {
    static func reconcileInsert<Span: TweenSpanProtocol>(
        spans: [Span],
        at index: Int,
        oldFrameCount: Int,
        owner: String
    ) -> (next: [Span], retween: [Span]) {
        if oldFrameCount < 1 {
            assertionFailure("\(owner) insert oldFrameCount \(oldFrameCount)")
            return (spans, [])
        }
        if index < 0 || index > oldFrameCount {
            assertionFailure("\(owner) insert \(index) out of \(oldFrameCount)")
            return (spans, [])
        }
        var retween: [Span] = []
        var next: [Span] = []
        for span in spans {
            let remapped: Span
            if index <= span.fromFrame {
                remapped = span.remapped(from: span.fromFrame + 1, to: span.toFrame + 1)
            } else if index <= span.toFrame {
                remapped = span.remapped(from: span.fromFrame, to: span.toFrame + 1)
                retween.append(remapped)
            } else {
                remapped = span
            }
            next.append(remapped)
        }
        return (next, retween)
    }

    static func reconcileDelete<Span: TweenSpanProtocol>(
        spans: [Span],
        deleted: [Int],
        oldFrameCount: Int,
        owner: String
    ) -> (next: [Span], retween: [Span]) {
        if oldFrameCount < 1 {
            assertionFailure("\(owner) delete oldFrameCount \(oldFrameCount)")
            return (spans, [])
        }
        let deletedSet = Set(deleted)
        var retween: [Span] = []
        var next: [Span] = []
        for span in spans {
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
            let remapped = span.remapped(from: from, to: to)
            if (span.fromFrame + 1..<span.toFrame).contains(where: { deletedSet.contains($0) }) {
                retween.append(remapped)
            }
            next.append(remapped)
        }
        return (next, retween)
    }
}

struct AutoTweenRange: TweenSpanProtocol {
    var unitName: String
    var fromFrame: Int
    var toFrame: Int
    var easingType: TweenEasing
    var easingStrength: Float
    var shakeFrequency: Float
    var channel: TweenChannel

    init(
        unitName: String,
        fromFrame: Int,
        toFrame: Int,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        channel: TweenChannel = .both
    ) {
        if unitName.isEmpty {
            assertionFailure("AutoTweenRange empty unitName")
        }
        self.unitName = unitName
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.easingType = easingType
        self.easingStrength = min(max(easingStrength, 0), 1)
        self.shakeFrequency = UnitTweenStorage.clampFrequency(easingType, shakeFrequency)
        self.channel = channel
    }

    func remapped(from: Int, to: Int) -> AutoTweenRange {
        AutoTweenRange(
            unitName: unitName,
            fromFrame: from,
            toFrame: to,
            easingType: easingType,
            easingStrength: easingStrength,
            shakeFrequency: shakeFrequency,
            channel: channel
        )
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
    static let defaultPulseFrequency: Float = 3
    static let minPulseFrequency: Float = 1
    static let maxPulseFrequency: Float = 12

    var ranges: [AutoTweenRange] = []

    var isEmpty: Bool { ranges.isEmpty }

    mutating func register(
        unitName: String,
        fromFrame: Int,
        toFrame: Int,
        easingType: TweenEasing,
        easingStrength: Float,
        shakeFrequency: Float,
        channel: TweenChannel = .both,
        frameCount: Int
    ) {
        let from = min(fromFrame, toFrame)
        let to = max(fromFrame, toFrame)
        if from < 0 || to >= frameCount {
            assertionFailure("Auto tween range \(from)..\(to) out of \(frameCount)")
            return
        }
        if from >= to {
            assertionFailure("Auto tween range must cover at least 2 frames")
            return
        }
        ranges.removeAll {
            $0.unitName == unitName
                && $0.channel.conflicts(with: channel)
                && $0.intersects(from: from, to: to)
        }
        ranges.append(
            AutoTweenRange(
                unitName: unitName,
                fromFrame: from,
                toFrame: to,
                easingType: easingType,
                easingStrength: easingStrength,
                shakeFrequency: shakeFrequency,
                channel: channel
            )
        )
        sort()
    }

    func findContaining(unitName: String, frameIndex: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.contains(frameIndex) }
    }

    func findAllContaining(unitName: String, frameIndex: Int) -> [AutoTweenRange] {
        ranges.filter { $0.unitName == unitName && $0.contains(frameIndex) }
    }

    func findExact(unitName: String, from: Int, to: Int, channel: TweenChannel? = nil) -> AutoTweenRange? {
        ranges.first {
            $0.unitName == unitName
                && $0.fromFrame == from
                && $0.toFrame == to
                && (channel == nil || $0.channel == channel)
        }
    }

    func findContainingSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        ranges.first { $0.unitName == unitName && $0.containsSpan(from: from, to: to) }
    }

    func findForSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return findContainingSpan(unitName: unitName, from: start, to: end)
    }

    func findMotionForSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return ranges.first {
            $0.unitName == unitName && $0.channel.includesMotion && $0.containsSpan(from: start, to: end)
        }
    }

    func findColorForSpan(unitName: String, from: Int, to: Int) -> AutoTweenRange? {
        let start = min(from, to)
        let end = max(from, to)
        return ranges.first {
            $0.unitName == unitName && $0.channel.includesColor && $0.containsSpan(from: start, to: end)
        }
    }

    func findIntersecting(unitName: String, from: Int, to: Int, channel: TweenChannel = .both) -> AutoTweenRange? {
        ranges.first {
            $0.unitName == unitName
                && $0.channel.conflicts(with: channel)
                && $0.intersects(from: from, to: to)
        }
    }

    func isPoseLocked(unitName: String, frameIndex: Int) -> Bool {
        ranges.contains { $0.unitName == unitName && $0.channel.includesMotion && $0.containsInterior(frameIndex) }
    }

    func isColorLocked(unitName: String, frameIndex: Int) -> Bool {
        ranges.contains { $0.unitName == unitName && $0.channel.includesColor && $0.containsInterior(frameIndex) }
    }

    func isOwned(unitName: String, frameIndex: Int) -> Bool {
        findContaining(unitName: unitName, frameIndex: frameIndex) != nil
    }

    func poseLockMessage(unitName: String, frameIndex: Int) -> String {
        if let range = ranges.first(where: { $0.unitName == unitName && $0.channel.includesMotion && $0.contains(frameIndex) }) {
            return "AUTO tween lock: \(unitName) frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO tween lock: \(unitName) frame \(frameIndex)"
    }

    func colorLockMessage(unitName: String, frameIndex: Int) -> String {
        if let range = ranges.first(where: { $0.unitName == unitName && $0.channel.includesColor && $0.contains(frameIndex) }) {
            return "AUTO color tween lock: \(unitName) frame \(frameIndex) is in [\(range.fromFrame)..\(range.toFrame)]"
        }
        return "AUTO color tween lock: \(unitName) frame \(frameIndex)"
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

    mutating func removeExact(unitName: String, from: Int, to: Int, channel: TweenChannel? = nil) {
        ranges.removeAll {
            $0.unitName == unitName
                && $0.fromFrame == from
                && $0.toFrame == to
                && (channel == nil || $0.channel == channel)
        }
    }

    mutating func clear() {
        ranges.removeAll()
    }

    mutating func replace(_ next: [AutoTweenRange], frameCount: Int) {
        ranges = next
        ensureValid(frameCount: frameCount)
    }

    mutating func ensureValid(frameCount: Int) {
        let before = ranges.count
        ranges.removeAll { $0.fromFrame < 0 || $0.toFrame >= frameCount || $0.fromFrame >= $0.toFrame }
        if ranges.count != before {
            assertionFailure("dropped \(before - ranges.count) invalid unit tween spans for \(frameCount) frames")
        }
        ensureNonOverlapping()
        sort()
    }

    func copy() -> UnitTweenStorage {
        UnitTweenStorage(ranges: ranges)
    }

    func encodeArchive(scene: StickmanScene) throws -> Data {
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
                params: ["shakeFrequency": span.shakeFrequency],
                channel: span.channel
            )
        }
        do {
            return try JSONEncoder().encode(Archive(spans: spans))
        } catch {
            throw SceneLoadError(message: "UnitTweenStorage encode: \(error)")
        }
    }

    mutating func importArchive(_ data: Data, scene: StickmanScene) throws {
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            throw SceneLoadError(message: "UnitTweenStorage unit_tweens_v1.txt JSON: \(error)")
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
            let core = UnitAssets.removeNumber(persisted.unitName)
            if let colon = core.firstIndex(of: ":"), core[core.index(after: colon)...].isEmpty {
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
            let channel = persisted.channel ?? .both
            if findIntersecting(unitName: unitName, from: from, to: to, channel: channel) != nil {
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
                channel: channel,
                frameCount: scene.frames.count
            )
        }
        ensureValid(frameCount: scene.frames.count)
    }

    static func clampFrequency(_ easing: TweenEasing, _ frequency: Float) -> Float {
        if easing.isCartwheel {
            return min(max(frequency, minCartwheelTurns), maxCartwheelTurns)
        }
        if easing.isPulseColor {
            return min(max(frequency, minPulseFrequency), maxPulseFrequency)
        }
        return min(max(frequency, minShakeFrequency), maxShakeFrequency)
    }

    mutating func reconcileInsert(at index: Int, oldFrameCount: Int) -> [AutoTweenRange] {
        let (next, retween) = TweenSpanReconciler.reconcileInsert(
            spans: ranges,
            at: index,
            oldFrameCount: oldFrameCount,
            owner: "UnitTweenStorage"
        )
        ranges = next
        if oldFrameCount >= 1 && index >= 0 && index <= oldFrameCount {
            ensureValid(frameCount: oldFrameCount + 1)
        }
        return retween
    }

    mutating func reconcileDelete(deleted: [Int], oldFrameCount: Int) -> [AutoTweenRange] {
        let (next, retween) = TweenSpanReconciler.reconcileDelete(
            spans: ranges,
            deleted: deleted,
            oldFrameCount: oldFrameCount,
            owner: "UnitTweenStorage"
        )
        ranges = next
        if oldFrameCount >= 1 {
            ensureValid(frameCount: oldFrameCount - Set(deleted).count)
        }
        return retween
    }

    func wouldInsertSplit(after index: Int) -> Bool {
        if index < 0 {
            return false
        }
        return ranges.contains { $0.fromFrame <= index && index < $0.toFrame }
    }

    private mutating func sort() {
        ranges.sort {
            if $0.unitName != $1.unitName {
                return $0.unitName < $1.unitName
            }
            if $0.fromFrame != $1.fromFrame {
                return $0.fromFrame < $1.fromFrame
            }
            if $0.toFrame != $1.toFrame {
                return $0.toFrame < $1.toFrame
            }
            return $0.channel.rawValue < $1.channel.rawValue
        }
    }

    private mutating func ensureNonOverlapping() {
        var byUnit: [String: [AutoTweenRange]] = [:]
        for span in ranges {
            byUnit[span.unitName, default: []].append(span)
        }
        var dropKeys: [AutoTweenRange] = []
        for (name, spans) in byUnit {
            let ordered = spans.sorted {
                $0.fromFrame == $1.fromFrame ? $0.toFrame < $1.toFrame : $0.fromFrame < $1.fromFrame
            }
            var kept: [AutoTweenRange] = []
            for current in ordered {
                if let prev = kept.first(where: {
                    $0.channel.conflicts(with: current.channel)
                        && $0.intersects(from: current.fromFrame, to: current.toFrame)
                }) {
                    assertionFailure(
                        "Overlapping unit spans for \(name): [\(prev.fromFrame)..\(prev.toFrame)] and [\(current.fromFrame)..\(current.toFrame)] — dropping later span"
                    )
                    dropKeys.append(current)
                    continue
                }
                kept.append(current)
            }
        }
        if !dropKeys.isEmpty {
            ranges.removeAll { span in
                dropKeys.contains(where: {
                    $0.unitName == span.unitName
                        && $0.fromFrame == span.fromFrame
                        && $0.toFrame == span.toFrame
                        && $0.channel == span.channel
                })
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
        var channel: TweenChannel?
    }
}
