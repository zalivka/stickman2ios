import CoreGraphics
import Foundation
import ImageIO

final class BackgroundAssets {
    private var images: [String: CGImage] = [:]
    private var archives: [String: Data] = [:]

    func image(for name: String) -> CGImage {
        guard let image = images[name] else {
            fatalError("BackgroundAssets missing '\(name)'")
        }
        return image
    }

    func hasImage(for name: String) -> Bool {
        images[name] != nil
    }

    func install(name: String, image: CGImage, archive: Data? = nil) {
        if name.isEmpty {
            fatalError("BackgroundAssets empty name")
        }
        images[name] = image
        if let archive {
            if archive.isEmpty {
                fatalError("BackgroundAssets '\(name)' archive is empty")
            }
            archives[name] = archive
        }
    }

    func archive(for name: String) -> Data {
        guard let zip = archives[name] else {
            fatalError("BackgroundAssets missing archive for '\(name)'")
        }
        return zip
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
