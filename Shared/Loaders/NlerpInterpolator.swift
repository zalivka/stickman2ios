import CoreGraphics
import Foundation

enum NlerpInterpolator {
    private static let vectorEpsilon: CGFloat = 1e-4
    private static let minEdgeLength: CGFloat = 1e-4
    private static let twoPi: CGFloat = .pi * 2

    static func interpolate(from frame1: StickmanFrame, to frame2: StickmanFrame, duration: Int) -> [StickmanFrame] {
        if duration <= 0 {
            fatalError("NlerpInterpolator duration must be > 0, got \(duration)")
        }
        let excluded = exclude(frame1, frame2)
        var frames: [StickmanFrame] = []
        for step in 0..<duration {
            let t = CGFloat(step) / CGFloat(duration)
            var units: [StickmanUnit] = []
            for unit1 in frame1.units {
                if excluded.contains(unit1.name) {
                    continue
                }
                guard let unit2 = frame2.units.first(where: { $0.name == unit1.name }) else {
                    continue
                }
                units.append(inbetween(unit1: unit1, unit2: unit2, t: t))
            }
            let cameraT = CGFloat(step + 1) / CGFloat(duration + 1)
            var generated = StickmanFrame(
                id: -1,
                units: units,
                bgName: frame1.bgName,
                bgMove: frame1.bgMove,
                cameraMove: frame1.cameraMove.lerp(frame2.cameraMove, t: cameraT)
            )
            adjustSlavesPositions(frame1: frame1, frame2: frame2, generated: &generated)
            frames.append(generated)
        }
        frames.append(frame2)
        if frames.count != duration + 1 {
            fatalError("NlerpInterpolator expected \(duration + 1) frames, got \(frames.count)")
        }
        return frames
    }

    static func inbetween(unit1: StickmanUnit, unit2: StickmanUnit, t: CGFloat) -> StickmanUnit {
        let scale1 = validScale(unit1)
        let scale2 = validScale(unit2)
        let base1 = unit1.basePoint()
        let base2 = unit2.basePoint()
        let xVal = lerp(base1.x, base2.x, t)
        let yVal = lerp(base1.y, base2.y, t)
        let scaleVal = lerp(unit1.scale, unit2.scale, t)
        let alphaVal = min(max(lerp(unit1.alpha, unit2.alpha, t), 0), 1)

        if unit1.edges.isEmpty {
            var result = unit1
            result.translateAll(dx: xVal - base1.x, dy: yVal - base1.y)
            let moved = result.basePoint()
            result.scaleAt(pivotX: moved.x, pivotY: moved.y, target: scaleVal)
            result.alpha = alphaVal
            return result
        }

        var written: [Int: StickmanPoint] = [:]
        for edge in unit1.edges {
            guard unit2.edges.contains(where: {
                ($0.from == edge.from && $0.to == edge.to) || ($0.from == edge.to && $0.to == edge.from)
            }) else {
                fatalError("NlerpInterpolator unit '\(unit1.name)' missing edge \(edge.from)->\(edge.to)")
            }
            let start1 = unit1.point(id: edge.from)
            let end1 = unit1.point(id: edge.to)
            let start2 = unit2.point(id: edge.from)
            let end2 = unit2.point(id: edge.to)

            var startPoint: StickmanPoint
            if start1.isBase {
                startPoint = start1
            } else {
                guard let parent = written[edge.from] else {
                    fatalError("NlerpInterpolator unit '\(unit1.name)' missing parent \(edge.from)")
                }
                startPoint = parent
            }

            let length = interpolateEdgeLength(
                from: start1, to: end1, scale: scale1,
                otherFrom: start2, otherTo: end2, otherScale: scale2,
                t: t
            )
            let direction = interpolateDirection(
                from: start1, to: end1,
                otherFrom: start2, otherTo: end2,
                t: t
            )
            var endPoint = end1
            endPoint.x = startPoint.x + direction.x * length
            endPoint.y = startPoint.y + direction.y * length

            if start1.isBase {
                let dx = xVal - base1.x
                let dy = yVal - base1.y
                startPoint.x += dx
                startPoint.y += dy
                endPoint.x += dx
                endPoint.y += dy
                if written[startPoint.id] == nil {
                    written[startPoint.id] = startPoint
                }
            }

            endPoint.parentId = startPoint.id
            written[endPoint.id] = endPoint
        }

        let points = unit1.points.map { point -> StickmanPoint in
            guard let writtenPoint = written[point.id] else {
                fatalError("NlerpInterpolator unit '\(unit1.name)' dropped point \(point.id)")
            }
            return writtenPoint
        }
        var result = StickmanUnit(
            name: unit1.name,
            points: points,
            edges: [],
            scale: unit1.scale,
            alpha: unit1.alpha,
            arrange: unit1.arrange,
            flipped: unit1.flipped,
            unitType: unit1.unitType,
            bubble: unit1.bubble
        )
        result.link()
        let base = result.basePoint()
        result.scaleAt(pivotX: base.x, pivotY: base.y, target: scaleVal)
        result.alpha = alphaVal
        return result
    }

