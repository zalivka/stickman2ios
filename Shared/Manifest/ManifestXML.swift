import CoreGraphics
import Foundation

enum ManifestXML {
    static func parse(_ data: Data, packName: String, translations: [String: String]) -> (
        defScale: CGFloat,
        editableItems: Bool,
        useCommonBg: Bool,
        items: [Item]
    ) {
        let parser = XMLParser(data: data)
        let sink = Sink(packName: packName, translations: translations)
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
        var defScale: CGFloat = 1
        var editableItems = false
        var useCommonBg = true
        var items: [Item] = []

        init(packName: String, translations: [String: String]) {
            self.packName = packName
            self.translations = translations
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
                let ati = ExternalPack.itemFile(packName: packName, systemName: sname)
                if !FileManager.default.fileExists(atPath: ati.path) {
                    fatalError("ManifestXML '\(packName)' missing items/\(sname).ati")
                }
                let setName = attributes["set"] ?? ""
                let fullNameAttr = attributes["fullname"]
                let fullName = (fullNameAttr?.isEmpty == false) ? fullNameAttr : nil
                var scale = defScale
                if let text = attributes["scale"], !text.isEmpty {
                    guard let value = Double(text) else {
                        fatalError("ManifestXML '\(packName)' item '\(sname)' scale '\(text)'")
                    }
                    scale = CGFloat(value)
                }
                var multiframed = attributes["multiframed"] == "true"
                applyAtiMeta(ati, sname: sname, scale: &scale, multiframed: &multiframed)
                let human = translations[sname] ?? sname
                items.append(
                    Item(
                        systemName: sname,
                        humanName: human,
                        packName: packName,
                        fullName: fullName,
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

        private func applyAtiMeta(_ url: URL, sname: String, scale: inout CGFloat, multiframed: inout Bool) {
            let zip: Data
            do {
                zip = try Data(contentsOf: url)
            } catch {
                fatalError("ManifestXML could not read \(url.path): \(error)")
            }
            if !ZipStore.contains("meta.txt", in: zip) {
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: ZipStore.data(named: "meta.txt", in: zip)) as? [String: Any] else {
                fatalError("ManifestXML '\(packName)' \(sname).ati meta.txt is not JSON")
            }
            if let number = object["scale"] as? NSNumber {
                let value = CGFloat(truncating: number)
                if value > 0.01 {
                    scale = value
                }
            }
            if object["multiframed"] as? Bool == true {
                multiframed = true
            }
        }
    }
}
