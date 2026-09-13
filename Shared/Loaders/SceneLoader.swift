import CoreGraphics
import Foundation

enum HexRGB {
    static func parse(_ text: String) -> (CGFloat, CGFloat, CGFloat) {
        if text.count != 7 || !text.hasPrefix("#") {
            fatalError("SceneLoader bg_name '\(text)' is not #rrggbb")
        }
        let hex = text.dropFirst()
        guard let value = UInt32(hex, radix: 16) else {
            fatalError("SceneLoader bg_name '\(text)' is not #rrggbb")
        }
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

enum SceneLoader {
    static func load(resource: String, subdirectory: String) -> (StickmanScene, UnitAssets) {
        let zip = ItemLoader.archive(resource: resource, subdirectory: subdirectory, ext: "ats")
        let names = ZipStore.names(in: zip)
        if !names.contains("model.xml") {
            fatalError("SceneLoader '\(resource).ats' missing model.xml")
        }
        let scene = SceneXML.parse(ZipStore.data(named: "model.xml", in: zip))
        let items = names.filter { !$0.contains("/") && $0.hasSuffix(".ati") }
        if items.isEmpty {
            fatalError("SceneLoader '\(resource).ats' has no root .ati")
        }
        let assets = UnitAssets()
        for item in items {
            assets.loadItemFromArchive(ZipStore.data(named: item, in: zip))
        }
        for frame in scene.frames {
            for unit in frame.units {
                let name = UnitAssets.removeNumber(unit.name)
                if !assets.hasAssetsFor(unitName: name) {
                    fatalError("SceneLoader assets missing unit '\(name)'")
                }
                let file = ownName(name) + ".ati"
                if !items.contains(file) {
                    fatalError("SceneLoader '\(resource).ats' missing '\(file)' for '\(unit.name)'")
                }
            }
        }
        return (scene, assets)
    }

    static func ownName(_ unitName: String) -> String {
        guard let colon = unitName.firstIndex(of: ":") else { return unitName }
        let rest = String(unitName[unitName.index(after: colon)...])
        if rest.isEmpty {
            fatalError("SceneLoader unit name '\(unitName)' has empty own name")
        }
        return rest
    }
}

private enum SceneXML {
    static func parse(_ data: Data) -> StickmanScene {
        let parser = XMLParser(data: data)
        let sink = Sink()
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            fatalError("SceneLoader model.xml parse failed: \(detail)")
        }
        guard let width = sink.width, let height = sink.height else {
            fatalError("SceneLoader model.xml missing scene w/h")
        }
        if width <= 0 || height <= 0 {
            fatalError("SceneLoader scene size \(width)x\(height)")
        }
        if sink.frames.isEmpty {
            fatalError("SceneLoader model.xml has no frames")
        }
        return StickmanScene(
            width: width,
            height: height,
            frames: sink.frames,
            currentIndex: 0,
            interframes: sink.interframes
        )
    }

    private final class Sink: NSObject, XMLParserDelegate {
        var width: CGFloat?
        var height: CGFloat?
        var interframes: Int = 36
        var frames: [StickmanFrame] = []

        private var frameId: Int?
        private var frameBgName: String?
        private var frameUnits: [StickmanUnit] = []
        private var unitName: String?
        private var unitScale: CGFloat?
        private var unitAlpha: CGFloat?
        private var unitPoints: [StickmanPoint] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "scene":
                guard let wText = attributes["w"], let w = Double(wText) else {
                    fatalError("SceneLoader scene missing w")
                }
                guard let hText = attributes["h"], let h = Double(hText) else {
                    fatalError("SceneLoader scene missing h")
                }
                width = CGFloat(w)
                height = CGFloat(h)
                if let text = attributes["interframes"] {
                    guard let value = Int(text) else {
                        fatalError("SceneLoader interframes '\(text)' is not an int")
                    }
                    if value < 0 {
                        fatalError("SceneLoader interframes is \(value)")
                    }
                    interframes = value
                }
            case "frame":
                guard let idText = attributes["id"], let id = Int(idText) else {
                    fatalError("SceneLoader frame missing id")
                }
                guard let bgName = attributes["bg_name"], !bgName.isEmpty else {
                    fatalError("SceneLoader frame \(id) missing bg_name")
                }
                _ = HexRGB.parse(bgName)
                frameId = id
                frameBgName = bgName
                frameUnits = []
            case "unit":
                guard let name = attributes["name"], !name.isEmpty else {
                    fatalError("SceneLoader unit missing name")
                }
                guard let scaleText = attributes["scale"], let scale = Double(scaleText) else {
                    fatalError("SceneLoader unit '\(name)' missing scale")
                }
                if scale <= 0 {
                    fatalError("SceneLoader unit '\(name)' scale is \(scale)")
                }
                guard let alphaText = attributes["alpha"], let alpha = Double(alphaText) else {
                    fatalError("SceneLoader unit '\(name)' missing alpha")
                }
                if alpha < 0 || alpha > 1 {
                    fatalError("SceneLoader unit '\(name)' alpha is \(alpha)")
                }
                unitName = name
                unitScale = CGFloat(scale)
                unitAlpha = CGFloat(alpha)
                unitPoints = []
            case "point":
                unitPoints.append(parsePoint(attributes))
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "unit" {
                guard let name = unitName, let scale = unitScale, let alpha = unitAlpha else {
                    fatalError("SceneLoader unit ended without name/scale/alpha")
                }
                if unitPoints.isEmpty {
                    fatalError("SceneLoader unit '\(name)' has no points")
                }
                var unit = StickmanUnit(
                    name: name,
                    points: unitPoints,
                    edges: [],
                    scale: scale,
                    alpha: alpha
                )
                unit.link()
                frameUnits.append(unit)
                unitName = nil
                unitScale = nil
                unitAlpha = nil
                unitPoints = []
            } else if elementName == "frame" {
                guard let id = frameId, let bgName = frameBgName else {
                    fatalError("SceneLoader frame ended without id/bg_name")
                }
                if frameUnits.isEmpty {
                    fatalError("SceneLoader frame \(id) has no units")
                }
                frames.append(StickmanFrame(id: id, units: frameUnits, bgName: bgName))
                frameId = nil
                frameBgName = nil
                frameUnits = []
            }
        }

        private func parsePoint(_ attributes: [String: String]) -> StickmanPoint {
            guard let idText = attributes["id"], let id = Int(idText) else {
                fatalError("SceneLoader point missing id")
            }
            guard let xText = attributes["x"], let x = Double(xText) else {
                fatalError("SceneLoader point \(id) missing x")
            }
            guard let yText = attributes["y"], let y = Double(yText) else {
                fatalError("SceneLoader point \(id) missing y")
            }
            let isBase = attributes["base"] == "true"
            let parentId: Int?
            if isBase {
                parentId = nil
            } else {
                guard let parText = attributes["par"], let par = Int(parText) else {
                    fatalError("SceneLoader point \(id) missing par")
                }
                parentId = par
            }
            return StickmanPoint(id: id, x: CGFloat(x), y: CGFloat(y), isBase: isBase, parentId: parentId)
        }
    }
}
