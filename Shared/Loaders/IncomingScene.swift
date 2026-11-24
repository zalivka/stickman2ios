import Foundation

extension Notification.Name {
    static let savedScenesDidChange = Notification.Name("savedScenesDidChange")
    static let customItemsDidChange = Notification.Name("customItemsDidChange")
}

enum IncomingScene {
    enum Failure: Error, CustomStringConvertible {
        case notAScene
        case readFailed(Error)
        case writeFailed(Error)

        var description: String {
            switch self {
            case .notAScene:
                return "This file is not a scene. It has no model.xml."
            case .readFailed(let error):
                return "Could not read the scene: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Could not save the scene: \(error.localizedDescription)"
            }
        }
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
        let names: [String]
        do {
            names = try ZipStore.namesThrowing(in: zip)
        } catch {
            throw Failure.notAScene
        }
        if !names.contains("model.xml") {
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

enum IncomingFile {
    static func importURL(_ url: URL) async -> String {
        do {
            switch url.pathExtension.lowercased() {
            case CustomItems.ext:
                try await IncomingItem.importURL(url)
                Analytics.event("entry_item")
                return "Item copied"
            case SceneSaver.ext:
                try IncomingScene.importURL(url)
                Analytics.event("entry_saved")
                return "Scene copied"
            case InstalledPacks.ext:
                let pack = try await IncomingPack.importURL(url)
                Analytics.event("entry_pack")
                return "Installing \(pack.name), version \(pack.version)"
            default:
                return "This file is not a scene (.ats), an item (.ati), or a pack (.atp)."
            }
        } catch {
            return ItemLoadError.text(error)
        }
    }
}
