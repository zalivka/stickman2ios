import FlexColorPicker
import SwiftUI
import UIKit

enum BonePaperBrush {
    static let sizeRange: ClosedRange<CGFloat> = 4...48
    static let opacityRange: ClosedRange<CGFloat> = 0.05...1
}

enum BonePaperChrome {
    static let pad: CGFloat = 16
    static let leftRail: CGFloat = 44
    static let rightRail: CGFloat = 64

    static func fitInsets(safe: EdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: safe.top + pad,
            left: safe.leading + pad + leftRail,
            bottom: safe.bottom + pad,
            right: safe.trailing + pad + rightRail
        )
    }
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
        .padding(.leading, BonePaperChrome.pad)
        .padding(.top, BonePaperChrome.pad)
    }
}

struct BonePaperApply: View {
    var onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: BonePaperChrome.rightRail, height: BonePaperChrome.rightRail)
                .background(Color(red: 0, green: 0xEC / 255, blue: 1))
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
    var color: Color
    var onSeeking: (Bool) -> Void

    @State private var activeSetting: BonePaperStrokeSetting?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BonePaperPanChip(selected: tool == .pan) {
                tool = .pan
            }
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
                onActivate: { tool = .pen },
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
        .padding(.leading, BonePaperChrome.pad)
        .padding(.bottom, BonePaperChrome.pad)
    }
}

private struct BonePaperPanChip: View {
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(selected ? Color(red: 0, green: 0xEC / 255, blue: 1) : Color.white))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pan")
    }
}

private enum BonePaperStrokeSetting {
    case size
    case opacity
    case eraser

    var label: String {
        switch self {
        case .size: "Size"
        case .opacity: "Opacity"
        case .eraser: "Eraser size"
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

    @State private var dragStartValue: CGFloat?

    private var isActive: Bool {
        activeSetting == setting
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
        ZStack(alignment: .leading) {
            if isActive {
                track
                    .offset(x: Self.side + Self.trackGap)
                    .transition(.opacity)
            }
            icon
                .gesture(drag)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        onActivate()
                    }
                )
        }
        .frame(
            width: isActive ? Self.side + Self.trackGap + Self.trackWidth : Self.side,
            height: Self.side,
            alignment: .leading
        )
        .animation(.easeOut(duration: 0.12), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(setting.label)
        .accessibilityValue(readout)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(selected ? Color(red: 0, green: 0xEC / 255, blue: 1) : Color.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            switch setting {
            case .size:
                let diameter = 6 + ratio * 22
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        if color == .white {
                            Circle().stroke(Color(white: 0.62), lineWidth: 1)
                        }
                    }
            case .opacity:
                Image(systemName: "drop.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color.opacity(value))
                    .overlay {
                        Image(systemName: "drop")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
            case .eraser:
                Image(systemName: "eraser.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(Circle())
    }

    private var track: some View {
        let lineWidth = Self.trackWidth - Self.trackPadding * 2
        let knobX = Self.trackPadding + ratio * lineWidth
        let bubbleWidth: CGFloat = 50
        let bubbleX = min(max(knobX - bubbleWidth / 2, 4), Self.trackWidth - bubbleWidth - 4)
        let knobColor = setting == .eraser ? Color.black : color
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

    @ViewBuilder
    private var trackLine: some View {
        if setting == .opacity {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.05), color],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        } else {
            Capsule()
                .fill(Color.black.opacity(0.22))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
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
                if drag.location.x < valueStart {
                    value = start
                    return
                }
                let valueWidth = Self.trackWidth - Self.trackPadding * 2
                let t = min(max((drag.location.x - valueStart) / valueWidth, 0), 1)
                let span = range.upperBound - range.lowerBound
                value = range.lowerBound + t * span
            }
            .onEnded { _ in
                activeSetting = nil
                dragStartValue = nil
                onSeeking(false)
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

    @State private var extras: [String] = BonePaperColorStore.load()
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 8) {
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

            BonePaperPlainScroll {
                VStack(spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        swatchButton(hex)
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
