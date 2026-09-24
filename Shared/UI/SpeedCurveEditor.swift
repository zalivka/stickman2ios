import SwiftUI
import UIKit

struct SpeedCurveEditor: UIViewRepresentable {
    var frameCount: Int
    var points: [SpeedPoint]
    var highlightIndex: Int
    var interactive: Bool = true
    var onChange: ([SpeedPoint]) -> Void

    func makeUIView(context: Context) -> SpeedCurveView {
        let view = SpeedCurveView()
        view.onChange = onChange
        view.isUserInteractionEnabled = interactive
        view.apply(frameCount: frameCount, points: points, highlightIndex: highlightIndex)
        return view
    }

    func updateUIView(_ view: SpeedCurveView, context: Context) {
        view.onChange = onChange
        view.isUserInteractionEnabled = interactive
        view.apply(frameCount: frameCount, points: points, highlightIndex: highlightIndex)
    }
}

final class SpeedCurveView: UIView {
    /// Android `Bars.SPAN` is 50px, not 50pt.
    static var span: CGFloat { 50 / UIScreen.main.scale }

    var onChange: (([SpeedPoint]) -> Void)?

    private var frameCount = 0
    private var points: [SpeedPoint] = []
    private var highlightIndex = -1
    private var offsetX: CGFloat = 0
    private var dragIndex: Int?

