import CoreGraphics
import UIKit

/// Session log of every document call plus the raw finger samples behind it, for studying how people draw.
/// Points are world coordinates (the `worldSize` square the document API takes); `t` is seconds since the session opened.
/// Replaying `ops` through a document built with the same `canvas` reproduces the drawing.
final class BonePaperRecorder {
    static let folder = "BonePaperRecordings"

    struct Op: Encodable {
        var op: String
        var t: Double
        var t1: Double?
        var input: String?
        var erase: Bool?
        var color: String?
        var size: Double?
        var opacity: Double?
        var zoom: Double?
        var at: [Double]?
        /// Stroke: `[x, y, t]` per document stamp; the first is the dot, each next one a segment from the previous.
        var points: [[Double]]?
        /// `[x, y, t]` coalesced touch samples of the whole gesture, including the slop before the stroke started.
        var raw: [[Double]]?
        /// Stroke: "commit" or "cancel".
        var end: String?
    }

    private struct Canvas: Encodable {
        var width: Int
        var height: Int
        var originX: Int
        var originY: Int
        var fixed: Bool
    }

    private struct Final: Encodable {
        var width: Int
        var height: Int
        var extraLeft: Int
        var extraTop: Int
    }

    private struct Session: Encodable {
        var version = 1
        var started: String
        var duration: Double
        var device: String
        var screenScale: Double
        var mode: String
        var worldSize: Int
        var sample: Int
        var canvas: Canvas
        var final: Final
        var paper: String?
        var boneStart: [Double]?
        var boneTip: [Double]?
        var base: String?
        var onion: String?
        var ops: [Op]
    }

    var zoom: CGFloat = 1
    var base: CGImage?

    private let canvas: Canvas
    private let started = Date()
    private let clock = ProcessInfo.processInfo.systemUptime
    private var ops: [Op] = []
    private var open: Op?
    private var pendingRaw: [[Double]] = []
    private var pendingInput: String?
    /// Between a one-finger touch-down and its end or abort; the rest of a pinch is not sampled.
    private var touching = false

    init(width: Int, height: Int, originX: Int, originY: Int, fixed: Bool, base: CGImage?) {
        canvas = Canvas(width: width, height: height, originX: originX, originY: originY, fixed: fixed)
        self.base = base
    }

    // MARK: Touches (draw view)

    func touchDown(_ samples: [(CGPoint, TimeInterval)], input: UITouch.TouchType) {
        pendingRaw = []
        pendingInput = Self.name(input)
        touching = true
        touchMoved(samples)
    }

    func touchMoved(_ samples: [(CGPoint, TimeInterval)]) {
        if !touching { return }
        let rows = samples.map { Self.row($0.0, t: $0.1 - clock) }
        if open != nil {
            open?.raw?.append(contentsOf: rows)
        } else {
            pendingRaw.append(contentsOf: rows)
        }
    }

    /// Gesture over. Samples no op took (a pen tap under the slop, a fill outside the page) are kept as "noop".
    func touchUp() {
        if touching, !pendingRaw.isEmpty {
            ops.append(Op(op: "noop", t: pendingRaw[0][2], input: pendingInput, raw: pendingRaw))
        }
        pendingRaw = []
        pendingInput = nil
        touching = false
    }

    /// Second finger: a pinch, not drawing.
    func touchAbort() {
        pendingRaw = []
        pendingInput = nil
        touching = false
    }

    // MARK: Document calls

    func begin(erase: Bool, opacity: CGFloat) {
        if open != nil {
            fatalError("BonePaperRecorder begin with an open stroke")
        }
        open = Op(
            op: "stroke",
            t: now(),
            input: pendingInput,
            erase: erase,
            opacity: Self.round(opacity, 1000),
            zoom: Self.round(zoom, 1000),
            points: [],
            raw: pendingRaw
        )
        pendingRaw = []
    }

    func dot(at point: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        guard var stroke = open, let points = stroke.points else {
            fatalError("BonePaperRecorder dot with no open stroke")
        }
        if !points.isEmpty || stroke.erase != erase {
            fatalError("BonePaperRecorder dot inside a stroke or erase mismatch")
        }
        stroke.color = erase ? nil : BonePaperColorStore.hex(from: color)
        stroke.size = Self.round(size, 100)
        stroke.points = [Self.row(point, t: now())]
        open = stroke
    }

