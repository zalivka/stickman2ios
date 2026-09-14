import Foundation

enum CustomsSeeder {
    static let markerName = ".customs1"
    static let names = ["aaa_sword", "akm", "bow"]

    static func copyIfNeeded() {
        let destDir = CustomItems.directory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            fatalError("CustomsSeeder could not create \(destDir.path): \(error)")
        }
        let marker = destDir.appendingPathComponent(markerName)
        if fm.fileExists(atPath: marker.path) {
            return
        }
        for name in names {
            guard let src = Bundle.main.url(forResource: name, withExtension: CustomItems.ext, subdirectory: "testdata") else {
                fatalError("CustomsSeeder missing testdata/\(name).\(CustomItems.ext)")
            }
            let dest = destDir.appendingPathComponent("\(name).\(CustomItems.ext)")
            if fm.fileExists(atPath: dest.path) {
                continue
            }
            do {
                try fm.copyItem(at: src, to: dest)
            } catch {
                fatalError("CustomsSeeder copy \(name).\(CustomItems.ext): \(error)")
            }
        }
        if !fm.createFile(atPath: marker.path, contents: Data()) {
            fatalError("CustomsSeeder could not write \(marker.path)")
        }
    }
}
