import CoreGraphics
import Foundation

struct SceneLoadError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum HexRGB {
    static func parse(_ text: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        try? parseThrowing(text)
    }

    static func parseThrowing(_ text: String) throws -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        if !text.hasPrefix("#") {
            throw SceneLoadError(message: "SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
        }
        let hex = text.dropFirst()
        guard let value = UInt32(hex, radix: 16) else {
            throw SceneLoadError(message: "SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
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
            throw SceneLoadError(message: "SceneLoader color '\(text)' is not #rrggbb or #aarrggbb")
        }
    }
}

enum SceneLoader {
    static func load(resource: String, subdirectory: String) throws -> (StickmanScene, UnitAssets, BackgroundAssets) {
        try load(zip: ItemLoader.archive(resource: resource, subdirectory: subdirectory, ext: "ats"), resource: resource)
    }

    static func load(url: URL) throws -> (StickmanScene, UnitAssets, BackgroundAssets) {
        let zip: Data
        do {
            zip = try Data(contentsOf: url)
        } catch {
            throw SceneLoadError(message: "SceneLoader could not read \(url.path): \(error)")
        }
        return try load(zip: zip, resource: url.deletingPathExtension().lastPathComponent)
    }

    static func load(zip: Data, resource: String) throws -> (StickmanScene, UnitAssets, BackgroundAssets) {
        let names: [String]
        do {
            names = try ZipStore.namesThrowing(in: zip)
        } catch {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' is not a scene archive: \(error)")
        }
        if !names.contains("model.xml") {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' missing model.xml")
        }
        try StickmanFonts.installSceneFonts(zip: zip, names: names, resource: resource)
        var scene = try SceneXML.parse(ZipStore.dataThrowing(named: "model.xml", in: zip))
        scene.unitAnimations = try loadAnimations(zip: zip, names: names, resource: resource)
        scene.unitTweens = try loadUnitTweens(zip: zip, names: names, scene: scene, resource: resource)
        scene.cameraTweens = try loadCameraTweens(zip: zip, names: names, scene: scene, resource: resource)
        // GOTCHA (doc/gotchas.md): pack items live at pack/items/name.ati, not zip root.
        // Android does not embed native (no-dot) pack items; those come from the bundled .atp.
        let items = names.filter { $0.hasSuffix(".ati") && !$0.hasSuffix("/") }
        let assets = UnitAssets()
        for item in items {
            try assets.loadItemFromArchive(try ZipStore.dataThrowing(named: item, in: zip), entryName: item)
        }
        try ensureAssets(scene: scene, assets: assets, resource: resource)
        let backgrounds = loadBackgrounds(scene: &scene, zip: zip, names: names, resource: resource)
        return (scene, assets, backgrounds)
    }

    /// File-supplied unit names must resolve without trapping in PackAlias.
    static func resolveUnitName(_ name: String) throws -> String {
        let core = UnitAssets.removeNumber(name)
        if let colon = core.firstIndex(of: ":"), core[core.index(after: colon)...].isEmpty {
            throw SceneLoadError(message: "SceneLoader unit name '\(name)' has empty own name")
        }
        return PackAlias.resolveUnitName(name)
    }

    private static func loadAnimations(zip: Data, names: [String], resource: String) throws -> [String: FBFAnimation] {
        if !names.contains("animations_v2.txt") {
            return [:]
        }
        let data = try ZipStore.dataThrowing(named: "animations_v2.txt", in: zip)
        let parsed: [FBFAnimation]
        do {
            parsed = try JSONDecoder().decode([FBFAnimation].self, from: data)
        } catch {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' animations_v2.txt is not FBF JSON: \(error)")
        }
        var result: [String: FBFAnimation] = [:]
        for animation in parsed {
            if animation.unitname.isEmpty {
                throw SceneLoadError(message: "SceneLoader '\(resource).ats' FBF animation missing unitname")
            }
            if animation.period < 1 {
                throw SceneLoadError(message: "SceneLoader '\(resource).ats' FBF '\(animation.unitname)' period is \(animation.period)")
            }
            let unitname = try resolveUnitName(animation.unitname)
            if result[unitname] != nil {
                throw SceneLoadError(message: "SceneLoader '\(resource).ats' duplicate FBF '\(unitname)'")
            }
            var mapped = animation
            mapped.unitname = unitname
            result[unitname] = mapped
        }
        return result
    }

    private static func loadUnitTweens(
        zip: Data,
        names: [String],
        scene: StickmanScene,
        resource _: String
    ) throws -> UnitTweenStorage {
        if !names.contains(UnitTweenStorage.archiveName) {
            return UnitTweenStorage()
        }
        var storage = UnitTweenStorage()
        try storage.importArchive(ZipStore.dataThrowing(named: UnitTweenStorage.archiveName, in: zip), scene: scene)
        return storage
    }

