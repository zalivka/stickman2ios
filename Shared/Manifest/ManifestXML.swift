import CoreGraphics
import Foundation

nonisolated enum ManifestXML {
    static func parse(_ data: Data, packName: String, translations: [String: String], archive: Data) throws -> (
        defScale: CGFloat,
        editableItems: Bool,
        useCommonBg: Bool,
        items: [Item]
    ) {
        let parser = XMLParser(data: data)
        let sink = Sink(packName: packName, translations: translations, archive: archive)
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            throw ZipError(message: "ManifestXML '\(packName)' parse failed: \(detail)")
        }
        if let error = sink.error {
            throw ZipError(message: "ManifestXML '\(packName)' \(error)")
        }
        return (sink.defScale, sink.editableItems, sink.useCommonBg, sink.items)
    }

    nonisolated private final class Sink: NSObject, XMLParserDelegate {
        let packName: String
        let translations: [String: String]
        let atiFiles: Set<String>
        var defScale: CGFloat = 1
        var editableItems = false
        var useCommonBg = true
        var items: [Item] = []
        private(set) var error: String?

        init(packName: String, translations: [String: String], archive: Data) {
            self.packName = packName
            self.translations = translations
            atiFiles = (try? ZipStore.namesThrowing(in: archive))
                .flatMap { names in Set(names.compactMap { name -> String? in
                    let file = (name as NSString).lastPathComponent
                    return file.hasSuffix(".ati") ? file : nil
                }) }
                ?? []
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "manifest":
                if let text = attributes["def_scale"], !text.isEmpty {
                    guard let value = Double(text) else {
                        error = "def_scale '\(text)'"
                        return
                    }
                    defScale = CGFloat(value)
                }
                editableItems = attributes["editable_items"] == "true"
                if attributes["use_common_bg"] == "false" {
                    useCommonBg = false
                }
            case "item":
                guard let sname = attributes["sname"], !sname.isEmpty else {
                    error = "item missing sname"
                    return
                }
                if !atiFiles.contains("\(sname).ati") {
                    error = "missing items/\(sname).ati"
                    return
                }
                let setName = attributes["set"] ?? ""
                let computed = packName + ":" + sname
                if let attr = attributes["fullname"], !attr.isEmpty, attr != computed {
                    error = "item '\(sname)' fullname '\(attr)' != '\(computed)'"
                    return
                }
                var scale = defScale
                if let text = attributes["scale"], !text.isEmpty {
                    guard let value = Double(text) else {
                        error = "item '\(sname)' scale '\(text)'"
                        return
                    }
                    scale = CGFloat(value)
                }
                let multiframed = attributes["multiframed"] == "true"
                let human = translations[sname] ?? sname
                items.append(
                    Item(
                        systemName: sname,
                        humanName: human,
                        packName: packName,
                        fullName: computed,
                        setName: translations[setName] ?? setName,
                        scale: scale,
                        faceable: attributes["faceable"] == "true",
                        multiframed: multiframed,
                        hidden: attributes["hidden"] == "true",
                        readOnly: false
                    )
                )
            default:
                break
            }
        }

    }
}
