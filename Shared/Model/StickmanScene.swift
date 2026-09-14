import CoreGraphics

enum Attachable {
    case none
    case master
    case slave
}

struct SlaveAttachment: Equatable {
    var masterName: String
    var masterPointId: Int
}

struct StickmanPoint: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var isBase: Bool
    var parentId: Int?
    var attachable: Attachable = .none
    var attachedMasterName: String? = nil
    var attachedMasterPointId: Int? = nil
    var semanticName: String? = nil
    var fixed: Bool = false
    var stretchable: Bool = false
    var kinematicStart: Bool = false
    var kinematicStop: Bool = false
}

struct StickmanEdge {
    let from: Int
    let to: Int
}

enum StickmanUnitType {
    case unit
    case bubble
}

struct StickmanUnit {
    var name: String
    var points: [StickmanPoint]
    var edges: [StickmanEdge]
    var scale: CGFloat = 1
    var alpha: CGFloat = 1
    var arrange: Int = 0
    var flipped: Bool = false
    var assetsState: Int = 0
    var unitType: StickmanUnitType = .unit
    var bubble: BubbleMeta? = nil

    func point(id: Int) -> StickmanPoint {
        guard let point = points.first(where: { $0.id == id }) else {
            fatalError("StickmanUnit '\(name)' missing point \(id)")
        }
        return point
    }

    /// Adds a child tip at `dest` under `parentId` and rebuilds edges. Returns the new point id.
    mutating func addPointWithEdge(parentId: Int, destX: CGFloat, destY: CGFloat) -> Int {
        _ = point(id: parentId)
        let newId = (points.map(\.id).max() ?? 0) + 1
        if points.contains(where: { $0.id == newId }) {
            fatalError("StickmanUnit '\(name)' already has point \(newId)")
        }
        points.append(
            StickmanPoint(id: newId, x: destX, y: destY, isBase: false, parentId: parentId)
        )
        link()
        return newId
    }

    /// Deletes `id` and every descendant. Base point is not deletable.
    mutating func deletePointSubtree(id: Int) {
        let target = point(id: id)
        if target.isBase {
            fatalError("StickmanUnit '\(name)' cannot delete base \(id)")
        }
        let remove = Set([id] + descendants(of: id))
        points.removeAll { remove.contains($0.id) }
        link()
    }

    /// Parent→child edge that ends at `id`, if any.
    func upperEdge(of id: Int) -> StickmanEdge? {
        edges.first { $0.to == id }
    }

    mutating func link() {
        let bases = points.filter(\.isBase)
        if bases.count != 1 {
            fatalError("StickmanUnit '\(name)' must have exactly one base, got \(bases.map(\.id))")
        }
        if bases[0].parentId != nil {
            fatalError("StickmanUnit '\(name)' base \(bases[0].id) has parentId")
        }
        var byId: [Int: StickmanPoint] = [:]
        for point in points {
            if byId[point.id] != nil {
                fatalError("StickmanUnit '\(name)' duplicate point \(point.id)")
            }
            byId[point.id] = point
        }
        for point in points {
            if point.isBase { continue }
            guard let parentId = point.parentId else {
                fatalError("StickmanUnit '\(name)' point \(point.id) has no parent")
            }
            if byId[parentId] == nil {
                fatalError("StickmanUnit '\(name)' point \(point.id) parent \(parentId) missing")
            }
        }
        var edges: [StickmanEdge] = []
        var seen: Set<Int> = []
        func walk(_ id: Int) {
            if seen.contains(id) {
                fatalError("StickmanUnit '\(name)' cycle at \(id)")
            }
            seen.insert(id)
            for child in points where child.parentId == id {
                edges.append(StickmanEdge(from: id, to: child.id))
                walk(child.id)
            }
        }
        walk(bases[0].id)
        if seen.count != points.count {
            let missing = points.map(\.id).filter { !seen.contains($0) }
            fatalError("StickmanUnit '\(name)' disconnected points \(missing)")
        }
        self.edges = edges
    }

