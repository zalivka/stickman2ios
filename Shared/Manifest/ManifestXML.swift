import CoreGraphics
import Foundation

enum ManifestXML {
    static func parse(_ data: Data, packName: String, translations: [String: String], archive: Data) -> (
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
            fatalError("ManifestXML '\(packName)' parse failed: \(detail)")
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

        init(packName: String, translations: [String: String], archive: Data) {
            self.packName = packName
            self.translations = translations
            atiFiles = Set(
                ZipStore.names(in: archive).compactMap { name -> String? in
                    let file = (name as NSString).lastPathComponent
                    return file.hasSuffix(".ati") ? file : nil
                }
            )
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
                        fatalError("ManifestXML '\(packName)' def_scale '\(text)'")
                    }
                    defScale = CGFloat(value)
                }
                editableItems = attributes["editable_items"] == "true"
                if attributes["use_common_bg"] == "false" {
                    useCommonBg = false
                }
            case "item":
                guard let sname = attributes["sname"], !sname.isEmpty else {
                    fatalError("ManifestXML '\(packName)' item missing sname")
                }
                if !atiFiles.contains("\(sname).ati") {
                    fatalError("ManifestXML '\(packName)' missing items/\(sname).ati")
                }
                let setName = attributes["set"] ?? ""
                let computed = packName + ":" + sname
                if let attr = attributes["fullname"], !attr.isEmpty, attr != computed {
                    fatalError("ManifestXML '\(packName)' item '\(sname)' fullname '\(attr)' != '\(computed)'")
                }
                var scale = defScale
                if let text = attributes["scale"], !text.isEmpty {
                    guard let value = Double(text) else {
                        fatalError("ManifestXML '\(packName)' item '\(sname)' scale '\(text)'")
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
