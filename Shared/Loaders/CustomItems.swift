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
            // platform precondition: Application Support always resolves on a real device
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
            print("CustomItems could not create \(dir.path): \(error)")
            return []
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("CustomItems could not list \(dir.path): \(error)")
            return []
        }
        let items = urls.compactMap { url -> Item? in
            if url.pathExtension.lowercased() != ext {
                return nil
            }
            let fileName = url.deletingPathExtension().lastPathComponent
            if fileName.hasPrefix("~") {
                return nil
            }
            let zip: Data
            do {
                zip = try Data(contentsOf: url)
            } catch {
                DispatchQueue.main.async {
                    ToastCenter.show("\(fileName): \(error)")
                }
                return nil
            }
            if !ZipStore.isArchive(zip) {
                return nil
            }
            let names: [String]
            do {
                names = try ZipStore.namesThrowing(in: zip)
            } catch {
                let message = ItemLoadError.text(error)
                DispatchQueue.main.async {
                    ToastCenter.show("\(fileName): \(message)")
                }
                return nil
            }
            if !names.contains("model.xml") || !names.contains("thumb.png") {
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
            assertionFailure("CustomItems empty systemName")
        }
        return directory().appendingPathComponent("\(systemName).\(ext)")
    }

    @discardableResult
    static func delete(_ item: Item) -> Bool {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            print("CustomItems delete \(item.url.lastPathComponent): \(error)")
            return false
        }
        // Manifest caches the customs list. Every mutation must announce itself
        // so the cached `@` pack is reloaded; otherwise itemZip keeps serving
        // the deleted file and dies reading it.
        NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
        return true
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
            throw CopyError.failed("Could not copy the item: \(error.localizedDescription)")
        }
        // See delete: the cached `@` pack must be reloaded after every change.
        NotificationCenter.default.post(name: .customItemsDidChange, object: nil)
    }

    enum CopyError: Error {
        case illegalName
        case exists
        case failed(String)
    }

    private static func displayName(zip: Data, fileName: String) -> String {
        guard let names = try? ZipStore.namesThrowing(in: zip), names.contains("meta.txt") else {
            return fileName
        }
        guard let data = try? ZipStore.dataThrowing(named: "meta.txt", in: zip),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.isEmpty
        else {
            return fileName
        }
        return name
    }
}
