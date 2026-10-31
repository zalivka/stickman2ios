import FlexColorPicker
import SwiftUI
import UIKit

enum BonePaperBrush {
    static let sizeRange: ClosedRange<CGFloat> = 1...48
    static let opacityRange: ClosedRange<CGFloat> = 0.01...1
}

public struct BonePaperDrawingConfig: Codable, Equatable, Sendable {
    public static let maxSliderMarks = 4
    public static let maxPaletteColors = 16

    public var palette: [String]
    public var brushSizes: [CGFloat]
    public var eraserSizes: [CGFloat]
    public var opacities: [CGFloat]
    public var colorBrightnesses: [String: [CGFloat]]

    private enum CodingKeys: String, CodingKey {
        case palette
        case brushSizes
        case eraserSizes
        case opacities
        case colorBrightnesses
    }

    public init(
        palette: [String] = [],
        brushSizes: [CGFloat] = [],
        eraserSizes: [CGFloat] = [],
        opacities: [CGFloat] = [],
        colorBrightnesses: [String: [CGFloat]] = [:]
    ) {
        self.palette = palette
        self.brushSizes = brushSizes
        self.eraserSizes = eraserSizes
        self.opacities = opacities
        self.colorBrightnesses = colorBrightnesses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        palette = try container.decodeIfPresent([String].self, forKey: .palette) ?? []
        brushSizes = try container.decodeIfPresent([CGFloat].self, forKey: .brushSizes) ?? []
        eraserSizes = try container.decodeIfPresent([CGFloat].self, forKey: .eraserSizes) ?? []
        opacities = try container.decodeIfPresent([CGFloat].self, forKey: .opacities) ?? []
        colorBrightnesses = try container.decodeIfPresent([String: [CGFloat]].self, forKey: .colorBrightnesses) ?? [:]
    }

    public var isEmpty: Bool {
        palette.isEmpty && brushSizes.isEmpty && eraserSizes.isEmpty && opacities.isEmpty && colorBrightnesses.isEmpty
    }

    public func colorBrightnesses(for color: UIColor) -> [CGFloat] {
        guard let key = Self.hueKey(for: color) else { return [] }
        return colorBrightnesses[key] ?? []
    }

    public static func hueKey(for color: UIColor) -> String? {
        guard let hsb = hsbComponents(of: color) else { return nil }
        let satPct = Int((hsb.saturation * 100).rounded())
        if satPct == 0 {
            return "0:0"
        }
        var hueDeg = Int((hsb.hue * 360).rounded()) % 360
        if hueDeg < 0 {
            hueDeg += 360
        }
        return "\(hueDeg):\(satPct)"
    }

