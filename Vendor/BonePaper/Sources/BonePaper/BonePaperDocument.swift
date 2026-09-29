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
    /// Full-resolution (`sample` times document) paint buffer for lossless reopen, when the session started from one.
    /// Nil for sheet exports, where `image` already is the buffer.
    public let buffer: CGImage?
    public let extraLeft: CGFloat
    public let extraTop: CGFloat
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

public final class BonePaperDocument: ObservableObject {
    /// Paint buffer pixels per document pixel. Part of the `.ati` sidecar contract (see `UnitAssets`).
    public static let sample: Int = 2
    static let undoCap = 5
    static let defaultSide: Int = 512
    public static let maxSide: Int = 2048
    static let growChunk: Int = 64
    // Dual-threshold region-growing flood fill (contiguous paint bucket).
    // Colour metric is OKLab Euclidean distance; white↔black is 1.0.
    /// Local step: a pixel joins only if close to the neighbour it was reached from.
    static let fillNeighbourLimit: Float = 0.06
    /// Recolour edge: a colour move this big within `fillRing` px is a wall (see `isEdgeRamp`).
    /// Stops #4c6371 against #3b5a71 (0.038 apart), which the neighbour step lets through.
    static let fillEdgeLimit: Float = 0.025
    /// Global skip: stay within this OKLab distance of the tap (first tap). Later same-colour taps add `fillSeedStep`.
    static let fillSeedLimit: Float = 0.2
    /// `alpha * (1 - L)` above this is contour ink the fill never enters (solid black ≈ 1.0).
    static let fillInkLimit: Float = 0.55
    /// Extra ink a pixel may carry past the tap before it reads as a darker wall.
    /// Blocks e.g. a #1e2a58 outline (ink 0.70) around a #2e4658 fill (ink 0.62).
    static let fillInkRelativeMargin: Float = 0.05
    /// Tapped alpha (0...255) at or above this recolours an island instead of filling empty space.
    static let fillRecolorAlpha: UInt8 = 26
    /// Sampled px grown past an empty-space region and painted behind soft line edges.
    static let fillRing = sample * 3 / 2
    /// Same-colour tap streak after the first; skip/neighbour/ink loosen this many times.
    static let fillStreakCap = 4
    static let fillSeedStep: Float = 0.1
    static let fillInkStep: Float = 0.1
    static let fillInkMax: Float = 0.95

    var worldSize: Int { Self.maxSide }

    /// Sheet documents keep their size; strokes past the edge are clipped instead of growing the bitmap.
    let fixed: Bool
    private(set) var width: Int
    private(set) var height: Int
    private(set) var originX: Int
    private(set) var originY: Int
    private(set) var extraLeft: Int = 0
    private(set) var extraTop: Int = 0

    @Published private(set) var preview: CGImage
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var filling = false

    private var context: CGContext
    private var stroke: CGContext
    private var composite: CGContext
    private var strokeLive = false
    private var strokeOpacity: CGFloat = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// Last paint-bucket colour+opacity. Nil after a stroke, undo, or redo so the next tap starts at skip 0.20.
    private var lastFillPaint: FillPaint?
    private var fillStreak = 0
    /// Serial so a fill never overlaps another write to `context`.
    private let fillQueue = DispatchQueue(label: "bonepaper.fill", qos: .userInitiated)
    let recorder: BonePaperRecorder

    var pixelWidth: Int { width * Self.sample }
    var pixelHeight: Int { height * Self.sample }

    convenience init() {
        self.init(width: Self.defaultSide, height: Self.defaultSide, source: nil)
    }

    convenience init(width: Int, height: Int, source: CGImage?) {
        self.init(width: width, height: height, source: source, fixed: false)
    }

    convenience init(sheet: BonePaperSheet) {
        self.init(width: sheet.width, height: sheet.height, source: nil, fixed: true)
    }

    /// Copies `buffer` into the paint buffer. It must already be `sheet` times `sample`; it is not scaled.
    convenience init(sheet: BonePaperSheet, buffer: CGImage) {
        self.init(sheet: sheet)
        if buffer.width != pixelWidth || buffer.height != pixelHeight {
            fatalError("BonePaperDocument buffer \(buffer.width)x\(buffer.height) != \(pixelWidth)x\(pixelHeight)")
        }
        copyBuffer(buffer)
    }

