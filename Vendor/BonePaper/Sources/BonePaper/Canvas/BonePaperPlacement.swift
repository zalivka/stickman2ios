import CoreGraphics
import Foundation
import UIKit

/// Where the bone sat on the caller's screen. BonePaper opens with the bitmap exactly there, then only zooms.
public struct BonePaperPlacement {
    /// Joint pixel (bone start) in window coordinates.
    public var jointScreen: CGPoint
    /// Bone direction on screen, radians, y down (`atan2(dy, dx)`).
    public var angle: CGFloat
    /// The bitmap is drawn with y negated around the bone.
    public var mirror: Bool
    /// Screen points per bitmap pixel.
    public var pointsPerPixel: CGFloat

    public init(jointScreen: CGPoint, angle: CGFloat, mirror: Bool, pointsPerPixel: CGFloat) {
        if pointsPerPixel <= 0 {
            fatalError("BonePaperPlacement pointsPerPixel \(pointsPerPixel)")
        }
        self.jointScreen = jointScreen
        self.angle = angle
        self.mirror = mirror
        self.pointsPerPixel = pointsPerPixel
    }
}

/// Lets the screen run the exit zoom on the UIKit stage.
final class BonePaperStage {
    weak var view: BonePaperStageView?

    var hasImagePlacement: Bool {
        view?.hasImagePlacement ?? false
    }

    var hasCanvasTransform: Bool {
        view?.hasCanvasTransform ?? false
    }

    func startImagePlacement(_ image: CGImage) {
        view?.startImagePlacement(image)
    }

    func commitImagePlacement() -> Bool {
        view?.commitImagePlacement() ?? false
    }

    func cancelImagePlacement() {
        view?.cancelImagePlacement()
    }

    func startCanvasTransform() -> Bool {
        view?.startCanvasTransform() ?? false
    }

    func commitCanvasTransform() -> Bool {
        view?.commitCanvasTransform() ?? false
    }

    func cancelCanvasTransform() {
        view?.cancelCanvasTransform()
    }

    func zoomBack(duration: TimeInterval, completion: @escaping () -> Void) {
        guard let view else {
            fatalError("BonePaperStage zoomBack with no view")
        }
        view.zoomBack(duration: duration, completion: completion)
    }

    /// Colour under a window point. Black when the point misses the picture. Nil on a clear pixel.
    func sampleColor(atWindow point: CGPoint) -> UIColor? {
        guard let view else {
            return nil
        }
        return view.sampleColor(atWindow: point)
    }

    func clearCursor() {
        view?.hideOffsetCursor()
    }
}
