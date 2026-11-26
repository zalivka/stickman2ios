import CoreGraphics
import Foundation

enum UnitStateInterpolator {
    static func inbetweenStatesAt(
        unit1: StickmanUnit,
        unit2: StickmanUnit,
        t: Float,
        easing: TweenEasing,
        strength: Float,
        frequency: Float,
        effectT: Float
    ) throws -> StickmanUnit {
        var pose = try NlerpInterpolator.inbetween(unit1: unit1, unit2: unit2, t: CGFloat(t))
        try UnitTweenEffects.apply(
            &pose,
            start: unit1,
            end: unit2,
            easing: easing,
            strength: strength,
            frequency: frequency,
            t: effectT
        )
        if easing.isPulseColor {
            let colorU = Easing.pulseProgress(t: effectT, frequency: frequency)
            let alphaVal = unit1.alpha + (unit2.alpha - unit1.alpha) * CGFloat(colorU)
            pose.alpha = min(max(alphaVal, 0), 1)
            pose.effect = CameraMoveInterpolator.tweenEffect(
                unit1.effect,
                unit2.effect,
                easing: easing,
                strength: strength,
                frequency: frequency,
                t: effectT
            )
        }
        return pose
    }

    static func inbetween(
        scene: StickmanScene,
        originIndex: Int,
        unit1: StickmanUnit,
        unit2: StickmanUnit,
        step: Int,
        framesNumber: Int
    ) throws -> StickmanUnit {
        if framesNumber <= 0 {
            throw SceneLoadError(message: "UnitStateInterpolator framesNumber must be > 0, got \(framesNumber)")
        }
        if step < 0 || step >= framesNumber {
            throw SceneLoadError(message: "UnitStateInterpolator step \(step) out of \(framesNumber)")
        }
        let localProgress = Float(step + 1) / Float(framesNumber + 1)
        let motionSpan = scene.unitTweens.findMotionForSpan(
            unitName: unit1.name,
            from: originIndex,
            to: originIndex + 1
        )
        let colorSpan = scene.unitTweens.findColorForSpan(
            unitName: unit1.name,
            from: originIndex,
            to: originIndex + 1
        )

        var result: StickmanUnit
        if let span = motionSpan,
           span.fromFrame >= 0, span.toFrame < scene.frames.count,
           let start = scene.frames[span.fromFrame].units.first(where: { $0.name == unit1.name }),
           let end = scene.frames[span.toFrame].units.first(where: { $0.name == unit1.name })
        {
            let sourcePosition = Float(originIndex) + localProgress
            let raw = (sourcePosition - Float(span.fromFrame)) / Float(span.toFrame - span.fromFrame)
            let spanProgress = min(max(raw, 0), 1)
            let eased = Easing.sample(span.easingType, t: spanProgress, strength: span.easingStrength)
            result = try inbetweenStatesAt(
                unit1: start,
                unit2: end,
                t: eased,
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                effectT: spanProgress
            )
        } else {
            result = try NlerpInterpolator.inbetween(unit1: unit1, unit2: unit2, t: CGFloat(localProgress))
        }

        if let span = colorSpan,
           span.fromFrame >= 0, span.toFrame < scene.frames.count,
           let start = scene.frames[span.fromFrame].units.first(where: { $0.name == unit1.name }),
           let end = scene.frames[span.toFrame].units.first(where: { $0.name == unit1.name })
        {
            let sourcePosition = Float(originIndex) + localProgress
            let raw = (sourcePosition - Float(span.fromFrame)) / Float(span.toFrame - span.fromFrame)
            let spanProgress = min(max(raw, 0), 1)
            let colorU = CameraMoveInterpolator.colorProgress(
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                t: spanProgress
            )
            let alphaVal = start.alpha + (end.alpha - start.alpha) * CGFloat(colorU)
            result.alpha = min(max(alphaVal, 0), 1)
            result.effect = CameraMoveInterpolator.tweenEffect(
                start.effect,
                end.effect,
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                t: spanProgress
            )
        } else if motionSpan != nil {
            let alphaVal = unit1.alpha + (unit2.alpha - unit1.alpha) * CGFloat(localProgress)
            result.alpha = min(max(alphaVal, 0), 1)
            result.effect = CameraMoveInterpolator.tweenEffect(
                unit1.effect,
                unit2.effect,
                easing: .NO,
                strength: Easing.defaultStrength,
                t: localProgress
            )
        }

        return result
    }
}
