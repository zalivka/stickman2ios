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
            // Bundled pack: an unreadable archive is a broken IPA, same as obtainBundlePack.
            let entries = packEntries(packName: packName, zip: ExternalPack.mappedZip(url))
            if entries.isEmpty {
                continue
            }
            let title = Manifest.shared.pack(named: packName)?.humanName ?? packName
            folders.append(Folder(packName: packName, title: title.isEmpty ? packName : title, entries: entries))
        }
        return folders
    }

    /// Drawn backgrounds in `bgs`, newest first; nil when there are none.
    static func userFolder() -> Folder? {
        var entries: [BackgroundEntry] = []
        for url in BackgroundStore.userArchives() {
            let own = url.deletingPathExtension().lastPathComponent
            // The file can vanish or be mid-write; skip it, the list survives.
            guard let archive = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                continue
            }
            if BackgroundStore.rasterEntry(in: archive) == nil {
                continue
            }
            guard let thumb = thumb(in: archive) else {
                continue
            }
            entries.append(BackgroundEntry(source: .user(ownName: own), thumb: thumb))
        }
        if entries.isEmpty {
            return nil
        }
        return Folder(packName: BackgroundEntry.userFolder, title: "My backgrounds", entries: entries)
    }

    /// Pack `bgs/<name>.zip`, as Android `ExternalPack.getPackBgs`.
    static func packArchive(packName: String, ownName: String) throws -> Data {
        let zip = ExternalPack.mappedZip(ExternalPack.bundleArchive(packName))
        let entry = "bgs/\(ownName).\(BackgroundStore.ext)"
        do {
            return try ZipStore.dataThrowing(named: entry, in: zip)
        } catch {
            throw BackgroundStore.Failure.missingArchive("\(packName):\(ownName)")
        }
    }

    private static func packEntries(packName: String, zip: Data) -> [BackgroundEntry] {
        let prefix = "bgs/"
        let suffix = ".\(BackgroundStore.ext)"
        guard let names = try? ZipStore.namesThrowing(in: zip) else {
            return []
        }
        var entries: [BackgroundEntry] = []
        for name in names.sorted() {
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
                continue
            }
            let own = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            if own.isEmpty || own.contains("/") {
                continue
            }
            guard let nested = try? ZipStore.dataThrowing(named: name, in: zip) else {
                continue
            }
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
        guard let data = try? ZipStore.dataThrowing(named: "thumb.png", in: nested) else {
            return nil
        }
        return BackgroundAssets.tryDecode(data)
    }
}
