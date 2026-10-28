import CoreGraphics

/// Drawing switches shared by the live canvas and `BonePaperBench`.
/// Defaults match the baseline; the bench flips one flag at a time to measure it.
public enum BonePaperFlags {
    public static var antialiasing = true
    public static var fillStreakLoosening = false
    public static var autoCloseStroke = true
    /// Upward screen-space offset (in points) applied to finger/touch input on the canvas.
    public static var brushOffset: CGFloat = 0
}
