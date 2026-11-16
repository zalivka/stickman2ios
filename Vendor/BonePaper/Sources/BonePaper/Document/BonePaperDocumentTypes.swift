import CoreGraphics
import UIKit

enum BonePaperTool {
    case pen
    case pan
    case eraser
    case bucket
    case brushfill
}

enum BonePaperFill {
    case color(UIColor, opacity: CGFloat)
    case clear
}

public struct BonePaperExport {
    public let image: CGImage
    /// Full-resolution (`sample` times document) paint buffer for lossless reopen, when the session started from one.
    /// Nil for sheet exports, where `image` already is the buffer.
    public let buffer: CGImage?
    /// Full-resolution (`sample` times document) RGBA mask sidecar image when a mask is active and the frame has visible pixels.
    public let mask: CGImage?
    public let extraLeft: CGFloat
    public let extraTop: CGFloat
    public var drawingConfig: BonePaperDrawingConfig
}

/// A fixed-size page with a solid paper colour behind the strokes. It never grows; the eraser shows the paper.
public struct BonePaperSheet: Identifiable {
    public let id = UUID()
    public let width: Int
    public let height: Int
    public let paper: UIColor

    public init(width: Int, height: Int, paper: UIColor) {
        if width < 1 || height < 1 {
            fatalError("BonePaperSheet size \(width)x\(height)")
        }
        if width > BonePaperDocument.maxSide || height > BonePaperDocument.maxSide {
            fatalError("BonePaperSheet size \(width)x\(height) exceeds \(BonePaperDocument.maxSide)")
        }
        self.width = width
        self.height = height
        self.paper = paper
    }
}
