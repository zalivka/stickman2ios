import CoreGraphics
import Foundation

extension BonePaperDocument {
    var hasMask: Bool {
        maskAlpha != nil
    }

    /// Converts the current drawing's alpha silhouette into the active mask and clears the paint buffer.
    /// Returns `false` if the paint buffer has no visible pixels.
    @discardableResult
    func convertDrawingToMask() -> Bool {
        if filling { return false }
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard let data = context.data else {
            fatalError("BonePaperDocument mask has no pixel data")
        }
        let stride = context.bytesPerRow
        if stride < pixelWidth * 4 {
            fatalError("BonePaperDocument mask stride \(stride) width \(pixelWidth)")
        }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let w = pixelWidth
        let h = pixelHeight
        var alpha = [UInt8](repeating: 0, count: w * h)
        var hasOpaque = false
        for y in 0..<h {
            let row = y * stride
            let base = y * w
            for x in 0..<w {
                let a = pixels[row + x * 4 + 3]
                if a > 0 {
                    alpha[base + x] = a
                    hasOpaque = true
                }
            }
        }
        guard hasOpaque else { return false }
        lastFillOperation = nil
        fillStreak = 0
        pushUndo()
        redoStack.removeAll()
        maskAlpha = alpha
        maskImage = Self.makeMaskImage(alpha: alpha, width: w, height: h)
        maskOverlay = Self.makeMaskOverlay(alpha: alpha, width: w, height: h)
        context.clear(pixelRect)
        publishPreview()
        publishStacks()
        return true
    }

    /// Removes the active mask while keeping whatever was drawn inside it.
    func clearMask() {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard maskAlpha != nil else { return }
        lastFillOperation = nil
        fillStreak = 0
        pushUndo()
        redoStack.removeAll()
        maskAlpha = nil
        maskImage = nil
        maskOverlay = nil
        publishPreview()
        publishStacks()
    }

    /// Builds an 8-bit grayscale `CGImage` for `CGContext.clip(to:mask:)` where 255 is inside the mask and 0 is clipped.
    static func makeMaskImage(alpha: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(alpha) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            fatalError("BonePaperDocument makeMaskImage failed")
        }
        return image
    }

    /// Shaded overlay for the canvas: dark outside the mask silhouette, transparent inside.
    static func makeMaskOverlay(alpha: [UInt8], width: Int, height: Int) -> CGImage {
        let ctx = makeBuffer(width: width, height: height)
        guard let data = ctx.data else {
            fatalError("BonePaperDocument makeMaskOverlay has no pixel data")
        }
        let stride = ctx.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let shadeMaxAlpha = 115 // ~45% black outside the mask
        for y in 0..<height {
            let row = y * stride
            let base = y * width
            for x in 0..<width {
                let outside = 255 - Int(alpha[base + x])
                if outside <= 0 { continue }
                let a = UInt8((outside * shadeMaxAlpha + 127) / 255)
                pixels[row + x * 4 + 3] = a
            }
        }
        guard let image = ctx.makeImage() else {
            fatalError("BonePaperDocument makeMaskOverlay makeImage failed")
        }
        return image
    }

    /// Extracts the 8-bit alpha channel from a mask sidecar image at `width × height`.
    /// Returns `nil` when dimensions do not match or no pixel has `alpha > 0`.
    static func extractMaskAlpha(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard image.width == width, image.height == height, width > 0, height > 0 else {
            return nil
        }
        let ctx = makeBuffer(width: width, height: height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let stride = ctx.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var alpha = [UInt8](repeating: 0, count: width * height)
        var hasOpaque = false
        for y in 0..<height {
            let row = y * stride
            let base = y * width
            for x in 0..<width {
                let a = pixels[row + x * 4 + 3]
                if a > 0 {
                    alpha[base + x] = a
                    hasOpaque = true
                }
            }
        }
        return hasOpaque ? alpha : nil
    }

    /// Builds an RGBA sidecar `CGImage` whose alpha channel stores `alpha` for lossless PNG encoding.
    static func makeMaskSidecarImage(alpha: [UInt8], width: Int, height: Int) -> CGImage {
        let ctx = makeBuffer(width: width, height: height)
        guard let data = ctx.data else {
            fatalError("BonePaperDocument makeMaskSidecarImage has no pixel data")
        }
        let stride = ctx.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = y * stride
            let base = y * width
            for x in 0..<width {
                let a = alpha[base + x]
                if a > 0 {
                    pixels[row + x * 4 + 3] = a
                }
            }
        }
        guard let image = ctx.makeImage() else {
            fatalError("BonePaperDocument makeMaskSidecarImage makeImage failed")
        }
        return image
    }

    /// True when `buffer` contains at least one pixel with `alpha > 0`.
    static func bufferHasVisiblePixels(_ buffer: CGImage) -> Bool {
        let w = buffer.width
        let h = buffer.height
        guard w > 0, h > 0 else { return false }
        if (buffer.alphaInfo == .premultipliedLast || buffer.alphaInfo == .last),
           buffer.bitsPerPixel == 32,
           let data = buffer.dataProvider?.data,
           let bytes = CFDataGetBytePtr(data) {
            let stride = buffer.bytesPerRow
            let total = CFDataGetLength(data)
            for y in 0..<h {
                let row = y * stride
                if row + w * 4 > total { break }
                for x in 0..<w {
                    if bytes[row + x * 4 + 3] > 0 {
                        return true
                    }
                }
            }
            return false
        }
        let ctx = makeBuffer(width: w, height: h)
        ctx.draw(buffer, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return false }
        let stride = ctx.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            let row = y * stride
            for x in 0..<w {
                if pixels[row + x * 4 + 3] > 0 {
                    return true
                }
            }
        }
        return false
    }
}
