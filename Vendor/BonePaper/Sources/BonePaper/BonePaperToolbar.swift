import FlexColorPicker
import SwiftUI
import UIKit

enum BonePaperBrush {
    static let sizeRange: ClosedRange<CGFloat> = 4...48
    static let opacityRange: ClosedRange<CGFloat> = 0.05...1
}

enum BonePaperChrome {
    static let pad: CGFloat = 16
    static let leftRail: CGFloat = 75
    static let rightRail: CGFloat = 64
    static let tool: CGFloat = 44
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let selected = Color(red: 0x45 / 255, green: 0x96 / 255, blue: 1)
    static let apply = Color(red: 0x37 / 255, green: 0xAB / 255, blue: 0x22 / 255)

    static var railIconInset: CGFloat { (leftRail - tool) / 2 }

    /// Fill took the move chip's slot; pinch still pans.
    static let showsMoveTool = false

    /// iPhone 12 mini (`iPhone13,1`) and 13 mini (`iPhone14,4`): no room for the top chip.
    static var hidesTopChip: Bool {
        let id = machineIdentifier
        return id == "iPhone13,1" || id == "iPhone14,4"
    }

    private static var machineIdentifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            return sim
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                fatalError("BonePaper machine identifier missing")
            }
            return String(cString: base)
        }
    }

    static func fitInsets(safe: EdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: safe.top + pad,
            left: pad,
            bottom: safe.bottom + pad,
            right: safe.trailing + pad + rightRail
        )
    }

    static func chromeImage(_ name: String) -> UIImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        else {
            fatalError("BonePaper missing chrome/\(name).png")
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            fatalError("BonePaper could not read \(url.path)")
        }
        return image
    }
}

struct BonePaperBackButton: View {
    var onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .padding(.leading, BonePaperChrome.leftRail + 8)
        .padding(.top, 8)
    }
}

struct BonePaperUndoButton: View {
    var canUndo: Bool
    var onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            VStack(spacing: 1) {
                Image(uiImage: BonePaperChrome.chromeImage("skel_btn_undo"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                Text("undo")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
            }
            .opacity(canUndo ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }
}

struct BonePaperRedoButton: View {
    var canRedo: Bool
    var onRedo: () -> Void

    private static let purple = Color(red: 1, green: 0.35, blue: 0.72)

    var body: some View {
        Button(action: onRedo) {
            VStack(spacing: 1) {
                Image(uiImage: BonePaperChrome.chromeImage("skel_btn_undo").withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Self.purple)
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                Text("redo")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
            }
            .opacity(canRedo ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRedo)
        .accessibilityLabel("Redo")
    }
}

/// Android `drawable/check` — the fat Kurwa apply tick.
private struct KurwaCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 15.4142, y: 4.41421))
        path.addLine(to: CGPoint(x: 6, y: 13.8284))
        path.addLine(to: CGPoint(x: 0.585785, y: 8.41421))
        path.addLine(to: CGPoint(x: 3.41421, y: 5.58578))
        path.addLine(to: CGPoint(x: 6, y: 8.17157))
        path.addLine(to: CGPoint(x: 12.5858, y: 1.58578))
        path.closeSubpath()
        let scale = min(rect.width, rect.height) / 16
        let offset = CGSize(
            width: rect.minX + (rect.width - 16 * scale) / 2,
            height: rect.minY + (rect.height - 16 * scale) / 2
        )
        return path.applying(
            CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
        )
    }
}

struct BonePaperApply: View {
    var onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            KurwaCheck()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .frame(width: BonePaperChrome.rightRail, height: BonePaperChrome.rightRail)
                .background(BonePaperChrome.apply)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply")
    }
}

struct BonePaperStrokeControls: View {
    @Binding var tool: BonePaperTool
    @Binding var brushSize: CGFloat
    @Binding var eraserSize: CGFloat
    @Binding var opacity: CGFloat
    var canUndo: Bool
    var onUndo: () -> Void
    var canRedo: Bool
    var onRedo: () -> Void
    var color: Color
    var onSeeking: (Bool) -> Void

