import CoreGraphics
import UIKit

enum FrameRasterizer {
    private static let sceneFill = UIColor(
        red: 0x3d / 255,
        green: 0x3e / 255,
        blue: 0x4c / 255,
        alpha: 1
    )

    static func render(
        frame: StickmanFrame,
        assets: UnitAssets,
        backgrounds: BackgroundAssets,
        sceneWidth: CGFloat,
        sceneHeight: CGFloat
    ) -> CGImage {
        if sceneWidth <= 0 || sceneHeight <= 0 {
            fatalError("FrameRasterizer scene size \(sceneWidth)x\(sceneHeight)")
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: sceneWidth, height: sceneHeight)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            cg.saveGState()
            cg.clip(to: CGRect(origin: .zero, size: size))
            cg.concatenate(frame.cameraMove.toTransform())
            drawBackground(
                name: frame.bgName,
                move: frame.bgMove,
                backgrounds: backgrounds,
                sceneWidth: sceneWidth,
                sceneHeight: sceneHeight,
                context: cg
            )
            for unit in unitsToDraw(frame.units) {
                drawUnit(unit, assets: assets, context: cg)
            }
            cg.restoreGState()
        }
        guard let cgImage = image.cgImage else {
            fatalError("FrameRasterizer produced no CGImage")
        }
        if cgImage.width != Int(sceneWidth.rounded()) || cgImage.height != Int(sceneHeight.rounded()) {
            fatalError(
                "FrameRasterizer size \(cgImage.width)x\(cgImage.height) != \(Int(sceneWidth))x\(Int(sceneHeight))"
            )
        }
        return cgImage
    }

    private static func unitsToDraw(_ units: [StickmanUnit]) -> [StickmanUnit] {
        units.sorted {
            if $0.arrange != $1.arrange {
                return $0.arrange < $1.arrange
            }
            return $0.name < $1.name
        }
    }

    private static func drawBackground(
        name: String?,
        move: PictureMove,
        backgrounds: BackgroundAssets,
        sceneWidth: CGFloat,
        sceneHeight: CGFloat,
        context: CGContext
    ) {
        let rect = CGRect(x: 0, y: 0, width: sceneWidth, height: sceneHeight)
        guard let name, !name.isEmpty else {
            sceneFill.setFill()
            context.fill(rect)
            return
        }
        if name.hasPrefix("usermade:") {
            context.saveGState()
            context.concatenate(move.toTransform())
            drawImage(backgrounds.image(for: name))
            context.restoreGState()
            return
        }
        if name.hasPrefix("#") {
            let rgba = HexRGB.parse(name)
            context.setFillColor(UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a).cgColor)
            context.fill(rect)
            return
        }
        fatalError("FrameRasterizer unknown bg_name '\(name)'")
    }

    /// UIKit Y-down. Raw `CGContext.draw(CGImage)` is Y-up and flips bitmaps/bg.
    private static func drawImage(_ image: CGImage) {
        UIImage(cgImage: image, scale: 1, orientation: .up).draw(
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }

    private static func drawUnit(_ drawn: StickmanUnit, assets: UnitAssets, context: CGContext) {
        context.saveGState()
        context.setAlpha(drawn.alpha)
        switch drawn.unitType {
        case .bubble:
            drawBubble(drawn, context: context)
        case .unit:
            drawBitmaps(drawn, assets: assets, context: context)
        }
        context.restoreGState()
    }

    private static func drawBubble(_ drawn: StickmanUnit, context: CGContext) {
        guard let bubble = drawn.bubble else {
            fatalError("FrameRasterizer unit '\(drawn.name)' type=bubble missing meta")
        }
        let start = drawn.point(id: 1)
        let end = drawn.point(id: 2)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let rgba = bubble.rgba
        let color = UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let font = UIFont.systemFont(ofSize: bubble.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        context.saveGState()
        context.translateBy(x: start.x, y: start.y)
        context.rotate(by: angle)
        context.scaleBy(x: drawn.scale, y: drawn.scale)
        let ns = bubble.text as NSString
        if bubble.oneLiner {
            ns.draw(at: .zero, withAttributes: attributes)
        } else {
            ns.draw(with: CGRect(x: 0, y: 0, width: 150, height: 2000), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        }
        context.restoreGState()
    }

    private static func drawBitmaps(_ drawn: StickmanUnit, assets: UnitAssets, context: CGContext) {
        struct Bone {
            var weight: Int
            var start: CGPoint
            var end: CGPoint
            var asset: UnitAssets.EdgeAsset
        }
        var bones: [Bone] = []
        let name = UnitAssets.removeNumber(drawn.name)
        for edge in drawn.edges {
            let key = UnitAssets.EdgeKey(unitName: name, start: edge.from, end: edge.to, flipped: drawn.flipped)
            guard let asset = assets.getDrawable(key, state: drawn.assetsState) else { continue }
            let from = drawn.point(id: edge.from)
            let to = drawn.point(id: edge.to)
            bones.append(
                Bone(
                    weight: asset.weight,
                    start: CGPoint(x: from.x, y: from.y),
                    end: CGPoint(x: to.x, y: to.y),
                    asset: asset
                )
            )
        }
        bones.sort { $0.weight < $1.weight }
        for bone in bones {
            let angle = atan2(bone.end.y - bone.start.y, bone.end.x - bone.start.x)
            let mirror = drawn.flipped && !bone.asset.nativeFlipped
            let yOffset = (mirror ? -bone.asset.yOffset : bone.asset.yOffset) * drawn.scale
            let bitmap = bone.asset.bitmap
            context.saveGState()
            context.translateBy(x: bone.start.x, y: bone.start.y)
            context.rotate(by: angle)
            context.translateBy(x: -bone.start.x, y: -bone.start.y)
            context.translateBy(
                x: bone.start.x + bone.asset.xOffset * drawn.scale,
                y: bone.start.y + yOffset
            )
            context.scaleBy(x: drawn.scale, y: mirror ? -drawn.scale : drawn.scale)
            drawImage(bitmap)
            context.restoreGState()
        }
    }
}
