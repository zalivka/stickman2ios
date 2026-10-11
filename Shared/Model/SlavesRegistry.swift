struct SlavesRegistry {
    private var children: [String: [String]] = [:]

    /// Nil for a unit without exactly one base: such a unit is malformed, and "no attachment"
    /// is the honest answer rather than a crash.
    static func attachment(of unit: StickmanUnit) -> SlaveAttachment? {
        guard let base = unit.basePointOrNil() else {
            return nil
        }
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

    /// Android `SlavesRegistry.isStraying` — slave base that is not attached.
    static func isStraying(_ unit: StickmanUnit) -> Bool {
        unit.basePointOrNil()?.attachable == .slave && attachment(of: unit) == nil
    }

    mutating func populate(units: [StickmanUnit]) throws {
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
                throw SceneLoadError(message: "SlavesRegistry stuck: \(pending.map(\.name))")
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

    /// Deepest master reachable from `unit`. Stops at a cycle or a missing master and reports
    /// the unit it stopped on: `populate` rejects both shapes, so reaching it means the caller
    /// passed an array that was never populated.
    static func rootMaster(of unit: StickmanUnit, in units: [StickmanUnit]) -> StickmanUnit {
        var current = unit
        var seen: Set<String> = []
        while let attachment = attachment(of: current) {
            if seen.contains(current.name) {
                print("SlavesRegistry cycle at '\(current.name)'; rootMaster stops here")
                return current
            }
            seen.insert(current.name)
            guard let master = units.first(where: { $0.name == attachment.masterName }) else {
                print("SlavesRegistry missing master '\(attachment.masterName)' for '\(current.name)'; rootMaster stops here")
                return current
            }
            current = master
        }
        return current
    }

    /// Android `getAllConnected` — root master plus every descendant slave.
    static func allConnected(of unit: StickmanUnit, in units: [StickmanUnit]) throws -> [StickmanUnit] {
        var registry = SlavesRegistry()
        try registry.populate(units: units)
        let root = rootMaster(of: unit, in: units)
        let names = [root.name] + registry.allSlaves(of: root.name)
        return try names.map { name in
            guard let match = units.first(where: { $0.name == name }) else {
                throw SceneLoadError(message: "SlavesRegistry connected missing '\(name)'")
            }
            return match
        }
    }

    /// How many masters up `unit` sits. Stops early on a cycle or missing master, same
    /// reporting as `rootMaster`; a truncated depth only orders slaves less precisely.
    static func slaveDepth(_ unit: StickmanUnit, in units: [StickmanUnit]) -> Int {
        var depth = 0
        var current = unit
        var seen: Set<String> = []
        while let attachment = attachment(of: current) {
            if seen.contains(current.name) {
                print("SlavesRegistry cycle at '\(current.name)'; slaveDepth stops at \(depth)")
                return depth
            }
            seen.insert(current.name)
            guard let master = units.first(where: { $0.name == attachment.masterName }) else {
                print("SlavesRegistry missing master '\(attachment.masterName)' for '\(current.name)'; slaveDepth stops at \(depth)")
                return depth
            }
            depth += 1
            current = master
        }
        return depth
    }
}
