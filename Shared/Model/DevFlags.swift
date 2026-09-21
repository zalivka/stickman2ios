/// Dev-only switches. Product behavior does not live here.
enum DevFlags {
    /// Draw the skeleton touch-capture radius on the canvas.
    static let debugDrawTouchCapture = false

    /// Expand bone PNGs into bitmap-backed CGImages at load.
    /// Off keeps the lazy PNG data-provider image.
    static let decodedBoneBitmaps = true
}
