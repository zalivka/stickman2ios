#if DEBUG
import SwiftUI

/// The ship background, three re-traced copies, cycling so the lines boil.
struct ShipBoilScreen: View {
    private static let page = CGSize(width: 640, height: 480)
    private static let copies = 3
    private static let boilFPS = 10.0
    private static let boilOrder = order()
    private static let pictures: [CGImage] = (0..<copies).map { image($0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.2).ignoresSafeArea()
            GeometryReader { geo in
                let scale = min(geo.size.width / Self.page.width, geo.size.height / Self.page.height)
                let size = CGSize(width: Self.page.width * scale, height: Self.page.height * scale)
                TimelineView(.animation) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate * Self.boilFPS)
                    let copy = Self.boilOrder[tick % Self.boilOrder.count]
                    Canvas { context, _ in
                        context.scaleBy(x: scale, y: scale)
                        context.draw(
                            Image(decorative: Self.pictures[copy], scale: 1),
                            in: CGRect(origin: .zero, size: Self.page)
                        )
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            FullscreenBackButton(besideMainPanel: false)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// No copy twice in a row, including the wrap back to the first.
    private static func order() -> [Int] {
        var rng = SystemRandomNumberGenerator()
        var out: [Int] = []
        while out.count < 64 {
            let next = Int.random(in: 0..<copies, using: &rng)
            if next != out.last, out.count < 63 || next != out.first {
                out.append(next)
            }
        }
        return out
    }

    private static func image(_ copy: Int) -> CGImage {
        let name = "ship_\(copy)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "testdata/ship") else {
            fatalError("ShipBoilScreen missing testdata/ship/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "testdata/ship/\(name).png")
        } catch {
            fatalError("ShipBoilScreen could not read \(url.path): \(error)")
        }
    }
}
#endif
