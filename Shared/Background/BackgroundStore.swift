import Foundation
import UIKit

/// Android `StickmanApp.CUSTOM_BG_DIR` / `CUSTOM_BG_DIR_RO`: user archives and sized caches,
/// each `name.zip` holding `bg.png` or `bg.jpg` plus `thumb.png`.
enum BackgroundStore {
    static let usermadePrefix = "usermade:"
    static let ext = "zip"
    static let thumbSide = 100

    enum Failure: Error, CustomStringConvertible {
        case unsupported(String)
        case missingArchive(String)
        case noRaster(String)
        case notAnImage(String)
        case writeFailed(String, Error)

        var description: String {
            switch self {
            case .unsupported(let name):
                return "Unsupported background \(name)"
            case .missingArchive(let name):
                return "Missing background \(name)"
            case .noRaster(let name):
                return "Background \(name) has no bg.png or bg.jpg"
            case .notAnImage(let name):
                return "Background \(name) is not an image"
            case .writeFailed(let name, let error):
                return "Cannot save background \(name): \(error.localizedDescription)"
            }
        }
    }

    static func userDirectory() -> URL {
        root().appendingPathComponent("bgs", isDirectory: true)
    }

    static func cacheDirectory() -> URL {
        root().appendingPathComponent("bgs_ro", isDirectory: true)
    }

    /// Android `BackgroundData.findArchiveOfUsermade`: `bgs` first, then `bgs_ro`.
    static func archiveURL(usermade bgName: String) throws -> URL {
        let own = SceneLoader.ownName(bgName)
        let fm = FileManager.default
        for dir in [userDirectory(), cacheDirectory()] {
            let url = dir.appendingPathComponent("\(own).\(ext)")
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        throw Failure.missingArchive(bgName)
    }

    /// Writes `bgs/<millis>.zip` with `bg.png` and a cover-cropped `thumb.png`; returns `usermade:<millis>` and the zip.
    static func saveDrawn(_ image: CGImage) throws -> (bgName: String, archive: Data) {
        let own = "\(Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)))"
        let bgName = usermadePrefix + own
        let archive = ZipStore.archive([
            (name: "bg.png", data: png(image, name: bgName)),
            (name: "thumb.png", data: png(thumb(image), name: bgName)),
        ])
        do {
            try FileManager.default.createDirectory(at: userDirectory(), withIntermediateDirectories: true)
            try archive.write(to: userDirectory().appendingPathComponent("\(own).\(ext)"), options: .atomic)
        } catch {
            throw Failure.writeFailed(bgName, error)
        }
        return (bgName, archive)
    }

    /// Overwrites `bgs/<own>.zip` for an existing `usermade:` name. The scene keeps that name.
    static func replaceDrawn(_ bgName: String, image: CGImage) throws -> Data {
        let own = SceneLoader.ownName(bgName)
        if own.isEmpty || own.contains("/") {
            fatalError("BackgroundStore replaceDrawn own name '\(own)'")
        }
        let archive = ZipStore.archive([
            (name: "bg.png", data: png(image, name: bgName)),
            (name: "thumb.png", data: png(thumb(image), name: bgName)),
        ])
        do {
            try FileManager.default.createDirectory(at: userDirectory(), withIntermediateDirectories: true)
            try archive.write(to: userDirectory().appendingPathComponent("\(own).\(ext)"), options: .atomic)
        } catch {
            throw Failure.writeFailed(bgName, error)
        }
        return archive
    }

    static func deleteUser(ownName: String) throws {
        if ownName.isEmpty || ownName.contains("/") {
            fatalError("BackgroundStore deleteUser own name '\(ownName)'")
        }
        let url = userDirectory().appendingPathComponent("\(ownName).\(ext)")
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            throw Failure.missingArchive(usermadePrefix + ownName)
        }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw Failure.writeFailed(usermadePrefix + ownName, error)
        }
    }

    /// `bgs/*.zip`, newest first.
    static func userArchives() -> [URL] {
        let fm = FileManager.default
        let dir = userDirectory()
        if !fm.fileExists(atPath: dir.path) {
            return []
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch {
            fatalError("BackgroundStore cannot list \(dir.path): \(error)")
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return urls
            .filter { $0.pathExtension == ext }
            .sorted { modified($0) > modified($1) }
    }

    static func isCached(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(name).path)
    }

    static func cacheURL(_ name: String) -> URL {
        cacheDirectory().appendingPathComponent("\(name).\(ext)")
    }

    /// Android `BackgroundAsyncCache.loadFromArchive` raster order.
    static func rasterEntry(in zip: Data) -> String? {
        let names = ZipStore.names(in: zip)
        if names.contains("bg.png") {
            return "bg.png"
        }
        if names.contains("bg.jpg") {
            return "bg.jpg"
        }
        return nil
    }

    private static func png(_ image: CGImage, name: String) -> Data {
        guard let data = UIImage(cgImage: image).pngData(), !data.isEmpty else {
            fatalError("BackgroundStore PNG encode failed for \(name)")
        }
        return data
    }

    /// Cover scale into a `thumbSide` square, centre crop.
    private static func thumb(_ image: CGImage) -> CGImage {
        let side = CGFloat(thumbSide)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = max(side / width, side / height)
        let drawn = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(
                x: (side - drawn.width) / 2,
                y: (side - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
        guard let cg = rendered.cgImage else {
            fatalError("BackgroundStore thumb render failed")
        }
        return cg
    }

    private static func root() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("BackgroundStore has no Application Support")
        }
        return root.appendingPathComponent("at_elements", isDirectory: true)
    }
}
