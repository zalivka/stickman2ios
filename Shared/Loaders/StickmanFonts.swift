import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Android `Fonts`: bundled keys plus custom files from `fonts/` in a scene zip.
enum StickmanFonts {
    private static let embedded: [(key: String, file: String)] = [
        ("roboto/bold", "Roboto-Bold"),
        ("roboto/regular", "Roboto-Regular"),
        ("graffiti", "SpriteGraffiti"),
        ("rafale", "rafale"),
    ]

    private static var postScript: [String: String] = [:]
    private static var customBytes: [String: (file: String, data: Data)] = [:]
    private static var booted = false

    static func boot() {
        if booted {
            return
        }
        booted = true
        for (key, file) in embedded {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "fonts")
                ?? Bundle.main.url(forResource: file, withExtension: "ttf")
            else {
                fatalError("StickmanFonts missing fonts/\(file).ttf")
            }
            register(url: url, key: key)
        }
    }

    static func contains(_ key: String) -> Bool {
        boot()
        if key == "default" {
            return true
        }
        return postScript[key] != nil
    }

    static func isCustom(_ key: String) -> Bool {
        customBytes[key] != nil
    }

    static func font(key: String, size: CGFloat) -> Font {
        boot()
        if key == "default" {
            return .system(size: size)
        }
        guard let name = postScript[key] else {
            fatalError("StickmanFonts unknown font '\(key)'")
        }
        return .custom(name, size: size)
    }

    static func installSceneFonts(zip: Data, names: [String], resource: String) {
        boot()
        for name in names {
            if !name.hasPrefix("fonts/") || name.hasSuffix("/") {
                continue
            }
            let file = (name as NSString).lastPathComponent
            if file.isEmpty {
                fatalError("SceneLoader '\(resource).ats' empty fonts/ entry")
            }
            let lower = file.lowercased()
            if !lower.hasSuffix(".ttf"), !lower.hasSuffix(".otf") {
                fatalError("SceneLoader '\(resource).ats' font '\(file)' is not ttf/otf")
            }
            let key = fontKey(file)
            if embedded.contains(where: { $0.key == key }) {
                continue
            }
            let data = ZipStore.data(named: name, in: zip)
            register(data: data, file: file, key: key)
        }
    }

    static func customFontsUsed(in scene: StickmanScene) -> [(file: String, data: Data)] {
        var seen = Set<String>()
        var result: [(file: String, data: Data)] = []
        for frame in scene.frames {
            for unit in frame.units {
                guard let key = unit.bubble?.font, isCustom(key), !seen.contains(key) else {
                    continue
                }
                seen.insert(key)
                guard let stored = customBytes[key] else {
                    fatalError("StickmanFonts missing bytes for '\(key)'")
                }
                result.append(stored)
            }
        }
        return result
    }

    private static func fontKey(_ file: String) -> String {
        let name = (file as NSString).lastPathComponent
        if let dot = name.lastIndex(of: ".") {
            return String(name[..<dot])
        }
        return name
    }

    private static func register(url: URL, key: String) {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            guard alreadyRegistered(error) else {
                let detail = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                fatalError("StickmanFonts could not register '\(key)': \(detail)")
            }
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first
        else {
            fatalError("StickmanFonts '\(key)' has no descriptors")
        }
        remember(CTFontCreateWithFontDescriptor(descriptor, 0, nil), key: key)
    }

    private static func register(data: Data, file: String, key: String) {
        if data.isEmpty {
            fatalError("StickmanFonts '\(key)' is empty")
        }
        guard let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider) else {
            fatalError("StickmanFonts '\(key)' is not a font")
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            guard alreadyRegistered(error) else {
                let detail = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                fatalError("StickmanFonts could not register '\(key)': \(detail)")
            }
        }
        remember(CTFontCreateWithGraphicsFont(cgFont, 0, nil, nil), key: key)
        customBytes[key] = (file: file, data: data)
    }

    private static func remember(_ font: CTFont, key: String) {
        guard let name = CTFontCopyPostScriptName(font) as String?, !name.isEmpty else {
            fatalError("StickmanFonts '\(key)' has no PostScript name")
        }
        postScript[key] = name
    }

    private static func alreadyRegistered(_ error: Unmanaged<CFError>?) -> Bool {
        guard let error else {
            return false
        }
        let ns = error.takeRetainedValue() as Error as NSError
        return ns.domain == kCTFontManagerErrorDomain as String
            && (ns.code == CTFontManagerError.alreadyRegistered.rawValue
                || ns.code == CTFontManagerError.duplicatedName.rawValue)
    }
}
