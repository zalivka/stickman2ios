nonisolated struct SlavesRegistry {
    private var children: [String: [String]] = [:]

    static func attachment(of unit: StickmanUnit) -> SlaveAttachment? {
        let base = unit.basePoint()
        if base.attachable != .slave {
            return nil
        }
        guard let id = base.attachedMasterPointId, id != -1 else {
            return nil
        }
        guard let name = base.attachedMasterName, !name.isEmpty, name != "null" else {
            return nil
        }
        return SlaveAttachment(masterName: name, masterPointId: id)
    }

    static func isEnslaved(_ unit: StickmanUnit) -> Bool {
        attachment(of: unit) != nil
    }

    mutating func populate(units: [StickmanUnit]) {
        children = [:]
        var pending: [StickmanUnit] = []
        for unit in units {
            if Self.attachment(of: unit) == nil {
                children[unit.name] = []
            } else {
                pending.append(unit)
            }
        }
        while !pending.isEmpty {
            var stuck = true
            pending.removeAll { slave in
                guard let attachment = Self.attachment(of: slave) else {
                    return true
                }
                if children[attachment.masterName] != nil {
                    children[attachment.masterName, default: []].append(slave.name)
                    children[slave.name] = []
                    stuck = false
                    return true
                }
                return false
            }
            if stuck {
                fatalError("SlavesRegistry stuck: \(pending.map(\.name))")
            }
        }
    }

    func allSlaves(of name: String) -> [String] {
        var result: [String] = []
        func walk(_ current: String) {
            for child in children[current] ?? [] {
                result.append(child)
                walk(child)
            }
        }
        walk(name)
        return result
    }

    static func rootMaster(of unit: StickmanUnit, in units: [StickmanUnit]) -> StickmanUnit {
        var current = unit
        var seen: Set<String> = []
        while let attachment = attachment(of: current) {
            if seen.contains(current.name) {
                fatalError("SlavesRegistry cycle at '\(current.name)'")
            }
            seen.insert(current.name)
            guard let master = units.first(where: { $0.name == attachment.masterName }) else {
                fatalError("SlavesRegistry missing master '\(attachment.masterName)' for '\(current.name)'")
            }
            current = master
        }
        return current
    }

    /// Android `getAllConnected` — root master plus every descendant slave.
    static func allConnected(of unit: StickmanUnit, in units: [StickmanUnit]) -> [StickmanUnit] {
        var registry = SlavesRegistry()
        registry.populate(units: units)
        let root = rootMaster(of: unit, in: units)
        let names = [root.name] + registry.allSlaves(of: root.name)
        return names.map { name in
            guard let match = units.first(where: { $0.name == name }) else {
                fatalError("SlavesRegistry connected missing '\(name)'")
            }
            return match
        }
    }

    static func slaveDepth(_ unit: StickmanUnit, in units: [StickmanUnit]) -> Int {
        var depth = 0
        var current = unit
        var seen: Set<String> = []
        while let attachment = attachment(of: current) {
            if seen.contains(current.name) {
                fatalError("SlavesRegistry cycle at '\(current.name)'")
            }
            seen.insert(current.name)
            guard let master = units.first(where: { $0.name == attachment.masterName }) else {
                fatalError("SlavesRegistry missing master '\(attachment.masterName)' for '\(current.name)'")
            }
            depth += 1
            current = master
        }
        return depth
    }
}
