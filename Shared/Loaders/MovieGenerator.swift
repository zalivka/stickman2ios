import Foundation

enum MovieGenerator {
    private static let queue = DispatchQueue(label: "movie.generate")

    static func generate(
        scene: StickmanScene,
        assets: UnitAssets,
        progress: @escaping (Int) -> Void,
        completion: @escaping (StickmanScene) -> Void
    ) {
        if scene.frames.count < 2 {
            fatalError("MovieGenerator needs at least 2 keyframes, got \(scene.frames.count)")
        }
        var stateLists: [String: [Int]] = [:]
        for name in scene.unitAnimations.keys {
            stateLists[name] = assets.states(for: name)
        }
        queue.async {
            let duration = scene.noInterpolation
                ? max(scene.noInterpolationFrames, 1)
                : max(scene.interframes, 1)
            let gaps = scene.frames.count - 1
            var movieFrames: [StickmanFrame] = []
            for index in 0..<gaps {
                var generated = scene.noInterpolation
                    ? NullInterpolator.interpolate(
                        from: scene.frames[index],
                        to: scene.frames[index + 1],
                        duration: duration
                    )
                    : NlerpInterpolator.interpolate(
                        from: scene.frames[index],
                        to: scene.frames[index + 1],
                        duration: duration
                    )
                for i in generated.indices {
                    generated[i].originFrameIndex = index
                }
                movieFrames.append(contentsOf: generated)
                let percent = min(max((index + 1) * 100 / gaps, 0), 100)
                DispatchQueue.main.async {
                    progress(percent)
                }
            }
            OngoingAnimations.apply(source: scene, frames: &movieFrames, stateLists: stateLists)
            var movie = scene
            movie.frames = movieFrames.enumerated().map { offset, frame in
                var copy = frame
                copy.id = offset
                return copy
            }
            movie.currentIndex = 0
            DispatchQueue.main.async {
                completion(movie)
            }
        }
    }
}
