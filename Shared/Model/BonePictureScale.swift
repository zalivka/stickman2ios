import CoreGraphics
import UIKit

/// Scale a bone bitmap around a joint pixel (top-left origin, y down) and report where that joint lands.
enum BonePictureScale {
    struct Result {
        var image: CGImage
        var jointX: CGFloat
        var jointY: CGFloat
    }

    static func scale(
        _ image: CGImage,
        aroundX: CGFloat,
        y aroundY: CGFloat,
        factor: CGFloat
    ) -> Result {
        transform(image, aroundX: aroundX, y: aroundY, factor: factor, radians: 0)
    }

    /// Scale, then rotate around the joint. Positive radians are counterclockwise, matching a Shift twist.
    static func transform(
        _ image: CGImage,
        aroundX: CGFloat,
        y aroundY: CGFloat,
        factor: CGFloat,
        radians: CGFloat
    ) -> Result {
        if factor <= 0 {
            fatalError("BonePictureScale factor \(factor)")
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        if width < 1 || height < 1 {
            fatalError("BonePictureScale image size \(image.width)x\(image.height)")
        }
        let cosR = cos(radians)
        let sinR = sin(radians)
        func map(_ point: CGPoint) -> CGPoint {
            let sx = (point.x - aroundX) * factor
            let sy = (point.y - aroundY) * factor
            return CGPoint(
                x: aroundX + sx * cosR - sy * sinR,
                y: aroundY + sx * sinR + sy * cosR
            )
        }
        let corners = [
            map(.zero),
            map(CGPoint(x: width, y: 0)),
            map(CGPoint(x: 0, y: height)),
            map(CGPoint(x: width, y: height))
        ]
        guard let minX = corners.map(\.x).min(),
              let minY = corners.map(\.y).min(),
              let maxX = corners.map(\.x).max(),
              let maxY = corners.map(\.y).max()
        else {
            fatalError("BonePictureScale image has no corners")
        }
        let pixelW = Int(ceil(maxX - minX))
        let pixelH = Int(ceil(maxY - minY))
        if pixelW < 1 || pixelH < 1 {
            fatalError("BonePictureScale image became \(pixelW)x\(pixelH)")
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelW, height: pixelH),
            format: format
        )
        let drawn = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.translateBy(x: -minX, y: -minY)
            cg.translateBy(x: aroundX, y: aroundY)
            cg.rotate(by: radians)
            cg.scaleBy(x: factor, y: factor)
            cg.translateBy(x: -aroundX, y: -aroundY)
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cg = drawn.cgImage else {
            fatalError("BonePictureScale produced no bitmap")
        }
        return Result(image: cg, jointX: aroundX - minX, jointY: aroundY - minY)
    }
}
