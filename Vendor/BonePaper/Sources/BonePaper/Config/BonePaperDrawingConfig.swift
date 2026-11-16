import CoreGraphics
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
