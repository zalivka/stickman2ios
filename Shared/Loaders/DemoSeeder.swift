import Foundation

enum DemoSeeder {
    static let markerName = ".demo1"

    static func copyIfNeeded() {
        let destDir = SceneSaver.savedDirectory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            print("DemoSeeder could not create \(destDir.path): \(error)")
            return
        }
        let marker = destDir.appendingPathComponent(markerName)
        if fm.fileExists(atPath: marker.path) {
            return
        }
        guard let urls = Bundle.main.urls(forResourcesWithExtension: SceneSaver.ext, subdirectory: "demo") else {
            // bundled resource: a failure here ships broken, fires on first debug run
            fatalError("DemoSeeder missing demo/")
        }
        if urls.isEmpty {
            // bundled resource: a failure here ships broken, fires on first debug run
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
                print("DemoSeeder copy \(src.lastPathComponent): \(error)")
            }
        }
        if !fm.createFile(atPath: marker.path, contents: Data()) {
            print("DemoSeeder could not write \(marker.path)")
        }
    }
}
