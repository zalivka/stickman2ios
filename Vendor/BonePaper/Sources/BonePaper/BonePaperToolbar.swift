import SwiftUI

enum BonePaperBrush {
    static let sizeRange: ClosedRange<CGFloat> = 4...48
    static let opacityRange: ClosedRange<CGFloat> = 0.05...1
}

enum BonePaperReveal {
    case none
    case color
}

struct BonePaperBackUndo: View {
    var canUndo: Bool
    var onBack: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canUndo ? Color.black : Color.black.opacity(0.28))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .accessibilityLabel("Undo")
        }
        .padding(.leading, 8)
        .padding(.top, 8)
    }
}

struct BonePaperApplyTools: View {
    @Binding var tool: BonePaperTool
    @Binding var color: Color
    @Binding var reveal: BonePaperReveal
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button(action: onApply) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 0, green: 0xEC / 255, blue: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply")

            toolButton(system: "pencil.tip", selected: tool == .pen, label: "Brush") {
                tool = .pen
                reveal = .none
            }
            toolButton(system: "arrow.up.and.down.and.arrow.left.and.right", selected: tool == .pan, label: "Pan") {
                tool = .pan
                reveal = .none
            }
            toolButton(system: "eraser", selected: tool == .eraser, label: "Eraser") {
                tool = .eraser
                reveal = .none
            }
            HStack(alignment: .center, spacing: 10) {
                if reveal == .color {
                    BonePaperPalette(color: $color) { reveal = .none }
                }
                Button {
                    reveal = reveal == .color ? .none : .color
                } label: {
                    Circle()
                        .fill(color)
                        .overlay {
                            if color == .white {
                                Circle().stroke(Color(white: 0.78), lineWidth: 1)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                        .background(reveal == .color ? Color.white : Color(white: 0.92))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
            }
        }
        .frame(minWidth: 64)
        .padding(.trailing, 0)
        .padding(.top, 0)
    }

    private func toolButton(system: String, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(selected ? Color.white : Color(white: 0.92))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct BonePaperStrokeControls: View {
    @Binding var brushSize: CGFloat
    @Binding var opacity: CGFloat
    var color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            BonePaperWidthSeek(value: $brushSize, color: color)
                .frame(width: 32, height: 180)
            BonePaperOpacitySeek(value: $opacity, color: color)
                .frame(width: 150, height: 28)
                .padding(.bottom, 8)
        }
        .padding(.leading, 12)
        .padding(.bottom, 16)
    }
}

struct BonePaperWidthSeek: View {
    @Binding var value: CGFloat
    var color: Color

    private static let minTrack: CGFloat = 1
    private static let maxTrack: CGFloat = 12
    private static let thumbRadius: CGFloat = 7
    private static let inner = Color(red: 1, green: 0xF7 / 255, blue: 0xE8 / 255)

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let ratio = Self.ratio(value)
            Canvas { ctx, size in
                var wedge = Path()
                let cx = size.width / 2
                wedge.move(to: CGPoint(x: cx - Self.minTrack / 2, y: size.height))
                wedge.addLine(to: CGPoint(x: cx + Self.minTrack / 2, y: size.height))
                wedge.addLine(to: CGPoint(x: cx + Self.maxTrack / 2, y: 0))
                wedge.addLine(to: CGPoint(x: cx - Self.maxTrack / 2, y: 0))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(color))
                let y = size.height * (1 - ratio)
                let center = CGPoint(x: cx, y: y)
                ctx.fill(Path(ellipseIn: Self.rect(center, Self.thumbRadius)), with: .color(color))
                ctx.fill(
                    Path(ellipseIn: Self.rect(center, Self.thumbRadius * 2 / 3)),
                    with: .color(Self.inner)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let t = 1 - min(max(drag.location.y / h, 0), 1)
                    value = BonePaperBrush.sizeRange.lowerBound
                        + t * (BonePaperBrush.sizeRange.upperBound - BonePaperBrush.sizeRange.lowerBound)
                }
            )
            .accessibilityLabel("Width")
            .accessibilityValue("\(Int(value.rounded()))")
            .frame(width: w, height: h)
        }
    }

    private static func ratio(_ value: CGFloat) -> CGFloat {
        let span = BonePaperBrush.sizeRange.upperBound - BonePaperBrush.sizeRange.lowerBound
        return (value - BonePaperBrush.sizeRange.lowerBound) / span
    }

    private static func rect(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

struct BonePaperOpacitySeek: View {
    @Binding var value: CGFloat
    var color: Color

    private static let inner = Color(red: 1, green: 0xF7 / 255, blue: 0xE8 / 255)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let t = Self.ratio(value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.05), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 5)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle()
                            .fill(Self.inner)
                            .padding(2)
                    }
                    .offset(x: t * (w - 14))
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let u = min(max(drag.location.x / w, 0), 1)
                    value = BonePaperBrush.opacityRange.lowerBound
                        + u * (BonePaperBrush.opacityRange.upperBound - BonePaperBrush.opacityRange.lowerBound)
                }
            )
            .accessibilityLabel("Opacity")
        }
    }

    private static func ratio(_ value: CGFloat) -> CGFloat {
        let span = BonePaperBrush.opacityRange.upperBound - BonePaperBrush.opacityRange.lowerBound
        return (value - BonePaperBrush.opacityRange.lowerBound) / span
    }
}

struct BonePaperPalette: View {
    @Binding var color: Color
    var onPick: () -> Void

    private static let row1: [Color] = [
        Color(red: 0.90, green: 0.22, blue: 0.21),
        Color(red: 1.00, green: 0.60, blue: 0.00),
        Color(red: 0.99, green: 0.85, blue: 0.21),
        Color(red: 0.49, green: 0.70, blue: 0.26),
        Color(red: 0.12, green: 0.53, blue: 0.90),
        Color(red: 0.56, green: 0.14, blue: 0.67)
    ]
    private static let row2: [Color] = [
        .black,
        Color(white: 0.62),
        .white,
        Color(red: 1.00, green: 0.88, blue: 0.70),
        Color(red: 0.55, green: 0.43, blue: 0.39),
        Color(red: 0.15, green: 0.78, blue: 0.85),
        Color(red: 0.96, green: 0.56, blue: 0.69)
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                wheelChip
                ForEach(Array(Self.row1.enumerated()), id: \.offset) { _, swatch in
                    swatchButton(swatch)
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(Self.row2.enumerated()), id: \.offset) { _, swatch in
                    swatchButton(swatch)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }

    private var wheelChip: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    )
                )
            Circle()
                .fill(Color(white: 0.92))
                .frame(width: 10, height: 10)
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.6)
                .opacity(0.02)
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private func swatchButton(_ swatch: Color) -> some View {
        Button {
            color = swatch
            onPick()
        } label: {
            Circle()
                .fill(swatch)
                .frame(width: 28, height: 28)
                .overlay {
                    if swatch == .white {
                        Circle().stroke(Color(white: 0.78), lineWidth: 1)
                    }
                }
                .overlay {
                    if colorsMatch(color, swatch) {
                        Circle().stroke(Color.black, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        UIColor(a).cgColor.components == UIColor(b).cgColor.components
    }
}
