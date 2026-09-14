import CoreGraphics
import Foundation

enum HexRGB {
    static func parse(_ text: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if !text.hasPrefix("#") {
            fatalError("SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
        }
        let hex = text.dropFirst()
        guard let value = UInt32(hex, radix: 16) else {
            fatalError("SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
        }
        switch hex.count {
        case 6:
            return (
                r: CGFloat((value >> 16) & 0xFF) / 255,
                g: CGFloat((value >> 8) & 0xFF) / 255,
                b: CGFloat(value & 0xFF) / 255,
                a: 1
            )
        case 8:
            return (
                r: CGFloat((value >> 16) & 0xFF) / 255,
                g: CGFloat((value >> 8) & 0xFF) / 255,
                b: CGFloat(value & 0xFF) / 255,
                a: CGFloat((value >> 24) & 0xFF) / 255
            )
        default:
            fatalError("SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
        }
    }
}

enum SceneLoader {
    static func load(resource: String, subdirectory: String) -> (StickmanScene, UnitAssets, BackgroundAssets) {
        load(zip: ItemLoader.archive(resource: resource, subdirectory: subdirectory, ext: "ats"), resource: resource)
    }

    static func load(url: URL) -> (StickmanScene, UnitAssets, BackgroundAssets) {
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            fatalError("SceneLoader could not read \(url.path): \(error)")
        }
        return load(zip: zip, resource: url.deletingPathExtension().lastPathComponent)
    }

    static func load(zip: Data, resource: String) -> (StickmanScene, UnitAssets, BackgroundAssets) {
        let names = ZipStore.names(in: zip)
        if !names.contains("model.xml") {
            fatalError("SceneLoader '\(resource).ats' missing model.xml")
        }
        var scene = SceneXML.parse(ZipStore.data(named: "model.xml", in: zip))
        scene.unitAnimations = loadAnimations(zip: zip, names: names, resource: resource)
        // GOTCHA (doc/gotchas.md): pack items live at pack/items/name.ati, not zip root.
        let items = names.filter { $0.hasSuffix(".ati") && !$0.hasSuffix("/") }
        if items.isEmpty {
            fatalError("SceneLoader '\(resource).ats' has no .ati")
        }
        let assets = UnitAssets()
        for item in items {
            assets.loadItemFromArchive(ZipStore.data(named: item, in: zip), entryName: item)
        }
        for frame in scene.frames {
            for unit in frame.units {
                let name = UnitAssets.removeNumber(unit.name)
                if !assets.hasAssetsFor(unitName: name) {
                    fatalError("SceneLoader assets missing unit '\(name)'")
                }
                let file = ownName(name) + ".ati"
                if !items.contains(where: { itemFileName($0) == file }) {
                    fatalError("SceneLoader '\(resource).ats' missing '\(file)' for '\(unit.name)'")
                }
            }
        }
        let backgrounds = loadBackgrounds(scene: scene, zip: zip, names: names, resource: resource)
        return (scene, assets, backgrounds)
    }

    private static func loadAnimations(zip: Data, names: [String], resource: String) -> [String: FBFAnimation] {
        if !names.contains("animations_v2.txt") {
            return [:]
        }
        let data = ZipStore.data(named: "animations_v2.txt", in: zip)
        let parsed: [FBFAnimation]
        do {
            parsed = try JSONDecoder().decode([FBFAnimation].self, from: data)
        } catch {
            fatalError("SceneLoader '\(resource).ats' animations_v2.txt is not FBF JSON: \(error)")
        }
        var result: [String: FBFAnimation] = [:]
        for animation in parsed {
            if animation.unitname.isEmpty {
                fatalError("SceneLoader '\(resource).ats' FBF animation missing unitname")
            }
            if animation.period < 1 {
                fatalError("SceneLoader '\(resource).ats' FBF '\(animation.unitname)' period is \(animation.period)")
            }
            if result[animation.unitname] != nil {
                fatalError("SceneLoader '\(resource).ats' duplicate FBF '\(animation.unitname)'")
            }
            result[animation.unitname] = animation
        }
        return result
    }

    private static func loadBackgrounds(
        scene: StickmanScene,
        zip: Data,
        names: [String],
        resource: String
    ) -> BackgroundAssets {
        let backgrounds = BackgroundAssets()
        var seen: Set<String> = []
        for frame in scene.frames {
            guard let bgName = frame.bgName else { continue }
            if bgName.hasPrefix("#") { continue }
            if !bgName.hasPrefix("usermade:") {
                fatalError("SceneLoader '\(resource).ats' unknown bg_name '\(bgName)'")
            }
            if seen.contains(bgName) { continue }
            seen.insert(bgName)
            let own = ownName(bgName)
            let entry = "_bgs/\(own).zip"
            if !names.contains(entry) {
                fatalError("SceneLoader '\(resource).ats' missing '\(entry)'")
            }
            let nested = ZipStore.data(named: entry, in: zip)
            let innerNames = ZipStore.names(in: nested)
            let imageName: String
            if innerNames.contains("bg.png") {
                imageName = "bg.png"
            } else if innerNames.contains("bg.jpg") {
                imageName = "bg.jpg"
            } else {
                fatalError("SceneLoader '\(entry)' has no bg.png or bg.jpg")
            }
            backgrounds.install(
                name: bgName,
                image: BackgroundAssets.decode(ZipStore.data(named: imageName, in: nested), name: imageName),
                archive: nested
            )
        }
        return backgrounds
    }

    private static func itemFileName(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else {
            return path
        }
        return String(path[path.index(after: slash)...])
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

enum SceneXML {
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
        guard let interframes = sink.interframes else {
            fatalError("SceneLoader scene missing interframes")
        }
        return StickmanScene(
            width: width,
            height: height,
            frames: sink.frames,
            currentIndex: 0,
            interframes: interframes,
            noInterpolation: sink.noInterpolation,
            noInterpolationFrames: sink.noInterpolationFrames
        )
    }

    static func serialize(_ scene: StickmanScene) -> Data {
        if scene.frames.isEmpty {
            fatalError("SceneXML serialize has no frames")
        }
        if scene.width <= 0 || scene.height <= 0 {
            fatalError("SceneXML serialize size \(scene.width)x\(scene.height)")
        }
        if scene.interframes < 1 {
            fatalError("SceneXML serialize interframes is \(scene.interframes)")
        }
        var xml = XMLWrite.header
        xml += "<scene"
        xml += XMLWrite.attr("version_code", XMLWrite.versionCode())
        xml += XMLWrite.attr("w", XMLWrite.float(scene.width))
        xml += XMLWrite.attr("h", XMLWrite.float(scene.height))
        xml += XMLWrite.attr("interframes", "\(scene.interframes)")
        xml += XMLWrite.attr("no_interpolation", scene.noInterpolation ? "true" : "false")
        xml += XMLWrite.attr("no_interpolation_frames", "\(scene.noInterpolationFrames)")
        xml += ">\n"
        var written = 0
        for frame in scene.frames {
            if frame.id == -1 {
                continue
            }
            xml += serialize(frame)
            written += 1
        }
        if written == 0 {
            fatalError("SceneXML serialize has no frames")
        }
        xml += "</scene>\n"
        return XMLWrite.data(xml)
    }

    private static func serialize(_ frame: StickmanFrame) -> String {
        if frame.units.isEmpty {
            fatalError("SceneXML frame \(frame.id) has no units")
        }
        let bgName = frame.bgName ?? "#ffffff"
        var xml = "<frame"
        xml += XMLWrite.attr("id", "\(frame.id)")
        xml += XMLWrite.attr("bg", frame.bgMove.serialize())
        xml += XMLWrite.attr("camera", frame.cameraMove.serialize())
        xml += XMLWrite.attr("bg_name", bgName)
        xml += ">\n"
        for unit in frame.units {
            xml += serialize(unit)
        }
        xml += "</frame>\n"
        return xml
    }

    private static func serialize(_ unit: StickmanUnit) -> String {
        if unit.name.isEmpty {
            fatalError("SceneXML unit has empty name")
        }
        if unit.points.isEmpty {
            fatalError("SceneXML unit '\(unit.name)' has no points")
        }
        if unit.scale <= 0 {
            fatalError("SceneXML unit '\(unit.name)' scale is \(unit.scale)")
        }
        if unit.alpha < 0 {
            fatalError("SceneXML unit '\(unit.name)' alpha is \(unit.alpha)")
        }
        var xml = "<unit"
        xml += XMLWrite.attr("name", unit.name)
        switch unit.unitType {
        case .unit:
            xml += XMLWrite.attr("type", "unit")
        case .bubble:
            xml += XMLWrite.attr("type", "bubble")
            guard let bubble = unit.bubble else {
                fatalError("SceneXML unit '\(unit.name)' bubble missing meta")
            }
            xml += XMLWrite.attr("meta", bubble.encoded(unitName: unit.name))
        }
        xml += XMLWrite.attr("flipped", unit.flipped ? "true" : "false")
        xml += XMLWrite.attr("arrange", "\(unit.arrange)")
        xml += XMLWrite.attr("scale", XMLWrite.float(unit.scale))
        xml += XMLWrite.attr("alpha", XMLWrite.float(unit.alpha))
        xml += XMLWrite.attr("state", "\(unit.assetsState)")
        xml += ">\n"
        for point in unit.points {
            xml += serialize(point, unitName: unit.name)
        }
        xml += "</unit>\n"
        return xml
    }

    private static func serialize(_ point: StickmanPoint, unitName: String) -> String {
        var xml = "<point"
        xml += XMLWrite.attr("id", "\(point.id)")
        xml += XMLWrite.attr("x", XMLWrite.float(point.x))
        xml += XMLWrite.attr("y", XMLWrite.float(point.y))
        if point.isBase {
            xml += XMLWrite.attr("base", "true")
        } else {
            guard let parentId = point.parentId else {
                fatalError("SceneXML unit '\(unitName)' point \(point.id) missing par")
            }
            xml += XMLWrite.attr("par", "\(parentId)")
        }
        switch point.attachable {
        case .none:
            break
        case .master:
            xml += XMLWrite.attr("attachable", "master")
        case .slave:
            xml += XMLWrite.attr("attachable", "slave")
            if let name = point.attachedMasterName, let id = point.attachedMasterPointId {
                xml += XMLWrite.attr("attached", "\(name)&\(id)")
            }
        }
        xml += " />\n"
        return xml
    }

    private final class Sink: NSObject, XMLParserDelegate {
        var width: CGFloat?
        var height: CGFloat?
        var interframes: Int?
        var noInterpolation = false
        var noInterpolationFrames = 0
        var frames: [StickmanFrame] = []

        private var frameId: Int?
        private var frameBgName: String?
        private var frameBgMove: PictureMove = .identity
        private var frameCameraMove: PictureMove = .identity
        private var frameUnits: [StickmanUnit] = []
        private var unitName: String?
        private var unitScale: CGFloat?
        private var unitAlpha: CGFloat?
        private var unitArrange: Int?
        private var unitFlipped = false
        private var unitState = 0
        private var unitType: StickmanUnitType = .unit
        private var unitBubble: BubbleMeta?
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
                guard let text = attributes["interframes"], let value = Int(text) else {
                    fatalError("SceneLoader scene missing interframes")
                }
                if value < 1 {
                    fatalError("SceneLoader interframes is \(value)")
                }
                interframes = value
                if let text = attributes["no_interpolation"] {
                    switch text.lowercased() {
                    case "true":
                        noInterpolation = true
                    case "false":
                        noInterpolation = false
                    default:
                        fatalError("SceneLoader no_interpolation is \(text)")
                    }
                }
                if let text = attributes["no_interpolation_frames"] {
                    guard let frames = Int(text) else {
                        fatalError("SceneLoader no_interpolation_frames is \(text)")
                    }
                    noInterpolationFrames = frames
                }
            case "frame":
                guard let idText = attributes["id"], let id = Int(idText) else {
                    fatalError("SceneLoader frame missing id")
                }
                // GOTCHA (doc/gotchas.md): older frames omit bg_name / bg;
                // Android keeps #ffffff and identity PictureMove.
                let bgName: String
                if let text = attributes["bg_name"], !text.isEmpty {
                    bgName = text
                } else {
                    bgName = "#ffffff"
                }
                if bgName.hasPrefix("#") {
                    _ = HexRGB.parse(bgName)
                } else if bgName.hasPrefix("usermade:") {
                    if SceneLoader.ownName(bgName).isEmpty {
                        fatalError("SceneLoader frame \(id) bg_name '\(bgName)' has empty own name")
                    }
                } else {
                    fatalError("SceneLoader frame \(id) unknown bg_name '\(bgName)'")
                }
                frameId = id
                frameBgName = bgName
                if let bgMoveText = attributes["bg"], !bgMoveText.isEmpty {
                    frameBgMove = PictureMove.parse(bgMoveText)
                } else {
                    frameBgMove = .identity
                }
                if let cameraText = attributes["camera"], !cameraText.isEmpty {
                    frameCameraMove = PictureMove.parse(cameraText)
                } else {
                    frameCameraMove = .identity
                }
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
                // GOTCHA (doc/gotchas.md): Android stores alpha as-is; 1.08 is opaque.
                if alpha < 0 {
                    fatalError("SceneLoader unit '\(name)' alpha is \(alpha)")
                }
                guard let arrangeText = attributes["arrange"], let arrange = Int(arrangeText) else {
                    fatalError("SceneLoader unit '\(name)' missing arrange")
                }
                unitName = name
                unitScale = CGFloat(scale)
                unitAlpha = CGFloat(alpha)
                unitArrange = arrange
                unitFlipped = attributes["flipped"] == "true"
                if let text = attributes["state"] {
                    guard let state = Int(text) else {
                        fatalError("SceneLoader unit '\(name)' state '\(text)' is not an int")
                    }
                    unitState = state
                } else {
                    unitState = 0
                }
                switch attributes["type"] {
                case nil, "", "unit":
                    unitType = .unit
                    unitBubble = nil
                case "bubble":
                    guard let meta = attributes["meta"], !meta.isEmpty else {
                        fatalError("SceneLoader unit '\(name)' bubble missing meta")
                    }
                    unitType = .bubble
                    unitBubble = BubbleMeta.parse(encoded: meta, unitName: name)
                case let other?:
                    fatalError("SceneLoader unit '\(name)' unknown type '\(other)'")
                }
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
                guard let name = unitName, let scale = unitScale, let alpha = unitAlpha, let arrange = unitArrange else {
                    fatalError("SceneLoader unit ended without name/scale/alpha/arrange")
                }
                if unitPoints.isEmpty {
                    fatalError("SceneLoader unit '\(name)' has no points")
                }
                var unit = StickmanUnit(
                    name: name,
                    points: uniquePoints(unitPoints, unitName: name),
                    edges: [],
                    scale: scale,
                    alpha: alpha,
                    arrange: arrange,
                    flipped: unitFlipped,
                    assetsState: unitState,
                    unitType: unitType,
                    bubble: unitBubble
                )
                unit.link()
                frameUnits.append(unit)
                unitName = nil
                unitScale = nil
                unitAlpha = nil
                unitArrange = nil
                unitFlipped = false
                unitState = 0
                unitType = .unit
                unitBubble = nil
                unitPoints = []
            } else if elementName == "frame" {
                guard let id = frameId, let bgName = frameBgName else {
                    fatalError("SceneLoader frame ended without id/bg_name")
                }
                if frameUnits.isEmpty {
                    fatalError("SceneLoader frame \(id) has no units")
                }
                var frame = StickmanFrame(
                    id: id,
                    units: frameUnits,
                    bgName: bgName,
                    bgMove: frameBgMove,
                    cameraMove: frameCameraMove
                )
                frame.refreshAttachments()
                frames.append(frame)
                frameId = nil
                frameBgName = nil
                frameBgMove = .identity
                frameCameraMove = .identity
                frameUnits = []
            }
        }

        private func uniquePoints(_ points: [StickmanPoint], unitName: String) -> [StickmanPoint] {
            var byId: [Int: StickmanPoint] = [:]
            var order: [Int] = []
            for point in points {
                if let existing = byId[point.id] {
                    if existing.x != point.x
                        || existing.y != point.y
                        || existing.isBase != point.isBase
                        || existing.parentId != point.parentId
                        || existing.attachable != point.attachable
                        || existing.attachedMasterName != point.attachedMasterName
                        || existing.attachedMasterPointId != point.attachedMasterPointId
                    {
                        fatalError("SceneLoader unit '\(unitName)' duplicate point \(point.id) disagrees")
                    }
                    continue
                }
                byId[point.id] = point
                order.append(point.id)
            }
            return order.map { byId[$0]! }
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
            let attachable: Attachable
            switch attributes["attachable"] {
            case nil:
                attachable = .none
            case "master":
                attachable = .master
            case "slave":
                attachable = .slave
            case let other?:
                fatalError("SceneLoader point \(id) unknown attachable '\(other)'")
            }
            var attachedName: String?
            var attachedId: Int?
            if let attached = attributes["attached"], !attached.isEmpty {
                let parts = attached.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
                if parts.count != 2 {
                    fatalError("SceneLoader point \(id) attached '\(attached)' is not name&id")
                }
                guard let masterId = Int(parts[1]) else {
                    fatalError("SceneLoader point \(id) attached id '\(parts[1])' is not an int")
                }
                if masterId != -1 && parts[0] != "null" && !parts[0].isEmpty {
                    attachedName = parts[0]
                    attachedId = masterId
                }
            }
            return StickmanPoint(
                id: id,
                x: CGFloat(x),
                y: CGFloat(y),
                isBase: isBase,
                parentId: parentId,
                attachable: attachable,
                attachedMasterName: attachedName,
                attachedMasterPointId: attachedId
            )
        }
    }
}
