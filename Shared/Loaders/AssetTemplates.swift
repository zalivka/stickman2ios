import Foundation

enum AssetTemplates {
    static let packName = "template.basic"

    private static let order = [
        "sword",
        "man2",
        "shark",
        "trex",
        "gun",
        "man1",
        "dog",
        "catapult",
    ]

    static func list() -> [Item] {
        guard let pack = Manifest.shared.pack(named: packName) else {
            fatalError("AssetTemplates missing pack '\(packName)'")
        }
        var byName: [String: Item] = [:]
        for item in pack.items {
            byName[item.systemName] = item
        }
        var templates: [Item] = []
        for name in order {
            if let item = byName[name] {
                templates.append(item)
            }
        }
        let extras = pack.items
            .filter { !order.contains($0.systemName) }
            .sorted { $0.systemName < $1.systemName }
        templates.append(contentsOf: extras)
        return templates
    }

    static func poster(fullname: String) throws -> Data {
        let zip = try Manifest.shared.itemZip(fullname: fullname)
        let names = try ZipStore.namesThrowing(in: zip)
        if names.contains("poster.png") {
            return try ZipStore.dataThrowing(named: "poster.png", in: zip)
        }
        if names.contains("thumb.png") {
            return try ZipStore.dataThrowing(named: "thumb.png", in: zip)
        }
        throw ItemLoadError("AssetTemplates '\(fullname)' missing poster.png and thumb.png")
    }
}
