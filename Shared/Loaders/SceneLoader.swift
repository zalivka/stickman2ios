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
        let zipIndex: ZipStore.Index
        do {
            zipIndex = try ZipStore.indexThrowing(in: zip)
        } catch {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' is not a scene archive: \(error)")
        }
        let names = zipIndex.names
        if !zipIndex.contains("model.xml") {
            throw SceneLoadError(message: "SceneLoader '\(resource).ats' missing model.xml")
        }
        try StickmanFonts.installSceneFonts(zip: zip, names: names, resource: resource)
        var scene = try SceneXML.parse(zipIndex.dataThrowing(named: "model.xml"))
        scene.unitAnimations = try loadAnimations(zipIndex: zipIndex, resource: resource)
        scene.unitTweens = try loadUnitTweens(zipIndex: zipIndex, scene: scene, resource: resource)
        scene.cameraTweens = try loadCameraTweens(zipIndex: zipIndex, scene: scene, resource: resource)
        scene.backgroundTweens = try loadBackgroundTweens(zipIndex: zipIndex, scene: scene, resource: resource)
        scene.audio = try SceneAudioArchive.load(
            zip: zip,
            names: names,
            sceneKey: SceneAudioStorage.key(resource: resource, zip: zip)
        )
        try SceneAudioArchive.validate(scene: &scene)
        // GOTCHA (doc/gotchas.md): pack items live at pack/items/name.ati, not zip root.
        // Android does not embed native (no-dot) pack items; those come from the bundled .atp.
        let items = names.filter { $0.hasSuffix(".ati") && !$0.hasSuffix("/") }
        let assets = UnitAssets()
        if items.count > 1 {
            var itemZips: [(name: String, data: Data)] = []
            itemZips.reserveCapacity(items.count)
            for item in items {
                itemZips.append((name: item, data: try zipIndex.dataThrowing(named: item)))
            }
            var results = [Result<UnitAssets.DecodedArchiveItem, Error>?](repeating: nil, count: itemZips.count)
            results.withUnsafeMutableBufferPointer { buf in
                DispatchQueue.concurrentPerform(iterations: itemZips.count) { idx in
                    let entry = itemZips[idx]
                    buf[idx] = Result {
                        try UnitAssets.decodeItemFromArchive(entry.data, entryName: entry.name)
                    }
                }
            }
            for result in results {
                guard let result else { continue }
                let decoded = try result.get()
                assets.applyDecodedItem(decoded)
            }
        } else {
            for item in items {
                try assets.loadItemFromArchive(try zipIndex.dataThrowing(named: item), entryName: item)
            }
        }
        try ensureAssets(scene: scene, assets: assets, resource: resource)
        let backgrounds = try loadBackgrounds(scene: &scene, zipIndex: zipIndex, resource: resource)
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

    private static func loadAnimations(zipIndex: ZipStore.Index, resource: String) throws -> [String: FBFAnimation] {
        if !zipIndex.contains("animations_v2.txt") {
            return [:]
        }
        let data = try zipIndex.dataThrowing(named: "animations_v2.txt")
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
        zipIndex: ZipStore.Index,
        scene: StickmanScene,
        resource _: String
    ) throws -> UnitTweenStorage {
        if !zipIndex.contains(UnitTweenStorage.archiveName) {
            return UnitTweenStorage()
        }
        var storage = UnitTweenStorage()
        try storage.importArchive(zipIndex.dataThrowing(named: UnitTweenStorage.archiveName), scene: scene)
        return storage
    }

    private static func loadCameraTweens(
        zipIndex: ZipStore.Index,
        scene: StickmanScene,
        resource _: String
    ) throws -> CameraTweenStorage {
        if !zipIndex.contains(CameraTweenStorage.archiveName) {
            return CameraTweenStorage()
        }
        var storage = CameraTweenStorage()
        try storage.importArchive(zipIndex.dataThrowing(named: CameraTweenStorage.archiveName), scene: scene)
        return storage
    }

    private static func loadBackgroundTweens(
        zipIndex: ZipStore.Index,
        scene: StickmanScene,
        resource _: String
    ) throws -> BackgroundTweenStorage {
        if !zipIndex.contains(BackgroundTweenStorage.archiveName) {
            return BackgroundTweenStorage()
        }
        var storage = BackgroundTweenStorage()
        try storage.importArchive(zipIndex.dataThrowing(named: BackgroundTweenStorage.archiveName), scene: scene)
        return storage
    }

    private static func loadBackgrounds(
        scene: inout StickmanScene,
        zipIndex: ZipStore.Index,
        resource: String
    ) throws -> BackgroundAssets {
        let backgrounds = BackgroundAssets()
        // GOTCHA (doc/gotchas.md): old demos (demo_space, demo_fight) put bg.png at zip root
        // and omit bg_name. Android wraps that PNG as usermade and stamps every frame.
        if zipIndex.contains("bg.png") {
            let png: Data?
            do {
                png = try zipIndex.dataThrowing(named: "bg.png")
            } catch {
                backgrounds.recordLoadError("\(error)")
                png = nil
            }
            if let png, let decoded = BackgroundAssets.tryDecodeSampled(png) {
                let own = "\(Int((Date().timeIntervalSince1970 * 1000).rounded(.towardZero)))"
                let bgName = "usermade:\(own)"
                backgrounds.install(
                    name: bgName,
                    image: decoded.image,
                    sampleScale: decoded.sampleScale,
                    archive: try ZipStore.archive([(name: "bg.png", data: png)])
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
                try installSceneBackground(bgName, zipIndex: zipIndex, into: backgrounds)
            } catch {
                failed.insert(bgName)
                print("SceneLoader '\(resource).ats' background: \(error)")
                backgrounds.recordLoadError("\(error)")
            }
        }
        if !failed.isEmpty {
            for bgName in failed {
                scene.backgroundTweens.removeSpans(named: bgName)
            }
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
        zipIndex: ZipStore.Index,
        into backgrounds: BackgroundAssets
    ) throws {
        guard bgName.hasPrefix(BackgroundStore.usermadePrefix),
              bgName.count > BackgroundStore.usermadePrefix.count
        else {
            throw BackgroundStore.Failure.unsupported(bgName)
        }
        let entry = "_bgs/\(ownName(bgName)).zip"
        if zipIndex.contains(entry) {
            try backgrounds.installArchive(name: bgName, archive: zipIndex.dataThrowing(named: entry))
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
            // Callers feed the result into zip lookups; an empty own name simply misses.
            assertionFailure("SceneLoader unit name '\(unitName)' has empty own name")
        }
        return rest
    }
}

enum SceneXML {
    static func parse(_ data: Data) throws -> StickmanScene {
        let sink = try data.withUnsafeBytes { rawBuf -> FastSink in
            var s = FastSink()
            if let base = rawBuf.bindMemory(to: UInt8.self).baseAddress, rawBuf.count > 0 {
                try s.parse(base: base, count: rawBuf.count)
            } else {
                throw SceneLoadError(message: "SceneLoader model.xml parse failed: empty data")
            }
            return s
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

    static func serialize(_ scene: StickmanScene) throws -> Data {
        if scene.frames.isEmpty {
            throw SceneLoadError(message: "SceneXML serialize has no frames")
        }
        if scene.width <= 0 || scene.height <= 0 {
            throw SceneLoadError(message: "SceneXML serialize size \(scene.width)x\(scene.height)")
        }
        if scene.interframes < 0 {
            throw SceneLoadError(message: "SceneXML serialize interframes is \(scene.interframes)")
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
            xml += XMLWrite.attr("pivot_points", try scene.speedModifier.encodeJSON())
        }
        xml += ">\n"
        var written = 0
        for frame in scene.frames {
            if frame.id == -1 {
                continue
            }
            xml += try serialize(frame)
            written += 1
        }
        if written == 0 {
            throw SceneLoadError(message: "SceneXML serialize has no frames")
        }
        xml += "</scene>\n"
        return try XMLWrite.data(xml)
    }

    private static func serialize(_ frame: StickmanFrame) throws -> String {
        let bgName = frame.bgName ?? "#ffffff"
        var xml = "<frame"
        xml += XMLWrite.attr("id", "\(frame.id)")
        xml += XMLWrite.attr("bg", frame.bgMove.serialize())
        xml += XMLWrite.attr("camera", frame.cameraMove.serialize())
        xml += XMLWrite.attr("bg_name", bgName)
        xml += ">\n"
        for unit in frame.units {
            xml += try serialize(unit)
        }
        xml += "</frame>\n"
        return xml
    }

    private static func serialize(_ unit: StickmanUnit) throws -> String {
        if unit.name.isEmpty {
            throw SceneLoadError(message: "SceneXML unit has empty name")
        }
        if unit.points.isEmpty {
            throw SceneLoadError(message: "SceneXML unit '\(unit.name)' has no points")
        }
        if unit.scale <= 0 {
            throw SceneLoadError(message: "SceneXML unit '\(unit.name)' scale is \(unit.scale)")
        }
        if unit.alpha < 0 {
            throw SceneLoadError(message: "SceneXML unit '\(unit.name)' alpha is \(unit.alpha)")
        }
        var xml = "<unit"
        xml += XMLWrite.attr("name", unit.name)
        switch unit.unitType {
        case .unit:
            xml += XMLWrite.attr("type", "unit")
        case .bubble:
            xml += XMLWrite.attr("type", "bubble")
            guard let bubble = unit.bubble else {
                throw SceneLoadError(message: "SceneXML unit '\(unit.name)' bubble missing meta")
            }
            xml += XMLWrite.attr("meta", try bubble.encoded(unitName: unit.name))
        }
        xml += XMLWrite.attr("flipped", unit.flipped ? "true" : "false")
        xml += XMLWrite.attr("arrange", "\(unit.arrange)")
        xml += XMLWrite.attr("scale", XMLWrite.float(unit.scale))
        xml += XMLWrite.attr("alpha", XMLWrite.float(unit.alpha))
        xml += XMLWrite.attr("state", "\(unit.assetsState)")
        xml += ">\n"
        for point in unit.points {
            xml += try serialize(point, unitName: unit.name)
        }
        xml += "</unit>\n"
        return xml
    }

    private static func serialize(_ point: StickmanPoint, unitName: String) throws -> String {
        var xml = "<point"
        xml += XMLWrite.attr("id", "\(point.id)")
        xml += XMLWrite.attr("x", XMLWrite.float(point.x))
        xml += XMLWrite.attr("y", XMLWrite.float(point.y))
        if point.isBase {
            xml += XMLWrite.attr("base", "true")
        } else {
            guard let parentId = point.parentId else {
                throw SceneLoadError(message: "SceneXML unit '\(unitName)' point \(point.id) missing par")
            }
            xml += XMLWrite.attr("par", "\(parentId)")
        }
        if point.fixed {
            xml += XMLWrite.attr("fixed", "true")
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
        if let name = point.semanticName {
            xml += XMLWrite.attr("name", name)
        }
        if point.kinematicStart {
            xml += XMLWrite.attr("kinstart", "true")
        }
        if point.kinematicStop {
            xml += XMLWrite.attr("kinstop", "true")
        }
        if point.stretchable {
            xml += XMLWrite.attr("stretchable", "true")
        }
        xml += " />\n"
        return xml
    }

    private struct FastSink {
        var width: CGFloat?
        var height: CGFloat?
        var interframes: Int?
        var noInterpolation = false
        var noInterpolationFrames = 0
        var speedModifier = SpeedModifier()
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
        private var resolvedNameCache: [String: String] = [:]
        private var linkedEdgesCache: [String: (sig: [(id: Int, parentId: Int?, isBase: Bool)], edges: [StickmanEdge])] = [:]

        mutating func parse(base: UnsafePointer<UInt8>, count: Int) throws {
            let end = base + count
            var p = base
            unitPoints.reserveCapacity(64)

            while p < end {
                guard let ltRaw = memchr(p, 60, end - p) else { break }
                p = UnsafePointer(ltRaw.assumingMemoryBound(to: UInt8.self)) + 1
                if p >= end { break }
                let c0 = p[0]
                if c0 == 112 && p + 5 < end && p[1] == 111 && p[2] == 105 && p[3] == 110 && p[4] == 116 && p[5] <= 32 {
                    // <point
                    p += 6
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed point tag")
                    }
                    let gt = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self))
                    let pt = try parsePointFast(from: p, to: gt)
                    unitPoints.append(pt)
                    p = gt + 1
                } else if c0 == 117 && p + 4 < end && p[1] == 110 && p[2] == 105 && p[3] == 116 && (p[4] <= 32 || p[4] == 62) {
                    // <unit
                    p += 4
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed unit tag")
                    }
                    let gt = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self))
                    try startUnit(from: p, to: gt)
                    if gt > p && (gt - 1)[0] == 47 {
                        try endUnit()
                    }
                    p = gt + 1
                } else if c0 == 47 {
                    // Closing tag </...>
                    p += 1
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed end tag")
                    }
                    let gt = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self))
                    let len = gt - p
                    if len >= 4 && p[0] == 117 && p[1] == 110 && p[2] == 105 && p[3] == 116 && (len == 4 || p[4] <= 32) {
                        try endUnit()
                    } else if len >= 5 && p[0] == 102 && p[1] == 114 && p[2] == 97 && p[3] == 109 && p[4] == 101 && (len == 5 || p[5] <= 32) {
                        try endFrame()
                    }
                    p = gt + 1
                } else if c0 == 102 && p + 5 < end && p[1] == 114 && p[2] == 97 && p[3] == 109 && p[4] == 101 && (p[5] <= 32 || p[5] == 62) {
                    // <frame
                    p += 5
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed frame tag")
                    }
                    let gt = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self))
                    try startFrame(from: p, to: gt)
                    if gt > p && (gt - 1)[0] == 47 {
                        try endFrame()
                    }
                    p = gt + 1
                } else if c0 == 115 && p + 5 < end && p[1] == 99 && p[2] == 101 && p[3] == 110 && p[4] == 101 && (p[5] <= 32 || p[5] == 62) {
                    // <scene
                    p += 5
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed scene tag")
                    }
                    let gt = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self))
                    try startScene(from: p, to: gt)
                    p = gt + 1
                } else if c0 == 63 {
                    // <?xml ... ?>
                    guard let gtRaw = memchr(p, 62, end - p) else { break }
                    p = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self)) + 1
                } else if c0 == 33 {
                    // <!-- ... --> or <!DOCTYPE ...>
                    guard let gtRaw = memchr(p, 62, end - p) else { break }
                    p = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self)) + 1
                } else {
                    // Any other tag (e.g. <faces>, <face>)
                    guard let gtRaw = memchr(p, 62, end - p) else {
                        throw SceneLoadError(message: "SceneLoader model.xml parse failed: unclosed tag")
                    }
                    p = UnsafePointer(gtRaw.assumingMemoryBound(to: UInt8.self)) + 1
                }
            }
        }

        private mutating func resolveCached(_ raw: String) throws -> String {
            if let hit = resolvedNameCache[raw] { return hit }
            let resolved = try SceneLoader.resolveUnitName(raw)
            resolvedNameCache[raw] = resolved
            return resolved
        }

        private static func parseAttributes(from start: UnsafePointer<UInt8>, to gt: UnsafePointer<UInt8>) -> [String: String] {
            var attrs: [String: String] = [:]
            var p = start
            while p < gt {
                while p < gt && p[0] <= 32 { p += 1 }
                if p >= gt || p[0] == 47 { break }
                let nameStart = p
                guard let eqRaw = memchr(p, 61, gt - p) else { break }
                let eq = UnsafePointer(eqRaw.assumingMemoryBound(to: UInt8.self))
                var nameEnd = eq
                while nameEnd > nameStart && (nameEnd - 1)[0] <= 32 { nameEnd -= 1 }
                var valP = eq + 1
                while valP < gt && valP[0] <= 32 { valP += 1 }
                if valP >= gt { break }
                let quote = valP[0]
                guard quote == 34 || quote == 39 else { break }
                let valStart = valP + 1
                guard let qEndRaw = memchr(valStart, Int32(quote), gt - valStart) else { break }
                let valEnd = UnsafePointer(qEndRaw.assumingMemoryBound(to: UInt8.self))
                p = valEnd + 1
                let key = String(decoding: UnsafeBufferPointer(start: nameStart, count: nameEnd - nameStart), as: UTF8.self)
                attrs[key] = unescapeXML(valStart, valEnd - valStart)
            }
            return attrs
        }

        private static func unescapeXML(_ start: UnsafePointer<UInt8>, _ count: Int) -> String {
            guard count > 0 else { return "" }
            guard memchr(start, 38, count) != nil else {
                return String(decoding: UnsafeBufferPointer(start: start, count: count), as: UTF8.self)
            }
            var s = String(decoding: UnsafeBufferPointer(start: start, count: count), as: UTF8.self)
            s = s.replacingOccurrences(of: "&quot;", with: "\"")
            s = s.replacingOccurrences(of: "&apos;", with: "'")
            s = s.replacingOccurrences(of: "&lt;", with: "<")
            s = s.replacingOccurrences(of: "&gt;", with: ">")
            s = s.replacingOccurrences(of: "&amp;", with: "&")
            return s
        }

        @inline(__always)
        private static func parseInt(_ s: UnsafePointer<UInt8>, _ e: UnsafePointer<UInt8>) -> Int? {
            if s >= e { return nil }
            var cur = s
            var neg = false
            if cur[0] == 45 {
                neg = true
                cur += 1
            } else if cur[0] == 43 {
                cur += 1
            }
            if cur >= e { return nil }
            var val = 0
            while cur < e {
                let b = cur[0]
                guard b >= 48 && b <= 57 else { return nil }
                val = val &* 10 &+ Int(b &- 48)
                cur += 1
            }
            return neg ? -val : val
        }

        @inline(__always)
        private static func parseDouble(_ s: UnsafePointer<UInt8>, _ e: UnsafePointer<UInt8>) -> Double? {
            if s >= e { return nil }
            var endPtr: UnsafeMutablePointer<CChar>? = nil
            let cStart = UnsafePointer<CChar>(OpaquePointer(s))
            let d = strtod(cStart, &endPtr)
            guard let ep = endPtr, OpaquePointer(ep) == OpaquePointer(e) else {
                let text = String(decoding: UnsafeBufferPointer(start: s, count: e - s), as: UTF8.self)
                return Double(text)
            }
            return d
        }

        private mutating func startScene(from start: UnsafePointer<UInt8>, to gt: UnsafePointer<UInt8>) throws {
            let attributes = Self.parseAttributes(from: start, to: gt)
            guard let wText = attributes["w"], let w = Double(wText) else {
                throw SceneLoadError(message: "SceneLoader scene missing w")
            }
            guard let hText = attributes["h"], let h = Double(hText) else {
                throw SceneLoadError(message: "SceneLoader scene missing h")
            }
            width = CGFloat(w)
            height = CGFloat(h)
            guard let text = attributes["interframes"], let value = Int(text) else {
                throw SceneLoadError(message: "SceneLoader scene missing interframes")
            }
            if value < 0 {
                throw SceneLoadError(message: "SceneLoader interframes is \(value)")
            }
            interframes = value
            if let text = attributes["no_interpolation"] {
                switch text.lowercased() {
                case "true":
                    noInterpolation = true
                case "false":
                    noInterpolation = false
                default:
                    throw SceneLoadError(message: "SceneLoader no_interpolation is \(text)")
                }
            }
            if let text = attributes["no_interpolation_frames"] {
                guard let count = Int(text) else {
                    throw SceneLoadError(message: "SceneLoader no_interpolation_frames is \(text)")
                }
                noInterpolationFrames = count
            }
            if let text = attributes["pivot_points"], !text.isEmpty {
                speedModifier = try SpeedModifier.decode(text)
            }
        }

        private mutating func startFrame(from start: UnsafePointer<UInt8>, to gt: UnsafePointer<UInt8>) throws {
            let attributes = Self.parseAttributes(from: start, to: gt)
            guard let idText = attributes["id"], let id = Int(idText) else {
                throw SceneLoadError(message: "SceneLoader frame missing id")
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
                _ = try HexRGB.parseThrowing(bgName)
            }
            frameId = id
            frameBgName = bgName
            if let bgMoveText = attributes["bg"], !bgMoveText.isEmpty {
                frameBgMove = try PictureMove.parse(bgMoveText)
            } else {
                frameBgMove = .identity
            }
            if let cameraText = attributes["camera"], !cameraText.isEmpty {
                frameCameraMove = try PictureMove.parse(cameraText)
            } else {
                frameCameraMove = .identity
            }
            frameUnits.removeAll(keepingCapacity: true)
        }

        private mutating func startUnit(from start: UnsafePointer<UInt8>, to gt: UnsafePointer<UInt8>) throws {
            var rawName: String?
            var scaleVal: Double?
            var alphaVal: Double?
            var arrangeVal: Int?
            var flippedVal = false
            var stateVal = 0
            var typeSlice: (UnsafePointer<UInt8>, Int)?
            var metaStr: String?

            var p = start
            while p < gt {
                while p < gt && p[0] <= 32 { p += 1 }
                if p >= gt || p[0] == 47 { break }
                let nameStart = p
                guard let eqRaw = memchr(p, 61, gt - p) else { break }
                let eq = UnsafePointer(eqRaw.assumingMemoryBound(to: UInt8.self))
                var nameEnd = eq
                while nameEnd > nameStart && (nameEnd - 1)[0] <= 32 { nameEnd -= 1 }
                let nameLen = nameEnd - nameStart
                var valP = eq + 1
                while valP < gt && valP[0] <= 32 { valP += 1 }
                if valP >= gt { break }
                let quote = valP[0]
                guard quote == 34 || quote == 39 else { break }
                let valStart = valP + 1
                guard let qEndRaw = memchr(valStart, Int32(quote), gt - valStart) else { break }
                let valEnd = UnsafePointer(qEndRaw.assumingMemoryBound(to: UInt8.self))
                p = valEnd + 1
                let valLen = valEnd - valStart

                switch nameLen {
                case 4:
                    if nameStart[0] == 110 && nameStart[1] == 97 && nameStart[2] == 109 && nameStart[3] == 101 { // name
                        rawName = Self.unescapeXML(valStart, valLen)
                    } else if nameStart[0] == 116 && nameStart[1] == 121 && nameStart[2] == 112 && nameStart[3] == 101 { // type
                        typeSlice = (valStart, valLen)
                    } else if nameStart[0] == 109 && nameStart[1] == 101 && nameStart[2] == 116 && nameStart[3] == 97 { // meta
                        metaStr = Self.unescapeXML(valStart, valLen)
                    }
                case 5:
                    if nameStart[0] == 115 && nameStart[1] == 99 && nameStart[2] == 97 && nameStart[3] == 108 && nameStart[4] == 101 { // scale
                        scaleVal = Self.parseDouble(valStart, valEnd)
                    } else if nameStart[0] == 97 && nameStart[1] == 108 && nameStart[2] == 112 && nameStart[3] == 104 && nameStart[4] == 97 { // alpha
                        alphaVal = Self.parseDouble(valStart, valEnd)
                    } else if nameStart[0] == 115 && nameStart[1] == 116 && nameStart[2] == 97 && nameStart[3] == 116 && nameStart[4] == 101 { // state
                        guard let st = Self.parseInt(valStart, valEnd) else {
                            let text = Self.unescapeXML(valStart, valLen)
                            throw SceneLoadError(message: "SceneLoader unit '\(rawName ?? "")' state '\(text)' is not an int")
                        }
                        stateVal = st
                    }
                case 7:
                    if nameStart[0] == 97 && nameStart[1] == 114 && nameStart[2] == 114 && nameStart[3] == 97 && nameStart[4] == 110 && nameStart[5] == 103 && nameStart[6] == 101 { // arrange
                        arrangeVal = Self.parseInt(valStart, valEnd)
                    } else if nameStart[0] == 102 && nameStart[1] == 108 && nameStart[2] == 105 && nameStart[3] == 112 && nameStart[4] == 112 && nameStart[5] == 101 && nameStart[6] == 100 { // flipped
                        flippedVal = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    }
                default:
                    break
                }
            }

            guard let name = rawName, !name.isEmpty else {
                throw SceneLoadError(message: "SceneLoader unit missing name")
            }
            guard let scale = scaleVal else {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' missing scale")
            }
            if scale <= 0 {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' scale is \(scale)")
            }
            guard let alpha = alphaVal else {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' missing alpha")
            }
            if alpha < 0 {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' alpha is \(alpha)")
            }
            guard let arrange = arrangeVal else {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' missing arrange")
            }
            unitName = try resolveCached(name)
            unitScale = CGFloat(scale)
            unitAlpha = CGFloat(alpha)
            unitArrange = arrange
            unitFlipped = flippedVal
            unitState = stateVal

            if let (ts, tl) = typeSlice, tl > 0 {
                if tl == 4 && ts[0] == 117 && ts[1] == 110 && ts[2] == 105 && ts[3] == 116 {
                    unitType = .unit
                    unitBubble = nil
                } else if tl == 6 && ts[0] == 98 && ts[1] == 117 && ts[2] == 98 && ts[3] == 98 && ts[4] == 108 && ts[5] == 101 {
                    unitType = .bubble
                    if let meta = metaStr, !meta.isEmpty {
                        unitBubble = try BubbleMeta.parse(encoded: meta, unitName: name)
                    } else {
                        unitBubble = .defaults
                    }
                } else {
                    let other = Self.unescapeXML(ts, tl)
                    throw SceneLoadError(message: "SceneLoader unit '\(name)' unknown type '\(other)'")
                }
            } else {
                unitType = .unit
                unitBubble = nil
            }
            unitPoints.removeAll(keepingCapacity: true)
        }

        private mutating func parsePointFast(from start: UnsafePointer<UInt8>, to gt: UnsafePointer<UInt8>) throws -> StickmanPoint {
            var idOpt: Int?
            var xOpt: Double?
            var yOpt: Double?
            var isBase = false
            var parOpt: Int?
            var attachable: Attachable = .none
            var attachedSlice: (UnsafePointer<UInt8>, Int)?
            var semanticName: String?
            var fixed = false
            var stretchable = false
            var kinStart = false
            var kinStop = false

            var p = start
            while p < gt {
                while p < gt && p[0] <= 32 { p += 1 }
                if p >= gt || p[0] == 47 { break }
                let nameStart = p
                guard let eqRaw = memchr(p, 61, gt - p) else { break }
                let eq = UnsafePointer(eqRaw.assumingMemoryBound(to: UInt8.self))
                var nameEnd = eq
                while nameEnd > nameStart && (nameEnd - 1)[0] <= 32 { nameEnd -= 1 }
                let nameLen = nameEnd - nameStart
                var valP = eq + 1
                while valP < gt && valP[0] <= 32 { valP += 1 }
                if valP >= gt { break }
                let quote = valP[0]
                guard quote == 34 || quote == 39 else { break }
                let valStart = valP + 1
                guard let qEndRaw = memchr(valStart, Int32(quote), gt - valStart) else { break }
                let valEnd = UnsafePointer(qEndRaw.assumingMemoryBound(to: UInt8.self))
                p = valEnd + 1
                let valLen = valEnd - valStart

                switch nameLen {
                case 1:
                    if nameStart[0] == 120 { // x
                        xOpt = Self.parseDouble(valStart, valEnd)
                    } else if nameStart[0] == 121 { // y
                        yOpt = Self.parseDouble(valStart, valEnd)
                    }
                case 2:
                    if nameStart[0] == 105 && nameStart[1] == 100 { // id
                        idOpt = Self.parseInt(valStart, valEnd)
                    }
                case 3:
                    if nameStart[0] == 112 && nameStart[1] == 97 && nameStart[2] == 114 { // par
                        parOpt = Self.parseInt(valStart, valEnd)
                    }
                case 4:
                    if nameStart[0] == 98 && nameStart[1] == 97 && nameStart[2] == 115 && nameStart[3] == 101 { // base
                        isBase = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    } else if nameStart[0] == 110 && nameStart[1] == 97 && nameStart[2] == 109 && nameStart[3] == 101 { // name
                        if valLen > 0 {
                            semanticName = Self.unescapeXML(valStart, valLen)
                        }
                    }
                case 5:
                    if nameStart[0] == 102 && nameStart[1] == 105 && nameStart[2] == 120 && nameStart[3] == 101 && nameStart[4] == 100 { // fixed
                        fixed = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    }
                case 7:
                    if nameStart[0] == 107 && nameStart[1] == 105 && nameStart[2] == 110 && nameStart[3] == 115 && nameStart[4] == 116 && nameStart[5] == 111 && nameStart[6] == 112 { // kinstop
                        kinStop = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    }
                case 8:
                    if nameStart[0] == 97 && nameStart[1] == 116 && nameStart[2] == 116 && nameStart[3] == 97 && nameStart[4] == 99 && nameStart[5] == 104 && nameStart[6] == 101 && nameStart[7] == 100 { // attached
                        if valLen > 0 {
                            attachedSlice = (valStart, valLen)
                        }
                    } else if nameStart[0] == 107 && nameStart[1] == 105 && nameStart[2] == 110 && nameStart[3] == 115 && nameStart[4] == 116 && nameStart[5] == 97 && nameStart[6] == 114 && nameStart[7] == 116 { // kinstart
                        kinStart = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    }
                case 10:
                    if nameStart[0] == 97 && nameStart[1] == 116 && nameStart[2] == 116 && nameStart[3] == 97 && nameStart[4] == 99 && nameStart[5] == 104 && nameStart[6] == 97 && nameStart[7] == 98 && nameStart[8] == 108 && nameStart[9] == 101 { // attachable
                        if valLen == 6 && valStart[0] == 109 && valStart[1] == 97 && valStart[2] == 115 && valStart[3] == 116 && valStart[4] == 101 && valStart[5] == 114 {
                            attachable = .master
                        } else if valLen == 5 && valStart[0] == 115 && valStart[1] == 108 && valStart[2] == 97 && valStart[3] == 118 && valStart[4] == 101 {
                            attachable = .slave
                        } else {
                            let other = Self.unescapeXML(valStart, valLen)
                            throw SceneLoadError(message: "SceneLoader point \(idOpt ?? -1) unknown attachable '\(other)'")
                        }
                    }
                case 11:
                    if nameStart[0] == 115 && nameStart[1] == 116 && nameStart[2] == 114 && nameStart[3] == 101 && nameStart[4] == 116 && nameStart[5] == 99 && nameStart[6] == 104 && nameStart[7] == 97 && nameStart[8] == 98 && nameStart[9] == 108 && nameStart[10] == 101 { // stretchable
                        stretchable = (valLen == 4 && valStart[0] == 116 && valStart[1] == 114 && valStart[2] == 117 && valStart[3] == 101)
                    }
                default:
                    break
                }
            }

            guard let id = idOpt else {
                throw SceneLoadError(message: "SceneLoader point missing id")
            }
            guard let x = xOpt else {
                throw SceneLoadError(message: "SceneLoader point \(id) missing x")
            }
            guard let y = yOpt else {
                throw SceneLoadError(message: "SceneLoader point \(id) missing y")
            }
            let parentId: Int?
            if isBase {
                parentId = nil
            } else {
                guard let par = parOpt else {
                    throw SceneLoadError(message: "SceneLoader point \(id) missing par")
                }
                parentId = par
            }
            var attachedName: String?
            var attachedId: Int?
            if let (attStart, attLen) = attachedSlice {
                let attached = Self.unescapeXML(attStart, attLen)
                let parts = attached.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
                if parts.count != 2 {
                    throw SceneLoadError(message: "SceneLoader point \(id) attached '\(attached)' is not name&id")
                }
                guard let masterId = Int(parts[1]) else {
                    throw SceneLoadError(message: "SceneLoader point \(id) attached id '\(parts[1])' is not an int")
                }
                if masterId != -1 && parts[0] != "null" && !parts[0].isEmpty {
                    attachedName = try resolveCached(parts[0])
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
                attachedMasterPointId: attachedId,
                semanticName: semanticName,
                fixed: fixed,
                stretchable: !isBase && stretchable,
                kinematicStart: kinStart,
                kinematicStop: kinStop
            )
        }

        private mutating func endUnit() throws {
            guard let name = unitName, let scale = unitScale, let alpha = unitAlpha, let arrange = unitArrange else {
                throw SceneLoadError(message: "SceneLoader unit ended without name/scale/alpha/arrange")
            }
            if unitPoints.isEmpty {
                throw SceneLoadError(message: "SceneLoader unit '\(name)' has no points")
            }
            let deduped = try uniquePoints(unitPoints, unitName: name)
            var unit = StickmanUnit(
                name: name,
                points: deduped,
                edges: [],
                scale: scale,
                alpha: alpha,
                arrange: arrange,
                flipped: unitFlipped,
                assetsState: unitState,
                unitType: unitType,
                bubble: unitBubble
            )
            if let cached = linkedEdgesCache[name], cached.sig.count == deduped.count {
                var matches = true
                for i in 0..<deduped.count {
                    let s = cached.sig[i]
                    let p = deduped[i]
                    if s.id != p.id || s.parentId != p.parentId || s.isBase != p.isBase {
                        matches = false
                        break
                    }
                }
                if matches {
                    unit.edges = cached.edges
                } else {
                    try unit.link()
                    linkedEdgesCache[name] = (deduped.map { ($0.id, $0.parentId, $0.isBase) }, unit.edges)
                }
            } else {
                try unit.link()
                linkedEdgesCache[name] = (deduped.map { ($0.id, $0.parentId, $0.isBase) }, unit.edges)
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
            unitPoints.removeAll(keepingCapacity: true)
        }

        private mutating func endFrame() throws {
            guard let id = frameId, let bgName = frameBgName else {
                throw SceneLoadError(message: "SceneLoader frame ended without id/bg_name")
            }
            if frameUnits.isEmpty {
                throw SceneLoadError(message: "SceneLoader frame \(id) has no units")
            }
            var frame = StickmanFrame(
                id: id,
                units: frameUnits,
                bgName: bgName,
                bgMove: frameBgMove,
                cameraMove: frameCameraMove
            )
            try frame.slaves.populate(units: frame.units)
            frames.append(frame)
            frameId = nil
            frameBgName = nil
            frameBgMove = .identity
            frameCameraMove = .identity
            frameUnits.removeAll(keepingCapacity: true)
        }

        private func uniquePoints(_ points: [StickmanPoint], unitName: String) throws -> [StickmanPoint] {
            var mask: UInt64 = 0
            var allDistinctIn64 = true
            for point in points {
                let id = point.id
                if id >= 0 && id < 64 {
                    let bit: UInt64 = 1 << UInt64(id)
                    if (mask & bit) != 0 {
                        allDistinctIn64 = false
                        break
                    }
                    mask |= bit
                } else {
                    allDistinctIn64 = false
                    break
                }
            }
            if allDistinctIn64 {
                return points
            }
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
                        throw SceneLoadError(message: "SceneLoader unit '\(unitName)' duplicate point \(point.id) disagrees")
                    }
                    continue
                }
                byId[point.id] = point
                order.append(point.id)
            }
            return order.map { byId[$0]! }
        }
    }
}
