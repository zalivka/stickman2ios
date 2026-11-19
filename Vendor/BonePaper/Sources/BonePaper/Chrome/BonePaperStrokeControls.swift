import SwiftUI
import UIKit

struct BonePaperStrokeControls: View {
    @Binding var tool: BonePaperTool
    @Binding var strokeMode: BonePaperTool
    @Binding var fillMode: BonePaperTool
    @Binding var brushSize: CGFloat
    @Binding var eraserSize: CGFloat
    @Binding var opacity: CGFloat
    @Binding var activeSetting: BonePaperStrokeSetting?
    var brushMarks: [CGFloat]
    var opacityMarks: [CGFloat]
    var eraserMarks: [CGFloat]
    var showingMenu: Bool
    var onToggleMenu: () -> Void
    var isPlacingImage: Bool = false
    var onCancelPlacement: () -> Void = {}
    var canUndo: Bool
    var onUndo: () -> Void
    var canRedo: Bool
    var onRedo: () -> Void
    var color: Color
    var onSeeking: (Bool) -> Void
    var onFlashPreview: () -> Void
    var bottomInset: CGFloat = 0

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var brushAndOpacityEnabled: Bool {
        UIColor(color).cgColor.alpha > 0
    }

    private var railWidth: CGFloat {
        activeSetting != nil
            ? BonePaperChrome.leftRail + 8 + 352
            : BonePaperChrome.leftRail
    }

    var body: some View {
        let itemSpacing: CGFloat = isPad ? 3 : 2
        let bottomPad: CGFloat = isPad ? bottomInset + BonePaperChrome.pad : max(bottomInset, 8)
        let dimAlpha: Double = isPlacingImage ? 0.25 : 1.0
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                if isPlacingImage {
                    BonePaperPlacementCancelButton(onCancel: onCancelPlacement)
                } else {
                    BonePaperMenuButton(activated: showingMenu, onTap: onToggleMenu)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: itemSpacing) {
                    modeControl
                    brushControl
                    opacityControl
                    eraserControl
                }
                .padding(.leading, BonePaperChrome.railIconInset)
                .opacity(dimAlpha)
                .disabled(isPlacingImage)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: itemSpacing) {
                    BonePaperRedoButton(canRedo: canRedo && !isPlacingImage, showsCaption: isPad, onRedo: onRedo)
                    BonePaperUndoButton(canUndo: canUndo && !isPlacingImage, showsCaption: isPad, onUndo: onUndo)
                }
                .padding(.leading, BonePaperChrome.railIconInset)
                .padding(.bottom, bottomPad)
                .opacity(dimAlpha)
                .disabled(isPlacingImage)
            }
            .animation(nil, value: tool)
            .frame(width: railWidth, height: geo.size.height, alignment: .leading)
        }
        .frame(width: railWidth)
    }

    private var modeControl: some View {
        BonePaperModeControl(
            fillMode: $fillMode,
            selected: tool.isFillMode,
            paintModesEnabled: brushAndOpacityEnabled,
            showsCaption: isPad,
            activeSetting: $activeSetting,
            onSelectMode: { picked in
                if !brushAndOpacityEnabled && picked != .bucket {
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    fillMode = picked
                    tool = picked
                }
            }
        )
    }

    private var brushControl: some View {
        BonePaperDragControl(
            setting: .size,
            value: $brushSize,
            range: BonePaperBrush.sizeRange,
            marks: brushMarks,
            color: color,
            selected: tool.isStrokeMode,
            enabled: brushAndOpacityEnabled,
            showsCaption: isPad,
            strokeMode: strokeMode,
            activeSetting: $activeSetting,
            onActivate: {
                tool = strokeMode
            },
            onSelectStrokeMode: { picked in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    strokeMode = picked
                    tool = picked
                }
            },
            onSeeking: onSeeking,
            onFlashPreview: onFlashPreview
        )
    }

    private var opacityControl: some View {
        BonePaperDragControl(
            setting: .opacity,
            value: $opacity,
            range: BonePaperBrush.opacityRange,
            marks: opacityMarks,
            color: color,
            selected: false,
            enabled: brushAndOpacityEnabled,
            showsCaption: isPad,
            activeSetting: $activeSetting,
            onActivate: {
                if !tool.isFillMode && !tool.isStrokeMode {
                    tool = strokeMode
                }
            },
            onSeeking: onSeeking,
            onFlashPreview: onFlashPreview
        )
    }

    private var eraserControl: some View {
        BonePaperDragControl(
            setting: .eraser,
            value: $eraserSize,
            range: BonePaperBrush.sizeRange,
            marks: eraserMarks,
            color: color,
            selected: tool == .eraser,
            enabled: true,
            showsCaption: isPad,
            activeSetting: $activeSetting,
            onActivate: { tool = .eraser },
            onSeeking: onSeeking,
            onFlashPreview: onFlashPreview
        )
    }
}

