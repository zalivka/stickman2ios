import CoreGraphics
import Foundation

enum CameraMoveInterpolator {
    static func inbetween(
        scene: StickmanScene,
        originIndex: Int,
        frame1: StickmanFrame,
        frame2: StickmanFrame,
        step: Int,
        framesNumber: Int
    ) -> PictureMove {
        if framesNumber <= 0 {
            fatalError("CameraMoveInterpolator framesNumber must be > 0, got \(framesNumber)")
        }
        if step < 0 || step >= framesNumber {
            fatalError("CameraMoveInterpolator step \(step) out of \(framesNumber)")
        }
        let localProgress = Float(step + 1) / Float(framesNumber + 1)
        if let span = scene.cameraTweens.findForSpan(from: originIndex, to: originIndex + 1) {
            let source = scene.frames[span.fromFrame].cameraMove
            let target = scene.frames[span.toFrame].cameraMove
            let sourcePosition = Float(originIndex) + localProgress
            let raw = (sourcePosition - Float(span.fromFrame)) / Float(span.toFrame - span.fromFrame)
            let spanProgress = min(max(raw, 0), 1)
            return tween(
                source,
                target,
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                t: spanProgress
            )
        }
        return tween(
            frame1.cameraMove,
            frame2.cameraMove,
            easing: .NO,
            strength: Easing.defaultStrength,
            frequency: UnitTweenStorage.defaultShakeFrequency,
            t: localProgress
        )
    }

    static func tween(
        _ source: PictureMove,
        _ target: PictureMove,
        easing: TweenEasing,
        strength: Float,
        frequency: Float,
        t: Float
    ) -> PictureMove {
        if easing == .SHAKE_X {
            return shakeTween(source, target, strength: strength, frequency: frequency, t: t, onX: true)
        }
        if easing == .SHAKE_Y {
            return shakeTween(source, target, strength: strength, frequency: frequency, t: t, onX: false)
        }
        if easing.isCartwheel {
            return cartwheelTween(source, target, strength: strength, turns: frequency, t: t, clockwise: easing == .CARTWHEEL_CW)
        }
        let progress = CGFloat(Easing.sample(easing, t: t, strength: strength))
        return PictureMove(
            scale: source.scale + (target.scale - source.scale) * progress,
            rotate: source.rotate + (target.rotate - source.rotate) * progress,
            x: source.x + (target.x - source.x) * progress,
            y: source.y + (target.y - source.y) * progress
        )
    }

    private static func shakeTween(
        _ source: PictureMove,
        _ target: PictureMove,
        strength: Float,
        frequency: Float,
        t: Float,
        onX: Bool
    ) -> PictureMove {
        let progress = CGFloat(t)
        let baselineX = source.x + (target.x - source.x) * progress
        let baselineY = source.y + (target.y - source.y) * progress
        let travel = onX ? Float(abs(target.x - source.x)) : Float(abs(target.y - source.y))
        let offset = CGFloat(UnitTweenEffects.computeShakeOffset(
            travel: travel,
            strength: strength,
            frequency: frequency,
            t: t
        ))
        return PictureMove(
            scale: source.scale + (target.scale - source.scale) * progress,
            rotate: source.rotate + (target.rotate - source.rotate) * progress,
            x: onX ? baselineX + offset : baselineX,
            y: onX ? baselineY : baselineY + offset
        )
    }

    private static func cartwheelTween(
        _ source: PictureMove,
        _ target: PictureMove,
        strength: Float,
        turns: Float,
        t: Float,
        clockwise: Bool
    ) -> PictureMove {
        let progress = CGFloat(t)
        let spinT = UnitTweenEffects.cartwheelSpinProgress(t, strength)
        let sign: Float = clockwise ? 1 : -1
        let extra = CGFloat(sign * 360 * UnitTweenStorage.clampFrequency(.CARTWHEEL_CW, turns) * spinT)
        return PictureMove(
            scale: source.scale + (target.scale - source.scale) * progress,
            rotate: source.rotate + (target.rotate - source.rotate) * progress + extra,
            x: source.x + (target.x - source.x) * progress,
            y: source.y + (target.y - source.y) * progress
        )
    }
}
