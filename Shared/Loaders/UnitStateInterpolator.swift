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
            applyUnitColorTween(
                to: &pose,
                from: unit1,
                to: unit2,
                easing: easing,
                strength: strength,
                frequency: frequency,
                t: effectT
            )
        }
        return pose
    }

    static func applyUnitColorTween(
        to unit: inout StickmanUnit,
        from start: StickmanUnit,
        to end: StickmanUnit,
        easing: TweenEasing,
        strength: Float = Easing.defaultStrength,
        frequency: Float = UnitTweenStorage.defaultPulseFrequency,
        t: Float
    ) {
        let colorU = CameraMoveInterpolator.colorProgress(
            easing: easing,
            strength: strength,
            frequency: frequency,
            t: t
        )
        let alphaVal = start.alpha + (end.alpha - start.alpha) * CGFloat(colorU)
        unit.alpha = min(max(alphaVal, 0), 1)
        unit.effect = CameraMoveInterpolator.tweenEffect(
            start.effect,
            end.effect,
            easing: easing,
            strength: strength,
            frequency: frequency,
            t: t
        )
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
            let spanProgress = span.progress(originIndex: originIndex, localProgress: localProgress)
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
            let spanProgress = span.progress(originIndex: originIndex, localProgress: localProgress)
            applyUnitColorTween(
                to: &result,
                from: start,
                to: end,
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                t: spanProgress
            )
        } else if motionSpan != nil {
            applyUnitColorTween(
                to: &result,
                from: unit1,
                to: unit2,
                easing: .NO,
                t: localProgress
            )
        }

        return result
    }
}
