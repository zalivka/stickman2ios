import CoreGraphics
import UIKit

public final class BonePaperDocument: ObservableObject {
    /// Paint buffer pixels per document pixel. Part of the `.ati` sidecar contract (see `UnitAssets`).
    public static let sample: Int = 2
    static let undoCap = 5
    public static let defaultSide: Int = 512
    public static let maxSide: Int = 1536
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
    /// Editor-only shaded overlay (dark outside the active mask, clear inside); nil when no mask is active.
    @Published internal(set) var maskOverlay: CGImage?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published internal(set) var filling = false
    @Published internal(set) var fillRejectedCount = 0

    var context: CGContext
    var stroke: CGContext
    var composite: CGContext
    /// Per-pixel 8-bit alpha (0...255) of the active silhouette mask at `pixelWidth × pixelHeight`; nil when unmasked.
    /// Used by flood fill to treat `0` as an impassable wall and scale edge fill alpha.
    var maskAlpha: [UInt8]?
    /// 8-bit grayscale `CGImage` built once from `maskAlpha` for native `CGContext.clip(to:mask:)` during strokes.
    var maskImage: CGImage?
    var strokeLive = false
    var brushfillLive = false
    private var brushfillPath = CGMutablePath()
    private var brushfillLastPoint: CGPoint = .zero
    private var brushfillHasDot = false
    private var brushfillHasSegment = false
    private var brushfillColor: UIColor = .black
    private var strokeOpacity: CGFloat = 1
    var undoStack: [Snapshot] = []
    var redoStack: [Snapshot] = []
    /// Last paint-bucket operation. Nil after a stroke, undo, or redo so the next tap starts at skip 0.20.
    var lastFillOperation: FillOperation?
    var fillStreak = 0
    /// Serial so a fill never overlaps another write to `context`.
    let fillQueue = DispatchQueue(label: "bonepaper.fill", qos: .userInitiated)
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
    convenience init(width: Int, height: Int, source: CGImage, buffer: CGImage, mask: CGImage? = nil) {
        if source.width != width || source.height != height {
            fatalError("BonePaperDocument source \(source.width)x\(source.height) != \(width)x\(height)")
        }
        if buffer.width != width * Self.sample || buffer.height != height * Self.sample {
            fatalError("BonePaperDocument buffer \(buffer.width)x\(buffer.height) != \(width * Self.sample)x\(height * Self.sample)")
        }
        self.init(width: width, height: height, source: nil, fixed: false)
        copyBuffer(buffer)
        if let mask, let alpha = Self.extractMaskAlpha(from: mask, width: pixelWidth, height: pixelHeight) {
            maskAlpha = alpha
            maskImage = Self.makeMaskImage(alpha: alpha, width: pixelWidth, height: pixelHeight)
            maskOverlay = Self.makeMaskOverlay(alpha: alpha, width: pixelWidth, height: pixelHeight)
        }
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
        if strokeLive || brushfillLive {
            fatalError("BonePaperDocument beginStroke during an open stroke")
        }
        recorder.begin(erase: erase, opacity: opacity)
        lastFillOperation = nil
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

    func beginBrushfillStroke(color: UIColor, opacity: CGFloat) {
        if filling { return }
        if strokeLive || brushfillLive {
            fatalError("BonePaperDocument beginBrushfillStroke during an open stroke")
        }
        if opacity <= 0 {
            fatalError("BonePaperDocument stroke opacity is \(opacity)")
        }
        recorder.beginBrushfill(color: color, opacity: opacity)
        lastFillOperation = nil
        pushUndo()
        redoStack.removeAll()
        stroke.clear(pixelRect)
        brushfillPath = CGMutablePath()
        brushfillLastPoint = .zero
        brushfillHasDot = false
        brushfillHasSegment = false
        brushfillLive = true
        strokeOpacity = opacity
        brushfillColor = color.withAlphaComponent(1)
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
            if let maskImage {
                context.clip(to: pixelRect, mask: maskImage)
            }
            context.setAlpha(strokeOpacity)
            context.draw(layer, in: pixelRect)
            context.restoreGState()
            stroke.clear(pixelRect)
            strokeLive = false
        } else if brushfillLive {
            if brushfillHasSegment {
                brushfillPath.addLine(to: brushfillLastPoint)
                brushfillHasSegment = false
            }
            brushfillPath.closeSubpath()
            if !brushfillPath.isEmpty {
                context.saveGState()
                if let maskImage {
                    context.clip(to: pixelRect, mask: maskImage)
                }
                context.setShouldAntialias(BonePaperFlags.antialiasing)
                context.setAlpha(strokeOpacity)
                context.setFillColor(brushfillColor.cgColor)
                context.addPath(brushfillPath)
                context.fillPath()
                context.restoreGState()
            }
            stroke.clear(pixelRect)
            brushfillPath = CGMutablePath()
            brushfillHasDot = false
            brushfillHasSegment = false
            brushfillLive = false
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
        brushfillLive = false
        brushfillPath = CGMutablePath()
        brushfillHasDot = false
        brushfillHasSegment = false
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

    func stampBrushfillWorld(from start: CGPoint, to end: CGPoint) {
        if filling { return }
        if !brushfillLive {
            fatalError("BonePaperDocument brushfill stamp with no live brushfill stroke")
        }
        recorder.brushfillLine(from: start, to: end)
        var a = bitmapFromWorld(start)
        var b = bitmapFromWorld(end)
        let shift = ensureFits(points: [a, b], radius: 2)
        if shift.dx != 0 || shift.dy != 0 {
            let scale = CGFloat(Self.sample)
            var t = CGAffineTransform(translationX: shift.dx * scale, y: shift.dy * scale)
            if let shifted = brushfillPath.mutableCopy(using: &t) {
                brushfillPath = shifted
            }
            brushfillLastPoint.x += shift.dx * scale
            brushfillLastPoint.y += shift.dy * scale
            a.x += shift.dx
            a.y += shift.dy
            b.x += shift.dx
            b.y += shift.dy
        }
        let p0 = sampledPoint(a)
        let p1 = sampledPoint(b)
        if !brushfillHasDot {
            brushfillHasDot = true
            brushfillPath.move(to: p0)
        }
        let mid = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        brushfillPath.addQuadCurve(to: mid, control: p0)
        brushfillLastPoint = p1
        brushfillHasSegment = true
        rasterizeBrushfillPreview()
    }

    private func rasterizeBrushfillPreview() {
        stroke.clear(pixelRect)
        guard brushfillHasSegment, let drawPath = brushfillPath.mutableCopy() else {
            publishPreview()
            return
        }
        drawPath.addLine(to: brushfillLastPoint)
        drawPath.closeSubpath()
        stroke.saveGState()
        stroke.setShouldAntialias(BonePaperFlags.antialiasing)
        stroke.setBlendMode(.normal)
        stroke.setFillColor(brushfillColor.cgColor)
        stroke.addPath(drawPath)
        stroke.fillPath()
        stroke.restoreGState()
        publishPreview()
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

    func stampBitmapWorld(
        _ image: CGImage,
        centerWorld: CGPoint,
        scale: CGFloat,
        angleRadians: CGFloat
    ) {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        if image.width < 1 || image.height < 1 {
            fatalError("BonePaperDocument invalid stamp image size \(image.width)x\(image.height)")
        }
        if !centerWorld.x.isFinite || !centerWorld.y.isFinite || !scale.isFinite || scale <= 0 || !angleRadians.isFinite {
            fatalError(
                "BonePaperDocument invalid stamp transform center=\(centerWorld) scale=\(scale) angle=\(angleRadians)"
            )
        }

        let halfW = CGFloat(image.width) * scale * 0.5
        let halfH = CGFloat(image.height) * scale * 0.5
        let c = abs(cos(angleRadians))
        let s = abs(sin(angleRadians))
        let extentX = halfW * c + halfH * s + 2
        let extentY = halfW * s + halfH * c + 2

        let minWorldX = centerWorld.x - extentX
        let minWorldY = centerWorld.y - extentY
        let maxWorldX = centerWorld.x + extentX
        let maxWorldY = centerWorld.y + extentY

        let beforeSnapshot = capture()
        var grew = false
        if !fixed {
            let clampedMinX = max(0, minWorldX)
            let clampedMinY = max(0, minWorldY)
            let clampedMaxX = min(CGFloat(worldSize), maxWorldX)
            let clampedMaxY = min(CGFloat(worldSize), maxWorldY)
            if clampedMinX >= clampedMaxX || clampedMinY >= clampedMaxY {
                return
            }
            let left = min(Self.chunk(max(0, CGFloat(originX) - clampedMinX)), originX)
            let top = min(Self.chunk(max(0, CGFloat(originY) - clampedMinY)), originY)
            let right = min(
                Self.chunk(max(0, clampedMaxX - CGFloat(originX + width))),
                worldSize - originX - width
            )
            let bottom = min(
                Self.chunk(max(0, clampedMaxY - CGFloat(originY + height))),
                worldSize - originY - height
            )
            if left > 0 || top > 0 || right > 0 || bottom > 0 {
                grow(left: left, top: top, right: right, bottom: bottom)
                grew = true
            }
        }

        let sampleScale = CGFloat(Self.sample)
        let dirtyLeft = max(0, Int(floor((minWorldX - CGFloat(originX)) * sampleScale)))
        let dirtyTop = max(0, Int(floor((minWorldY - CGFloat(originY)) * sampleScale)))
        let dirtyRight = min(pixelWidth, Int(ceil((maxWorldX - CGFloat(originX)) * sampleScale)))
        let dirtyBottom = min(pixelHeight, Int(ceil((maxWorldY - CGFloat(originY)) * sampleScale)))
        if dirtyLeft >= dirtyRight || dirtyTop >= dirtyBottom {
            if grew {
                restore(beforeSnapshot)
            }
            return
        }

        lastFillOperation = nil
        undoStack.append(beforeSnapshot)
        if undoStack.count > Self.undoCap {
            undoStack.removeFirst()
        }
        redoStack.removeAll()

        let centerBitmap = sampledPoint(bitmapFromWorld(centerWorld))
        context.saveGState()
        if let maskImage {
            context.clip(to: pixelRect, mask: maskImage)
        }
        context.interpolationQuality = .high
        context.translateBy(x: centerBitmap.x, y: centerBitmap.y)
        context.rotate(by: -angleRadians)
        context.scaleBy(x: scale * sampleScale, y: scale * sampleScale)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) * 0.5,
                y: -CGFloat(image.height) * 0.5,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        context.restoreGState()
        publishPreview()
        publishStacks()
    }

    func undo() {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard let previous = undoStack.popLast() else { return }
        recorder.undo()
        lastFillOperation = nil
        redoStack.append(capture())
        restore(previous)
        publishStacks()
    }

    func redo() {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard let next = redoStack.popLast() else { return }
        recorder.redo()
        lastFillOperation = nil
        undoStack.append(capture())
        restore(next)
        publishStacks()
    }

    func snapshotBuffer() -> CGImage {
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument snapshotBuffer failed")
        }
        return image
    }

    func snapshotMaskAlpha() -> [UInt8]? {
        maskAlpha
    }

    func loadFrameBuffer(
        _ image: CGImage,
        maskAlpha: [UInt8]? = nil,
        width: Int,
        height: Int,
        originX: Int,
        originY: Int,
        extraLeft: Int,
        extraTop: Int
    ) {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        if width < 1 || height < 1 || width > worldSize || height > worldSize {
            fatalError("BonePaperDocument loadFrameBuffer size \(width)x\(height)")
        }
        if image.width != width * Self.sample || image.height != height * Self.sample {
            fatalError("BonePaperDocument loadFrameBuffer buffer \(image.width)x\(image.height) != \(width * Self.sample)x\(height * Self.sample)")
        }
        lastFillOperation = nil
        fillStreak = 0
        undoStack.removeAll()
        redoStack.removeAll()
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
        self.extraLeft = extraLeft
        self.extraTop = extraTop
        if let maskAlpha, maskAlpha.count == pixelWidth * pixelHeight {
            self.maskAlpha = maskAlpha
            self.maskImage = Self.makeMaskImage(alpha: maskAlpha, width: pixelWidth, height: pixelHeight)
            self.maskOverlay = Self.makeMaskOverlay(alpha: maskAlpha, width: pixelWidth, height: pixelHeight)
        } else {
            self.maskAlpha = nil
            self.maskImage = nil
            self.maskOverlay = nil
        }
        context = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        stroke = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        composite = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        context.draw(image, in: pixelRect)
        publishPreview()
        publishStacks()
    }

    static func materializeBuffer(width: Int, height: Int, source: CGImage?, buffer: CGImage?) -> CGImage {
        let pWidth = width * sample
        let pHeight = height * sample
        if let buffer, buffer.width == pWidth, buffer.height == pHeight {
            return buffer
        }
        let ctx = makeBuffer(width: pWidth, height: pHeight)
        if let source {
            ctx.interpolationQuality = .high
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: pWidth, height: pHeight))
        }
        guard let image = ctx.makeImage() else {
            fatalError("BonePaperDocument materializeBuffer failed")
        }
        return image
    }

    static func exportCommittedBuffer(
        buffer: CGImage,
        maskAlpha: [UInt8]? = nil,
        width: Int,
        height: Int,
        extraLeft: Int,
        extraTop: Int,
        drawingConfig: BonePaperDrawingConfig
    ) -> BonePaperExport {
        if buffer.width != width * sample || buffer.height != height * sample {
            fatalError("BonePaperDocument exportCommittedBuffer \(buffer.width)x\(buffer.height) != \(width * sample)x\(height * sample)")
        }
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: buffer).draw(in: CGRect(origin: .zero, size: size))
        }
        guard let exported = image.cgImage else {
            fatalError("BonePaperDocument export PNG image failed")
        }
        let pW = width * sample
        let pH = height * sample
        let exportedMask: CGImage?
        if let maskAlpha,
           maskAlpha.count == pW * pH,
           bufferHasVisiblePixels(buffer) {
            exportedMask = makeMaskSidecarImage(alpha: maskAlpha, width: pW, height: pH)
        } else {
            exportedMask = nil
        }
        return BonePaperExport(
            image: exported,
            buffer: buffer,
            mask: exportedMask,
            extraLeft: CGFloat(extraLeft),
            extraTop: CGFloat(extraTop),
            drawingConfig: drawingConfig
        )
    }

    func export() -> BonePaperExport {
        if filling {
            fatalError("BonePaperDocument export during fill")
        }
        if strokeLive || brushfillLive {
            endStroke()
        }
        guard let committed = context.makeImage() else {
            fatalError("BonePaperDocument export committed snapshot failed")
        }
        return Self.exportCommittedBuffer(
            buffer: committed,
            maskAlpha: maskAlpha,
            width: width,
            height: height,
            extraLeft: extraLeft,
            extraTop: extraTop,
            drawingConfig: BonePaperDrawingConfig()
        )
    }

    /// The paint buffer at `pixelWidth` × `pixelHeight` (`sample` times the document). No downscale.
    func exportBuffer() -> BonePaperExport {
        if filling {
            fatalError("BonePaperDocument export during fill")
        }
        if strokeLive || brushfillLive {
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
            mask: nil,
            extraLeft: CGFloat(extraLeft),
            extraTop: CGFloat(extraTop),
            drawingConfig: BonePaperDrawingConfig()
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

    /// Colour under one paint-buffer pixel. `x` and `y` grow right and down from the top of the picture.
    /// Nil when the pixel is outside the picture or fully transparent.
    func color(atPixel x: Int, y: Int) -> UIColor? {
        let image = preview
        if x < 0 || y < 0 || x >= image.width || y >= image.height {
            return nil
        }
        let alpha = image.alphaInfo
        if alpha != .premultipliedLast && alpha != .last {
            fatalError("BonePaperDocument preview alpha \(alpha.rawValue)")
        }
        if image.bitsPerPixel != 32 {
            fatalError("BonePaperDocument preview bpp \(image.bitsPerPixel)")
        }
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            fatalError("BonePaperDocument preview has no pixels")
        }
        let row = image.bytesPerRow
        let i = y * row + x * 4
        if i < 0 || i + 4 > CFDataGetLength(data) {
            fatalError("BonePaperDocument preview pixel \(x),\(y) outside \(CFDataGetLength(data)) bytes")
        }
        let a = bytes[i + 3]
        if a == 0 {
            return nil
        }
        let straight = alpha == .premultipliedLast ? 255 / CGFloat(a) : 1
        return UIColor(
            red: min(CGFloat(bytes[i]) / 255 * straight, 1),
            green: min(CGFloat(bytes[i + 1]) / 255 * straight, 1),
            blue: min(CGFloat(bytes[i + 2]) / 255 * straight, 1),
            alpha: CGFloat(a) / 255
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
        if fixed || maskAlpha != nil {
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
        let oldPixelWidth = pixelWidth
        let oldPixelHeight = pixelHeight
        let oldMaskAlpha = maskAlpha
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
        if let oldMaskAlpha, oldMaskAlpha.count == oldPixelWidth * oldPixelHeight {
            let newPixelWidth = pixelWidth
            let newPixelHeight = pixelHeight
            var newMaskAlpha = [UInt8](repeating: 0, count: newPixelWidth * newPixelHeight)
            let dstX0 = left * Self.sample
            let dstY0 = top * Self.sample
            for y in 0..<oldPixelHeight {
                let srcRow = y * oldPixelWidth
                let dstRow = (dstY0 + y) * newPixelWidth + dstX0
                for x in 0..<oldPixelWidth {
                    newMaskAlpha[dstRow + x] = oldMaskAlpha[srcRow + x]
                }
            }
            maskAlpha = newMaskAlpha
            maskImage = Self.makeMaskImage(alpha: newMaskAlpha, width: newPixelWidth, height: newPixelHeight)
            maskOverlay = Self.makeMaskOverlay(alpha: newMaskAlpha, width: newPixelWidth, height: newPixelHeight)
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

    func pushUndo() {
        undoStack.append(capture())
        if undoStack.count > Self.undoCap {
            undoStack.removeFirst()
        }
    }

    func capture() -> Snapshot {
        guard let image = context.makeImage() else {
            fatalError("BonePaperDocument undo snapshot failed")
        }
        return Snapshot(
            image: image,
            maskAlpha: maskAlpha,
            maskImage: maskImage,
            maskOverlay: maskOverlay,
            width: width,
            height: height,
            originX: originX,
            originY: originY,
            extraLeft: extraLeft,
            extraTop: extraTop
        )
    }

    func restore(_ snapshot: Snapshot) {
        width = snapshot.width
        height = snapshot.height
        originX = snapshot.originX
        originY = snapshot.originY
        extraLeft = snapshot.extraLeft
        extraTop = snapshot.extraTop
        maskAlpha = snapshot.maskAlpha
        maskImage = snapshot.maskImage
        maskOverlay = snapshot.maskOverlay
        context = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        stroke = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        composite = Self.makeBuffer(width: pixelWidth, height: pixelHeight)
        context.draw(snapshot.image, in: pixelRect)
        publishPreview()
    }

    func publishPreview() {
        composite.clear(pixelRect)
        guard let committed = context.makeImage() else {
            fatalError("BonePaperDocument committed snapshot failed")
        }
        composite.draw(committed, in: pixelRect)
        if strokeLive || brushfillLive {
            guard let layer = stroke.makeImage() else {
                fatalError("BonePaperDocument stroke snapshot failed")
            }
            composite.saveGState()
            if let maskImage {
                composite.clip(to: pixelRect, mask: maskImage)
            }
            composite.setAlpha(strokeOpacity)
            composite.draw(layer, in: pixelRect)
            composite.restoreGState()
        }
        guard let image = composite.makeImage() else {
            fatalError("BonePaperDocument preview snapshot failed")
        }
        preview = image
    }

    func publishStacks() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func sampledPoint(_ point: CGPoint) -> CGPoint {
        let scale = CGFloat(Self.sample)
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    var pixelRect: CGRect {
        CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    private static func chunk(_ need: CGFloat) -> Int {
        if need <= 0 { return 0 }
        let step = CGFloat(growChunk)
        return Int(ceil(need / step) * step)
    }

    static func makeBuffer(width: Int, height: Int) -> CGContext {
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

    struct Snapshot {
        var image: CGImage
        var maskAlpha: [UInt8]?
        var maskImage: CGImage?
        var maskOverlay: CGImage?
        var width: Int
        var height: Int
        var originX: Int
        var originY: Int
        var extraLeft: Int
        var extraTop: Int
    }
}
