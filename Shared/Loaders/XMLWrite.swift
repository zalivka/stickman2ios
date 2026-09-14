import CoreGraphics
import Foundation

enum XMLWrite {
    static let header = "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>\n"

    static func attr(_ name: String, _ value: String) -> String {
        " \(name)=\"\(escape(value))\""
    }

    static func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func float(_ value: CGFloat) -> String {
        String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }

    static func versionCode() -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !value.isEmpty else {
            fatalError("XMLWrite missing CFBundleVersion")
        }
        return value
    }

    static func data(_ xml: String) -> Data {
        guard let data = xml.data(using: .utf8) else {
            fatalError("XMLWrite could not encode \(xml.count) characters as UTF-8")
        }
        return data
    }
}
