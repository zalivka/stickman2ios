import CoreGraphics
import Foundation

struct PackMeta: Decodable {
    var mSysName: String
    var mHumanName: String
    var version: Int
    var mAuthor: String
    var editableItems: Bool

    private enum CodingKeys: String, CodingKey {
        case mSysName, mHumanName, version, mAuthor, editableItems
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        mSysName = try box.decode(String.self, forKey: .mSysName)
        mHumanName = try box.decodeIfPresent(String.self, forKey: .mHumanName) ?? ""
        version = try box.decode(Int.self, forKey: .version)
        mAuthor = try box.decodeIfPresent(String.self, forKey: .mAuthor) ?? ""
        editableItems = try box.decodeIfPresent(Bool.self, forKey: .editableItems) ?? false
    }

    static func parse(_ data: Data, source: String) -> PackMeta {
        let meta: PackMeta
        do {
            meta = try JSONDecoder().decode(PackMeta.self, from: data)
        } catch {
            fatalError("PackMeta '\(source)' is not JSON: \(error)")
        }
        if meta.mSysName.isEmpty {
            fatalError("PackMeta '\(source)' missing mSysName")
        }
        if !meta.mSysName.contains(".") {
            fatalError("PackMeta '\(source)' mSysName '\(meta.mSysName)' has no '.'")
        }
        return meta
    }
}

struct Query {
    private var requested: Set<String> = []

    static func empty() -> Query {
        Query()
    }

    init(_ packs: String...) {
        requested = Set(packs)
    }

    var isEmpty: Bool { requested.isEmpty }

    func contains(_ packName: String) -> Bool {
        requested.contains(packName)
    }

    var requestedPacks: Set<String> { requested }
}

struct Item {
    var systemName: String
    var humanName: String
    var packName: String
    var fullName: String
    var setName: String
    var scale: CGFloat
    var faceable: Bool
    var multiframed: Bool
    var hidden: Bool
    var readOnly: Bool

    func makeFullName() -> String {
        packName + ":" + systemName
    }
}

struct Pack {
    static let customName = "@"
    static let customTitle = "Custom items"

    var name: String
    var humanName: String
    var version: Int
    var defScale: CGFloat
    var editableItems: Bool
    var useCommonBg: Bool
    var items: [Item]
    var translations: [String: String]

    func translate(_ key: String) -> String? {
        translations[key]
    }

    var title: String {
        if let nameKey = translations["pack_name"], nameKey != name {
            return nameKey
        }
        if !humanName.isEmpty, humanName != name {
            return humanName
        }
        return translations["pack_name"] ?? name
    }
}
