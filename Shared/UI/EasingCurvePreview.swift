import SwiftUI

/// Android `EasingCurveView` — sampled easing path in an 80pt cell.
struct EasingCurvePreview: View {
    var easing: TweenEasing
    var strength: Float
    var frequency: Float
    var selected: Bool

    private static let samples = 64

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 8
            let radius: CGFloat = 4
            let bounds = CGRect(
                x: pad,
                y: pad,
                width: size.width - pad * 2,
                height: size.height - pad * 2
            )
            let bg = Path(roundedRect: bounds, cornerRadius: radius)
            context.fill(bg, with: .color(Color(red: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255)))
            if selected {
                context.stroke(
                    bg,
                    with: .color(Color(red: 0x4d / 255, green: 0xa3 / 255, blue: 1)),
                    lineWidth: 2
                )
            }

            let plot = bounds.insetBy(dx: 4, dy: 4)
            if plot.width <= 0 || plot.height <= 0 {
                return
            }
            var path = Path()
            if easing.isCartwheel {
                drawCartwheel(&path, plot: plot)
            } else {
                drawCurve(&path, plot: plot)
            }
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawCurve(_ path: inout Path, plot: CGRect) {
        let shakeX = easing == .SHAKE_X
        for i in 0...Self.samples {
            let t = Float(i) / Float(Self.samples)
            let value = previewValue(t)
            let x: CGFloat
            let y: CGFloat
            if shakeX {
                x = plot.minX + CGFloat(value) * plot.width
                y = plot.minY + CGFloat(t) * plot.height
            } else {
                x = plot.minX + CGFloat(t) * plot.width
                y = plot.maxY - CGFloat(value) * plot.height
            }
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    private func drawCartwheel(_ path: inout Path, plot: CGRect) {
        let cx = plot.midX
        let cy = plot.midY
        let maxR = min(plot.width, plot.height) * 0.45
        let sign: Float = easing == .CARTWHEEL_CW ? 1 : -1
        let turns = min(max(frequency, 1), 4)
        let samples = max(Self.samples, Int((turns * 48).rounded()))
        for i in 0...samples {
            let t = Float(i) / Float(samples)
            let spinT = UnitTweenEffects.cartwheelSpinProgress(t, strength)
            let angle = CGFloat(sign * 2 * Float.pi * turns * spinT)
            let r = maxR * CGFloat(0.15 + 0.85 * t)
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    private func previewValue(_ t: Float) -> Float {
        if easing.isShake {
            let centered = Float(sin(2 * Double.pi * Double(frequency) * Double(t)))
            let amplitude = 0.45 * strength
            return min(max(0.5 + centered * amplitude, 0), 1)
        }
        return Easing.sample(easing, t: t, strength: strength)
    }
}
