import Foundation

enum BackgroundInbetweener {
    static func propagate(
        scene: inout StickmanScene,
        from: Int,
        to: Int,
        bgName: String,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float
    ) {
        if from < 0 || to >= scene.frames.count || to - from < 2 {
            assertionFailure("BackgroundInbetweener range \(from)..\(to) out of \(scene.frames.count)")
            return
        }
        bakeInteriors(
            scene: &scene,
            from: from,
            to: to,
            bgName: bgName,
            easing: easing,
            strength: strength,
            shakeFrequency: shakeFrequency
        )
        scene.backgroundTweens.register(
            fromFrame: from,
            toFrame: to,
            bgName: bgName,
            easingType: easing,
            easingStrength: strength,
            shakeFrequency: shakeFrequency,
            frameCount: scene.frames.count
        )
    }

    static func bakeInteriors(
        scene: inout StickmanScene,
        from: Int,
        to: Int,
        bgName: String,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float
    ) {
        if from < 0 || to >= scene.frames.count || from >= to {
            assertionFailure("BackgroundInbetweener bake \(from)..\(to) out of \(scene.frames.count)")
            return
        }
        let source = scene.frames[from].bgMove
        let target = scene.frames[to].bgMove
        for frameIndex in from...to {
            scene.frames[frameIndex].bgName = bgName
        }
        let duration = to - from
        if duration < 2 {
            return
        }
        for step in 1..<duration {
            let t = Float(step) / Float(duration)
            scene.frames[from + step].bgMove = CameraMoveInterpolator.tween(
                source,
                target,
                easing: easing,
                strength: strength,
                frequency: shakeFrequency,
                t: t
            )
        }
    }
}
