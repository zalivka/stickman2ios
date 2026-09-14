import CoreGraphics
import Foundation

enum InstantiateUnit {
    static func insert(
        item: Item,
        into scene: inout StickmanScene,
        assets: UnitAssets,
        frameIndices: [Int]
    ) -> String {
        if frameIndices.isEmpty {
            fatalError("InstantiateUnit no target frames")
        }
        if !item.isAvailable {
            fatalError("InstantiateUnit locked item '\(item.makeFullName())'")
        }
        let zip = Manifest.shared.itemZip(fullname: item.makeFullName())
        assets.loadItemFromArchive(
            zip,
            entryName: UnitAssets.atiEntryName(packName: item.packName, systemName: item.systemName),
            forceReload: false
        )
        let model = ItemLoader.load(zip: zip, into: assets)
        var scale = item.scale
        if ZipStore.contains("meta.txt", in: zip) {
            let atiScale = ItemMeta.scale(from: ZipStore.data(named: "meta.txt", in: zip))
            if atiScale > 0.01 {
                scale = atiScale
            }
        }
        var existing: [String] = []
        for index in frameIndices {
            if index < 0 || index >= scene.frames.count {
                fatalError("InstantiateUnit frame \(index) out of \(scene.frames.count)")
            }
            existing.append(contentsOf: scene.frames[index].units.map(\.name))
        }
        let resolved = UnitName.unique(base: model.name, existing: existing)
        let wherePoint = CGPoint(x: scene.width / 2, y: scene.height / 2)
        for index in frameIndices {
            if index < 0 || index >= scene.frames.count {
                fatalError("InstantiateUnit frame \(index) out of \(scene.frames.count)")
            }
            scene.frames[index].addCopy(model, name: resolved, at: wherePoint, scale: scale)
        }
        return resolved
    }
}
