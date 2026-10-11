import CoreGraphics
import Foundation

enum InstantiateUnit {
    static func insert(
        item: Item,
        into scene: inout StickmanScene,
        assets: UnitAssets,
        frameIndices: [Int]
    ) throws -> String {
        if frameIndices.isEmpty {
            throw SceneLoadError(message: "InstantiateUnit no target frames")
        }
        let zip = try Manifest.shared.itemZip(fullname: item.makeFullName())
        try assets.loadItemFromArchive(
            zip,
            entryName: UnitAssets.atiEntryName(packName: item.packName, systemName: item.systemName),
            forceReload: false
        )
        let model = try ItemLoader.load(zip: zip, into: assets)
        var scale = item.scale
        if try ZipStore.namesThrowing(in: zip).contains("meta.txt") {
            let atiScale = try ItemMeta.scale(from: try ZipStore.dataThrowing(named: "meta.txt", in: zip))
            if atiScale > 0.01 {
                scale = atiScale
            }
        }
        var existing: [String] = []
        for index in frameIndices {
            if index < 0 || index >= scene.frames.count {
                throw SceneLoadError(message: "InstantiateUnit frame \(index) out of \(scene.frames.count)")
            }
            existing.append(contentsOf: scene.frames[index].units.map(\.name))
        }
        let resolved = try UnitName.unique(base: model.name, existing: existing)
        let wherePoint = CGPoint(x: scene.width / 2, y: scene.height / 2)
        for index in frameIndices {
            if index < 0 || index >= scene.frames.count {
                throw SceneLoadError(message: "InstantiateUnit frame \(index) out of \(scene.frames.count)")
            }
            try scene.frames[index].addCopy(model, name: resolved, at: wherePoint, scale: scale)
        }
        return resolved
    }
}
