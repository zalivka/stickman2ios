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

    @State private var isPressed = false

    var body: some View {
        Image(decorative: isPressed ? pressed : idle, scale: UIScreen.main.scale)
            .resizable()
            .scaledToFit()
            .frame(width: SeekFramesBar.barWidth / 1.5, height: SeekFramesBar.barWidth / 1.5)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.35, pressing: { isPressed = $0 }, perform: longPress)
            .padding(8)
    }
}
