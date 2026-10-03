import Foundation

enum CustomsSeeder {
    /// Written by the old first-launch copy of the three testdata items.
    static let markerName = ".customs1"
    static let names = ["aaa_sword", "akm", "bow"]

    /// Removes that seeded copy once. A later item with one of these names is left alone.
    static func removeSeeded() {
        let destDir = CustomItems.directory()
        let fm = FileManager.default
        let marker = destDir.appendingPathComponent(markerName)
        guard fm.fileExists(atPath: marker.path) else { return }
        for name in names {
            let dest = destDir.appendingPathComponent("\(name).\(CustomItems.ext)")
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
        }
        try? fm.removeItem(at: marker)
    }
}