    func descendants(of id: Int) -> [Int] {
        _ = point(id: id)
        var result: [Int] = []
        var seen: Set<Int> = [id]
        var queue = [id]
        while let current = queue.first {
            queue.removeFirst()
            for edge in edges where edge.from == current {
                if seen.contains(edge.to) {
                    fatalError("StickmanUnit '\(name)' cycle at \(edge.to)")
                }
                seen.insert(edge.to)
                result.append(edge.to)
                queue.append(edge.to)
            }
        }
        return result
    }

    mutating func translateAll(dx: CGFloat, dy: CGFloat) {
        for i in points.indices {
            points[i].x += dx
            points[i].y += dy
        }
    }

    mutating func placeInScene(width: CGFloat, height: CGFloat, scale factor: CGFloat) {
        if width <= 0 || height <= 0 {
            fatalError("StickmanUnit '\(name)' scene size \(width)x\(height)")
        }
        if factor <= 0 {
            fatalError("StickmanUnit '\(name)' place scale is \(factor)")
        }
        translateAll(dx: width / 2, dy: height / 2)
        let base = basePoint()
        scaleBy(pivotX: base.x, pivotY: base.y, factor: factor)
    }

    mutating func rotateAroundParent(id: Int, destX: CGFloat, destY: CGFloat) {
        let grabbed = point(id: id)
        guard let parentId = grabbed.parentId else {
            fatalError("StickmanUnit '\(name)' point \(id) has no parent")
        }
        let parent = point(id: parentId)
        let dx = destX - parent.x
        let dy = destY - parent.y
        if hypot(dx, dy) < 1e-6 { return }
        let dAngle = atan2(dy, dx) - atan2(grabbed.y - parent.y, grabbed.x - parent.x)
        let transform = CGAffineTransform.identity
            .translatedBy(x: parent.x, y: parent.y)
            .rotated(by: dAngle)
            .translatedBy(x: -parent.x, y: -parent.y)
        for rotateId in [id] + descendants(of: id) {
            guard let index = points.firstIndex(where: { $0.id == rotateId }) else {
                fatalError("StickmanUnit '\(name)' missing point \(rotateId)")
            }
            let p = CGPoint(x: points[index].x, y: points[index].y).applying(transform)
            points[index].x = p.x
            points[index].y = p.y
        }
    }

    mutating func drag(id: Int, destX: CGFloat, destY: CGFloat) {
        if point(id: id).isBase {
            translateAll(dx: destX - point(id: id).x, dy: destY - point(id: id).y)
        } else {
            rotateAroundParent(id: id, destX: destX, destY: destY)
        }
    }

    mutating func movePointAndDescendants(id: Int, destX: CGFloat, destY: CGFloat) {
        let grabbed = point(id: id)
        if grabbed.isBase {
            return
        }
        let dx = destX - grabbed.x
        let dy = destY - grabbed.y
        for moveId in [id] + descendants(of: id) {
            guard let index = points.firstIndex(where: { $0.id == moveId }) else {
                fatalError("StickmanUnit '\(name)' missing point \(moveId)")
            }
            points[index].x += dx
            points[index].y += dy
        }
    }

    func basePoint() -> StickmanPoint {
        let bases = points.filter(\.isBase)
        if bases.count != 1 {
            fatalError("StickmanUnit '\(name)' must have exactly one base, got \(bases.map(\.id))")
        }
        return bases[0]
    }

