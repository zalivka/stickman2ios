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
    ) -> StickmanUnit {
        var pose = NlerpInterpolator.inbetween(unit1: unit1, unit2: unit2, t: CGFloat(t))
        UnitTweenEffects.apply(
            &pose,
            start: unit1,
            end: unit2,
            easing: easing,
            strength: strength,
            frequency: frequency,
            t: effectT
        )
        return pose
    }

    static func inbetween(
        scene: StickmanScene,
        originIndex: Int,
        unit1: StickmanUnit,
        unit2: StickmanUnit,
        step: Int,
        framesNumber: Int
    ) -> StickmanUnit {
        if framesNumber <= 0 {
            fatalError("UnitStateInterpolator framesNumber must be > 0, got \(framesNumber)")
        }
        if step < 0 || step >= framesNumber {
            fatalError("UnitStateInterpolator step \(step) out of \(framesNumber)")
        }
        let localProgress = Float(step + 1) / Float(framesNumber + 1)
        if let span = scene.unitTweens.findForSpan(
            unitName: unit1.name,
            from: originIndex,
            to: originIndex + 1
        ) {
            if let start = scene.frames[span.fromFrame].units.first(where: { $0.name == unit1.name }),
               let end = scene.frames[span.toFrame].units.first(where: { $0.name == unit1.name })
            {
                let sourcePosition = Float(originIndex) + localProgress
                let raw = (sourcePosition - Float(span.fromFrame)) / Float(span.toFrame - span.fromFrame)
                let spanProgress = min(max(raw, 0), 1)
                let eased = Easing.sample(span.easingType, t: spanProgress, strength: span.easingStrength)
                return inbetweenStatesAt(
                    unit1: start,
                    unit2: end,
                    t: eased,
                    easing: span.easingType,
                    strength: span.easingStrength,
                    frequency: span.shakeFrequency,
                    effectT: spanProgress
                )
            }
        }
        return NlerpInterpolator.inbetween(unit1: unit1, unit2: unit2, t: CGFloat(localProgress))
    }
}
