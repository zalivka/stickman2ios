import SwiftUI

private struct CheckerDisc: View {
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 2
            let light = Color(white: 0.92)
            let dark = Color(white: 0.62)
            for row in 0..<2 {
                for col in 0..<2 {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color((row + col).isMultiple(of: 2) ? light : dark))
                }
            }
        }
        .clipShape(Circle())
    }
}

struct BonePaperDragControl: View {
    var setting: BonePaperStrokeSetting
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>
    var marks: [CGFloat]
    var color: Color
    var selected: Bool
    var enabled: Bool
    var showsCaption: Bool = true
    @Binding var activeSetting: BonePaperStrokeSetting?
    var onActivate: () -> Void
    var onSeeking: (Bool) -> Void
    var onFlashPreview: () -> Void

    private static let side: CGFloat = 44
    private static let trackWidth: CGFloat = 352
    private static let trackPadding: CGFloat = 12
    private static let trackGap: CGFloat = 8
    private static let snapRadius: CGFloat = 6
    private static let tapJumpRadius: CGFloat = 14
    private static let space = "bonepaper.slider"

    @State private var dragStartValue: CGFloat?
    /// Seek bar stays out after a double tap or long press. A plain drag still closes it on release.
    @State private var pinned = false
    /// The tap that finishes a double tap or long press must not immediately close the bar.
    @State private var swallowNextTap = false

    private var isActive: Bool {
        enabled && (pinned || activeSetting == setting)
    }

    private var ratio: CGFloat {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var readout: String {
        switch setting {
        case .size, .eraser:
            "\(Int(value.rounded()))"
        case .opacity:
            "\(Int((value * 100).rounded()))%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ZStack(alignment: .leading) {
                if isActive {
                    track
                        .offset(x: Self.side + Self.trackGap)
                }
                icon
            }
            .frame(
                width: isActive ? Self.side + Self.trackGap + Self.trackWidth : Self.side,
                height: Self.side,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.space)
            .gesture(drag)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    handleDoubleTap()
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    pinSeekBar()
                }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { event in
                    handleTap(at: event.location)
                }
            )
            .onChange(of: activeSetting) { _, next in
                if next != setting {
                    pinned = false
                    swallowNextTap = false
                }
            }
            .onChange(of: enabled) { _, next in
                if !next {
                    dragStartValue = nil
                    pinned = false
                    swallowNextTap = false
                    if activeSetting == setting {
                        activeSetting = nil
                        onSeeking(false)
                    }
                }
            }
            if showsCaption {
                Text(setting.label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(selected || isActive ? BonePaperChrome.selected : Color.white)
                    .frame(width: Self.side)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: enabled)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setting.label)
        .accessibilityValue(readout)
    }

    private var icon: some View {
        ZStack {
            if selected {
                BonePaperChrome.selected
            }
            switch setting {
            case .size:
                Image(uiImage: BonePaperChrome.chromeImage("v3_draw_free_unactivated"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            case .opacity:
                ZStack {
                    CheckerDisc()
                    Circle()
                        .fill(color.opacity(value))
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 22, height: 22)
            case .eraser:
                Image(uiImage: BonePaperChrome.chromeImage(
                    selected ? "vector_eraser_activated" : "vector_eraser_deactivated"
                ))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(Rectangle())
    }

    private var track: some View {
        let lineWidth = Self.trackWidth - Self.trackPadding * 2
        let knobX = Self.trackPadding + ratio * lineWidth
        let bubbleWidth: CGFloat = 50
        let bubbleX = min(max(knobX - bubbleWidth / 2, 4), Self.trackWidth - bubbleWidth - 4)
        let knobColor = Color.black
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            trackLine
                .frame(width: lineWidth, height: 5)
                .offset(x: Self.trackPadding, y: 29)
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                let clamped = min(max(mark, range.lowerBound), range.upperBound)
                let markRatio = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
                let markX = Self.trackPadding + markRatio * lineWidth
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 2, height: 11)
                    .offset(x: markX - 1, y: 26)
            }
            Circle()
                .fill(knobColor)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().stroke(Color.black.opacity(0.3), lineWidth: 1)
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
        .frame(width: Self.trackWidth, height: Self.side)
    }

    private var trackLine: some View {
        Capsule()
            .fill(Color.black.opacity(0.22))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if !enabled { return }
                if dragStartValue == nil {
                    dragStartValue = value
                    onActivate()
                    onSeeking(true)
                }
                activeSetting = setting
                guard let start = dragStartValue else {
                    fatalError("BonePaper drag started without a value")
                }
                let valueStart = Self.side + Self.trackGap + Self.trackPadding
                let valueWidth = Self.trackWidth - Self.trackPadding * 2
                if valueWidth <= 0 {
                    fatalError("BonePaper slider track width is \(valueWidth)")
                }
                if drag.location.x < valueStart {
                    value = start
                    return
                }
                let rawX = min(max(drag.location.x - valueStart, 0), valueWidth)
                let span = range.upperBound - range.lowerBound
                if let snapped = nearestMark(atTrackX: rawX, valueWidth: valueWidth, span: span, maxDistance: Self.snapRadius) {
                    value = snapped
                } else {
                    let t = rawX / valueWidth
                    value = range.lowerBound + t * span
                }
            }
            .onEnded { _ in
                if !enabled { return }
                dragStartValue = nil
                onSeeking(false)
                if !pinned {
                    activeSetting = nil
                }
            }
    }

    private func nearestMark(atTrackX rawX: CGFloat, valueWidth: CGFloat, span: CGFloat, maxDistance: CGFloat) -> CGFloat? {
        guard span > 0, valueWidth > 0 else { return nil }
        var bestMark: CGFloat?
        var bestDist = maxDistance
        for mark in marks {
            let clamped = min(max(mark, range.lowerBound), range.upperBound)
            let markX = ((clamped - range.lowerBound) / span) * valueWidth
            let dist = abs(rawX - markX)
            if dist <= bestDist {
                bestDist = dist
                bestMark = clamped
            }
        }
        return bestMark
    }

    private func handleDoubleTap() {
        if !enabled { return }
        if setting == .opacity {
            pinned = false
            swallowNextTap = true
            if activeSetting == setting {
                activeSetting = nil
            }
            value = range.upperBound
            onActivate()
            onFlashPreview()
            BonePaperHexToast.showMessage("Opacity 100%")
            return
        }
        pinSeekBar()
    }

    private func pinSeekBar() {
        if !enabled { return }
        pinned = true
        activeSetting = setting
        swallowNextTap = true
        onActivate()
    }

    private func handleTap(at location: CGPoint) {
        if !enabled { return }
        onActivate()
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        if pinned {
            let trackLeft = Self.side + Self.trackGap
            if location.x >= trackLeft {
                let valueStart = trackLeft + Self.trackPadding
                let valueWidth = Self.trackWidth - Self.trackPadding * 2
                let rawX = min(max(location.x - valueStart, 0), valueWidth)
                let span = range.upperBound - range.lowerBound
                if let jumped = nearestMark(atTrackX: rawX, valueWidth: valueWidth, span: span, maxDistance: Self.tapJumpRadius) {
                    value = jumped
                    onFlashPreview()
                    return
                }
            }
            pinned = false
            activeSetting = nil
        }
    }
}
