import SwiftUI
import UIKit

struct VerticalRangeBar: View {
    enum Axis {
        case vertical
        case horizontal
    }

    enum PinMapping {
        case inverted
        case identity
    }

    static let barWidth: CGFloat = 84
    static let horizontalHeight: CGFloat = 80
    static let tickHeight: CGFloat = 4
    static let pinRadius: CGFloat = 17
    static let circleRadius: CGFloat = 9
    static let strokeWidth: CGFloat = 2
    static let targetRadius: CGFloat = 44
    static let bubbleOffset: CGFloat = 28
    static let selectedTickThickness: CGFloat = 5
    static let unselectedTrackThickness: CGFloat = 2
    static let tickColor = Color(red: 0, green: 197 / 255, blue: 1)
    static let unselectedTrackColor = Color(white: 0.55)
    static let pad: CGFloat = 22
    /// Android `DualNavigation.PIN_DRAG_UPDATE_INTERVAL_MS` (4 fps max while dragging).
    static let pinDragUpdateInterval: CFTimeInterval = 0.25

    let frameCount: Int
    @Binding var currentIndex: Int
    @Binding var range: ClosedRange<Int>
    var axis: Axis = .vertical
    var pinMapping: PinMapping = .inverted
    var onDoubleTap: () -> Void = {}

    @State private var dragRef = DragRef()
    @State private var dragRange: ClosedRange<Int>?
    @State private var dragCurrentIndex: Int?

    private enum PinEnd {
        case low
        case high
    }

    private final class DragRef {
        var end: PinEnd?
        var lastSyncTime: CFTimeInterval = 0
        var lastFrame: Int?
    }

    private var displayedRange: ClosedRange<Int> {
        dragRange ?? range
    }

    var body: some View {
        let activeRange = displayedRange
        GeometryReader { proxy in
            Canvas { context, size in
                drawTicks(context: context, size: size, activeRange: activeRange)
                drawPin(context: context, size: size, frame: activeRange.lowerBound)
                drawPin(context: context, size: size, frame: activeRange.upperBound)
            }
            .overlay {
                RangeBarTouchOverlay(
                    onBegan: { handleDragBegan(at: $0, size: proxy.size) },
                    onChanged: { handleDragChanged(at: $0, size: proxy.size) },
                    onEnded: { _ in handleDragEnded() },
                    onDoubleTap: onDoubleTap
                )
            }
        }
        .frame(width: axis == .vertical ? Self.barWidth : nil)
        .frame(height: axis == .horizontal ? Self.horizontalHeight : nil)
        .frame(maxWidth: axis == .horizontal ? .infinity : nil)
    }

    private func handleDragBegan(at location: CGPoint, size: CGSize) {
        dragRef.end = pinEnd(at: location, size: size, activeRange: displayedRange)
        dragRef.lastSyncTime = 0
        dragRef.lastFrame = nil
        guard let end = dragRef.end else { return }
        move(end: end, at: location, size: size)
    }

    private func handleDragChanged(at location: CGPoint, size: CGSize) {
        if dragRef.end == nil {
            dragRef.end = pinEnd(at: location, size: size, activeRange: displayedRange)
            dragRef.lastSyncTime = 0
            dragRef.lastFrame = nil
        }
        guard let end = dragRef.end else { return }
        move(end: end, at: location, size: size)
    }

    private func handleDragEnded() {
        defer {
            dragRef.end = nil
            dragRef.lastFrame = nil
            dragRange = nil
            dragCurrentIndex = nil
        }
        guard dragRef.end != nil else { return }
        if let finalIndex = dragCurrentIndex, currentIndex != finalIndex {
            currentIndex = finalIndex
        }
        if let finalRange = dragRange, range != finalRange {
            range = finalRange
        }
    }

    private func pinEnd(at location: CGPoint, size: CGSize, activeRange: ClosedRange<Int>) -> PinEnd? {
        let low = trackPoint(frame: activeRange.lowerBound, size: size)
        let high = trackPoint(frame: activeRange.upperBound, size: size)
        let lowHit = hitsPin(location: location, track: low)
        let highHit = hitsPin(location: location, track: high)
        if lowHit && highHit {
            if low == high {
                let along = axis == .vertical ? location.y : location.x
                let pinAlong = axis == .vertical ? low.y : low.x
                switch (axis, pinMapping) {
                case (.vertical, .inverted):
                    return along < pinAlong ? .low : .high
                case (.vertical, .identity):
                    return along > pinAlong ? .low : .high
                case (.horizontal, .identity):
                    return along < pinAlong ? .low : .high
                case (.horizontal, .inverted):
                    return along > pinAlong ? .low : .high
                }
            }
            return pinDistance(location, low) <= pinDistance(location, high) ? .low : .high
        }
        if lowHit { return .low }
        if highHit { return .high }
        return nil
    }

