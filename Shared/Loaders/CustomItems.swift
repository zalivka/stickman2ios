import Foundation

nonisolated enum CustomItems {
    static let ext = "ati"

    struct Item: Identifiable {
        var id: String { cacheKey }
        var systemName: String
        var name: String
        var url: URL
        var mtime: TimeInterval
        var cacheKey: String { "custom:\(url.path)|\(mtime)" }
    }

    static func directory() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("CustomItems has no Application Support")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("customs", isDirectory: true)
    }

    static func collect() -> [Item] {
        let dir = directory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fatalError("CustomItems could not create \(dir.path): \(error)")
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            fatalError("CustomItems could not list \(dir.path): \(error)")
        }
        let items = urls.compactMap { url -> Item? in
            if url.pathExtension.lowercased() != ext {
                return nil
            }
            let fileName = url.deletingPathExtension().lastPathComponent
            if fileName.hasPrefix("~") {
                return nil
            }
            guard let zip = try? Data(contentsOf: url),
                  ZipStore.contains("model.xml", in: zip),
                  ZipStore.contains("thumb.png", in: zip)
            else {
                return nil
            }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?
                .timeIntervalSince1970 ?? 0
            return Item(
                systemName: fileName,
                name: displayName(zip: zip, fileName: fileName),
                url: url,
                mtime: mtime
            )
        }
        return items.sorted {
            if $0.mtime != $1.mtime {
                return $0.mtime > $1.mtime
            }
            return $0.name < $1.name
        }
    }

    static func file(systemName: String) -> URL {
        if systemName.isEmpty {
            fatalError("CustomItems empty systemName")
        }
        return directory().appendingPathComponent("\(systemName).\(ext)")
    }

    static func zipData(systemName: String) -> Data {
        let url = file(systemName: systemName)
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("CustomItems could not read \(url.path): \(error)")
        }
    }

    static func delete(_ item: Item) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            fatalError("CustomItems delete \(item.url.lastPathComponent): \(error)")
        }
        // Manifest caches the customs list. Every mutation must announce itself
        // so the cached `@` pack is reloaded; otherwise itemZip keeps serving
        // the deleted file and dies reading it.
        NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
    }

    static func copy(_ item: Item, as rawName: String) throws {
        if !SceneSaver.isGoodFileName(rawName) {
            throw CopyError.illegalName
        }
        let name = rawName.replacingOccurrences(of: " ", with: "_")
        let dest = directory().appendingPathComponent("\(name).\(ext)")
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            throw CopyError.exists
        }
        do {
            try fm.copyItem(at: item.url, to: dest)
        } catch {
            fatalError("CustomItems copy \(item.url.lastPathComponent): \(error)")
        }
        // See delete: the cached `@` pack must be reloaded after every change.
        NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
    }

    enum CopyError: Error {
        case illegalName
        case exists
    }

    private static func displayName(zip: Data, fileName: String) -> String {
        guard ZipStore.contains("meta.txt", in: zip) else {
            return fileName
        }
        let data = ZipStore.data(named: "meta.txt", in: zip)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["name"] as? String,
           !name.isEmpty
        {
            return name
        }
        return fileName
    }
}
