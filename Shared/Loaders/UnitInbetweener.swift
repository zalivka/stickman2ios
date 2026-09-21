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
        shakeFrequency: Float
    ) -> Bool {
        if from < 0 || to >= scene.frames.count || from >= to {
            fatalError("UnitInbetweener range \(from)..\(to) out of \(scene.frames.count)")
        }
        guard let startRoot = scene.frames[from].units.first(where: { $0.name == rootName }) else {
            fatalError("UnitInbetweener missing '\(rootName)' on frame \(from)")
        }
        if SlavesRegistry.isEnslaved(startRoot) {
            fatalError("UnitInbetweener enslaved '\(rootName)'")
        }
        let conflicts = scene.ensureStructureOnRange(
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
            fatalError("UnitInbetweener missing '\(rootName)' after ensure")
        }
        if !mismatchedFrames(scene: scene, reference: startUnit, from: from, to: to).isEmpty {
            return false
        }

        _ = bake(scene: &scene, start: startUnit, end: endUnit, from: from, to: to,
                 easing: easing, strength: strength, shakeFrequency: shakeFrequency)

        let slaves = attachedSlaves(of: startUnit, in: scene.frames[from].units)
        for slave in slaves.sorted(by: { $0.name < $1.name }) {
            guard let startSlave = scene.frames[from].units.first(where: { $0.name == slave.name }),
                  let endSlave = scene.frames[to].units.first(where: { $0.name == slave.name })
            else {
                fatalError("UnitInbetweener missing slave '\(slave.name)'")
            }
            _ = bake(scene: &scene, start: startSlave, end: endSlave, from: from, to: to,
                     easing: easing, strength: strength, shakeFrequency: shakeFrequency)
        }

        for index in from...to {
            let connected = SlavesRegistry.allConnected(
                of: scene.frames[index].unit(named: rootName),
                in: scene.frames[index].units
            )
            for unit in connected.sorted(by: {
                SlavesRegistry.slaveDepth($0, in: scene.frames[index].units)
                    < SlavesRegistry.slaveDepth($1, in: scene.frames[index].units)
            }) where SlavesRegistry.isEnslaved(unit) {
                scene.frames[index].moveUnitToMaster(named: unit.name)
            }
            scene.frames[index].refreshAttachments()
        }

        scene.unitTweens.register(
            unitName: rootName,
            fromFrame: from,
            toFrame: to,
            easingType: easing,
            easingStrength: strength,
            shakeFrequency: shakeFrequency,
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
                frameCount: scene.frames.count
            )
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
    ) -> StickmanUnit {
        if framesCount <= 0 {
            fatalError("UnitInbetweener framesCount \(framesCount)")
        }
        if step < 0 || step >= framesCount {
            fatalError("UnitInbetweener step \(step) out of \(framesCount)")
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
        return UnitStateInterpolator.inbetweenStatesAt(
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
        shakeFrequency: Float
    ) -> [Int] {
        if start.name != end.name {
            fatalError("UnitInbetweener bake name mismatch '\(start.name)' vs '\(end.name)'")
        }
        let framesCount = to - from + 1
        var written: [Int] = []
        for step in 0..<framesCount {
            let pose = interpolateClosedRange(
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
                fatalError("UnitInbetweener bake missing '\(start.name)' on frame \(frameIndex)")
            }
            scene.frames[frameIndex].units[unitIndex].applyPose(from: pose)
            written.append(frameIndex)
        }
        return written
    }

    private static func mismatchedFrames(
        scene: StickmanScene,
        reference: StickmanUnit,
        from: Int,
        to: Int
    ) -> [Int] {
        var mismatches: [Int] = []
        for index in from...to {
            guard let onFrame = scene.frames[index].units.first(where: { $0.name == reference.name }) else {
                mismatches.append(index)
                continue
            }
            if !sameConnectedStructure(reference, onFrame, unitsA: scene.frames[from].units, unitsB: scene.frames[index].units) {
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
    ) -> Bool {
        if startRoot.name != endRoot.name {
            return false
        }
        return attachedSlaves(of: startRoot, in: unitsA) == attachedSlaves(of: endRoot, in: unitsB)
    }

    private static func attachedSlaves(of root: StickmanUnit, in units: [StickmanUnit]) -> Set<AttachedSlave> {
        var out = Set<AttachedSlave>()
        for unit in SlavesRegistry.allConnected(of: root, in: units) where unit.name != root.name {
            guard let attachment = SlavesRegistry.attachment(of: unit) else {
                fatalError("UnitInbetweener connected '\(unit.name)' has no attachment")
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