    private func hitsPin(location: CGPoint, track: CGPoint) -> Bool {
        pinDistance(location, track) <= Self.targetRadius
    }

    private func pinDistance(_ location: CGPoint, _ track: CGPoint) -> CGFloat {
        let bubble = bubbleCenter(from: track)
        let alongDist = axis == .vertical ? abs(location.y - track.y) : abs(location.x - track.x)
        return min(
            alongDist,
            hypot(location.x - track.x, location.y - track.y),
            hypot(location.x - bubble.x, location.y - bubble.y)
        )
    }

    private func move(end: PinEnd, at location: CGPoint, size: CGSize) {
        let pin = nearestPin(at: location, size: size)
        let frame = frameOf(pin: pin)
        if dragRef.lastFrame == frame {
            return
        }
        dragRef.lastFrame = frame

        let currentRange = displayedRange
        let nextRange: ClosedRange<Int>
        switch end {
        case .low:
            let other = currentRange.upperBound
            nextRange = min(frame, other)...max(frame, other)
            if frame > other {
                dragRef.end = .high
            }
        case .high:
            let other = currentRange.lowerBound
            nextRange = min(frame, other)...max(frame, other)
            if frame < other {
                dragRef.end = .low
            }
        }

        dragCurrentIndex = frame
        dragRange = nextRange

        let now = CACurrentMediaTime()
        if now - dragRef.lastSyncTime >= Self.pinDragUpdateInterval {
            dragRef.lastSyncTime = now
            if currentIndex != frame {
                currentIndex = frame
            }
            if range != nextRange {
                range = nextRange
            }
        }
    }

    private func drawTicks(context: GraphicsContext, size: CGSize, activeRange: ClosedRange<Int>) {
        // Ticks need at least 2 frames to place; a shrinking scene just draws no track.
        guard frameCount >= 2 else {
            return
        }
        if axis == .horizontal {
            drawHorizontalTrack(context: context, size: size, activeRange: activeRange)
            return
        }
        let start = trackPoint(frame: activeRange.lowerBound, size: size)
        let end = trackPoint(frame: activeRange.upperBound, size: size)
        if start.y != end.y {
            var selectedPath = Path()
            selectedPath.move(to: start)
            selectedPath.addLine(to: end)
            context.stroke(selectedPath, with: .color(Self.tickColor), lineWidth: Self.selectedTickThickness)
        }

        let manyTicks = (frameCount - 1) > 50
        let baseRadius = manyTicks ? Self.tickHeight / 3 : Self.tickHeight / 2
        var unselectedPath = Path()

        for pin in 0..<frameCount {
            let frame = frameOf(pin: pin)
            if activeRange.contains(frame) {
                continue
            }
            let point = trackPoint(pin: pin, size: size)
            let radius = baseRadius * (pin == 0 || pin == frameCount - 1 ? 2 : 1)
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            unselectedPath.addEllipse(in: rect)
        }

        if !unselectedPath.isEmpty {
            context.fill(unselectedPath, with: .color(Self.tickColor))
        }
    }

    private func drawHorizontalTrack(context: GraphicsContext, size: CGSize, activeRange: ClosedRange<Int>) {
        let first = trackPoint(pin: 0, size: size)
        let last = trackPoint(pin: frameCount - 1, size: size)
        var track = Path()
        track.move(to: first)
        track.addLine(to: last)
        context.stroke(track, with: .color(Self.unselectedTrackColor), lineWidth: Self.unselectedTrackThickness)

        let start = trackPoint(frame: activeRange.lowerBound, size: size)
        let end = trackPoint(frame: activeRange.upperBound, size: size)
        if start.x == end.x {
            return
        }
        var selected = Path()
        selected.move(to: start)
        selected.addLine(to: end)
        context.stroke(selected, with: .color(Self.tickColor), lineWidth: Self.selectedTickThickness)
    }

