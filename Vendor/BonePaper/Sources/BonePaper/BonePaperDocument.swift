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
    // Dual-threshold region-growing flood fill (contiguous paint bucket).
    // Colour metric is OKLab Euclidean distance; white↔black is 1.0.
    /// Local step: a pixel joins only if close to the neighbour it was reached from.
    static let fillNeighbourLimit: Float = 0.06
    /// Global skip: stay within this OKLab distance of the tap (first tap). Later same-colour taps add `fillSeedStep`.
    static let fillSeedLimit: Float = 0.2
    /// `alpha * (1 - L)` above this is contour ink the fill never enters (solid black ≈ 1.0).
    static let fillInkLimit: Float = 0.55
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
    /// Last paint-bucket colour+opacity. Nil after a stroke, undo, or redo so the next tap starts at skip 0.20.
    private var lastFillPaint: FillPaint?
    private var fillStreak = 0

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

    /// Paint-bucket tap. Same colour+opacity in a row loosens skip/neighbour/ink; a different colour, stroke, undo or redo resets.
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
        let paint = Self.fillPaint(color: color, opacity: opacity)
        fillStreak = lastFillPaint == paint ? fillStreak + 1 : 0
        lastFillPaint = paint
        // Opaque/semi-opaque seed → recolour island. Transparent seed → fill empty space, stop at ink.
        let recolor = pixels[py * stride + px * 4 + 3] >= Self.fillRecolorAlpha
        var mask = Self.fillRegion(
            pixels: pixels,
            width: pixelWidth,
            height: pixelHeight,
            stride: stride,
            seedX: px,
            seedY: py,
            recolor: recolor,
            limits: FillLimits(streak: fillStreak)
        )
        pushUndo()
        redoStack.removeAll()
        if recolor {
            Self.recolor(pixels: pixels, mask: mask, width: pixelWidth, stride: stride, paint: paint)
        } else {
            Self.growRing(pixels: pixels, mask: &mask, width: pixelWidth, height: pixelHeight, stride: stride)
            Self.paintBehind(pixels: pixels, mask: mask, width: pixelWidth, stride: stride, paint: paint)
        }
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
        lastFillPaint = nil
        redoStack.append(capture())
        restore(previous)
        publishStacks()
    }

    func redo() {
        if strokeLive {
            endStroke()
        }
        guard let next = redoStack.popLast() else { return }
        lastFillPaint = nil
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
    /// 1. not transparent (recolour) / not ink (empty fill, unless the tap was on ink);
    /// 2. OKLab distance to the previous pixel < neighbour limit (region growing);
    /// 3. OKLab distance to the tap < skip/seed limit (global cap).
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
        let seed = lab(pixels, seedY * stride + seedX * 4)
        // Tapping a dark line turns walls off so the contour itself can be recoloured.
        let walls = seed.ink <= limits.ink
        let distance: (FillLab, FillLab) -> Float = recolor ? FillLab.colorDistance : FillLab.coverDistance
        var mask = [UInt8](repeating: 0, count: width * height)
        mask[seedY * width + seedX] = 1
        var stack = [Int32(seedY * width + seedX)]
        func visit(_ x: Int, _ y: Int, from current: FillLab) {
            let m = y * width + x
            if mask[m] != 0 { return }
            let next = lab(pixels, y * stride + x * 4)
            if recolor, next.alpha == 0 { return }
            if walls, next.ink > limits.ink { return }
            if distance(next, current) >= limits.neighbour { return }
            if distance(next, seed) >= limits.seed { return }
            mask[m] = 1
            stack.append(Int32(m))
        }
        while let top = stack.popLast() {
            let m = Int(top)
            let x = m % width
            let y = m / width
            let current = lab(pixels, y * stride + x * 4)
            if x > 0 { visit(x - 1, y, from: current) }
            if x + 1 < width { visit(x + 1, y, from: current) }
            if y > 0 { visit(x, y - 1, from: current) }
            if y + 1 < height { visit(x, y + 1, from: current) }
        }
        return mask
    }

    /// Dilate the empty-space mask into AA fringes (mask 2). Opaque ink is claimed but not crossed.
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
                if x > 0 { claim(m - 1, into: &next) }
                if x + 1 < width { claim(m + 1, into: &next) }
                if y > 0 { claim(m - width, into: &next) }
                if y + 1 < height { claim(m + width, into: &next) }
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

    /// Island recolour: write paint RGB at the pixel's own alpha so the silhouette stays.
    private static func recolor(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: [UInt8],
        width: Int,
        stride: Int,
        paint: FillPaint
    ) {
        let o = paint.a
        func mix(_ dst: UInt8, _ channel: Int, _ alpha: Int) -> UInt8 {
            let src = (channel * alpha + 127) / 255
            return UInt8(clamping: (Int(dst) * (255 - o) + src * o + 127) / 255)
        }
        for m in mask.indices where mask[m] == 1 {
            let i = (m / width) * stride + (m % width) * 4
            let alpha = Int(pixels[i + 3])
            pixels[i] = mix(pixels[i], paint.r, alpha)
            pixels[i + 1] = mix(pixels[i + 1], paint.g, alpha)
            pixels[i + 2] = mix(pixels[i + 2], paint.b, alpha)
        }
    }

    /// Streak 0 is the first tap. Each later same-colour tap widens neighbour ×(1 + step) and skip/ink additively.
    private struct FillLimits {
        var neighbour: Float
        var seed: Float
        var ink: Float

        init(streak: Int) {
            let step = Float(min(streak, fillStreakCap))
            neighbour = fillNeighbourLimit * (1 + step)
            seed = fillSeedLimit + fillSeedStep * step
            ink = min(fillInkLimit + fillInkStep * step, fillInkMax)
        }
    }

    /// Straight (not premultiplied) 0...255; `a` includes tool opacity.
    private struct FillPaint: Equatable {
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