    @State private var activeSetting: BonePaperStrokeSetting?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if BonePaperChrome.showsMoveTool, !BonePaperChrome.hidesTopChip {
                        BonePaperPanChip(selected: tool == .pan) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                tool = .pan
                            }
                        }
                    }
                    if !BonePaperChrome.showsMoveTool, !BonePaperChrome.hidesTopChip {
                        BonePaperFillChip(selected: tool == .fill) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                tool = .fill
                            }
                        }
                    }
                    BonePaperRedoButton(canRedo: canRedo, onRedo: onRedo)
                    BonePaperUndoButton(canUndo: canUndo, onUndo: onUndo)
                    BonePaperDragControl(
                        setting: .size,
                        value: $brushSize,
                        range: BonePaperBrush.sizeRange,
                        color: color,
                        selected: tool == .pen,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .pen },
                        onSeeking: onSeeking
                    )
                    BonePaperDragControl(
                        setting: .opacity,
                        value: $opacity,
                        range: BonePaperBrush.opacityRange,
                        color: color,
                        selected: false,
                        activeSetting: $activeSetting,
                        onActivate: { if tool != .fill { tool = .pen } },
                        onSeeking: onSeeking
                    )
                    BonePaperDragControl(
                        setting: .eraser,
                        value: $eraserSize,
                        range: BonePaperBrush.sizeRange,
                        color: color,
                        selected: tool == .eraser,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .eraser },
                        onSeeking: onSeeking
                    )
                }
                .animation(nil, value: tool)
                .padding(.leading, BonePaperChrome.railIconInset)
                .padding(.bottom, BonePaperChrome.pad)
                .frame(minHeight: geo.size.height, alignment: .bottom)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

private struct BonePaperPanChip: View {
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background {
                    if selected {
                        BonePaperChrome.selected
                            .transition(.identity)
                    }
                }
            Text("move")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selected ? BonePaperChrome.selected : Color.white)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .transaction { $0.animation = nil }
        .accessibilityLabel("Move")
        .accessibilityAddTraits(.isButton)
    }
}

/// Android `drawable-xxxhdpi/kurwa_fill`.
private struct BonePaperFillChip: View {
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Image(uiImage: BonePaperChrome.chromeImage("kurwa_fill"))
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background {
                    if selected {
                        BonePaperChrome.selected
                            .transition(.identity)
                    }
                }
            Text("fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selected ? BonePaperChrome.selected : Color.white)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .transaction { $0.animation = nil }
        .accessibilityLabel("Fill")
        .accessibilityAddTraits(.isButton)
    }
}

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

private enum BonePaperStrokeSetting {
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

private struct BonePaperDragControl: View {
    var setting: BonePaperStrokeSetting
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>
    var color: Color
    var selected: Bool
    @Binding var activeSetting: BonePaperStrokeSetting?
    var onActivate: () -> Void
    var onSeeking: (Bool) -> Void

    private static let side: CGFloat = 44
    private static let trackWidth: CGFloat = 176
    private static let trackPadding: CGFloat = 12
    private static let trackGap: CGFloat = 8
    private static let space = "bonepaper.slider"

    @State private var dragStartValue: CGFloat?
    /// Seek bar stays out after a double tap or long press. A plain drag still closes it on release.
    @State private var pinned = false
    /// The tap that finishes a double tap or long press must not immediately close the bar.
    @State private var swallowNextTap = false

