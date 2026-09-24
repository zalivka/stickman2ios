import CoreGraphics
import Foundation
import ImageIO

final class BackgroundAssets {
    private var images: [String: CGImage] = [:]
    private var archives: [String: Data] = [:]
    /// Backgrounds a loaded scene referenced but could not show; those frames fall back to white.
    private(set) var loadErrors: [String] = []

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

    /// A `usermade:` archive with `bg.png` or `bg.jpg`, kept whole so the scene saves it as `_bgs/<own>.zip`.
    func installArchive(name: String, archive: Data) throws {
        guard let entry = BackgroundStore.rasterEntry(in: archive) else {
            throw BackgroundStore.Failure.noRaster(name)
        }
        guard let image = Self.tryDecode(ZipStore.data(named: entry, in: archive)) else {
            throw BackgroundStore.Failure.notAnImage(name)
        }
        install(name: name, image: image, archive: archive)
    }

    func recordLoadError(_ message: String) {
        loadErrors.append(message)
    }

    func archive(for name: String) -> Data {
        guard let zip = archives[name] else {
            fatalError("BackgroundAssets missing archive for '\(name)'")
        }
        return zip
    }

    static func decode(_ data: Data, name: String) -> CGImage {
        guard let image = tryDecode(data) else {
            fatalError("BackgroundAssets '\(name)' is not an image")
        }
        return image
    }

    static func tryDecode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
