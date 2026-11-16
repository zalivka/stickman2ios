import SwiftUI
import UIKit

struct BonePaperPipettePreview: View {
    var color: Color

    var body: some View {
        ZStack {
            Color.white
            Circle()
                .fill(color)
                .padding(12)
        }
        .frame(width: BonePaperChrome.rightRail, height: BonePaperChrome.rightRail)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BonePaperPipetteButton: View {
    var stage: BonePaperStage
    @Binding var color: Color
    @Binding var hover: Color?
    var onPick: () -> Void

    private static let side: CGFloat = 36

    var body: some View {
        Image(systemName: "eyedropper")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color(white: 0.15))
            .frame(width: Self.side, height: Self.side)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(white: 0.45), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(sample)
            .accessibilityLabel("Color pipette")
            .accessibilityAddTraits(.isButton)
    }

    private var sample: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                hover = stage.sampleColor(atWindow: value.location).map(Color.init)
            }
            .onEnded { value in
                if let picked = stage.sampleColor(atWindow: value.location) {
                    let hex = BonePaperColorStore.hex(from: picked)
                    color = BonePaperColorStore.color(from: hex)
                    BonePaperColorStore.remember(hex)
                    onPick()
                }
                stage.clearCursor()
                hover = nil
            }
    }
}

private enum BonePaperPaletteEntry: Hashable {
    case transparent
    case color(String)
}