    private static func interpolateEdgeLength(
        from: StickmanPoint,
        to: StickmanPoint,
        scale: CGFloat,
        otherFrom: StickmanPoint,
        otherTo: StickmanPoint,
        otherScale: CGFloat,
        t: CGFloat
    ) -> CGFloat {
        let baseLen1 = unscaledLength(from: from, to: to, scale: scale)
        let baseLen2 = unscaledLength(from: otherFrom, to: otherTo, scale: otherScale)
        return lerp(baseLen1, baseLen2, t) * scale
    }

    private static func interpolateDirection(
        from: StickmanPoint,
        to: StickmanPoint,
        otherFrom: StickmanPoint,
        otherTo: StickmanPoint,
        t: CGFloat
    ) -> CGPoint {
        let len1 = hypot(to.x - from.x, to.y - from.y)
        let len2 = hypot(otherTo.x - otherFrom.x, otherTo.y - otherFrom.y)
        if len1 <= vectorEpsilon && len2 <= vectorEpsilon {
            return .zero
        }
        if len1 <= vectorEpsilon {
            return CGPoint(x: (otherTo.x - otherFrom.x) / len2, y: (otherTo.y - otherFrom.y) / len2)
        }
        if len2 <= vectorEpsilon {
            return CGPoint(x: (to.x - from.x) / len1, y: (to.y - from.y) / len1)
        }
        let angle1 = atan2(to.y - from.y, to.x - from.x)
        let angle2 = atan2(otherTo.y - otherFrom.y, otherTo.x - otherFrom.x)
        let angle = angle1 + normalizeAngle(angle2 - angle1) * t
        return CGPoint(x: cos(angle), y: sin(angle))
    }

    private static func unscaledLength(from: StickmanPoint, to: StickmanPoint, scale: CGFloat) -> CGFloat {
        max(hypot(to.x - from.x, to.y - from.y) / scale, minEdgeLength)
    }

    private static func validScale(_ unit: StickmanUnit) -> CGFloat {
        if unit.scale <= 0 {
            fatalError("NlerpInterpolator unit '\(unit.name)' scale is \(unit.scale)")
        }
        return unit.scale
    }

    private static func normalizeAngle(_ a: CGFloat) -> CGFloat {
        a - twoPi * floor((a + .pi) / twoPi)
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }

    private static func exclude(_ first: StickmanFrame, _ second: StickmanFrame) -> Set<String> {
        let names1 = Set(first.units.map(\.name))
        let names2 = Set(second.units.map(\.name))
        var excluded = names1.symmetricDifference(names2)
        for name in names2.subtracting(names1) {
            excluded.formUnion(second.slaves.allSlaves(of: name))
        }
        for name in names1.subtracting(names2) {
            excluded.formUnion(first.slaves.allSlaves(of: name))
        }
        return excluded
    }

    private static func adjustSlavesPositions(frame1: StickmanFrame, frame2: StickmanFrame, generated: inout StickmanFrame) {
        let enslaved = generated.units
            .filter { SlavesRegistry.attachment(of: $0) != nil }
            .sorted { SlavesRegistry.slaveDepth($0, in: generated.units) < SlavesRegistry.slaveDepth($1, in: generated.units) }
        for unit in enslaved {
            let attachment1 = SlavesRegistry.attachment(of: frame1.unit(named: unit.name))
            let attachment2 = SlavesRegistry.attachment(of: frame2.unit(named: unit.name))
            if attachment1 != attachment2 {
                guard let index = generated.units.firstIndex(where: { $0.name == unit.name }) else {
                    fatalError("NlerpInterpolator missing generated unit '\(unit.name)'")
                }
                generated.units[index].stripAttachment()
            } else {
                generated.moveUnitToMaster(named: unit.name)
            }
        }
        generated.refreshAttachments()
    }
}
