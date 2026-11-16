import SwiftUI
import UIKit

struct BonePaperActiveSwatchTrack: Equatable {
    var swatchHex: String
    var baseColor: UIColor
    var centerY: CGFloat
    var brightness: CGFloat
    var marks: [CGFloat]
    var pinned: Bool

    static func == (lhs: BonePaperActiveSwatchTrack, rhs: BonePaperActiveSwatchTrack) -> Bool {
        lhs.swatchHex == rhs.swatchHex
            && lhs.centerY == rhs.centerY
            && lhs.brightness == rhs.brightness
            && lhs.marks == rhs.marks
            && lhs.pinned == rhs.pinned
    }
}

struct BonePaperSwatchTrackOverlay: View {
    @Binding var activeTrack: BonePaperActiveSwatchTrack?
    var screenHeight: CGFloat
    var onBrightnessChange: (UIColor, CGFloat, Bool) -> Void
    var onDismiss: () -> Void

    static let trackWidth: CGFloat = 312
    static let trackHeight: CGFloat = 44
    static let trackLeftPadding: CGFloat = 12
    static let trackRightPadding: CGFloat = 28
    static let trackGap: CGFloat = 8
    static let snapRadius: CGFloat = 6
    static let tapJumpRadius: CGFloat = 14
    static let minBrightness: CGFloat = 0.01
    static let maxBrightness: CGFloat = 1.0

    var body: some View {
        if let track = activeTrack {
            let clampedCenterY = min(
                max(track.centerY, Self.trackHeight / 2 + 8),
                max(screenHeight - Self.trackHeight / 2 - 8, Self.trackHeight / 2 + 8)
            )
            let span = Self.maxBrightness - Self.minBrightness
            let ratio = min(max((track.brightness - Self.minBrightness) / span, 0), 1)
            let lineWidth = Self.trackWidth - Self.trackLeftPadding - Self.trackRightPadding
            let knobX = Self.trackLeftPadding + ratio * lineWidth
            let bubbleWidth: CGFloat = 50
            let bubbleX = min(max(knobX - bubbleWidth / 2, 4), Self.trackWidth - bubbleWidth - 4)
            let readout = "\(Int((track.brightness * 100).rounded()))%"
            let fullColor = Self.color(base: track.baseColor, brightness: 1.0)
            let knobColor = Self.color(base: track.baseColor, brightness: track.brightness)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.black, Color(fullColor)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lineWidth, height: 6)
                    .overlay {
                        Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.75)
                    }
                    .offset(x: Self.trackLeftPadding, y: 28.5)

                ForEach(Array(track.marks.enumerated()), id: \.offset) { _, mark in
                    let clamped = min(max(mark, Self.minBrightness), Self.maxBrightness)
                    let markRatio = (clamped - Self.minBrightness) / span
                    let markX = Self.trackLeftPadding + markRatio * lineWidth
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 2, height: 11)
                        .offset(x: markX - 1, y: 26)
                }

                Circle()
                    .fill(Color(knobColor))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 1.5)
                    }
                    .overlay {
                        Circle().stroke(Color.black.opacity(0.45), lineWidth: 1)
                            .padding(-1)
                    }
                    .offset(x: knobX - 7, y: 24.5)

                Text(readout)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.black)
                    .frame(width: bubbleWidth, height: 20)
                    .background(Color(white: 0.92))
                    .clipShape(Capsule())
                    .offset(x: bubbleX, y: 2)
            }
            .frame(width: Self.trackWidth, height: Self.trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let rawX = min(max(value.location.x - Self.trackLeftPadding, 0), lineWidth)
                        let next = Self.valueAt(
                            rawX: rawX,
                            lineWidth: lineWidth,
                            marks: track.marks,
                            snapRadius: Self.snapRadius
                        )
                        activeTrack?.brightness = next
                        onBrightnessChange(track.baseColor, next, true)
                    }
                    .onEnded { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        if dist < 4 {
                            let rawX = min(max(value.location.x - Self.trackLeftPadding, 0), lineWidth)
                            if let jumped = Self.nearestMark(
                                atTrackX: rawX,
                                valueWidth: lineWidth,
                                marks: track.marks,
                                maxDistance: Self.tapJumpRadius
                            ) {
                                activeTrack?.brightness = jumped
                                onBrightnessChange(track.baseColor, jumped, false)
                                return
                            }
                            onDismiss()
                        } else {
                            onBrightnessChange(track.baseColor, activeTrack?.brightness ?? track.brightness, false)
                            if track.pinned == false {
                                onDismiss()
                            }
                        }
                    }
            )
            .position(
                x: -Self.trackGap - Self.trackWidth / 2,
                y: clampedCenterY
            )
        }
    }

    static func color(base: UIColor, brightness: CGFloat) -> UIColor {
        guard let hsb = BonePaperDrawingConfig.hsbComponents(of: base) else {
            return base
        }
        let v = min(max(brightness, minBrightness), maxBrightness)
        return UIColor(hue: hsb.hue, saturation: hsb.saturation, brightness: v, alpha: 1)
    }

    static func valueAt(
        rawX: CGFloat,
        lineWidth: CGFloat,
        marks: [CGFloat],
        snapRadius: CGFloat
    ) -> CGFloat {
        let span = maxBrightness - minBrightness
        if let snapped = nearestMark(
            atTrackX: rawX,
            valueWidth: lineWidth,
            marks: marks,
            maxDistance: snapRadius
        ) {
            return snapped
        }
        let t = min(max(rawX / max(lineWidth, 1), 0), 1)
        return minBrightness + t * span
    }

    static func nearestMark(
        atTrackX rawX: CGFloat,
        valueWidth: CGFloat,
        marks: [CGFloat],
        maxDistance: CGFloat
    ) -> CGFloat? {
        let span = maxBrightness - minBrightness
        guard span > 0, valueWidth > 0 else { return nil }
        var bestMark: CGFloat?
        var bestDist = maxDistance
        for mark in marks {
            let clamped = min(max(mark, minBrightness), maxBrightness)
            let markX = ((clamped - minBrightness) / span) * valueWidth
            let dist = abs(rawX - markX)
            if dist <= bestDist {
                bestDist = dist
                bestMark = clamped
            }
        }
        return bestMark
    }
}

