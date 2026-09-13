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

    var isZero: Bool {
        let eps: CGFloat = 0.01
        return abs(scale - 1) < eps
            && abs(rotate) < eps
            && abs(x) < eps
            && abs(y) < eps
    }

    func lerp(_ other: PictureMove, t: CGFloat) -> PictureMove {
        PictureMove(
            scale: scale + (other.scale - scale) * t,
            rotate: rotate + (other.rotate - rotate) * t,
            x: x + (other.x - x) * t,
            y: y + (other.y - y) * t
        )
    }

    func toTransform() -> CGAffineTransform {
        // GOTCHA (doc/gotchas.md): Android toMatrix is setScale → postRotate →
        // postTranslate = scale, then rotate, then unscaled translate (T * R * S).
        // identity.scaledBy.translatedBy is the opposite (translate, then scale):
        // the translation is multiplied by scale. Camera 1.48 0 20 -200 must mean
        // zoom 1.48× then move (20, -200), not move then zoom around the origin.
        // Wrong order puts the inverted camera rect too far left and down.
        // Same PictureMove is used for camera and bg=.
        CGAffineTransform(translationX: x, y: y)
            .rotated(by: rotate * .pi / 180)
            .scaledBy(x: scale, y: scale)
    }

    func canvasTransform(layout: SkeletonLayout) -> CGAffineTransform {
        PictureMove(
            scale: scale * layout.scale,
            rotate: rotate,
            x: x * layout.scale + layout.originX,
            y: y * layout.scale + layout.originY
        ).toTransform()
    }
}
