import Foundation

extension Notification.Name {
    static let savedScenesDidChange = Notification.Name("savedScenesDidChange")
    static let customItemsDidChange = Notification.Name("customItemsDidChange")
}

enum IncomingScene {
    enum Failure: Error {
        case notAScene
        case readFailed(Error)
        case writeFailed(Error)
    }

    static func importURL(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            throw Failure.readFailed(error)
        }
        if !ZipStore.contains("model.xml", in: zip) {
            throw Failure.notAScene
        }
        let name = SceneSaver.incomingName(from: zip)
        let dir = SceneSaver.savedDirectory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw Failure.writeFailed(error)
        }
        let dest = dir.appendingPathComponent("\(name).\(SceneSaver.ext)")
        if fm.fileExists(atPath: dest.path) {
            do {
                try fm.removeItem(at: dest)
            } catch {
                throw Failure.writeFailed(error)
            }
        }
        do {
            try zip.write(to: dest, options: .atomic)
        } catch {
            throw Failure.writeFailed(error)
        }
        NotificationCenter.default.post(name: .savedScenesDidChange, object: nil)
    }
}