    static func hsbComponents(of color: UIColor) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)? {
        if color.cgColor.alpha == 0 {
            return nil
        }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return (h, s, b)
        }
        guard let converted = color.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ) else {
            return nil
        }
        if UIColor(cgColor: converted).getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return (h, s, b)
        }
        return nil
    }

    public func sanitized() -> BonePaperDrawingConfig {
        var cleanPalette: [String] = []
        for raw in palette {
            let hex = raw.uppercased()
            guard Self.isValidHex(hex), !cleanPalette.contains(hex) else { continue }
            cleanPalette.append(hex)
            if cleanPalette.count == Self.maxPaletteColors { break }
        }
        var cleanBrightnesses: [String: [CGFloat]] = [:]
        for (key, vals) in colorBrightnesses where !key.isEmpty {
            let cleaned = Self.cleanOpacities(vals)
            if !cleaned.isEmpty {
                cleanBrightnesses[key] = cleaned
            }
        }
        return BonePaperDrawingConfig(
            palette: cleanPalette,
            brushSizes: Self.cleanSizes(brushSizes),
            eraserSizes: Self.cleanSizes(eraserSizes),
            opacities: Self.cleanOpacities(opacities),
            colorBrightnesses: cleanBrightnesses
        )
    }

    public mutating func recordPenOrFill(colorHex: String?, brushSize: CGFloat?, opacity: CGFloat) {
        if let rawHex = colorHex {
            let hex = rawHex.uppercased()
            if Self.isValidHex(hex) {
                palette.removeAll { $0 == hex }
                palette.insert(hex, at: 0)
                if palette.count > Self.maxPaletteColors {
                    palette.removeLast(palette.count - Self.maxPaletteColors)
                }
            }
        }
        if let brushSize {
            let sizeMark = Self.clampSize(brushSize)
            brushSizes.removeAll { abs($0 - sizeMark) <= 0.001 }
            brushSizes.insert(sizeMark, at: 0)
            if brushSizes.count > Self.maxSliderMarks {
                brushSizes.removeLast(brushSizes.count - Self.maxSliderMarks)
            }
        }
        let opacityMark = Self.clampOpacity(opacity)
        opacities.removeAll { abs($0 - opacityMark) <= 0.001 }
        opacities.insert(opacityMark, at: 0)
        if opacities.count > Self.maxSliderMarks {
            opacities.removeLast(opacities.count - Self.maxSliderMarks)
        }
    }

    public mutating func recordColorBrightness(baseColor: UIColor, activeColor: UIColor) {
        guard let key = Self.hueKey(for: baseColor),
              let activeHSB = Self.hsbComponents(of: activeColor) else {
            return
        }
        let brightnessMark = Self.clampOpacity(activeHSB.brightness)
        var list = colorBrightnesses[key] ?? []
        list.removeAll { abs($0 - brightnessMark) <= 0.001 }
        list.insert(brightnessMark, at: 0)
        if list.count > Self.maxSliderMarks {
            list.removeLast(list.count - Self.maxSliderMarks)
        }
        colorBrightnesses[key] = list
    }

    public mutating func recordEraser(eraserSize: CGFloat) {
        let sizeMark = Self.clampSize(eraserSize)
        eraserSizes.removeAll { abs($0 - sizeMark) <= 0.001 }
        eraserSizes.insert(sizeMark, at: 0)
        if eraserSizes.count > Self.maxSliderMarks {
            eraserSizes.removeLast(eraserSizes.count - Self.maxSliderMarks)
        }
    }

    static func clampSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 14 }
        let rounded = CGFloat(Int(value.rounded()))
        return min(max(rounded, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
    }

    static func clampOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let rounded = CGFloat((value * 100).rounded()) / 100
        return min(max(rounded, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
    }

    static func isValidHex(_ hex: String) -> Bool {
        guard hex.count == 7, hex.hasPrefix("#") else { return false }
        return Int(hex.dropFirst(), radix: 16) != nil
    }

    private static func cleanSizes(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for v in values where v.isFinite {
            let clamped = clampSize(v)
            if !result.contains(clamped) {
                result.append(clamped)
                if result.count == maxSliderMarks { break }
            }
        }
        return result
    }

    private static func cleanOpacities(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for v in values where v.isFinite {
            let clamped = clampOpacity(v)
            if !result.contains(clamped) {
                result.append(clamped)
                if result.count == maxSliderMarks { break }
            }
        }
        return result
    }
}

enum BonePaperToolStore {
    private static let brushSizeKey = "bonepaper.brush_size"
    private static let eraserSizeKey = "bonepaper.eraser_size"
    private static let opacityKey = "bonepaper.opacity"
    private static let colorKey = "bonepaper.color"
    private static let fallbackConfigKey = "bonepaper.fallback_drawing_config"
    private static let clearToken = "CLEAR"

    static var brushSize: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: brushSizeKey) != nil else { return 14 }
            let val = CGFloat(UserDefaults.standard.double(forKey: brushSizeKey))
            guard val.isFinite else { return 14 }
            return min(max(val, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: brushSizeKey)
        }
    }

    static var eraserSize: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: eraserSizeKey) != nil else { return 14 }
            let val = CGFloat(UserDefaults.standard.double(forKey: eraserSizeKey))
            guard val.isFinite else { return 14 }
            return min(max(val, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: eraserSizeKey)
        }
    }

    static var opacity: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: opacityKey) != nil else { return 1 }
            let val = CGFloat(UserDefaults.standard.double(forKey: opacityKey))
            guard val.isFinite else { return 1 }
            return min(max(val, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: opacityKey)
        }
    }

    static var color: Color {
        get {
            guard let stored = UserDefaults.standard.string(forKey: colorKey) else {
                return .black
            }
            if stored == clearToken {
                return .clear
            }
            let upper = stored.uppercased()
            guard BonePaperDrawingConfig.isValidHex(upper) else {
                return .black
            }
            return BonePaperColorStore.color(from: upper)
        }
        set {
            let uiColor = UIColor(newValue)
            if uiColor.cgColor.alpha == 0 {
                UserDefaults.standard.set(clearToken, forKey: colorKey)
            } else {
                UserDefaults.standard.set(BonePaperColorStore.hex(from: uiColor), forKey: colorKey)
            }
        }
    }

    static var fallbackConfig: BonePaperDrawingConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: fallbackConfigKey),
                  let decoded = try? JSONDecoder().decode(BonePaperDrawingConfig.self, from: data) else {
                return BonePaperDrawingConfig()
            }
            return decoded.sanitized()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.sanitized()) {
                UserDefaults.standard.set(data, forKey: fallbackConfigKey)
            }
        }
    }
}

