import Foundation

enum NullInterpolator {
    static func interpolate(from frame1: StickmanFrame, to frame2: StickmanFrame, duration: Int) -> [StickmanFrame] {
        if duration <= 0 {
            fatalError("NullInterpolator duration must be > 0, got \(duration)")
        }
        var frames: [StickmanFrame] = []
        frames.reserveCapacity(duration + 1)
        for _ in 0..<duration {
            frames.append(frame1)
        }
        frames.append(frame2)
        return frames
    }
}
