import SwiftUI

protocol RangeDialogPresenting {
    func showRangeDialog()
}

struct RangePicker: View {
    let title: String
    let frameCount: Int
    let initialRange: ClosedRange<Int>
    var preview: ((Int) -> AnyView)?
    var canApply: ((ClosedRange<Int>) -> Bool)? = nil
    var onCancel: (() -> Void)? = nil
    var onApply: (ClosedRange<Int>) -> Void

    @State private var draft: ClosedRange<Int>
    @State private var currentIndex: Int
    @State private var shownStart: Int
    @State private var shownEnd: Int
    @Environment(\.dismiss) private var dismiss

    private let previewGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)

    init(
        title: String,
        frameCount: Int,
        initialRange: ClosedRange<Int>,
        preview: ((Int) -> AnyView)? = nil,
        canApply: ((ClosedRange<Int>) -> Bool)? = nil,
        onCancel: (() -> Void)? = nil,
        onApply: @escaping (ClosedRange<Int>) -> Void
    ) {
        if frameCount < 1 {
            fatalError("RangePicker frameCount must be >= 1, got \(frameCount)")
        }
        if initialRange.lowerBound < 0 || initialRange.upperBound >= frameCount {
            fatalError("RangePicker initialRange \(initialRange) out of \(frameCount)")
        }
        self.title = title
        self.frameCount = frameCount
        self.initialRange = initialRange
        self.preview = preview
        self.canApply = canApply
        self.onCancel = onCancel
        self.onApply = onApply
        _draft = State(initialValue: initialRange)
        _currentIndex = State(initialValue: initialRange.lowerBound)
        _shownStart = State(initialValue: initialRange.lowerBound)
        _shownEnd = State(initialValue: initialRange.upperBound)
    }

    /// Current plus next 10 if they fit; else current minus previous 10; else all frames.
    static func suggestedTweenRange(current: Int, frameCount: Int) -> ClosedRange<Int> {
        if frameCount < 1 {
            fatalError("RangePicker suggestedTweenRange frameCount \(frameCount)")
        }
        if current < 0 || current >= frameCount {
            fatalError("RangePicker suggestedTweenRange current \(current) out of \(frameCount)")
        }
        let last = frameCount - 1
        if current + 10 <= last {
            return current...(current + 10)
        }
        if current - 10 >= 0 {
            return (current - 10)...current
        }
        return 0...last
    }

    var body: some View {
        VStack(spacing: 0) {
            topPanel
            HStack(spacing: 0) {
                previewBox(border: previewGreen, frame: shownStart, draftFrame: draft.lowerBound)
                previewBox(border: .red, frame: shownEnd, draftFrame: draft.upperBound)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VerticalRangeBar(
                frameCount: frameCount,
                currentIndex: $currentIndex,
                range: $draft,
                axis: .horizontal,
                pinMapping: .identity
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(SkeletonChrome.pane.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SkeletonChrome.pane)
        .onAppear {
            applyInitialRange()
        }
        .onChange(of: initialRange) { _, _ in
            applyInitialRange()
        }
        .task(id: draft) {
            await debounceShownFrames()
        }
    }

    private func applyInitialRange() {
        draft = initialRange
        currentIndex = initialRange.lowerBound
        shownStart = initialRange.lowerBound
        shownEnd = initialRange.upperBound
    }

    private var topPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                backButton
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                applyButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            SkeletonChrome.bonesAccent.frame(height: 3)
        }
        .background(SkeletonChrome.pane)
    }

    private var backButton: some View {
        Button(action: cancel) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var applyEnabled: Bool {
        canApply?(draft) ?? true
    }

    private var applyButton: some View {
        Button {
            onApply(draft)
        } label: {
            Text("Apply")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 72)
                .padding(.vertical, 8)
                .background(SkeletonChrome.boneNew)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!applyEnabled)
        .opacity(applyEnabled ? 1 : 0.4)
        .accessibilityLabel("Apply")
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func debounceShownFrames() async {
        guard preview != nil else {
            shownStart = draft.lowerBound
            shownEnd = draft.upperBound
            return
        }
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            return
        }
        if Task.isCancelled {
            return
        }
        shownStart = draft.lowerBound
        shownEnd = draft.upperBound
    }

    private func previewBox(border: Color, frame: Int, draftFrame: Int) -> some View {
        ZStack {
            if let preview {
                preview(frame)
            } else {
                border
                Text("Frame \(draftFrame + 1)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(border, lineWidth: 3)
        }
    }
}

struct RangeDialogSheet: View {
    let frameCount: Int
    @Binding var range: ClosedRange<Int>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RangePicker(
            title: "Tweening",
            frameCount: frameCount,
            initialRange: range,
            onApply: { next in
                range = next
                dismiss()
            }
        )
    }
}

struct RangeFramePreview: View {
    var scene: StickmanScene
    var index: Int
    var assets: UnitAssets
    var backgrounds: BackgroundAssets

    var body: some View {
        makeCanvas()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func makeCanvas() -> SkeletonCanvas {
        if index < 0 || index >= scene.frames.count {
            fatalError("RangeFramePreview index \(index) out of \(scene.frames.count)")
        }
        let frame = scene.frames[index]
        return SkeletonCanvas(
            unit: frame.units.isEmpty ? nil : Binding(
                get: {
                    guard let first = frame.units.first else {
                        fatalError("RangeFramePreview empty frame read unit")
                    }
                    return first
                },
                set: { _ in
                    fatalError("RangeFramePreview canvas is not interactive")
                }
            ),
            frameUnits: frame.units,
            assets: assets,
            backgrounds: backgrounds,
            bgName: frame.bgName,
            bgMove: frame.bgMove,
            cameraMove: frame.cameraMove,
            sceneWidth: scene.width,
            sceneHeight: scene.height,
            currentIndex: index,
            mode: .preview,
            showSkeleton: false
        )
    }
}
