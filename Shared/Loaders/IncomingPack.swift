import Foundation

/// Android `EntryActivity.processPack`: copy a user `.atp` to `{mSysName}.atp` after it parses.
nonisolated enum IncomingPack {
    enum Failure: Error, CustomStringConvertible {
        case rejected(String)

        var description: String {
            switch self {
            case .rejected(let message):
                return message
            }
        }
    }

    static func importURL(_ url: URL) async throws -> Pack {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var label = url.lastPathComponent
        do {
            let pack = try install(url, label: &label)
            _ = await Manifest.shared.requestReload()
            guard Manifest.shared.pack(named: pack.name) != nil else {
                throw Failure.rejected("Could not install \(pack.name): the pack did not load")
            }
            NotificationCenter.default.post(name: .installedPacksDidChange, object: nil)
            return pack
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.rejected(installMessage(label, error))
        }
    }

    private static func install(_ url: URL, label: inout String) throws -> Pack {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        } catch {
            throw ZipError(message: "could not read the file: \(error)")
        }
        if values.isDirectory == true {
            throw ZipError(message: "this file is a directory")
        }
        let size = values.fileSize ?? 0
        if size <= 0 || size > InstalledPacks.maxFileBytes {
            throw ZipError(message: "this file is \(size) bytes")
        }
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            throw ZipError(message: "could not read the file: \(error)")
        }
        if !ZipStore.isArchive(zip) {
            throw ZipError(message: "this file is not a zip")
        }
        let names = try ZipStore.namesThrowing(in: zip)
        if !names.contains("meta.txt") {
            throw ZipError(message: "missing meta.txt")
        }
        let meta = try PackMeta.parse(
            ZipStore.dataThrowing(named: "meta.txt", in: zip),
            source: "\(label)/meta.txt"
        )
        label = meta.mSysName
        if !InstalledPacks.isPackSysName(meta.mSysName) {
            throw ZipError(message: "mSysName '\(meta.mSysName)' is not a pack name")
        }
        if InstalledPacks.isBundledName(meta.mSysName) {
            throw ZipError(message: "that pack is already in the app")
        }
        let pack = try Manifest.validateUserPack(zip: zip, packName: meta.mSysName)
        try commit(zip, sysName: meta.mSysName)
        return pack
    }

    /// Write `~{sys}.atp`, parse it back, then replace `{sys}.atp`. The previous file stays until the replacement parses.
    private static func commit(_ zip: Data, sysName: String) throws {
        let fm = FileManager.default
        let dir = InstalledPacks.directory()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ZipError(message: "could not save the pack: \(error)")
        }
        let temp = dir.appendingPathComponent("~\(sysName).\(InstalledPacks.ext)")
        let dest = InstalledPacks.file(sysName: sysName)
        let backup = dir.appendingPathComponent("\(sysName).\(InstalledPacks.ext).bak")
        do {
            try zip.write(to: temp, options: .atomic)
            let written = try Data(contentsOf: temp)
            _ = try Manifest.validateUserPack(zip: written, packName: sysName)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        if fm.fileExists(atPath: backup.path) {
            try? fm.removeItem(at: backup)
        }
        let hadPrevious = fm.fileExists(atPath: dest.path)
        if hadPrevious {
            do {
                try fm.moveItem(at: dest, to: backup)
            } catch {
                try? fm.removeItem(at: temp)
                throw ZipError(message: "could not save the pack: \(error)")
            }
        }
        do {
            try fm.moveItem(at: temp, to: dest)
            let final = try InstalledPacks.read(dest, packName: sysName)
            _ = try Manifest.validateUserPack(zip: final, packName: sysName)
            if hadPrevious {
                try? fm.removeItem(at: backup)
            }
        } catch {
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            if hadPrevious, fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: dest)
            }
            if fm.fileExists(atPath: temp.path) {
                try? fm.removeItem(at: temp)
            }
            throw error
        }
    }

    private static func installMessage(_ label: String, _ error: Error) -> String {
        let text = ItemLoadError.text(error)
        if text.contains("password-protected") {
            return "Could not install \(label): this pack is password-protected."
        }
        return "Could not install \(label): \(text)"
    }
}
