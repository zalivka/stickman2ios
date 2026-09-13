import CoreGraphics
import Foundation

struct BubbleMeta: Equatable {
    var text: String
    var color: String
    var font: String
    var scale: CGFloat
    var oneLiner: Bool

    var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        HexRGB.parse(color)
    }

    var fontSize: CGFloat {
        max(22, 30 - CGFloat(text.count) / 4) * scale
    }

    static func parse(encoded: String, unitName: String) -> BubbleMeta {
        if encoded.isEmpty {
            fatalError("SceneLoader unit '\(unitName)' bubble meta is empty")
        }
        let plus = encoded.replacingOccurrences(of: "+", with: " ")
        guard let decoded = plus.removingPercentEncoding, !decoded.isEmpty else {
            fatalError("SceneLoader unit '\(unitName)' bubble meta is not URL-encoded")
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(decoded.utf8))
        } catch {
            fatalError("SceneLoader unit '\(unitName)' bubble meta is not BubbleMeta JSON: \(error)")
        }
        if payload.text.isEmpty {
            fatalError("SceneLoader unit '\(unitName)' bubble text is empty")
        }
        if payload.font != "default" {
            fatalError("SceneLoader unit '\(unitName)' bubble font '\(payload.font)' is not default")
        }
        if payload.scale <= 0 {
            fatalError("SceneLoader unit '\(unitName)' bubble scale is \(payload.scale)")
        }
        _ = HexRGB.parse(payload.color)
        return BubbleMeta(
            text: payload.text,
            color: payload.color,
            font: payload.font,
            scale: payload.scale,
            oneLiner: payload.oneLiner
        )
    }

    private struct Payload: Decodable {
        var text: String
        var color: String
        var font: String
        var scale: CGFloat
        var oneLiner: Bool
    }
}
