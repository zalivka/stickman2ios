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
    ) throws -> CGImage {
        if sceneWidth <= 0 || sceneHeight <= 0 {
            throw SceneLoadError(message: "FrameRasterizer scene size \(sceneWidth)x\(sceneHeight)")
        }
        // Resolve the background before rasterizing: the renderer closure cannot throw,
        // and an imported scene missing its stripped background must fail the frame
        // honestly instead of drawing a lie.
        let background = try resolveBackground(
            name: frame.bgName,
            move: frame.bgMove,
            backgrounds: backgrounds,
            sceneWidth: sceneWidth,
            sceneHeight: sceneHeight
        )
        let cameraRect = DevFlags.cameraCullingOnExport
            ? cameraRectangle(sceneWidth: sceneWidth, sceneHeight: sceneHeight, cameraMove: frame.cameraMove)
            : nil
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
            drawBackground(background, context: cg)
            for unit in unitsToDraw(frame.units) {
                if let cameraRect, isOutOfSight(unit, assets: assets, cameraRect: cameraRect) {
                    continue
                }
                drawUnit(unit, assets: assets, context: cg)
            }
            cg.restoreGState()
            if let overlay = frame.cameraEffect.overlayUIColor {
                overlay.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
        }
        guard var cgImage = image.cgImage else {
            throw SceneLoadError(message: "FrameRasterizer produced no CGImage")
        }
        if frame.cameraEffect.normalizedColorMatrix != nil {
            cgImage = frame.cameraEffect.applyColorMatrix(to: cgImage)
        }
        if cgImage.width != Int(sceneWidth.rounded()) || cgImage.height != Int(sceneHeight.rounded()) {
            throw SceneLoadError(
                message: "FrameRasterizer size \(cgImage.width)x\(cgImage.height) != \(Int(sceneWidth))x\(Int(sceneHeight))"
            )
        }
        return cgImage
    }

    private enum BackgroundDraw {
        case sceneFill(rect: CGRect)
        case color(CGColor, rect: CGRect)
        case image(CGImage, PictureMove, sampleScale: CGFloat)
    }

    private static func resolveBackground(
        name: String?,
        move: PictureMove,
        backgrounds: BackgroundAssets,
        sceneWidth: CGFloat,
        sceneHeight: CGFloat
    ) throws -> BackgroundDraw {
        let rect = CGRect(x: 0, y: 0, width: sceneWidth, height: sceneHeight)
        guard let name, !name.isEmpty else {
            return .sceneFill(rect: rect)
        }
        if name.hasPrefix("usermade:") {
            guard let image = backgrounds.image(for: name) else {
                throw SceneLoadError(message: "FrameRasterizer missing background '\(name)'")
            }
            return .image(image, move, sampleScale: backgrounds.sampleScale(for: name))
        }
        if name.hasPrefix("#") {
            guard let rgba = HexRGB.parse(name) else {
                return .sceneFill(rect: rect)
            }
            return .color(UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a).cgColor, rect: rect)
        }
        throw SceneLoadError(message: "FrameRasterizer unknown bg_name '\(name)'")
    }

    private static func drawBackground(_ background: BackgroundDraw, context: CGContext) {
        switch background {
        case .sceneFill(let rect):
            sceneFill.setFill()
            context.fill(rect)
        case .color(let color, let rect):
            context.setFillColor(color)
            context.fill(rect)
        case .image(let image, let move, let sampleScale):
            context.saveGState()
            context.concatenate(move.toTransform())
            if sampleScale != 1 {
                context.scaleBy(x: sampleScale, y: sampleScale)
            }
            drawImage(image, alpha: 1)
            context.restoreGState()
        }
    }

    private static func unitsToDraw(_ units: [StickmanUnit]) -> [StickmanUnit] {
        units.sorted {
            if $0.arrange != $1.arrange {
                return $0.arrange < $1.arrange
            }
            return $0.name < $1.name
        }
    }

    /// Android `FrameDrawer.cameraRectangle(scene, cameraMovement)`.
    private static func cameraRectangle(
        sceneWidth: CGFloat,
        sceneHeight: CGFloat,
        cameraMove: PictureMove
    ) -> CGRect {
        let viewport = CGRect(x: 0, y: 0, width: sceneWidth, height: sceneHeight)
        let transform = cameraMove.toTransform()
        if transform.a * transform.d - transform.b * transform.c == 0 {
            assertionFailure("FrameRasterizer camera transform is not invertible")
            return viewport
        }
        return viewport.applying(transform.inverted())
    }

    /// Android `Unit.isOutOfSight(camRect)` + `AssetsOpsImpl.updateBoundingBoxFor`.
    private static func isOutOfSight(
        _ unit: StickmanUnit,
        assets: UnitAssets,
        cameraRect: CGRect
    ) -> Bool {
        if unit.points.isEmpty {
            return true
        }
        switch unit.unitType {
        case .bubble:
            return !bubbleBoundingBox(unit).intersects(cameraRect)
        case .unit:
            return !unitBoundingBox(unit, assets: assets).intersects(cameraRect)
        }
    }

    private static func unitBoundingBox(_ unit: StickmanUnit, assets: UnitAssets) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for point in unit.points {
            if point.x < minX { minX = point.x }
            if point.x > maxX { maxX = point.x }
            if point.y < minY { minY = point.y }
            if point.y > maxY { maxY = point.y }
        }
        for corner in assets.assetCornerPoints(for: unit, state: unit.assetsState) {
            if corner.x < minX { minX = corner.x }
            if corner.x > maxX { maxX = corner.x }
            if corner.y < minY { minY = corner.y }
            if corner.y > maxY { maxY = corner.y }
        }
        let minSide: CGFloat = 60
        if maxX - minX < minSide {
            maxX += minSide / 2
            minX -= minSide / 2
        }
        if maxY - minY < minSide {
            maxY += minSide / 2
            minY -= minSide / 2
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func bubbleBoundingBox(_ unit: StickmanUnit) -> CGRect {
        guard let bubble = unit.bubble,
              let start = unit.point(optionalId: 1),
              let end = unit.point(optionalId: 2)
        else {
            return .null
        }
        let font = UIFont.systemFont(ofSize: bubble.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let ns = bubble.text as NSString
        let rawSize: CGSize
        if bubble.oneLiner {
            rawSize = ns.size(withAttributes: attributes)
        } else {
            rawSize = ns.boundingRect(
                with: CGSize(width: 150, height: 2000),
                options: [.usesLineFragmentOrigin],
                attributes: attributes,
                context: nil
            ).size
        }
        let width = max(rawSize.width, 1) * unit.scale
        let height = max(rawSize.height, 1) * unit.scale
        let angle = atan2(end.y - start.y, end.x - start.x)
        let cosine = cos(angle)
        let sine = sin(angle)
        let locals = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: height),
            CGPoint(x: 0, y: height)
        ]
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for local in locals {
            let x = start.x + local.x * cosine - local.y * sine
            let y = start.y + local.x * sine + local.y * cosine
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// UIKit Y-down. Raw `CGContext.draw(CGImage)` is Y-up and flips bitmaps/bg.
    /// `UIImage.draw(in:)` ignores the context global alpha, so opacity is
    /// passed explicitly instead of relying on `setAlpha`.
    private static func drawImage(_ image: CGImage, alpha: CGFloat) {
        UIImage(cgImage: image, scale: 1, orientation: .up).draw(
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
            blendMode: .normal,
            alpha: alpha
        )
    }

    private static func drawUnit(_ drawn: StickmanUnit, assets: UnitAssets, context: CGContext) {
        context.saveGState()
        switch drawn.unitType {
        case .bubble:
            context.setAlpha(drawn.alpha)
            drawBubble(drawn, context: context)
        case .unit:
            drawBitmaps(drawn, assets: assets, alpha: drawn.alpha, context: context)
        }
        context.restoreGState()
    }

    private static func drawBubble(_ drawn: StickmanUnit, context: CGContext) {
        guard let bubble = drawn.bubble else {
            // SceneXML.parse rejects a bubble without meta; a scene reaching here was built in-memory.
            assertionFailure("FrameRasterizer unit '\(drawn.name)' type=bubble missing meta")
            return
        }
        guard let start = drawn.point(optionalId: 1), let end = drawn.point(optionalId: 2) else { return }
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

    private static func drawBitmaps(_ drawn: StickmanUnit, assets: UnitAssets, alpha: CGFloat, context: CGContext) {
        struct Bone {
            var weight: Int
            var start: CGPoint
            var end: CGPoint
            var edge: StickmanEdge
            var asset: UnitAssets.EdgeAsset
        }
        var bones: [Bone] = []
        let name = UnitAssets.removeNumber(drawn.name)
        for edge in drawn.edges {
            let key = UnitAssets.EdgeKey(unitName: name, start: edge.from, end: edge.to, flipped: drawn.flipped)
            guard let asset = assets.getDrawable(key, state: drawn.assetsState) else { continue }
            guard let from = drawn.point(optionalId: edge.from), let to = drawn.point(optionalId: edge.to) else { continue }
            bones.append(
                Bone(
                    weight: asset.weight,
                    start: CGPoint(x: from.x, y: from.y),
                    end: CGPoint(x: to.x, y: to.y),
                    edge: edge,
                    asset: asset
                )
            )
        }
        bones.sort { $0.weight < $1.weight }
        for bone in bones {
            let angle = atan2(bone.end.y - bone.start.y, bone.end.x - bone.start.x)
            let ratio = BoneStretch.ratio(unit: drawn, edge: bone.edge, assets: assets)
            let mirror = drawn.flipped && !bone.asset.nativeFlipped
            let yOffset = (mirror ? -bone.asset.yOffset : bone.asset.yOffset) * drawn.scale
            let picture = bone.asset.drawnPicture(ignoreSample: AppSettings.ignoreBmSample, unitScale: drawn.scale)
            let pictureScale = drawn.scale / picture.divisor
            context.saveGState()
            context.translateBy(x: bone.start.x, y: bone.start.y)
            context.rotate(by: angle)
            if let ratio {
                context.scaleBy(x: ratio, y: 1)
            }
            context.translateBy(x: -bone.start.x, y: -bone.start.y)
            context.translateBy(
                x: bone.start.x + bone.asset.xOffset * drawn.scale,
                y: bone.start.y + yOffset
            )
            context.scaleBy(x: pictureScale, y: mirror ? -pictureScale : pictureScale)
            drawImage(picture.image, alpha: alpha)
            context.restoreGState()
        }
    }
}