/// Top rail button for the 4 filling tools: Bucket, Brushfill, Rectangle, Circle.
/// Supports tap to activate, tap-when-active / long-press / double-tap to pin the strip open,
/// and horizontal drag-right to scrub across the 4 tools.
private struct BonePaperModeControl: View {
    private static let modes: [BonePaperTool] = [.bucket, .brushfill, .rectangle, .circle]
    private static let side: CGFloat = BonePaperTrackStyle.side
    private static let trackGap: CGFloat = BonePaperTrackStyle.trackGap
    private static let trackWidth: CGFloat = BonePaperTrackStyle.chipStripWidth(chipCount: modes.count)
    private static let space = "bonepaper.mode"

    @Binding var fillMode: BonePaperTool
    var selected: Bool
    var paintModesEnabled: Bool
    var showsCaption: Bool = true
    @Binding var activeSetting: BonePaperStrokeSetting?
    var onSelectMode: (BonePaperTool) -> Void

    @State private var dragging = false
    @State private var pinned = false
    @State private var swallowNextTap = false

    private var isActive: Bool {
        pinned || activeSetting == .mode
    }

    private func highlightColor(for mode: BonePaperTool) -> Color {
        mode == .brushfill ? BonePaperChrome.brushfillSelected : BonePaperChrome.selected
    }

    private var captionText: String {
        switch fillMode {
        case .bucket: "bucket"
        case .brushfill: "brushfill"
        case .rectangle: "rect"
        case .circle: "circle"
        default: "bucket"
        }
    }

    private func isModeAllowed(_ mode: BonePaperTool) -> Bool {
        mode == .bucket || paintModesEnabled
    }

