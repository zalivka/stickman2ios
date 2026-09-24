import CoreGraphics
import Foundation

/// Android `BackgroundResolver`: turns a picked entry into the `usermade:` id a frame stores.
enum BackgroundResolver {
    /// Android `processPackBg`: pack `zalivka.farm:barn` on a 1280x720 scene becomes
    /// `bgs_ro/zalivka.farm_barn_1280x720.zip`, returned as `usermade:zalivka.farm_barn_1280x720`.
    static func materialize(_ entry: BackgroundEntry, sceneWidth: CGFloat, sceneHeight: CGFloat) throws -> String {
        switch entry.source {
        case .pack(let packName, let ownName):
            let cacheName = "\(packName)_\(ownName)_\(Int(sceneWidth))x\(Int(sceneHeight))"
            if !BackgroundStore.isCached(cacheName) {
                let archive = try BackgroundCatalog.packArchive(packName: packName, ownName: ownName)
                if BackgroundStore.rasterEntry(in: archive) == nil {
                    throw BackgroundStore.Failure.noRaster(entry.id)
                }
                let fm = FileManager.default
                do {
                    try fm.createDirectory(at: BackgroundStore.cacheDirectory(), withIntermediateDirectories: true)
                    try archive.write(to: BackgroundStore.cacheURL(cacheName), options: .atomic)
                } catch {
                    throw BackgroundStore.Failure.writeFailed(entry.id, error)
                }
            }
            return BackgroundStore.usermadePrefix + cacheName
        case .embedded:
            throw BackgroundStore.Failure.unsupported(entry.id)
        case .user(let ownName):
            return BackgroundStore.usermadePrefix + ownName
        }
    }

    /// Decodes the on-disk archive for `bgName` into `backgrounds` unless it is already there.
    static func install(_ bgName: String, into backgrounds: BackgroundAssets) throws {
        if backgrounds.hasImage(for: bgName) {
            return
        }
        let url = try BackgroundStore.archiveURL(usermade: bgName)
        let archive: Data
        do {
            archive = try Data(contentsOf: url)
        } catch {
            throw BackgroundStore.Failure.missingArchive(bgName)
        }
        try backgrounds.installArchive(name: bgName, archive: archive)
    }

    /// Android `buildFittedMoveForBackground`: match scene width, centre both axes.
    static func fittedMove(image: CGImage, sceneWidth: CGFloat, sceneHeight: CGFloat) -> PictureMove {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        if width <= 0 || height <= 0 {
            return .identity
        }
        let scale = max(sceneWidth, 1) / width
        return PictureMove(
            scale: scale,
            rotate: 0,
            x: (sceneWidth - width * scale) / 2,
            y: (sceneHeight - height * scale) / 2
        )
    }
}
