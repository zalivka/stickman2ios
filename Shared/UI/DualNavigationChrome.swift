import SwiftUI
import UIKit

struct DualNavigationChrome: View {
    let frameCount: Int
    @Binding var currentIndex: Int
    @Binding var range: ClosedRange<Int>
    @Binding var mode: DualNavigation.Mode

    @State private var barHeight: CGFloat = 0

    var body: some View {
        Group {
            switch mode {
            case .frames:
                framesColumn
            case .range:
                VerticalRangeBar(
                    frameCount: frameCount,
                    currentIndex: $currentIndex,
                    range: $range,
                    onDoubleTap: enterFrames
                )
                .frame(maxHeight: .infinity)
            }
        }
        .onPreferenceChange(SeekFramesBarHeightKey.self) { barHeight = $0 }
    }

    private var windowSize: Int {
        SeekFramesBar.windowSize(height: barHeight)
    }

    private var framesColumn: some View {
        VStack(spacing: 0) {
            navButton(idle: Self.prevIdle, pressed: Self.prevPressed) {
                currentIndex = max(0, currentIndex - 1)
            } longPress: {
                currentIndex = SeekFramesBar.prevPage(
                    current: currentIndex,
                    windowSize: windowSize
                )
            }

            SeekFramesBar(
                frameCount: frameCount,
                currentIndex: $currentIndex,
                onDoubleTap: enterRange
            )
            .frame(maxHeight: .infinity)

            navButton(idle: Self.nextIdle, pressed: Self.nextPressed) {
                currentIndex = min(frameCount - 1, currentIndex + 1)
            } longPress: {
                currentIndex = SeekFramesBar.nextPage(
                    current: currentIndex,
                    frameCount: frameCount,
                    windowSize: windowSize
                )
            }
        }
        .frame(width: SeekFramesBar.barWidth)
        .background(Color.clear)
    }

    private func enterRange() {
        range = DualNavigation.defaultRange(current: currentIndex, frameCount: frameCount)
        mode = .range
    }

    private func enterFrames() {
        mode = .frames
    }

    private func navButton(idle: CGImage, pressed: CGImage, tap: @escaping () -> Void, longPress: @escaping () -> Void) -> some View {
        FrameNavButton(idle: idle, pressed: pressed, tap: tap, longPress: longPress)
    }

    private static let prevIdle = chromeImage("main_prev_frame_np")
    private static let prevPressed = chromeImage("main_prev_frame_pr")
    private static let nextIdle = chromeImage("main_next_frame_np")
    private static let nextPressed = chromeImage("main_next_frame_pr")

    private static func chromeImage(_ name: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("DualNavigationChrome missing chrome/\(name).png")
        }
        do {
            let data = try Data(contentsOf: url)
            return PNGImage.cgImage(from: data, name: "chrome/\(name).png")
        } catch {
            fatalError("DualNavigationChrome could not read \(url.path): \(error)")
        }
    }
}

private struct FrameNavButton: View {
    let idle: CGImage
    let pressed: CGImage
    var tap: () -> Void
    var longPress: () -> Void

    var body: some View {
        FrameNavUIButton(idle: idle, pressed: pressed, tap: tap, longPress: longPress)
            .frame(width: Self.artwork + 16, height: Self.artwork + 16)
            .clipped()
            .accessibilityAddTraits(.isButton)
    }

    static let artwork = SeekFramesBar.barWidth / 1.5
}

/// Android `ImageButton` next/prev: click and long-click must not share a SwiftUI gesture.
private struct FrameNavUIButton: UIViewRepresentable {
    let idle: CGImage
    let pressed: CGImage
    var tap: () -> Void
    var longPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.adjustsImageWhenHighlighted = false
        button.clipsToBounds = true
        button.imageView?.contentMode = .scaleAspectFit
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.35
        button.addGestureRecognizer(hold)
        apply(button, context: context)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        apply(button, context: context)
    }

    private func apply(_ button: UIButton, context: Context) {
        context.coordinator.tap = tap
        context.coordinator.longPress = longPress
        let side = FrameNavButton.artwork
        let idleImage = UIImage(cgImage: idle, scale: CGFloat(idle.width) / side, orientation: .up)
        let pressedImage = UIImage(cgImage: pressed, scale: CGFloat(pressed.width) / side, orientation: .up)
        button.setImage(idleImage, for: .normal)
        button.setImage(pressedImage, for: .highlighted)
        button.setImage(pressedImage, for: [.highlighted, .focused])
    }

    final class Coordinator: NSObject {
        var tap: () -> Void = {}
        var longPress: () -> Void = {}
        private var consumedByHold = false

        @objc func tapped() {
            if consumedByHold {
                consumedByHold = false
                return
            }
            tap()
        }

        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                consumedByHold = true
                longPress()
            case .cancelled, .failed:
                consumedByHold = false
            default:
                break
            }
        }
    }
}