    var body: some View {
        let activeColor = highlightColor(for: fillMode)
        VStack(alignment: .leading, spacing: 1) {
            ZStack(alignment: .leading) {
                if isActive {
                    track
                        .offset(x: Self.side + Self.trackGap)
                }
                icon(activeColor: activeColor)
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
                    pinStrip()
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    pinStrip()
                }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { event in
                    handleTap(at: event.location)
                }
            )
            .onChange(of: activeSetting) { _, next in
                if next != .mode {
                    pinned = false
                    swallowNextTap = false
                }
            }
            .onChange(of: paintModesEnabled) { _, next in
                if !next, fillMode != .bucket {
                    fillMode = .bucket
                }
            }
            if showsCaption {
                Text(captionText)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected || isActive ? activeColor : Color.white)
                    .frame(width: Self.side)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captionText)
        .accessibilityAddTraits(.isButton)
    }

    private func icon(activeColor: Color) -> some View {
        ZStack {
            if selected {
                activeColor
            }
            BonePaperToolChipIcon(
                mode: fillMode,
                boxSide: Self.side,
                inset: (Self.side - 30) / 2,
                tintColor: .white
            )
        }
        .frame(width: Self.side, height: Self.side)
        .overlay {
            SubtoolCornerTriangle()
                .fill(Color.white)
        }
        .contentShape(Rectangle())
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

            HStack(spacing: BonePaperTrackStyle.chipGap) {
                ForEach(Self.modes, id: \.self) { mode in
                    let isSelectedMode = mode == fillMode
                    let allowed = isModeAllowed(mode)
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelectedMode ? highlightColor(for: mode) : BonePaperTrackStyle.unselectedChipFill)
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
                            tintColor: isSelectedMode ? .white : BonePaperTrackStyle.unselectedIconColor,
                            opacity: allowed ? 1 : 0.35
                        )
                    }
                    .frame(width: BonePaperTrackStyle.chipSide, height: BonePaperTrackStyle.chipSide)
                }
            }
            .padding(.horizontal, BonePaperTrackStyle.chipPadH)
        }
        .frame(width: Self.trackWidth, height: Self.side)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !dragging {
                    dragging = true
                    onSelectMode(fillMode)
                }
                activeSetting = .mode
                if let picked = modeAtTrackX(value.location.x), isModeAllowed(picked), picked != fillMode {
                    onSelectMode(picked)
                }
            }
            .onEnded { value in
                dragging = false
                if let picked = modeAtTrackX(value.location.x), isModeAllowed(picked) {
                    onSelectMode(picked)
                }
                if !pinned {
                    activeSetting = nil
                }
            }
    }

    private func modeAtTrackX(_ x: CGFloat) -> BonePaperTool? {
        let startX = Self.side + Self.trackGap + BonePaperTrackStyle.chipPadH
        guard let idx = BonePaperTrackStyle.chipIndex(
            atX: x,
            startX: startX,
            count: Self.modes.count
        ) else {
            return nil
        }
        return Self.modes[idx]
    }

    private func pinStrip() {
        pinned = true
        activeSetting = .mode
        swallowNextTap = true
        onSelectMode(fillMode)
    }

    private func handleTap(at location: CGPoint) {
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        let wasAlreadyActive = selected
        if pinned {
            let trackLeft = Self.side + Self.trackGap
            if location.x >= trackLeft {
                if let tapped = modeAtTrackX(location.x), isModeAllowed(tapped) {
                    onSelectMode(tapped)
                    pinned = false
                    activeSetting = nil
                }
                return
            }
            pinned = false
            activeSetting = nil
            return
        }
        onSelectMode(fillMode)
        if wasAlreadyActive {
            pinned = true
            activeSetting = .mode
        }
    }
}

enum BonePaperStrokeSetting: Equatable {
    case mode
    case size
    case opacity
    case eraser

    var label: String {
        switch self {
        case .mode: "bucket"
        case .size: "brush"
        case .opacity: "opacity"
        case .eraser: "erase"
        }
    }
}

struct BonePaperStrokePreview: View {
    var brushSize: CGFloat
    var opacity: CGFloat
    var color: Color
    var zoom: CGFloat
    var label: String
    var showsOpacity: Bool

    private static let width: CGFloat = 180
    private static let height: CGFloat = 70

    var body: some View {
        let screenStroke = max(brushSize * max(zoom, 0.01), 1)
        VStack(spacing: 4) {
            Text(previewLabel)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(.black)
            curve
                .stroke(
                    color.opacity(opacity),
                    style: StrokeStyle(lineWidth: screenStroke, lineCap: .round, lineJoin: .round)
                )
                .frame(width: Self.width, height: Self.height)
                .padding(screenStroke / 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    private var previewLabel: String {
        var text = "\(label) \(Int(brushSize.rounded()))"
        if showsOpacity {
            text += "  \(Int((opacity * 100).rounded()))%"
        }
        return text
    }

    private var curve: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: Self.height / 2))
        path.addCurve(
            to: CGPoint(x: Self.width, y: Self.height / 2),
            control1: CGPoint(x: Self.width / 3, y: 0),
            control2: CGPoint(x: Self.width * 2 / 3, y: Self.height)
        )
        return path
    }
}
