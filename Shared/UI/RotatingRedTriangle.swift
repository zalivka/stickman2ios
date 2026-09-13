import SwiftUI

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct RotatingRedTriangle: View {
    /// Full turn duration in seconds.
    var period: TimeInterval = 2

    var body: some View {
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSinceReferenceDate / period
            Triangle()
                .fill(Color.red)
                .aspectRatio(1, contentMode: .fit)
                .rotationEffect(.degrees(turns * 360))
        }
    }
}

#Preview {
    RotatingRedTriangle()
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
