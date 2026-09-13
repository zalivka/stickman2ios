import CoreGraphics
import Foundation

struct PictureMove {
    static let identity = PictureMove(scale: 1, rotate: 0, x: 0, y: 0)

    var scale: CGFloat
    var rotate: CGFloat
    var x: CGFloat
    var y: CGFloat

    init(scale: CGFloat, rotate: CGFloat, x: CGFloat, y: CGFloat) {
        if scale <= 0 {
            fatalError("PictureMove scale is \(scale)")
        }
        self.scale = scale
        self.rotate = rotate
        self.x = x
        self.y = y
    }

    static func parse(_ text: String) -> PictureMove {
        let parts = text.split { $0.isWhitespace }.map(String.init)
        if parts.count != 4 {
            fatalError("PictureMove expected 4 numbers, got '\(text)'")
        }
        guard let scale = Double(parts[0]) else {
            fatalError("PictureMove scale '\(parts[0])' is not a number")
        }
        guard let rotate = Double(parts[1]) else {
            fatalError("PictureMove rotate '\(parts[1])' is not a number")
        }
        guard let x = Double(parts[2]) else {
            fatalError("PictureMove x '\(parts[2])' is not a number")
        }
        guard let y = Double(parts[3]) else {
            fatalError("PictureMove y '\(parts[3])' is not a number")
        }
        return PictureMove(scale: CGFloat(scale), rotate: CGFloat(rotate), x: CGFloat(x), y: CGFloat(y))
    }

    func serialize() -> String {
        "\(scale) \(rotate) \(x) \(y)"
    }

    func toTransform() -> CGAffineTransform {
        CGAffineTransform.identity
            .scaledBy(x: scale, y: scale)
            .rotated(by: rotate * .pi / 180)
            .translatedBy(x: x, y: y)
    }
}
