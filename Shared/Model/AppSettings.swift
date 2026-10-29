import BonePaper
import CoreGraphics
import Foundation

/// Persisted app settings. `boot` copies them into BonePaper before any drawing.
enum AppSettings {
    private static let paperDrawAntialiasingKey = "paperDrawAntialiasing"
    private static let brushOffsetKey = "paperDrawBrushOffset"
    #if DEBUG
    /// Display-only. Missing key is off. A separate key from the retired "No sidecar" switch.
    static let ignoreBmSampleKey = "debugIgnoreBmSample"
    #endif

    static let maxBrushOffset = 70
    static let brushOffsetStep = 10

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

    /// Upward screen-space brush offset in points (`0...70`, step `10`). Defaults to `0`.
    static var brushOffset: Int {
        get {
            guard UserDefaults.standard.object(forKey: brushOffsetKey) != nil else {
                return 0
            }
            return clampBrushOffset(UserDefaults.standard.integer(forKey: brushOffsetKey))
        }
        set {
            let clamped = clampBrushOffset(newValue)
            UserDefaults.standard.set(clamped, forKey: brushOffsetKey)
            BonePaperFlags.brushOffset = CGFloat(clamped)
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

    static func clampBrushOffset(_ raw: Int) -> Int {
        let clamped = min(max(raw, 0), maxBrushOffset)
        let rounded = Int((Double(clamped) / Double(brushOffsetStep)).rounded()) * brushOffsetStep
        return min(max(rounded, 0), maxBrushOffset)
    }

    static func boot() {
        BonePaperFlags.antialiasing = paperDrawAntialiasing
        BonePaperFlags.brushOffset = CGFloat(brushOffset)
    }
}