    func line(from start: CGPoint, to end: CGPoint, color: UIColor, size: CGFloat, erase: Bool) {
        guard var stroke = open, let last = stroke.points?.last else {
            fatalError("BonePaperRecorder line with no dot")
        }
        if abs(last[0] - Double(start.x)) > 0.01 || abs(last[1] - Double(start.y)) > 0.01 {
            fatalError("BonePaperRecorder line from \(start) does not continue \(last)")
        }
        if stroke.size != Self.round(size, 100) || stroke.erase != erase
            || (!erase && stroke.color != BonePaperColorStore.hex(from: color)) {
            fatalError("BonePaperRecorder brush changed inside a stroke")
        }
        stroke.points?.append(Self.row(end, t: now()))
        open = stroke
    }

    func end() {
        close("commit")
    }

    func cancel() {
        close("cancel")
    }

    func fill(at point: CGPoint, color: UIColor, opacity: CGFloat) {
        if open != nil {
            fatalError("BonePaperRecorder fill with an open stroke")
        }
        ops.append(Op(
            op: "fill",
            t: now(),
            input: pendingInput,
            color: BonePaperColorStore.hex(from: color),
            opacity: Self.round(opacity, 1000),
            zoom: Self.round(zoom, 1000),
            at: [Self.round(point.x, 100), Self.round(point.y, 100)],
            raw: pendingRaw
        ))
        pendingRaw = []
    }

    func undo() {
        ops.append(Op(op: "undo", t: now()))
    }

    func redo() {
        ops.append(Op(op: "redo", t: now()))
    }

    // MARK: Saving

    /// Writes `Documents/BonePaperRecordings/<started>/` with `session.json`, `result.png`, and `base.png` / `onion.png` when present.
    func save(
        result: CGImage,
        onion: CGImage?,
        paper: UIColor?,
        boneStart: CGPoint?,
        boneTip: CGPoint?,
        width: Int,
        height: Int,
        extraLeft: Int,
        extraTop: Int
    ) {
        if open != nil {
            fatalError("BonePaperRecorder save with an open stroke")
        }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let dir = URL.documentsDirectory
            .appending(path: Self.folder)
            .appending(path: stamp.string(from: started))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fatalError("BonePaperRecorder mkdir \(dir.path): \(error)")
        }
        Self.writePNG(result, to: dir.appending(path: "result.png"))
        if let base {
            Self.writePNG(base, to: dir.appending(path: "base.png"))
        }
        if let onion {
            Self.writePNG(onion, to: dir.appending(path: "onion.png"))
        }
        let session = Session(
            started: ISO8601DateFormatter().string(from: started),
            duration: Self.round(now(), 1000),
            device: UIDevice.current.model + " " + UIDevice.current.systemVersion,
            screenScale: Double(UITraitCollection.current.displayScale),
            mode: paper != nil ? "sheet" : (boneStart != nil ? "bone" : "free"),
            worldSize: BonePaperDocument.maxSide,
            sample: BonePaperDocument.sample,
            canvas: canvas,
            final: Final(width: width, height: height, extraLeft: extraLeft, extraTop: extraTop),
            paper: paper.map { BonePaperColorStore.hex(from: $0) },
            boneStart: boneStart.map { [Double($0.x), Double($0.y)] },
            boneTip: boneTip.map { [Double($0.x), Double($0.y)] },
            base: base == nil ? nil : "base.png",
            onion: onion == nil ? nil : "onion.png",
            ops: ops
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            fatalError("BonePaperRecorder encode: \(error)")
        }
        do {
            try data.write(to: dir.appending(path: "session.json"))
        } catch {
            fatalError("BonePaperRecorder write session.json: \(error)")
        }
    }

    private func close(_ how: String) {
        guard var stroke = open else {
            fatalError("BonePaperRecorder \(how) with no open stroke")
        }
        stroke.end = how
        stroke.t1 = now()
        ops.append(stroke)
        open = nil
    }

    private func now() -> Double {
        Self.round(ProcessInfo.processInfo.systemUptime - clock, 10000)
    }

    private static func row(_ point: CGPoint, t: Double) -> [Double] {
        [round(point.x, 100), round(point.y, 100), round(t, 10000)]
    }

    private static func round(_ value: CGFloat, _ scale: Double) -> Double {
        round(Double(value), scale)
    }

    private static func round(_ value: Double, _ scale: Double) -> Double {
        (value * scale).rounded() / scale
    }

    private static func name(_ type: UITouch.TouchType) -> String {
        switch type {
        case .direct: "finger"
        case .pencil: "pencil"
        case .indirect: "indirect"
        case .indirectPointer: "pointer"
        @unknown default: "unknown"
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let data = UIImage(cgImage: image).pngData() else {
            fatalError("BonePaperRecorder PNG encode \(url.lastPathComponent)")
        }
        do {
            try data.write(to: url)
        } catch {
            fatalError("BonePaperRecorder write \(url.lastPathComponent): \(error)")
        }
    }
}
