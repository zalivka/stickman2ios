import SwiftUI

struct CameraAnimatorScreen: View {
    @Binding var scene: StickmanScene
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    @State private var navMode: DualNavigation.Mode = .frames
    @State private var range: ClosedRange<Int>
    @State private var showingPreview = false
    @State private var showingTweenRange = false
    @State private var showingTweenEasing = false
    @State private var tweenDraftRange: ClosedRange<Int> = 0...0
    @State private var tweenApplyRange: ClosedRange<Int>?
    @State private var toast = ""
    @StateObject private var undo = SceneUndo()

    init(scene: Binding<StickmanScene>, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if scene.wrappedValue.frames.isEmpty {
            fatalError("CameraAnimatorScreen has no frames")
        }
        _scene = scene
        self.assets = assets
        self.backgrounds = backgrounds
        _range = State(
            initialValue: DualNavigation.defaultRange(
                current: scene.wrappedValue.currentIndex,
                frameCount: scene.wrappedValue.frames.count
            )
        )
        _tweenDraftRange = State(
            initialValue: RangePicker.suggestedTweenRange(
                current: scene.wrappedValue.currentIndex,
                frameCount: scene.wrappedValue.frames.count
            )
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                MainPanel(
                    onPlay: { showingPreview = true },
                    playEnabled: scene.frames.count >= 2,
                    onUndo: performUndo,
                    undoEnabled: undo.canUndo,
                    onReset: resetCamera,
                    onTween: openTweenRange,
                    tweenEnabled: scene.frames.count >= 2
                )
                SkeletonCanvas(
                    unit: unitBinding,
                    frameUnits: scene.currentFrame.units,
                    assets: assets,
                    backgrounds: backgrounds,
                    bgName: scene.currentFrame.bgName,
                    bgMove: scene.currentFrame.bgMove,
                    cameraMove: scene.currentFrame.cameraMove,
                    sceneWidth: scene.width,
                    sceneHeight: scene.height,
                    currentIndex: scene.currentIndex,
                    mode: .camera,
                    showSkeleton: false,
                    onPrepareUndo: { undo.commitTimeline(from: scene) },
                    onLockedEdit: { showToast("Locked") },
                    onCameraChange: applyCamera,
                    canMutateCamera: canMutateCamera
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SkeletonCanvas.pane)
            }
        }
        .overlay(alignment: .trailing) {
            DualNavigationChrome(
                frameCount: scene.frames.count,
                currentIndex: currentIndexBinding,
                range: $range,
                mode: $navMode,
                stickStyle: tweenStickStyle
            )
        }
        .overlay(alignment: .top) {
            if navMode == .frames, let chip = currentCameraSpan {
                HStack(spacing: 0) {
                    Button {
                        openTweenEasing(for: chip)
                    } label: {
                        Text(chip.easingType.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 40)
                    }
                    .background(chip.easingType.chipColor)
                    Button {
                        deleteCurrentTween()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .background(Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 10)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            FullscreenBackButton()
        }
        .overlay {
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showingPreview) {
            FullscreenPreviewScreen(source: scene, assets: assets, backgrounds: backgrounds)
        }
        .sheet(isPresented: $showingTweenRange) {
            RangePicker(
                title: "Smooth camera movement",
                frameCount: scene.frames.count,
                initialRange: tweenDraftRange,
                preview: { index in
                    AnyView(
                        RangeFramePreview(
                            scene: scene,
                            index: index,
                            assets: assets,
                            backgrounds: backgrounds
                        )
                    )
                },
                canApply: canApplyTween(range:),
                onApply: { next in
                    showingTweenRange = false
                    tweenApplyRange = next
                    showingTweenEasing = true
                }
            )
            .id("\(tweenDraftRange.lowerBound):\(tweenDraftRange.upperBound):\(scene.frames.count)")
        }
        .sheet(isPresented: $showingTweenEasing) {
            let span = tweenEasingInitial
            EasingChoiceSheet(
                initialType: span.type,
                initialStrength: span.strength,
                initialFrequency: span.frequency,
                showsCartwheel: false,
                onApply: applyTweenEasing
            )
        }
    }

    private var canMutateCamera: Bool {
        switch navMode {
        case .frames:
            return !scene.isCameraPoseLocked(frameIndex: scene.currentIndex)
        case .range:
            return !range.contains(where: { scene.isCameraPoseLocked(frameIndex: $0) })
        }
    }

    private var currentCameraSpan: CameraAutoTweenRange? {
        scene.cameraTweens.findContaining(frameIndex: scene.currentIndex)
    }

    private func tweenStickStyle(_ index: Int) -> (color: Color?, scale: CGFloat) {
        guard let span = scene.cameraTweens.findContaining(frameIndex: index) else {
            return (nil, 1)
        }
        let scale: CGFloat
        if index == span.fromFrame || index == span.toFrame {
            scale = 1.5
        } else if span.containsInterior(index) {
            scale = 1 / 1.5
        } else {
            scale = 1
        }
        return (span.easingType.chipColor, scale)
    }

    private func applyCamera(_ move: PictureMove) {
        if !canMutateCamera {
            return
        }
        switch navMode {
        case .frames:
            let index = scene.currentIndex
            if index < 0 || index >= scene.frames.count {
                fatalError("CameraAnimatorScreen currentIndex \(index) out of \(scene.frames.count)")
            }
            scene.frames[index].cameraMove = move
            scene.retweenCameraEndpoints(frames: [index])
        case .range:
            if range.lowerBound < 0 || range.upperBound >= scene.frames.count {
                fatalError("CameraAnimatorScreen range \(range) out of \(scene.frames.count)")
            }
            for index in range {
                scene.frames[index].cameraMove = move
            }
            scene.retweenCameraEndpoints(frames: Array(range))
        }
    }

    private func resetCamera() {
        switch navMode {
        case .frames:
            if scene.cameraTweens.findContaining(frameIndex: scene.currentIndex) != nil {
                deleteCurrentTween()
                return
            }
            if scene.currentFrame.cameraMove.isZero {
                return
            }
            undo.commitTimeline(from: scene)
            scene.frames[scene.currentIndex].cameraMove = .identity
        case .range:
            resetRangeMode()
        }
    }

    private func resetRangeMode() {
        var deleted = false
        for index in range {
            if scene.cameraTweens.findContaining(frameIndex: index) != nil {
                deleted = true
                break
            }
        }
        if deleted {
            undo.commitTimeline(from: scene)
            for index in range {
                _ = scene.removeCameraTweenContaining(frameIndex: index)
            }
            showToast("Tweening removed")
            return
        }
        if !canMutateCamera {
            showToast("Locked")
            return
        }
        undo.commitTimeline(from: scene)
        for index in range {
            scene.frames[index].cameraMove = .identity
        }
    }

    private func openTweenRange() {
        if scene.frames.count < 2 {
            return
        }
        tweenDraftRange = resolveTweenInitialRange()
        showingTweenRange = true
    }

    private func resolveTweenInitialRange() -> ClosedRange<Int> {
        if navMode == .range, range.upperBound - range.lowerBound >= 2 {
            return range
        }
        if let existing = scene.cameraTweens.findContaining(frameIndex: scene.currentIndex) {
            return existing.fromFrame...existing.toFrame
        }
        return RangePicker.suggestedTweenRange(current: scene.currentIndex, frameCount: scene.frames.count)
    }

    private func canApplyTween(range: ClosedRange<Int>) -> Bool {
        if range.upperBound - range.lowerBound < 2 {
            return false
        }
        if let intersecting = scene.cameraTweens.findIntersecting(
            from: range.lowerBound,
            to: range.upperBound
        ), intersecting.fromFrame != range.lowerBound || intersecting.toFrame != range.upperBound {
            return false
        }
        return true
    }

    private var tweenEasingInitial: (type: TweenEasing, strength: Float, frequency: Float) {
        let range = tweenApplyRange ?? tweenDraftRange
        if let span = scene.cameraTweens.findExact(from: range.lowerBound, to: range.upperBound) {
            return (span.easingType, span.easingStrength, span.shakeFrequency)
        }
        return (.NO, Easing.defaultStrength, UnitTweenStorage.defaultShakeFrequency)
    }

    private func openTweenEasing(for span: CameraAutoTweenRange) {
        tweenApplyRange = span.fromFrame...span.toFrame
        showingTweenEasing = true
    }

    private func applyTweenEasing(type: TweenEasing, strength: Float, frequency: Float) {
        let range = tweenApplyRange ?? tweenDraftRange
        let from = range.lowerBound
        let to = range.upperBound
        if to - from < 2 {
            fatalError("CameraAnimatorScreen tween range \(from)..\(to) too short")
        }
        if !canApplyTween(range: from...to) {
            return
        }
        undo.commitTimeline(from: scene)
        CameraInbetweener.propagate(
            scene: &scene,
            from: from,
            to: to,
            easing: type,
            strength: strength,
            shakeFrequency: frequency
        )
        scene.currentIndex = to
        clampRange()
        tweenApplyRange = nil
    }

    private func deleteCurrentTween() {
        if scene.cameraTweens.findContaining(frameIndex: scene.currentIndex) == nil {
            return
        }
        undo.commitTimeline(from: scene)
        if scene.removeCameraTweenContaining(frameIndex: scene.currentIndex) != nil {
            showToast("Tweening removed")
        }
    }

    private func performUndo() {
        if !undo.canUndo {
            return
        }
        undo.restore(into: &scene)
        clampRange()
    }

    private func clampRange() {
        let last = scene.frames.count - 1
        if last < 0 {
            fatalError("CameraAnimatorScreen clampRange empty scene")
        }
        if scene.currentIndex < 0 || scene.currentIndex > last {
            fatalError("CameraAnimatorScreen currentIndex \(scene.currentIndex) out of \(scene.frames.count)")
        }
        let low = min(max(range.lowerBound, 0), last)
        let high = min(max(range.upperBound, 0), last)
        self.range = min(low, high)...max(low, high)
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text {
                toast = ""
            }
        }
    }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { scene.currentIndex },
            set: { newIndex in
                if newIndex < 0 || newIndex >= scene.frames.count {
                    fatalError("CameraAnimatorScreen currentIndex \(newIndex) out of \(scene.frames.count)")
                }
                scene.currentIndex = newIndex
            }
        )
    }

    private var unitBinding: Binding<StickmanUnit> {
        Binding(
            get: {
                let frame = scene.currentFrame
                guard let first = frame.units.first else {
                    fatalError("CameraAnimatorScreen frame \(frame.id) read unit")
                }
                return first
            },
            set: { _ in
                fatalError("CameraAnimatorScreen canvas is not an editor")
            }
        )
    }
}