    private let lineColor = UIColor(red: 0, green: 178 / 255, blue: 1, alpha: 1)
    private let barColor = UIColor.white
    private let shade = UIColor(white: 0.067, alpha: 0.33)
    private let barWidth = 4 / UIScreen.main.scale
    /// Android varspeed sets `mStrokeWidth = 10` px. `UIBezierPath.stroke()`
    /// ignores the context width and defaults to 1pt — keep it on the path.
    private let lineWidth: CGFloat = 5
    private let handleRadius: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpeedCurveView coder")
    }

    func apply(frameCount: Int, points: [SpeedPoint], highlightIndex: Int) {
        if dragIndex != nil {
            return
        }
        self.frameCount = frameCount
        self.points = points
        if self.highlightIndex != highlightIndex {
            self.highlightIndex = highlightIndex
            centerHighlight()
        }
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerHighlight()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), frameCount > 1, bounds.height > 1 else {
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: offsetX, y: 0)
        shade.setFill()
        ctx.fill(CGRect(x: -bounds.width, y: 0, width: contentWidth() + bounds.width * 2, height: bounds.height))

        let band = bounds.midY
        let clipH: CGFloat = 60
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -CGFloat.greatestFiniteMagnitude, y: band - clipH / 2, width: .greatestFiniteMagnitude, height: clipH))
        barColor.setStroke()
        ctx.setLineWidth(barWidth)
        for index in 0..<frameCount {
            let x = barX(index)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        ctx.strokePath()
        if highlightIndex >= 0, highlightIndex + 1 < frameCount {
            barColor.setFill()
            ctx.fill(
                CGRect(
                    x: barX(highlightIndex),
                    y: 0,
                    width: Self.span,
                    height: bounds.height
                )
            )
        }
        ctx.restoreGState()

        lineColor.setStroke()
        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        for (i, point) in points.enumerated() {
            let at = screenPoint(point)
            if i == 0 {
                path.move(to: at)
            } else {
                path.addLine(to: at)
            }
        }
        path.stroke()
        for point in points {
            let at = screenPoint(point)
            ctx.setFillColor(lineColor.cgColor)
            ctx.fillEllipse(
                in: CGRect(
                    x: at.x - handleRadius,
                    y: at.y - handleRadius,
                    width: handleRadius * 2,
                    height: handleRadius * 2
                )
            )
        }
        ctx.restoreGState()

        if highlightIndex >= 0, highlightIndex + 1 < frameCount {
            let speed = speedAt(gap: highlightIndex)
            let text = String(
                format: "Frame #%d-#%d Speed %d%%",
                highlightIndex + 1,
                highlightIndex + 2,
                SpeedModifier.speedPercent(speed)
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.height * 0.75 + 24),
                withAttributes: attrs
            )
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        dragIndex = hitPoint(at: location)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let dragIndex, dragIndex >= 0, dragIndex < points.count else {
            return
        }
        let location = touch.location(in: self)
        movePoint(at: dragIndex, to: location)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    @objc private func handleDoubleTap(_ tap: UITapGestureRecognizer) {
        if tap.state != .ended {
            return
        }
        insert(at: tap.location(in: self))
    }

    private func finishDrag() {
        if dragIndex != nil {
            snapDragged()
            dragIndex = nil
            emit()
        }
        setNeedsDisplay()
    }

    private func movePoint(at index: Int, to screen: CGPoint) {
        var point = points[index]
        let graphX = screen.x - offsetX
        let first = index == 0
        let last = index == points.count - 1
        if !first, !last {
            let minX = barX(points[index - 1].index) + 1
            let maxX = barX(points[index + 1].index) - 1
            point.index = nearestIndex(x: min(max(graphX, minX), maxX), avoiding: index)
        }
        let y = min(max(screen.y, 0), bounds.height)
        point.speedValue = SpeedModifier.yToSpeed(y, viewHeight: bounds.height)
        points[index] = point
    }

    private func snapDragged() {
        guard let dragIndex, dragIndex > 0, dragIndex < points.count - 1 else {
            return
        }
        var point = points[dragIndex]
        point.index = nearestIndex(x: barX(point.index), avoiding: dragIndex)
        points[dragIndex] = point
    }

    private func insert(at screen: CGPoint) {
        if hitPoint(at: screen) != nil {
            return
        }
        let graphX = screen.x - offsetX
        let index = nearestVacant(x: graphX)
        guard let index else {
            return
        }
        let speed = SpeedModifier.yToSpeed(min(max(screen.y, 0), bounds.height), viewHeight: bounds.height)
        points.append(SpeedPoint(index: index, speedValue: speed))
        points.sort { $0.index < $1.index }
        emit()
        setNeedsDisplay()
    }

    private func hitPoint(at screen: CGPoint) -> Int? {
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, point) in points.enumerated() {
            let at = CGPoint(x: barX(point.index) + offsetX, y: SpeedModifier.speedToY(point.speedValue, viewHeight: bounds.height))
            let dist = hypot(screen.x - at.x, screen.y - at.y)
            if dist < 28, dist < bestDist {
                best = i
                bestDist = dist
            }
        }
        return best
    }

    private func nearestIndex(x: CGFloat, avoiding skip: Int) -> Int {
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<frameCount {
            if occupied(i, skipping: skip) {
                continue
            }
            let dist = abs(barX(i) - x)
            if dist < bestDist {
                best = i
                bestDist = dist
            }
        }
        return best
    }

    private func nearestVacant(x: CGFloat) -> Int? {
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 1..<(frameCount - 1) {
            if occupied(i, skipping: -1) {
                continue
            }
            let dist = abs(barX(i) - x)
            if dist < bestDist {
                best = i
                bestDist = dist
            }
        }
        return best
    }

    private func occupied(_ index: Int, skipping skip: Int) -> Bool {
        points.enumerated().contains { $0.offset != skip && $0.element.index == index }
    }

    private func emit() {
        onChange?(points)
    }

    private func centerHighlight() {
        if highlightIndex < 0 || bounds.width < 1 {
            return
        }
        offsetX = bounds.width / 2 - CGFloat(highlightIndex) * Self.span
    }

    private func barX(_ index: Int) -> CGFloat {
        CGFloat(index) * Self.span
    }

    private func contentWidth() -> CGFloat {
        CGFloat(max(frameCount - 1, 0)) * Self.span
    }

    private func screenPoint(_ point: SpeedPoint) -> CGPoint {
        CGPoint(
            x: barX(point.index),
            y: SpeedModifier.speedToY(point.speedValue, viewHeight: bounds.height)
        )
    }

    private func speedAt(gap: Int) -> Float {
        SpeedModifier(points: points).speedMod(gapIndex: gap, frameCount: frameCount)
    }
}
