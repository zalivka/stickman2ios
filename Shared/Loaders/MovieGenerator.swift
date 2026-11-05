import Foundation

enum MovieGenerator {
    private static let queue = DispatchQueue(label: "movie.generate")

    static func generate(
        scene: StickmanScene,
        assets: UnitAssets,
        progress: @escaping (Int) -> Void,
        failure: @escaping (Error) -> Void,
        completion: @escaping (StickmanScene) -> Void
    ) {
        if scene.frames.count < 2 {
            failure(SceneLoadError(message: "MovieGenerator needs at least 2 keyframes, got \(scene.frames.count)"))
            return
        }
        var stateLists: [String: [Int]] = [:]
        for name in scene.unitAnimations.keys {
            stateLists[name] = assets.states(for: name)
        }
        queue.async {
            var movieFrames: [StickmanFrame] = []
            do {
                _ = try streamFrames(
                    scene: scene,
                    stateLists: stateLists,
                    onFrame: { frame, _ in
                        movieFrames.append(frame)
                    },
                    onSpanProgress: { spanIndex, gaps in
                        let percent = min(max((spanIndex + 1) * 100 / gaps, 0), 100)
                        DispatchQueue.main.async {
                            progress(percent)
                        }
                    }
                )
            } catch {
                DispatchQueue.main.async {
                    failure(error)
                }
                return
            }
            var movie = scene
            movie.frames = movieFrames
            movie.currentIndex = 0
            DispatchQueue.main.async {
                completion(movie)
            }
        }
    }

    /// Streams interpolated frames one span at a time (`ThriftMovieGeneratorUseCase.generate`),
    /// stamping `originFrameIndex`, `id`, and FBF animations in flight so callers such as
    /// `JpegSequenceWriter` never accumulate the full movie in memory.
    @discardableResult
    static func streamFrames(
        scene: StickmanScene,
        stateLists: [String: [Int]],
        onFrame: (StickmanFrame, Int) throws -> Void,
        onSpanProgress: (Int, Int) throws -> Void = { _, _ in }
    ) throws -> Int {
        if scene.frames.count < 2 {
            throw SceneLoadError(message: "MovieGenerator needs at least 2 keyframes, got \(scene.frames.count)")
        }
        let base = scene.noInterpolation
            ? max(scene.noInterpolationFrames, 1)
            : max(scene.interframes, 1)
        let gaps = scene.frames.count - 1
        var fbfState = OngoingAnimations.State()
        var genIndex = 0
        for index in 0..<gaps {
            let speed = scene.speedModifier.speedMod(gapIndex: index, frameCount: scene.frames.count)
            let duration = max(1, Int(Float(base) * speed))
            let generated = scene.noInterpolation
                ? NullInterpolator.interpolate(
                    from: scene.frames[index],
                    to: scene.frames[index + 1],
                    duration: duration
                )
                : try NlerpInterpolator.interpolate(
                    from: scene.frames[index],
                    to: scene.frames[index + 1],
                    duration: duration,
                    scene: scene,
                    originIndex: index
                )
            for var frame in generated {
                frame.originFrameIndex = index
                OngoingAnimations.apply(
                    source: scene,
                    frame: &frame,
                    stateLists: stateLists,
                    state: &fbfState
                )
                frame.id = genIndex
                try onFrame(frame, genIndex)
                genIndex += 1
            }
            try onSpanProgress(index, gaps)
        }
        return genIndex
    }
}
