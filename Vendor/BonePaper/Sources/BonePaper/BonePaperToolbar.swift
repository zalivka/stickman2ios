import SwiftUI

enum BonePaperBrush {
    static let sizes: [CGFloat] = [4, 8, 14, 22, 32, 48]

    static func dot(_ size: CGFloat) -> CGFloat {
        6 + (size / sizes.last!) * 16
    }

    static func railDot(_ size: CGFloat) -> CGFloat {
        3 + (size / sizes.last!) * 18
    }
}

enum BonePaperReveal {
    case none
    case penSize
    case eraserSize
    case color
}

struct BonePaperDrawTools: View {
    @Binding var tool: BonePaperTool
    @Binding var color: Color
    @Binding var penSize: CGFloat
    @Binding var eraserSize: CGFloat
    @Binding var reveal: BonePaperReveal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reveal == .penSize {
                BonePaperSizeRail(brushSize: $penSize) { reveal = .none }
            }
            if reveal == .eraserSize {
                BonePaperSizeRail(brushSize: $eraserSize) { reveal = .none }
            }
            if reveal == .color {
                BonePaperPalette(color: $color) { reveal = .none }
            }
            HStack(spacing: 10) {
                BonePaperWidthTool(
                    system: "pencil.tip",
                    accessibilityName: "Brush",
                    selected: tool == .pen || reveal == .penSize,
                    size: penSize
                ) {
                    tool = .pen
                    reveal = .none
                } onLongPress: {
                    tool = .pen
                    reveal = .penSize
                }
                BonePaperWidthTool(
                    system: "eraser",
                    accessibilityName: "Eraser",
                    selected: tool == .eraser || reveal == .eraserSize,
                    size: eraserSize
                ) {
                    tool = .eraser
                    reveal = .none
                } onLongPress: {
                    tool = .eraser
                    reveal = .eraserSize
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
        .padding(.leading, 12)
        .padding(.bottom, 16)
    }
}

struct BonePaperWidthTool: View {
    var system: String
    var accessibilityName: String
    var selected: Bool
    var size: CGFloat
    var onTap: () -> Void
    var onLongPress: () -> Void

    @State private var ignoreTap = false

    var body: some View {
        Button {
            if ignoreTap {
                ignoreTap = false
                return
            }
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                Circle()
                    .fill(Color.black)
                    .frame(width: BonePaperBrush.dot(size), height: BonePaperBrush.dot(size))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(selected ? Color.white : Color(white: 0.92))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                ignoreTap = true
                onLongPress()
            }
        )
        .accessibilityLabel(accessibilityName)
        .accessibilityHint("Long press to choose width")
    }
}

struct BonePaperHistoryButtons: View {
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            historyButton(system: "arrow.uturn.backward", enabled: canUndo, action: onUndo)
            historyButton(system: "arrow.uturn.forward", enabled: canRedo, action: onRedo)
        }
        .padding(.trailing, 12)
        .padding(.bottom, 16)
    }

    private func historyButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Color.black : Color.black.opacity(0.28))
                .frame(width: 44, height: 44)
                .background(Color(white: 0.92))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct BonePaperSizeRail: View {
    @Binding var brushSize: CGFloat
    var onPick: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(BonePaperBrush.sizes, id: \.self) { size in
                Button {
                    brushSize = size
                    onPick()
                } label: {
                    Circle()
                        .fill(Color.black)
                        .frame(width: BonePaperBrush.railDot(size), height: BonePaperBrush.railDot(size))
                        .frame(width: 36, height: 36)
                        .background(brushSize == size ? Color.white : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Size \(Int(size))")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(white: 0.92))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
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