    private var isActive: Bool {
        pinned || activeSetting == setting
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
                    pinSeekBar()
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    pinSeekBar()
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    handleTap()
                }
            )
            .onChange(of: activeSetting) { _, next in
                if next != setting {
                    pinned = false
                    swallowNextTap = false
                }
            }
            Text(setting.label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selected || isActive ? BonePaperChrome.selected : Color.white)
                .frame(width: Self.side)
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
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
                let t = min(max((drag.location.x - valueStart) / valueWidth, 0), 1)
                let span = range.upperBound - range.lowerBound
                value = range.lowerBound + t * span
            }
            .onEnded { _ in
                dragStartValue = nil
                onSeeking(false)
                if !pinned {
                    activeSetting = nil
                }
            }
    }

    private func pinSeekBar() {
        pinned = true
        activeSetting = setting
        swallowNextTap = true
        onActivate()
    }

    private func handleTap() {
        onActivate()
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        if pinned {
            pinned = false
            activeSetting = nil
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

enum BonePaperColorStore {
    static let key = "bonepaper.custom_colors"

    static let presets: [String] = [
        "#E63836",
        "#FF9900",
        "#FCD936",
        "#7DB343",
        "#1F87E6",
        "#8F24AB",
        "#000000",
        "#9E9E9E",
        "#FFFFFF",
        "#FFE0B3",
        "#8C6E63",
        "#26C7D9",
        "#F58FB0"
    ]

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ hexes: [String]) {
        UserDefaults.standard.set(hexes, forKey: key)
    }

    static func hex(from color: UIColor) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            guard let converted = color.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            ) else {
                fatalError("BonePaperColorStore color is not RGB")
            }
            if !UIColor(cgColor: converted).getRed(&r, green: &g, blue: &b, alpha: &a) {
                fatalError("BonePaperColorStore converted color is not RGB")
            }
        }
        let ri = min(max(Int((r * 255).rounded()), 0), 255)
        let gi = min(max(Int((g * 255).rounded()), 0), 255)
        let bi = min(max(Int((b * 255).rounded()), 0), 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    static func color(from hex: String) -> Color {
        if hex.count != 7 || !hex.hasPrefix("#") {
            fatalError("BonePaperColorStore hex \(hex)")
        }
        let digits = hex.dropFirst()
        guard let value = Int(digits, radix: 16) else {
            fatalError("BonePaperColorStore hex \(hex)")
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

struct BonePaperColorStrip: View {
    @Binding var color: Color
    var onPick: () -> Void

    private static let swatch: CGFloat = 30
    private static let gap: CGFloat = 4

    @State private var extras: [String] = BonePaperColorStore.load()
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: Self.gap) {
            Button {
                showingPicker = true
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
                        .frame(width: 10, height: 10)
                }
                .frame(width: Self.swatch, height: Self.swatch)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(white: 0.45), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color picker")

            BonePaperPlainScroll {
                VStack(spacing: Self.gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Self.gap) {
                            ForEach(row, id: \.self) { hex in
                                swatchButton(hex)
                            }
                            if row.count == 1 {
                                Color.clear.frame(width: Self.swatch, height: Self.swatch)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: BonePaperChrome.rightRail)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("bone paper colors")
        .sheet(isPresented: $showingPicker) {
            BonePaperFlexColorPickerSheet(initial: UIColor(BonePaperColorStore.color(from: topHex))) { picked in
                let hex = BonePaperColorStore.hex(from: picked)
                color = BonePaperColorStore.color(from: hex)
                remember(hex)
                onPick()
                showingPicker = false
            }
        }
    }

    private var topHex: String {
        extras.first ?? BonePaperColorStore.presets[0]
    }

    private var swatches: [String] {
        extras + BonePaperColorStore.presets
    }

    private var rows: [[String]] {
        stride(from: 0, to: swatches.count, by: 2).map { index in
            Array(swatches[index..<min(index + 2, swatches.count)])
        }
    }

    private func swatchButton(_ hex: String) -> some View {
        let swatch = BonePaperColorStore.color(from: hex)
        let selected = BonePaperColorStore.hex(from: UIColor(color)) == hex
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(swatch)
            .frame(width: Self.swatch, height: Self.swatch)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.white : Color(white: 0.25), lineWidth: selected ? 3 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onTapGesture {
                color = swatch
                onPick()
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(.isButton)
    }

    private func remember(_ hex: String) {
        if swatches.contains(hex) {
            return
        }
        extras.insert(hex, at: 0)
        BonePaperColorStore.save(extras)
    }
}

public struct BonePaperColorRow: View {
    @Binding var color: Color

    @State private var extras: [String] = BonePaperColorStore.load()
    @State private var showingPicker = false

    public init(color: Binding<Color>) {
        _color = color
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                showingPicker = true
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
                .frame(width: 36, height: 36)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(white: 0.45), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color picker")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        swatchButton(hex)
                    }
                }
            }
        }
        .frame(height: 36)
        .sheet(isPresented: $showingPicker) {
            BonePaperFlexColorPickerSheet(initial: UIColor(color)) { picked in
                let hex = BonePaperColorStore.hex(from: picked)
                color = BonePaperColorStore.color(from: hex)
                remember(hex)
                showingPicker = false
            }
        }
    }

    private var swatches: [String] {
        extras + BonePaperColorStore.presets
    }

    private func swatchButton(_ hex: String) -> some View {
        let swatch = BonePaperColorStore.color(from: hex)
        let selected = BonePaperColorStore.hex(from: UIColor(color)) == hex
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(swatch)
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.white : Color(white: 0.25), lineWidth: selected ? 3 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onTapGesture {
                color = swatch
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(.isButton)
    }

    private func remember(_ hex: String) {
        if swatches.contains(hex) {
            return
        }
        extras.insert(hex, at: 0)
        BonePaperColorStore.save(extras)
    }
}

private struct BonePaperPlainScroll<Content: View>: UIViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BonePaperFillScrollView {
        let scroll = BonePaperFillScrollView()
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.automaticallyAdjustsScrollIndicatorInsets = false
        scroll.backgroundColor = .clear
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let host = UIHostingController(rootView: AnyView(content.ignoresSafeArea()))
        host.sizingOptions = .intrinsicContentSize
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        context.coordinator.host = host
        return scroll
    }

    func updateUIView(_ scroll: BonePaperFillScrollView, context: Context) {
        guard let host = context.coordinator.host else {
            fatalError("BonePaperPlainScroll missing host")
        }
        host.rootView = AnyView(content.ignoresSafeArea())
        host.view.invalidateIntrinsicContentSize()
        host.view.setNeedsLayout()
        // Keep the inserted custom color visible after the new intrinsic height reaches UIScrollView.
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else { return }
            scroll.layoutIfNeeded()
            scroll.setContentOffset(.zero, animated: false)
        }
    }

    final class Coordinator {
        var host: UIHostingController<AnyView>?
    }
}

