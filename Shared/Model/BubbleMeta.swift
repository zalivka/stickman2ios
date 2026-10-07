import CoreGraphics
import Foundation

struct BubbleMeta: Equatable {
    var text: String
    var color: String
    var font: String
    var scale: CGFloat
    var oneLiner: Bool

    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if let parsed = HexRGB.parse(color) {
            return parsed
        }
        return HexRGB.parse(Self.defaults.color) ?? (r: 0, g: 0, b: 0, a: 1)
    }

    var fontSize: CGFloat {
        max(22, 30 - CGFloat(text.count) / 4) * scale
    }

    /// Android `BubbleMeta()` defaults when item `meta=""`.
    static let defaults = BubbleMeta(
        text: "Text",
        color: "#ff000000",
        font: "default",
        scale: 1,
        oneLiner: false
    )

    static func parse(encoded: String, unitName: String) throws -> BubbleMeta {
        if encoded.isEmpty {
            return defaults
        }
        let plus = encoded.replacingOccurrences(of: "+", with: " ")
        guard let decoded = plus.removingPercentEncoding, !decoded.isEmpty else {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' bubble meta is not URL-encoded")
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(decoded.utf8))
        } catch {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' bubble meta is not BubbleMeta JSON: \(error)")
        }
        if payload.text.isEmpty {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' bubble text is empty")
        }
        if payload.font != "default", !StickmanFonts.contains(payload.font) {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' unknown bubble font '\(payload.font)'")
        }
        if payload.scale <= 0 {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' bubble scale is \(payload.scale)")
        }
        do {
            _ = try HexRGB.parseThrowing(payload.color)
        } catch {
            throw SceneLoadError(message: "SceneLoader unit '\(unitName)' bubble color: \(error)")
        }
        return BubbleMeta(
            text: payload.text,
            color: payload.color,
            font: payload.font,
            scale: payload.scale,
            oneLiner: payload.oneLiner
        )
    }

    func encoded(unitName: String) -> String {
        if text.isEmpty {
            fatalError("SceneXML unit '\(unitName)' bubble text is empty")
        }
        if font != "default", !StickmanFonts.contains(font) {
            fatalError("SceneXML unit '\(unitName)' unknown bubble font '\(font)'")
        }
        if scale <= 0 {
            fatalError("SceneXML unit '\(unitName)' bubble scale is \(scale)")
        }
        let payload = Payload(text: text, color: color, font: font, scale: scale, oneLiner: oneLiner)
        let json: Data
        do {
            json = try JSONEncoder().encode(payload)
        } catch {
            fatalError("SceneXML unit '\(unitName)' bubble meta JSON: \(error)")
        }
        guard let raw = String(data: json, encoding: .utf8) else {
            fatalError("SceneXML unit '\(unitName)' bubble meta is not UTF-8")
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) else {
            fatalError("SceneXML unit '\(unitName)' bubble meta is not URL-encodable")
        }
        return encoded
    }

    private struct Payload: Codable {
        var text: String
        var color: String
        var font: String
        var scale: CGFloat
        var oneLiner: Bool
    }
}
