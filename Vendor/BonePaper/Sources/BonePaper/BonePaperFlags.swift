/// BonePaper's own switches. The package can't see the app's settings, so the app assigns `antialiasing` at launch and when App settings are applied.
public enum BonePaperFlags {
    /// Anti-aliased brush and eraser edges.
    /// Off: every stamped pixel is fully line colour or untouched, so edges are hard (stair-stepped on curves)
    /// and a recolour needs no edge step (see `BonePaperRecolor`).
    public static var antialiasing = true

    /// Same-colour fill retries widen neighbour/seed/ink ("tap again to fill more").
    /// Off: every tap uses streak-0 limits, so a retry never punches through an outline.
    public static var fillStreakLoosening = false
}