final class BonePaperFillScrollView: UIScrollView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

struct BonePaperFlexColorPickerSheet: UIViewControllerRepresentable {
    var initial: UIColor
    var onApply: (UIColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onApply: onApply)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = DefaultColorPickerViewController()
        picker.selectedColor = initial
        picker.delegate = context.coordinator
        picker.title = "Color"
        picker.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: context.coordinator,
            action: #selector(Coordinator.cancel)
        )
        picker.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Apply",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.apply)
        )
        context.coordinator.picker = picker
        let nav = UINavigationController(rootViewController: picker)
        context.coordinator.navigation = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onApply = onApply
        context.coordinator.navigation = uiViewController
        if let picker = uiViewController.viewControllers.first as? DefaultColorPickerViewController {
            context.coordinator.picker = picker
            picker.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, ColorPickerDelegate {
        var onApply: (UIColor) -> Void
        weak var picker: DefaultColorPickerViewController?
        weak var navigation: UINavigationController?

        init(onApply: @escaping (UIColor) -> Void) {
            self.onApply = onApply
        }

        func colorPicker(
            _ colorPicker: ColorPickerController,
            confirmedColor: UIColor,
            usingControl: ColorControl
        ) {
            onApply(confirmedColor)
        }

        @objc func apply() {
            guard let picker else {
                fatalError("BonePaperFlexColorPickerSheet Apply with no picker")
            }
            onApply(picker.selectedColor)
        }

        @objc func cancel() {
            navigation?.dismiss(animated: true)
        }
    }
}
