import SwiftUI
import UIKit

enum SceneThumbRenderer {
    static let smallSize = CGSize(width: 64, height: 64)
    static let bigSize = CGSize(width: 160, height: 64)
    private static let itemPosterSize = CGSize(width: 480, height: 480)
    private static let itemThumbSize = CGSize(width: 196, height: 196)
    private static let itemPadding: CGFloat = 0.1

    @MainActor
    static func pair(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets
    ) -> (small: Data, big: Data) {
        let shot = screenshot(scene: scene, assets: assets, backgrounds: backgrounds)
        return (png(cover(shot, size: smallSize)), png(cover(shot, size: bigSize)))
    }

    /// Android `EditView.screenshotItemPoster` (480, 10% pad) and `CustomUnitIO.thumbFromPoster` (196 on white).
    @MainActor
    static func itemPair(unit: StickmanUnit, assets: UnitAssets) -> (thumb: Data, poster: Data) {
        let poster = screenshotItem(unit: unit, assets: assets, size: itemPosterSize)
        let thumb = cover(poster, size: itemThumbSize)
        return (png(thumb), png(poster))
    }

    @MainActor
    private static func screenshotItem(unit: StickmanUnit, assets: UnitAssets, size: CGSize) -> UIImage {
        if unit.points.isEmpty {
            fatalError("SceneThumbRenderer item '\(unit.name)' has no points")
        }
        let layout = posterLayout(unit: unit, assets: assets, size: size)
        let canvas = SkeletonCanvas(
            unit: Binding(
                get: { unit },
                set: { _ in
                    fatalError("SceneThumbRenderer item canvas is not interactive")
                }
            ),
            frameUnits: [unit],
            assets: assets,
            sceneWidth: size.width,
            sceneHeight: size.height,
            mode: .itemPoster,
            posterLayout: layout,
            showSkeleton: false
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage, image.size.width >= 1, image.size.height >= 1 else {
            fatalError("SceneThumbRenderer item screenshot is empty")
        }
        return image
    }

    private static func posterLayout(unit: StickmanUnit, assets: UnitAssets, size: CGSize) -> SkeletonLayout {
        var xs = unit.points.map(\.x)
        var ys = unit.points.map(\.y)
        for corner in assets.assetCornerPoints(for: unit, state: unit.assetsState) {
            xs.append(corner.x)
            ys.append(corner.y)
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            fatalError("SceneThumbRenderer item '\(unit.name)' has no bounds")
        }
        var bounds = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        bounds = bounds.insetBy(dx: -bounds.width * itemPadding, dy: -bounds.height * itemPadding)
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        if scale <= 0 {
            fatalError("SceneThumbRenderer item scale is \(scale)")
        }
        return SkeletonLayout(
            minX: 0,
            minY: 0,
            scale: scale,
            originX: size.width / 2 - bounds.midX * scale,
            originY: size.height / 2 - bounds.midY * scale
        )
    }

    @MainActor
    private static func screenshot(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets
    ) -> UIImage {
        if scene.frames.isEmpty {
            fatalError("SceneThumbRenderer scene has no frames")
        }
        let frame = scene.currentFrame
        let size = CGSize(width: scene.width, height: scene.height)
        if size.width < 1 || size.height < 1 {
            fatalError("SceneThumbRenderer scene size \(size.width)x\(size.height)")
        }
        let canvas = SkeletonCanvas(
            unit: Binding(
                get: {
                    guard let first = frame.units.first else {
                        fatalError("SceneThumbRenderer empty frame read unit")
                    }
                    return first
                },
                set: { _ in
                    fatalError("SceneThumbRenderer canvas is not interactive")
                }
            ),
            frameUnits: frame.units,
            assets: assets,
            backgrounds: backgrounds,
            bgName: frame.bgName,
            bgMove: frame.bgMove,
            cameraMove: frame.cameraMove,
            sceneWidth: scene.width,
            sceneHeight: scene.height,
            currentIndex: scene.currentIndex,
            mode: .preview,
            showSkeleton: false
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.uiImage, image.size.width >= 1, image.size.height >= 1 else {
            fatalError("SceneThumbRenderer screenshot is empty")
        }
        return image
    }

    private static func cover(_ image: UIImage, size: CGSize) -> UIImage {
        let src = image.size
        if src.width < 1 || src.height < 1 {
            fatalError("SceneThumbRenderer screenshot size \(src.width)x\(src.height)")
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let ratio = size.width / src.width
            let yOffset = (ratio * src.height - size.height) / 2
            image.draw(
                in: CGRect(
                    x: 0,
                    y: -yOffset,
                    width: src.width * ratio,
                    height: src.height * ratio
                )
            )
        }
    }

    private static func png(_ image: UIImage) -> Data {
        guard let data = image.pngData(), !data.isEmpty else {
            fatalError("SceneThumbRenderer produced no PNG")
        }
        return data
    }
}
