import Foundation

enum ExternalPack {
    static func root() -> URL {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            fatalError("ExternalPack Application Support: \(error)")
        }
        return base.appendingPathComponent("packs", isDirectory: true)
    }

    static func packDir(_ packName: String) -> URL {
        root().appendingPathComponent(packName, isDirectory: true)
    }

    static func itemFile(packName: String, systemName: String) -> URL {
        packDir(packName)
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent(systemName + ".ati")
    }

    static func logoFile(_ packName: String) -> URL {
        let url = packDir(packName).appendingPathComponent("logo.png")
        if !FileManager.default.fileExists(atPath: url.path) {
            fatalError("ExternalPack pack '\(packName)' missing logo.png")
        }
        return url
    }

    static func translationFile(packName: String, lang: String) -> URL {
        packDir(packName).appendingPathComponent("translate_\(lang).xml")
    }

    static func installedPackNames() -> [String] {
        let dir = root()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            return []
        }
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: dir.path)
        } catch {
            fatalError("ExternalPack list \(dir.path): \(error)")
        }
        return names.filter { name in
            var isDir: ObjCBool = false
            let path = dir.appendingPathComponent(name).path
            return name.contains(".") && fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    static func bundleArchives() -> [URL] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "atp", subdirectory: "packs"), !urls.isEmpty else {
            fatalError("Manifest missing packs/*.atp")
        }
        if !urls.contains(where: { $0.deletingPathExtension().lastPathComponent == "template.basic" }) {
            fatalError("Manifest missing packs/template.basic.atp")
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func unpackEmbeddedIfNeeded() {
        for url in bundleArchives() {
            let zip: Data
            do {
                zip = try Data(contentsOf: url)
            } catch {
                fatalError("ExternalPack could not read \(url.path): \(error)")
            }
            let meta = PackMeta.parse(ZipStore.data(named: "meta.txt", in: zip), source: url.lastPathComponent)
            let dest = packDir(meta.mSysName)
            let extractedMeta = dest.appendingPathComponent("meta.txt")
            var oldVersion = 0
            if FileManager.default.fileExists(atPath: extractedMeta.path) {
                do {
                    oldVersion = PackMeta.parse(try Data(contentsOf: extractedMeta), source: extractedMeta.path).version
                } catch {
                    fatalError("ExternalPack could not read \(extractedMeta.path): \(error)")
                }
            }
            if oldVersion >= meta.version, ZipStore.allFilesPresent(zip, in: dest) {
                print("manifest: skip \(meta.mSysName) v\(oldVersion) (bundle v\(meta.version))")
                continue
            }
            print("manifest: unpack \(meta.mSysName) v\(oldVersion) -> v\(meta.version)")
            if FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.removeItem(at: dest)
                } catch {
                    fatalError("ExternalPack could not replace \(dest.path): \(error)")
                }
            }
            ZipStore.unpack(zip, to: dest)
        }
    }
}
