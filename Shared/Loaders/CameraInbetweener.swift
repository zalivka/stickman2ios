import Foundation

enum CameraInbetweener {
    /// Returns a clear user-facing blocking message when the camera span cannot be tweened, or `nil` when valid.
    static func rangeWarning(
        scene: StickmanScene,
        from: Int,
        to: Int,
        channel: TweenChannel = .both
    ) -> String? {
        guard from >= 0, to < scene.frames.count, from < to else {
            return nil
        }
        if channel.includesColor && !endpointEffectsCompatible(scene: scene, from: from, to: to) {
            return "Color effects are different (e.g. Fade vs Tint)"
        }
        return nil
    }

    static func endpointEffectsCompatible(scene: StickmanScene, from: Int, to: Int) -> Bool {
        guard from >= 0, to < scene.frames.count, from <= to else {
            return true
        }
        return scene.frames[from].cameraEffect.canTween(with: scene.frames[to].cameraEffect)
    }

    static func propagate(
        scene: inout StickmanScene,
        from: Int,
        to: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float,
        channel: TweenChannel = .both
    ) {
        if from < 0 || to >= scene.frames.count || to - from < 2 {
            assertionFailure("CameraInbetweener range \(from)..\(to) out of \(scene.frames.count)")
            return
        }
        if channel.includesColor && !endpointEffectsCompatible(scene: scene, from: from, to: to) {
            return
        }
        bakeInteriors(
            scene: &scene,
            from: from,
            to: to,
            easing: easing,
            strength: strength,
            shakeFrequency: shakeFrequency,
            channel: channel
        )
        scene.cameraTweens.register(
            fromFrame: from,
            toFrame: to,
            easingType: easing,
            easingStrength: strength,
            shakeFrequency: shakeFrequency,
            channel: channel,
            frameCount: scene.frames.count
        )
    }

    static func bakeInteriors(
        scene: inout StickmanScene,
        from: Int,
        to: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float,
        channel: TweenChannel = .both
    ) {
        if from < 0 || to >= scene.frames.count || from >= to {
            assertionFailure("CameraInbetweener bake \(from)..\(to) out of \(scene.frames.count)")
            return
        }
        let source = scene.frames[from].cameraMove
        let target = scene.frames[to].cameraMove
        let sourceEffect = scene.frames[from].cameraEffect
        let targetEffect = scene.frames[to].cameraEffect
        let duration = to - from
        if duration < 2 {
            return
        }
        for step in 1..<duration {
            let t = Float(step) / Float(duration)
            if channel.includesMotion {
                scene.frames[from + step].cameraMove = CameraMoveInterpolator.tween(
                    source,
                    target,
                    easing: easing,
                    strength: strength,
                    frequency: shakeFrequency,
                    t: t
                )
            }
            if channel.includesColor {
                scene.frames[from + step].cameraEffect = CameraMoveInterpolator.tweenEffect(
                    sourceEffect,
                    targetEffect,
                    easing: easing,
                    strength: strength,
                    frequency: shakeFrequency,
                    t: t
                )
            }
        }
    }
}
