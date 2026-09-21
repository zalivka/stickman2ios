import CoreGraphics
import UIKit

enum BonePaperTool {
    case pen
    case pan
    case eraser
    case fill
}

public struct BonePaperExport {
    public let image: CGImage
    public let extraLeft: CGFloat
    public let extraTop: CGFloat
}

final class BonePaperDocument: ObservableObject {
    static let sample: Int = 2
    static let undoCap = 5
    static let defaultSide: Int = 512
    static let maxSide: Int = 1024
    static let growChunk: Int = 64
    /// Per-channel 0...255. High so AA fringes join the tapped region.
    static let fillTolerance = 128

    var worldSize: Int { Self.maxSide }

    private(set) var width: Int
    private(set) var height: Int
    private(set) var originX: Int
    private(set) var originY: Int
    private(set) var extraLeft: Int = 0
    private(set) var extraTop: Int = 0

    @Published private(set) var preview: CGImage
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var context: CGContext
    private var stroke: CGContext
    private var composite: CGContext
    private var strokeLive = false
    private var strokeOpacity: CGFloat = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var pixelWidth: Int { width * Self.sample }
    var pixelHeight: Int { height * Self.sample }

    convenience init() {
        self.init(width: Self.defaultSide, height: Self.defaultSide, source: nil)
    }

    init(width: Int, height: Int, source: CGImage?) {
        if width < 1 || height < 1 {
            fatalError("BonePaperDocument size \(width)x\(height)")
        }
        if width > Self.maxSide || height > Self.maxSide {
            fatalError("BonePaperDocument size \(width)x\(height) exceeds \(Self.maxSide)")
        }
        if let source, source.width != width || source.height != height {
            fatalError("BonePaperDocument source \(source.width)x\(source.height) != \(width)x\(height)")
        }
        self.width = width
        self.height = height
        originX = (Self.maxSide - width) / 2
        originY = (Self.maxSide - height) / 2
        context = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        stroke = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        composite = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        if let source {
            Self.drawUIKitImage(source, into: context, rect: CGRect(
                x: 0,
                y: 0,
                width: width * Self.sample,
                height: height * Self.sample
            ))
        }
        guard let preview = context.makeImage() else {
            fatalError("BonePaperDocument empty image failed")
        }
        self.preview = preview
    }

    func beginStroke(erase: Bool, opacity: CGFloat) {
        pushUndo()
        redoStack.removeAll()
        if erase {
            strokeLive = false
        } else {
            if opacity <= 0 {
                fatalError("BonePaperDocument stroke opacity is \(opacity)")
            }
            stroke.clear(pixelRect)
            strokeLive = true
            strokeOpacity = opacity
        }
        publishStacks()
    }

    func endStroke() {
        if strokeLive {
            guard let layer = stroke.makeImage() else {
                fatalError("BonePaperDocument stroke snapshot failed")
            }
            context.saveGState()
            context.setAlpha(strokeOpacity)
            context.draw(layer, in: pixelRect)
            context.restoreGState()
            stroke.clear(pixelRect)
            strokeLive = false
        }
        publishPreview()
    }

    // Pinch/second finger: drop the live stroke and the undo snapshot from beginStroke.
    // Do not undo() — that would commit first, then eat a real earlier stroke.
    func cancelStroke() {
        guard let snapshot = undoStack.popLast() else {
            fatalError("BonePaperDocument cancel with empty undo")
        }
        strokeLive = false
        stroke.clear(pixelRect)
        restore(snapshot)
        publishStacks()
    }

    func stampWorld(from start: CGPoint, to end: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        var a = bitmapFromWorld(start)
        var b = bitmapFromWorld(end)
        if !erase {
            let shift = ensureFits(points: [a, b], radius: size / 2)
            a.x += shift.dx
            a.y += shift.dy
            b.x += shift.dx
            b.y += shift.dy
        }
        paint(erase: erase, size: size) { target, sampled in
            target.setStrokeColor(color.withAlphaComponent(1).cgColor)
            target.setLineCap(.round)
            target.setLineJoin(.round)
            target.setLineWidth(sampled)
            target.move(to: sampledPoint(a))
            target.addLine(to: sampledPoint(b))
            target.strokePath()
        }
    }

    func fillWorld(at world: CGPoint, color: UIColor, opacity: CGFloat) {
        if strokeLive {
            endStroke()
        }
        let px = Int(floor((world.x - CGFloat(originX)) * CGFloat(Self.sample)))
        let py = Int(floor((world.y - CGFloat(originY)) * CGFloat(Self.sample)))
        if px < 0 || py < 0 || px >= pixelWidth || py >= pixelHeight {
            return
        }
        guard let data = context.data else {
            fatalError("BonePaperDocument fill has no pixel data")
        }
        let stride = context.bytesPerRow
        if stride < pixelWidth * 4 {
            fatalError("BonePaperDocument fill stride \(stride) width \(pixelWidth)")
        }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let fill = Self.premultiplied(color: color, opacity: opacity)
        let seedIndex = py * stride + px * 4
        let target = (
            pixels[seedIndex],
            pixels[seedIndex + 1],
            pixels[seedIndex + 2],
            pixels[seedIndex + 3]
        )
        if target == fill {
            return
        }
        pushUndo()
        redoStack.removeAll()
        Self.floodFill(
            pixels: pixels,
            width: pixelWidth,
            height: pixelHeight,
            stride: stride,
            seedX: px,
            seedY: py,
            target: target,
            fill: fill
        )
        publishPreview()
        publishStacks()
    }

