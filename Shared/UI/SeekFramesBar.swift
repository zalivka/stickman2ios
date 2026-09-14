import SwiftUI
import UIKit

struct SeekFramesBar: View {
    static let barWidth: CGFloat = 60
    static let framesDistance: CGFloat = 12
    static let verticalPad: CGFloat = 5
    static let idleDiameter: CGFloat = 8
    static let currentDiameter: CGFloat = 13
    static let idleColor = Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255)
    static let currentColor = Color(red: 0, green: 0x82 / 255, blue: 1)

    let frameCount: Int
    @Binding var currentIndex: Int
    var onDoubleTap: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let layout = Self.layout(frameCount: frameCount, currentIndex: currentIndex, height: size.height)

                for index in layout.visible {
                    let stickY = Self.stickY(index: index, windowSize: layout.windowSize)
                    let isCurrent = index == currentIndex
                    let diameter = isCurrent ? Self.currentDiameter : Self.idleDiameter
                    let idleCenterX = Self.horizontalPad + Self.idleDiameter / 2
                    let idleCenterY = stickY + Self.idleDiameter / 2
                    let rect = CGRect(
                        x: idleCenterX - diameter / 2,
                        y: idleCenterY - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(isCurrent ? Self.currentColor : Self.idleColor)
                    )
                }

                let firstVisible = layout.visible.first!
                let lastVisible = layout.visible.last!

                context.draw(
                    Text("\(currentIndex + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black),
                    at: CGPoint(x: 5, y: size.height / 2),
                    anchor: .leading
                )
                context.draw(
                    Text("\(firstVisible + 1)")
                        .font(.system(size: 10))
                        .foregroundColor(.black.opacity(0.5)),
                    at: CGPoint(x: 10, y: 10),
                    anchor: UnitPoint(x: 0, y: 1)
                )
                context.draw(
                    Text("\(lastVisible + 1)")
                        .font(.system(size: 10))
                        .foregroundColor(.black.opacity(0.5)),
                    at: CGPoint(x: 10, y: size.height - 10),
                    anchor: UnitPoint(x: 0, y: 0)
                )
            }
            .overlay {
                FramesBarTouchOverlay(
                    onSelectY: { selectNearest(atY: $0, height: proxy.size.height) },
                    onDoubleTap: onDoubleTap
                )
            }
            .preference(key: SeekFramesBarHeightKey.self, value: proxy.size.height)
        }
        .frame(width: Self.barWidth)
        .background(Color.clear)
    }

    private func selectNearest(atY y: CGFloat, height: CGFloat) {
        let layout = Self.layout(frameCount: frameCount, currentIndex: currentIndex, height: height)
        if let nearest = Self.nearestIndex(atY: y, visible: layout.visible, windowSize: layout.windowSize) {
            currentIndex = nearest
        }
    }

    static var horizontalPad: CGFloat {
        (barWidth - idleDiameter) / 2
    }

    static func windowSize(height: CGFloat) -> Int {
        max(Int((height - 2 * verticalPad) / framesDistance), 1)
    }

    static func stickY(index: Int, windowSize: Int) -> CGFloat {
        verticalPad + CGFloat(index % windowSize) * framesDistance
    }

    static func nearestIndex(atY y: CGFloat, visible: Range<Int>, windowSize: Int) -> Int? {
        var nearest = -1
        var minDiff = CGFloat.greatestFiniteMagnitude
        for index in visible {
            let centerY = stickY(index: index, windowSize: windowSize) + idleDiameter / 2
            let diff = abs(centerY - y)
            if diff < minDiff {
                minDiff = diff
                nearest = index
            }
        }
        return nearest < 0 ? nil : nearest
    }

    static func nextPage(current: Int, frameCount: Int, windowSize: Int) -> Int {
        let windowIndex = current / windowSize
        let lastWindow = (frameCount - 1) / windowSize
        if windowIndex == lastWindow {
            return frameCount - 1
        }
        return (windowIndex + 1) * windowSize
    }

    static func prevPage(current: Int, windowSize: Int) -> Int {
        let windowIndex = current / windowSize
        if windowIndex == 0 {
            return 0
        }
        return (windowIndex - 1) * windowSize
    }

    private static func layout(frameCount: Int, currentIndex: Int, height: CGFloat) -> (windowSize: Int, visible: Range<Int>) {
        if frameCount < 1 {
            fatalError("SeekFramesBar frameCount must be >= 1, got \(frameCount)")
        }
        if currentIndex < 0 || currentIndex >= frameCount {
            fatalError("SeekFramesBar currentIndex \(currentIndex) out of range 0..<\(frameCount)")
        }
        let windowSize = windowSize(height: height)
        let windowStart = (currentIndex / windowSize) * windowSize
        let windowEnd = min(windowStart + windowSize, frameCount)
        return (windowSize, windowStart..<windowEnd)
    }
}

struct SeekFramesBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FramesBarTouchOverlay: UIViewRepresentable {
    var onSelectY: (CGFloat) -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onSelectY = onSelectY
        context.coordinator.onDoubleTap = onDoubleTap
    }

    final class Coordinator: NSObject {
        var onSelectY: (CGFloat) -> Void = { _ in }
        var onDoubleTap: () -> Void = {}
        private var startY: CGFloat = 0
        private var lastTapTime: TimeInterval = 0

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            let y = gesture.location(in: gesture.view).y
            switch gesture.state {
            case .began:
                startY = y
                onSelectY(y)
            case .changed:
                onSelectY(y)
            case .ended:
                let now = CACurrentMediaTime()
                if abs(y - startY) < 12, now - lastTapTime < 0.35 {
                    lastTapTime = 0
                    onDoubleTap()
                } else if abs(y - startY) < 12 {
                    lastTapTime = now
                } else {
                    lastTapTime = 0
                }
            default:
                lastTapTime = 0
            }
        }
    }
}

#Preview {
    StatefulPreview()
}

private struct StatefulPreview: View {
    @State private var currentIndex = 0

    var body: some View {
        SeekFramesBar(frameCount: 100, currentIndex: $currentIndex)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.92))
    }
}
