import SwiftUI

protocol RangeDialogPresenting {
    func showRangeDialog()
}

struct RangeDialogSheet: View {
    let frameCount: Int
    @Binding var range: ClosedRange<Int>
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ClosedRange<Int>
    @State private var currentIndex: Int

    private let previewGreen = Color(red: 0x99 / 255, green: 0xc9 / 255, blue: 0x3c / 255)

    init(frameCount: Int, range: Binding<ClosedRange<Int>>) {
        self.frameCount = frameCount
        self._range = range
        self._draft = State(initialValue: range.wrappedValue)
        self._currentIndex = State(initialValue: range.wrappedValue.lowerBound)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Tweening")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    previewBox(color: previewGreen, frame: draft.lowerBound)
                    previewBox(color: .red, frame: draft.upperBound)
                }
                Button("Apply") {
                    range = draft
                    dismiss()
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
        .background(Color(white: 0.15))
    }

    private func previewBox(color: Color, frame: Int) -> some View {
        color
            .overlay {
                Text("Frame \(frame + 1)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 160, height: 160)
    }
}
