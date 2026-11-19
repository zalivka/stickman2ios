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

/// Top-right white corner triangle indicating a long-press / slide-out subtool (`fillButtonBackground` on Android).
struct SubtoolCornerTriangle: Shape {
    var inset: CGFloat = 3
    var leg: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let right = rect.maxX - inset
        let top = rect.minY + inset
        var path = Path()
        path.move(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + leg))
        path.addLine(to: CGPoint(x: right - leg, y: top))
        path.closeSubpath()
        return path
    }
}

/// Shared layout constants and chip styling matching `BonePaperTrackStyle.java`.
enum BonePaperTrackStyle {
    static let side: CGFloat = 44
    static let trackGap: CGFloat = 8
    static let chipPadH: CGFloat = 6
    static let chipSide: CGFloat = 36
    static let chipGap: CGFloat = 4
    static let unselectedIconColor = Color(red: 36.0 / 255.0, green: 37.0 / 255.0, blue: 48.0 / 255.0)
    static let unselectedChipFill = Color(red: 240.0 / 255.0, green: 241.0 / 255.0, blue: 245.0 / 255.0)
    static let unselectedChipStroke = Color(red: 216.0 / 255.0, green: 219.0 / 255.0, blue: 226.0 / 255.0)

    static func chipStripWidth(chipCount: Int) -> CGFloat {
        chipPadH * 2 + CGFloat(chipCount) * chipSide + CGFloat(max(0, chipCount - 1)) * chipGap
    }

    static func chipIndex(atX x: CGFloat, startX: CGFloat, count: Int) -> Int? {
        guard x >= startX, count > 0 else { return nil }
        let step = chipSide + chipGap
        let relX = x - startX
        let index = min(max(Int(floor(relX / step)), 0), count - 1)
        let withinSlot = relX - CGFloat(index) * step
        if withinSlot > chipSide + chipGap {
            return nil
        }
        return index
    }
}

struct BonePaperToolChipIcon: View {
    var mode: BonePaperTool
    var boxSide: CGFloat
    var inset: CGFloat
    var tintColor: Color
    var opacity: Double = 1

