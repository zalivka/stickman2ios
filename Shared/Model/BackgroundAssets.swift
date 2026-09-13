import CoreGraphics
import Foundation
import ImageIO

final class BackgroundAssets {
    private var images: [String: CGImage] = [:]

    func image(for name: String) -> CGImage {
        guard let image = images[name] else {
            fatalError("BackgroundAssets missing '\(name)'")
        }
        return image
    }

    func hasImage(for name: String) -> Bool {
        images[name] != nil
    }

    func install(name: String, image: CGImage) {
        if name.isEmpty {
            fatalError("BackgroundAssets empty name")
        }
        images[name] = image
    }

    static func decode(_ data: Data, name: String) -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            fatalError("BackgroundAssets '\(name)' is not an image")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("BackgroundAssets '\(name)' has no image frames")
        }
        return image
    }
}
