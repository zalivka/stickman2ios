import CoreGraphics
import UIKit

extension BonePaperDocument {
    /// Paint-bucket tap. The same operation in a row loosens skip/neighbour/ink; a different operation, stroke, undo or redo resets.
    func fillWorld(at world: CGPoint, fill: BonePaperFill, onCommitted: (() -> Void)? = nil) {
        if filling { return }
        if strokeLive || brushfillLive {
            endStroke()
        }
        let px = Int(floor((world.x - CGFloat(originX)) * CGFloat(Self.sample)))
        let py = Int(floor((world.y - CGFloat(originY)) * CGFloat(Self.sample)))
        if px < 0 || py < 0 || px >= pixelWidth || py >= pixelHeight {
            return
        }
        let activeMask = maskAlpha
        if let activeMask, activeMask[py * pixelWidth + px] == 0 {
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
        let operation: FillOperation
        switch fill {
        case .color(let color, let opacity):
            operation = .color(Self.fillPaint(color: color, opacity: opacity))
        case .clear:
            operation = .clear
        }
        let seedPainted = pixels[py * stride + px * 4 + 3] >= Self.fillRecolorAlpha
        if operation == .clear, !seedPainted {
            return
        }
        let rejectBorderEscape = !fixed && activeMask == nil && operation != .clear && !seedPainted
        let width = pixelWidth
        let height = pixelHeight
        if rejectBorderEscape, px == 0 || py == 0 || px == width - 1 || py == height - 1 {
            fillRejectedCount += 1
            return
        }
        let sameOp = lastFillOperation == operation
        let nextStreak = sameOp ? fillStreak + 1 : 0
        let limits = FillLimits(streak: nextStreak)
        let beforeSnapshot = capture()
        filling = true
        fillQueue.async {
            guard var mask = Self.fillRegion(
                pixels: pixels,
                clipMask: activeMask,
                width: width,
                height: height,
                stride: stride,
                seedX: px,
                seedY: py,
                recolor: seedPainted,
                limits: limits,
                rejectBorderEscape: rejectBorderEscape
            ) else {
                DispatchQueue.main.async {
                    self.filling = false
                    self.fillRejectedCount += 1
                }
                return
            }
            switch operation {
            case .clear:
                BonePaperRecolor.clear(
                    pixels: pixels,
                    mask: mask,
                    width: width,
                    height: height,
                    stride: stride,
                    seed: py * width + px
                )
            case .color(let paint) where seedPainted:
                BonePaperRecolor.apply(
                    pixels: pixels,
                    mask: mask,
                    width: width,
                    height: height,
                    stride: stride,
                    seed: py * width + px,
                    paint: paint
                )
            case .color(let paint):
                if BonePaperFlags.antialiasing {
                    Self.growRing(pixels: pixels, clipMask: activeMask, mask: &mask, width: width, height: height, stride: stride)
                }
                Self.paintBehind(pixels: pixels, clipMask: activeMask, mask: mask, width: width, stride: stride, paint: paint)
            }
            DispatchQueue.main.async {
                self.fillStreak = nextStreak
                self.lastFillOperation = operation
                self.recorder.fill(at: world, fill: fill)
                self.undoStack.append(beforeSnapshot)
                if self.undoStack.count > Self.undoCap {
                    self.undoStack.removeFirst()
                }
                self.redoStack.removeAll()
                self.publishPreview()
                self.publishStacks()
                self.filling = false
                onCommitted?()
            }
        }
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

    /// 4-connected stack flood fill.
    /// Antialiasing off: a neighbour joins only when its premultiplied bytes equal the tap. A hard stroke has no blend band.
    /// Antialiasing on, a neighbour joins when:
    /// 1. its premultiplied bytes match the previous pixel (same colour, so the limits already passed still hold), or
    /// 2. not transparent (recolour) / not ink (empty fill, unless the tap was on ink), and
    /// 3. OKLab distance to the previous pixel < neighbour limit (region growing), and
    /// 4. OKLab distance to the tap < skip/seed limit (global cap), and
    /// 5. recolour only: not on an anti-aliased edge (`isEdgeRamp`).
    /// OKLab runs only for a pixel whose bytes differ. A flat sky never converts the interior.
    private static func fillRegion(
        pixels: UnsafeMutablePointer<UInt8>,
        clipMask: [UInt8]?,
        width: Int,
        height: Int,
        stride: Int,
        seedX: Int,
        seedY: Int,
        recolor: Bool,
        limits: FillLimits,
        rejectBorderEscape: Bool
    ) -> [UInt8]? {
        if stride % 4 != 0 {
            fatalError("BonePaperDocument fill stride \(stride) is not a multiple of 4")
        }
        if !BonePaperFlags.antialiasing {
            return fillExact(pixels: pixels, clipMask: clipMask, width: width, height: height, stride: stride, seedX: seedX, seedY: seedY, rejectBorderEscape: rejectBorderEscape)
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
            if rejectBorderEscape, x == 0 || y == 0 || x + 1 == width || y + 1 == height {
                return nil
            }
            let currentOffset = y * stride + x * 4
            let currentBytes = rgba(currentOffset)
            var currentLab: FillLab?
            func visit(_ nx: Int, _ ny: Int) {
                let n = ny * width + nx
                if mask[n] != 0 { return }
                if let clipMask, clipMask[n] == 0 { return }
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

    /// 4-connected flood of pixels whose premultiplied bytes equal the tap. Used when antialiasing is off.
    private static func fillExact(
        pixels: UnsafeMutablePointer<UInt8>,
        clipMask: [UInt8]?,
        width: Int,
        height: Int,
        stride: Int,
        seedX: Int,
        seedY: Int,
        rejectBorderEscape: Bool
    ) -> [UInt8]? {
        func rgba(_ offset: Int) -> UInt32 {
            UnsafeRawPointer(pixels).load(fromByteOffset: offset, as: UInt32.self)
        }
        let seedBytes = rgba(seedY * stride + seedX * 4)
        var mask = [UInt8](repeating: 0, count: width * height)
        mask[seedY * width + seedX] = 1
        var stack = [Int32(seedY * width + seedX)]
        while let top = stack.popLast() {
            let m = Int(top)
            let x = m % width
            let y = m / width
            if rejectBorderEscape, x == 0 || y == 0 || x + 1 == width || y + 1 == height {
                return nil
            }
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                let n = ny * width + nx
                if mask[n] != 0 { continue }
                if let clipMask, clipMask[n] == 0 { continue }
                if rgba(ny * stride + nx * 4) != seedBytes { continue }
                mask[n] = 1
                stack.append(Int32(n))
            }
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
        clipMask: [UInt8]?,
        mask: inout [UInt8],
        width: Int,
        height: Int,
        stride: Int
    ) {
        func claim(_ n: Int, into next: inout [Int32]) {
            if mask[n] != 0 { return }
            if let clipMask, clipMask[n] == 0 { return }
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
        clipMask: [UInt8]?,
        mask: [UInt8],
        width: Int,
        stride: Int,
        paint: FillPaint
    ) {
        let r = paint.r
        let g = paint.g
        let b = paint.b
        let baseA = paint.a
        for m in mask.indices where mask[m] != 0 {
            let maskScale = clipMask.map { Int($0[m]) } ?? 255
            if maskScale == 0 { continue }
            let effA = (baseA * maskScale + 127) / 255
            if effA == 0 { continue }
            let pr = r * effA
            let pg = g * effA
            let pb = b * effA
            let pa = effA * 255
            let i = (m / width) * stride + (m % width) * 4
            let keep = 255 - Int(pixels[i + 3])
            pixels[i] = UInt8(clamping: Int(pixels[i]) + (pr * keep + 32512) / 65025)
            pixels[i + 1] = UInt8(clamping: Int(pixels[i + 1]) + (pg * keep + 32512) / 65025)
            pixels[i + 2] = UInt8(clamping: Int(pixels[i + 2]) + (pb * keep + 32512) / 65025)
            pixels[i + 3] = UInt8(clamping: Int(pixels[i + 3]) + (pa * keep + 32512) / 65025)
        }
    }

    /// Streak 0 is the first tap. Each later same-colour tap widens neighbour ×(1 + step) and skip/ink additively.
    struct FillLimits {
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

    enum FillOperation: Equatable {
        case color(FillPaint)
        case clear
    }

    /// OKLab + straight alpha. `ink` is how much the pixel reads as a dark contour.
    struct FillLab {
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
}