    private static func loadCameraTweens(
        zip: Data,
        names: [String],
        scene: StickmanScene,
        resource _: String
    ) throws -> CameraTweenStorage {
        if !names.contains(CameraTweenStorage.archiveName) {
            return CameraTweenStorage()
        }
        var storage = CameraTweenStorage()
        try storage.importArchive(ZipStore.dataThrowing(named: CameraTweenStorage.archiveName, in: zip), scene: scene)
        return storage
    }

    private static func loadBackgrounds(
        scene: inout StickmanScene,
        zip: Data,
        names: [String],
        resource: String
    ) -> BackgroundAssets {
        let backgrounds = BackgroundAssets()
        // GOTCHA (doc/gotchas.md): old demos (demo_space, demo_fight) put bg.png at zip root
        // and omit bg_name. Android wraps that PNG as usermade and stamps every frame.
        if names.contains("bg.png") {
            let png: Data?
            do {
                png = try ZipStore.dataThrowing(named: "bg.png", in: zip)
            } catch {
                backgrounds.recordLoadError("\(error)")
                png = nil
            }
            if let png, let image = BackgroundAssets.tryDecode(png) {
                let own = "\(Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)))"
                let bgName = "usermade:\(own)"
                backgrounds.install(
                    name: bgName,
                    image: image,
                    archive: ZipStore.archive([(name: "bg.png", data: png)])
                )
                for i in scene.frames.indices {
                    scene.frames[i].bgName = bgName
                }
            } else {
                backgrounds.recordLoadError("\(BackgroundStore.Failure.notAnImage("bg.png"))")
            }
        }
        var failed: Set<String> = []
        for frame in scene.frames {
            guard let bgName = frame.bgName, !bgName.hasPrefix("#") else { continue }
            if backgrounds.hasImage(for: bgName) || failed.contains(bgName) { continue }
            do {
                try installSceneBackground(bgName, zip: zip, names: names, into: backgrounds)
            } catch {
                failed.insert(bgName)
                print("SceneLoader '\(resource).ats' background: \(error)")
                backgrounds.recordLoadError("\(error)")
            }
        }
        if !failed.isEmpty {
            for i in scene.frames.indices {
                if let bgName = scene.frames[i].bgName, failed.contains(bgName) {
                    scene.frames[i].bgName = "#ffffff"
                    scene.frames[i].bgMove = .identity
                }
            }
        }
        return backgrounds
    }

    /// Scene-embedded `_bgs/<own>.zip` first, then the device `bgs` / `bgs_ro` archives.
    private static func installSceneBackground(
        _ bgName: String,
        zip: Data,
        names: [String],
        into backgrounds: BackgroundAssets
    ) throws {
        guard bgName.hasPrefix(BackgroundStore.usermadePrefix),
              bgName.count > BackgroundStore.usermadePrefix.count
        else {
            throw BackgroundStore.Failure.unsupported(bgName)
        }
        let entry = "_bgs/\(ownName(bgName)).zip"
        if names.contains(entry) {
            try backgrounds.installArchive(name: bgName, archive: ZipStore.dataThrowing(named: entry, in: zip))
            return
        }
        try BackgroundResolver.install(bgName, into: backgrounds)
    }

