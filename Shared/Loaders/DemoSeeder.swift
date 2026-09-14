import Foundation

enum DemoSeeder {
    static let markerName = ".demo1"

    static func copyIfNeeded() {
        let destDir = SceneSaver.savedDirectory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            fatalError("DemoSeeder could not create \(destDir.path): \(error)")
        }
        let marker = destDir.appendingPathComponent(markerName)
        if fm.fileExists(atPath: marker.path) {
            return
        }
        guard let urls = Bundle.main.urls(forResourcesWithExtension: SceneSaver.ext, subdirectory: "demo") else {
            fatalError("DemoSeeder missing demo/")
        }
        if urls.isEmpty {
            fatalError("DemoSeeder demo/ has no .ats")
        }
        for src in urls {
            let dest = destDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                continue
            }
            do {
                try fm.copyItem(at: src, to: dest)
            } catch {
                fatalError("DemoSeeder copy \(src.lastPathComponent): \(error)")
            }
        }
        if !fm.createFile(atPath: marker.path, contents: Data()) {
            fatalError("DemoSeeder could not write \(marker.path)")
        }
    }
}
