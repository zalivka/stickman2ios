import Foundation

enum TweenEasing: String, Codable, CaseIterable {
    case NO
    case BOUNCE_OUT
    case BOUNCE_IN
    case IN_OUT_EXPO
    case IN_OUT_BACK
    case IN_QUINT
    case OUT_QUINT
    case SHAKE_X
    case SHAKE_Y
    case CARTWHEEL_CW
    case CARTWHEEL_CCW

    var isShake: Bool { self == .SHAKE_X || self == .SHAKE_Y }
    var isCartwheel: Bool { self == .CARTWHEEL_CW || self == .CARTWHEEL_CCW }

    var label: String {
        switch self {
        case .NO: return "Linear"
        case .BOUNCE_OUT: return "Bounce out"
        case .BOUNCE_IN: return "Bounce in"
        case .IN_OUT_EXPO: return "In-out expo"
        case .IN_OUT_BACK: return "In-out back"
        case .IN_QUINT: return "In quint"
        case .OUT_QUINT: return "Out quint"
        case .SHAKE_X: return "Shake X"
        case .SHAKE_Y: return "Shake Y"
        case .CARTWHEEL_CW: return "Cartwheel CW"
        case .CARTWHEEL_CCW: return "Cartwheel CCW"
        }
    }
}

enum Easing {
    static let defaultStrength: Float = 0.5

    static func sample(_ type: TweenEasing, t: Float, strength: Float) -> Float {
        if t < 0 || t > 1 {
            fatalError("Easing sample t \(t)")
        }
        let s = clamp01(strength)
        switch type {
        case .NO, .SHAKE_X, .SHAKE_Y, .CARTWHEEL_CW, .CARTWHEEL_CCW:
            return t
        case .BOUNCE_OUT:
            return lerp(t, easeOutBounce(t), s)
        case .BOUNCE_IN:
            return lerp(t, easeInBounce(t), s)
        case .IN_OUT_EXPO:
            return lerp(t, easeInOutExpo(t), s)
        case .IN_OUT_BACK:
            return lerp(t, easeInOutBack(t, magnitude: 1.70158), s)
        case .IN_QUINT:
            return lerp(t, easeInQuint(t), s)
        case .OUT_QUINT:
            return lerp(t, easeOutQuint(t), s)
        }
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func lerp(_ from: Float, _ to: Float, _ t: Float) -> Float {
        from + (to - from) * t
    }

    private static func easeOutBounce(_ t: Float) -> Float {
        let n1: Float = 7.5625
        let d1: Float = 2.75
        if t < 1 / d1 {
            return n1 * t * t
        }
        if t < 2 / d1 {
            let v = t - 1.5 / d1
            return n1 * v * v + 0.75
        }
        if t < 2.5 / d1 {
            let v = t - 2.25 / d1
            return n1 * v * v + 0.9375
        }
        let v = t - 2.625 / d1
        return n1 * v * v + 0.984375
    }

    private static func easeInBounce(_ t: Float) -> Float {
        1 - easeOutBounce(1 - t)
    }

    private static func easeInOutExpo(_ t: Float) -> Float {
        if t == 0 || t == 1 {
            return t
        }
        let scaled = t * 2
        let scaled1 = scaled - 1
        if scaled < 1 {
            return 0.5 * Float(pow(2.0, Double(10 * scaled1)))
        }
        return 0.5 * Float(-(pow(2.0, Double(-10 * scaled1))) + 2)
    }

    private static func easeInOutBack(_ t: Float, magnitude: Float) -> Float {
        let scaled = t * 2
        let scaled2 = scaled - 2
        let s = magnitude * 1.525
        if scaled < 1 {
            return 0.5 * scaled * scaled * ((s + 1) * scaled - s)
        }
        return 0.5 * (scaled2 * scaled2 * ((s + 1) * scaled2 + s) + 2)
    }

    private static func easeInQuint(_ t: Float) -> Float {
        t * t * t * t * t
    }

    private static func easeOutQuint(_ t: Float) -> Float {
        let t1 = t - 1
        return 1 + t1 * t1 * t1 * t1 * t1
    }
}
