import CoreGraphics

enum Attachable: Hashable {
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
        var created: StickmanFrame
        if currentIndex == frames.count - 1 {
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
        if created.units.isEmpty {
            fatalError("StickmanScene addFrame produced no units")
        }
        frames.insert(created, at: currentIndex + 1)
        currentIndex += 1
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
        var drop = Set(unique)
        frames = frames.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
        guard let next = frames.firstIndex(where: { $0.id == landingId }) else {
            fatalError("StickmanScene removeFrames lost landing id \(landingId)")
        }
        currentIndex = next
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
}
