import SwiftUI
import UIKit

enum BonePaperToolStore {
    private static let brushSizeKey = "bonepaper.brush_size"
    private static let eraserSizeKey = "bonepaper.eraser_size"
    private static let opacityKey = "bonepaper.opacity"
    private static let colorKey = "bonepaper.color"
    private static let fallbackConfigKey = "bonepaper.fallback_drawing_config"
    private static let brushOffsetKey = "paperDrawBrushOffset"
    private static let clearToken = "CLEAR"

    static let maxBrushOffset: Int = 70
    static let brushOffsetStep: Int = 10

    static func clampBrushOffset(_ raw: Int) -> Int {
        let clamped = min(max(raw, 0), maxBrushOffset)
        let rounded = Int((Double(clamped) / Double(brushOffsetStep)).rounded()) * brushOffsetStep
        return min(max(rounded, 0), maxBrushOffset)
    }

    static var brushOffset: Int {
        get {
            guard UserDefaults.standard.object(forKey: brushOffsetKey) != nil else { return 0 }
            return clampBrushOffset(UserDefaults.standard.integer(forKey: brushOffsetKey))
        }
        set {
            let clamped = clampBrushOffset(newValue)
            UserDefaults.standard.set(clamped, forKey: brushOffsetKey)
            BonePaperFlags.brushOffset = CGFloat(clamped)
        }
    }

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