private struct BonePaperTransparentSwatch: View {
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 4
            for row in 0..<4 {
                for column in 0..<4 {
                    let rect = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    let shade = (row + column).isMultiple(of: 2)
                        ? Color(white: 0.92)
                        : Color(white: 0.62)
                    context.fill(Path(rect), with: .color(shade))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct BonePaperColorStrip: View {
    @Binding var color: Color
    @Binding var activeSwatchBaseColor: Color
    @Binding var hover: Color?
    @Binding var activeTrack: BonePaperActiveSwatchTrack?
    var itemPalette: [String]
    var drawingConfig: BonePaperDrawingConfig
    var stage: BonePaperStage
    var onPick: (Color) -> Void
    var onPickTransparent: () -> Void
    var onSeekingBrightness: (Bool) -> Void
    var onFlashPreview: () -> Void

    private static let swatch: CGFloat = 36
    private static let gap: CGFloat = 4

    @State private var extras: [String] = BonePaperColorStore.load()
    @State private var pickerInitialColor: UIColor?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Self.gap) {
                HStack(spacing: Self.gap) {
                    BonePaperPipetteButton(
                        stage: stage,
                        color: $color,
                        hover: $hover,
                        onPick: {
                            activeTrack = nil
                            activeSwatchBaseColor = color
                            onPick(color)
                        }
                    )
                    colorPickerButton
                }

                BonePaperPlainScroll(onScroll: {
                    if activeTrack != nil {
                        activeTrack = nil
                    }
                }) {
                    VStack(spacing: Self.gap) {
                        ForEach(Array(topRows.enumerated()), id: \.offset) { _, row in
                            swatchRow(row)
                        }
                        if !normalizedItemPalette.isEmpty, !bottomRows.isEmpty {
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: Self.swatch * 2 + Self.gap, height: 1)
                                .padding(.vertical, 2)
                        }
                        ForEach(Array(bottomRows.enumerated()), id: \.offset) { _, row in
                            swatchRow(row)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: BonePaperChrome.rightRail, height: geo.size.height)
            .overlay(alignment: .topLeading) {
                BonePaperSwatchTrackOverlay(
                    activeTrack: $activeTrack,
                    screenHeight: geo.size.height,
                    onBrightnessChange: { baseUIColor, brightness, dragging in
                        activeSwatchBaseColor = Color(baseUIColor)
                        let updated = BonePaperSwatchTrackOverlay.color(base: baseUIColor, brightness: brightness)
                        color = Color(updated)
                        onSeekingBrightness(dragging)
                        if !dragging {
                            onPick(Color(baseUIColor))
                        }
                    },
                    onDismiss: {
                        activeTrack = nil
                        onSeekingBrightness(false)
                    }
                )
            }
        }
        .frame(width: BonePaperChrome.rightRail)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("bone paper colors")
        .onReceive(NotificationCenter.default.publisher(for: BonePaperColorStore.didChange)) { _ in
            extras = BonePaperColorStore.load()
        }
        .sheet(
            isPresented: Binding(
                get: { pickerInitialColor != nil },
                set: { if !$0 { pickerInitialColor = nil } }
            )
        ) {
            if let initial = pickerInitialColor {
                BonePaperFlexColorPickerSheet(initial: initial) { picked in
                    let hex = BonePaperColorStore.hex(from: picked)
                    let nextColor = BonePaperColorStore.color(from: hex)
                    color = nextColor
                    activeSwatchBaseColor = nextColor
                    remember(hex)
                    onPick(nextColor)
                    pickerInitialColor = nil
                }
            }
        }
    }

    private var colorPickerButton: some View {
        Button {
            activeTrack = nil
            let current = UIColor(color)
            pickerInitialColor = current.cgColor.alpha == 0 ? .black : current
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                Circle()
                    .fill(Color(white: 0.78))
                    .frame(width: 12, height: 12)
            }
            .frame(width: Self.swatch, height: Self.swatch)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(white: 0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color picker")
    }

    private var normalizedItemPalette: [String] {
        var result: [String] = []
        for raw in itemPalette {
            let hex = raw.uppercased()
            if BonePaperDrawingConfig.isValidHex(hex), !result.contains(hex) {
                result.append(hex)
            }
        }
        return result
    }

    private var topSwatches: [BonePaperPaletteEntry] {
        [.transparent] + normalizedItemPalette.map(BonePaperPaletteEntry.color)
    }

    private var bottomSwatches: [BonePaperPaletteEntry] {
        let used = Set(normalizedItemPalette)
        var rest: [String] = []
        for hex in extras + BonePaperColorStore.presets {
            let upper = hex.uppercased()
            if !used.contains(upper), !rest.contains(upper) {
                rest.append(upper)
            }
        }
        return rest.map(BonePaperPaletteEntry.color)
    }

    private var topRows: [[BonePaperPaletteEntry]] {
        let items = normalizedItemPalette.isEmpty ? (topSwatches + bottomSwatches) : topSwatches
        return Self.chunkRows(items)
    }

    private var bottomRows: [[BonePaperPaletteEntry]] {
        normalizedItemPalette.isEmpty ? [] : Self.chunkRows(bottomSwatches)
    }

    private static func chunkRows(_ entries: [BonePaperPaletteEntry]) -> [[BonePaperPaletteEntry]] {
        stride(from: 0, to: entries.count, by: 2).map { index in
            Array(entries[index..<min(index + 2, entries.count)])
        }
    }

    private func swatchRow(_ row: [BonePaperPaletteEntry]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(row, id: \.self) { entry in
                swatchButton(entry)
            }
            if row.count == 1 {
                Color.clear.frame(width: Self.swatch, height: Self.swatch)
            }
        }
    }

    @ViewBuilder
    private func swatchButton(_ entry: BonePaperPaletteEntry) -> some View {
        let isTransparent = UIColor(color).cgColor.alpha == 0
        switch entry {
        case .transparent:
            let selected = isTransparent
            BonePaperTransparentSwatch()
                .frame(width: Self.swatch, height: Self.swatch)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(white: 0.25), lineWidth: 1)
                }
                .overlay {
                    if selected {
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 1)
                            .background(Circle().fill(Color.white))
                            .frame(width: 10, height: 10)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .onTapGesture {
                    activeTrack = nil
                    color = .clear
                    onPickTransparent()
                }
                .onLongPressGesture(minimumDuration: 0.45) {
                    activeTrack = nil
                    BonePaperHexToast.showMessage("Transparent")
                }
                .accessibilityLabel("Transparent")
                .accessibilityAddTraits(.isButton)

        case .color(let hex):
            let swatchColor = BonePaperColorStore.color(from: hex)
            let swatchUIColor = UIColor(swatchColor)
            let activeBaseHex = BonePaperColorStore.hex(from: UIColor(activeSwatchBaseColor))
            let currentHex = isTransparent ? "" : BonePaperColorStore.hex(from: UIColor(color))
            let selected = !isTransparent && (currentHex == hex || (activeBaseHex == hex && BonePaperDrawingConfig.hueKey(for: UIColor(color)) == BonePaperDrawingConfig.hueKey(for: swatchUIColor)))
            let marks = drawingConfig.colorBrightnesses(for: swatchUIColor)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(swatchColor)
                .frame(width: Self.swatch, height: Self.swatch)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(white: 0.25), lineWidth: 1)
                }
                .overlay {
                    if selected {
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 1)
                            .background(Circle().fill(Color.white))
                            .frame(width: 10, height: 10)
                    }
                }
                .overlay {
                    BonePaperColorSwatchGestureView(
                        hex: hex,
                        baseColor: swatchUIColor,
                        currentColor: UIColor(color),
                        marks: marks,
                        activeTrack: $activeTrack,
                        onSelectBase: { base in
                            let next = Color(base)
                            activeSwatchBaseColor = next
                            color = next
                            onPick(next)
                        },
                        onBrightnessChange: { base, brightness, dragging in
                            let baseSw = Color(base)
                            activeSwatchBaseColor = baseSw
                            let updated = BonePaperSwatchTrackOverlay.color(base: base, brightness: brightness)
                            color = Color(updated)
                            onSeekingBrightness(dragging)
                            if !dragging {
                                onPick(baseSw)
                            }
                        },
                        onResetFullBrightness: { base in
                            let baseSw = Color(base)
                            activeSwatchBaseColor = baseSw
                            let full = BonePaperSwatchTrackOverlay.color(base: base, brightness: 1.0)
                            color = Color(full)
                            onPick(baseSw)
                            onFlashPreview()
                            BonePaperHexToast.showMessage("Brightness 100%")
                        },
                        onLongPress: { base in
                            let current = UIColor(color)
                            let seed: UIColor
                            if !isTransparent, BonePaperDrawingConfig.hueKey(for: current) == BonePaperDrawingConfig.hueKey(for: base) {
                                seed = current
                            } else {
                                seed = base
                            }
                            pickerInitialColor = seed
                        }
                    )
                }
                .accessibilityLabel(hex)
                .accessibilityAddTraits(.isButton)
        }
    }

    private func remember(_ hex: String) {
        BonePaperColorStore.remember(hex)
        extras = BonePaperColorStore.load()
    }
}
