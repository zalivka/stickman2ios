import Compression
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
        let unit = unit(from: zip)
        let assets = UnitAssets()
        assets.loadItemFromArchive(zip)
        if !assets.hasAssetsFor(unitName: unit.name) {
            fatalError("ItemLoader assets missing unit '\(unit.name)'")
        }
        return (unit, assets, ItemMeta.scale(from: ZipStore.data(named: "meta.txt", in: zip)))
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
        return StickmanUnit(name: name, points: sink.points, edges: [])
    }

    private final class Sink: NSObject, XMLParserDelegate {
        var unitName: String?
        var points: [StickmanPoint] = []

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
            points.append(
                StickmanPoint(id: id, x: CGFloat(x), y: CGFloat(y), isBase: isBase, parentId: parentId)
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
}
