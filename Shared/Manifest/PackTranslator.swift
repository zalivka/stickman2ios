import Foundation

nonisolated enum PackTranslator {
    static func load(from zip: Data, packName: String) throws -> [String: String] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let preferred = "translate_\(lang).xml"
        let english = "translate_en.xml"
        let names = try ZipStore.namesThrowing(in: zip)
        let name: String
        if names.contains(preferred) {
            name = preferred
        } else if names.contains(english) {
            name = english
        } else {
            throw ZipError(message: "PackTranslator '\(packName)' missing translate_en.xml")
        }
        return try parse(ZipStore.dataThrowing(named: name, in: zip), source: "\(packName)/\(name)")
    }

    /// Android XmlPullParser accepts any xml version. NSXMLParser only accepts 1.0 / 1.1.
    /// moonlighte.test ships `translate_en.xml` / `translate_ru.xml` as `version='3.0'`.
    private static func xml10(_ data: Data, source: String) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ZipError(message: "PackTranslator '\(source)' is not UTF-8")
        }
        guard let end = text.range(of: "?>") else {
            return data
        }
        let decl = text[text.startIndex..<end.upperBound]
        if decl.range(of: #"version\s*=\s*['"]1\.[01]['"]"#, options: .regularExpression) != nil {
            return data
        }
        guard decl.range(of: #"version\s*=\s*['"][^'"]+['"]"#, options: .regularExpression) != nil else {
            return data
        }
        let fixed = decl.replacingOccurrences(
            of: #"version\s*=\s*['"][^'"]+['"]"#,
            with: "version='1.0'",
            options: .regularExpression
        )
        text.replaceSubrange(text.startIndex..<end.upperBound, with: fixed)
        return Data(text.utf8)
    }

    private static func parse(_ data: Data, source: String) throws -> [String: String] {
        let parser = XMLParser(data: try xml10(data, source: source))
        let sink = Sink()
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            throw ZipError(message: "PackTranslator '\(source)' parse failed: \(detail)")
        }
        if let error = sink.error {
            throw ZipError(message: "PackTranslator '\(source)' \(error)")
        }
        return sink.values
    }

    nonisolated private final class Sink: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private(set) var error: String?
        private var key: String?
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            if elementName == "string" {
                guard let name = attributes["name"], !name.isEmpty else {
                    error = "string missing name"
                    return
                }
                key = name
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if key != nil {
                text += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "string" {
                guard let key else {
                    error = "string ended without name"
                    return
                }
                values[key] = text
                self.key = nil
                text = ""
            }
        }
    }
}
