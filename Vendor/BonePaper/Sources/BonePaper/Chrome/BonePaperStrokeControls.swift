import SwiftUI
import UIKit

struct BonePaperStrokeControls: View {
    @Binding var tool: BonePaperTool
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
    var onToggleFillMode: () -> Void
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
                    if isPad {
                        bucketSingleChip
                        brushfillSingleChip
                    } else {
                        fillToggleChip
                    }
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

    private var bucketSingleChip: some View {
        BonePaperSingleFillChip(
            mode: .bucket,
            selected: tool == .bucket
        ) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                fillMode = .bucket
                tool = .bucket
            }
        }
    }

    private var brushfillSingleChip: some View {
        BonePaperSingleFillChip(
            mode: .brushfill,
            selected: tool == .brushfill
        ) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if UIColor(color).cgColor.alpha == 0 {
                    onToggleFillMode()
                } else {
                    fillMode = .brushfill
                    tool = .brushfill
                }
            }
        }
    }

    private var fillToggleChip: some View {
        BonePaperFillChip(
            selected: tool == .bucket || tool == .brushfill,
            fillMode: fillMode,
            showsCaption: isPad,
            onSelect: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if UIColor(color).cgColor.alpha == 0 {
                        fillMode = .bucket
                    }
                    tool = fillMode
                }
            },
            onToggleMode: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    onToggleFillMode()
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
            selected: tool == .pen,
            enabled: brushAndOpacityEnabled,
            showsCaption: isPad,
            activeSetting: $activeSetting,
            onActivate: { tool = .pen },
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
                if tool != .bucket, tool != .brushfill {
                    tool = .pen
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

/// Top-right white corner triangle indicating a long-press subtool (`fillButtonBackground` on Android).
private struct SubtoolCornerTriangle: Shape {
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

/// Standalone Bucket or Brushfill button used on iPad where vertical rail space allows separate buttons.
private struct BonePaperSingleFillChip: View {
    var mode: BonePaperTool
    var selected: Bool
    var onSelect: () -> Void

    private var isBrushfill: Bool {
        mode == .brushfill
    }

    private var activeColor: Color {
        isBrushfill ? BonePaperChrome.brushfillSelected : BonePaperChrome.selected
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(uiImage: BonePaperChrome.chromeImage(
                isBrushfill ? "kurwa_fill" : "vector_flood_unactivated"
            ))
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
            .background {
                if selected {
                    activeColor
                        .transition(.identity)
                }
            }
            Text(isBrushfill ? "brushfill" : "bucket")
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? activeColor : Color.white)
                .frame(width: BonePaperChrome.tool)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .transaction { $0.animation = nil }
        .accessibilityLabel(isBrushfill ? "Brushfill" : "Bucket")
        .accessibilityAddTraits(.isButton)
    }
}

/// Bucket (`vector_flood_unactivated`) / Brushfill (`kurwa_fill`) toggle chip.
private struct BonePaperFillChip: View {
    var selected: Bool
    var fillMode: BonePaperTool
    var showsCaption: Bool = true
    var onSelect: () -> Void
    var onToggleMode: () -> Void

    private var isBrushfill: Bool {
        fillMode == .brushfill
    }

    private var activeColor: Color {
        isBrushfill ? BonePaperChrome.brushfillSelected : BonePaperChrome.selected
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(uiImage: BonePaperChrome.chromeImage(
                isBrushfill ? "kurwa_fill" : "vector_flood_unactivated"
            ))
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
            .background {
                if selected {
                    activeColor
                        .transition(.identity)
                }
            }
            .overlay {
                SubtoolCornerTriangle()
                    .fill(Color.white)
            }
            if showsCaption {
                Text(isBrushfill ? "brushfill" : "bucket")
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? activeColor : Color.white)
                    .frame(width: BonePaperChrome.tool)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            onToggleMode()
        }
        .transaction { $0.animation = nil }
        .accessibilityLabel(isBrushfill ? "Brushfill" : "Bucket")
        .accessibilityAddTraits(.isButton)
    }
}

enum BonePaperStrokeSetting: Equatable {
    case size
    case opacity
    case eraser

    var label: String {
        switch self {
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
