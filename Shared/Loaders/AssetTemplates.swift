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

    static func poster(fullname: String) -> Data {
        let zip = Manifest.shared.itemZip(fullname: fullname)
        if ZipStore.contains("poster.png", in: zip) {
            return ZipStore.data(named: "poster.png", in: zip)
        }
        if ZipStore.contains("thumb.png", in: zip) {
            return ZipStore.data(named: "thumb.png", in: zip)
        }
        fatalError("AssetTemplates '\(fullname)' missing poster.png and thumb.png")
    }
}
