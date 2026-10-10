import CoreGraphics
import Foundation
import ImageIO

final class BackgroundAssets {
    private var images: [String: CGImage] = [:]
    private var archives: [String: Data] = [:]
    /// Backgrounds a loaded scene referenced but could not show; those frames fall back to white.
    private(set) var loadErrors: [String] = []

    /// Nil when the background is not installed; draw sites fall back to the scene fill.
    func image(for name: String) -> CGImage? {
        images[name]
    }

    func hasImage(for name: String) -> Bool {
        images[name] != nil
    }

    func install(name: String, image: CGImage, archive: Data? = nil) {
        if name.isEmpty {
            assertionFailure("BackgroundAssets empty name")
            return
        }
        images[name] = image
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
        guard let image = Self.tryDecode(try ZipStore.dataThrowing(named: entry, in: archive)) else {
            throw BackgroundStore.Failure.notAnImage(name)
        }
        install(name: name, image: image, archive: archive)
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
}
