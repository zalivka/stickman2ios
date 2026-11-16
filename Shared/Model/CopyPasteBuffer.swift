import Combine
import Foundation

/// Android `CopyPasteBuffer` — independent unit and frame slots, shared across scenes.
final class CopyPasteBuffer: ObservableObject {
    static let shared = CopyPasteBuffer()

    @Published private(set) var units: [StickmanUnit] = []
    @Published private(set) var frames: [StickmanFrame] = []
    @Published private(set) var animations: [String: FBFAnimation] = [:]
    private var unitArchives: [String: UnitAssets.StoredArchive] = [:]
    private var frameUnitArchives: [String: UnitAssets.StoredArchive] = [:]
    private var frameBackgroundArchives: [String: Data] = [:]

    var hasUnits: Bool { !units.isEmpty }
    var hasFrames: Bool { !frames.isEmpty }
    var framesInBuffer: Int { frames.count }

    func clear() {
        units = []
        frames = []
        animations = [:]
        unitArchives = [:]
        frameUnitArchives = [:]
        frameBackgroundArchives = [:]
    }

    func copyUnits(_ structure: [StickmanUnit], assets: UnitAssets = UnitAssets()) {
        if structure.isEmpty {
            assertionFailure("CopyPasteBuffer copyUnits empty")
            return
        }
        units = structure
        unitArchives = Self.captureUnitArchives(units: structure, from: assets)
    }

    func copyFrames(
        from scene: StickmanScene,
        indices: [Int],
        assets: UnitAssets = UnitAssets(),
        backgrounds: BackgroundAssets = BackgroundAssets()
    ) throws {
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
        frameUnitArchives = Self.captureUnitArchives(
            units: copied.flatMap(\.units),
            from: assets
        )
        frameBackgroundArchives = Self.captureBackgroundArchives(
            frames: copied,
            from: backgrounds
        )
    }

    @discardableResult
    func pasteFrames(
        into scene: inout StickmanScene,
        assets: UnitAssets = UnitAssets(),
        backgrounds: BackgroundAssets = BackgroundAssets()
    ) throws -> [Int] {
        if frames.isEmpty {
            assertionFailure("CopyPasteBuffer pasteFrames empty")
            return []
        }
        let inserted = try scene.pasteFrames(frames, animations: animations)
        try Self.ensureUnitAssets(
            units: frames.flatMap(\.units),
            into: assets,
            storedArchives: frameUnitArchives
        )
        Self.ensureBackgrounds(
            frames: frames,
            into: backgrounds,
            storedArchives: frameBackgroundArchives
        )
        return inserted
    }

    func pasteUnits(
        into scene: inout StickmanScene,
        at indices: [Int],
        assets: UnitAssets = UnitAssets()
    ) throws {
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
        try Self.ensureUnitAssets(
            units: units,
            into: assets,
            storedArchives: unitArchives
        )
    }

    private static func captureUnitArchives(
        units: [StickmanUnit],
        from assets: UnitAssets
    ) -> [String: UnitAssets.StoredArchive] {
        var result: [String: UnitAssets.StoredArchive] = [:]
        for unit in units {
            let key = UnitAssets.removeNumber(unit.name)
            if result[key] != nil || !assets.hasArchive(for: key) {
                continue
            }
            if let archive = assets.archive(for: key) {
                result[key] = archive
            }
        }
        return result
    }

    private static func captureBackgroundArchives(
        frames: [StickmanFrame],
        from backgrounds: BackgroundAssets
    ) -> [String: Data] {
        var result: [String: Data] = [:]
        for frame in frames {
            guard let bgName = frame.bgName, !bgName.hasPrefix("#") else {
                continue
            }
            if result[bgName] != nil || !backgrounds.hasImage(for: bgName) {
                continue
            }
            if let archive = backgrounds.archive(for: bgName) {
                result[bgName] = archive
            }
        }
        return result
    }

    private static func ensureUnitAssets(
        units: [StickmanUnit],
        into assets: UnitAssets,
        storedArchives: [String: UnitAssets.StoredArchive]
    ) throws {
        var seen = Set<String>()
        for unit in units {
            let key = UnitAssets.removeNumber(unit.name)
            if !seen.insert(key).inserted {
                continue
            }
            if assets.hasAssetsFor(unitName: key) && assets.hasArchive(for: key) {
                continue
            }
            if unit.unitType == .bubble && assets.hasArchive(for: key) {
                continue
            }
            if let stored = storedArchives[key] {
                try assets.loadItemFromArchive(stored.zip, entryName: stored.entryName, forceReload: false)
                continue
            }
            if let zip = try? Manifest.shared.itemZip(fullname: key) {
                try assets.loadItemFromArchive(
                    zip,
                    entryName: UnitAssets.atiEntryName(for: key),
                    forceReload: false
                )
            }
        }
    }

    private static func ensureBackgrounds(
        frames: [StickmanFrame],
        into backgrounds: BackgroundAssets,
        storedArchives: [String: Data]
    ) {
        var seen = Set<String>()
        for frame in frames {
            guard let bgName = frame.bgName, !bgName.hasPrefix("#") else {
                continue
            }
            if !seen.insert(bgName).inserted || backgrounds.hasImage(for: bgName) {
                continue
            }
            if let archive = storedArchives[bgName] {
                try? backgrounds.installArchive(name: bgName, archive: archive)
                continue
            }
            try? BackgroundResolver.install(bgName, into: backgrounds)
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
