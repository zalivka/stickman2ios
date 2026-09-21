import CoreGraphics
import Foundation

enum UnitTweenEffects {
    private static let shakeBaseAmplitude: Float = 12
    private static let shakeDynamicFactor: Float = 0.15
    private static let shakeAmplitudeScale: Float = 1.5

    static func apply(
        _ unit: inout StickmanUnit,
        start: StickmanUnit,
        end: StickmanUnit,
        easing: TweenEasing,
        strength: Float,
        frequency: Float,
        t: Float
    ) {
        applyShake(
            &unit,
            start: start,
            end: end,
            easing: easing,
            strength: strength,
            frequency: frequency,
            t: t
        )
        applyCartwheel(&unit, easing: easing, strength: strength, turns: frequency, t: t)
    }

    static func applyShake(
        _ unit: inout StickmanUnit,
        start: StickmanUnit,
        end: StickmanUnit,
        easing: TweenEasing,
        strength: Float,
        frequency: Float,
        t: Float
    ) {
        if !easing.isShake {
            return
        }
        let onX = easing == .SHAKE_X
        let startBase = start.basePoint()
        let endBase = end.basePoint()
        let travel = onX
            ? Float(abs(endBase.x - startBase.x))
            : Float(abs(endBase.y - startBase.y))
        let offset = computeShakeOffset(
            travel: travel,
            strength: strength,
            frequency: frequency,
            t: t
        )
        unit.translateAll(
            dx: onX ? CGFloat(offset) : 0,
            dy: onX ? 0 : CGFloat(offset)
        )
    }

    static func applyCartwheel(
        _ unit: inout StickmanUnit,
        easing: TweenEasing,
        strength: Float,
        turns: Float,
        t: Float
    ) {
        if !easing.isCartwheel {
            return
        }
        let sign: Float = easing == .CARTWHEEL_CW ? 1 : -1
        let spinT = cartwheelSpinProgress(t, strength)
        let degrees = sign * 360 * UnitTweenStorage.clampFrequency(easing, turns) * spinT
        let base = unit.basePoint()
        unit.rotate(radians: CGFloat(degrees) * .pi / 180, pivotX: base.x, pivotY: base.y)
    }

    static func computeShakeOffset(travel: Float, strength: Float, frequency: Float, t: Float) -> Float {
        let s = min(max(strength, 0), 1)
        let baseAmplitude = max(shakeBaseAmplitude, travel * shakeDynamicFactor)
        return Float(sin(2 * Double.pi * Double(frequency) * Double(t)))
            * baseAmplitude * s * shakeAmplitudeScale
    }

    static func cartwheelSpinProgress(_ t: Float, _ easeStrength: Float) -> Float {
        let s = min(max(easeStrength, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return t + (eased - t) * s
    }
}
