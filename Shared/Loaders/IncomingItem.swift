import Foundation

enum IncomingItem {
    enum Failure: Error {
        case notAnItem
        case foreignPack
        case illegalName
        case readFailed(Error)
        case writeFailed(Error)
    }

    static func importURL(_ url: URL) async throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            throw Failure.readFailed(error)
        }
        if !isItem(zip) {
            throw Failure.notAnItem
        }
        if rejectsForeignPack(zip) {
            throw Failure.foreignPack
        }
        let name = incomingName(from: zip, fileURL: url)
        if !SceneSaver.isGoodFileName(name) {
            throw Failure.illegalName
        }
        let dir = CustomItems.directory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw Failure.writeFailed(error)
        }
        let dest = dir.appendingPathComponent("\(name).\(CustomItems.ext)")
        if fm.fileExists(atPath: dest.path) {
            do {
                try fm.removeItem(at: dest)
            } catch {
                throw Failure.writeFailed(error)
            }
        }
        do {
            try zip.write(to: dest, options: .atomic)
        } catch {
            throw Failure.writeFailed(error)
        }
        _ = await Manifest.shared.requestReloadCustomPack()
        NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
    }

    /// Android `EntryActivity.getType` ITEM: a `.name` tag, `assets.xml`, or an `svg` entry.
    private static func isItem(_ zip: Data) -> Bool {
        if ZipStore.contains("assets.xml", in: zip) {
            return true
        }
        for name in ZipStore.names(in: zip) {
            let base = (name as NSString).lastPathComponent
            if base.hasSuffix(".name"), base != ".name" {
                return true
            }
            if name == "svg" || name == "svg/" || name.hasPrefix("svg/") {
                return true
            }
        }
        return false
    }

    /// Android `ProcessItemTask`: a `meta.txt` pack other than `@` is not a custom item.
    private static func rejectsForeignPack(_ zip: Data) -> Bool {
        if !ZipStore.contains("meta.txt", in: zip) {
            return false
        }
        let data = ZipStore.data(named: "meta.txt", in: zip)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pack = object["pack"] as? String
        else {
            return false
        }
        return pack != Pack.customName
    }

    /// Android `EntryActivity.getName`: stem of the first `*.name` entry, else the filename stem.
    private static func incomingName(from zip: Data, fileURL: URL) -> String {
        if let entry = ZipStore.names(in: zip).first(where: { name in
            let base = (name as NSString).lastPathComponent
            return base.hasSuffix(".name") && base != ".name"
        }) {
            return ((entry as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return fileURL.deletingPathExtension().lastPathComponent
    }
}