    func axisBounds() -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        if points.isEmpty {
            fatalError("StickmanUnit '\(name)' has no points")
        }
        var minX = points.map(\.x).min()!
        var maxX = points.map(\.x).max()!
        var minY = points.map(\.y).min()!
        var maxY = points.map(\.y).max()!
        if maxX - minX < 60 {
            minX -= 30
            maxX += 30
        }
        if maxY - minY < 60 {
            minY -= 30
            maxY += 30
        }
        return (minX, minY, maxX, maxY)
    }

    func handlerCenters(sceneScale: CGFloat) -> (move: CGPoint, rotate: CGPoint, scale: CGPoint) {
        if sceneScale <= 0 {
            fatalError("StickmanUnit '\(name)' handler sceneScale is \(sceneScale)")
        }
        let bb = axisBounds()
        let offset = 80 / sceneScale
        let corner = offset / 1.5
        return (
            move: CGPoint(x: (bb.minX + bb.maxX) / 2, y: bb.maxY + offset),
            rotate: CGPoint(x: bb.minX - corner, y: bb.minY - corner),
            scale: CGPoint(x: bb.maxX + corner, y: bb.minY - corner)
        )
    }

    mutating func scaleBy(pivotX: CGFloat, pivotY: CGFloat, factor: CGFloat) {
        for i in points.indices {
            let xDiff = (pivotX - points[i].x) * factor
            let yDiff = (pivotY - points[i].y) * factor
            points[i].x = pivotX - xDiff
            points[i].y = pivotY - yDiff
        }
        scale *= factor
    }

    mutating func scaleAt(pivotX: CGFloat, pivotY: CGFloat, target: CGFloat) {
        if scale <= 0 {
            fatalError("StickmanUnit '\(name)' scale is \(scale)")
        }
        if target <= 0 {
            fatalError("StickmanUnit '\(name)' target scale is \(target)")
        }
        scaleBy(pivotX: pivotX, pivotY: pivotY, factor: 1 / scale)
        scale = target
        for i in points.indices {
            let xDiff = (pivotX - points[i].x) * scale
            let yDiff = (pivotY - points[i].y) * scale
            points[i].x = pivotX - xDiff
            points[i].y = pivotY - yDiff
        }
    }

    mutating func rotate(radians: CGFloat, pivotX: CGFloat, pivotY: CGFloat) {
        let transform = CGAffineTransform.identity
            .translatedBy(x: pivotX, y: pivotY)
            .rotated(by: radians)
            .translatedBy(x: -pivotX, y: -pivotY)
        for i in points.indices {
            let p = CGPoint(x: points[i].x, y: points[i].y).applying(transform)
            points[i].x = p.x
            points[i].y = p.y
        }
    }

    func handlerRotateDiff(handler: CGPoint) -> CGFloat {
        if edges.isEmpty {
            fatalError("StickmanUnit '\(name)' has no edges for rotate handler")
        }
        let base = basePoint()
        let handlerAngle = atan2(handler.y - base.y, handler.x - base.x)
        let from = point(id: edges[0].from)
        let to = point(id: edges[0].to)
        let edgeAngle = atan2(to.y - from.y, to.x - from.x)
        return edgeAngle - handlerAngle
    }

    mutating func stripAttachment() {
        guard let index = points.firstIndex(where: \.isBase) else {
            fatalError("StickmanUnit '\(name)' has no base")
        }
        points[index].attachedMasterName = nil
        points[index].attachedMasterPointId = nil
    }

    mutating func rotateToHandler(handler: CGPoint, constDiff: CGFloat) {
        if edges.isEmpty {
            fatalError("StickmanUnit '\(name)' has no edges for rotate handler")
        }
        let base = basePoint()
        let pivotAngle = atan2(handler.y - base.y, handler.x - base.x)
        let from = point(id: edges[0].from)
        let to = point(id: edges[0].to)
        let edgeAngle = atan2(to.y - from.y, to.x - from.x)
        rotate(radians: constDiff - (edgeAngle - pivotAngle), pivotX: base.x, pivotY: base.y)
    }

    mutating func nextState(states: [Int], current: Int, backward: Bool, loop: Bool) -> (state: Int, backward: Bool) {
        var states = states
        if states.isEmpty {
            fatalError("StickmanUnit '\(name)' has no asset states")
        }
        let currentState = states.contains(current) ? current : states[0]
        guard let currentIndex = states.firstIndex(of: currentState) else {
            fatalError("StickmanUnit '\(name)' missing state \(currentState)")
        }
        rotateStates(&states, by: backward ? 1 : -1)
        let newState = states[currentIndex]
        assetsState = newState
        var nextBackward = backward
        if loop {
            if backward && newState == states.min() {
                nextBackward = false
            } else if !backward && newState == states.max() {
                nextBackward = true
            }
        }
        return (newState, nextBackward)
    }

    private func rotateStates(_ states: inout [Int], by distance: Int) {
        let count = states.count
        if count == 0 {
            return
        }
        let shift = ((distance % count) + count) % count
        states = Array(states.suffix(shift) + states.prefix(count - shift))
    }
}

