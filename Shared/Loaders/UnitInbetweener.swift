import CoreGraphics
import Foundation

enum UnitInbetweener {
    static func propagate(
        scene: inout StickmanScene,
        rootName: String,
        from: Int,
        to: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float,
        channel: TweenChannel = .both
    ) throws -> Bool {
        if from < 0 || to >= scene.frames.count || from >= to {
            throw SceneLoadError(message: "UnitInbetweener range \(from)..\(to) out of \(scene.frames.count)")
        }
        guard let startRoot = scene.frames[from].units.first(where: { $0.name == rootName }) else {
            throw SceneLoadError(message: "UnitInbetweener missing '\(rootName)' on frame \(from)")
        }
        if SlavesRegistry.isEnslaved(startRoot) {
            throw SceneLoadError(message: "UnitInbetweener enslaved '\(rootName)'")
        }
        if channel.includesMotion && !endpointFlipsMatch(scene: scene, rootName: rootName, from: from, to: to) {
            return false
        }
        if channel.includesColor && !endpointEffectsCompatible(scene: scene, rootName: rootName, from: from, to: to) {
            return false
        }
        let conflicts = try scene.ensureStructureOnRange(
            root: startRoot,
            in: scene.frames[from].units,
            range: from...to
        )
        if !conflicts.isEmpty {
            return false
        }
        guard let startUnit = scene.frames[from].units.first(where: { $0.name == rootName }),
              let endUnit = scene.frames[to].units.first(where: { $0.name == rootName })
        else {
            throw SceneLoadError(message: "UnitInbetweener missing '\(rootName)' after ensure")
        }
        let mismatched = try mismatchedFrames(scene: scene, reference: startUnit, from: from, to: to)
        if !mismatched.isEmpty {
            return false
        }

        _ = try bake(
            scene: &scene, start: startUnit, end: endUnit, from: from, to: to,
            easing: easing, strength: strength, shakeFrequency: shakeFrequency, channel: channel
        )

        let slaves = try attachedSlaves(of: startUnit, in: scene.frames[from].units)
        for slave in slaves.sorted(by: { $0.name < $1.name }) {
            guard let startSlave = scene.frames[from].units.first(where: { $0.name == slave.name }),
                  let endSlave = scene.frames[to].units.first(where: { $0.name == slave.name })
            else {
                throw SceneLoadError(message: "UnitInbetweener missing slave '\(slave.name)'")
            }
            _ = try bake(
                scene: &scene, start: startSlave, end: endSlave, from: from, to: to,
                easing: easing, strength: strength, shakeFrequency: shakeFrequency, channel: channel
            )
        }

        if channel.includesMotion {
            for index in from...to {
                let connected = try SlavesRegistry.allConnected(
                    of: scene.frames[index].unit(named: rootName),
                    in: scene.frames[index].units
                )
                for unit in connected.sorted(by: {
                    SlavesRegistry.slaveDepth($0, in: scene.frames[index].units)
                        < SlavesRegistry.slaveDepth($1, in: scene.frames[index].units)
                }) where SlavesRegistry.isEnslaved(unit) {
                    try scene.frames[index].moveUnitToMaster(named: unit.name)
                }
                try scene.frames[index].refreshAttachments()
            }
        }

        scene.unitTweens.register(
            unitName: rootName,
            fromFrame: from,
            toFrame: to,
            easingType: easing,
            easingStrength: strength,
            shakeFrequency: shakeFrequency,
            channel: channel,
            frameCount: scene.frames.count
        )
        for slave in slaves {
            scene.unitTweens.register(
                unitName: slave.name,
                fromFrame: from,
                toFrame: to,
                easingType: easing,
                easingStrength: strength,
                shakeFrequency: shakeFrequency,
                channel: channel,
                frameCount: scene.frames.count
            )
        }
        return true
    }

    /// Non-mutating pre-flight check matching `propagate`: verifies the unit exists on both
    /// endpoints, flip flags match (when `channel.includesMotion`), connected structures match,
    /// and any missing interior frames have no name conflicts when auto-pasting the structure.
    static func canPropagate(
        scene: StickmanScene,
        rootName: String,
        from: Int,
        to: Int,
        channel: TweenChannel = .both
    ) -> Bool {
        rangeWarning(scene: scene, rootName: rootName, from: from, to: to, channel: channel) == nil
    }

    /// Returns a clear user-facing blocking message when the span cannot be tweened, or `nil` when valid.
    static func rangeWarning(
        scene: StickmanScene,
        rootName: String,
        from: Int,
        to: Int,
        channel: TweenChannel = .both
    ) -> String? {
        guard from >= 0, to < scene.frames.count, from < to else {
            return "Items are different"
        }
        guard let startRoot = scene.frames[from].units.first(where: { $0.name == rootName }),
              !SlavesRegistry.isEnslaved(startRoot),
              scene.frames[to].units.contains(where: { $0.name == rootName })
        else {
            return "Item is missing on start or end frame"
        }
        guard let structure = try? SlavesRegistry.allConnected(of: startRoot, in: scene.frames[from].units) else {
            return "Items are different"
        }
        for index in from...to {
            let frame = scene.frames[index]
            let intact = (try? frame.structureIntact(structure)) ?? false
            if !intact && frame.hasNameIntersection(structure) {
                return "Attached items are different"
            }
        }
        if channel.includesMotion && !endpointFlipsMatch(scene: scene, rootName: rootName, from: from, to: to) {
            return "First and last frame are flipped differently"
        }
        if channel.includesColor && !endpointEffectsCompatible(scene: scene, rootName: rootName, from: from, to: to) {
            return "Color effects are different (e.g. Fade vs Tint)"
        }
        return nil
    }

