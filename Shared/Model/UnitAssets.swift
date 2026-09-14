import CoreGraphics
import Foundation

final class UnitAssets {
    static let stateDefault = 0

    struct EdgeKey: Hashable {
        var unitName = ""
        var start = -1
        var end = -1
        var flipped = false
        var faceId = -1

        func hash(into hasher: inout Hasher) {
            hasher.combine(unitName)
            hasher.combine(min(start, end))
            hasher.combine(max(start, end))
            hasher.combine(faceId)
            hasher.combine(flipped)
        }

        static func == (lhs: EdgeKey, rhs: EdgeKey) -> Bool {
            let sameEnds = (lhs.start == rhs.start && lhs.end == rhs.end)
                || (lhs.end == rhs.start && lhs.start == rhs.end)
            return sameEnds
                && lhs.unitName == rhs.unitName
                && lhs.faceId == rhs.faceId
                && lhs.flipped == rhs.flipped
        }
    }

    struct EdgeAsset {
        var unitName: String
        var start: Int
        var end: Int
        var xOffset: CGFloat
        var yOffset: CGFloat
        var weight: Int
        var state: Int
        var nativeFlipped: Bool
        var bmName: String
        var bitmap: CGImage
    }

    private var edgeAssets: [EdgeKey: [Int: EdgeAsset]] = [:]
    private var restModel: [String: [Int: CGFloat]] = [:]
    private var archives: [String: StoredArchive] = [:]

    struct StoredArchive {
        var entryName: String
        var zip: Data
    }

    func hasAssetsFor(unitName: String) -> Bool {
        edgeAssets.keys.contains { $0.unitName == unitName }
    }

    func loadItemFromArchive(_ zip: Data, entryName: String, forceReload: Bool = true) {
        if entryName.isEmpty {
            fatalError("UnitAssets empty archive entry name")
        }
        let model = ModelXML.parse(ZipStore.data(named: "model.xml", in: zip))
        let key = Self.removeNumber(model.name)
        if archives[key] == nil {
            archives[key] = StoredArchive(entryName: entryName, zip: zip)
        }
        if !forceReload && hasAssetsFor(unitName: model.name) {
            return
        }
        let xml = ZipStore.data(named: "assets.xml", in: zip)
        let parsed = AssetsXML.parse(xml)
        install(parsed, zip: zip)
        captureRest(from: model)
    }

    func archive(for unitName: String) -> StoredArchive {
        let key = Self.removeNumber(unitName)
        guard let stored = archives[key] else {
            fatalError("UnitAssets missing archive for '\(key)'")
        }
        return stored
    }

    static func atiEntryName(packName: String, systemName: String) -> String {
        if systemName.isEmpty {
            fatalError("UnitAssets empty systemName")
        }
        if packName == "@" {
            return systemName + ".ati"
        }
        if packName.isEmpty {
            fatalError("UnitAssets empty packName for '\(systemName)'")
        }
        return "\(packName)/items/\(systemName).ati"
    }

    static func atiEntryName(for unitName: String) -> String {
        let name = removeNumber(unitName)
        guard let colon = name.firstIndex(of: ":") else {
            return name + ".ati"
        }
        let pack = String(name[..<colon])
        let own = String(name[name.index(after: colon)...])
        if own.isEmpty {
            fatalError("UnitAssets unit name '\(unitName)' has empty own name")
        }
        return atiEntryName(packName: pack, systemName: own)
    }

    func getDrawable(_ key: EdgeKey, state: Int) -> EdgeAsset? {
        var states = edgeStates(key)
        if states.isEmpty {
            var unflipped = key
            unflipped.flipped = false
            states = edgeStates(unflipped)
        }
        return states[state] ?? states[Self.stateDefault]
    }

    func getEdgeWeight(unitName: String, startId: Int, endId: Int, state: Int, flipped: Bool) -> Int {
        let key = EdgeKey(unitName: unitName, start: startId, end: endId, flipped: flipped)
        return getDrawable(key, state: state)?.weight ?? -1
    }

    func restLength(unitName: String, endId: Int) -> CGFloat {
        restModel[unitName]?[endId] ?? 0
    }

    func states(for fullname: String) -> [Int] {
        let name = Self.removeNumber(fullname)
        var numbers = Set<Int>()
        for (key, states) in edgeAssets where key.unitName == name {
            numbers.formUnion(states.keys)
        }
        return numbers.sorted()
    }

    func multiframedAssets() -> Set<String> {
        Set(edgeAssets.compactMap { $0.value.count > 1 ? $0.key.unitName : nil })
    }

    static func removeNumber(_ name: String) -> String {
        guard let hash = name.firstIndex(of: "#") else { return name }
        return String(name[..<hash])
    }

    private func install(_ rows: [EdgeAssetRow], zip: Data) {
        let names = Set(ZipStore.names(in: zip))
        var bitmaps: [String: CGImage] = [:]
        func bitmap(named name: String) -> CGImage {
            if let cached = bitmaps[name] { return cached }
            let image = PNG.image(from: ZipStore.data(named: name, in: zip), name: name)
            bitmaps[name] = image
            return image
        }

        var assets: [EdgeAsset] = []
        for row in rows {
            if !names.contains(row.bmName) {
                continue
            }
            assets.append(
                EdgeAsset(
                    unitName: row.unitName,
                    start: row.start,
                    end: row.end,
                    xOffset: row.xOffset,
                    yOffset: row.yOffset,
                    weight: row.weight,
                    state: row.state,
                    nativeFlipped: row.nativeFlipped,
                    bmName: row.bmName,
                    bitmap: bitmap(named: row.bmName)
                )
            )
        }
        if assets.isEmpty {
            fatalError("UnitAssets zip has no packed bitmaps for \(rows.map(\.bmName))")
        }

        for asset in assets {
            let key = EdgeKey(
                unitName: asset.unitName,
                start: asset.start,
                end: asset.end,
                flipped: asset.nativeFlipped
            )
            edgeAssets[key] = [:]
        }
        for asset in assets {
            let key = EdgeKey(
                unitName: asset.unitName,
                start: asset.start,
                end: asset.end,
                flipped: asset.nativeFlipped
            )
            var states = edgeAssets[key] ?? [:]
            states[asset.state] = asset
            edgeAssets[key] = states
        }
    }