enum BonePaperChrome {
    static let pad: CGFloat = 16
    static let leftRail: CGFloat = 75
    static let rightRail: CGFloat = 76
    static let tool: CGFloat = 44
    static let pane = Color(red: 0x24 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let selected = Color(red: 0x45 / 255, green: 0x96 / 255, blue: 1)
    static let brushfillSelected = Color(red: 1, green: 0x59 / 255, blue: 0xB8 / 255)
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

    static func fitInsets(safe: EdgeInsets, topClearance: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: topClearance + pad,
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
    @Binding var fillMode: BonePaperTool
    @Binding var brushSize: CGFloat
    @Binding var eraserSize: CGFloat
    @Binding var opacity: CGFloat
    @Binding var activeSetting: BonePaperStrokeSetting?
    var brushMarks: [CGFloat]
    var opacityMarks: [CGFloat]
    var eraserMarks: [CGFloat]
    var canUndo: Bool
    var onUndo: () -> Void
    var canRedo: Bool
    var onRedo: () -> Void
    var color: Color
    var onToggleFillMode: () -> Void
    var onSeeking: (Bool) -> Void
    var onFlashPreview: () -> Void

    private var brushAndOpacityEnabled: Bool {
        UIColor(color).cgColor.alpha > 0
    }

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
                        if UIDevice.current.userInterfaceIdiom == .pad {
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
                        } else {
                            BonePaperFillChip(
                                selected: tool == .bucket || tool == .brushfill,
                                fillMode: fillMode,
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
                    }
                    BonePaperRedoButton(canRedo: canRedo, onRedo: onRedo)
                    BonePaperUndoButton(canUndo: canUndo, onUndo: onUndo)
                    BonePaperDragControl(
                        setting: .size,
                        value: $brushSize,
                        range: BonePaperBrush.sizeRange,
                        marks: brushMarks,
                        color: color,
                        selected: tool == .pen,
                        enabled: brushAndOpacityEnabled,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .pen },
                        onSeeking: onSeeking,
                        onFlashPreview: onFlashPreview
                    )
                    BonePaperDragControl(
                        setting: .opacity,
                        value: $opacity,
                        range: BonePaperBrush.opacityRange,
                        marks: opacityMarks,
                        color: color,
                        selected: false,
                        enabled: brushAndOpacityEnabled,
                        activeSetting: $activeSetting,
                        onActivate: {
                            if tool != .bucket, tool != .brushfill {
                                tool = .pen
                            }
                        },
                        onSeeking: onSeeking,
                        onFlashPreview: onFlashPreview
                    )
                    BonePaperDragControl(
                        setting: .eraser,
                        value: $eraserSize,
                        range: BonePaperBrush.sizeRange,
                        marks: eraserMarks,
                        color: color,
                        selected: tool == .eraser,
                        enabled: true,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .eraser },
                        onSeeking: onSeeking,
                        onFlashPreview: onFlashPreview
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
            Text(isBrushfill ? "brushfill" : "bucket")
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? activeColor : Color.white)
                .frame(width: BonePaperChrome.tool)
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

private struct BonePaperDragControl: View {
    var setting: BonePaperStrokeSetting
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>
    var marks: [CGFloat]
    var color: Color
    var selected: Bool
    var enabled: Bool
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
            Text(setting.label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(selected || isActive ? BonePaperChrome.selected : Color.white)
                .frame(width: Self.side)
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
    static let didChange = Notification.Name("bonepaper.custom_colors")

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

    /// Inserts `hex` at the front of the custom list. Presets and colours already stored are left as they are.
    static func remember(_ hex: String) {
        var extras = load()
        if extras.contains(hex) || presets.contains(hex) {
            return
        }
        extras.insert(hex, at: 0)
        save(extras)
        NotificationCenter.default.post(name: didChange, object: nil)
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

enum BonePaperHexToast {
    private static var label: UILabel?
    private static var hide: DispatchWorkItem?

    static func show(_ hex: String) {
        showMessage(hex)
    }

    static func showMessage(_ text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else {
            fatalError("BonePaperHexToast with no window")
        }
        let label = self.label ?? UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.textAlignment = .center
        label.layer.cornerRadius = 16
        label.clipsToBounds = true
        let textWidth = (text as NSString).size(withAttributes: [.font: label.font as Any]).width
        label.bounds = CGRect(x: 0, y: 0, width: textWidth + 28, height: 32)
        label.center = CGPoint(x: window.bounds.midX, y: window.safeAreaInsets.top + 88)
        label.alpha = 1
        if label.superview !== window {
            window.addSubview(label)
        }
        self.label = label
        hide?.cancel()
        let work = DispatchWorkItem { [weak label] in
            UIView.animate(withDuration: 0.2) { label?.alpha = 0 }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

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

private struct BonePaperColorSwatchGestureView: UIViewRepresentable {
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
        .onReceive(NotificationCenter.default.publisher(for: BonePaperColorStore.didChange)) { _ in
            extras = BonePaperColorStore.load()
        }
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
                color = swatch
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                BonePaperHexToast.show(hex)
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(.isButton)
    }

    private func remember(_ hex: String) {
        BonePaperColorStore.remember(hex)
        extras = BonePaperColorStore.load()
    }
}

private struct BonePaperPlainScroll<Content: View>: UIViewRepresentable {
    var onScroll: () -> Void
    var content: Content

    init(onScroll: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.onScroll = onScroll
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeUIView(context: Context) -> BonePaperFillScrollView {
        let scroll = BonePaperFillScrollView()
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.automaticallyAdjustsScrollIndicatorInsets = false
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
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
        context.coordinator.onScroll = onScroll
        guard let host = context.coordinator.host else {
            fatalError("BonePaperPlainScroll missing host")
        }
        host.rootView = AnyView(content.ignoresSafeArea())
        host.view.invalidateIntrinsicContentSize()
        host.view.setNeedsLayout()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        var onScroll: () -> Void

        init(onScroll: @escaping () -> Void) {
            self.onScroll = onScroll
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onScroll()
        }
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
        let applyItem = UIBarButtonItem(
            title: "Apply",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.apply)
        )
        picker.navigationItem.rightBarButtonItem = applyItem
        picker.colorPreview.onHexValidityChanged = { [weak applyItem] valid in
            applyItem?.isEnabled = valid
        }
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
            let applyItem = picker.navigationItem.rightBarButtonItem
            picker.colorPreview.onHexValidityChanged = { [weak applyItem] valid in
                applyItem?.isEnabled = valid
            }
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
            if let picker, !picker.colorPreview.isHexValid {
                return
            }
            picker?.colorPreview.hexTextField.resignFirstResponder()
            let finalColor = picker?.colorPreview.parsedHexColor() ?? confirmedColor
            let hex = BonePaperColorStore.hex(from: finalColor)
            UIPasteboard.general.string = hex
            onApply(finalColor)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                BonePaperHexToast.showMessage("Color \(hex) copied")
            }
        }

        @objc func apply() {
            guard let picker else {
                fatalError("BonePaperFlexColorPickerSheet Apply with no picker")
            }
            guard picker.colorPreview.isHexValid else {
                return
            }
            picker.colorPreview.hexTextField.resignFirstResponder()
            let finalColor = picker.colorPreview.parsedHexColor() ?? picker.selectedColor
            onApply(finalColor)
        }

        @objc func cancel() {
            navigation?.dismiss(animated: true)
        }
    }
}
