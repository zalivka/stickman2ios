#if DEBUG
import SwiftUI

/// Line-boil preview: the snowy village, and the template T-Rex walking right then back.
/// The slider sets the boil rate. The walk runs on its own clock.
struct BoilDemoScreen: View {
    private static let page = CGSize(width: 640, height: 480)
    private static let variants = 3
    /// Poses per second. Independent of the boil slider.
    private static let walkFPS = 12.0

    private static let villageOrder = order()
    private static let trexOrder = order()
    private static let village: [CGImage] = (0..<variants).map { image("village_\($0)", "testdata/boil") }
    private static let walk = TrexWalk.load()

    @State private var fps: Double = 10
    @State private var boiling = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.2).ignoresSafeArea()
            VStack(spacing: 8) {
                GeometryReader { geo in
                    let scale = min(geo.size.width / Self.page.width, geo.size.height / Self.page.height)
                    let size = CGSize(width: Self.page.width * scale, height: Self.page.height * scale)
                    TimelineView(.animation) { context in
                        let time = context.date.timeIntervalSinceReferenceDate
                        let boilTick = Int(time * fps)
                        let walkIndex = Int(time * Self.walkFPS) % Self.walk.poses.count
                        Canvas { context, _ in
                            context.scaleBy(x: scale, y: scale)
                            let background = boiling
                                ? Self.village[Self.villageOrder[boilTick % Self.villageOrder.count]]
                                : Self.village[0]
                            context.draw(
                                Image(decorative: background, scale: 1),
                                in: CGRect(origin: .zero, size: Self.page)
                            )
                            Self.drawTrex(
                                Self.walk.poses[walkIndex],
                                boil: boiling ? Self.trexOrder[boilTick % Self.trexOrder.count] : nil,
                                context: &context
                            )
                        }
                        .frame(width: size.width, height: size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Toggle("Boil", isOn: $boiling).fixedSize()
                    Text("fps").frame(width: 40, alignment: .trailing)
                    Slider(value: $fps, in: 4...16)
                    Text(String(format: "%.0f", fps)).frame(width: 36, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: 480)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 8)
            FullscreenBackButton(besideMainPanel: false)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    /// `boil` nil draws the still copy of every part. Otherwise every part uses that boil copy.
    private static func drawTrex(_ pose: TrexWalk.Pose, boil: Int?, context: inout GraphicsContext) {
        for part in walk.parts {
            let start = pose.point(part.start)
            let end = pose.point(part.end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let xOff = part.ox * walk.k - walk.margin
            let yOff = part.oy * walk.k - walk.margin
            let picture = part.image(boil)
            context.drawLayer { ctx in
                ctx.translateBy(x: start.x, y: start.y)
                ctx.rotate(by: .radians(angle))
                if pose.flip {
                    ctx.translateBy(x: xOff, y: -yOff)
                    ctx.scaleBy(x: 1, y: -1)
                } else {
                    ctx.translateBy(x: xOff, y: yOff)
                }
                ctx.draw(Image(decorative: picture, scale: 1), at: .zero, anchor: .topLeading)
            }
        }
    }

    /// Boil frame order: no copy twice in a row, wrap included.
    private static func order() -> [Int] {
        var rng = SystemRandomNumberGenerator()
        var out: [Int] = []
        while out.count < 64 {
            let next = Int.random(in: 0..<variants, using: &rng)
            if next != out.last, out.count < 63 || next != out.first {
                out.append(next)
            }
        }
        return out
    }

    fileprivate static func image(_ name: String, _ directory: String) -> CGImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: directory) else {
            fatalError("BoilDemoScreen missing \(directory)/\(name).png")
        }
        do {
            return PNGImage.cgImage(from: try Data(contentsOf: url), name: "\(directory)/\(name).png")
        } catch {
            fatalError("BoilDemoScreen could not read \(url.path): \(error)")
        }
    }
}

/// `trex_walk.py` output: one PNG per bone per boil copy, and the walk poses in page px.
private struct TrexWalk: Decodable {
    struct Part: Decodable {
        var name: String
        var weight: Int
        var start: Int
        var end: Int
        var ox: Double
        var oy: Double
        var w: Int
        var h: Int

        /// Index 0 is the still copy; 1...3 are the boil copies.
        var images: [CGImage] = []

        func image(_ boil: Int?) -> CGImage {
            let index = boil.map { $0 + 1 } ?? 0
            if index < 0 || index >= images.count {
                fatalError("TrexWalk part \(name) has no image \(index)")
            }
            return images[index]
        }

        private enum CodingKeys: String, CodingKey {
            case name, weight, start, end, ox, oy, w, h
        }
    }

    struct Pose: Decodable {
        var flip: Bool
        var pts: [[Double]]

        func point(_ id: Int) -> CGPoint {
            guard let row = pts.first(where: { Int($0[0]) == id }), row.count == 3 else {
                fatalError("TrexWalk pose has no point \(id)")
            }
            return CGPoint(x: row[1], y: row[2])
        }
    }

    var k: Double
    var margin: Double
    var parts: [Part]
    var poses: [Pose]

    static func load() -> TrexWalk {
        guard let url = Bundle.main.url(forResource: "walk", withExtension: "json", subdirectory: "testdata/boil/trex") else {
            fatalError("BoilDemoScreen missing testdata/boil/trex/walk.json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            fatalError("BoilDemoScreen could not read \(url.path): \(error)")
        }
        let decoded: TrexWalk
        do {
            decoded = try JSONDecoder().decode(TrexWalk.self, from: data)
        } catch {
            fatalError("BoilDemoScreen walk.json: \(error)")
        }
        if decoded.poses.isEmpty || decoded.parts.isEmpty {
            fatalError("BoilDemoScreen walk.json has no poses or parts")
        }
        var walk = decoded
        walk.parts.sort { $0.weight < $1.weight }
        for i in walk.parts.indices {
            let name = walk.parts[i].name
            walk.parts[i].images = ["still", "0", "1", "2"].map {
                BoilDemoScreen.image("\(name)_\($0)", "testdata/boil/trex")
            }
        }
        return walk
    }
}
#endif
