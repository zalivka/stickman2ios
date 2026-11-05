import CoreGraphics
import Foundation
import ImageIO

final class BackgroundAssets {
    static let maxEditorDimension = 2048

    private var images: [String: CGImage] = [:]
    private var sampleScales: [String: CGFloat] = [:]
    private var archives: [String: Data] = [:]
    /// Backgrounds a loaded scene referenced but could not show; those frames fall back to white.
    private(set) var loadErrors: [String] = []

    /// Nil when the background is not installed; draw sites fall back to the scene fill.
    func image(for name: String) -> CGImage? {
        images[name]
    }

    func sampleScale(for name: String) -> CGFloat {
        guard DevFlags.optimizeGiantBitmaps, let scale = sampleScales[name], scale > 0 else {
            return 1
        }
        return scale
    }

    func originalSize(for name: String) -> (width: CGFloat, height: CGFloat)? {
        guard let img = images[name] else { return nil }
        let scale = sampleScale(for: name)
        return (CGFloat(img.width) * scale, CGFloat(img.height) * scale)
    }

    func hasImage(for name: String) -> Bool {
        images[name] != nil
    }

    func install(name: String, image: CGImage, sampleScale: CGFloat = 1, archive: Data? = nil) {
        if name.isEmpty {
            assertionFailure("BackgroundAssets empty name")
            return
        }
        images[name] = image
        sampleScales[name] = sampleScale > 0 ? sampleScale : 1
        if let archive {
            if archive.isEmpty {
                assertionFailure("BackgroundAssets '\(name)' archive is empty")
            } else {
                archives[name] = archive
            }
        }
    }

    /// A `usermade:` archive with `bg.png` or `bg.jpg`, kept whole so the scene saves it as `_bgs/<own>.zip`.
    func installArchive(name: String, archive: Data) throws {
        guard let entry = BackgroundStore.rasterEntry(in: archive) else {
            throw BackgroundStore.Failure.noRaster(name)
        }
        let data = try ZipStore.dataThrowing(named: entry, in: archive)
        guard let decoded = Self.tryDecodeSampled(data) else {
            throw BackgroundStore.Failure.notAnImage(name)
        }
        install(name: name, image: decoded.image, sampleScale: decoded.sampleScale, archive: archive)
    }

    /// Decodes the original full-resolution raster from the retained archive (used when opening Paper Draw).
    func fullResolutionImage(for name: String) -> CGImage? {
        if let archive = archives[name],
           let entry = BackgroundStore.rasterEntry(in: archive),
           let data = try? ZipStore.dataThrowing(named: entry, in: archive),
           let full = Self.tryDecode(data) {
            return full
        }
        return images[name]
    }

    func recordLoadError(_ message: String) {
        loadErrors.append(message)
    }

    /// Nil when the scene referenced a background that never installed; the frame draws the fill.
    func archive(for name: String) -> Data? {
        guard let zip = archives[name] else {
            assertionFailure("BackgroundAssets missing archive for '\(name)'")
            return nil
        }
        return zip
    }

    static func tryDecode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func tryDecodeSampled(_ data: Data, maxDimension: Int = maxEditorDimension) -> (image: CGImage, sampleScale: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        if !DevFlags.optimizeGiantBitmaps {
            guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return (img, 1)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let origW = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let origH = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        if origW <= 0 || origH <= 0 {
            guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return (img, 1)
        }
        let sample = UnitAssets.computePowerOfTwoSampleSize(width: origW, height: origH, maxDimension: maxDimension)
        if sample <= 1 {
            guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return (img, 1)
        }
        let targetW = max(1, origW / sample)
        let targetH = max(1, origH / sample)
        let maxPixel = max(targetW, targetH)
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary),
           thumb.width > 0, thumb.height > 0 {
            return (thumb, CGFloat(sample))
        }
        guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return (full, 1)
    }
}
