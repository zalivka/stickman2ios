import Compression
import CoreGraphics
import Foundation

enum ItemLoader {
    static func archive(resource: String, subdirectory: String) -> Data {
        archive(resource: resource, subdirectory: subdirectory, ext: "ati")
    }

    static func archive(resource: String, subdirectory: String, ext: String) -> Data {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: resource, withExtension: ext)
        else {
            fatalError("ItemLoader missing \(subdirectory)/\(resource).\(ext) (and bundle-root \(resource).\(ext))")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("ItemLoader could not read \(url.path): \(error)")
        }
    }

    static func unit(from zip: Data) -> StickmanUnit {
        var unit = ModelXML.parse(ZipStore.data(named: "model.xml", in: zip))
        unit.link()
        return unit
    }

    static func unit(resource: String, subdirectory: String) -> StickmanUnit {
        unit(from: archive(resource: resource, subdirectory: subdirectory))
    }

    static func load(resource: String, subdirectory: String) -> (StickmanUnit, UnitAssets, CGFloat) {
        let zip = archive(resource: resource, subdirectory: subdirectory)
        let assets = UnitAssets()
        let unit = load(zip: zip, into: assets)
        return (unit, assets, ItemMeta.scale(from: ZipStore.data(named: "meta.txt", in: zip)))
    }

    static func load(zip: Data, into assets: UnitAssets) -> StickmanUnit {
        let unit = unit(from: zip)
        assets.loadItemFromArchive(zip, entryName: UnitAssets.atiEntryName(for: unit.name), forceReload: false)
        if unit.unitType == .bubble {
            if unit.bubble == nil {
                fatalError("ItemLoader '\(unit.name)' bubble missing meta")
            }
            return unit
        }
        let own = UnitAssets.removeNumber(unit.name)
        if !assets.hasAssetsFor(unitName: own) {
            fatalError("ItemLoader assets missing unit '\(unit.name)'")
        }
        return unit
    }

    static func thumb(from zip: Data, name: String) -> CGImage {
        if !ZipStore.contains("thumb.png", in: zip) {
            fatalError("ItemLoader '\(name)' missing thumb.png")
        }
        return PNGImage.cgImage(from: ZipStore.data(named: "thumb.png", in: zip), name: "\(name)/thumb.png")
    }
}

enum PNGImage {
    static func cgImage(from data: Data, name: String) -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData) else {
            fatalError("PNGImage '\(name)' has no data provider")
        }
        guard let image = CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            fatalError("PNGImage '\(name)' is not a PNG")
        }
        return image
    }
}

enum ItemMeta {
    static func scale(from data: Data) -> CGFloat {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("ItemLoader meta.txt is not JSON")
        }
        guard let number = object["scale"] as? NSNumber else {
            fatalError("ItemLoader meta.txt missing scale")
        }
        let scale = CGFloat(truncating: number)
        if scale <= 0 {
            fatalError("ItemLoader meta.txt scale is \(scale)")
        }
        return scale
    }
}

enum ZipStore {
    static let store: UInt16 = 0
    static let deflate: UInt16 = 8

    static func names(in zip: Data) -> [String] {
        entries(in: zip).map(\.name)
    }

    static func contains(_ name: String, in zip: Data) -> Bool {
        names(in: zip).contains(name)
    }

    static func data(named name: String, in zip: Data) -> Data {
        for entry in entries(in: zip) where entry.name == name {
            return payload(
                zip: zip,
                localOffset: entry.localOffset,
                method: entry.method,
                compressed: entry.compressed,
                uncompressed: entry.uncompressed
            )
        }
        fatalError("ItemLoader zip missing '\(name)'")
    }