    private static func ensureAssets(scene: StickmanScene, assets: UnitAssets, resource: String) throws {
        var seen = Set<String>()
        for frame in scene.frames {
            for unit in frame.units {
                let name = UnitAssets.removeNumber(unit.name)
                if seen.contains(name) {
                    continue
                }
                seen.insert(name)
                if let colon = name.firstIndex(of: ":"), name[name.index(after: colon)...].isEmpty {
                    throw SceneLoadError(message: "SceneLoader unit name '\(unit.name)' has empty own name")
                }
                if assets.hasAssetsFor(unitName: name) {
                    continue
                }
                if unit.unitType == .bubble, assets.hasArchive(for: name) {
                    continue
                }
                let zip = try Manifest.shared.itemZip(fullname: name)
                try assets.loadItemFromArchive(zip, entryName: UnitAssets.atiEntryName(for: name))
                if unit.unitType == .bubble {
                    continue
                }
                if !assets.hasAssetsFor(unitName: name) {
                    throw SceneLoadError(message: "SceneLoader assets missing unit '\(name)'")
                }
            }
        }
        if seen.isEmpty {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' has no units")
        }
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
    static func parse(_ data: Data) throws -> StickmanScene {
        let parser = XMLParser(data: data)
        let sink = Sink()
        parser.delegate = sink
        let ok = parser.parse()
        if let failure = sink.failure {
            throw SceneLoadError(message: failure)
        }
        if !ok {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            throw SceneLoadError(message: "SceneLoader model.xml parse failed: \(detail)")
        }
        guard let width = sink.width, let height = sink.height else {
            throw SceneLoadError(message: "SceneLoader model.xml missing scene w/h")
        }
        if width <= 0 || height <= 0 {
            throw SceneLoadError(message: "SceneLoader scene size \(width)x\(height)")
        }
        if sink.frames.isEmpty {
            throw SceneLoadError(message: "SceneLoader model.xml has no frames")
        }
        guard let interframes = sink.interframes else {
            throw SceneLoadError(message: "SceneLoader scene missing interframes")
        }
        var scene = StickmanScene(
            width: width,
            height: height,
            frames: sink.frames,
            currentIndex: 0,
            interframes: interframes,
            noInterpolation: sink.noInterpolation,
            noInterpolationFrames: sink.noInterpolationFrames,
            speedModifier: sink.speedModifier
        )
        if !scene.speedModifier.isEmpty {
            scene.speedModifier.adjustTo(frameCount: scene.frames.count)
        }
        return scene
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
        if !scene.speedModifier.isEmpty {
            xml += XMLWrite.attr("pivot_points", scene.speedModifier.encodeJSON())
        }
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
        var speedModifier = SpeedModifier()
        var frames: [StickmanFrame] = []
        var failure: String?

        private func fail(_ parser: XMLParser, _ message: String) {
            if failure == nil {
                failure = message
            }
            parser.abortParsing()
        }

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
                    fail(parser, "SceneLoader scene missing w")
                    return
                }
                guard let hText = attributes["h"], let h = Double(hText) else {
                    fail(parser, "SceneLoader scene missing h")
                    return
                }
                width = CGFloat(w)
                height = CGFloat(h)
                guard let text = attributes["interframes"], let value = Int(text) else {
                    fail(parser, "SceneLoader scene missing interframes")
                    return
                }
                if value < 1 {
                    fail(parser, "SceneLoader interframes is \(value)")
                    return
                }
                interframes = value
                if let text = attributes["no_interpolation"] {
                    switch text.lowercased() {
                    case "true":
                        noInterpolation = true
                    case "false":
                        noInterpolation = false
                    default:
                        fail(parser, "SceneLoader no_interpolation is \(text)")
                        return
                    }
                }
                if let text = attributes["no_interpolation_frames"] {
                    guard let frames = Int(text) else {
                        fail(parser, "SceneLoader no_interpolation_frames is \(text)")
                        return
                    }
                    noInterpolationFrames = frames
                }
                if let text = attributes["pivot_points"], !text.isEmpty {
                    do {
                        speedModifier = try SpeedModifier.decode(text)
                    } catch {
                        fail(parser, "\(error)")
                        return
                    }
                }
            case "frame":
                guard let idText = attributes["id"], let id = Int(idText) else {
                    fail(parser, "SceneLoader frame missing id")
                    return
                }
                // GOTCHA (doc/gotchas.md): older frames omit bg_name; Android Frame
                // defaults to #ffffff. Root zip bg.png is applied after parse.
                let bgName: String
                if let text = attributes["bg_name"], !text.isEmpty {
                    bgName = text
                } else {
                    bgName = "#ffffff"
                }
                if bgName.hasPrefix("#") {
                    do {
                        _ = try HexRGB.parseThrowing(bgName)
                    } catch {
                        fail(parser, "\(error)")
                        return
                    }
                }
                frameId = id
                frameBgName = bgName
                if let bgMoveText = attributes["bg"], !bgMoveText.isEmpty {
                    do {
                        frameBgMove = try PictureMove.parse(bgMoveText)
                    } catch {
                        fail(parser, "\(error)")
                        return
                    }
                } else {
                    frameBgMove = .identity
                }
                if let cameraText = attributes["camera"], !cameraText.isEmpty {
                    do {
                        frameCameraMove = try PictureMove.parse(cameraText)
                    } catch {
                        fail(parser, "\(error)")
                        return
                    }
                } else {
                    frameCameraMove = .identity
                }
                frameUnits = []
            case "unit":
                guard let name = attributes["name"], !name.isEmpty else {
                    fail(parser, "SceneLoader unit missing name")
                    return
                }
                guard let scaleText = attributes["scale"], let scale = Double(scaleText) else {
                    fail(parser, "SceneLoader unit '\(name)' missing scale")
                    return
                }
                if scale <= 0 {
                    fail(parser, "SceneLoader unit '\(name)' scale is \(scale)")
                    return
                }
                guard let alphaText = attributes["alpha"], let alpha = Double(alphaText) else {
                    fail(parser, "SceneLoader unit '\(name)' missing alpha")
                    return
                }
                // GOTCHA (doc/gotchas.md): Android stores alpha as-is; 1.08 is opaque.
                if alpha < 0 {
                    fail(parser, "SceneLoader unit '\(name)' alpha is \(alpha)")
                    return
                }
                guard let arrangeText = attributes["arrange"], let arrange = Int(arrangeText) else {
                    fail(parser, "SceneLoader unit '\(name)' missing arrange")
                    return
                }
                do {
                    unitName = try SceneLoader.resolveUnitName(name)
                } catch {
                    fail(parser, "\(error)")
                    return
                }
                unitScale = CGFloat(scale)
                unitAlpha = CGFloat(alpha)
                unitArrange = arrange
                unitFlipped = attributes["flipped"] == "true"
                if let text = attributes["state"] {
                    guard let state = Int(text) else {
                        fail(parser, "SceneLoader unit '\(name)' state '\(text)' is not an int")
                        return
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
                    unitType = .bubble
                    if let meta = attributes["meta"], !meta.isEmpty {
                        do {
                            unitBubble = try BubbleMeta.parse(encoded: meta, unitName: name)
                        } catch {
                            fail(parser, "\(error)")
                            return
                        }
                    } else {
                        unitBubble = .defaults
                    }
                case let other?:
                    fail(parser, "SceneLoader unit '\(name)' unknown type '\(other)'")
                    return
                }
                unitPoints = []
            case "point":
                if let point = parsePoint(attributes, parser) {
                    unitPoints.append(point)
                }
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
                    fail(parser, "SceneLoader unit ended without name/scale/alpha/arrange")
                    return
                }
                if unitPoints.isEmpty {
                    fail(parser, "SceneLoader unit '\(name)' has no points")
                    return
                }
                var unit = StickmanUnit(
                    name: name,
                    points: uniquePoints(unitPoints, unitName: name, parser: parser),
                    edges: [],
                    scale: scale,
                    alpha: alpha,
                    arrange: arrange,
                    flipped: unitFlipped,
                    assetsState: unitState,
                    unitType: unitType,
                    bubble: unitBubble
                )
                do {
                    try unit.link()
                } catch {
                    fail(parser, "\(error)")
                    return
                }
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
                    fail(parser, "SceneLoader frame ended without id/bg_name")
                    return
                }
                if frameUnits.isEmpty {
                    fail(parser, "SceneLoader frame \(id) has no units")
                    return
                }
                var frame = StickmanFrame(
                    id: id,
                    units: frameUnits,
                    bgName: bgName,
                    bgMove: frameBgMove,
                    cameraMove: frameCameraMove
                )
                do {
                    try frame.slaves.populate(units: frame.units)
                } catch {
                    fail(parser, "\(error)")
                    return
                }
                frames.append(frame)
                frameId = nil
                frameBgName = nil
                frameBgMove = .identity
                frameCameraMove = .identity
                frameUnits = []
            }
        }

        private func uniquePoints(_ points: [StickmanPoint], unitName: String, parser: XMLParser) -> [StickmanPoint] {
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
                        fail(parser, "SceneLoader unit '\(unitName)' duplicate point \(point.id) disagrees")
                        return points
                    }
                    continue
                }
                byId[point.id] = point
                order.append(point.id)
            }
            return order.map { byId[$0]! }
        }

        private func parsePoint(_ attributes: [String: String], _ parser: XMLParser) -> StickmanPoint? {
            guard let idText = attributes["id"], let id = Int(idText) else {
                fail(parser, "SceneLoader point missing id")
                return nil
            }
            guard let xText = attributes["x"], let x = Double(xText) else {
                fail(parser, "SceneLoader point \(id) missing x")
                return nil
            }
            guard let yText = attributes["y"], let y = Double(yText) else {
                fail(parser, "SceneLoader point \(id) missing y")
                return nil
            }
            let isBase = attributes["base"] == "true"
            let parentId: Int?
            if isBase {
                parentId = nil
            } else {
                guard let parText = attributes["par"], let par = Int(parText) else {
                    fail(parser, "SceneLoader point \(id) missing par")
                    return nil
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
                fail(parser, "SceneLoader point \(id) unknown attachable '\(other)'")
                return nil
            }
            var attachedName: String?
            var attachedId: Int?
            if let attached = attributes["attached"], !attached.isEmpty {
                let parts = attached.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
                if parts.count != 2 {
                    fail(parser, "SceneLoader point \(id) attached '\(attached)' is not name&id")
                    return nil
                }
                guard let masterId = Int(parts[1]) else {
                    fail(parser, "SceneLoader point \(id) attached id '\(parts[1])' is not an int")
                    return nil
                }
                if masterId != -1 && parts[0] != "null" && !parts[0].isEmpty {
                    do {
                        attachedName = try SceneLoader.resolveUnitName(parts[0])
                    } catch {
                        fail(parser, "\(error)")
                        return nil
                    }
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
