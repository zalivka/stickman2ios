import SwiftUI

protocol RangeDialogPresenting {
    func showRangeDialog()
}

struct RangePicker: View {
    let title: String
    let frameCount: Int
    var preview: ((Int) -> AnyView)?
    var onApply: (ClosedRange<Int>) -> Void

    @State private var draft: ClosedRange<Int>
    @State private var currentIndex: Int
    @State private var shownStart: Int
    @State private var shownEnd: Int

    private let previewGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)

    init(
        title: String,
        frameCount: Int,
        initialRange: ClosedRange<Int>,
        preview: ((Int) -> AnyView)? = nil,
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
        self.preview = preview
        self.onApply = onApply
        _draft = State(initialValue: initialRange)
        _currentIndex = State(initialValue: initialRange.lowerBound)
        _shownStart = State(initialValue: initialRange.lowerBound)
        _shownEnd = State(initialValue: initialRange.upperBound)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .multilineTextAlignment(.center)

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    previewBox(border: previewGreen, frame: shownStart, draftFrame: draft.lowerBound)
                    previewBox(border: .red, frame: shownEnd, draftFrame: draft.upperBound)
                }
                Button("Apply") {
                    onApply(draft)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
            }

            VerticalRangeBar(
                frameCount: frameCount,
                currentIndex: $currentIndex,
                range: $draft,
                axis: .horizontal,
                pinMapping: .identity
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.15))
        .task(id: draft) {
            await debounceShownFrames()
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
        .frame(width: 160, height: 160)
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
            .frame(width: 160, height: 160)
    }

    private func makeCanvas() -> SkeletonCanvas {
        if index < 0 || index >= scene.frames.count {
            fatalError("RangeFramePreview index \(index) out of \(scene.frames.count)")
        }
        let frame = scene.frames[index]
        return SkeletonCanvas(
            unit: Binding(
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
