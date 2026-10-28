import BonePaper
import CoreGraphics
import Foundation
import UIKit

/// Splits a bone bitmap (and its optional 2x BonePaper paint buffer) at `splitDistance`
/// along the bone's local +X axis, giving both halves the circular disc `D(split, radius)`.
enum BonePictureSplit {
    struct Half {
        var image: CGImage
        var paintBuffer: Data?
        var xOffset: CGFloat
        var yOffset: CGFloat
    }

    struct Pair {
        var proximal: Half
        var distal: Half
    }

    static func split(
        bitmap: CGImage,
        paintBuffer: Data?,
        xOffset: CGFloat,
        yOffset: CGFloat,
        splitDistance: CGFloat,
        radius: CGFloat,
        name: String
    ) throws -> Pair {
        if splitDistance <= 0 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' splitDistance \(splitDistance) <= 0")
        }
        if radius <= 0 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' radius \(radius) <= 0")
        }
        let width = bitmap.width
        let height = bitmap.height
        if width < 1 || height < 1 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' size \(width)x\(height)")
        }

        let xSplit = -xOffset + splitDistance
        let ySplit = -yOffset

        // Tight horizontal crop bounds in 1x pixel coordinates (integer-aligned so 2x buffer scales exact).
        let proxMinX = 0
        let proxMaxX = min(width, max(1, Int(ceil(xSplit + radius))))

        let distMinX = max(0, min(width - 1, Int(floor(xSplit - radius))))
        let distMaxX = width

        let proxImage = try renderHalf(
            source: bitmap,
            cropMinX: proxMinX,
            cropMaxX: proxMaxX,
            height: height,
            xSplit: xSplit,
            ySplit: ySplit,
            radius: radius,
            isProximal: true,
            name: name
        )
        let distImage = try renderHalf(
            source: bitmap,
            cropMinX: distMinX,
            cropMaxX: distMaxX,
            height: height,
            xSplit: xSplit,
            ySplit: ySplit,
            radius: radius,
            isProximal: false,
            name: name
        )

        var proxBuffer: Data?
        var distBuffer: Data?
        let sample = BonePaperDocument.sample
        if let data = paintBuffer,
           let bufferImage = UnitAssets.pngImage(from: data),
           bufferImage.width == width * sample,
           bufferImage.height == height * sample {
            let s = CGFloat(sample)
            if let proxBufImg = try? renderHalf(
                source: bufferImage,
                cropMinX: proxMinX * sample,
                cropMaxX: proxMaxX * sample,
                height: height * sample,
                xSplit: xSplit * s,
                ySplit: ySplit * s,
                radius: radius * s,
                isProximal: true,
                name: name
            ), proxBufImg.width == proxImage.width * sample,
               proxBufImg.height == proxImage.height * sample {
                proxBuffer = try? UnitAssets.pngData(from: proxBufImg, name: name)
            }
            if let distBufImg = try? renderHalf(
                source: bufferImage,
                cropMinX: distMinX * sample,
                cropMaxX: distMaxX * sample,
                height: height * sample,
                xSplit: xSplit * s,
                ySplit: ySplit * s,
                radius: radius * s,
                isProximal: false,
                name: name
            ), distBufImg.width == distImage.width * sample,
               distBufImg.height == distImage.height * sample {
                distBuffer = try? UnitAssets.pngData(from: distBufImg, name: name)
            }
        }

        let proximal = Half(
            image: proxImage,
            paintBuffer: proxBuffer,
            xOffset: xOffset + CGFloat(proxMinX),
            yOffset: yOffset
        )
        let distal = Half(
            image: distImage,
            paintBuffer: distBuffer,
            xOffset: CGFloat(distMinX) - xSplit,
            yOffset: yOffset
        )
        return Pair(proximal: proximal, distal: distal)
    }

    /// Scans the vertical column at `xSplit` for non-transparent pixels (`alpha > 16`)
    /// and returns half the thickness clamped to `[8, min(boneLength / 2, 120)]`.
    static func defaultRadius(
        bitmap: CGImage,
        xOffset: CGFloat,
        yOffset: CGFloat,
        splitDistance: CGFloat,
        boneLength: CGFloat
    ) -> CGFloat {
        let fallback = min(max(boneLength * 0.18, 8), 60)
        let width = bitmap.width
        let height = bitmap.height
        let col = Int(((-xOffset) + splitDistance).rounded())
        guard width >= 1, height >= 1, col >= 0, col < width else {
            return fallback
        }
        var pixel = [UInt8](repeating: 0, count: height * 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }
        context.draw(
            bitmap,
            in: CGRect(x: -CGFloat(col), y: 0, width: CGFloat(width), height: CGFloat(height))
        )
        var firstY: Int?
        var lastY: Int?
        for y in 0..<height {
            let alpha = pixel[y * 4 + 3]
            if alpha > 16 {
                if firstY == nil { firstY = y }
                lastY = y
            }
        }
        guard let first = firstY, let last = lastY, last >= first else {
            return fallback
        }
        let halfSpan = CGFloat(last - first + 1) / 2
        let cap = max(8, min(boneLength / 2, 120))
        return min(max(halfSpan, 8), cap)
    }

    private static func renderHalf(
        source: CGImage,
        cropMinX: Int,
        cropMaxX: Int,
        height: Int,
        xSplit: CGFloat,
        ySplit: CGFloat,
        radius: CGFloat,
        isProximal: Bool,
        name: String
    ) throws -> CGImage {
        let outW = max(1, cropMaxX - cropMinX)
        let outH = max(1, height)
        let fullW = CGFloat(source.width)
        let fullH = CGFloat(source.height)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outW, height: outH),
            format: format
        )
        let drawn = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.translateBy(x: -CGFloat(cropMinX), y: 0)

            let clipPath = CGMutablePath()
            if isProximal {
                if xSplit > 0 {
                    clipPath.addRect(CGRect(x: 0, y: 0, width: xSplit, height: fullH))
                }
            } else {
                if fullW > xSplit {
                    clipPath.addRect(CGRect(x: xSplit, y: 0, width: fullW - xSplit, height: fullH))
                }
            }
            clipPath.addEllipse(
                in: CGRect(
                    x: xSplit - radius,
                    y: ySplit - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            cg.addPath(clipPath)
            cg.clip(using: .winding)

            UIImage(cgImage: source).draw(in: CGRect(x: 0, y: 0, width: fullW, height: fullH))
        }
        guard let cg = drawn.cgImage else {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' produced no bitmap")
        }
        return cg
    }
}