    private func drawPin(context: GraphicsContext, size: CGSize, frame: Int) {
        guard frameCount >= 2 else { return }
        let track = trackPoint(frame: frame, size: size)
        let bubble = bubbleCenter(from: track)
        context.fill(Self.pinBubble(center: bubble, size: Self.pinRadius * 2), with: .color(Self.tickColor))

        let strokeRect = CGRect(
            x: track.x - Self.circleRadius,
            y: track.y - Self.circleRadius,
            width: Self.circleRadius * 2,
            height: Self.circleRadius * 2
        )
        context.stroke(
            Path(ellipseIn: strokeRect.insetBy(dx: -Self.strokeWidth / 2, dy: -Self.strokeWidth / 2)),
            with: .color(.black),
            lineWidth: Self.strokeWidth
        )
        context.fill(Path(ellipseIn: strokeRect), with: .color(Self.tickColor))
        context.draw(
            Text("\(frame + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white),
            at: bubble,
            anchor: .center
        )
    }

    private func pinOf(frame: Int) -> Int {
        switch pinMapping {
        case .inverted:
            return DualNavigation.frameToPin(frame: frame, frameCount: frameCount)
        case .identity:
            return frame
        }
    }

    private func frameOf(pin: Int) -> Int {
        switch pinMapping {
        case .inverted:
            return DualNavigation.pinToFrame(pin: pin, frameCount: frameCount)
        case .identity:
            return pin
        }
    }

    private func axisLength(_ size: CGSize) -> CGFloat {
        axis == .vertical ? size.height : size.width
    }

    private func tickAlong(pin: Int, length: CGFloat) -> CGFloat {
        let span = length - 2 * Self.pad
        let t = CGFloat(pin) / CGFloat(frameCount - 1)
        switch axis {
        case .vertical:
            return length - Self.pad - t * span
        case .horizontal:
            return Self.pad + t * span
        }
    }

    private func trackCross(_ size: CGSize) -> CGFloat {
        let inset = Self.circleRadius + Self.strokeWidth + 4
        return axis == .vertical ? size.width - inset : size.height - inset
    }

    private func trackPoint(pin: Int, size: CGSize) -> CGPoint {
        let along = tickAlong(pin: pin, length: axisLength(size))
        let cross = trackCross(size)
        return axis == .vertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
    }

    private func trackPoint(frame: Int, size: CGSize) -> CGPoint {
        trackPoint(pin: pinOf(frame: frame), size: size)
    }

    private func bubbleCenter(from track: CGPoint) -> CGPoint {
        axis == .vertical
            ? CGPoint(x: track.x - Self.bubbleOffset, y: track.y)
            : CGPoint(x: track.x, y: track.y - Self.bubbleOffset)
    }

    private func nearestPin(at location: CGPoint, size: CGSize) -> Int {
        let length = axisLength(size)
        let span = length - 2 * Self.pad
        let along = axis == .vertical ? location.y : location.x
        let t: CGFloat
        switch axis {
        case .vertical:
            t = (length - Self.pad - along) / span
        case .horizontal:
            t = (along - Self.pad) / span
        }
        let pin = Int((t * CGFloat(frameCount - 1)).rounded())
        return min(max(pin, 0), frameCount - 1)
    }

    static func pinBubble(center: CGPoint, size: CGFloat) -> Path {
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let rounded = Path(roundedRect: rect, cornerRadius: size * 0.15)
        let transform = CGAffineTransform.identity
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: .pi / 4)
            .translatedBy(x: -center.x, y: -center.y)
        return rounded.applying(transform)
    }
}

private struct RangeBarTouchOverlay: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onDoubleTap: () -> Void

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
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onDoubleTap = onDoubleTap
    }

    final class Coordinator: NSObject {
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }
        var onDoubleTap: () -> Void = {}
        private var startPoint: CGPoint = .zero
        private var lastTapTime: TimeInterval = 0

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                startPoint = point
                onBegan(point)
            case .changed:
                onChanged(point)
            case .ended:
                onEnded(point)
                let now = CACurrentMediaTime()
                let dist = hypot(point.x - startPoint.x, point.y - startPoint.y)
                if dist < 12, now - lastTapTime < 0.35 {
                    lastTapTime = 0
                    onDoubleTap()
                } else if dist < 12 {
                    lastTapTime = now
                } else {
                    lastTapTime = 0
                }
            case .cancelled, .failed:
                lastTapTime = 0
                onEnded(point)
            default:
                lastTapTime = 0
            }
        }
    }
}

#Preview {
    RangePreview()
}

private struct RangePreview: View {
    @State private var currentIndex = 0
    @State private var range = 0...12

    var body: some View {
        VerticalRangeBar(frameCount: 100, currentIndex: $currentIndex, range: $range)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.92))
    }
}
