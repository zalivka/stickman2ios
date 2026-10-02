#if DEBUG
import SwiftUI

/// Ten-frame loop of the desert road driving forward. The sun stays put, behind the mesa.
/// Each frame has three re-traced copies. The road advances at `fps`; the lines boil on their own clock.
struct RoadLoopScreen: View {
    private static let page = CGSize(width: 640, height: 480)
    private static let frames = 10
    private static let copies = 3
    private static let fps = 8.0
    private static let boilFPS = 10.0
    private static let boilOrder = order()
    private static let pictures: [[CGImage]] = (0..<frames).map { frame in
        (0..<copies).map { image(frame, $0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.2).ignoresSafeArea()
            GeometryReader { geo in
                let scale = min(geo.size.width / Self.page.width, geo.size.height / Self.page.height)
                let size = CGSize(width: Self.page.width * scale, height: Self.page.height * scale)
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let index = Int(time * Self.fps) % Self.frames
                    let boil = Self.boilOrder[Int(time * Self.boilFPS) % Self.boilOrder.count]
                    Canvas { context, _ in
                        context.scaleBy(x: scale, y: scale)
                        context.draw(
                            Image(decorative: Self.pictures[index][boil], scale: 1),
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

    private static func image(_ frame: Int, _ copy: Int) -> CGImage {
        let name = "frame_\(frame)_\(copy)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "testdata/road") else {
            fatalError("RoadLoopScreen missing testdata/road/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "testdata/road/\(name).png")
        } catch {
            fatalError("RoadLoopScreen could not read \(url.path): \(error)")
        }
    }
}
#endif