    var body: some View {
        ZStack {
            switch mode {
            case .pen:
                Image(uiImage: BonePaperChrome.chromeImage("v3_draw_free_unactivated"))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tintColor)
                    .padding(inset)
            case .line:
                Image(uiImage: BonePaperChrome.chromeImage("v3_draw_line_unactivated"))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tintColor)
                    .padding(inset)
            case .bucket:
                Image(uiImage: BonePaperChrome.chromeImage("vector_flood_unactivated"))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tintColor)
                    .padding(inset)
            case .brushfill:
                Image(uiImage: BonePaperChrome.chromeImage("kurwa_fill"))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tintColor)
                    .padding(inset)
            case .rectangle:
                let pad = boxSide * 0.25
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tintColor)
                    .frame(
                        width: max(1, boxSide - pad * 2),
                        height: max(1, boxSide - pad * 2 - 3)
                    )
            case .circle:
                let diameter = boxSide * 0.52
                Circle()
                    .fill(tintColor)
                    .frame(width: diameter, height: diameter)
            default:
                EmptyView()
            }
        }
        .frame(width: boxSide, height: boxSide)
        .opacity(opacity)
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
    var strokeMode: BonePaperTool = .pen
    @Binding var activeSetting: BonePaperStrokeSetting?
    var onActivate: () -> Void
    var onSelectStrokeMode: ((BonePaperTool) -> Void)? = nil
    var onSeeking: (Bool) -> Void
    var onFlashPreview: () -> Void

    private static let strokeModes: [BonePaperTool] = [.pen, .line]
    private static let side: CGFloat = BonePaperTrackStyle.side
    private static let trackWidth: CGFloat = 352
    private static let pinnedBrushSliderWidth: CGFloat = 260
    private static let pinnedBrushChipsWidth: CGFloat = BonePaperTrackStyle.chipStripWidth(chipCount: strokeModes.count)
    private static let pinnedBrushTrackWidth: CGFloat = pinnedBrushSliderWidth + pinnedBrushChipsWidth
    private static let trackPadding: CGFloat = 12
    private static let trackGap: CGFloat = BonePaperTrackStyle.trackGap
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

    private var showsStrokeModeChips: Bool {
        setting == .size && pinned
    }

    private var currentSliderWidth: CGFloat {
        showsStrokeModeChips ? Self.pinnedBrushSliderWidth : Self.trackWidth
    }

    private var currentTrackWidth: CGFloat {
        showsStrokeModeChips ? Self.pinnedBrushTrackWidth : Self.trackWidth
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
        case .mode:
            ""
        }
    }

    private var captionText: String {
        if setting == .size {
            return strokeMode == .line ? "line" : "brush"
        }
        return setting.label
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
                width: isActive ? Self.side + Self.trackGap + currentTrackWidth : Self.side,
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
                Text(captionText)
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
        .accessibilityLabel(captionText)
        .accessibilityValue(readout)
    }

    private var icon: some View {
        ZStack {
            if selected {
                BonePaperChrome.selected
            }
            switch setting {
            case .size:
                BonePaperToolChipIcon(
                    mode: strokeMode == .line ? .line : .pen,
                    boxSide: Self.side,
                    inset: (Self.side - 32) / 2,
                    tintColor: .white
                )
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
            case .mode:
                EmptyView()
            }
        }
        .frame(width: Self.side, height: Self.side)
        .overlay {
            if setting == .size {
                SubtoolCornerTriangle()
                    .fill(Color.white)
            }
        }
        .contentShape(Rectangle())
    }

    private var track: some View {
        let sliderW = currentSliderWidth
        let trackW = currentTrackWidth
        let lineWidth = sliderW - Self.trackPadding * 2
        let knobX = Self.trackPadding + ratio * lineWidth
        let bubbleWidth: CGFloat = 50
        let bubbleX = min(max(knobX - bubbleWidth / 2, 4), sliderW - bubbleWidth - 4)
        let knobColor = Color.black
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                }
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

            if showsStrokeModeChips {
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 1, height: Self.side - 12)
                    .offset(x: sliderW - 0.5, y: 6)

                HStack(spacing: BonePaperTrackStyle.chipGap) {
                    ForEach(Self.strokeModes, id: \.self) { mode in
                        let isSelectedMode = mode == strokeMode
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelectedMode ? BonePaperChrome.selected : BonePaperTrackStyle.unselectedChipFill)
                                .overlay {
                                    if !isSelectedMode {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(BonePaperTrackStyle.unselectedChipStroke, lineWidth: 1)
                                    }
                                }
                            BonePaperToolChipIcon(
                                mode: mode,
                                boxSide: BonePaperTrackStyle.chipSide,
                                inset: 6,
                                tintColor: isSelectedMode ? .white : BonePaperTrackStyle.unselectedIconColor
                            )
                        }
                        .frame(width: BonePaperTrackStyle.chipSide, height: BonePaperTrackStyle.chipSide)
                    }
                }
                .frame(height: Self.side)
                .offset(x: sliderW + BonePaperTrackStyle.chipPadH, y: 0)
            }
        }
        .frame(width: trackW, height: Self.side)
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
                let sliderW = currentSliderWidth
                let valueStart = Self.side + Self.trackGap + Self.trackPadding
                let valueWidth = sliderW - Self.trackPadding * 2
                if valueWidth <= 0 {
                    fatalError("BonePaper slider track width is \(valueWidth)")
                }
                if drag.location.x < valueStart {
                    value = start
                    return
                }
                if !BonePaperToolStore.hasUsedDragSlider {
                    BonePaperToolStore.hasUsedDragSlider = true
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
        let wasAlreadyActiveTool = selected || setting == .opacity
        onActivate()
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        if pinned {
            let trackLeft = Self.side + Self.trackGap
            if location.x >= trackLeft {
                let sliderW = currentSliderWidth
                let sliderRight = trackLeft + sliderW
                if showsStrokeModeChips && location.x >= sliderRight {
                    let startX = sliderRight + BonePaperTrackStyle.chipPadH
                    if let idx = BonePaperTrackStyle.chipIndex(
                        atX: location.x,
                        startX: startX,
                        count: Self.strokeModes.count
                    ) {
                        let picked = Self.strokeModes[idx]
                        onSelectStrokeMode?(picked)
                        pinned = false
                        activeSetting = nil
                    }
                    return
                }
                let valueStart = trackLeft + Self.trackPadding
                let valueWidth = sliderW - Self.trackPadding * 2
                let rawX = min(max(location.x - valueStart, 0), valueWidth)
                let span = range.upperBound - range.lowerBound
                if let jumped = nearestMark(atTrackX: rawX, valueWidth: valueWidth, span: span, maxDistance: Self.tapJumpRadius) {
                    value = jumped
                } else {
                    let t = rawX / valueWidth
                    value = range.lowerBound + t * span
                }
                onFlashPreview()
                return
            }
            pinned = false
            activeSetting = nil
        } else if wasAlreadyActiveTool {
            pinned = true
            activeSetting = setting
            if !BonePaperToolStore.hasUsedDragSlider {
                BonePaperHexToast.showMessage("Drag right to adjust")
            }
        }
    }
}
