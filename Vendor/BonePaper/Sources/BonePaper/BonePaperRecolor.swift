/// Paint-bucket tap on existing paint: repaint the tapped island, keeping each pixel's alpha.
///
/// With anti-aliasing on, a line drawn over paint leaves an edge band of opaque blends, e.g. 60% blue line +
/// 40% grey page = (91, 101, 196). The island stops before that band, so repainting only the island leaves
/// the old grey showing as a hairline between the line and the new fill. The edge step splits each band pixel
/// into its island share and its line share and swaps only the island share for the paint.
/// With anti-aliasing off there is no band, so the edge step is skipped. See `doc/rim_issue.md`.
enum BonePaperRecolor {
    /// `mask` is the island (value 1) from the flood fill. `seed` is the tapped pixel index (`y * width + x`).
    static func apply(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: [UInt8],
        width: Int,
        height: Int,
        stride: Int,
        seed: Int,
        paint: BonePaperDocument.FillPaint
    ) {
        // Read the band before the island is repainted: the split needs the old island colour around it.
        let edge = BonePaperFlags.antialiasing
            ? edgeShares(pixels: pixels, mask: mask, width: width, height: height, stride: stride, seed: seed)
            : nil
        paintIsland(pixels: pixels, mask: mask, width: width, stride: stride, paint: paint)
        if let edge {
            paintEdge(edge, pixels: pixels, width: width, stride: stride, paint: paint)
        }
    }

    /// The old island colour and, for each band pixel, how much of it is that colour (0...1).
    private struct Edge {
        var island: SIMD3<Float>
        var shares: [(pixel: Int32, share: Float)]
    }

    /// Paint RGB at the pixel's own alpha, mixed by tool opacity, so the silhouette stays.
    private static func paintIsland(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: [UInt8],
        width: Int,
        stride: Int,
        paint: BonePaperDocument.FillPaint
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

    /// Band pixels up to `fillRing` 8-neighbour steps outside the island.
    ///
    /// A band pixel `p` is read as `t·line + (1 − t)·island`. `line` is its neighbour outside the island
    /// that is most different from the island colour; `p` itself counts, so a speck that is already the most
    /// different gets t = 1 and stays. `t` is `p − island` projected onto `line − island`, clamped to 0...1.
    /// Growth goes on only through pixels with t < 0.9, so it stops at solid line and does not cross a thin line.
    private static func edgeShares(
        pixels: UnsafeMutablePointer<UInt8>,
        mask: [UInt8],
        width: Int,
        height: Int,
        stride: Int,
        seed: Int
    ) -> Edge {
        func offset(_ n: Int) -> Int { (n / width) * stride + (n % width) * 4 }
        func distance2(_ p: SIMD3<Float>, _ q: SIMD3<Float>) -> Float { ((p - q) * (p - q)).sum() }
        let island = straightColor(pixels, offset(seed))
        var seen = mask.map { $0 == 1 }
        var shares = [(pixel: Int32, share: Float)]()
        var frontier = [Int32]()
        for m in mask.indices where mask[m] == 1 {
            frontier.append(Int32(m))
        }
        for _ in 0..<BonePaperDocument.fillRing {
            var next = [Int32]()
            for top in frontier {
                let m = Int(top)
                let x = m % width
                let y = m / width
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let n = ny * width + nx
                        if seen[n] { continue }
                        seen[n] = true
                        if pixels[offset(n) + 3] == 0 { continue }
                        let color = straightColor(pixels, offset(n))
                        var line = color
                        var far = distance2(color, island)
                        for ky in max(0, ny - 1)...min(height - 1, ny + 1) {
                            for kx in max(0, nx - 1)...min(width - 1, nx + 1) {
                                let k = ky * width + kx
                                if mask[k] == 1 || pixels[offset(k) + 3] == 0 { continue }
                                let other = straightColor(pixels, offset(k))
                                let d = distance2(other, island)
                                if d > far {
                                    line = other
                                    far = d
                                }
                            }
                        }
                        // Nothing around differs from the island by even one RGB unit: no blend to split.
                        if far < 1 { continue }
                        let t = min(max(((color - island) * (line - island)).sum() / far, 0), 1)
                        if t >= 1 { continue }
                        shares.append((Int32(n), 1 - t))
                        if t < 0.9 {
                            next.append(Int32(n))
                        }
                    }
                }
            }
            frontier = next
        }
        return Edge(island: island, shares: shares)
    }

    /// `p' = p + (paint − island) · share · opacity`, written back premultiplied at the pixel's own alpha.
    /// Example, grey island (174, 181, 173), blue paint (35, 47, 211), share 0.4: (91, 101, 196) → (35, 47, 211).
    private static func paintEdge(
        _ edge: Edge,
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        stride: Int,
        paint: BonePaperDocument.FillPaint
    ) {
        let shift = (SIMD3(Float(paint.r), Float(paint.g), Float(paint.b)) - edge.island) * (Float(paint.a) / 255)
        for (n, share) in edge.shares {
            let i = (Int(n) / width) * stride + (Int(n) % width) * 4
            let alpha = Float(pixels[i + 3])
            let color = straightColor(pixels, i) + shift * share
            for c in 0..<3 {
                pixels[i + c] = UInt8((min(max(color[c], 0), 255) * alpha / 255).rounded())
            }
        }
    }

    /// Un-premultiplied RGB 0...255 of the pixel at byte offset `i`; alpha must be > 0.
    private static func straightColor(_ pixels: UnsafeMutablePointer<UInt8>, _ i: Int) -> SIMD3<Float> {
        SIMD3(Float(pixels[i]), Float(pixels[i + 1]), Float(pixels[i + 2])) * (255 / Float(pixels[i + 3]))
    }
}
