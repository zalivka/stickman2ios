import CoreGraphics
import Foundation

/// Android `SceneManager.getAllBackgrounds`, raster pack sources only.
enum BackgroundCatalog {
    struct Folder: Identifiable {
        var id: String { packName }
        var packName: String
        var title: String
        var entries: [BackgroundEntry]
    }

    static func packFolders() -> [Folder] {
        var folders: [Folder] = []
        for url in ExternalPack.bundleArchives() {
            let packName = url.deletingPathExtension().lastPathComponent
            let entries = packEntries(packName: packName, zip: ExternalPack.mappedZip(url))
            if entries.isEmpty {
                continue
            }
            let title = Manifest.shared.pack(named: packName)?.humanName ?? packName
            folders.append(Folder(packName: packName, title: title.isEmpty ? packName : title, entries: entries))
        }
        return folders
    }

    /// Pack `bgs/<name>.zip`, as Android `ExternalPack.getPackBgs`.
    static func packArchive(packName: String, ownName: String) throws -> Data {
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        let entry = "bgs/\(ownName).\(BackgroundStore.ext)"
        if !ZipStore.contains(entry, in: zip) {
            throw BackgroundStore.Failure.missingArchive("\(packName):\(ownName)")
        }
        return ZipStore.data(named: entry, in: zip)
    }

    private static func packEntries(packName: String, zip: Data) -> [BackgroundEntry] {
        let prefix = "bgs/"
        let suffix = ".\(BackgroundStore.ext)"
        var entries: [BackgroundEntry] = []
        for name in ZipStore.names(in: zip).sorted() {
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
                continue
            }
            let own = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            if own.isEmpty || own.contains("/") {
                continue
            }
            let nested = ZipStore.data(named: name, in: zip)
            if BackgroundStore.rasterEntry(in: nested) == nil {
                continue
            }
            entries.append(BackgroundEntry(
                source: .pack(packName: packName, ownName: own),
                thumb: thumb(in: nested)
            ))
        }
        return entries
    }

    private static func thumb(in nested: Data) -> CGImage? {
        if !ZipStore.contains("thumb.png", in: nested) {
            return nil
        }
        return BackgroundAssets.tryDecode(ZipStore.data(named: "thumb.png", in: nested))
    }
}
