import CoreImage
import CoreGraphics
import UIKit

enum SkeletonOnion {
    static func worldOverlay(
        unit: StickmanUnit,
        assets: UnitAssets,
        excludeFrom: Int,
        excludeTo: Int,
        worldSize: Int,
        pngWidth: Int,
        pngHeight: Int,
        boneStartPNG: CGPoint,
        mirror: Bool
    ) -> CGImage? {
        if worldSize < 1 {
            fatalError("SkeletonOnion worldSize \(worldSize)")
        }
        if unit.scale <= 0 {
            fatalError("SkeletonOnion '\(unit.name)' scale is \(unit.scale)")
        }
        if pngWidth < 1 || pngHeight < 1 {
            fatalError("SkeletonOnion '\(unit.name)' png \(pngWidth)x\(pngHeight)")
        }

        struct Bone {
            var weight: Int
            var start: CGPoint
            var angle: CGFloat
            var asset: UnitAssets.EdgeAsset
        }

        let name = UnitAssets.removeNumber(unit.name)
        var bones: [Bone] = []
        for edge in unit.edges {
            if (edge.from == excludeFrom && edge.to == excludeTo)
                || (edge.from == excludeTo && edge.to == excludeFrom)
            {
                continue
            }
            let key = UnitAssets.EdgeKey(
                unitName: name,
                start: edge.from,
                end: edge.to,
                flipped: unit.flipped
            )
            guard let asset = assets.getDrawable(key, state: unit.assetsState) else { continue }
            let from = unit.point(id: edge.from)
            let to = unit.point(id: edge.to)
            bones.append(
                Bone(
                    weight: asset.weight,
                    start: CGPoint(x: from.x / unit.scale, y: from.y / unit.scale),
                    angle: atan2(to.y - from.y, to.x - from.x),
                    asset: asset
                )
            )
        }
        if bones.isEmpty {
            return nil
        }
        bones.sort { $0.weight < $1.weight }

        let editFrom = unit.point(id: excludeFrom)
        let editTo = unit.point(id: excludeTo)
        let editStart = CGPoint(x: editFrom.x / unit.scale, y: editFrom.y / unit.scale)
        let editAngle = atan2(editTo.y - editFrom.y, editTo.x - editFrom.x)
        let originX = (worldSize - pngWidth) / 2
        let originY = (worldSize - pngHeight) / 2
        let worldBoneStart = CGPoint(
            x: CGFloat(originX) + boneStartPNG.x,
            y: CGFloat(originY) + boneStartPNG.y
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let side = CGFloat(worldSize)
        let raster = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: worldBoneStart.x, y: worldBoneStart.y)
            // BonePaper mirrors the whole paper for a mirrored bone, so the onion is stored unmirrored.
            cg.scaleBy(x: 1, y: mirror ? -1 : 1)
            cg.rotate(by: -editAngle)
            cg.translateBy(x: -editStart.x, y: -editStart.y)
            for bone in bones {
                let mirror = unit.flipped && !bone.asset.nativeFlipped
                let yOffset = mirror ? -bone.asset.yOffset : bone.asset.yOffset
                cg.saveGState()
                cg.translateBy(x: bone.start.x, y: bone.start.y)
                cg.rotate(by: bone.angle)
                cg.translateBy(x: bone.asset.xOffset, y: yOffset)
                if mirror {
                    cg.scaleBy(x: 1, y: -1)
                }
                UIImage(cgImage: bone.asset.bitmap).draw(at: .zero)
                cg.restoreGState()
            }
        }
        guard let cgRaster = raster.cgImage else {
            fatalError("SkeletonOnion '\(unit.name)' raster failed")
        }
        return Self.pale(cgRaster, worldSize: worldSize, name: unit.name)
    }

    private static func pale(_ image: CGImage, worldSize: Int, name: String) -> CGImage {
        let input = CIImage(cgImage: image)
        guard let saturate = CIFilter(name: "CIColorControls") else {
            fatalError("SkeletonOnion '\(name)' missing CIColorControls")
        }
        saturate.setValue(input, forKey: kCIInputImageKey)
        saturate.setValue(0, forKey: kCIInputSaturationKey)
        guard let gray = saturate.outputImage else {
            fatalError("SkeletonOnion '\(name)' saturate failed")
        }
        guard let matrix = CIFilter(name: "CIColorMatrix") else {
            fatalError("SkeletonOnion '\(name)' missing CIColorMatrix")
        }
        matrix.setValue(gray, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 0.2, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 0.2, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0.2, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.85), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0.8, y: 0.8, z: 0.8, w: 0), forKey: "inputBiasVector")
        guard let output = matrix.outputImage else {
            fatalError("SkeletonOnion '\(name)' matrix failed")
        }
        let ci = CIContext(options: nil)
        let extent = CGRect(x: 0, y: 0, width: worldSize, height: worldSize)
        guard let filtered = ci.createCGImage(output, from: extent) else {
            fatalError("SkeletonOnion '\(name)' filter output failed")
        }
        return filtered
    }
}