struct BonePaperColorSwatchGestureView: UIViewRepresentable {
    var hex: String
    var baseColor: UIColor
    var currentColor: UIColor
    var marks: [CGFloat]
    @Binding var activeTrack: BonePaperActiveSwatchTrack?
    var onSelectBase: (UIColor) -> Void
    var onBrightnessChange: (UIColor, CGFloat, Bool) -> Void
    var onResetFullBrightness: (UIColor) -> Void
    var onLongPress: (UIColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.42

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator

        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pan)
        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostView = uiView
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: BonePaperColorSwatchGestureView
        weak var hostView: UIView?
        private var initialBrightness: CGFloat = 1.0

        init(parent: BonePaperColorSwatchGestureView) {
            self.parent = parent
        }

        private func currentBrightness() -> CGFloat {
            let baseKey = BonePaperDrawingConfig.hueKey(for: parent.baseColor)
            let curKey = BonePaperDrawingConfig.hueKey(for: parent.currentColor)
            if baseKey != nil, baseKey == curKey,
               let hsb = BonePaperDrawingConfig.hsbComponents(of: parent.currentColor) {
                return min(max(hsb.brightness, BonePaperSwatchTrackOverlay.minBrightness), BonePaperSwatchTrackOverlay.maxBrightness)
            }
            if let hsb = BonePaperDrawingConfig.hsbComponents(of: parent.baseColor) {
                return min(max(hsb.brightness, BonePaperSwatchTrackOverlay.minBrightness), BonePaperSwatchTrackOverlay.maxBrightness)
            }
            return 1.0
        }

        private func centerYInRightRail() -> CGFloat {
            guard let view = hostView else { return 100 }
            var cursor: UIView? = view
            while let current = cursor {
                if let scroll = current as? BonePaperFillScrollView, let rail = scroll.superview {
                    return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: rail).y
                }
                cursor = current.superview
            }
            if let window = view.window {
                return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window).y
            }
            return view.bounds.midY
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.activeTrack = nil
            parent.onSelectBase(parent.baseColor)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.activeTrack = nil
            parent.onResetFullBrightness(parent.baseColor)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            parent.activeTrack = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(parent.baseColor)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = hostView else { return }
            let railView: UIView = {
                var cursor: UIView? = view
                while let current = cursor {
                    if let scroll = current as? BonePaperFillScrollView, let rail = scroll.superview {
                        return rail
                    }
                    cursor = current.superview
                }
                return view
            }()
            let locInRail = gesture.location(in: railView)
            let lineWidth = BonePaperSwatchTrackOverlay.trackWidth - BonePaperSwatchTrackOverlay.trackLeftPadding - BonePaperSwatchTrackOverlay.trackRightPadding
            let trackLeftInRail = -BonePaperSwatchTrackOverlay.trackGap - BonePaperSwatchTrackOverlay.trackWidth
            let valueStartInRail = trackLeftInRail + BonePaperSwatchTrackOverlay.trackLeftPadding
            let trackRightInRail = -BonePaperSwatchTrackOverlay.trackGap

            switch gesture.state {
            case .began:
                initialBrightness = currentBrightness()
                let cy = centerYInRightRail()
                parent.activeTrack = BonePaperActiveSwatchTrack(
                    swatchHex: parent.hex,
                    baseColor: parent.baseColor,
                    centerY: cy,
                    brightness: initialBrightness,
                    marks: parent.marks,
                    pinned: false
                )
                parent.onBrightnessChange(parent.baseColor, initialBrightness, true)
            case .changed:
                let next: CGFloat
                if locInRail.x > trackRightInRail {
                    next = initialBrightness
                } else {
                    let rawX = min(max(locInRail.x - valueStartInRail, 0), lineWidth)
                    next = BonePaperSwatchTrackOverlay.valueAt(
                        rawX: rawX,
                        lineWidth: lineWidth,
                        marks: parent.marks,
                        snapRadius: BonePaperSwatchTrackOverlay.snapRadius
                    )
                }
                parent.activeTrack?.brightness = next
                parent.onBrightnessChange(parent.baseColor, next, true)
            case .ended, .cancelled, .failed:
                let finalB = parent.activeTrack?.brightness ?? initialBrightness
                parent.onBrightnessChange(parent.baseColor, finalB, false)
                parent.activeTrack = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = hostView {
                let vel = pan.velocity(in: view)
                return abs(vel.x) > abs(vel.y)
            }
            return true
        }
    }
}
