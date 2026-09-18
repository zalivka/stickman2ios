import SwiftUI

struct PreviewSeekBar: View {
    static let width: CGFloat = 48

    @Binding var progress: Double

    var body: some View {
        GeometryReader { geo in
            Slider(
                value: Binding(
                    get: { min(max(progress, 0), 1) },
                    set: { progress = min(max($0, 0), 1) }
                ),
                in: 0...1
            )
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(-90))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(width: Self.width)
    }
}
