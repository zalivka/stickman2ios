import SwiftUI
import UIKit

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
