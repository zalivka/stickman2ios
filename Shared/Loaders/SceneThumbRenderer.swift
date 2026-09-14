import SwiftUI
import UIKit

enum SceneThumbRenderer {
    static let smallSize = CGSize(width: 64, height: 64)
    static let bigSize = CGSize(width: 160, height: 64)

    @MainActor
    static func pair(
        scene: StickmanScene,
        assets: UnitAssets,
        backgrounds: BackgroundAssets
    ) -> (small: Data, big: Data) {
        let shot = screenshot(scene: scene, assets: assets, backgrounds: backgrounds)
        return (png(cover(shot, size: smallSize)), png(cover(shot, size: bigSize)))
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
        if frame.units.isEmpty {
            fatalError("SceneThumbRenderer frame \(frame.id) has no units")
        }
        let size = CGSize(width: scene.width, height: scene.height)
        if size.width < 1 || size.height < 1 {
            fatalError("SceneThumbRenderer scene size \(size.width)x\(size.height)")
        }
        let canvas = SkeletonCanvas(
            unit: Binding(
                get: { frame.units[0] },
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
