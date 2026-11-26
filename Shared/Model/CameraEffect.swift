import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct CameraEffect: Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case none = "NONE"
        case fade = "FADE"
        case desaturate = "DESATURATE"
        case colorize = "COLORIZE"

        var displayName: String {
            switch self {
            case .none: return "None"
            case .fade: return "Fade"
            case .desaturate: return "B&W"
            case .colorize: return "Tint"
            }
        }
    }

    /// Legacy preset names still accepted when parsing old `.ats` files.
    enum LegacyName: String {
        case aqua = "AQUA"
        case night = "NIGHT"
        case sepia = "SEPIA"
        case red = "RED"
        case green = "GREEN"
        case purple = "PURPLE"

        var rgbInt: Int {
            switch self {
            case .aqua: return 0x00A8E8
            case .night: return 0x3B6EE8
            case .sepia: return 0xD4A359
            case .red: return 0xE63946
            case .green: return 0x38B000
            case .purple: return 0x9D4EDD
            }
        }
    }

    static let none = CameraEffect()
    static let zeroThreshold: Float = 0.005
    static let paletteSize = 6

    var kind: Kind = .none
    var colorIndex: Int = 0
    var rgb: (r: Float, g: Float, b: Float) = (0, 0, 0)
    var power: Float = 0

    init(kind: Kind = .none, colorIndex: Int = 0, power: Float = 0) {
        self.kind = kind
        self.colorIndex = Self.clampedColorIndex(colorIndex)
        self.rgb = kind.paletteRGB(at: self.colorIndex)
        if kind == .none {
            self.power = 0
        } else {
            self.power = min(max(power, 0), 1)
        }
    }

    init(kind: Kind, colorIndex: Int, snapshot: (r: Float, g: Float, b: Float), power: Float) {
        self.kind = kind
        self.colorIndex = colorIndex < 0 ? -1 : Self.clampedColorIndex(colorIndex)
        self.rgb = snapshot
        self.power = kind == .none ? 0 : min(max(power, 0), 1)
    }

    /// Convenience: build directly from a 0xRRGGBB int (records the palette slot it matches, or -1).
    init(kind: Kind, rgbInt: Int, power: Float) {
        self.kind = kind
        let palette = kind.palette
        self.colorIndex = palette.firstIndex(of: rgbInt & 0xFFFFFF) ?? -1
        self.rgb = Self.rgbComponents(from: rgbInt & 0xFFFFFF)
        self.power = kind == .none ? 0 : min(max(power, 0), 1)
    }

    static func clampedColorIndex(_ index: Int) -> Int {
        min(max(index, 0), paletteSize - 1)
    }

    var isZero: Bool {
        kind == .none || power < Self.zeroThreshold
    }

    /// Two effects can be tweened together when either is inactive (`.none` / 0% power)
    /// or both share the same `Kind`. Different active kinds (e.g. `Fade` vs `Tint`) conflict.
    func canTween(with other: CameraEffect) -> Bool {
        isZero || other.isZero || kind == other.kind
    }

    static func == (lhs: CameraEffect, rhs: CameraEffect) -> Bool {
        lhs.kind == rhs.kind
            && lhs.colorIndex == rhs.colorIndex
            && lhs.rgb.r == rhs.rgb.r
            && lhs.rgb.g == rhs.rgb.g
            && lhs.rgb.b == rhs.rgb.b
            && lhs.power == rhs.power
    }

    /// 0xRRGGBB int for the current snapshot.
    var rgbInt: Int {
        Self.rgbInt(from: rgb)
    }

    static func rgbInt(from rgb: (r: Float, g: Float, b: Float)) -> Int {
        let ri = Int((min(max(rgb.r, 0), 1) * 255).rounded())
        let gi = Int((min(max(rgb.g, 0), 1) * 255).rounded())
        let bi = Int((min(max(rgb.b, 0), 1) * 255).rounded())
        return (ri << 16) | (gi << 8) | bi
    }

    static func rgbComponents(from rgb: Int) -> (r: Float, g: Float, b: Float) {
        let clamped = rgb & 0xFFFFFF
        return (
            Float((clamped >> 16) & 0xFF) / 255.0,
            Float((clamped >> 8) & 0xFF) / 255.0,
            Float(clamped & 0xFF) / 255.0
        )
    }

    var hexString: String {
        String(format: "#%06X", rgbInt & 0xFFFFFF)
    }

    static func rgbInt(fromHex text: String) -> Int? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex = String(hex.dropFirst())
        }
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }
        return value & 0xFFFFFF
    }

    func serialize() -> String {
        if isZero {
            return ""
        }
        switch kind {
        case .none:
            return ""
        case .desaturate:
            return "\(kind.rawValue) \(XMLWrite.float(CGFloat(power)))"
        case .fade, .colorize:
            return "\(kind.rawValue) \(hexString) \(XMLWrite.float(CGFloat(power)))"
        }
    }

    static func parse(_ text: String) throws -> CameraEffect {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .none
        }
        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = parts.first else {
            throw SceneLoadError(message: "CameraEffect empty in '\(text)'")
        }
        let token = String(first)

        // Legacy FADE_BLACK / FADE_WHITE → single Fade with black / white.
        if token == "FADE_BLACK" {
            guard parts.count == 2, let val = Float(parts[1]), val.isFinite else {
                throw SceneLoadError(message: "CameraEffect expected 'FADE_BLACK <power>', got '\(text)'")
            }
            let clamped = min(max(val, 0), 1)
            if clamped < zeroThreshold { return .none }
            return CameraEffect(kind: .fade, rgbInt: 0x000000, power: clamped)
        }
        if token == "FADE_WHITE" {
            guard parts.count == 2, let val = Float(parts[1]), val.isFinite else {
                throw SceneLoadError(message: "CameraEffect expected 'FADE_WHITE <power>', got '\(text)'")
            }
            let clamped = min(max(val, 0), 1)
            if clamped < zeroThreshold { return .none }
            return CameraEffect(kind: .fade, rgbInt: 0xFFFFFF, power: clamped)
        }

        guard let kind = Kind(rawValue: token) else {
            throw SceneLoadError(message: "CameraEffect unknown kind in '\(text)'")
        }
        switch kind {
        case .none:
            return .none
        case .desaturate:
            guard parts.count == 2, let val = Float(parts[1]), val.isFinite else {
                throw SceneLoadError(message: "CameraEffect expected '<KIND> <power>', got '\(text)'")
            }
            let clamped = min(max(val, 0), 1)
            if clamped < zeroThreshold { return .none }
            return CameraEffect(kind: .desaturate, power: clamped)
        case .fade, .colorize:
            guard parts.count == 3, let val = Float(parts[2]), val.isFinite else {
                throw SceneLoadError(message: "CameraEffect expected 'COLORIZE|FADE <hex> <power>', got '\(text)'")
            }
            let colorToken = String(parts[1])
            let rgbInt: Int
            if let hex = Self.rgbInt(fromHex: colorToken) {
                rgbInt = hex
            } else if let legacy = LegacyName(rawValue: colorToken) {
                rgbInt = legacy.rgbInt
            } else {
                throw SceneLoadError(message: "CameraEffect expected 'COLORIZE|FADE <hex> <power>', got '\(text)'")
            }
            let clamped = min(max(val, 0), 1)
            if clamped < zeroThreshold { return .none }
            return CameraEffect(kind: kind, rgbInt: rgbInt, power: clamped)
        }
    }

    // MARK: - ColorMatrix Math (shared by SwiftUI GraphicsContext and CGImage rasterizer)

    private static let lumR: Float = 0.213
    private static let lumG: Float = 0.715
    private static let lumB: Float = 0.072

    /// Returns the 4x5 color matrix where bias terms (column 5) are in 0...1 scale.
    /// Returns nil when this effect does not use a color matrix (.none, .fade).
    var normalizedColorMatrix: [Float]? {
        if isZero {
            return nil
        }
        let p = min(max(power, 0), 1)
        switch kind {
        case .none, .fade:
            return nil
        case .desaturate:
            let s = 1.0 - p
            let invS = 1.0 - s
            let r = Self.lumR * invS
            let g = Self.lumG * invS
            let b = Self.lumB * invS
            return [
                r + s, g,     b,     0, 0,
                r,     g + s, b,     0, 0,
                r,     g,     b + s, 0, 0,
                0,     0,     0,     1, 0
            ]
        case .colorize:
            let (rt, gt, bt) = rgb
            let invP = 1.0 - p
            let lift: Float = (25.0 / 255.0) * p
            return [
                invP + p * Self.lumR * rt, p * Self.lumG * rt,        p * Self.lumB * rt,        0, lift * rt,
                p * Self.lumR * gt,        invP + p * Self.lumG * gt, p * Self.lumB * gt,        0, lift * gt,
                p * Self.lumR * bt,        p * Self.lumG * bt,        invP + p * Self.lumB * bt, 0, lift * bt,
                0,                         0,                         0,                         1, 0
            ]
        }
    }

    var swiftUIColorMatrix: SwiftUI.ColorMatrix? {
        guard let m = normalizedColorMatrix else {
            return nil
        }
        return Self.makeSwiftUIColorMatrix(m)
    }

    /// 4x5 color matrix for individual scene units (items).
    /// Note: SwiftUI `.colorMatrix` operates on unpremultiplied RGBA, so `.fade` is omitted for items
    /// (items only support `.none`, `.desaturate`, and `.colorize`). If a `.fade` effect is present on a unit,
    /// `unitColorMatrix` still blends RGB toward the target color while preserving alpha.
    var unitColorMatrix: [Float]? {
        if isZero {
            return nil
        }
        switch kind {
        case .none:
            return nil
        case .desaturate, .colorize:
            return normalizedColorMatrix
        case .fade:
            let p = min(max(power, 0), 1)
            let (rt, gt, bt) = rgb
            let invP = 1.0 - p
            return [
                invP, 0,    0,    0, p * rt,
                0,    invP, 0,    0, p * gt,
                0,    0,    invP, 0, p * bt,
                0,    0,    0,    1, 0
            ]
        }
    }

    var unitSwiftUIColorMatrix: SwiftUI.ColorMatrix? {
        guard let m = unitColorMatrix else {
            return nil
        }
        return Self.makeSwiftUIColorMatrix(m)
    }

    private static func makeSwiftUIColorMatrix(_ m: [Float]) -> SwiftUI.ColorMatrix {
        var cm = SwiftUI.ColorMatrix()
        cm.r1 = m[0];  cm.r2 = m[1];  cm.r3 = m[2];  cm.r4 = m[3];  cm.r5 = m[4]
        cm.g1 = m[5];  cm.g2 = m[6];  cm.g3 = m[7];  cm.g4 = m[8];  cm.g5 = m[9]
        cm.b1 = m[10]; cm.b2 = m[11]; cm.b3 = m[12]; cm.b4 = m[13]; cm.b5 = m[14]
        cm.a1 = m[15]; cm.a2 = m[16]; cm.a3 = m[17]; cm.a4 = m[18]; cm.a5 = m[19]
        return cm
    }

    /// Overlay fill color for `.fade`.
    var overlayColor: Color? {
        if isZero {
            return nil
        }
        let alpha = Double(min(max(power, 0), 1))
        switch kind {
        case .fade:
            return Color(red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b)).opacity(alpha)
        case .none, .desaturate, .colorize:
            return nil
        }
    }

    var overlayUIColor: UIColor? {
        if isZero {
            return nil
        }
        let alpha = CGFloat(min(max(power, 0), 1))
        switch kind {
        case .fade:
            return UIColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: alpha)
        case .none, .desaturate, .colorize:
            return nil
        }
    }

    /// Applies the 4x5 color matrix to an existing CGImage for offline export / thumbnails.
    func applyColorMatrix(to image: CGImage) -> CGImage {
        guard let m = normalizedColorMatrix else {
            return image
        }
        return Self.applyMatrix(m, to: image)
    }

    /// Applies `unitColorMatrix` to a transparent unit bitmap (`premultipliedLast`).
    /// Scales bias terms by `alpha / 255` so transparent pixels remain `[0, 0, 0, 0]`.
    func applyUnitColorMatrix(to image: CGImage) -> CGImage {
        guard let m = unitColorMatrix else {
            return image
        }
        return Self.applyMatrix(m, to: image)
    }

    private static func applyMatrix(_ m: [Float], to image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        if width <= 0 || height <= 0 {
            return image
        }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let rendered: CGImage? = buffer.withUnsafeMutableBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  )
            else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            let count = width * height
            let r1 = m[0], r2 = m[1], r3 = m[2], r5 = m[4]
            let g1 = m[5], g2 = m[6], g3 = m[7], g5 = m[9]
            let b1 = m[10], b2 = m[11], b3 = m[12], b5 = m[14]

            for i in 0..<count {
                let offset = i * 4
                let a = ptr[offset + 3]
                if a == 0 {
                    continue
                }
                let af = Float(a)
                let r = Float(ptr[offset])
                let g = Float(ptr[offset + 1])
                let b = Float(ptr[offset + 2])

                let nr = min(max(r1 * r + r2 * g + r3 * b + r5 * af, 0), af)
                let ng = min(max(g1 * r + g2 * g + g3 * b + g5 * af, 0), af)
                let nb = min(max(b1 * r + b2 * g + b3 * b + b5 * af, 0), af)

                ptr[offset]     = UInt8(nr + 0.5)
                ptr[offset + 1] = UInt8(ng + 0.5)
                ptr[offset + 2] = UInt8(nb + 0.5)
            }
            return context.makeImage()
        }
        return rendered ?? image
    }
}

extension CameraEffect.Kind {
    /// The active (shared, persisted) palette for this kind.
    var palette: [Int] {
        AppSettings.palette(for: self)
    }

    func paletteRGB(at index: Int) -> (r: Float, g: Float, b: Float) {
        let pal = palette
        guard pal.isEmpty else {
            return CameraEffect.rgbComponents(from: pal[CameraEffect.clampedColorIndex(index)])
        }
        return (0, 0, 0)
    }
}
