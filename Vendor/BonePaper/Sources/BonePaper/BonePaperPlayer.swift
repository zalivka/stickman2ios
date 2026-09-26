import QuartzCore
import SwiftUI
import UIKit

/// Plays a sheet-mode `session.json` back through a real document at the recorded pace, with a fingertip marker.
/// Strokes keep their own timing (sped up by `strokeSpeed`); idle gaps between ops are squeezed.
public struct BonePaperPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: BonePaperPlayer

    public init(session: Data) {
        _player = StateObject(wrappedValue: BonePaperPlayer(session: session))
    }

    public var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                Color(white: 0.78).ignoresSafeArea()
                BonePaperPlayerPage(document: player.document, player: player)
                    .padding(.horizontal, BonePaperChrome.tool + BonePaperChrome.pad * 2)
                    .padding(.vertical, BonePaperChrome.pad)
            }
            .overlay(alignment: .topLeading) {
                BonePaperBackButton(onBack: { dismiss() })
                    .padding(.top, safe.top)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: BonePaperChrome.pad) {
                    BonePaperPlayerButton(symbol: player.running ? "pause.fill" : "play.fill") {
                        player.toggle()
                    }
                    BonePaperPlayerButton(symbol: "arrow.counterclockwise") {
                        player.restart()
                    }
                }
                .padding(.trailing, safe.trailing + BonePaperChrome.pad)
                .padding(.bottom, safe.bottom + BonePaperChrome.pad)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { player.attach() }
        .onDisappear { player.detach() }
    }
}

