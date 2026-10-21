import Foundation

extension Notification.Name {
    static let installedPacksDidChange = Notification.Name("installedPacksDidChange")
}

/// User-installed `.atp` files. Bundled `packs/*.atp` stay in the app bundle.
nonisolated enum InstalledPacks {
    static let ext = "atp"
    /// On-disk size of a user `.atp`. A real pack can be 140 MB.
    static let maxFileBytes = 1024 * 1024 * 1024

    private static let bundledNames: Set<String> = {
        Set(ExternalPack.bundleArchives().map { $0.deletingPathExtension().lastPathComponent })
    }()

    static func directory() -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // platform precondition: Application Support always resolves on a real device
            fatalError("InstalledPacks has no Application Support")
        }
        return root
            .appendingPathComponent("at_elements", isDirectory: true)
            .appendingPathComponent("packs", isDirectory: true)
    }

    static func isBundledName(_ sysName: String) -> Bool {
        bundledNames.contains(sysName)
    }

    /// `camp.fire`, `vk.gr1`, `prehistoric.animals`. One or more dots, lowercase, digits after the first letter of each piece.
    static func isPackSysName(_ name: String) -> Bool {
        if name.count < 3 || name.count > 64 {
            return false
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count < 2 {
            return false
        }
        for part in parts {
            let scalars = Array(part.unicodeScalars)
            if scalars.isEmpty || !isPackLetter(scalars[0]) {
                return false
            }
            for scalar in scalars.dropFirst() where !isPackLetter(scalar) && !isPackDigit(scalar) {
                return false
            }
        }
        return true
    }

    private static func isPackLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    private static func isPackDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    /// False for bundled names, even if a same-named file was left in the directory.
    static func contains(_ sysName: String) -> Bool {
        if isBundledName(sysName) || sysName == Pack.customName {
            return false
        }
        return FileManager.default.fileExists(atPath: file(sysName: sysName).path)
    }

    static func file(sysName: String) -> URL {
        directory().appendingPathComponent("\(sysName).\(ext)")
    }

    /// Installed archives, skipping `~` temps and names that belong to the app bundle.
    static func archives() -> [URL] {
        let dir = directory()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("InstalledPacks could not create \(dir.path): \(error)")
            return []
        }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            print("InstalledPacks could not list \(dir.path): \(error)")
            return []
        }
        return urls.compactMap { url in
            if url.pathExtension.lowercased() != ext {
                return nil
            }
            let stem = url.deletingPathExtension().lastPathComponent
            if stem.hasPrefix("~") {
                return nil
            }
            if isBundledName(stem) {
                print("InstalledPacks skipping \(stem), bundled name")
                return nil
            }
            return url
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func read(_ url: URL, packName: String) throws -> Data {
        let size: Int
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values.isDirectory == true {
                throw ZipError(message: "Pack '\(packName)' is a directory")
            }
            size = values.fileSize ?? 0
        } catch let error as ZipError {
            throw error
        } catch {
            throw ZipError(message: "Pack '\(packName)' could not be read: \(error)")
        }
        if size <= 0 || size > maxFileBytes {
            throw ZipError(message: "Pack '\(packName)' is \(size) bytes")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ZipError(message: "Pack '\(packName)' could not be read: \(error)")
        }
    }

    /// Removes `{sys}.atp`, a leftover `~{sys}.atp`, and `{sys}.atp.bak`. Does not touch the app bundle.
    static func delete(_ sysName: String) throws {
        if !isPackSysName(sysName) || isBundledName(sysName) {
            throw ZipError(message: "Could not delete \(sysName)")
        }
        let fm = FileManager.default
        let dir = directory()
        let names = ["\(sysName).\(ext)", "~\(sysName).\(ext)", "\(sysName).\(ext).bak"]
        var removed = false
        for name in names {
            let url = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) {
                continue
            }
            do {
                try fm.removeItem(at: url)
                removed = true
            } catch {
                throw ZipError(message: "Could not delete \(sysName): \(error)")
            }
        }
        if !removed {
            throw ZipError(message: "Could not delete \(sysName): pack file is missing")
        }
    }
}
