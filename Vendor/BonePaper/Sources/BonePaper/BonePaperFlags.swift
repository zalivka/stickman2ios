/// BonePaper's own switches. The package can't see the app's `FeatureFlags`.
enum BonePaperFlags {
    /// Anti-aliased brush and eraser edges.
    /// Off: every stamped pixel is fully line colour or untouched, so edges are hard (stair-stepped on curves)
    /// and a recolour needs no edge step (see `BonePaperRecolor`).
    static let antialiasing = false
}