    static func data(atiNamed file: String, in zip: Data) -> Data {
        let matches = entries(in: zip).filter { ($0.name as NSString).lastPathComponent == file }
        if matches.isEmpty {
            fatalError("ItemLoader zip missing '\(file)'")
        }
        let entry = matches.first(where: { $0.name == "items/\(file)" }) ?? matches[0]
        return payload(
            zip: zip,
            localOffset: entry.localOffset,
            method: entry.method,
            compressed: entry.compressed,
            uncompressed: entry.uncompressed
        )
    }

    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        if files.isEmpty {
            fatalError("ZipStore archive has no files")
        }
        var seen = Set<String>()
        var locals = Data()
        var central = Data()
        var count: UInt16 = 0
        for file in files {
            let name = file.name
            let payload = file.data
            if name.isEmpty || name.hasPrefix("/") || name.hasSuffix("/") {
                fatalError("ZipStore refuses entry '\(name)'")
            }
            if name.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                fatalError("ZipStore refuses entry '\(name)'")
            }
            if seen.contains(name) {
                fatalError("ZipStore duplicate entry '\(name)'")
            }
            seen.insert(name)
            guard let nameData = name.data(using: .utf8) else {
                fatalError("ZipStore entry '\(name)' is not UTF-8")
            }
            if nameData.count > 0xFFFF {
                fatalError("ZipStore entry '\(name)' name is \(nameData.count) bytes")
            }
            if payload.count > Int(UInt32.max) {
                fatalError("ZipStore entry '\(name)' is \(payload.count) bytes")
            }
            let crc = CRC32.hash(payload)
            let size = UInt32(payload.count)
            let localOffset = UInt32(locals.count)
            locals.appendU32(0x0403_4b50)
            locals.appendU16(20)
            locals.appendU16(0)
            locals.appendU16(store)
            locals.appendU16(0)
            locals.appendU16(0)
            locals.appendU32(crc)
            locals.appendU32(size)
            locals.appendU32(size)
            locals.appendU16(UInt16(nameData.count))
            locals.appendU16(0)
            locals.append(nameData)
            locals.append(payload)

