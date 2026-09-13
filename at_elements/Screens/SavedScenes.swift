import Foundation

enum SavedScenes {
    struct Item: Identifiable {
        var id: String { cacheKey }
        var name: String
        var url: URL
        var mtime: TimeInterval
        var cacheKey: String { "saved:\(name)|\(mtime)" }
    }

    static func collectDemos() -> [Item] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ats", subdirectory: "demo") else {
            fatalError("SavedScenes missing demo/")
        }
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
        if items.isEmpty {
            fatalError("SavedScenes demo/ has no .ats")
        }
        return items.sorted {
            if $0.mtime != $1.mtime {
                return $0.mtime > $1.mtime
            }
            return $0.name < $1.name
        }
    }
}
