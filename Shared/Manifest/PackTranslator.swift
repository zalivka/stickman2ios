import Foundation

enum PackTranslator {
    static func load(from zip: Data, packName: String) -> [String: String] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let preferred = "translate_\(lang).xml"
        let english = "translate_en.xml"
        let name: String
        if ZipStore.contains(preferred, in: zip) {
            name = preferred
        } else if ZipStore.contains(english, in: zip) {
            name = english
        } else {
            fatalError("PackTranslator '\(packName)' missing translate_en.xml")
        }
        return parse(ZipStore.data(named: name, in: zip), source: "\(packName)/\(name)")
    }

    /// Android XmlPullParser accepts any xml version. NSXMLParser only accepts 1.0 / 1.1.
    /// moonlighte.test ships `translate_en.xml` / `translate_ru.xml` as `version='3.0'`.
    private static func xml10(_ data: Data, source: String) -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            fatalError("PackTranslator '\(source)' is not UTF-8")
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

    private static func parse(_ data: Data, source: String) -> [String: String] {
        let parser = XMLParser(data: xml10(data, source: source))
        let sink = Sink()
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            fatalError("PackTranslator '\(source)' parse failed: \(detail)")
        }
        return sink.values
    }

    nonisolated private final class Sink: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
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
                    fatalError("PackTranslator string missing name")
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
                    fatalError("PackTranslator string ended without name")
                }
                values[key] = text
                self.key = nil
                text = ""
            }
        }
    }
}
