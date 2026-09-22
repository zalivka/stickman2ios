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
    var flashToken: Int = 0
    var pageWindow: SeekFramesPageWindow? = nil
    var stickStyle: ((Int) -> (color: Color?, scale: CGFloat))? = nil

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let layout = Self.layout(frameCount: frameCount, currentIndex: currentIndex, height: size.height)

                for index in layout.visible {
                    let stickY = Self.stickY(index: index, windowSize: layout.windowSize)
                    let isCurrent = index == currentIndex
                    let style = stickStyle?(index)
                    let requestedScale = style?.scale ?? 1
                    let scale = isCurrent && requestedScale > 1 ? 1 : requestedScale
                    let diameter = (isCurrent ? Self.currentDiameter : Self.idleDiameter) * scale
                    let idleCenterX = Self.horizontalPad + Self.idleDiameter / 2
                    let idleCenterY = stickY + Self.idleDiameter / 2
                    let rect = CGRect(
                        x: idleCenterX - diameter / 2,
                        y: idleCenterY - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    let color: Color
                    if let tint = style?.color {
                        color = tint
                    } else {
                        color = isCurrent ? Self.currentColor : Self.idleColor
                    }
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color)
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
            .overlay {
                FrameInsertFlash(
                    token: flashToken,
                    currentIndex: currentIndex,
                    windowSize: Self.windowSize(height: proxy.size.height)
                )
            }
            .onChange(of: proxy.size.height, initial: true) { _, height in
                pageWindow?.size = Self.windowSize(height: height)
            }
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
        if windowSize < 1 {
            fatalError("SeekFramesBar nextPage windowSize \(windowSize)")
        }
        if frameCount < 1 {
            fatalError("SeekFramesBar nextPage frameCount \(frameCount)")
        }
        if current < 0 || current >= frameCount {
            fatalError("SeekFramesBar nextPage current \(current) out of \(frameCount)")
        }
        let nextStart = (current / windowSize + 1) * windowSize
        if nextStart >= frameCount {
            return frameCount - 1
        }
        return nextStart
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

/// Android `SeekFramesBar.WINDOW_SIZE` after `onLayout`. Buttons read this at press time.
final class SeekFramesPageWindow {
    var size = 1
}

/// Android `ScreenFlash.TYPE.BLUE` at the active seek-bar dot after a new frame.
private struct FrameInsertFlash: View {
    let token: Int
    let currentIndex: Int
    let windowSize: Int

    @State private var progress: CGFloat = 1
    @State private var active = false

    var body: some View {
        let center = CGPoint(
            x: SeekFramesBar.horizontalPad + SeekFramesBar.idleDiameter / 2,
            y: SeekFramesBar.stickY(index: currentIndex, windowSize: windowSize)
                + SeekFramesBar.idleDiameter / 2
        )
        Circle()
            .stroke(Color(red: 0x91 / 255, green: 0xcb / 255, blue: 1), lineWidth: 2.5)
            .frame(width: diameter, height: diameter)
            .opacity(active ? Double(progress) : 0)
            .position(center)
            .allowsHitTesting(false)
            .animation(nil, value: currentIndex)
            .onChange(of: token) { _, newToken in
                if newToken <= 0 {
                    return
                }
                active = true
                progress = 0
                withAnimation(.easeIn(duration: 0.5)) {
                    progress = 1
                } completion: {
                    active = false
                }
            }
    }

    private var diameter: CGFloat {
        36 - 28 * progress
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
