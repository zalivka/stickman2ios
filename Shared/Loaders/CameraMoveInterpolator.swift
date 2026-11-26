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
            assertionFailure("CameraMoveInterpolator framesNumber must be > 0, got \(framesNumber)")
            return frame2.cameraMove
        }
        if step < 0 || step >= framesNumber {
            assertionFailure("CameraMoveInterpolator step \(step) out of \(framesNumber)")
            return frame2.cameraMove
        }
        let localProgress = Float(step + 1) / Float(framesNumber + 1)
        if let span = scene.cameraTweens.findMotionForSpan(from: originIndex, to: originIndex + 1),
           span.fromFrame >= 0, span.toFrame < scene.frames.count {
            let source = scene.frames[span.fromFrame].cameraMove
            let target = scene.frames[span.toFrame].cameraMove
            let spanProgress = span.progress(originIndex: originIndex, localProgress: localProgress)
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

    static func inbetweenEffect(
        scene: StickmanScene,
        originIndex: Int,
        frame1: StickmanFrame,
        frame2: StickmanFrame,
        step: Int,
        framesNumber: Int
    ) -> CameraEffect {
        if framesNumber <= 0 {
            assertionFailure("CameraMoveInterpolator framesNumber must be > 0, got \(framesNumber)")
            return frame2.cameraEffect
        }
        if step < 0 || step >= framesNumber {
            assertionFailure("CameraMoveInterpolator step \(step) out of \(framesNumber)")
            return frame2.cameraEffect
        }
        let localProgress = Float(step + 1) / Float(framesNumber + 1)
        if let span = scene.cameraTweens.findColorForSpan(from: originIndex, to: originIndex + 1),
           span.fromFrame >= 0, span.toFrame < scene.frames.count {
            let source = scene.frames[span.fromFrame].cameraEffect
            let target = scene.frames[span.toFrame].cameraEffect
            let spanProgress = span.progress(originIndex: originIndex, localProgress: localProgress)
            return tweenEffect(
                source,
                target,
                easing: span.easingType,
                strength: span.easingStrength,
                frequency: span.shakeFrequency,
                t: spanProgress
            )
        }
        return tweenEffect(
            frame1.cameraEffect,
            frame2.cameraEffect,
            easing: .NO,
            strength: Easing.defaultStrength,
            t: localProgress
        )
    }

    static func colorProgress(
        easing: TweenEasing,
        strength: Float,
        frequency: Float = UnitTweenStorage.defaultPulseFrequency,
        t: Float
    ) -> Float {
        let clampedT = min(max(t, 0), 1)
        if easing.isPulseColor {
            return Easing.pulseProgress(t: clampedT, frequency: frequency)
        }
        if easing.isShake || easing.isCartwheel || easing == .NO {
            return clampedT
        }
        return min(max(Easing.sample(easing, t: clampedT, strength: strength), 0), 1)
    }

    static func tweenEffect(
        _ source: CameraEffect,
        _ target: CameraEffect,
        easing: TweenEasing,
        strength: Float,
        frequency: Float = UnitTweenStorage.defaultPulseFrequency,
        t: Float
    ) -> CameraEffect {
        let u = colorProgress(easing: easing, strength: strength, frequency: frequency, t: t)
        if source.isZero && target.isZero {
            return .none
        }
        if source.isZero {
            return CameraEffect(
                kind: target.kind,
                colorIndex: target.colorIndex,
                snapshot: target.rgb,
                power: target.power * u
            )
        }
        if target.isZero {
            return CameraEffect(
                kind: source.kind,
                colorIndex: source.colorIndex,
                snapshot: source.rgb,
                power: source.power * (1.0 - u)
            )
        }
        // Same kind: blend power, and blend RGB channels when colors differ (e.g. black fade → white fade passes through gray).
        if source.kind == target.kind {
            if source.kind == .fade || source.kind == .colorize {
                let blendedRGB = (
                    r: source.rgb.r + (target.rgb.r - source.rgb.r) * u,
                    g: source.rgb.g + (target.rgb.g - source.rgb.g) * u,
                    b: source.rgb.b + (target.rgb.b - source.rgb.b) * u
                )
                // Keep colorIndex only when colors match exactly; otherwise mark as off-palette (-1) since it's mid-transition.
                let blendedIndex = source.rgbInt == target.rgbInt ? source.colorIndex : -1
                return CameraEffect(
                    kind: source.kind,
                    colorIndex: blendedIndex,
                    snapshot: blendedRGB,
                    power: source.power + (target.power - source.power) * u
                )
            }
            return CameraEffect(
                kind: source.kind,
                colorIndex: source.colorIndex,
                snapshot: source.rgb,
                power: source.power + (target.power - source.power) * u
            )
        }
        // Conflicting active effect kinds cannot be blended; step at midpoint during live frame-to-frame interpolation.
        return u < 0.5 ? source : target
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
