import SwiftUI
import UIKit

struct PreviewSeekBar: View {
    static let width: CGFloat = 56
    static let verticalPad: CGFloat = 16
    static let trackThickness: CGFloat = 4
    static let idleThumbDiameter: CGFloat = 20
    static let activeThumbDiameter: CGFloat = 26
    static let accentColor = Color(red: 0, green: 197 / 255, blue: 1)
    static let trackColor = Color.white.opacity(0.32)

    @Binding var progress: Double
    @State private var isDragging = false

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        GeometryReader { proxy in
            Canvas { context, size in
                let centerX = size.width / 2
                let topY = Self.verticalPad
                let bottomY = max(topY, size.height - Self.verticalPad)
                let thumbY = topY + CGFloat(clamped) * (bottomY - topY)

                let trackRect = CGRect(
                    x: centerX - Self.trackThickness / 2,
                    y: topY,
                    width: Self.trackThickness,
                    height: bottomY - topY
                )
                context.fill(
                    Path(roundedRect: trackRect, cornerRadius: Self.trackThickness / 2),
                    with: .color(Self.trackColor)
                )

                if thumbY > topY {
                    let filledRect = CGRect(
                        x: centerX - Self.trackThickness / 2,
                        y: topY,
                        width: Self.trackThickness,
                        height: thumbY - topY
                    )
                    context.fill(
                        Path(roundedRect: filledRect, cornerRadius: Self.trackThickness / 2),
                        with: .color(Self.accentColor)
                    )
                }

                let diameter = isDragging ? Self.activeThumbDiameter : Self.idleThumbDiameter
                let thumbRect = CGRect(
                    x: centerX - diameter / 2,
                    y: thumbY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: thumbRect), with: .color(.white))
                context.stroke(
                    Path(ellipseIn: thumbRect.insetBy(dx: 1, dy: 1)),
                    with: .color(Self.accentColor),
                    lineWidth: 3
                )
            }
            .overlay {
                PreviewSeekTouchOverlay(
                    onScrub: { y, active in
                        isDragging = active
                        seek(atY: y, height: proxy.size.height)
                    },
                    onEnd: {
                        isDragging = false
                    }
                )
            }
        }
        .frame(width: Self.width)
    }

    private func seek(atY y: CGFloat, height: CGFloat) {
        let topY = Self.verticalPad
        let span = height - 2 * Self.verticalPad
        guard span > 0 else { return }
        let ratio = Double((y - topY) / span)
        progress = min(max(ratio, 0), 1)
    }
}

private struct PreviewSeekTouchOverlay: UIViewRepresentable {
    var onScrub: (CGFloat, Bool) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePress)
        )
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onScrub = onScrub
        context.coordinator.onEnd = onEnd
    }

    final class Coordinator: NSObject {
        var onScrub: (CGFloat, Bool) -> Void = { _, _ in }
        var onEnd: () -> Void = {}

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            let y = gesture.location(in: gesture.view).y
            switch gesture.state {
            case .began, .changed:
                onScrub(y, true)
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }
    }
}

