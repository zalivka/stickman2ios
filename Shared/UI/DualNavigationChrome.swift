import SwiftUI

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
            navButton(systemName: "chevron.up") {
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

            navButton(systemName: "chevron.down") {
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
    }

    private func enterRange() {
        range = DualNavigation.defaultRange(current: currentIndex, frameCount: frameCount)
        mode = .range
    }

    private func enterFrames() {
        mode = .frames
    }

    private func navButton(systemName: String, tap: @escaping () -> Void, longPress: @escaping () -> Void) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: SeekFramesBar.barWidth, height: SeekFramesBar.barWidth)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .onLongPressGesture(perform: longPress)
    }
}
