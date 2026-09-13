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

    static let barWidth: CGFloat = 75
    static let horizontalHeight: CGFloat = 72
    static let tickHeight: CGFloat = 4
    static let pinRadius: CGFloat = 14
    static let circleRadius: CGFloat = 5
    static let strokeWidth: CGFloat = 2
    static let targetRadius: CGFloat = 24
    static let selectedTickThickness: CGFloat = 5
    static let tickColor = Color(red: 0, green: 197 / 255, blue: 1)
    static let pad: CGFloat = 19

    let frameCount: Int
    @Binding var currentIndex: Int
    @Binding var range: ClosedRange<Int>
    var axis: Axis = .vertical
    var pinMapping: PinMapping = .inverted
    var onDoubleTap: () -> Void = {}

    @State private var dragRef = DragRef()

    private enum PinEnd {
        case low
        case high
    }

    private final class DragRef {
        var end: PinEnd?
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawTicks(context: context, size: size)
                drawPin(context: context, size: size, frame: range.lowerBound)
                drawPin(context: context, size: size, frame: range.upperBound)
            }
            .overlay {
                RangeBarTouchOverlay(
                    onBegan: { handleDragChanged(at: $0, size: proxy.size) },
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

    private func handleDragChanged(at location: CGPoint, size: CGSize) {
        if dragRef.end == nil {
            dragRef.end = pinEnd(at: location, size: size)
        }
        guard let end = dragRef.end else { return }
        move(end: end, at: location, size: size)
    }

    private func handleDragEnded() {
        dragRef.end = nil
    }

    private func pinEnd(at location: CGPoint, size: CGSize) -> PinEnd? {
        let low = trackPoint(frame: range.lowerBound, size: size)
        let high = trackPoint(frame: range.upperBound, size: size)
        let lowHit = hitsPin(location: location, track: low)
        let highHit = hitsPin(location: location, track: high)
        if lowHit && highHit {
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
        return min(
            hypot(location.x - track.x, location.y - track.y),
            hypot(location.x - bubble.x, location.y - bubble.y)
        )
    }

    private func move(end: PinEnd, at location: CGPoint, size: CGSize) {
        let pin = nearestPin(at: location, size: size)
        let frame = frameOf(pin: pin)
        currentIndex = frame
        switch end {
        case .low:
            let other = range.upperBound
            range = min(frame, other)...max(frame, other)
            if frame > other {
                dragRef.end = .high
            }
        case .high:
            let other = range.lowerBound
            range = min(frame, other)...max(frame, other)
            if frame < other {
                dragRef.end = .low
            }
        }
    }

    private func drawTicks(context: GraphicsContext, size: CGSize) {
        if frameCount < 2 {
            fatalError("VerticalRangeBar frameCount must be >= 2, got \(frameCount)")
        }
        let span = axisLength(size) - 2 * Self.pad
        let tickSpacing = span / CGFloat(frameCount - 1)
        let lowFramePin = pinOf(frame: range.lowerBound)
        let manyTicks = (frameCount - 1) > 50
        let baseRadius = manyTicks ? Self.tickHeight / 3 : Self.tickHeight / 2

        for pin in 0..<frameCount {
            let frame = frameOf(pin: pin)
            let point = trackPoint(pin: pin, size: size)
            let selected = range.contains(frame)
            if selected && pin != lowFramePin {
                let rect: CGRect
                switch axis {
                case .vertical:
                    rect = CGRect(
                        x: point.x - Self.selectedTickThickness / 2,
                        y: point.y - tickSpacing / 2,
                        width: Self.selectedTickThickness,
                        height: tickSpacing + 2
                    )
                case .horizontal:
                    rect = CGRect(
                        x: point.x - tickSpacing / 2,
                        y: point.y - Self.selectedTickThickness / 2,
                        width: tickSpacing + 2,
                        height: Self.selectedTickThickness
                    )
                }
                context.fill(Path(rect), with: .color(Self.tickColor))
            } else {
                let radius = baseRadius * (pin == 0 || pin == frameCount - 1 ? 2 : 1)
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Self.tickColor))
            }
        }
    }

    private func drawPin(context: GraphicsContext, size: CGSize, frame: Int) {
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
                .font(.system(size: 10, weight: .bold))
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
            ? CGPoint(x: track.x - 22, y: track.y)
            : CGPoint(x: track.x, y: track.y - 22)
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
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
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

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                onBegan(point)
            case .changed:
                onChanged(point)
            case .ended, .cancelled, .failed:
                onEnded(point)
            default:
                break
            }
        }

        @objc func handleDoubleTap() {
            onDoubleTap()
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
