import CoreGraphics
import UIKit

struct SceneSize: Equatable, Identifiable, Hashable {
    var id: String { "\(Int(width))x\(Int(height))-\(name)" }
    var name: String
    var width: CGFloat
    var height: CGFloat

    var dropdownTitle: String {
        "\(name) (\(Int(width)) x \(Int(height)))"
    }
}

enum SceneSizes {
    static let fps = 60
    static let customMin = 101
    static let customMax = 2999
    static let noInterpTicks = [60, 30, 20, 15, 12, 10, 6, 5, 4, 3]

    static func fullScreen() -> (CGFloat, CGFloat) {
        let bounds = UIScreen.main.bounds
        return (max(bounds.width, bounds.height), min(bounds.width, bounds.height))
    }

    static func presets() -> [SceneSize] {
        let full = fullScreen()
        return [
            SceneSize(name: "Default", width: full.0, height: full.1),
            SceneSize(name: "Small (landscape)", width: 320, height: 240),
            SceneSize(name: "Medium (landscape)", width: 480, height: 320),
            SceneSize(name: "Large (landscape)", width: 640, height: 480),
            SceneSize(name: "Full screen", width: full.0, height: full.1),
            SceneSize(name: "HD Ready", width: 1280, height: 720),
            SceneSize(name: "Portrait 9:16 HD", width: 720, height: 1280),
            SceneSize(name: "Portrait 9:16 Full HD", width: 1080, height: 1920),
            SceneSize(name: "Portrait 4:5", width: 1080, height: 1350),
            SceneSize(name: "Portrait 3:4", width: 1080, height: 1440),
        ]
    }

    static func available(currentWidth: CGFloat, currentHeight: CGFloat) -> [SceneSize] {
        var sizes = presets()
        if !sizes.contains(where: { $0.width == currentWidth && $0.height == currentHeight }) {
            sizes.append(
                SceneSize(
                    name: "\(Int(currentWidth)) x \(Int(currentHeight))",
                    width: currentWidth,
                    height: currentHeight
                )
            )
        }
        return sizes
    }

    static func speedBand(_ interframes: Int) -> String {
        switch interframes {
        case 0: return "Frame-by-frame"
        case 1...5: return "Extra Fast"
        case 6...9: return "Very Fast"
        case 10...16: return "Fast"
        case 17...24: return "Normal"
        case 25...36: return "Slow"
        default: return "Slow Motion"
        }
    }

    static func speedLabel(_ interframes: Int) -> String {
        "Animation speed: \(speedBand(interframes)) - \(interframes)"
    }

    static func noInterpPeriodMs(tick: Int) -> Int {
        if tick < 0 || tick >= noInterpTicks.count {
            fatalError("SceneSizes no-interp tick \(tick) out of 0..<\(noInterpTicks.count)")
        }
        return noInterpTicks[tick] * 1000 / fps
    }

    static func storedNoInterpFrames(tick: Int) -> Int {
        if tick < 0 || tick >= noInterpTicks.count {
            fatalError("SceneSizes no-interp tick \(tick) out of 0..<\(noInterpTicks.count)")
        }
        return noInterpTicks[tick] - 2
    }

    static func tick(storedNoInterpFrames: Int) -> Int {
        let mapped = storedNoInterpFrames + 2
        return noInterpTicks.firstIndex(of: mapped) ?? 0
    }

    static func isValidCustom(_ value: Int) -> Bool {
        value >= customMin && value <= customMax
    }
}
