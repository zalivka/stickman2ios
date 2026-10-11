import Foundation

nonisolated enum ExternalPack {
    static func bundleArchives() -> [URL] {
        guard let root = Bundle.main.resourceURL else {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest missing resourceURL")
        }
        let dir = root.appendingPathComponent("packs", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest missing packs/ at \(dir.path)")
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "atp" }
        } catch {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest list \(dir.path): \(error)")
        }
        if urls.isEmpty {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest missing packs/*.atp")
        }
        if !urls.contains(where: { $0.deletingPathExtension().lastPathComponent == "template.basic" }) {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest missing packs/template.basic.atp")
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func bundleArchive(_ packName: String) -> URL {
        let matches = bundleArchives().filter { $0.deletingPathExtension().lastPathComponent == packName }
        if matches.count != 1 {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("Manifest pack '\(packName)' archives \(matches.map(\.lastPathComponent))")
        }
        return matches[0]
    }

    static func mappedZip(_ url: URL) -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            // bundled pack: a failure here ships broken, fires on first debug run
            fatalError("ExternalPack could not map \(url.path): \(error)")
        }
    }
}
