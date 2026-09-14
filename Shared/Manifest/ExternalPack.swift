import Foundation

enum ExternalPack {
    static func bundleArchives() -> [URL] {
        guard let root = Bundle.main.resourceURL else {
            fatalError("Manifest missing resourceURL")
        }
        let dir = root.appendingPathComponent("packs", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            fatalError("Manifest missing packs/ at \(dir.path)")
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "atp" }
        } catch {
            fatalError("Manifest list \(dir.path): \(error)")
        }
        if urls.isEmpty {
            fatalError("Manifest missing packs/*.atp")
        }
        if !urls.contains(where: { $0.deletingPathExtension().lastPathComponent == "template.basic" }) {
            fatalError("Manifest missing packs/template.basic.atp")
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func bundleArchive(_ packName: String) -> URL {
        let matches = bundleArchives().filter { $0.deletingPathExtension().lastPathComponent == packName }
        if matches.count != 1 {
            fatalError("Manifest pack '\(packName)' archives \(matches.map(\.lastPathComponent))")
        }
        return matches[0]
    }

    static func mappedZip(_ url: URL) -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            fatalError("ExternalPack could not map \(url.path): \(error)")
        }
    }
}
