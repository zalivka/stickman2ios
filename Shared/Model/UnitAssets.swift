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
        var svgName: String?
        var commandScale: String?
    }

    struct GalleryBone: Identifiable {
        var id: String { bmName }
        var bmName: String
        var thumb: CGImage
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

    /// Android `AssetsOpsImpl.getAssetsBoundingPoints` — bitmap corners in scene space.
    func assetCornerPoints(for unit: StickmanUnit, state: Int) -> [CGPoint] {
        let name = Self.removeNumber(unit.name)
        var corners: [CGPoint] = []
        for edge in unit.edges {
            let key = EdgeKey(unitName: name, start: edge.from, end: edge.to, flipped: unit.flipped)
            guard let asset = getDrawable(key, state: state) else { continue }
            let start = unit.point(id: edge.from)
            let end = unit.point(id: edge.to)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let mirror = unit.flipped && !asset.nativeFlipped
            let scale = unit.scale
            let xOffset = asset.xOffset * scale
            let yOffset = (mirror ? -asset.yOffset : asset.yOffset) * scale
            let yScale = mirror ? -scale : scale
            let width = CGFloat(asset.bitmap.width)
            let height = CGFloat(asset.bitmap.height)
            let locals: [CGPoint] = [
                CGPoint(x: xOffset, y: yOffset),
                CGPoint(x: xOffset + width * scale, y: yOffset),
                CGPoint(x: xOffset + width * scale, y: yOffset + height * yScale),
                CGPoint(x: xOffset, y: yOffset + height * yScale)
            ]
            let cosine = cos(angle)
            let sine = sin(angle)
            for local in locals {
                corners.append(
                    CGPoint(
                        x: start.x + local.x * cosine - local.y * sine,
                        y: start.y + local.x * sine + local.y * cosine
                    )
                )
            }
        }
        return corners
    }

    /// Skeleton joints plus every state's bitmaps — the box the FBF preview must fit.
    func combinedBounds(for unit: StickmanUnit) -> CGRect {
        if unit.points.isEmpty {
            fatalError("UnitAssets combinedBounds '\(unit.name)' has no points")
        }
        var xs = unit.points.map(\.x)
        var ys = unit.points.map(\.y)
        let scan = states(for: unit.name)
        let statesToScan = scan.isEmpty ? [unit.assetsState] : scan
        for state in statesToScan {
            for corner in assetCornerPoints(for: unit, state: state) {
                xs.append(corner.x)
                ys.append(corner.y)
            }
        }
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func getEdgeWeight(unitName: String, startId: Int, endId: Int, state: Int, flipped: Bool) -> Int {
        let key = EdgeKey(unitName: unitName, start: startId, end: endId, flipped: flipped)
        return getDrawable(key, state: state)?.weight ?? -1
    }

    /// Unique bone bitmaps for the gallery rail, ordered by first-seen weight then bmName.
    func galleryBones(unitName: String) -> [GalleryBone] {
        let name = Self.removeNumber(unitName)
        struct Seen {
            var bmName: String
            var thumb: CGImage
            var weight: Int
        }
        var byBm: [String: Seen] = [:]
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if byBm[asset.bmName] != nil { continue }
                byBm[asset.bmName] = Seen(bmName: asset.bmName, thumb: asset.bitmap, weight: asset.weight)
            }
        }
        return byBm.values
            .sorted {
                if $0.weight != $1.weight { return $0.weight < $1.weight }
                return $0.bmName < $1.bmName
            }
            .map { GalleryBone(bmName: $0.bmName, thumb: $0.thumb) }
    }

    func bmName(forEdge start: Int, end: Int, unitName: String) -> String? {
        let name = Self.removeNumber(unitName)
        let key = EdgeKey(unitName: name, start: start, end: end, flipped: false)
        return getDrawable(key, state: Self.stateDefault)?.bmName
    }

    /// Clones art from an existing `bmName` onto a new edge (shared bitmap, Android-style reuse).
    func attachBone(bmName: String, toEdge start: Int, end: Int, unitName: String) {
        if bmName.isEmpty {
            fatalError("UnitAssets attachBone empty bmName")
        }
        let name = Self.removeNumber(unitName)
        guard let template = firstAsset(bmName: bmName, unitName: name) else {
            fatalError("UnitAssets attachBone unknown bm '\(bmName)' for '\(name)'")
        }
        let nextWeight = (edgeAssets
            .filter { $0.key.unitName == name }
            .flatMap { $0.value.values.map(\.weight) }
            .max() ?? -1) + 1
        let key = EdgeKey(
            unitName: name,
            start: start,
            end: end,
            flipped: template.nativeFlipped
        )
        var asset = template
        asset.unitName = name
        asset.start = start
        asset.end = end
        asset.weight = nextWeight
        asset.state = Self.stateDefault
        edgeAssets[key] = [Self.stateDefault: asset]
    }

    /// Live edge rows for save — includes edges attached during this session.
    func exportRows(unitName: String) -> [EdgeAssetRow] {
        let name = Self.removeNumber(unitName)
        var rows: [EdgeAssetRow] = []
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values.sorted(by: { $0.state < $1.state }) {
                rows.append(
                    EdgeAssetRow(
                        unitName: name,
                        start: asset.start,
                        end: asset.end,
                        xOffset: asset.xOffset,
                        yOffset: asset.yOffset,
                        weight: asset.weight,
                        state: asset.state,
                        nativeFlipped: asset.nativeFlipped,
                        bmName: asset.bmName,
                        svgName: asset.svgName,
                        commandScale: asset.commandScale
                    )
                )
            }
        }
        rows.sort {
            if $0.weight != $1.weight { return $0.weight < $1.weight }
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.state < $1.state
        }
        return rows
    }

    private func firstAsset(bmName: String, unitName: String) -> EdgeAsset? {
        for (key, states) in edgeAssets where key.unitName == unitName {
            if let match = states.values.first(where: { $0.bmName == bmName }) {
                return match
            }
        }
        return nil
    }

    /// Swaps draw-order weight of the edge with its neighbor, matching Android `doMoveOrder`.
    @discardableResult
    func moveEdgeOrder(unitName: String, start: Int, end: Int, moveUp: Bool) -> Bool {
        let name = Self.removeNumber(unitName)
        struct Entry {
            var key: EdgeKey
            var weight: Int
        }
        var entries: [Entry] = []
        for (key, states) in edgeAssets where key.unitName == name {
            let weight = states.values.map(\.weight).min() ?? 0
            entries.append(Entry(key: key, weight: weight))
        }
        entries.sort { $0.weight < $1.weight }
        guard let index = entries.firstIndex(where: {
            ($0.key.start == start && $0.key.end == end) || ($0.key.start == end && $0.key.end == start)
        }) else {
            return false
        }
        let swapIndex = moveUp ? index + 1 : index - 1
        if swapIndex < 0 || swapIndex >= entries.count {
            return false
        }
        entries.swapAt(index, swapIndex)
        for (order, entry) in entries.enumerated() {
            guard var states = edgeAssets[entry.key] else { continue }
            for state in states.keys {
                states[state]?.weight = order
            }
            edgeAssets[entry.key] = states
        }
        return true
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
                    bitmap: bitmap(named: row.bmName),
                    svgName: row.svgName,
                    commandScale: row.commandScale
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
