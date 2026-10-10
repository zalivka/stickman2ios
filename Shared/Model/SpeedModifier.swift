import CoreGraphics
import Foundation

struct SpeedPoint: Equatable, Codable {
    var index: Int
    var speedValue: Float
}

struct SpeedModifier: Equatable {
    static let defaultSpeed: Float = 1

    var points: [SpeedPoint] = []

    var isEmpty: Bool { points.isEmpty }

    mutating func setPoints(_ next: [SpeedPoint]) {
        points = next
    }

    mutating func resetFor(frameCount: Int) {
        if frameCount < 2 {
            points = []
            return
        }
        points = [
            SpeedPoint(index: 0, speedValue: Self.defaultSpeed),
            SpeedPoint(index: frameCount - 1, speedValue: Self.defaultSpeed)
        ]
    }

    mutating func adjustTo(frameCount: Int) {
        if frameCount < 2 {
            points = []
            return
        }
        if isEmpty {
            resetFor(frameCount: frameCount)
            return
        }
        guard let last = points.last else {
            return
        }
        let lastIndex = frameCount - 1
        if last.index > lastIndex {
            trimTo(frameCount: frameCount)
        } else if last.index < lastIndex {
            points[points.count - 1].index = lastIndex
        }
    }

    func fineSpeedValues(frameCount: Int) -> [Float] {
        let gaps = frameCount - 1
        if gaps < 1 {
            return []
        }
        if isEmpty {
            return Array(repeating: Self.defaultSpeed, count: gaps)
        }
        let fine = slice()
        if fine.count != gaps {
            // Malformed pivots (a 1-point or descending array survives decode).
            print("SpeedModifier slice produced \(fine.count) gaps for \(frameCount) frames — flat speed")
            return Array(repeating: Self.defaultSpeed, count: gaps)
        }
        return fine.map(\.speed)
    }

    func speedMod(gapIndex: Int, frameCount: Int) -> Float {
        let values = fineSpeedValues(frameCount: frameCount)
        if gapIndex < 0 || gapIndex >= values.count {
            assertionFailure("SpeedModifier gap \(gapIndex) out of \(values.count)")
            return Self.defaultSpeed
        }
        return values[gapIndex]
    }

    func copy() -> SpeedModifier {
        SpeedModifier(points: points)
    }

    static func decode(_ text: String) throws -> SpeedModifier {
        guard let data = text.data(using: .utf8) else {
            throw SceneLoadError(message: "SpeedModifier pivot_points is not UTF-8")
        }
        do {
            let points = try JSONDecoder().decode([SpeedPoint].self, from: data)
            return SpeedModifier(points: points)
        } catch {
            throw SceneLoadError(message: "SpeedModifier pivot_points JSON: \(error)")
        }
    }

    func encodeJSON() throws -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(points)
        } catch {
            throw SceneLoadError(message: "SpeedModifier encode: \(error)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SceneLoadError(message: "SpeedModifier encode is not UTF-8")
        }
        return text
    }

    static func yToSpeed(_ y: CGFloat, viewHeight: CGFloat) -> Float {
        let half = viewHeight / 2
        if half <= 0 {
            assertionFailure("SpeedModifier yToSpeed height \(viewHeight)")
            return Self.defaultSpeed
        }
        let ratio = abs((half - y) / half)
        if y < half {
            return Float(1 - 0.8 * ratio)
        }
        return Float(1 + 6 * ratio)
    }

    static func speedToY(_ speed: Float, viewHeight: CGFloat) -> CGFloat {
        let half = viewHeight / 2
        if speed <= 1 {
            return half - CGFloat((1 - speed) / 0.8) * half
        }
        return half + CGFloat((speed - 1) / 6) * half
    }

    static func speedPercent(_ speed: Float) -> Int {
        if speed <= 0 {
            assertionFailure("SpeedModifier speedPercent \(speed)")
            return 100
        }
        return Int((1 / speed * 100).rounded(.towardZero))
    }

    private mutating func trimTo(frameCount: Int) {
        let maxIndex = frameCount - 1
        var next: [SpeedPoint] = []
        for point in points {
            if point.index < maxIndex {
                next.append(point)
            } else if point.index == maxIndex {
                next.append(point)
                break
            } else {
                var clipped = point
                clipped.index = maxIndex
                next.append(clipped)
                break
            }
        }
        points = next
    }

    /// Android `slice` / `sliceSegment`. Zero-length spans are skipped — saved
    /// scenes (demo_lil_dino) keep two pivots on the same frame.
    private func slice() -> [(index: Int, speed: Float)] {
        if points.count < 2 {
            return []
        }
        var fine: [(index: Int, speed: Float)] = []
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            let length = end.index - start.index
            if length <= 0 {
                continue
            }
            let quant = (end.speedValue - start.speedValue) / Float(length)
            for k in 0..<length {
                fine.append((k, start.speedValue + quant * Float(k)))
            }
        }
        return fine
    }
}