private struct BonePaperPlayerButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: BonePaperChrome.tool, height: BonePaperChrome.tool)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct BonePaperPlayerPage: View {
    @ObservedObject var document: BonePaperDocument
    @ObservedObject var player: BonePaperPlayer

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / CGFloat(player.width), geo.size.height / CGFloat(player.height))
            let size = CGSize(width: CGFloat(player.width) * scale, height: CGFloat(player.height) * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            let view = { (world: CGPoint) in
                CGPoint(
                    x: origin.x + (world.x - CGFloat(player.originX)) * scale,
                    y: origin.y + (world.y - CGFloat(player.originY)) * scale
                )
            }
            ZStack(alignment: .topLeading) {
                Color(uiColor: player.paper)
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                Image(decorative: document.preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                if let ripple = player.ripple {
                    Circle()
                        .stroke(Color.white.opacity(0.8 * (1 - ripple.progress)), lineWidth: 3)
                        .frame(width: 16 + 70 * ripple.progress, height: 16 + 70 * ripple.progress)
                        .position(view(ripple.at))
                }
                if let finger = player.finger {
                    let side: CGFloat = finger.touching ? 20 : 24
                    Circle()
                        .fill(Color(white: 0.35).opacity(finger.touching ? 0.45 : 0.18))
                        .overlay(Circle().stroke(Color.white.opacity(finger.touching ? 0.9 : 0.5), lineWidth: 1.5))
                        .frame(width: side, height: side)
                        .opacity(finger.alpha)
                        .position(view(finger.at))
                        .animation(.easeOut(duration: 0.08), value: finger.touching)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

final class BonePaperPlayer: ObservableObject {
    /// Stroke playback rate; 1 is the recorded speed.
    static let strokeSpeed: Double = 1.2
    /// Idle gap between ops after squeezing: `min(gap, gapBase + gapShare * gap, gapMax)`.
    static let gapBase: Double = 0.25
    static let gapShare: Double = 0.4
    static let gapMax: Double = 0.9
    /// Time before the first touch, so the marker is seen arriving.
    static let leadIn: Double = 0.8
    /// The marker lands this long before a touch-down and hovers.
    static let hover: Double = 0.12
    static let tap: Double = 0.07
    static let rippleDuration: Double = 0.45
    static let fadeOut: Double = 0.6

    struct Finger {
        var at: CGPoint
        var touching: Bool
        var alpha: Double
    }

    struct Ripple {
        var at: CGPoint
        var born: CFTimeInterval
        var progress: CGFloat
    }

    private struct Stroke {
        var points: [CGPoint]
        var times: [Double]
        var color: UIColor
        var size: CGFloat
        var erase: Bool
        var opacity: CGFloat
        var cancel: Bool
    }

    private enum Step {
        case stroke(Stroke)
        case fill(at: CGPoint, time: Double, color: UIColor, opacity: CGFloat)
        case undo(time: Double)
        case redo(time: Double)

        var start: Double {
            switch self {
            case .stroke(let s): s.times[0]
            case .fill(_, let time, _, _): time
            case .undo(let time), .redo(let time): time
            }
        }

        /// Where the finger lands; undo/redo are toolbar taps, so the marker stays put.
        var point: CGPoint? {
            switch self {
            case .stroke(let s): s.points[0]
            case .fill(let at, _, _, _): at
            case .undo, .redo: nil
            }
        }
    }

    let width: Int
    let height: Int
    let originX: Int
    let originY: Int
    let paper: UIColor

    @Published private(set) var document: BonePaperDocument
    @Published private(set) var finger: Finger?
    @Published private(set) var ripple: Ripple?
    @Published private(set) var running = true

    private let sheet: BonePaperSheet
    private let steps: [Step]
    private var clock: Double = 0
    private var cursor = 0
    private var stamped = 0
    /// Where and when the finger last lifted, and whether that was a fill tap (shown pressed until `time`).
    private var lifted: (at: CGPoint, time: Double, tap: Bool)?
    private var link: CADisplayLink?
    private var lastStamp: CFTimeInterval?

    init(session data: Data) {
        let session: BonePaperSessionFile
        do {
            session = try JSONDecoder().decode(BonePaperSessionFile.self, from: data)
        } catch {
            fatalError("BonePaperPlayer session.json: \(error)")
        }
        if session.mode != "sheet" {
            fatalError("BonePaperPlayer plays sheet sessions only, got \(session.mode)")
        }
        if session.base != nil {
            fatalError("BonePaperPlayer does not load base.png")
        }
        if session.worldSize != BonePaperDocument.maxSide || session.sample != BonePaperDocument.sample {
            fatalError("BonePaperPlayer world \(session.worldSize) sample \(session.sample) differ from the editor")
        }
        guard let paperHex = session.paper else {
            fatalError("BonePaperPlayer sheet session without paper")
        }
        paper = UIColor(BonePaperColorStore.color(from: paperHex))
        width = session.canvas.width
        height = session.canvas.height
        originX = session.canvas.originX
        originY = session.canvas.originY
        sheet = BonePaperSheet(width: width, height: height, paper: paper)
        let document = BonePaperDocument(sheet: sheet)
        if document.originX != originX || document.originY != originY {
            fatalError("BonePaperPlayer origin (\(originX),\(originY)) != document (\(document.originX),\(document.originY))")
        }
        self.document = document
        steps = Self.timeline(session.ops)
    }

    func attach() {
        if link != nil { return }
        let link = CADisplayLink(target: BonePaperPlayerTicker(self), selector: #selector(BonePaperPlayerTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func detach() {
        link?.invalidate()
        link = nil
        lastStamp = nil
    }

    func toggle() {
        if cursor >= steps.count {
            restart()
            return
        }
        running.toggle()
    }

    func restart() {
        document = BonePaperDocument(sheet: sheet)
        clock = 0
        cursor = 0
        stamped = 0
        lifted = nil
        finger = nil
        ripple = nil
        running = true
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastStamp.map { now - $0 } ?? 0
        lastStamp = now
        if let current = ripple {
            let progress = CGFloat((CACurrentMediaTime() - current.born) / Self.rippleDuration)
            ripple = progress >= 1 ? nil : Ripple(at: current.at, born: current.born, progress: progress)
        }
        // A fill runs off the main thread; the clock waits for it like the user would.
        if !running || document.filling { return }
        clock += dt
        advance()
        updateFinger()
    }

    private func advance() {
        while cursor < steps.count {
            switch steps[cursor] {
            case .stroke(let s):
                if stamped == 0 {
                    if clock < s.times[0] { return }
                    document.beginStroke(erase: s.erase, opacity: s.opacity)
                    document.stampDotWorld(at: s.points[0], color: s.color, size: s.size, erase: s.erase)
                    stamped = 1
                }
                while stamped < s.points.count, s.times[stamped] <= clock {
                    document.stampWorld(
                        from: s.points[stamped - 1],
                        to: s.points[stamped],
                        color: s.color,
                        size: s.size,
                        erase: s.erase
                    )
                    stamped += 1
                }
                if stamped < s.points.count { return }
                if s.cancel {
                    document.cancelStroke()
                } else {
                    document.endStroke()
                }
                lifted = (s.points[s.points.count - 1], s.times[s.times.count - 1], false)
                stamped = 0
                cursor += 1
            case .fill(let at, let time, let color, let opacity):
                if clock < time { return }
                document.fillWorld(at: at, color: color, opacity: opacity)
                ripple = Ripple(at: at, born: CACurrentMediaTime(), progress: 0)
                lifted = (at, time + Self.tap, true)
                cursor += 1
                return
            case .undo(let time):
                if clock < time { return }
                document.undo()
                cursor += 1
            case .redo(let time):
                if clock < time { return }
                document.redo()
                cursor += 1
            }
        }
    }

    private func updateFinger() {
        if cursor >= steps.count {
            guard let lifted else { return }
            let alpha = 1 - (clock - lifted.time) / Self.fadeOut
            finger = alpha <= 0 ? nil : Finger(at: lifted.at, touching: false, alpha: alpha)
            if alpha <= 0 {
                running = false
            }
            return
        }
        let step = steps[cursor]
        if case .stroke(let s) = step, stamped > 0 {
            let i = stamped - 1
            var at = s.points[i]
            if stamped < s.points.count {
                let span = s.times[stamped] - s.times[i]
                let u = span > 0 ? CGFloat(min(1, max(0, (clock - s.times[i]) / span))) : 0
                at = CGPoint(
                    x: at.x + (s.points[stamped].x - at.x) * u,
                    y: at.y + (s.points[stamped].y - at.y) * u
                )
            }
            finger = Finger(at: at, touching: true, alpha: 1)
            return
        }
        guard let lifted else {
            guard let target = step.point else { return }
            let alpha = min(1, max(0, (clock - (step.start - Self.leadIn)) / Self.leadIn))
            finger = Finger(at: target, touching: false, alpha: alpha)
            return
        }
        if lifted.tap, clock < lifted.time {
            finger = Finger(at: lifted.at, touching: true, alpha: 1)
            return
        }
        guard let target = step.point else {
            finger = Finger(at: lifted.at, touching: false, alpha: 1)
            return
        }
        let arrive = max(lifted.time, step.start - Self.hover)
        let raw = arrive > lifted.time ? (clock - lifted.time) / (arrive - lifted.time) : 1
        let u = CGFloat(min(1, max(0, raw)))
        let eased = u * u * (3 - 2 * u)
        let dx = target.x - lifted.at.x
        let dy = target.y - lifted.at.y
        let distance = (dx * dx + dy * dy).squareRoot()
        var at = CGPoint(x: lifted.at.x + dx * eased, y: lifted.at.y + dy * eased)
        if distance > 1 {
            // A lifted finger travels in a shallow arc, bowed upward on the page.
            var nx = -dy / distance
            var ny = dx / distance
            if ny > 0 {
                nx = -nx
                ny = -ny
            }
            let bow = min(distance * 0.2, 60) * sin(.pi * eased)
            at.x += nx * bow
            at.y += ny * bow
        }
        finger = Finger(at: at, touching: false, alpha: 1)
    }

    /// Recorded ops to playback steps: stroke-internal time scaled by `strokeSpeed`, gaps squeezed.
    private static func timeline(_ ops: [BonePaperSessionFile.Op]) -> [Step] {
        var steps: [Step] = []
        var recordedEnd: Double?
        var playedEnd = leadIn
        for op in ops {
            let start: Double
            let end: Double
            switch op.op {
            case "stroke":
                guard let points = op.points, points.count >= 1 else {
                    fatalError("BonePaperPlayer stroke at \(op.t) has no points")
                }
                start = points[0][2]
                end = points[points.count - 1][2]
            case "fill":
                start = op.t
                end = op.t + tap
            case "undo", "redo":
                start = op.t
                end = op.t
            case "noop":
                continue
            default:
                fatalError("BonePaperPlayer unknown op \(op.op)")
            }
            let gap = recordedEnd.map { max(0, start - $0) } ?? 0
            let playedStart = recordedEnd == nil ? leadIn : playedEnd + min(gap, gapBase + gapShare * gap, gapMax)
            let played = { (t: Double) in playedStart + (t - start) / strokeSpeed }
            switch op.op {
            case "stroke":
                let points = op.points ?? []
                let erase = op.erase ?? false
                guard let size = op.size, let opacity = op.opacity else {
                    fatalError("BonePaperPlayer stroke at \(op.t) without size or opacity")
                }
                let color: UIColor
                if erase {
                    color = .clear
                } else {
                    guard let hex = op.color else {
                        fatalError("BonePaperPlayer pen stroke at \(op.t) without colour")
                    }
                    color = UIColor(BonePaperColorStore.color(from: hex))
                }
                steps.append(.stroke(Stroke(
                    points: points.map { CGPoint(x: $0[0], y: $0[1]) },
                    times: points.map { played($0[2]) },
                    color: color,
                    size: CGFloat(size),
                    erase: erase,
                    opacity: CGFloat(opacity),
                    cancel: op.end == "cancel"
                )))
            case "fill":
                guard let at = op.at, at.count == 2, let hex = op.color, let opacity = op.opacity else {
                    fatalError("BonePaperPlayer fill at \(op.t) without point, colour or opacity")
                }
                steps.append(.fill(
                    at: CGPoint(x: at[0], y: at[1]),
                    time: playedStart,
                    color: UIColor(BonePaperColorStore.color(from: hex)),
                    opacity: CGFloat(opacity)
                ))
            case "undo":
                steps.append(.undo(time: playedStart))
            default:
                steps.append(.redo(time: playedStart))
            }
            recordedEnd = end
            playedEnd = played(end)
        }
        return steps
    }
}

/// `CADisplayLink` retains its target; this breaks the cycle with the player.
private final class BonePaperPlayerTicker: NSObject {
    weak var player: BonePaperPlayer?

    init(_ player: BonePaperPlayer) {
        self.player = player
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let player else {
            link.invalidate()
            return
        }
        player.tick(link)
    }
}

/// The subset of `BonePaperRecorder`'s session.json the player needs.
struct BonePaperSessionFile: Decodable {
    struct Canvas: Decodable {
        var width: Int
        var height: Int
        var originX: Int
        var originY: Int
    }

    struct Op: Decodable {
        var op: String
        var t: Double
        var erase: Bool?
        var color: String?
        var size: Double?
        var opacity: Double?
        var at: [Double]?
        var points: [[Double]]?
        var end: String?
    }

    var mode: String
    var worldSize: Int
    var sample: Int
    var canvas: Canvas
    var paper: String?
    var base: String?
    var ops: [Op]
}