    /// Reopens a bone drawing from its saved picture plus the full-resolution paint buffer.
    /// `buffer` must already be `source` times `sample`; it is copied in without scaling, so no
    /// upscale blur. The source is not drawn (the buffer holds the same pixels at full resolution).
    convenience init(width: Int, height: Int, source: CGImage, buffer: CGImage) {
        if source.width != width || source.height != height {
            fatalError("BonePaperDocument source \(source.width)x\(source.height) != \(width)x\(height)")
        }
        if buffer.width != width * Self.sample || buffer.height != height * Self.sample {
            fatalError("BonePaperDocument buffer \(buffer.width)x\(buffer.height) != \(width * Self.sample)x\(height * Self.sample)")
        }
        self.init(width: width, height: height, source: nil, fixed: false)
        copyBuffer(buffer)
    }

    /// Copies `buffer` into the paint buffer unscaled and refreshes the preview. Size must be checked first.
    private func copyBuffer(_ buffer: CGImage) {
        context.draw(buffer, in: pixelRect)
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument buffer preview failed")
        }
        preview = image
        recorder.base = buffer
    }

    private init(width: Int, height: Int, source: CGImage?, fixed: Bool) {
        self.fixed = fixed
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
        recorder = BonePaperRecorder(
            width: width,
            height: height,
            originX: originX,
            originY: originY,
            fixed: fixed,
            base: source
        )
        context = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        stroke = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        composite = Self.makeBuffer(width: width * Self.sample, height: height * Self.sample)
        if let source {
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(
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
        if filling { return }
        recorder.begin(erase: erase, opacity: opacity)
        lastFillPaint = nil
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
        if filling { return }
        recorder.end()
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
        if filling { return }
        guard let snapshot = undoStack.popLast() else {
            fatalError("BonePaperDocument cancel with empty undo")
        }
        recorder.cancel()
        strokeLive = false
        stroke.clear(pixelRect)
        restore(snapshot)
        publishStacks()
    }

    func stampWorld(from start: CGPoint, to end: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        if filling { return }
        recorder.line(from: start, to: end, color: color, size: size, erase: erase)
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

    /// Paint-bucket tap. Same colour+opacity in a row loosens skip/neighbour/ink; a different colour, stroke, undo or redo resets.
    func fillWorld(at world: CGPoint, color: UIColor, opacity: CGFloat) {
        if filling { return }
        if strokeLive {
            endStroke()
        }
        let px = Int(floor((world.x - CGFloat(originX)) * CGFloat(Self.sample)))
        let py = Int(floor((world.y - CGFloat(originY)) * CGFloat(Self.sample)))
        if px < 0 || py < 0 || px >= pixelWidth || py >= pixelHeight {
            return
        }
        recorder.fill(at: world, color: color, opacity: opacity)
        guard let data = context.data else {
            fatalError("BonePaperDocument fill has no pixel data")
        }
        let stride = context.bytesPerRow
        if stride < pixelWidth * 4 {
            fatalError("BonePaperDocument fill stride \(stride) width \(pixelWidth)")
        }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let paint = Self.fillPaint(color: color, opacity: opacity)
        fillStreak = lastFillPaint == paint ? fillStreak + 1 : 0
        lastFillPaint = paint
        let recolor = pixels[py * stride + px * 4 + 3] >= Self.fillRecolorAlpha
        let limits = FillLimits(streak: fillStreak)
        let width = pixelWidth
        let height = pixelHeight
        pushUndo()
        redoStack.removeAll()
        publishStacks()
        filling = true
        fillQueue.async {
            var mask = Self.fillRegion(
                pixels: pixels,
                width: width,
                height: height,
                stride: stride,
                seedX: px,
                seedY: py,
                recolor: recolor,
                limits: limits
            )
            if recolor {
                BonePaperRecolor.apply(
                    pixels: pixels,
                    mask: mask,
                    width: width,
                    height: height,
                    stride: stride,
                    seed: py * width + px,
                    paint: paint
                )
            } else {
                Self.growRing(pixels: pixels, mask: &mask, width: width, height: height, stride: stride)
                Self.paintBehind(pixels: pixels, mask: mask, width: width, stride: stride, paint: paint)
            }
            DispatchQueue.main.async {
                self.publishPreview()
                self.publishStacks()
                self.filling = false
            }
        }
    }

    func stampDotWorld(at point: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        if filling { return }
        recorder.dot(at: point, color: color, size: size, erase: erase)
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
        if filling { return }
        if strokeLive {
            endStroke()
        }
        guard let previous = undoStack.popLast() else { return }
        recorder.undo()
        lastFillPaint = nil
        redoStack.append(capture())
        restore(previous)
        publishStacks()
    }

    func redo() {
        if filling { return }
        if strokeLive {
            endStroke()
        }
        guard let next = redoStack.popLast() else { return }
        recorder.redo()
        lastFillPaint = nil
        undoStack.append(capture())
        restore(next)
        publishStacks()
    }

    func export() -> BonePaperExport {
        if filling {
            fatalError("BonePaperDocument export during fill")
        }
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
            buffer: committed,
            extraLeft: CGFloat(extraLeft),
            extraTop: CGFloat(extraTop)
        )
    }

    /// The paint buffer at `pixelWidth` × `pixelHeight` (`sample` times the document). No downscale.
    func exportBuffer() -> BonePaperExport {
        if filling {
            fatalError("BonePaperDocument export during fill")
        }
        if strokeLive {
            endStroke()
        }
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument export buffer snapshot failed")
        }
        if image.width != pixelWidth || image.height != pixelHeight {
            fatalError("BonePaperDocument export buffer \(image.width)x\(image.height) != \(pixelWidth)x\(pixelHeight)")
        }
        return BonePaperExport(
            image: image,
            buffer: nil,
            extraLeft: CGFloat(extraLeft),
            extraTop: CGFloat(extraTop)
        )
    }

    func saveRecording(result: CGImage, onion: CGImage?, paper: UIColor?, boneStart: CGPoint?, boneTip: CGPoint?) {
        recorder.save(
            result: result,
            onion: onion,
            paper: paper,
            boneStart: boneStart,
            boneTip: boneTip,
            width: width,
            height: height,
            extraLeft: extraLeft,
            extraTop: extraTop
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
        if fixed {
            return .zero
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
        target.setShouldAntialias(BonePaperFlags.antialiasing)
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

    private static func fillPaint(color: UIColor, opacity: CGFloat) -> FillPaint {
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
        let channel = { (v: CGFloat) in Int((max(0, min(v, 1)) * 255).rounded()) }
        return FillPaint(r: channel(c[0]), g: channel(c[1]), b: channel(c[2]), a: channel(c[3] * opacity))
    }

    private static let srgbToLinear: [Float] = (0..<256).map { v in
        let c = Float(v) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// Un-premultiply RGBA at byte `i`, then sRGB → linear → OKLab (Björn Ottosson).
    private static func lab(_ pixels: UnsafeMutablePointer<UInt8>, _ i: Int) -> FillLab {
        let alpha = Int(pixels[i + 3])
        if alpha == 0 {
            return FillLab(L: 0, a: 0, b: 0, alpha: 0)
        }
        let r = srgbToLinear[min(255, (Int(pixels[i]) * 255 + alpha / 2) / alpha)]
        let g = srgbToLinear[min(255, (Int(pixels[i + 1]) * 255 + alpha / 2) / alpha)]
        let b = srgbToLinear[min(255, (Int(pixels[i + 2]) * 255 + alpha / 2) / alpha)]
        let l = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return FillLab(
            L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717876 * m - 0.8086757660 * s,
            alpha: Float(alpha) / 255
        )
    }

    /// 4-connected stack flood fill. A neighbour joins when:
    /// 1. its premultiplied bytes match the previous pixel (same colour, so the limits already passed still hold), or
    /// 2. not transparent (recolour) / not ink (empty fill, unless the tap was on ink), and
    /// 3. OKLab distance to the previous pixel < neighbour limit (region growing), and
    /// 4. OKLab distance to the tap < skip/seed limit (global cap), and
    /// 5. recolour only: not on an anti-aliased edge (`isEdgeRamp`).
    /// OKLab runs only for a pixel whose bytes differ. A flat sky never converts the interior.
    private static func fillRegion(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        stride: Int,
        seedX: Int,
        seedY: Int,
        recolor: Bool,
        limits: FillLimits
    ) -> [UInt8] {
        if stride % 4 != 0 {
            fatalError("BonePaperDocument fill stride \(stride) is not a multiple of 4")
        }
        func rgba(_ offset: Int) -> UInt32 {
            UnsafeRawPointer(pixels).load(fromByteOffset: offset, as: UInt32.self)
        }
        let seedOffset = seedY * stride + seedX * 4
        let seed = lab(pixels, seedOffset)
        // Ink wall is relative when the tap itself is dark: tapping a dark line still
        // recolours the line (same ink passes), but a darker outline around a dark fill blocks.
        let inkLimit = max(limits.ink, seed.ink + Self.fillInkRelativeMargin)
        let distance: (FillLab, FillLab) -> Float = recolor ? FillLab.colorDistance : FillLab.coverDistance
        var mask = [UInt8](repeating: 0, count: width * height)
        mask[seedY * width + seedX] = 1
        var stack = [Int32(seedY * width + seedX)]
        while let top = stack.popLast() {
            let m = Int(top)
            let x = m % width
            let y = m / width
            let currentOffset = y * stride + x * 4
            let currentBytes = rgba(currentOffset)
            var currentLab: FillLab?
            func visit(_ nx: Int, _ ny: Int) {
                let n = ny * width + nx
                if mask[n] != 0 { return }
                let nextOffset = ny * stride + nx * 4
                if rgba(nextOffset) == currentBytes {
                    mask[n] = 1
                    stack.append(Int32(n))
                    return
                }
                let next = lab(pixels, nextOffset)
                if recolor, next.alpha == 0 { return }
                if next.ink > inkLimit { return }
                let current = currentLab ?? lab(pixels, currentOffset)
                currentLab = current
                if distance(next, current) >= limits.neighbour { return }
                if distance(next, seed) >= limits.seed { return }
                if recolor, isEdgeRamp(pixels: pixels, width: width, height: height, stride: stride, x: nx, y: ny, next: next, seed: seed, limit: Self.fillEdgeLimit) { return }
                mask[n] = 1
                stack.append(Int32(n))
            }
            if x > 0 { visit(x - 1, y) }
            if x + 1 < width { visit(x + 1, y) }
            if y > 0 { visit(x, y - 1) }
            if y + 1 < height { visit(x, y + 1) }
        }
        return mask
    }

    /// Recolour wall at a colour edge, hard or anti-aliased. Anti-aliasing turns a jump into steps under the
    /// neighbour limit, e.g. #2e4658 → (38, 56, 88) → #1e2a58 in 0.024 steps against a 0.06 limit.
    /// A pixel is an edge when some pixel up to `fillRing` away on one of 8 rays is closer to the tap
    /// yet at least `limit` from it, i.e. the colour moves `limit` within `fillRing` px.
    /// Pixels within `limit / 2` of the tap can never pass that test, so flat interiors skip the rays.
    private static func isEdgeRamp(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        stride: Int,
        x: Int,
        y: Int,
        next: FillLab,
        seed: FillLab,
        limit: Float
    ) -> Bool {
        let toSeed = FillLab.colorDistance(next, seed)
        if toSeed < limit / 2 { return false }
        for (dx, dy) in edgeRays {
            for step in 1...fillRing {
                let qx = x + dx * step
                let qy = y + dy * step
                if qx < 0 || qy < 0 || qx >= width || qy >= height { break }
                let q = lab(pixels, qy * stride + qx * 4)
                if q.alpha == 0 { continue }
                if FillLab.colorDistance(q, next) >= limit, FillLab.colorDistance(q, seed) < toSeed {
                    return true
                }
            }
        }
        return false
    }

    private static let edgeRays = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]

    /// Dilate the empty-space mask into AA fringes (mask 2).
    /// Eight neighbours, so a curved edge that only touches the fill at a corner is still claimed.
    /// Opaque ink is claimed but not crossed. Transparent pixels are not entered, so this does not jump a gap.
    private static func growRing(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: inout [UInt8],
        width: Int,
        height: Int,
        stride: Int
    ) {
        func claim(_ n: Int, into next: inout [Int32]) {
            if mask[n] != 0 { return }
            let alpha = pixels[(n / width) * stride + (n % width) * 4 + 3]
            if alpha == 0 { return }
            mask[n] = 2
            if alpha < 255 {
                next.append(Int32(n))
            }
        }
        var frontier = [Int32]()
        for m in mask.indices where mask[m] == 1 {
            frontier.append(Int32(m))
        }
        for _ in 0..<fillRing {
            var next = [Int32]()
            for top in frontier {
                let m = Int(top)
                let x = m % width
                let y = m / width
                let x0 = max(0, x - 1)
                let x1 = min(width - 1, x + 1)
                let y0 = max(0, y - 1)
                let y1 = min(height - 1, y + 1)
                for ny in y0...y1 {
                    for nx in x0...x1 {
                        if nx == x, ny == y { continue }
                        claim(ny * width + nx, into: &next)
                    }
                }
            }
            frontier = next
        }
    }

    /// Destination-over into mask 1+2: line edges stay on top, so the fill tucks under the AA fringe.
    private static func paintBehind(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: [UInt8],
        width: Int,
        stride: Int,
        paint: FillPaint
    ) {
        let r = paint.r * paint.a
        let g = paint.g * paint.a
        let b = paint.b * paint.a
        let a = paint.a * 255
        for m in mask.indices where mask[m] != 0 {
            let i = (m / width) * stride + (m % width) * 4
            let keep = 255 - Int(pixels[i + 3])
            pixels[i] = UInt8(clamping: Int(pixels[i]) + (r * keep + 32512) / 65025)
            pixels[i + 1] = UInt8(clamping: Int(pixels[i + 1]) + (g * keep + 32512) / 65025)
            pixels[i + 2] = UInt8(clamping: Int(pixels[i + 2]) + (b * keep + 32512) / 65025)
            pixels[i + 3] = UInt8(clamping: Int(pixels[i + 3]) + (a * keep + 32512) / 65025)
        }
    }

    /// Streak 0 is the first tap. Each later same-colour tap widens neighbour ×(1 + step) and skip/ink additively.
    private struct FillLimits {
        var neighbour: Float
        var seed: Float
        var ink: Float

        init(streak: Int) {
            let step = BonePaperFlags.fillStreakLoosening ? Float(min(streak, fillStreakCap)) : 0
            neighbour = fillNeighbourLimit * (1 + step)
            seed = fillSeedLimit + fillSeedStep * step
            ink = min(fillInkLimit + fillInkStep * step, fillInkMax)
        }
    }

    /// Straight (not premultiplied) 0...255; `a` includes tool opacity.
    struct FillPaint: Equatable {
        var r: Int
        var g: Int
        var b: Int
        var a: Int
    }

    /// OKLab + straight alpha. `ink` is how much the pixel reads as a dark contour.
    private struct FillLab {
        var L: Float
        var a: Float
        var b: Float
        var alpha: Float

        var ink: Float { alpha * (1 - L) }

        /// Recolour metric: chroma/lightness only. Transparent pixels are rejected before this.
        static func colorDistance(_ p: FillLab, _ q: FillLab) -> Float {
            let dL = p.L - q.L
            let da = p.a - q.a
            let db = p.b - q.b
            return (dL * dL + da * da + db * db).squareRoot()
        }

        /// Colour of barely covered pixels matters little; alpha steps count at half weight.
        static func coverDistance(_ p: FillLab, _ q: FillLab) -> Float {
            let color = colorDistance(p, q)
            let dA = (p.alpha - q.alpha) * 0.5
            return (min(p.alpha, q.alpha) * color * color + dA * dA).squareRoot()
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
