import Foundation
import UIKit

/// Android `ImageLibraryRepository`: user-imported raster images in `Application Support/at_elements/image_library/`,
/// each saved as `<id>.png` (capped at 2048px) and `<id>_thumb.png` (capped at 256px).
enum ImageLibrary {
    static let maxDimension = 2048
    static let thumbMaxDimension = 256
    private static let thumbSuffix = "_thumb.png"
    private static let mainExt = ".png"

    struct Entry: Identifiable, Equatable {
        var id: String
        var mainURL: URL
        var thumbURL: URL
    }

    enum Failure: Error, CustomStringConvertible, LocalizedError {
        case invalidIdentifier(String)
        case unreadableImage(String)
        case encodeFailed(String)
        case ioFailed(String, Error)

        var description: String {
            switch self {
            case .invalidIdentifier(let id):
                return "Invalid image id '\(id)'"
            case .unreadableImage(let label):
                return "Could not decode image '\(label)'"
            case .encodeFailed(let label):
                return "Could not encode PNG for '\(label)'"
            case .ioFailed(let label, let error):
                return "Image library error (\(label)): \(error.localizedDescription)"
            }
        }

        var errorDescription: String? { description }
    }

    static func libraryDirectory() throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // platform precondition: Application Support always resolves on a real device
            fatalError("ImageLibrary has no Application Support")
        }
        let dir = root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("image_library", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw Failure.ioFailed(dir.path, error)
            }
        }
        return dir
    }

    /// Lists all entries in `directory` (or `libraryDirectory()`), newest id first like Android `ImageLibraryRepository.list()`.
    static func list(in directory: URL? = nil) throws -> [Entry] {
        let dir = try resolveDirectory(directory)
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw Failure.ioFailed(dir.path, error)
        }
        var entries: [Entry] = []
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasSuffix(mainExt), !name.hasSuffix(thumbSuffix) else {
                continue
            }
            let id = String(name.dropLast(mainExt.count))
            guard !id.isEmpty else {
                continue
            }
            let thumb = thumbFile(id: id, in: dir)
            if !fm.fileExists(atPath: thumb.path) {
                try regenerateThumb(mainURL: url, thumbURL: thumb)
            }
            entries.append(Entry(id: id, mainURL: url, thumbURL: thumb))
        }
        entries.sort { $0.id > $1.id }
        return entries
    }

    static func ingest(url: URL, in directory: URL? = nil) throws -> Entry {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.ioFailed(url.lastPathComponent, error)
        }
        return try ingest(data: data, label: url.lastPathComponent, in: directory)
    }

    static func ingest(data: Data, label: String = "image", in directory: URL? = nil) throws -> Entry {
        guard !data.isEmpty, let decoded = UIImage(data: data) else {
            throw Failure.unreadableImage(label)
        }
        let normalized = reasonableImage(decoded, minDesiredWidth: maxDimension, minDesiredHeight: maxDimension)
        guard let mainData = normalized.pngData(), !mainData.isEmpty else {
            throw Failure.encodeFailed(label)
        }
        let thumbImage = makeThumb(normalized)
        guard let thumbData = thumbImage.pngData(), !thumbData.isEmpty else {
            throw Failure.encodeFailed("\(label) thumb")
        }

        let dir = try resolveDirectory(directory)
        let id = allocateId(in: dir)
        let mainURL = mainFile(id: id, in: dir)
        let thumbURL = thumbFile(id: id, in: dir)

        do {
            try mainData.write(to: mainURL, options: .atomic)
            try thumbData.write(to: thumbURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: thumbURL)
            throw Failure.ioFailed(id, error)
        }
        return Entry(id: id, mainURL: mainURL, thumbURL: thumbURL)
    }

    static func delete(id: String, in directory: URL? = nil) throws {
        if id.isEmpty || id.contains("/") {
            throw Failure.invalidIdentifier(id)
        }
        let dir = try resolveDirectory(directory)
        let fm = FileManager.default
        let mainURL = mainFile(id: id, in: dir)
        let thumbURL = thumbFile(id: id, in: dir)
        if fm.fileExists(atPath: mainURL.path) {
            do {
                try fm.removeItem(at: mainURL)
            } catch {
                throw Failure.ioFailed(id, error)
            }
        }
        if fm.fileExists(atPath: thumbURL.path) {
            do {
                try fm.removeItem(at: thumbURL)
            } catch {
                throw Failure.ioFailed("\(id)_thumb", error)
            }
        }
    }

    /// Halves dimensions by powers of 2 while `width > minDesiredWidth` or `height > minDesiredHeight`.
    static func reasonableImage(_ image: UIImage, minDesiredWidth: Int, minDesiredHeight: Int) -> UIImage {
        let pixelWidth = Int((image.size.width * image.scale).rounded())
        let pixelHeight = Int((image.size.height * image.scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            return image
        }
        var tmpWidth = pixelWidth
        var tmpHeight = pixelHeight
        var sampleSize = 1
        while tmpWidth > minDesiredWidth || tmpHeight > minDesiredHeight {
            tmpWidth /= 2
            tmpHeight /= 2
            sampleSize *= 2
        }
        let targetSize = CGSize(
            width: max(1, pixelWidth / sampleSize),
            height: max(1, pixelHeight / sampleSize)
        )
        if sampleSize == 1, image.imageOrientation == .up, image.scale == 1.0,
           image.size == targetSize {
            return image
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Android `ImageLibraryRepository.makeThumb`: square thumbnail of size `thumbMaxDimension`,
    /// scaled by `thumbMaxDimension / min(width, height)` over a white background.
    static func makeThumb(_ image: UIImage) -> UIImage {
        let side = CGFloat(thumbMaxDimension)
        let w = max(1, image.size.width * image.scale)
        let h = max(1, image.size.height * image.scale)
        let ratio = side / min(w, h)
        let drawn = CGSize(width: w * ratio, height: h * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(origin: .zero, size: drawn))
        }
    }

    // MARK: - Private

    private static func resolveDirectory(_ custom: URL?) throws -> URL {
        if let custom {
            if !FileManager.default.fileExists(atPath: custom.path) {
                do {
                    try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
                } catch {
                    throw Failure.ioFailed(custom.path, error)
                }
            }
            return custom
        }
        return try libraryDirectory()
    }

    private static func mainFile(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id)\(mainExt)", isDirectory: false)
    }

    private static func thumbFile(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id)\(thumbSuffix)", isDirectory: false)
    }

    private static func allocateId(in directory: URL) -> String {
        let fm = FileManager.default
        var ts = Int64((Date().timeIntervalSince1970 * 1000).rounded(.towardZero))
        while fm.fileExists(atPath: mainFile(id: String(ts), in: directory).path) {
            ts += 1
        }
        return String(ts)
    }

    private static func regenerateThumb(mainURL: URL, thumbURL: URL) throws {
        guard let data = try? Data(contentsOf: mainURL), let main = UIImage(data: data) else {
            throw Failure.unreadableImage(mainURL.lastPathComponent)
        }
        let thumb = makeThumb(main)
        guard let png = thumb.pngData(), !png.isEmpty else {
            throw Failure.encodeFailed(thumbURL.lastPathComponent)
        }
        do {
            try png.write(to: thumbURL, options: .atomic)
        } catch {
            throw Failure.ioFailed(thumbURL.lastPathComponent, error)
        }
    }
}
