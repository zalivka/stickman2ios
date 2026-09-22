import CoreGraphics

enum Attachable: Hashable {
    case none
    case master
    case slave
}

struct SlaveAttachment: Equatable, Hashable {
    var masterName: String
    var masterPointId: Int
}

struct MasterTarget: Equatable {
    var unitName: String
    var pointId: Int
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
    /// Android `Unit.ATTACH_RADIUS`. Scene-unit nudge on detach.
    static let attachRadius: CGFloat = 25
    /// Red/green hold circles, in screen points. Snap distance matches the circle.
    static let exposeMarkerRadius: CGFloat = attachRadius / 1.5

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

    /// Gallery attach: new child at `length` from parent, angled like Android `EditUnit.addPointWithEdge`.
    mutating func addGalleryBonePoint(parentId: Int, length: CGFloat = 200) -> Int {
        let parent = point(id: parentId)
        var dx: CGFloat = 150
        var dy: CGFloat = 0
        if let upper = upperEdge(of: parentId) {
            let start = point(id: upper.from)
            let end = point(id: upper.to)
            let baseDeg = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
            let angleDeg = baseDeg + CGFloat(Int.random(in: 0..<12)) * 30
            let rads = angleDeg * .pi / 180
            // Match Android: dx = sin(θ) * 50, dy = cos(θ) * 50
            dx = sin(rads) * 50
            dy = cos(rads) * 50
        }
        let dist = hypot(dx, dy)
        if dist < 0.001 {
            fatalError("StickmanUnit '\(name)' gallery bone direction is zero")
        }
        let scale = length / dist
        return addPointWithEdge(
            parentId: parentId,
            destX: parent.x + dx * scale,
            destY: parent.y + dy * scale
        )
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

    /// Android `EditPointDialog` Apply: attachable + invisible (`fixed`). Slave is base-only.
    mutating func applyPointProps(id: Int, attachable: Attachable, fixed: Bool) {
        guard let index = points.firstIndex(where: { $0.id == id }) else {
            fatalError("StickmanUnit '\(name)' missing point \(id)")
        }
        let isBase = points[index].isBase
        if attachable == .slave && !isBase {
            fatalError("StickmanUnit '\(name)' slave only on base, got point \(id)")
        }
        points[index].fixed = isBase ? false : fixed
        points[index].attachable = attachable
    }

    /// Android `Frame.canBeDragged` — Invisible points and enslaved bases are not grab handles.
    func canBeDragged(_ point: StickmanPoint) -> Bool {
        if point.fixed {
            return false
        }
        if point.isBase && SlavesRegistry.isEnslaved(self) {
            return false
        }
        return true
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

    /// Android `Unit.flipBones` — mirror X across `axisX`. Free unit keeps its base.
    mutating func flipBones(around axisX: CGFloat) {
        let keepBase = !SlavesRegistry.isEnslaved(self)
        for i in points.indices {
            if points[i].isBase && keepBase {
                continue
            }
            points[i].x = axisX + (axisX - points[i].x)
        }
    }

    mutating func flipBitmaps() {
        flipped.toggle()
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

    /// Copy interpolated pose onto this instance; keep attachment / identity fields.
    mutating func applyPose(from other: StickmanUnit) {
        if name != other.name {
            fatalError("StickmanUnit '\(name)' applyPose from '\(other.name)'")
        }
        for i in points.indices {
            guard let src = other.points.first(where: { $0.id == points[i].id }) else {
                fatalError("StickmanUnit '\(name)' applyPose missing point \(points[i].id)")
            }
            points[i].x = src.x
            points[i].y = src.y
        }
        scale = other.scale
        alpha = other.alpha
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

    /// Android `Unit.setAlpha(alpha, true)` — this unit and its slaves.
    mutating func setUnitAlpha(_ alpha: CGFloat, unitNamed name: String) {
        if alpha < 0 || alpha > 1 {
            fatalError("StickmanFrame \(id) opacity \(alpha) for '\(name)'")
        }
        guard units.contains(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) opacity missing '\(name)'")
        }
        refreshAttachments()
        let names = [name] + slaves.allSlaves(of: name)
        for slaveName in names {
            guard let index = units.firstIndex(where: { $0.name == slaveName }) else {
                fatalError("StickmanFrame \(id) opacity missing slave '\(slaveName)'")
            }
            units[index].alpha = alpha
        }
    }

    /// Android `Unit.flip` — mirror this unit and its slaves across this unit's base X.
    mutating func flipUnit(named name: String) {
        guard let source = units.first(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) flip missing '\(name)'")
        }
        refreshAttachments()
        let axisX = source.basePoint().x
        let names = [name] + slaves.allSlaves(of: name)
        for slaveName in names {
            guard let index = units.firstIndex(where: { $0.name == slaveName }) else {
                fatalError("StickmanFrame \(id) flip missing slave '\(slaveName)'")
            }
            units[index].flipBones(around: axisX)
            units[index].flipBitmaps()
        }
        refreshAttachments()
    }

    mutating func deleteConnectedUnit(named name: String) {
        guard let victim = units.first(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        refreshAttachments()
        let names = Set([victim.name] + slaves.allSlaves(of: victim.name))
        units.removeAll { names.contains($0.name) }
        refreshAttachments()
    }

    func canRearrange(unitNamed name: String, forward: Bool) -> Bool {
        guard let unit = units.first(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        let boundary = forward ? units.map(\.arrange).max() : units.map(\.arrange).min()
        guard let boundary else {
            fatalError("StickmanFrame \(id) has no units")
        }
        return forward ? unit.arrange < boundary : unit.arrange > boundary
    }

    mutating func rearrange(unitNamed name: String, forward: Bool) {
        guard let index = units.firstIndex(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        guard canRearrange(unitNamed: name, forward: forward) else { return }
        let oldArrange = units[index].arrange
        let newArrange = oldArrange + (forward ? 1 : -1)
        if let swapIndex = units.firstIndex(where: { $0.arrange == newArrange }) {
            units[swapIndex].arrange = oldArrange
        }
        units[index].arrange = newArrange
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

    /// Android `Frame.findCloseMasterPoint` plus `Unit.canAttachTo`. Nearest vacant master inside `radius`.
    func nearestAttachTarget(for name: String, radius: CGFloat) -> MasterTarget? {
        if radius <= 0 {
            fatalError("StickmanFrame \(id) attach radius \(radius)")
        }
        guard let slave = units.first(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) missing unit '\(name)'")
        }
        guard SlavesRegistry.isStraying(slave) else {
            return nil
        }
        let base = slave.basePoint()
        var best: (target: MasterTarget, dist: CGFloat)?
        for other in units where other.name != slave.name {
            for point in other.points where point.attachable == .master {
                let target = MasterTarget(unitName: other.name, pointId: point.id)
                guard canAttach(slave, to: target) else { continue }
                let dist = hypot(point.x - base.x, point.y - base.y)
                if dist < radius {
                    if let current = best {
                        if dist < current.dist {
                            best = (target, dist)
                        }
                    } else {
                        best = (target, dist)
                    }
                }
            }
        }
        return best?.target
    }

    func canAttach(_ slave: StickmanUnit, to target: MasterTarget) -> Bool {
        guard let master = units.first(where: { $0.name == target.unitName }) else {
            return false
        }
        guard master.points.contains(where: { $0.id == target.pointId && $0.attachable == .master }) else {
            return false
        }
        guard isMasterVacant(target) else {
            return false
        }
        let connected = SlavesRegistry.allConnected(of: slave, in: units)
        return !connected.contains(where: { $0.name == target.unitName })
    }

    /// Android `Unit.doAttachTo` — snap this straying unit and its slaves onto the master point.
    mutating func attach(named name: String, to target: MasterTarget) -> Bool {
        guard let index = units.firstIndex(where: { $0.name == name }) else {
            return false
        }
        guard SlavesRegistry.isStraying(units[index]) else {
            return false
        }
        guard canAttach(units[index], to: target) else {
            return false
        }
        guard let master = units.first(where: { $0.name == target.unitName }),
              let point = master.points.first(where: { $0.id == target.pointId })
        else {
            return false
        }
        guard let baseIndex = units[index].points.firstIndex(where: \.isBase) else {
            fatalError("StickmanFrame \(id) '\(name)' has no base")
        }
        units[index].points[baseIndex].attachedMasterName = target.unitName
        units[index].points[baseIndex].attachedMasterPointId = target.pointId
        let base = units[index].basePoint()
        shiftUnitAndSlaves(named: name, dx: point.x - base.x, dy: point.y - base.y)
        return true
    }

    /// Android `Unit.detachAndShift`.
    mutating func detachAndShift(named name: String) -> Bool {
        guard let index = units.firstIndex(where: { $0.name == name }) else {
            return false
        }
        guard SlavesRegistry.isEnslaved(units[index]) else {
            return false
        }
        units[index].stripAttachment()
        shiftUnitAndSlaves(
            named: name,
            dx: StickmanUnit.attachRadius,
            dy: StickmanUnit.attachRadius
        )
        return true
    }

    private func isMasterVacant(_ target: MasterTarget) -> Bool {
        !units.contains { unit in
            guard let attachment = SlavesRegistry.attachment(of: unit) else { return false }
            return attachment.masterName == target.unitName && attachment.masterPointId == target.pointId
        }
    }

    /// Slaves only. The named unit is already at its new pose.
    mutating func shiftSlaves(of name: String, dx: CGFloat, dy: CGFloat) {
        if dx == 0 && dy == 0 { return }
        refreshAttachments()
        for slaveName in slaves.allSlaves(of: name) {
            guard let index = units.firstIndex(where: { $0.name == slaveName }) else {
                fatalError("StickmanFrame \(id) shift missing '\(slaveName)'")
            }
            units[index].translateAll(dx: dx, dy: dy)
        }
    }

    private mutating func shiftUnitAndSlaves(named name: String, dx: CGFloat, dy: CGFloat) {
        guard let index = units.firstIndex(where: { $0.name == name }) else {
            fatalError("StickmanFrame \(id) shift missing '\(name)'")
        }
        units[index].translateAll(dx: dx, dy: dy)
        shiftSlaves(of: name, dx: dx, dy: dy)
    }

    /// Android `applyMatrix(..., includingSlaves)` and `PointManipulator` — slaves ride the master point.
    mutating func followAttachedSlaves(old: StickmanUnit, new: StickmanUnit) {
        if old.name != new.name {
            fatalError("StickmanFrame \(id) follow renamed '\(old.name)' to '\(new.name)'")
        }
        for point in old.points where !new.points.contains(where: { $0.id == point.id }) {
            fatalError("StickmanFrame \(id) '\(new.name)' lost point \(point.id)")
        }
        refreshAttachments()
        let slaveNames = slaves.allSlaves(of: new.name)
        if slaveNames.isEmpty { return }

        if let shift = Self.translation(from: old, to: new) {
            if shift.dx == 0 && shift.dy == 0 { return }
            translateUnits(slaveNames, dx: shift.dx, dy: shift.dy)
            return
        }
        if new.scale != old.scale {
            if old.scale <= 0 {
                fatalError("StickmanFrame \(id) '\(new.name)' scale is \(old.scale)")
            }
            followScale(slaveNames, factor: new.scale / old.scale)
            return
        }
        let pivot = new.basePoint()
        let oldBase = old.basePoint()
        if hypot(pivot.x - oldBase.x, pivot.y - oldBase.y) < 0.05,
           let angle = Self.uniformRotation(from: old, to: new, pivotX: pivot.x, pivotY: pivot.y),
           abs(angle) > 0.0001 {
            rotateUnits(slaveNames, radians: angle, pivotX: pivot.x, pivotY: pivot.y)
            return
        }
        if let limb = Self.limbRotation(from: old, to: new), abs(limb.angle) > 0.0001 {
            followLimb(masterName: new.name, limb)
            return
        }
        glueSlaves(masterName: new.name, old: old, new: new)
    }

    private mutating func followScale(_ slaveNames: [String], factor: CGFloat) {
        if factor <= 0 {
            fatalError("StickmanFrame \(id) slave scale factor \(factor)")
        }
        let ordered = slaveNames.sorted {
            SlavesRegistry.slaveDepth(unit(named: $0), in: units)
                < SlavesRegistry.slaveDepth(unit(named: $1), in: units)
        }
        for name in ordered {
            guard let index = units.firstIndex(where: { $0.name == name }) else {
                fatalError("StickmanFrame \(id) scale missing '\(name)'")
            }
            let base = units[index].basePoint()
            units[index].scaleBy(pivotX: base.x, pivotY: base.y, factor: factor)
        }
        for name in ordered {
            moveUnitToMaster(named: name)
        }
    }

    private mutating func followLimb(masterName: String, _ limb: LimbTurn) {
        var names: [String] = []
        for unit in units {
            guard let attachment = SlavesRegistry.attachment(of: unit),
                  attachment.masterName == masterName,
                  limb.movedIds.contains(attachment.masterPointId)
            else { continue }
            names.append(unit.name)
            names.append(contentsOf: slaves.allSlaves(of: unit.name))
        }
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0).inserted }
        rotateUnits(unique, radians: limb.angle, pivotX: limb.pivotX, pivotY: limb.pivotY)
    }

    /// Keep each slave's base on its master point when the pose edit was not a rigid move.
    private mutating func glueSlaves(masterName: String, old: StickmanUnit, new: StickmanUnit) {
        for unit in units {
            guard let attachment = SlavesRegistry.attachment(of: unit), attachment.masterName == masterName else {
                continue
            }
            let from = old.point(id: attachment.masterPointId)
            let to = new.point(id: attachment.masterPointId)
            let dx = to.x - from.x
            let dy = to.y - from.y
            if dx == 0 && dy == 0 { continue }
            let names = [unit.name] + slaves.allSlaves(of: unit.name)
            translateUnits(names, dx: dx, dy: dy)
        }
    }

    private mutating func translateUnits(_ names: [String], dx: CGFloat, dy: CGFloat) {
        for name in names {
            guard let index = units.firstIndex(where: { $0.name == name }) else {
                fatalError("StickmanFrame \(id) shift missing '\(name)'")
            }
            units[index].translateAll(dx: dx, dy: dy)
        }
    }

    private mutating func rotateUnits(_ names: [String], radians: CGFloat, pivotX: CGFloat, pivotY: CGFloat) {
        for name in names {
            guard let index = units.firstIndex(where: { $0.name == name }) else {
                fatalError("StickmanFrame \(id) rotate missing '\(name)'")
            }
            units[index].rotate(radians: radians, pivotX: pivotX, pivotY: pivotY)
        }
    }

    private struct LimbTurn {
        var pivotX: CGFloat
        var pivotY: CGFloat
        var angle: CGFloat
        var movedIds: Set<Int>
    }

    private static func translation(from old: StickmanUnit, to new: StickmanUnit) -> (dx: CGFloat, dy: CGFloat)? {
        let dx = new.basePoint().x - old.basePoint().x
        let dy = new.basePoint().y - old.basePoint().y
        for point in old.points {
            guard let moved = new.points.first(where: { $0.id == point.id }) else { return nil }
            if moved.x - point.x != dx || moved.y - point.y != dy { return nil }
        }
        return (dx, dy)
    }

    /// One angle around `pivot` for every point that is not the pivot. Nil when the pose is not that rotation.
    private static func uniformRotation(
        from old: StickmanUnit,
        to new: StickmanUnit,
        pivotX: CGFloat,
        pivotY: CGFloat
    ) -> CGFloat? {
        var angle: CGFloat?
        for point in old.points {
            let moved = new.point(id: point.id)
            guard let delta = rotationDelta(
                ox: point.x, oy: point.y, nx: moved.x, ny: moved.y, pivotX: pivotX, pivotY: pivotY
            ) else { continue }
            if let angle {
                if abs(wrapAngle(delta - angle)) > 0.02 { return nil }
            } else {
                angle = delta
            }
        }
        return angle
    }

    private static func limbRotation(from old: StickmanUnit, to new: StickmanUnit) -> LimbTurn? {
        var movedIds: [Int] = []
        var stationary: [StickmanPoint] = []
        for point in old.points {
            let moved = new.point(id: point.id)
            if hypot(moved.x - point.x, moved.y - point.y) <= 0.05 {
                stationary.append(point)
            } else {
                movedIds.append(point.id)
            }
        }
        if movedIds.isEmpty || stationary.isEmpty { return nil }
        let parentIds = Set(movedIds.compactMap { old.point(id: $0).parentId })
        let pivots = stationary.sorted { parentIds.contains($0.id) && !parentIds.contains($1.id) }
        for pivot in pivots {
            var angle: CGFloat?
            var matched = true
            for id in movedIds {
                let from = old.point(id: id)
                let to = new.point(id: id)
                guard let delta = rotationDelta(
                    ox: from.x, oy: from.y, nx: to.x, ny: to.y, pivotX: pivot.x, pivotY: pivot.y
                ) else {
                    matched = false
                    break
                }
                if let angle {
                    if abs(wrapAngle(delta - angle)) > 0.02 {
                        matched = false
                        break
                    }
                } else {
                    angle = delta
                }
            }
            if matched, let angle {
                return LimbTurn(pivotX: pivot.x, pivotY: pivot.y, angle: angle, movedIds: Set(movedIds))
            }
        }
        return nil
    }

    /// Nil when the point is the pivot, or its distance from the pivot changed.
    private static func rotationDelta(
        ox: CGFloat, oy: CGFloat, nx: CGFloat, ny: CGFloat,
        pivotX: CGFloat, pivotY: CGFloat
    ) -> CGFloat? {
        let oldX = ox - pivotX
        let oldY = oy - pivotY
        let newX = nx - pivotX
        let newY = ny - pivotY
        let oldLen = hypot(oldX, oldY)
        let newLen = hypot(newX, newY)
        if oldLen < 0.05 && newLen < 0.05 { return nil }
        if abs(oldLen - newLen) > 0.75 { return nil }
        return wrapAngle(atan2(newY, newX) - atan2(oldY, oldX))
    }

    private static func wrapAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle
        let turn = CGFloat.pi * 2
        while value > .pi { value -= turn }
        while value < -.pi { value += turn }
        return value
    }

    func uniqueName(for name: String) -> String {
        UnitName.unique(base: name, existing: units.map(\.name))
    }

    func clone() -> StickmanFrame {
        var copy = self
        copy.refreshAttachments()
        return copy
    }

    /// Android `UnitPaster.pasteOnFrame` — unique names, masters first, arrange on top.
    func hasNameIntersection(_ structure: [StickmanUnit]) -> Bool {
        let names = Set(structure.map(\.name))
        return units.contains { names.contains($0.name) }
    }

    /// Android `Inbetweener.structureIntact` — same names and attachments, no extra slaves.
    func structureIntact(_ structure: [StickmanUnit]) -> Bool {
        guard let strRoot = structure.first(where: { SlavesRegistry.attachment(of: $0) == nil }) else {
            fatalError("StickmanFrame \(id) structure has no root")
        }
        guard units.contains(where: { $0.name == strRoot.name }) else {
            return false
        }
        var onFrameNames = Set(SlavesRegistry.allConnected(of: unit(named: strRoot.name), in: units).map(\.name))
        let ordered = structure.sorted {
            SlavesRegistry.slaveDepth($0, in: structure) < SlavesRegistry.slaveDepth($1, in: structure)
        }
        for unit in ordered {
            guard let onFrame = units.first(where: { $0.name == unit.name }) else {
                return false
            }
            if SlavesRegistry.attachment(of: unit) != SlavesRegistry.attachment(of: onFrame) {
                return false
            }
            onFrameNames.remove(unit.name)
        }
        return onFrameNames.isEmpty
    }

    mutating func pasteStructure(_ structure: [StickmanUnit]) {
        if structure.isEmpty {
            fatalError("StickmanFrame \(id) pasteStructure empty")
        }
        let offset = units.map(\.arrange).max() ?? 0
        let ordered = structure.sorted {
            SlavesRegistry.slaveDepth($0, in: structure) < SlavesRegistry.slaveDepth($1, in: structure)
        }
        var existing = units.map(\.name)
        var rename: [String: String] = [:]
        for unit in ordered {
            let next = UnitName.unique(base: unit.name, existing: existing)
            rename[unit.name] = next
            existing.append(next)
        }
        for var unit in ordered {
            let oldName = unit.name
            guard let newName = rename[oldName] else {
                fatalError("StickmanFrame \(id) paste missing rename for '\(oldName)'")
            }
            unit.name = newName
            unit.arrange += offset
            if let baseIndex = unit.points.firstIndex(where: \.isBase),
               let master = unit.points[baseIndex].attachedMasterName,
               let mapped = rename[master] {
                unit.points[baseIndex].attachedMasterName = mapped
            }
            units.append(unit)
        }
        refreshAttachments()
    }

    /// Android `Unit.setNumber` plus `SlavesRegistry.onUnitNameUpdated` on this frame.
    mutating func renameUnit(from oldName: String, to newName: String) {
        guard let index = units.firstIndex(where: { $0.name == oldName }) else {
            fatalError("StickmanFrame \(id) rename missing '\(oldName)'")
        }
        if units.contains(where: { $0.name == newName }) {
            fatalError("StickmanFrame \(id) already has unit '\(newName)'")
        }
        units[index].name = newName
        for unitIndex in units.indices {
            for pointIndex in units[unitIndex].points.indices
            where units[unitIndex].points[pointIndex].attachedMasterName == oldName {
                units[unitIndex].points[pointIndex].attachedMasterName = newName
            }
        }
        refreshAttachments()
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

    /// Android `Unit.setNumber`: 0 keeps the bare name, 1...9 appends `#n`.
    static func withNumber(_ name: String, _ number: Int) -> String {
        if number < 0 || number > 9 {
            fatalError("UnitName '\(name)' number \(number) out of 0...9")
        }
        let pure = UnitAssets.removeNumber(name)
        return number == 0 ? pure : "\(pure)#\(number)"
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
    var speedModifier = SpeedModifier()
    var unitTweens = UnitTweenStorage()
    var cameraTweens = CameraTweenStorage()

    /// Android `CartoonStage.makeOneFrameStage` — one empty frame at `LARGE_L` 640×480.
    static func empty() -> StickmanScene {
        StickmanScene(
            width: 640,
            height: 480,
            frames: [StickmanFrame(id: 0, units: [], bgName: "#ffffff")],
            currentIndex: 0
        )
    }

    var currentFrame: StickmanFrame {
        if frames.isEmpty {
            fatalError("StickmanScene has no frames")
        }
        if currentIndex < 0 || currentIndex >= frames.count {
            fatalError("StickmanScene currentIndex \(currentIndex) out of \(frames.count)")
        }
        return frames[currentIndex]
    }

    func nextFrameId() -> Int {
        (frames.map(\.id).max() ?? -1) + 1
    }

    func canDeleteFrames(at indices: [Int]) -> Bool {
        if indices.isEmpty {
            return false
        }
        return frames.count - Set(indices).count > 0
    }

    /// Android `Scene.addFrame` — clone last, otherwise nlerp midpoint. Moves current to the new frame.
    mutating func addFrame() {
        if frames.isEmpty {
            fatalError("StickmanScene addFrame has no frames")
        }
        if currentIndex < 0 || currentIndex >= frames.count {
            fatalError("StickmanScene addFrame currentIndex \(currentIndex) out of \(frames.count)")
        }
        let appendAtEnd = currentIndex == frames.count - 1
        let oldCount = frames.count
        let insertIndex = currentIndex + 1
        var created: StickmanFrame
        if appendAtEnd {
            created = frames[currentIndex].clone()
        } else {
            let generated = NlerpInterpolator.interpolate(
                from: frames[currentIndex],
                to: frames[currentIndex + 1],
                duration: 2
            )
            if generated.count < 2 {
                fatalError("StickmanScene addFrame interpolator returned \(generated.count)")
            }
            created = generated[1]
        }
        created.id = nextFrameId()
        created.refreshAttachments()
        frames.insert(created, at: insertIndex)
        currentIndex += 1
        speedModifier.adjustTo(frameCount: frames.count)
        if !appendAtEnd {
            retweenReconciled(unitTweens.reconcileInsert(at: insertIndex, oldFrameCount: oldCount))
            retweenCameraReconciled(cameraTweens.reconcileInsert(at: insertIndex, oldFrameCount: oldCount))
        }
    }

    /// Android `Scene.removeFrames` — cannot delete every frame. Lands on the neighbor Android picks.
    mutating func removeFrames(at indices: [Int]) {
        let unique = Array(Set(indices)).sorted()
        if unique.isEmpty {
            fatalError("StickmanScene removeFrames empty")
        }
        if !canDeleteFrames(at: unique) {
            fatalError("StickmanScene cannot delete all \(frames.count) frames")
        }
        for index in unique where index < 0 || index >= frames.count {
            fatalError("StickmanScene removeFrames \(index) out of \(frames.count)")
        }
        let minDeleted = unique[0]
        let maxDeleted = unique[unique.count - 1]
        let landingOld = minDeleted == 0 ? maxDeleted + 1 : minDeleted - 1
        if landingOld < 0 || landingOld >= frames.count {
            fatalError("StickmanScene removeFrames landing \(landingOld) out of \(frames.count)")
        }
        if unique.contains(landingOld) {
            fatalError("StickmanScene removeFrames landing \(landingOld) is deleted")
        }
        let landingId = frames[landingOld].id
        let oldCount = frames.count
        var drop = Set(unique)
        frames = frames.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
        guard let next = frames.firstIndex(where: { $0.id == landingId }) else {
            fatalError("StickmanScene removeFrames lost landing id \(landingId)")
        }
        currentIndex = next
        speedModifier.adjustTo(frameCount: frames.count)
        retweenReconciled(unitTweens.reconcileDelete(deleted: unique, oldFrameCount: oldCount))
        retweenCameraReconciled(cameraTweens.reconcileDelete(deleted: unique, oldFrameCount: oldCount))
    }

    /// Android `Scene.pasteFrames` — insert after current, or at start when current is 0.
    @discardableResult
    mutating func pasteFrames(
        _ source: [StickmanFrame],
        animations incoming: [String: FBFAnimation]
    ) -> [Int] {
        if source.isEmpty {
            fatalError("StickmanScene pasteFrames empty")
        }
        let insertAt = currentIndex == 0 ? 0 : currentIndex + 1
        var oldToNew: [Int: Int] = [:]
        var inserted: [Int] = []
        var cursor = insertAt
        for original in source {
            var frame = original.clone()
            let newId = nextFrameId()
            oldToNew[original.id] = newId
            frame.id = newId
            frame.refreshAttachments()
            frames.insert(frame, at: cursor)
            inserted.append(cursor)
            cursor += 1
        }
        for (name, animation) in incoming {
            if unitAnimations[name] != nil {
                continue
            }
            var copy = animation
            if !copy.hasNoRange {
                guard let start = oldToNew[animation.startFrameId], let end = oldToNew[animation.endFrameId] else {
                    continue
                }
                copy.startFrameId = start
                copy.endFrameId = end
            }
            unitAnimations[name] = copy
        }
        speedModifier.adjustTo(frameCount: frames.count)
        unitTweens.clear()
        cameraTweens.clear()
        return inserted
    }

    /// Android `Inbetweener.ensureStructureOnRange` — copy root+slaves onto frames if no name conflicts.
    @discardableResult
    mutating func ensureStructureOnRange(
        root: StickmanUnit,
        in sourceUnits: [StickmanUnit],
        range: ClosedRange<Int>
    ) -> [Int] {
        if SlavesRegistry.isEnslaved(root) {
            fatalError("StickmanScene ensureStructureOnRange enslaved '\(root.name)'")
        }
        if range.lowerBound < 0 || range.upperBound >= frames.count {
            fatalError("StickmanScene ensureStructureOnRange \(range) out of \(frames.count)")
        }
        let structure = SlavesRegistry.allConnected(of: root, in: sourceUnits)
        var conflicts: [Int] = []
        for index in range {
            let frame = frames[index]
            if !frame.structureIntact(structure) && frame.hasNameIntersection(structure) {
                conflicts.append(index)
            }
        }
        if !conflicts.isEmpty {
            return conflicts
        }
        for index in range where !frames[index].structureIntact(structure) {
            frames[index].pasteStructure(structure)
        }
        return []
    }

    func isPoseLocked(unitName: String, frameIndex: Int) -> Bool {
        if unitTweens.isPoseLocked(unitName: unitName, frameIndex: frameIndex) {
            return true
        }
        guard let unit = frames[safe: frameIndex]?.units.first(where: { $0.name == unitName }) else {
            return false
        }
        let root = SlavesRegistry.rootMaster(of: unit, in: frames[frameIndex].units)
        return root.name != unitName && unitTweens.isPoseLocked(unitName: root.name, frameIndex: frameIndex)
    }

    func isStructureLocked(unitName: String, frameIndex: Int) -> Bool {
        if unitTweens.isOwned(unitName: unitName, frameIndex: frameIndex) {
            return true
        }
        guard let unit = frames[safe: frameIndex]?.units.first(where: { $0.name == unitName }) else {
            return false
        }
        let root = SlavesRegistry.rootMaster(of: unit, in: frames[frameIndex].units)
        return root.name != unitName && unitTweens.isOwned(unitName: root.name, frameIndex: frameIndex)
    }

    func wouldPasteSplitTweens() -> Bool {
        let after = currentIndex == 0 ? -1 : currentIndex
        return unitTweens.wouldInsertSplit(after: after) || cameraTweens.wouldInsertSplit(after: after)
    }

    func isCameraPoseLocked(frameIndex: Int) -> Bool {
        cameraTweens.isPoseLocked(frameIndex: frameIndex)
    }

    mutating func removeCameraTweenContaining(frameIndex: Int) -> CameraAutoTweenRange? {
        cameraTweens.removeContaining(frameIndex: frameIndex)
    }

    mutating func retweenCameraSpan(_ span: CameraAutoTweenRange) {
        if span.fromFrame < 0 || span.toFrame >= frames.count || span.fromFrame >= span.toFrame {
            _ = cameraTweens.removeExact(from: span.fromFrame, to: span.toFrame)
            return
        }
        CameraInbetweener.bakeInteriors(
            scene: &self,
            from: span.fromFrame,
            to: span.toFrame,
            easing: span.easingType,
            strength: span.easingStrength,
            shakeFrequency: span.shakeFrequency
        )
    }

    mutating func retweenCameraEndpoints(frames edited: [Int]) {
        if edited.isEmpty {
            return
        }
        let editedSet = Set(edited)
        for span in cameraTweens.ranges
        where editedSet.contains(span.fromFrame) || editedSet.contains(span.toFrame) {
            retweenCameraSpan(span)
        }
    }

    mutating func removeUnitTweenContaining(unitName: String, frameIndex: Int) -> AutoTweenRange? {
        guard let range = unitTweens.removeContaining(unitName: unitName, frameIndex: frameIndex) else {
            return nil
        }
        if let unit = frames[safe: range.fromFrame]?.units.first(where: { $0.name == unitName }) {
            let root = SlavesRegistry.rootMaster(of: unit, in: frames[range.fromFrame].units)
            for connected in SlavesRegistry.allConnected(of: root, in: frames[range.fromFrame].units)
            where connected.name != unitName {
                unitTweens.removeExact(unitName: connected.name, from: range.fromFrame, to: range.toFrame)
            }
        }
        return range
    }

    mutating func breakTweensTouching(unitName: String, frameIndex: Int) {
        if unitTweens.isOwned(unitName: unitName, frameIndex: frameIndex) {
            _ = removeUnitTweenContaining(unitName: unitName, frameIndex: frameIndex)
        }
        guard let unit = frames[safe: frameIndex]?.units.first(where: { $0.name == unitName }) else {
            return
        }
        let root = SlavesRegistry.rootMaster(of: unit, in: frames[frameIndex].units)
        if root.name != unitName && unitTweens.isOwned(unitName: root.name, frameIndex: frameIndex) {
            _ = removeUnitTweenContaining(unitName: root.name, frameIndex: frameIndex)
        }
    }

    mutating func retweenEndpoints(unitName: String, frames edited: [Int]) {
        if edited.isEmpty {
            return
        }
        let editedSet = Set(edited)
        let spans = unitTweens.ranges.filter { span in
            span.unitName == unitName && (editedSet.contains(span.fromFrame) || editedSet.contains(span.toFrame))
        }
        var seen = Set<String>()
        for span in spans {
            guard let unit = self.frames[safe: span.fromFrame]?.units.first(where: { $0.name == span.unitName }) else {
                continue
            }
            let root = SlavesRegistry.rootMaster(of: unit, in: self.frames[span.fromFrame].units)
            let key = "\(root.name):\(span.fromFrame):\(span.toFrame)"
            if !seen.insert(key).inserted {
                continue
            }
            retweenSpan(
                AutoTweenRange(
                    unitName: root.name,
                    fromFrame: span.fromFrame,
                    toFrame: span.toFrame,
                    easingType: span.easingType,
                    easingStrength: span.easingStrength,
                    shakeFrequency: span.shakeFrequency
                )
            )
        }
    }

    mutating func retweenSpan(_ span: AutoTweenRange) {
        if span.fromFrame < 0 || span.toFrame >= frames.count {
            unitTweens.removeExact(unitName: span.unitName, from: span.fromFrame, to: span.toFrame)
            return
        }
        guard let startUnit = frames[span.fromFrame].units.first(where: { $0.name == span.unitName }),
              frames[span.toFrame].units.contains(where: { $0.name == span.unitName })
        else {
            unitTweens.removeExact(unitName: span.unitName, from: span.fromFrame, to: span.toFrame)
            return
        }
        let root = SlavesRegistry.rootMaster(of: startUnit, in: frames[span.fromFrame].units)
        if SlavesRegistry.isEnslaved(root) {
            unitTweens.removeExact(unitName: span.unitName, from: span.fromFrame, to: span.toFrame)
            return
        }
        if root.name != span.unitName {
            return
        }
        if !UnitInbetweener.propagate(
            scene: &self,
            rootName: root.name,
            from: span.fromFrame,
            to: span.toFrame,
            easing: span.easingType,
            strength: span.easingStrength,
            shakeFrequency: span.shakeFrequency
        ) {
            unitTweens.removeExact(unitName: span.unitName, from: span.fromFrame, to: span.toFrame)
        }
    }

    private mutating func retweenCameraReconciled(_ spans: [CameraAutoTweenRange]) {
        var seen = Set<String>()
        for span in spans {
            let key = "\(span.fromFrame):\(span.toFrame)"
            if !seen.insert(key).inserted {
                continue
            }
            retweenCameraSpan(span)
        }
    }

    private mutating func retweenReconciled(_ spans: [AutoTweenRange]) {
        var seen = Set<String>()
        for span in spans {
            guard let unit = frames[safe: span.fromFrame]?.units.first(where: { $0.name == span.unitName }) else {
                continue
            }
            let root = SlavesRegistry.rootMaster(of: unit, in: frames[span.fromFrame].units)
            let key = "\(root.name):\(span.fromFrame):\(span.toFrame)"
            if !seen.insert(key).inserted {
                continue
            }
            retweenSpan(
                AutoTweenRange(
                    unitName: root.name,
                    fromFrame: span.fromFrame,
                    toFrame: span.toFrame,
                    easingType: span.easingType,
                    easingStrength: span.easingStrength,
                    shakeFrequency: span.shakeFrequency
                )
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
