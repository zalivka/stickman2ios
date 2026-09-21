import Foundation

enum CameraInbetweener {
    static func propagate(
        scene: inout StickmanScene,
        from: Int,
        to: Int,
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float
    ) {
        if from < 0 || to >= scene.frames.count || to - from < 2 {
            fatalError("CameraInbetweener range \(from)..\(to) out of \(scene.frames.count)")
        }
        bakeInteriors(
            scene: &scene,
            from: from,
            to: to,
            easing: easing,
            strength: strength,
            shakeFrequency: shakeFrequency
        )
        scene.cameraTweens.register(
            fromFrame: from,
            toFrame: to,
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
        easing: TweenEasing,
        strength: Float,
        shakeFrequency: Float
    ) {
        if from < 0 || to >= scene.frames.count || from >= to {
            fatalError("CameraInbetweener bake \(from)..\(to) out of \(scene.frames.count)")
        }
        let source = scene.frames[from].cameraMove
        let target = scene.frames[to].cameraMove
        let duration = to - from
        if duration < 2 {
            return
        }
        for step in 1..<duration {
            let t = Float(step) / Float(duration)
            scene.frames[from + step].cameraMove = CameraMoveInterpolator.tween(
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
