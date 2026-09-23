enum FeatureFlags {
    /// Hold Shift and pinch or twist to scale and rotate the selected bone picture. Off: that pinch zooms the view.
    static let shiftPinchScale = true
    /// BonePaper opens with the bone at its Skeleton angle and position and zooms in and out.
    /// Off: the bone is level and the editor slides up and down (Android Kurwa).
    static let bonePaperKeepsBoneAngle = true
}
