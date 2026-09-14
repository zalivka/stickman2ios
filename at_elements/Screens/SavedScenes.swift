import Foundation

enum SavedScenes {
    struct Item: Identifiable {
        var id: String { cacheKey }
        var name: String
        var url: URL
        var mtime: TimeInterval
        var cacheKey: String { "saved:\(url.path)|\(mtime)" }
    }

    static func collect() -> [Item] {
        collectSaved()
    }

    static func collectSaved() -> [Item] {
        let dir = SceneSaver.savedDirectory()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
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
            fatalError("SavedScenes could not list \(dir.path): \(error)")
        }
        return items(from: urls.filter { $0.pathExtension.lowercased() == SceneSaver.ext })
    }

    private static func items(from urls: [URL]) -> [Item] {
        let items = urls.compactMap { url -> Item? in
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("~") || name.hasPrefix("best_") {
                return nil
            }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?
                .timeIntervalSince1970 ?? 0
            return Item(name: name, url: url, mtime: mtime)
        }
        return items.sorted {
            if $0.mtime != $1.mtime {
                return $0.mtime > $1.mtime
            }
            return $0.name < $1.name
        }
    }
}