            central.appendU32(0x0201_4b50)
            central.appendU16(20)
            central.appendU16(20)
            central.appendU16(0)
            central.appendU16(store)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(crc)
            central.appendU32(size)
            central.appendU32(size)
            central.appendU16(UInt16(nameData.count))
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(0)
            central.appendU32(localOffset)
            central.append(nameData)
            if count == UInt16.max {
                fatalError("ZipStore archive exceeds \(UInt16.max) entries")
            }
            count += 1
        }
        let cdOffset = UInt32(locals.count)
        let cdSize = UInt32(central.count)
        var out = locals
        out.append(central)
        out.appendU32(0x0605_4b50)
        out.appendU16(0)
        out.appendU16(0)
        out.appendU16(count)
        out.appendU16(count)
        out.appendU32(cdSize)
        out.appendU32(cdOffset)
        out.appendU16(0)
        return out
    }

    static func unpack(_ zip: Data, to directory: URL) {
        let fm = FileManager.default
        let tmp = directory.appendingPathExtension("unpacking")
        if fm.fileExists(atPath: tmp.path) {
            do {
                try fm.removeItem(at: tmp)
            } catch {
                fatalError("ZipStore could not replace \(tmp.path): \(error)")
            }
        }
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            fatalError("ZipStore could not create \(tmp.path): \(error)")
        }
        for name in names(in: zip) {
            if name.hasSuffix("/") { continue }
            if name.hasPrefix("/") || name.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                fatalError("ZipStore refuses entry '\(name)'")
            }
            let dest = tmp.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data(named: name, in: zip).write(to: dest, options: .atomic)
            } catch {
                fatalError("ZipStore could not write \(dest.path): \(error)")
            }
        }
        if fm.fileExists(atPath: directory.path) {
            do {
                try fm.removeItem(at: directory)
            } catch {
                fatalError("ZipStore could not replace \(directory.path): \(error)")
            }
        }
        do {
            try fm.moveItem(at: tmp, to: directory)
        } catch {
            fatalError("ZipStore could not move \(tmp.path) to \(directory.path): \(error)")
        }
    }

    private struct Entry {
        var name: String
        var method: UInt16
        var compressed: Int
        var uncompressed: Int
        var localOffset: Int
    }

    private static func entries(in zip: Data) -> [Entry] {
        guard let eocd = eocdOffset(in: zip) else {
            fatalError("ItemLoader zip has no EOCD")
        }
        let cdOffset = Int(zip.u32(eocd + 16))
        let cdEntries = Int(zip.u16(eocd + 10))
        if cdOffset < 0 || cdOffset >= zip.count || cdEntries <= 0 {
            fatalError("ItemLoader zip central directory invalid")
        }
        var cursor = cdOffset
        var result: [Entry] = []
        for _ in 0..<cdEntries {
            if zip.u32(cursor) != 0x02014b50 {
                fatalError("ItemLoader zip central directory signature missing")
            }
            let method = zip.u16(cursor + 10)
            let compressed = Int(zip.u32(cursor + 20))
            let uncompressed = Int(zip.u32(cursor + 24))
            let nameLen = Int(zip.u16(cursor + 28))
            let extraLen = Int(zip.u16(cursor + 30))
            let commentLen = Int(zip.u16(cursor + 32))
            let localOff = Int(zip.u32(cursor + 42))
            let entryName = zip.string(cursor + 46, nameLen)
            cursor += 46 + nameLen + extraLen + commentLen
            result.append(
                Entry(
                    name: entryName,
                    method: method,
                    compressed: compressed,
                    uncompressed: uncompressed,
                    localOffset: localOff
                )
            )
        }
        return result
    }

    private static func payload(
        zip: Data,
        localOffset: Int,
        method: UInt16,
        compressed: Int,
        uncompressed: Int
    ) -> Data {
        if zip.u32(localOffset) != 0x04034b50 {
            fatalError("ItemLoader zip local header signature missing")
        }
        let nameLen = Int(zip.u16(localOffset + 26))
        let extraLen = Int(zip.u16(localOffset + 28))
        let dataStart = localOffset + 30 + nameLen + extraLen
        let dataEnd = dataStart + compressed
        if dataStart < 0 || dataEnd > zip.count {
            fatalError("ItemLoader zip entry data out of range")
        }
        let packed = zip.subdata(in: dataStart..<dataEnd)
        switch method {
        case store:
            if packed.count != uncompressed {
                fatalError("ItemLoader stored entry size \(packed.count) != \(uncompressed)")
            }
            return packed
        case deflate:
            return inflate(packed, uncompressedSize: uncompressed)
        default:
            fatalError("ItemLoader zip method \(method) is not STORE or DEFLATE")
        }
    }

    private static func eocdOffset(in zip: Data) -> Int? {
        if zip.count < 22 { return nil }
        let minStart = max(0, zip.count - 22 - 0xFFFF)
        var i = zip.count - 22
        while i >= minStart {
            if zip.u32(i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func inflate(_ packed: Data, uncompressedSize: Int) -> Data {
        if uncompressedSize <= 0 {
            fatalError("ItemLoader deflate uncompressed size \(uncompressedSize)")
        }
        var dest = [UInt8](repeating: 0, count: uncompressedSize)
        let written = packed.withUnsafeBytes { src -> Int in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return dest.withUnsafeMutableBytes { dst in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase,
                    uncompressedSize,
                    srcBase,
                    packed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        if written != uncompressedSize {
            fatalError("ItemLoader deflate wrote \(written) expected \(uncompressedSize)")
        }
        return Data(dest)
    }
}

private enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB8_8320 ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            return c
        }
    }()

    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

enum ModelXML {
    static func parse(_ data: Data) -> StickmanUnit {
        let parser = XMLParser(data: data)
        let sink = Sink()
        parser.delegate = sink
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            fatalError("ItemLoader model.xml parse failed: \(detail)")
        }
        guard let name = sink.unitName, !sink.points.isEmpty else {
            fatalError("ItemLoader model.xml has no unit name or points")
        }
        if sink.unitType == .bubble, sink.bubble == nil {
            fatalError("ItemLoader unit '\(name)' bubble missing meta")
        }
        return StickmanUnit(
            name: name,
            points: sink.points,
            edges: [],
            unitType: sink.unitType,
            bubble: sink.bubble
        )
    }

    /// Writes the item format: base point at the origin, in native unscaled item units.
    static func serialize(_ unit: StickmanUnit, fullName: String) -> Data {
        if fullName.isEmpty {
            fatalError("ModelXML serialize has empty unit name")
        }
        if unit.scale <= 0 {
            fatalError("ModelXML serialize unit '\(unit.name)' scale is \(unit.scale)")
        }
        let base = unit.basePoint()
        var xml = XMLWrite.header
        xml += "<unit"
        xml += XMLWrite.attr("name", fullName)
        xml += ">\n"
        for point in unit.points {
            xml += serialize(point, base: base, scale: unit.scale, unitName: unit.name)
        }
        xml += "</unit>\n"
        return XMLWrite.data(xml)
    }

    private static func serialize(
        _ point: StickmanPoint,
        base: StickmanPoint,
        scale: CGFloat,
        unitName: String
    ) -> String {
        var xml = "<point"
        xml += XMLWrite.attr("id", "\(point.id)")
        xml += XMLWrite.attr("x", XMLWrite.float((point.x - base.x) / scale))
        xml += XMLWrite.attr("y", XMLWrite.float((point.y - base.y) / scale))
        if point.isBase {
            xml += XMLWrite.attr("base", "true")
        } else {
            guard let parentId = point.parentId else {
                fatalError("ModelXML unit '\(unitName)' point \(point.id) missing par")
            }
            xml += XMLWrite.attr("par", "\(parentId)")
        }
        if point.fixed {
            xml += XMLWrite.attr("fixed", "true")
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
        if let name = point.semanticName {
            xml += XMLWrite.attr("name", name)
        }
        switch point.attachable {
        case .none: break
        case .master: xml += XMLWrite.attr("attachable", "master")
        case .slave: xml += XMLWrite.attr("attachable", "slave")
        }
        xml += " />\n"
        return xml
    }

    private final class Sink: NSObject, XMLParserDelegate {
        var unitName: String?
        var unitType: StickmanUnitType = .unit
        var bubble: BubbleMeta?
        var points: [StickmanPoint] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            if elementName == "unit" {
                let name = attributes["name"].map(PackAlias.resolveUnitName)
                unitName = name
                switch attributes["type"] {
                case nil, "", "unit":
                    unitType = .unit
                    bubble = nil
                case "bubble":
                    guard let resolved = name, !resolved.isEmpty else {
                        fatalError("ItemLoader bubble unit missing name")
                    }
                    unitType = .bubble
                    if let meta = attributes["meta"], !meta.isEmpty {
                        bubble = BubbleMeta.parse(encoded: meta, unitName: resolved)
                    } else {
                        bubble = .defaults
                    }
                case let other?:
                    fatalError("ItemLoader unit '\(name ?? "")' unknown type '\(other)'")
                }
                return
            }
            if elementName != "point" { return }
            guard let idText = attributes["id"], let id = Int(idText) else {
                fatalError("ItemLoader point missing id")
            }
            guard let xText = attributes["x"], let x = Double(xText) else {
                fatalError("ItemLoader point \(id) missing x")
            }
            guard let yText = attributes["y"], let y = Double(yText) else {
                fatalError("ItemLoader point \(id) missing y")
            }
            let isBase = attributes["base"] == "true"
            let parentId: Int?
            if isBase {
                parentId = nil
            } else {
                guard let parText = attributes["par"], let par = Int(parText) else {
                    fatalError("ItemLoader point \(id) missing par")
                }
                parentId = par
            }
            let attachable: Attachable
            switch attributes["attachable"] {
            case nil: attachable = .none
            case "master": attachable = .master
            case "slave": attachable = .slave
            default: fatalError("ItemLoader point \(id) attachable '\(attributes["attachable"]!)'")
            }
            points.append(
                StickmanPoint(
                    id: id,
                    x: CGFloat(x),
                    y: CGFloat(y),
                    isBase: isBase,
                    parentId: parentId,
                    attachable: attachable,
                    semanticName: attributes["name"],
                    // Android forces the base unstretchable on load.
                    fixed: attributes["fixed"] == "true",
                    stretchable: !isBase && attributes["stretchable"] == "true",
                    kinematicStart: attributes["kinstart"] == "true",
                    kinematicStop: attributes["kinstop"] == "true"
                )
            )
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        require(offset, 2)
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        require(offset, 4)
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func string(_ offset: Int, _ length: Int) -> String {
        require(offset, length)
        guard let s = String(data: subdata(in: offset..<(offset + length)), encoding: .utf8) else {
            fatalError("ItemLoader zip name is not UTF-8")
        }
        return s
    }

    func require(_ offset: Int, _ length: Int) {
        if offset < 0 || length < 0 || offset + length > count {
            fatalError("ItemLoader zip read \(offset)+\(length) out of \(count)")
        }
    }

    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