    /// Root and every slave present on both ends have compatible color effects
    /// (either one is `.none` / 0% power, or both share the same `CameraEffect.Kind`).
    static func endpointEffectsCompatible(scene: StickmanScene, rootName: String, from: Int, to: Int) -> Bool {
        guard from >= 0, to < scene.frames.count, from <= to else {
            return true
        }
        guard let start = scene.frames[from].units.first(where: { $0.name == rootName }),
              let end = scene.frames[to].units.first(where: { $0.name == rootName })
        else {
            return true
        }
        if !start.effect.canTween(with: end.effect) {
            return false
        }
        var registry = SlavesRegistry()
        guard (try? registry.populate(units: scene.frames[from].units)) != nil else {
            return true
        }
        for slaveName in registry.allSlaves(of: rootName) {
            guard let startSlave = scene.frames[from].units.first(where: { $0.name == slaveName }),
                  let endSlave = scene.frames[to].units.first(where: { $0.name == slaveName })
            else {
                continue
            }
            if !startSlave.effect.canTween(with: endSlave.effect) {
                return false
            }
        }
        return true
    }

    /// Root and every slave present on both ends share a flip flag.
    /// A missing unit is ignored; structure checks report that. Interior frames are not consulted.
    static func endpointFlipsMatch(scene: StickmanScene, rootName: String, from: Int, to: Int) -> Bool {
        guard from >= 0, to < scene.frames.count, from <= to else {
            return true
        }
        guard let start = scene.frames[from].units.first(where: { $0.name == rootName }),
              let end = scene.frames[to].units.first(where: { $0.name == rootName })
        else {
            return true
        }
        if start.flipped != end.flipped {
            return false
        }
        var registry = SlavesRegistry()
        guard (try? registry.populate(units: scene.frames[from].units)) != nil else {
            return true
        }
        for slaveName in registry.allSlaves(of: rootName) {
            guard let startSlave = scene.frames[from].units.first(where: { $0.name == slaveName }),
                  let endSlave = scene.frames[to].units.first(where: { $0.name == slaveName })
            else {
                continue
            }
            if startSlave.flipped != endSlave.flipped {
                return false
            }
        }
        return true
    }

    static func interpolateClosedRange(
        start: StickmanUnit,
        end: StickmanUnit,
        step: Int,
        framesCount: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float
    ) throws -> StickmanUnit {
        if framesCount <= 0 {
            throw SceneLoadError(message: "UnitInbetweener framesCount \(framesCount)")
        }
        if step < 0 || step >= framesCount {
            throw SceneLoadError(message: "UnitInbetweener step \(step) out of \(framesCount)")
        }
        if step == 0 {
            return start
        }
        if step == framesCount - 1 {
            return end
        }
        let spanDuration = max(1, framesCount - 1)
        let t = Float(step) / Float(spanDuration)
        let eased = Easing.sample(easing, t: t, strength: strength)
        return try UnitStateInterpolator.inbetweenStatesAt(
            unit1: start,
            unit2: end,
            t: eased,
            easing: easing,
            strength: strength,
            frequency: shakeFrequency,
            effectT: t
        )
    }

    private static func bake(
        scene: inout StickmanScene,
        start: StickmanUnit,
        end: StickmanUnit,
        from: Int,
        to: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float,
        channel: TweenChannel
    ) throws -> [Int] {
        if start.name != end.name {
            throw SceneLoadError(message: "UnitInbetweener bake name mismatch '\(start.name)' vs '\(end.name)'")
        }
        let framesCount = to - from + 1
        var written: [Int] = []
        for step in 0..<framesCount {
            let pose = try interpolateClosedRange(
                start: start,
                end: end,
                step: step,
                framesCount: framesCount,
                easing: easing,
                strength: strength,
                shakeFrequency: shakeFrequency
            )
            let frameIndex = from + step
            guard let unitIndex = scene.frames[frameIndex].units.firstIndex(where: { $0.name == start.name }) else {
                throw SceneLoadError(message: "UnitInbetweener bake missing '\(start.name)' on frame \(frameIndex)")
            }
            try scene.frames[frameIndex].units[unitIndex].applyPose(from: pose, channel: channel)
            written.append(frameIndex)
        }
        return written
    }

    private static func mismatchedFrames(
        scene: StickmanScene,
        reference: StickmanUnit,
        from: Int,
        to: Int
    ) throws -> [Int] {
        var mismatches: [Int] = []
        for index in from...to {
            guard let onFrame = scene.frames[index].units.first(where: { $0.name == reference.name }) else {
                mismatches.append(index)
                continue
            }
            if try !sameConnectedStructure(reference, onFrame, unitsA: scene.frames[from].units, unitsB: scene.frames[index].units) {
                mismatches.append(index)
            }
        }
        return mismatches
    }

    private static func sameConnectedStructure(
        _ startRoot: StickmanUnit,
        _ endRoot: StickmanUnit,
        unitsA: [StickmanUnit],
        unitsB: [StickmanUnit]
    ) throws -> Bool {
        if startRoot.name != endRoot.name {
            return false
        }
        return try attachedSlaves(of: startRoot, in: unitsA) == attachedSlaves(of: endRoot, in: unitsB)
    }

    private static func attachedSlaves(of root: StickmanUnit, in units: [StickmanUnit]) throws -> Set<AttachedSlave> {
        var out = Set<AttachedSlave>()
        for unit in try SlavesRegistry.allConnected(of: root, in: units) where unit.name != root.name {
            guard let attachment = SlavesRegistry.attachment(of: unit) else {
                throw SceneLoadError(message: "UnitInbetweener connected '\(unit.name)' has no attachment")
            }
            out.insert(AttachedSlave(name: unit.name, attachment: attachment))
        }
        return out
    }

    private struct AttachedSlave: Hashable {
        var name: String
        var attachment: SlaveAttachment
    }
}