struct StickmanFrame {
    var id: Int
    var units: [StickmanUnit]
    var bgName: String? = nil
    var bgMove: PictureMove = .identity
    var cameraMove: PictureMove = .identity
    var originFrameIndex: Int = 0
    var slaves = SlavesRegistry()

    func unit(named name: String) -> StickmanUnit {
        guard let unit = units.first(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        return unit
    }

    mutating func refreshAttachments() {
        slaves.populate(units: units)
    }

    mutating func moveUnitToMaster(named name: String) {
        guard let index = units.firstIndex(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        guard let attachment = SlavesRegistry.attachment(of: units[index]) else {
            return
        }
        let master = unit(named: attachment.masterName)
        let target = master.point(id: attachment.masterPointId)
        let base = units[index].basePoint()
        units[index].translateAll(dx: target.x - base.x, dy: target.y - base.y)
    }

    func uniqueName(for name: String) -> String {
        UnitName.unique(base: name, existing: units.map(\.name))
    }

    mutating func addCopy(_ src: StickmanUnit, name: String, at point: CGPoint, scale: CGFloat) {
        if scale <= 0 {
            fatalError("StickmanFrame \(id) addCopy scale is \(scale)")
        }
        if units.contains(where: { $0.name == name }) {
            fatalError("StickmanFrame \(id) already has unit '\(name)'")
        }
        var copy = src
        copy.name = name
        copy.arrange = (units.map(\.arrange).max() ?? -1) + 1
        copy.translateAll(dx: point.x, dy: point.y)
        let base = copy.basePoint()
        copy.scaleBy(pivotX: base.x, pivotY: base.y, factor: scale)
        units.append(copy)
    }
}

enum UnitName {
    static func number(_ name: String) -> Int {
        guard let hash = name.firstIndex(of: "#") else { return 0 }
        let rest = name[name.index(after: hash)...]
        guard let value = Int(rest) else {
            fatalError("UnitName '\(name)' has non-integer number")
        }
        return value
    }

    static func unique(base: String, existing: [String]) -> String {
        if !existing.contains(base) {
            let n = number(base)
            let pure = UnitAssets.removeNumber(base)
            return n == 0 ? pure : "\(pure)#\(n)"
        }
        let pure = UnitAssets.removeNumber(base)
        let maxN = existing
            .filter { UnitAssets.removeNumber($0) == pure }
            .map(number)
            .max() ?? 0
        let next = maxN + 1
        return next == 0 ? pure : "\(pure)#\(next)"
    }
}

struct StickmanScene {
    var width: CGFloat
    var height: CGFloat
    var frames: [StickmanFrame]
    var currentIndex: Int
    var interframes: Int = 36
    var noInterpolation: Bool = false
    var noInterpolationFrames: Int = 0
    var unitAnimations: [String: FBFAnimation] = [:]

    var currentFrame: StickmanFrame {
        if frames.isEmpty {
            fatalError("StickmanScene has no frames")
        }
        if currentIndex < 0 || currentIndex >= frames.count {
            fatalError("StickmanScene currentIndex \(currentIndex) out of \(frames.count)")
        }
        return frames[currentIndex]
    }
}
