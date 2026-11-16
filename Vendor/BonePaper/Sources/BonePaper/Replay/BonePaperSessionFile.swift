import Foundation
import QuartzCore

/// `CADisplayLink` retains its target; this breaks the cycle with the player.
final class BonePaperPlayerTicker: NSObject {
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
        var clear: Bool?
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
