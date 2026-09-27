#if DEBUG
import SwiftUI

/// Ten-frame loop of the desert road driving forward. The sun stays put, behind the mesa.
struct RoadLoopScreen: View {
    private static let page = CGSize(width: 640, height: 480)
    private static let frames = 10
    private static let fps = 8.0
    private static let pictures: [CGImage] = (0..<frames).map { image($0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.2).ignoresSafeArea()
            GeometryReader { geo in
                let scale = min(geo.size.width / Self.page.width, geo.size.height / Self.page.height)
                let size = CGSize(width: Self.page.width * scale, height: Self.page.height * scale)
                TimelineView(.animation) { context in
                    let index = Int(context.date.timeIntervalSinceReferenceDate * Self.fps) % Self.frames
                    Canvas { context, _ in
                        context.scaleBy(x: scale, y: scale)
                        context.draw(
                            Image(decorative: Self.pictures[index], scale: 1),
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
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private static func image(_ index: Int) -> CGImage {
        let name = "frame_\(index)"
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