    func stampDotWorld(at point: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        var p = bitmapFromWorld(point)
        if !erase {
            let shift = ensureFits(points: [p], radius: size / 2)
            p.x += shift.dx
            p.y += shift.dy
        }
        paint(erase: erase, size: size) { target, sampled in
            let radius = sampled / 2
            let at = sampledPoint(p)
            target.setFillColor(color.withAlphaComponent(1).cgColor)
            target.fillEllipse(
                in: CGRect(
                    x: at.x - radius,
                    y: at.y - radius,
                    width: sampled,
                    height: sampled
                )
            )
        }
    }

    func undo() {
        if strokeLive {
            endStroke()
        }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(capture())
        restore(previous)
        publishStacks()
    }

    func redo() {
        if strokeLive {
            endStroke()
        }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(capture())
        restore(next)
        publishStacks()
    }

    func export() -> BonePaperExport {
        if strokeLive {
            endStroke()
        }
        guard let committed = context.makeImage() else {
            fatalError("BonePaperDocument export committed snapshot failed")
        }
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: committed).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let exported = image.cgImage else {
            fatalError("BonePaperDocument export PNG image failed")
        }
        return BonePaperExport(
            image: exported,
            extraLeft: CGFloat(extraLeft),
            extraTop: CGFloat(extraTop)
        )
    }

    func bitmapFromWorld(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: world.x - CGFloat(originX),
            y: CGFloat(height) - (world.y - CGFloat(originY))
        )
    }

    private func ensureFits(points: [CGPoint], radius: CGFloat) -> CGVector {
        if radius < 0 {
            fatalError("BonePaperDocument ensureFits radius is \(radius)")
        }
        var minX = CGFloat(0)
        var minY = CGFloat(0)
        var maxX = CGFloat(width)
        var maxY = CGFloat(height)
        for point in points {
            minX = min(minX, point.x - radius)
            minY = min(minY, point.y - radius)
            maxX = max(maxX, point.x + radius)
            maxY = max(maxY, point.y + radius)
        }
        let needLeft = max(0, 0 - floor(minX))
        let needBottom = max(0, 0 - floor(minY))
        let needRight = max(0, ceil(maxX) - CGFloat(width))
        let needTop = max(0, ceil(maxY) - CGFloat(height))
        let availLeft = originX
        let availTop = originY
        let availRight = worldSize - originX - width
        let availBottom = worldSize - originY - height
        let addLeft = min(Self.chunk(needLeft), availLeft)
        let addTop = min(Self.chunk(needTop), availTop)
        let addRight = min(Self.chunk(needRight), availRight)
        let addBottom = min(Self.chunk(needBottom), availBottom)
        if addLeft == 0, addTop == 0, addRight == 0, addBottom == 0 {
            return .zero
        }
        grow(left: addLeft, top: addTop, right: addRight, bottom: addBottom)
        return CGVector(dx: CGFloat(addLeft), dy: CGFloat(addBottom))
    }

    private func grow(left: Int, top: Int, right: Int, bottom: Int) {
        let oldWidth = width
        let oldHeight = height
        guard let committed = context.makeImage() else {
            fatalError("BonePaperDocument grow committed snapshot failed")
        }
        let liveStroke = strokeLive ? stroke.makeImage() : nil
        if strokeLive, liveStroke == nil {
            fatalError("BonePaperDocument grow stroke snapshot failed")
        }
        width = oldWidth + left + right
        height = oldHeight + top + bottom
        if width > worldSize || height > worldSize {
            fatalError("BonePaperDocument grow \(width)x\(height) exceeds world \(worldSize)")
        }
        originX -= left
        originY -= top
        extraLeft += left
        extraTop += top
        if originX < 0 || originY < 0 || originX + width > worldSize || originY + height > worldSize {
            fatalError("BonePaperDocument origin (\(originX),\(originY)) size \(width)x\(height) outside world")
        }
        context = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        stroke = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        composite = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        let dest = CGRect(
            x: left * Self.sample,
            y: bottom * Self.sample,
            width: oldWidth * Self.sample,
            height: oldHeight * Self.sample
        )
        context.draw(committed, in: dest)
        if let liveStroke {
            stroke.draw(liveStroke, in: dest)
        }
    }

    private func paint(
        erase: Bool,
        size: CGFloat,
        draw: (CGContext, CGFloat) -> Void
    ) {
        if size <= 0 {
            fatalError("BonePaperDocument brush size is \(size)")
        }
        let sampled = size * CGFloat(Self.sample)
        let target = erase ? context : stroke
        if !erase, !strokeLive {
            fatalError("BonePaperDocument pen stamp with no live stroke")
        }
        target.saveGState()
        target.setBlendMode(erase ? .clear : .normal)
        draw(target, sampled)
        target.restoreGState()
        publishPreview()
    }

    private func pushUndo() {
        undoStack.append(capture())
        if undoStack.count > Self.undoCap {
            undoStack.removeFirst()
        }
    }

    private func capture() -> Snapshot {
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument undo snapshot failed")
        }
        return Snapshot(
            image: image,
            width: width,
            height: height,
            originX: originX,
            originY: originY,
            extraLeft: extraLeft,
            extraTop: extraTop
        )
    }

    private func restore(_ snapshot: Snapshot) {
        width = snapshot.width
        height = snapshot.height
        originX = snapshot.originX
        originY = snapshot.originY
        extraLeft = snapshot.extraLeft
        extraTop = snapshot.extraTop
        context = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        stroke = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        composite = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        context.draw(snapshot.image, in: pixelRect)
        publishPreview()
    }

    private func publishPreview() {
        composite.clear(pixelRect)
        guard let committed = context.makeImage() else {
            fatalError("BonePaperDocument committed snapshot failed")
        }
        composite.draw(committed, in: pixelRect)
        if strokeLive {
            guard let layer = stroke.makeImage() else {
                fatalError("BonePaperDocument stroke snapshot failed")
            }
            composite.saveGState()
            composite.setAlpha(strokeOpacity)
            composite.draw(layer, in: pixelRect)
            composite.restoreGState()
        }
        guard let image = composite.makeImage() else {
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

    private var pixelRect: CGRect {
        CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    private static func chunk(_ need: CGFloat) -> Int {
        if need <= 0 { return 0 }
        let step = CGFloat(growChunk)
        return Int(ceil(need / step) * step)
    }

    private static func drawUIKitImage(
        _ image: CGImage,
        into context: CGContext,
        rect: CGRect,
        interpolation: CGInterpolationQuality = .high
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = interpolation
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func makeBuffer(width: Int, height: Int) -> CGContext {
        guard let context = makeBuffer(width: width, height: height, data: nil) else {
            fatalError("BonePaperDocument could not create \(width)x\(height) context")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func makeBuffer(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func premultiplied(color: UIColor, opacity: CGFloat) -> (UInt8, UInt8, UInt8, UInt8) {
        if opacity <= 0 {
            fatalError("BonePaperDocument fill opacity is \(opacity)")
        }
        guard let rgb = color.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ), let c = rgb.components, c.count >= 4 else {
            fatalError("BonePaperDocument fill color is not RGB")
        }
        let alpha = max(0, min(c[3] * opacity, 1))
        return (
            UInt8(clamping: Int((c[0] * alpha * 255).rounded())),
            UInt8(clamping: Int((c[1] * alpha * 255).rounded())),
            UInt8(clamping: Int((c[2] * alpha * 255).rounded())),
            UInt8(clamping: Int((alpha * 255).rounded()))
        )
    }

    private static func floodFill(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        stride: Int,
        seedX: Int,
        seedY: Int,
        target: (UInt8, UInt8, UInt8, UInt8),
        fill: (UInt8, UInt8, UInt8, UInt8)
    ) {
        func write(_ x: Int, _ y: Int) {
            let i = y * stride + x * 4
            pixels[i] = fill.0
            pixels[i + 1] = fill.1
            pixels[i + 2] = fill.2
            pixels[i + 3] = fill.3
        }
        func isTarget(_ x: Int, _ y: Int) -> Bool {
            let i = y * stride + x * 4
            let pixel = (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
            if pixel == fill {
                return false
            }
            return abs(Int(pixel.0) - Int(target.0)) <= fillTolerance
                && abs(Int(pixel.1) - Int(target.1)) <= fillTolerance
                && abs(Int(pixel.2) - Int(target.2)) <= fillTolerance
                && abs(Int(pixel.3) - Int(target.3)) <= fillTolerance
        }

        var stack = [(seedX, seedY)]
        while let (startX, y) = stack.popLast() {
            if !isTarget(startX, y) {
                continue
            }
            var x = startX
            while x > 0, isTarget(x - 1, y) {
                x -= 1
            }
            var spanUp = false
            var spanDown = false
            while x < width, isTarget(x, y) {
                write(x, y)
                if y > 0 {
                    if isTarget(x, y - 1) {
                        if !spanUp {
                            stack.append((x, y - 1))
                            spanUp = true
                        }
                    } else {
                        spanUp = false
                    }
                }
                if y + 1 < height {
                    if isTarget(x, y + 1) {
                        if !spanDown {
                            stack.append((x, y + 1))
                            spanDown = true
                        }
                    } else {
                        spanDown = false
                    }
                }
                x += 1
            }
        }
    }

    private struct Snapshot {
        var image: CGImage
        var width: Int
        var height: Int
        var originX: Int
        var originY: Int
        var extraLeft: Int
        var extraTop: Int
    }
}
