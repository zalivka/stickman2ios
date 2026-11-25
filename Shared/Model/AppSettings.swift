import BonePaper
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Persisted app settings. `boot` copies them into BonePaper before any drawing.
enum AppSettings {
    private static let paperDrawAntialiasingKey = "paperDrawAntialiasing"
    static let showOnionSkeletonKey = "showOnionSkeleton"
    static let skeletonColorRGBKey = "skeletonColorRGB"
    static let cameraFxFadePaletteKey = "cameraFxFadePalette"
    static let cameraFxTintPaletteKey = "cameraFxTintPalette"

    static let cameraFxPaletteSize = 6
    static let defaultCameraFxFadePalette: [Int] = [0x000000, 0xFFFFFF, 0x00A8E8, 0x3B6EE8, 0xD4A359, 0xE63946]
    static let defaultCameraFxTintPalette: [Int] = [0x00A8E8, 0x3B6EE8, 0xD4A359, 0xE63946, 0x38B000, 0x9D4EDD]
    #if DEBUG
    /// Display-only. Missing key is off. A separate key from the retired "No sidecar" switch.
    static let ignoreBmSampleKey = "debugIgnoreBmSample"
    #endif

    static let defaultSkeletonColorRGB = 0xFF7100

    /// Show gray skeleton of the previous frame in the scene editor. Missing key defaults to `true`.
    static var showOnionSkeleton: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showOnionSkeletonKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: showOnionSkeletonKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showOnionSkeletonKey)
        }
    }

    /// 6-slot Fade palette (includes black, white). Defaults to `[0x000000, 0xFFFFFF, 0x00A8E8, 0x3B6EE8, 0xD4A359, 0xE63946]`.
    static var cameraFxFadePalette: [Int] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: cameraFxFadePaletteKey) as? [Int] else {
                return defaultCameraFxFadePalette
            }
            return normalizeCameraFxPalette(raw)
        }
        set {
            UserDefaults.standard.set(normalizeCameraFxPalette(newValue), forKey: cameraFxFadePaletteKey)
        }
    }

    /// 6-slot Tint palette. Defaults to `[0x00A8E8, 0x3B6EE8, 0xD4A359, 0xE63946, 0x38B000, 0x9D4EDD]`.
    static var cameraFxTintPalette: [Int] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: cameraFxTintPaletteKey) as? [Int] else {
                return defaultCameraFxTintPalette
            }
            return normalizeCameraFxPalette(raw)
        }
        set {
            UserDefaults.standard.set(normalizeCameraFxPalette(newValue), forKey: cameraFxTintPaletteKey)
        }
    }

    static func palette(for kind: CameraEffect.Kind) -> [Int] {
        switch kind {
        case .fade:
            return cameraFxFadePalette
        case .colorize:
            return cameraFxTintPalette
        case .none, .desaturate:
            return []
        }
    }

    static func setPalette(_ palette: [Int], for kind: CameraEffect.Kind) {
        switch kind {
        case .fade:
            cameraFxFadePalette = palette
        case .colorize:
            cameraFxTintPalette = palette
        case .none, .desaturate:
            break
        }
    }

    static func normalizeCameraFxPalette(_ raw: [Int]) -> [Int] {
        var out = raw.map { $0 & 0xFFFFFF }
        out = Array(out.prefix(cameraFxPaletteSize))
        while out.count < cameraFxPaletteSize {
            out.append(0x000000)
        }
        return out
    }

    /// 24-bit `0xRRGGBB` color for normal editor skeleton bones/nodes. Defaults to `0xFF7100`.
    static var skeletonColorRGB: Int {
        get {
            guard UserDefaults.standard.object(forKey: skeletonColorRGBKey) != nil else {
                return defaultSkeletonColorRGB
            }
            return UserDefaults.standard.integer(forKey: skeletonColorRGBKey) & 0xFFFFFF
        }
        set {
            UserDefaults.standard.set(newValue & 0xFFFFFF, forKey: skeletonColorRGBKey)
        }
    }

    static func color(fromRGB rgb: Int) -> Color {
        let clamped = rgb & 0xFFFFFF
        let r = Double((clamped >> 16) & 0xFF) / 255.0
        let g = Double((clamped >> 8) & 0xFF) / 255.0
        let b = Double(clamped & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func uiColor(fromRGB rgb: Int) -> UIColor {
        let clamped = rgb & 0xFFFFFF
        let r = CGFloat((clamped >> 16) & 0xFF) / 255.0
        let g = CGFloat((clamped >> 8) & 0xFF) / 255.0
        let b = CGFloat(clamped & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    static func hexString(fromRGB rgb: Int) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }

    static func rgb(from color: UIColor) -> Int? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let converted = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
                  let comps = converted.components,
                  comps.count >= 3
            else {
                return nil
            }
            r = comps[0]
            g = comps[1]
            b = comps[2]
        }
        let ri = Int((min(max(r, 0), 1) * 255).rounded())
        let gi = Int((min(max(g, 0), 1) * 255).rounded())
        let bi = Int((min(max(b, 0), 1) * 255).rounded())
        return (ri << 16) | (gi << 8) | bi
    }

    /// Paper Draw brush and eraser antialiasing. A missing key stays on, matching BonePaper's own default.
    static var paperDrawAntialiasing: Bool {
        get {
            guard UserDefaults.standard.object(forKey: paperDrawAntialiasingKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: paperDrawAntialiasingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: paperDrawAntialiasingKey)
            BonePaperFlags.antialiasing = newValue
        }
    }

    /// DEBUG: draw the `bm` PNG and skip the sidecar, the way an old build does.
    /// Does not change what is saved. A missing key stays off. Release builds follow `sample`.
    #if DEBUG
    static var ignoreBmSample: Bool {
        get { UserDefaults.standard.bool(forKey: ignoreBmSampleKey) }
        set { UserDefaults.standard.set(newValue, forKey: ignoreBmSampleKey) }
    }
    #else
    static let ignoreBmSample = false
    #endif

    static func boot() {
        BonePaperFlags.antialiasing = paperDrawAntialiasing
    }
}
