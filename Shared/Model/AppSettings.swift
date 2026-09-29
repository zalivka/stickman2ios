import BonePaper
import Foundation

/// Persisted app settings. `boot` copies them into BonePaper before any drawing.
enum AppSettings {
    private static let paperDrawAntialiasingKey = "paperDrawAntialiasing"

    /// Paper Draw brush and eraser antialiasing. Missing key is off, matching BonePaper's own default.
    static var paperDrawAntialiasing: Bool {
        get { UserDefaults.standard.bool(forKey: paperDrawAntialiasingKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: paperDrawAntialiasingKey)
            BonePaperFlags.antialiasing = newValue
        }
    }

    static func boot() {
        BonePaperFlags.antialiasing = paperDrawAntialiasing
    }
}