    private func captureRest(from model: StickmanUnit) {
        var lengths: [Int: CGFloat] = [:]
        for point in model.points {
            if point.isBase { continue }
            guard let parentId = point.parentId else { continue }
            let parent = model.point(id: parentId)
            let rest = hypot(point.x - parent.x, point.y - parent.y)
            if rest > 0 {
                lengths[point.id] = rest
            }
        }
        restModel[Self.removeNumber(model.name)] = lengths
    }

    private func edgeStates(_ key: EdgeKey) -> [Int: EdgeAsset] {
        if let existing = edgeAssets[key] {
            return existing
        }
        let empty: [Int: EdgeAsset] = [:]
        edgeAssets[key] = empty
        return empty
    }
}

struct EdgeAssetRow {
    var unitName: String
    var start: Int
    var end: Int
    var xOffset: CGFloat
    var yOffset: CGFloat
    var weight: Int
    var state: Int
    var nativeFlipped: Bool
    var bmName: String
    var svgName: String?
    var commandScale: String?
}

private enum PNG {
    static func image(from data: Data, name: String) -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData) else {
            fatalError("UnitAssets '\(name)' has no data provider")
        }
        guard let image = CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            fatalError("UnitAssets '\(name)' is not a PNG")
        }
        return image
    }
}

enum AssetsXML {
    static func serialize(rows: [EdgeAssetRow], fullName: String) -> Data {
        if fullName.isEmpty {
            fatalError("AssetsXML serialize has empty unit name")
        }
        if rows.isEmpty {
            fatalError("AssetsXML serialize '\(fullName)' has no rows")
        }
        var xml = XMLWrite.header
        xml += "<unit"
        xml += XMLWrite.attr("name", fullName)
        xml += XMLWrite.attr("version", XMLWrite.versionCode())
        xml += ">\n"
        for row in rows {
            xml += "<edgeAsset"
            xml += XMLWrite.attr("start", "\(row.start)")
            xml += XMLWrite.attr("end", "\(row.end)")
            xml += XMLWrite.attr("weight", "\(row.weight)")
            xml += XMLWrite.attr("x_offset", XMLWrite.float(row.xOffset))
            xml += XMLWrite.attr("y_offset", XMLWrite.float(row.yOffset))
            xml += XMLWrite.attr("state", "\(row.state)")
            xml += XMLWrite.attr("bm", row.bmName)
            if row.nativeFlipped {
                xml += XMLWrite.attr("flipped", "true")
            }
            if let scale = row.commandScale {
                xml += XMLWrite.attr("command_scale", scale)
            }
            if let svg = row.svgName {
                xml += XMLWrite.attr("svg", svg)
            }
            xml += " />\n"
        }
        xml += "</unit>\n"
        return XMLWrite.data(xml)
    }

    static func parse(_ data: Data) -> [EdgeAssetRow] {
        let parser = XMLParser(data: data)
        let sink = Sink()
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            fatalError("UnitAssets assets.xml parse failed: \(detail)")
        }
        if sink.assets.isEmpty {
            fatalError("UnitAssets assets.xml has no edgeAsset rows")
        }
        return sink.assets
    }

    private final class Sink: NSObject, XMLParserDelegate {
        var unitName: String?
        var assets: [EdgeAssetRow] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            if elementName == "unit" {
                unitName = attributes["name"]
                return
            }
            if elementName != "edgeAsset" { return }
            guard let name = unitName else {
                fatalError("UnitAssets edgeAsset outside unit")
            }
            guard let startText = attributes["start"], let start = Int(startText) else {
                fatalError("UnitAssets edgeAsset missing start")
            }
            guard let endText = attributes["end"], let end = Int(endText) else {
                fatalError("UnitAssets edgeAsset missing end")
            }
            guard let xText = attributes["x_offset"], let x = Double(xText) else {
                fatalError("UnitAssets edgeAsset \(start)-\(end) missing x_offset")
            }
            guard let yText = attributes["y_offset"], let y = Double(yText) else {
                fatalError("UnitAssets edgeAsset \(start)-\(end) missing y_offset")
            }
            guard let bm = attributes["bm"], !bm.isEmpty else {
                fatalError("UnitAssets edgeAsset \(start)-\(end) missing bm")
            }
            assets.append(
                EdgeAssetRow(
                    unitName: name,
                    start: start,
                    end: end,
                    xOffset: CGFloat(x),
                    yOffset: CGFloat(y),
                    weight: Int(attributes["weight"] ?? "") ?? 0,
                    state: Int(attributes["state"] ?? "") ?? UnitAssets.stateDefault,
                    nativeFlipped: attributes["flipped"] == "true",
                    bmName: bm,
                    svgName: attributes["svg"],
                    commandScale: attributes["command_scale"]
                )
            )
        }
    }
}
