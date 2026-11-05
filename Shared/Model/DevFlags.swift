enum DevFlags {
    /// Draw the skeleton touch-capture radius on the canvas.
    static let debugDrawTouchCapture = false

    /// Expand bone PNGs into bitmap-backed CGImages at load.
    /// Off keeps the lazy PNG data-provider image.
    static let decodedBoneBitmaps = true

    /// Cap custom item bitmaps at 1024px, skip .x2 sidecars when decodeSample > 1 or unitScale <= 0.5,
    /// and cap raster backgrounds at 2048px.
    static let optimizeGiantBitmaps = true

    /// Offload export JPEG compression and disk writes to a worker pool with a 3-slot semaphore (`FeatureFlags.SAVE_BITMAPS_IN_SEPARATE_THREAD`).
    static let saveBitmapsInSeparateThread = true

    /// Skip drawing off-camera units during export (`FeatureFlags.CAMERA_CULLING_ON_EXPORT`).
    static let cameraCullingOnExport = true
}
