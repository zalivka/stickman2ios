enum FeatureFlags {
    /// Hold Shift and pinch or twist to scale and rotate the selected bone picture.
    /// Off for now: Shift only slides the picture. Pinch and twist do nothing while it is held.
    static let shiftPinchScale = false
    /// BonePaper opens with the bone at its Skeleton angle and position and zooms in and out.
    /// Off: the bone is level and the editor slides up and down (Android Kurwa).
    static let bonePaperKeepsBoneAngle = true
}
