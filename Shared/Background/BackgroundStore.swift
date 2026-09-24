import Foundation

/// Android `StickmanApp.CUSTOM_BG_DIR` / `CUSTOM_BG_DIR_RO`: user archives and sized caches,
/// each `name.zip` holding `bg.png` or `bg.jpg` plus `thumb.png`.
enum BackgroundStore {
    static let usermadePrefix = "usermade:"
    static let ext = "zip"

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

    private static func root() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("BackgroundStore has no Application Support")
        }
        return root.appendingPathComponent("at_elements", isDirectory: true)
    }
}
