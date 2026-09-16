import CoreGraphics
import UIKit

enum BonePaperTool {
    case pen
    case eraser
}

final class BonePaperDocument: ObservableObject {
    static let side: Int = 512
    static let sample: Int = 2
    static var pixels: Int { side * sample }
    static let undoCap = 20

    @Published private(set) var preview: CGImage
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private let context: CGContext
    private var undoStack: [CGImage] = []
    private var redoStack: [CGImage] = []

    init() {
        let pixels = Self.pixels
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("BonePaperDocument could not create \(pixels)x\(pixels) context")
        }
        context.clear(Self.pixelRect)
        guard let preview = context.makeImage() else {
            fatalError("BonePaperDocument empty image failed")
        }
        self.context = context
        self.preview = preview
    }

    func beginStroke() {
        pushUndo()
        redoStack.removeAll()
        publishStacks()
    }

    func stamp(from start: CGPoint, to end: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        if size <= 0 {
            fatalError("BonePaperDocument brush size is \(size)")
        }
        let sampled = size * CGFloat(Self.sample)
        context.saveGState()
        context.setBlendMode(erase ? .clear : .normal)
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(sampled)
        context.move(to: sampledPoint(start))
        context.addLine(to: sampledPoint(end))
        context.strokePath()
        context.restoreGState()
        publishPreview()
    }

    func stampDot(at point: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        if size <= 0 {
            fatalError("BonePaperDocument brush size is \(size)")
        }
        let sampled = size * CGFloat(Self.sample)
        let radius = sampled / 2
        let at = sampledPoint(point)
        context.saveGState()
        context.setBlendMode(erase ? .clear : .normal)
        context.setFillColor(color.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: at.x - radius,
                y: at.y - radius,
                width: sampled,
                height: sampled
            )
        )
        context.restoreGState()
        publishPreview()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(preview)
        draw(previous)
        publishStacks()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(preview)
        draw(next)
        publishStacks()
    }

    private func pushUndo() {
        undoStack.append(preview)
        if undoStack.count > Self.undoCap {
            undoStack.removeFirst()
        }
    }

    private func draw(_ image: CGImage) {
        context.clear(Self.pixelRect)
        context.draw(image, in: Self.pixelRect)
        publishPreview()
    }

    private func publishPreview() {
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument preview snapshot failed")
        }
        preview = image
    }

    private func publishStacks() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func sampledPoint(_ point: CGPoint) -> CGPoint {
        let scale = CGFloat(Self.sample)
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private static var pixelRect: CGRect {
        CGRect(x: 0, y: 0, width: pixels, height: pixels)
    }
}
