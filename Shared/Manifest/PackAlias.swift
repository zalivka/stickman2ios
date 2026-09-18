import Foundation

enum PackAlias {
    private static let packs = [
        "newstickman": "zalivka.newstickman",
        "jungle": "zalivka.jungle",
    ]

    static func resolvePack(_ pack: String) -> String {
        packs[pack] ?? pack
    }

    static func resolveUnitName(_ name: String) -> String {
        let core = UnitAssets.removeNumber(name)
        guard let colon = core.firstIndex(of: ":") else {
            return name
        }
        let pack = String(core[..<colon])
        let own = String(core[core.index(after: colon)...])
        if own.isEmpty {
            fatalError("PackAlias unit name '\(name)' has empty own name")
        }
        let mapped = resolvePack(pack)
        if mapped == pack {
            return name
        }
        if let hash = name.firstIndex(of: "#") {
            return mapped + ":" + own + String(name[hash...])
        }
        return mapped + ":" + own
    }
}
