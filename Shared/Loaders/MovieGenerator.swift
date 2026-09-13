import Foundation

enum MovieGenerator {
    private static let queue = DispatchQueue(label: "movie.generate")

    static func generate(
        scene: StickmanScene,
        progress: @escaping (Int) -> Void,
        completion: @escaping (StickmanScene) -> Void
    ) {
        if scene.frames.count < 2 {
            fatalError("MovieGenerator needs at least 2 keyframes, got \(scene.frames.count)")
        }
        if scene.interframes < 1 {
            fatalError("MovieGenerator interframes is \(scene.interframes)")
        }
        queue.async {
            let duration = scene.interframes
            let gaps = scene.frames.count - 1
            var movieFrames: [StickmanFrame] = []
            for index in 0..<gaps {
                let generated = NlerpInterpolator.interpolate(
                    from: scene.frames[index],
                    to: scene.frames[index + 1],
                    duration: duration
                )
                movieFrames.append(contentsOf: generated)
                let percent = min(max((index + 1) * 100 / gaps, 0), 100)
                DispatchQueue.main.async {
                    progress(percent)
                }
            }
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
