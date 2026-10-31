import BonePaper
import CoreGraphics
import CryptoKit
import Foundation
import UIKit

final class UnitAssets {
    nonisolated static let stateDefault = 0
    /// Android `Constants.DEFAULT_LENGTH` — gallery new-bone hint and attach length.
    static let defaultBoneLength: CGFloat = 200

    struct EdgeKey: Hashable {
        var unitName = ""
        var start = -1
        var end = -1
        var flipped = false
        var faceId = -1

        func hash(into hasher: inout Hasher) {
            hasher.combine(unitName)
            hasher.combine(min(start, end))
            hasher.combine(max(start, end))
            hasher.combine(faceId)
            hasher.combine(flipped)
        }

        static func == (lhs: EdgeKey, rhs: EdgeKey) -> Bool {
            let sameEnds = (lhs.start == rhs.start && lhs.end == rhs.end)
                || (lhs.end == rhs.start && lhs.start == rhs.end)
            return sameEnds
                && lhs.unitName == rhs.unitName
                && lhs.faceId == rhs.faceId
                && lhs.flipped == rhs.flipped
        }
    }

    struct EdgeAsset {
        var unitName: String
        var start: Int
        var end: Int
        var xOffset: CGFloat
        var yOffset: CGFloat
        var weight: Int
        var state: Int
        var nativeFlipped: Bool
        var bmName: String
        var bitmap: CGImage
        /// Sidecar pixels per `bm` pixel. `1` (omitted on disk) draws `bitmap`. Greater than `1`
        /// draws `sidecarImage` at `1 / sample` when that image is exactly `bitmap` times `sample`.
        var sample: Int = 1
        /// Compressed PNG of the paint buffer, `BonePaperDocument.sample` times `bitmap` on each side.
        /// Nil when the picture was never drawn in Paper Draw, or the sidecar was dropped.
        /// Touch only through `adoptSidecar`.
        var paintBuffer: Data?
        /// Decoded `paintBuffer`, kept so drawing does not decode every frame. Nil unless `sample > 1`
        /// and the buffer is exactly `bitmap` times `sample`.
        var sidecarImage: CGImage?
        var svgName: String?
        var commandScale: String?

        /// Stores the sidecar and, when `sample > 1` and the size is `bitmap * sample`, the image drawn for it.
        /// A buffer that is not a PNG, or not `bitmap` times `BonePaperDocument.sample`, is logged and dropped.
        /// When `predecoded` is supplied (e.g. shared across edges referencing the same `bmName`), it is reused.
        mutating func adoptSidecar(_ data: Data?, name: String, predecoded: CGImage? = nil) {
            paintBuffer = nil
            sidecarImage = nil
            guard let data, !data.isEmpty else { return }
            let raw: CGImage
            if let predecoded {
                raw = predecoded
            } else if let decoded = UnitAssets.pngImage(from: data) {
                raw = decoded
            } else {
                print("UnitAssets '\(name)' sidecar is not a PNG")
                return
            }
            let factor = BonePaperDocument.sample
            guard raw.width == bitmap.width * factor,
                  raw.height == bitmap.height * factor else {
                print("UnitAssets '\(name)' sidecar \(raw.width)x\(raw.height) != \(bitmap.width * factor)x\(bitmap.height * factor)")
                return
            }
            paintBuffer = data
            if sample > 1,
               raw.width == bitmap.width * sample,
               raw.height == bitmap.height * sample {
                if predecoded != nil {
                    sidecarImage = raw
                } else {
                    do {
                        sidecarImage = DevFlags.decodedBoneBitmaps
                            ? try PNG.decodedBitmap(raw, name: name)
                            : raw
                    } catch {
                        print("UnitAssets '\(name)' sidecar decode failed: \(error)")
                    }
                }
            }
        }

        /// The picture to draw. `divisor` is `1` for the `bm` PNG, or `sample` when the sidecar is used.
        func drawnPicture(ignoreSample: Bool) -> (image: CGImage, divisor: CGFloat) {
            if !ignoreSample,
               sample > 1,
               let sidecar = sidecarImage,
               sidecar.width == bitmap.width * sample,
               sidecar.height == bitmap.height * sample {
                return (sidecar, CGFloat(sample))
            }
            return (bitmap, 1)
        }
    }

    struct GalleryBone: Identifiable {
        var id: String { bmName }
        var bmName: String
        var thumb: CGImage
    }

    private var edgeAssets: [EdgeKey: [Int: EdgeAsset]] = [:]
    /// Unattached gallery pictures (Android bone-picture repo rows with no edge yet).
    private var looseBones: [String: EdgeAsset] = [:]
    private var drawingConfigs: [String: BonePaperDrawingConfig] = [:]
    private var restModel: [String: [Int: CGFloat]] = [:]
    private var archives: [String: StoredArchive] = [:]

    struct StoredArchive {
        var entryName: String
        var zip: Data
    }

    struct Snapshot {
        var edgeAssets: [EdgeKey: [Int: EdgeAsset]]
        var looseBones: [String: EdgeAsset]
        var drawingConfigs: [String: BonePaperDrawingConfig]
    }

    func snapshot() -> Snapshot {
        Snapshot(edgeAssets: edgeAssets, looseBones: looseBones, drawingConfigs: drawingConfigs)
    }

    func restore(_ snapshot: Snapshot) {
        edgeAssets = snapshot.edgeAssets
        looseBones = snapshot.looseBones
        drawingConfigs = snapshot.drawingConfigs
    }

    func drawingConfig(for unitName: String) -> BonePaperDrawingConfig {
        drawingConfigs[Self.removeNumber(unitName)] ?? BonePaperDrawingConfig()
    }

    func setDrawingConfig(_ config: BonePaperDrawingConfig, for unitName: String) {
        let key = Self.removeNumber(unitName)
        let clean = config.sanitized()
        if clean.isEmpty {
            drawingConfigs.removeValue(forKey: key)
        } else {
            drawingConfigs[key] = clean
        }
    }

    func hasAssetsFor(unitName: String) -> Bool {
        edgeAssets.keys.contains { $0.unitName == unitName }
    }

    func hasArchive(for unitName: String) -> Bool {
        archives[Self.removeNumber(unitName)] != nil
    }

    func loadItemFromArchive(_ zip: Data, entryName: String, forceReload: Bool = true) throws {
        if entryName.isEmpty {
            throw ItemLoadError("UnitAssets empty archive entry name")
        }
        let model = try ModelXML.parse(try ZipStore.dataThrowing(named: "model.xml", in: zip))
        let key = Self.removeNumber(model.name)
        if !forceReload && hasAssetsFor(unitName: model.name) {
            if archives[key] == nil {
                archives[key] = StoredArchive(entryName: entryName, zip: zip)
            }
            return
        }
        if model.unitType == .bubble {
            archives[key] = StoredArchive(entryName: entryName, zip: zip)
            try captureRest(from: model)
            return
        }
        let xml = try ZipStore.dataThrowing(named: "assets.xml", in: zip)
        let parsed = try AssetsXML.parse(xml)
        try install(parsed, zip: zip)
        archives[key] = StoredArchive(entryName: entryName, zip: zip)
        try captureRest(from: model)
    }

    func archive(for unitName: String) -> StoredArchive? {
        let key = Self.removeNumber(unitName)
        guard let stored = archives[key] else {
            assertionFailure("UnitAssets missing archive for '\(key)'")
            return nil
        }
        return stored
    }

    static func atiEntryName(packName: String, systemName: String) -> String {
        if systemName.isEmpty {
            // Behind ManifestXML / SceneLoader.resolveUnitName validators.
            assertionFailure("UnitAssets empty systemName")
        }
        if packName == "@" {
            return systemName + ".ati"
        }
        if packName.isEmpty {
            assertionFailure("UnitAssets empty packName for '\(systemName)'")
            return systemName + ".ati"
        }
        return "\(packName)/items/\(systemName).ati"
    }

    static func atiEntryName(for unitName: String) -> String {
        let name = removeNumber(unitName)
        guard let colon = name.firstIndex(of: ":") else {
            return name + ".ati"
        }
        let pack = String(name[..<colon])
        let own = String(name[name.index(after: colon)...])
        if own.isEmpty {
            // Behind SceneLoader.resolveUnitName; a file-supplied name never gets here empty.
            assertionFailure("UnitAssets unit name '\(unitName)' has empty own name")
            return name + ".ati"
        }
        return atiEntryName(packName: pack, systemName: own)
    }

    func getDrawable(_ key: EdgeKey, state: Int) -> EdgeAsset? {
        var states = edgeStates(key)
        if states.isEmpty {
            var unflipped = key
            unflipped.flipped = false
            states = edgeStates(unflipped)
        }
        return states[state] ?? states[Self.stateDefault]
    }

    /// Android `AssetsOpsImpl.getAssetsBoundingPoints` — bitmap corners in scene space.
    func assetCornerPoints(for unit: StickmanUnit, state: Int) -> [CGPoint] {
        let name = Self.removeNumber(unit.name)
        var corners: [CGPoint] = []
        for edge in unit.edges {
            let key = EdgeKey(unitName: name, start: edge.from, end: edge.to, flipped: unit.flipped)
            guard let asset = getDrawable(key, state: state) else { continue }
            guard let start = unit.point(optionalId: edge.from), let end = unit.point(optionalId: edge.to) else { continue }
            let angle = atan2(end.y - start.y, end.x - start.x)
            let mirror = unit.flipped && !asset.nativeFlipped
            let scale = unit.scale
            let xOffset = asset.xOffset * scale
            let yOffset = (mirror ? -asset.yOffset : asset.yOffset) * scale
            let yScale = mirror ? -scale : scale
            let width = CGFloat(asset.bitmap.width)
            let height = CGFloat(asset.bitmap.height)
            let locals: [CGPoint] = [
                CGPoint(x: xOffset, y: yOffset),
                CGPoint(x: xOffset + width * scale, y: yOffset),
                CGPoint(x: xOffset + width * scale, y: yOffset + height * yScale),
                CGPoint(x: xOffset, y: yOffset + height * yScale)
            ]
            let cosine = cos(angle)
            let sine = sin(angle)
            for local in locals {
                corners.append(
                    CGPoint(
                        x: start.x + local.x * cosine - local.y * sine,
                        y: start.y + local.x * sine + local.y * cosine
                    )
                )
            }
        }
        return corners
    }

    /// Skeleton joints plus every state's bitmaps — the box the FBF preview must fit.
    func combinedBounds(for unit: StickmanUnit) -> CGRect {
        if unit.points.isEmpty {
            // FBFAnimationSheet only fits units that were built with points.
            assertionFailure("UnitAssets combinedBounds '\(unit.name)' has no points")
            return .zero
        }
        var xs = unit.points.map(\.x)
        var ys = unit.points.map(\.y)
        let scan = states(for: unit.name)
        let statesToScan = scan.isEmpty ? [unit.assetsState] : scan
        for state in statesToScan {
            for corner in assetCornerPoints(for: unit, state: state) {
                xs.append(corner.x)
                ys.append(corner.y)
            }
        }
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func getEdgeWeight(unitName: String, startId: Int, endId: Int, state: Int, flipped: Bool) -> Int {
        let key = EdgeKey(unitName: unitName, start: startId, end: endId, flipped: flipped)
        return getDrawable(key, state: state)?.weight ?? -1
    }

    /// Android `Utils.BM_NAME_PATTERN`. Frames that share the id are one gallery bone.
    /// The row is the lowest state. Any other name is one bone by itself.
    private static func androidBoneFrame(_ bmName: String) -> (id: Int, state: Int)? {
        let prefix = "bm_"
        let middle = "_state_"
        let suffix = ".png"
        guard bmName.hasPrefix(prefix), bmName.hasSuffix(suffix) else { return nil }
        let core = bmName.dropFirst(prefix.count).dropLast(suffix.count)
        guard let split = core.range(of: middle) else { return nil }
        let idText = core[..<split.lowerBound]
        let stateText = core[split.upperBound...]
        guard !idText.isEmpty, !stateText.isEmpty,
              idText.allSatisfy(\.isNumber), stateText.allSatisfy(\.isNumber),
              let id = Int(idText), let state = Int(stateText) else { return nil }
        return (id, state)
    }

    /// Unique bones for the gallery rail, ordered by weight then bitmap name.
    /// `bm_<id>_state_<n>.png` frames collapse to one row (the lowest state), matching Android.
    func galleryBones(unitName: String) -> [GalleryBone] {
        let name = Self.removeNumber(unitName)
        struct Seen {
            var bmName: String
            var thumb: CGImage
            var weight: Int
            var state: Int
        }
        var seen: [String: Seen] = [:]
        func consider(_ asset: EdgeAsset) {
            if let frame = Self.androidBoneFrame(asset.bmName) {
                let key = "bone:\(frame.id)"
                if let existing = seen[key], existing.state <= frame.state { return }
                seen[key] = Seen(
                    bmName: asset.bmName,
                    thumb: asset.bitmap,
                    weight: asset.weight,
                    state: frame.state
                )
                return
            }
            if seen[asset.bmName] != nil { return }
            seen[asset.bmName] = Seen(
                bmName: asset.bmName,
                thumb: asset.bitmap,
                weight: asset.weight,
                state: asset.state
            )
        }
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                consider(asset)
            }
        }
        for asset in looseBones.values where asset.unitName == name {
            consider(asset)
        }
        return seen.values
            .sorted {
                if $0.weight != $1.weight { return $0.weight < $1.weight }
                return $0.bmName < $1.bmName
            }
            .map { GalleryBone(bmName: $0.bmName, thumb: $0.thumb) }
    }

    func bmName(forEdge start: Int, end: Int, unitName: String) -> String? {
        let name = Self.removeNumber(unitName)
        let key = EdgeKey(unitName: name, start: start, end: end, flipped: false)
        return getDrawable(key, state: Self.stateDefault)?.bmName
    }

    /// Clones art from an existing `bmName` onto a new edge (shared bitmap, Android-style reuse).
    func attachBone(bmName: String, toEdge start: Int, end: Int, unitName: String) {
        if bmName.isEmpty {
            assertionFailure("UnitAssets attachBone empty bmName")
            return
        }
        let name = Self.removeNumber(unitName)
        guard let template = firstAsset(bmName: bmName, unitName: name) else {
            assertionFailure("UnitAssets attachBone unknown bm '\(bmName)' for '\(name)'")
            return
        }
        let key = EdgeKey(
            unitName: name,
            start: start,
            end: end,
            flipped: template.nativeFlipped
        )
        let weight = nextWeight(unitName: name)
        if let frame = Self.androidBoneFrame(bmName) {
            var attachedStates: [Int: EdgeAsset] = [:]
            for (_, states) in edgeAssets where states.values.contains(where: { $0.unitName == name && Self.androidBoneFrame($0.bmName)?.id == frame.id }) {
                for (st, stAsset) in states where Self.androidBoneFrame(stAsset.bmName)?.id == frame.id {
                    var copy = stAsset
                    copy.unitName = name
                    copy.start = start
                    copy.end = end
                    copy.weight = weight
                    attachedStates[st] = copy
                }
                break
            }
            if attachedStates.isEmpty {
                for (looseKey, looseAsset) in looseBones where looseAsset.unitName == name {
                    if let lf = Self.androidBoneFrame(looseKey), lf.id == frame.id {
                        var copy = looseAsset
                        copy.unitName = name
                        copy.start = start
                        copy.end = end
                        copy.weight = weight
                        copy.state = lf.state
                        attachedStates[lf.state] = copy
                        looseBones.removeValue(forKey: looseKey)
                    }
                }
            }
            if !attachedStates.isEmpty {
                edgeAssets[key] = attachedStates
                return
            }
        }
        var asset = template
        asset.unitName = name
        asset.start = start
        asset.end = end
        asset.weight = weight
        asset.state = Self.stateDefault
        edgeAssets[key] = [Self.stateDefault: asset]
        looseBones.removeValue(forKey: bmName)
    }

    func stateAssets(for edge: EdgeKey) -> [EdgeAsset] {
        var states = edgeStates(edge)
        if states.isEmpty {
            var unflipped = edge
            unflipped.flipped = false
            states = edgeStates(unflipped)
        }
        return states.values.sorted { $0.state < $1.state }
    }

    func stateAssets(forBmName bmName: String, unitName: String) -> [EdgeAsset] {
        let name = Self.removeNumber(unitName)
        if let frame = Self.androidBoneFrame(bmName) {
            for (key, states) in edgeAssets where key.unitName == name {
                if states.values.contains(where: { Self.androidBoneFrame($0.bmName)?.id == frame.id }) {
                    return states.values.sorted { $0.state < $1.state }
                }
            }
            let looseMatches = looseBones.values.filter {
                $0.unitName == name && Self.androidBoneFrame($0.bmName)?.id == frame.id
            }
            if !looseMatches.isEmpty {
                return looseMatches.sorted { $0.state < $1.state }
            }
        }
        for (key, states) in edgeAssets where key.unitName == name {
            if states.values.contains(where: { $0.bmName == bmName }) {
                return states.values.sorted { $0.state < $1.state }
            }
        }
        if let loose = looseBones[bmName], loose.unitName == name {
            return [loose]
        }
        return []
    }

    private func nextBonePictureId(unitName: String) -> Int {
        var maxId = -1
        for (key, states) in edgeAssets where key.unitName == unitName {
            for asset in states.values {
                if let parsed = Self.androidBoneFrame(asset.bmName) {
                    maxId = max(maxId, parsed.id)
                }
            }
        }
        for asset in looseBones.values where asset.unitName == unitName {
            if let parsed = Self.androidBoneFrame(asset.bmName) {
                maxId = max(maxId, parsed.id)
            }
        }
        return maxId + 1
    }

    func replaceBoneFrames(
        baseAsset: EdgeAsset,
        frameExports: [BonePaperFrameExport]
    ) throws {
        if frameExports.isEmpty {
            throw SceneLoadError(message: "UnitAssets replaceBoneFrames has no frames")
        }
        let name = Self.removeNumber(baseAsset.unitName)
        let existingBoneId = Self.androidBoneFrame(baseAsset.bmName)?.id
        let useMultiFrameNaming = frameExports.count > 1 || existingBoneId != nil
        let boneId = existingBoneId ?? nextBonePictureId(unitName: name)

        func targetBmName(for state: Int) -> String {
            if useMultiFrameNaming {
                return "bm_\(boneId)_state_\(state).png"
            }
            return baseAsset.bmName
        }

        struct PreparedFrame {
            var state: Int
            var bmName: String
            var image: CGImage
            var bufferData: Data
            var predecoded: CGImage?
            var xOffset: CGFloat
            var yOffset: CGFloat
        }

        var prepared: [PreparedFrame] = []
        for item in frameExports {
            let bm = targetBmName(for: item.state)
            let img = item.export.image
            if img.width < 1 || img.height < 1 {
                throw SceneLoadError(message: "UnitAssets replaceBoneFrames '\(bm)' size \(img.width)x\(img.height)")
            }
            guard let bufImg = item.export.buffer else {
                throw SceneLoadError(message: "UnitAssets replaceBoneFrames '\(bm)' missing paint buffer")
            }
            let bufData = try Self.pngData(from: bufImg, name: bm)
            let predecoded = Self.predecodedSidecar(bufData, bitmap: img, name: bm)
            prepared.append(
                PreparedFrame(
                    state: item.state,
                    bmName: bm,
                    image: img,
                    bufferData: bufData,
                    predecoded: predecoded,
                    xOffset: item.baseXOffset - item.export.extraLeft,
                    yOffset: item.baseYOffset - item.export.extraTop
                )
            )
        }

        func matchesTargetGroup(_ asset: EdgeAsset) -> Bool {
            if asset.bmName == baseAsset.bmName {
                return true
            }
            if let existingBoneId, let parsed = Self.androidBoneFrame(asset.bmName) {
                return parsed.id == existingBoneId
            }
            return false
        }

        var matchedEdgeKeys: [EdgeKey] = []
        for (key, states) in edgeAssets where key.unitName == name {
            if states.values.contains(where: matchesTargetGroup) {
                matchedEdgeKeys.append(key)
            }
        }

        if !matchedEdgeKeys.isEmpty {
            for key in matchedEdgeKeys {
                let oldStates = edgeAssets[key] ?? [:]
                let template = oldStates[Self.stateDefault] ?? oldStates.values.first ?? baseAsset
                var newStates: [Int: EdgeAsset] = [:]
                for frame in prepared {
                    var updated = EdgeAsset(
                        unitName: name,
                        start: template.start,
                        end: template.end,
                        xOffset: frame.xOffset,
                        yOffset: frame.yOffset,
                        weight: template.weight,
                        state: frame.state,
                        nativeFlipped: template.nativeFlipped,
                        bmName: frame.bmName,
                        bitmap: frame.image,
                        sample: BonePaperDocument.sample,
                        paintBuffer: nil,
                        sidecarImage: nil,
                        svgName: nil,
                        commandScale: nil
                    )
                    updated.adoptSidecar(frame.bufferData, name: frame.bmName, predecoded: frame.predecoded)
                    newStates[frame.state] = updated
                }
                edgeAssets[key] = newStates
            }
            return
        }

        // Loose gallery bone update
        let oldLooseKeys = looseBones.keys.filter { key in
            guard let loose = looseBones[key], loose.unitName == name else { return false }
            return matchesTargetGroup(loose)
        }
        for key in oldLooseKeys {
            looseBones.removeValue(forKey: key)
        }
        for frame in prepared {
            var updated = EdgeAsset(
                unitName: name,
                start: -1,
                end: -1,
                xOffset: frame.xOffset,
                yOffset: frame.yOffset,
                weight: baseAsset.weight,
                state: frame.state,
                nativeFlipped: baseAsset.nativeFlipped,
                bmName: frame.bmName,
                bitmap: frame.image,
                sample: BonePaperDocument.sample,
                paintBuffer: nil,
                sidecarImage: nil,
                svgName: nil,
                commandScale: nil
            )
            updated.adoptSidecar(frame.bufferData, name: frame.bmName, predecoded: frame.predecoded)
            looseBones[frame.bmName] = updated
        }
    }

    /// Android `BonePictureFactory.createEmpty` + `Constants.DEFAULT_LENGTH` Kurwa hint.
    /// Nil when the empty bitmap could not be allocated (memory pressure).
    func createEmptyGalleryBone(unitName: String, length: CGFloat = defaultBoneLength) -> EdgeAsset? {
        if length <= 0 {
            assertionFailure("UnitAssets gallery bone length is \(length)")
            return nil
        }
        let name = Self.removeNumber(unitName)
        guard let asset = makeEmptyAsset(
            unitName: name,
            start: -1,
            end: -1,
            length: length,
            bmName: uniqueGalleryBmName()
        ) else {
            return nil
        }
        if looseBones[asset.bmName] != nil {
            assertionFailure("UnitAssets duplicate loose bm '\(asset.bmName)'")
            return nil
        }
        looseBones[asset.bmName] = asset
        return asset
    }

    /// FastPainter empty frame: square `2*length`, pad so the bone sits on the mid-line.
    /// Nil when the empty bitmap could not be allocated (memory pressure).
    func ensureDrawable(
        start: Int,
        end: Int,
        unitName: String,
        length: CGFloat
    ) -> EdgeAsset? {
        let name = Self.removeNumber(unitName)
        let key = EdgeKey(unitName: name, start: start, end: end, flipped: false)
        if let existing = getDrawable(key, state: Self.stateDefault) {
            return existing
        }
        guard let asset = makeEmptyAsset(
            unitName: name,
            start: start,
            end: end,
            length: length,
            bmName: uniqueBmName(start: start, end: end)
        ) else {
            return nil
        }
        edgeAssets[key] = [Self.stateDefault: asset]
        return asset
    }

    /// Android `setBonePictureId(NO_PICTURE)` — edge stays, artwork unlinks. Unused pictures go to the gallery.
    func clearEdgeArtwork(start: Int, end: Int, unitName: String) {
        let name = Self.removeNumber(unitName)
        var removed: EdgeAsset?
        edgeAssets = edgeAssets.filter { key, states in
            let sameUnit = key.unitName == name
            let sameEnds = (key.start == start && key.end == end) || (key.start == end && key.end == start)
            if sameUnit && sameEnds {
                removed = states[Self.stateDefault] ?? states.values.first
                return false
            }
            return true
        }
        guard let asset = removed else { return }
        let stillUsed = edgeAssets.values.contains { states in
            states.values.contains { $0.bmName == asset.bmName }
        }
        if !stillUsed {
            var loose = asset
            loose.start = -1
            loose.end = -1
            looseBones[asset.bmName] = loose
        }
    }

    /// Splits every state/flip asset on edge `from → to` into proximal (`from → mid`) and distal (`mid → to`)
    /// assets using `BonePictureSplit`, keeps the original default-state asset in `looseBones` if unused
    /// elsewhere, and places distal draw weight directly above proximal (`weight + 1`).
    func splitEdgeAssets(
        from: Int,
        mid: Int,
        to: Int,
        unitName: String,
        splitDistance: CGFloat,
        radius: CGFloat,
        shape: BoneSplitShape = .circle
    ) throws {
        let name = Self.removeNumber(unitName)
        let matchingKeys = edgeAssets.keys.filter { key in
            key.unitName == name
                && ((key.start == from && key.end == to) || (key.start == to && key.end == from))
        }
        if matchingKeys.isEmpty {
            return
        }

        var collected: [(key: EdgeKey, states: [Int: EdgeAsset])] = []
        for key in matchingKeys {
            if let states = edgeAssets.removeValue(forKey: key), !states.isEmpty {
                collected.append((key, states))
            }
        }
        if collected.isEmpty {
            return
        }

        for (_, states) in collected {
            if let original = states[Self.stateDefault] ?? states.values.first {
                let stillUsed = edgeAssets.values.contains { otherStates in
                    otherStates.values.contains { $0.bmName == original.bmName }
                }
                if !stillUsed && looseBones[original.bmName] == nil {
                    var loose = original
                    loose.start = -1
                    loose.end = -1
                    looseBones[original.bmName] = loose
                }
            }
        }

        let baseWeight = collected
            .flatMap { $0.states.values.map(\.weight) }
            .min() ?? nextWeight(unitName: name)

        for (otherKey, otherStates) in edgeAssets where otherKey.unitName == name {
            var updatedStates = otherStates
            var changed = false
            for (st, var asset) in otherStates where asset.weight > baseWeight {
                asset.weight += 1
                updatedStates[st] = asset
                changed = true
            }
            if changed {
                edgeAssets[otherKey] = updatedStates
            }
        }
        for (looseName, var loose) in looseBones where loose.unitName == name && loose.weight > baseWeight {
            loose.weight += 1
            looseBones[looseName] = loose
        }

        var splitCache: [String: (proxBm: String, distBm: String, pair: BonePictureSplit.Pair)] = [:]
        var reservedNames = Set<String>()

        for (oldKey, states) in collected {
            let proxKey = EdgeKey(
                unitName: name,
                start: from,
                end: mid,
                flipped: oldKey.flipped,
                faceId: oldKey.faceId
            )
            let distKey = EdgeKey(
                unitName: name,
                start: mid,
                end: to,
                flipped: oldKey.flipped,
                faceId: oldKey.faceId
            )
            var proxStates = edgeAssets[proxKey] ?? [:]
            var distStates = edgeAssets[distKey] ?? [:]

            for (state, asset) in states {
                let cacheKey = "\(asset.bmName)|\(asset.xOffset)|\(asset.yOffset)|\(asset.sample)"
                let cached: (proxBm: String, distBm: String, pair: BonePictureSplit.Pair)
                if let existing = splitCache[cacheKey] {
                    cached = existing
                } else {
                    let pair = try BonePictureSplit.split(
                        bitmap: asset.bitmap,
                        paintBuffer: asset.paintBuffer,
                        xOffset: asset.xOffset,
                        yOffset: asset.yOffset,
                        splitDistance: splitDistance,
                        radius: radius,
                        shape: shape,
                        name: asset.bmName
                    )
                    let proxBm = uniqueBmName(start: from, end: mid, extraUsed: reservedNames)
                    reservedNames.insert(proxBm)
                    let distBm = uniqueBmName(start: mid, end: to, extraUsed: reservedNames)
                    reservedNames.insert(distBm)
                    cached = (proxBm, distBm, pair)
                    splitCache[cacheKey] = cached
                }

                var proxAsset = EdgeAsset(
                    unitName: name,
                    start: from,
                    end: mid,
                    xOffset: cached.pair.proximal.xOffset,
                    yOffset: cached.pair.proximal.yOffset,
                    weight: baseWeight,
                    state: state,
                    nativeFlipped: asset.nativeFlipped,
                    bmName: cached.proxBm,
                    bitmap: cached.pair.proximal.image,
                    sample: asset.sample,
                    paintBuffer: nil,
                    sidecarImage: nil,
                    svgName: nil,
                    commandScale: nil
                )
                proxAsset.adoptSidecar(cached.pair.proximal.paintBuffer, name: cached.proxBm)
                var distAsset = EdgeAsset(
                    unitName: name,
                    start: mid,
                    end: to,
                    xOffset: cached.pair.distal.xOffset,
                    yOffset: cached.pair.distal.yOffset,
                    weight: baseWeight + 1,
                    state: state,
                    nativeFlipped: asset.nativeFlipped,
                    bmName: cached.distBm,
                    bitmap: cached.pair.distal.image,
                    sample: asset.sample,
                    paintBuffer: nil,
                    sidecarImage: nil,
                    svgName: nil,
                    commandScale: nil
                )
                distAsset.adoptSidecar(cached.pair.distal.paintBuffer, name: cached.distBm)
                proxStates[state] = proxAsset
                distStates[state] = distAsset
            }

            edgeAssets[proxKey] = proxStates
            edgeAssets[distKey] = distStates
        }
    }

    /// Android `PictureFrame.applyModifier`: `xpad -= dx` (`xOffset` is `-xpad`).
    func applyShift(bmName: String, dx: CGFloat, dy: CGFloat) {
        if bmName.isEmpty {
            assertionFailure("UnitAssets applyShift empty bmName")
            return
        }
        var found = false
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states where asset.bmName == bmName {
                var updated = asset
                updated.xOffset += dx
                updated.yOffset += dy
                next[state] = updated
                changed = true
                found = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
        if var loose = looseBones[bmName] {
            loose.xOffset += dx
            loose.yOffset += dy
            looseBones[bmName] = loose
            found = true
        }
        if !found {
            assertionFailure("UnitAssets applyShift unknown bm '\(bmName)'")
        }
    }

    /// PNG bytes for a paint buffer, for the screen layer (the `PNG` helper is file-private).
    static func pngData(from image: CGImage, name: String) throws -> Data {
        try PNG.data(from: image, name: name)
    }

    /// Decoded buffer image, nil for bad bytes. Loud variant is `PNG.image`, kept for pack art.
    static func pngImage(from data: Data) -> CGImage? {
        PNG.decodedImage(from: data)
    }

    func replaceBitmap(
        bmName: String,
        image: CGImage,
        buffer: Data? = nil,
        sample: Int = 1,
        extraLeft: CGFloat = 0,
        extraTop: CGFloat = 0
    ) throws {
        if bmName.isEmpty {
            throw SceneLoadError(message: "UnitAssets replaceBitmap empty bmName")
        }
        if image.width < 1 || image.height < 1 {
            throw SceneLoadError(message: "UnitAssets replaceBitmap '\(bmName)' size \(image.width)x\(image.height)")
        }
        if sample < 1 {
            throw SceneLoadError(message: "UnitAssets replaceBitmap '\(bmName)' sample \(sample)")
        }
        let predecoded = Self.predecodedSidecar(buffer, bitmap: image, name: bmName)
        var found = false
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states where asset.bmName == bmName {
                var updated = asset
                updated.bitmap = image
                updated.sample = sample
                updated.xOffset -= extraLeft
                updated.yOffset -= extraTop
                updated.svgName = nil
                updated.commandScale = nil
                updated.adoptSidecar(buffer, name: bmName, predecoded: predecoded)
                next[state] = updated
                changed = true
                found = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
        if var loose = looseBones[bmName] {
            loose.bitmap = image
            loose.sample = sample
            loose.xOffset -= extraLeft
            loose.yOffset -= extraTop
            loose.svgName = nil
            loose.commandScale = nil
            loose.adoptSidecar(buffer, name: bmName, predecoded: predecoded)
            looseBones[bmName] = loose
            found = true
        }
        if !found {
            assertionFailure("UnitAssets replaceBitmap unknown bm '\(bmName)'")
        }
    }

    func pngFiles(unitName: String) throws -> [(name: String, data: Data)] {
        let name = Self.removeNumber(unitName)
        var seen: Set<String> = []
        var files: [(name: String, data: Data)] = []
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if seen.contains(asset.bmName) { continue }
                seen.insert(asset.bmName)
                files.append((name: asset.bmName, data: try PNG.data(from: asset.bitmap, name: asset.bmName)))
            }
        }
        return files.sorted { $0.name < $1.name }
    }

    private func makeEmptyAsset(
        unitName: String,
        start: Int,
        end: Int,
        length: CGFloat,
        bmName: String
    ) -> EdgeAsset? {
        let safe = max(length, 1)
        let side = min(BonePaperDocument.maxSide, max(2, Int(ceil(safe * 2))))
        guard let bitmap = Self.emptyBitmap(width: side, height: side) else {
            return nil
        }
        let xPad = max(0, (CGFloat(side) - safe) / 2)
        return EdgeAsset(
            unitName: unitName,
            start: start,
            end: end,
            xOffset: -xPad,
            yOffset: -CGFloat(side) / 2,
            weight: nextWeight(unitName: unitName),
            state: Self.stateDefault,
            nativeFlipped: false,
            bmName: bmName,
            bitmap: bitmap,
            paintBuffer: nil,
            svgName: nil,
            commandScale: nil
        )
    }

    private func nextWeight(unitName: String) -> Int {
        let edgeMax = edgeAssets
            .filter { $0.key.unitName == unitName }
            .flatMap { $0.value.values.map(\.weight) }
            .max() ?? -1
        let looseMax = looseBones.values
            .filter { $0.unitName == unitName }
            .map(\.weight)
            .max() ?? -1
        return max(edgeMax, looseMax) + 1
    }

    private func usedBmNames() -> Set<String> {
        var used = Set(looseBones.keys)
        for states in edgeAssets.values {
            for asset in states.values {
                used.insert(asset.bmName)
            }
        }
        return used
    }

    private func uniqueBmName(start: Int, end: Int, extraUsed: Set<String> = []) -> String {
        let used = usedBmNames().union(extraUsed)
        let base = "bone_\(start)_\(end).png"
        if !used.contains(base) {
            return base
        }
        var suffix = 2
        while used.contains("bone_\(start)_\(end)_\(suffix).png") {
            suffix += 1
        }
        return "bone_\(start)_\(end)_\(suffix).png"
    }

    private func uniqueGalleryBmName() -> String {
        let used = usedBmNames()
        let base = "bone_new.png"
        if !used.contains(base) {
            return base
        }
        var suffix = 2
        while used.contains("bone_new_\(suffix).png") {
            suffix += 1
        }
        return "bone_new_\(suffix).png"
    }

    /// Live edge rows for save — includes edges attached or painted during this session.
    func exportRows(unitName: String) -> [EdgeAssetRow] {
        let name = Self.removeNumber(unitName)
        var rows: [EdgeAssetRow] = []
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values.sorted(by: { $0.state < $1.state }) {
                rows.append(
                    EdgeAssetRow(
                        unitName: name,
                        start: asset.start,
                        end: asset.end,
                        xOffset: asset.xOffset,
                        yOffset: asset.yOffset,
                        weight: asset.weight,
                        state: asset.state,
                        nativeFlipped: asset.nativeFlipped,
                        bmName: asset.bmName,
                        svgName: asset.svgName,
                        commandScale: asset.commandScale,
                        sample: asset.sample
                    )
                )
            }
        }
        rows.sort {
            if $0.weight != $1.weight { return $0.weight < $1.weight }
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.state < $1.state
        }
        return rows
    }

    func firstAsset(bmName: String, unitName: String) -> EdgeAsset? {
        let name = Self.removeNumber(unitName)
        for (key, states) in edgeAssets where key.unitName == name {
            if let match = states.values.first(where: { $0.bmName == bmName }) {
                return match
            }
        }
        if let loose = looseBones[bmName], loose.unitName == name {
            return loose
        }
        return nil
    }

    /// Android `BonesGalleryFragment.findEdgeUsing` — first skeleton edge that draws this picture.
    func firstEdgeUsing(bmName: String, unitName: String) -> (start: Int, end: Int)? {
        let name = Self.removeNumber(unitName)
        for (key, states) in edgeAssets where key.unitName == name {
            if states.values.contains(where: { $0.bmName == bmName }) {
                return (key.start, key.end)
            }
        }
        return nil
    }

    /// Swaps draw-order weight of the edge with its neighbor, matching Android `doMoveOrder`.
    @discardableResult
    func moveEdgeOrder(unitName: String, start: Int, end: Int, moveUp: Bool) -> Bool {
        let name = Self.removeNumber(unitName)
        struct Entry {
            var key: EdgeKey
            var weight: Int
        }
        var entries: [Entry] = []
        for (key, states) in edgeAssets where key.unitName == name {
            let weight = states.values.map(\.weight).min() ?? 0
            entries.append(Entry(key: key, weight: weight))
        }
        entries.sort { $0.weight < $1.weight }
        guard let index = entries.firstIndex(where: {
            ($0.key.start == start && $0.key.end == end) || ($0.key.start == end && $0.key.end == start)
        }) else {
            return false
        }
        let swapIndex = moveUp ? index + 1 : index - 1
        if swapIndex < 0 || swapIndex >= entries.count {
            return false
        }
        entries.swapAt(index, swapIndex)
        for (order, entry) in entries.enumerated() {
            guard var states = edgeAssets[entry.key] else { continue }
            for state in states.keys {
                states[state]?.weight = order
            }
            edgeAssets[entry.key] = states
        }
        return true
    }

    func restLength(unitName: String, endId: Int) -> CGFloat {
        restModel[unitName]?[endId] ?? 0
    }

    func states(for fullname: String) -> [Int] {
        let name = Self.removeNumber(fullname)
        var numbers = Set<Int>()
        for (key, states) in edgeAssets where key.unitName == name {
            numbers.formUnion(states.keys)
        }
        return numbers.sorted()
    }

    func multiframedAssets() -> Set<String> {
        Set(edgeAssets.compactMap { $0.value.count > 1 ? $0.key.unitName : nil })
    }

    nonisolated static func removeNumber(_ name: String) -> String {
        guard let hash = name.firstIndex(of: "#") else { return name }
        return String(name[..<hash])
    }

    private static func emptyBitmap(width: Int, height: Int) -> CGImage? {
        if width < 1 || height < 1 {
            assertionFailure("UnitAssets emptyBitmap \(width)x\(height)")
            return nil
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func install(_ rows: [EdgeAssetRow], zip: Data) throws {
        let names = Set(try ZipStore.namesThrowing(in: zip))
        var bitmaps: [String: CGImage] = [:]
        func bitmap(named name: String) throws -> CGImage {
            if let cached = bitmaps[name] { return cached }
            let data = try ZipStore.dataThrowing(named: name, in: zip)
            let image = try PNG.loaded(from: data, name: name)
            bitmaps[name] = image
            return image
        }

        var assets: [EdgeAsset] = []
        for row in rows {
            if !names.contains(row.bmName) {
                continue
            }
            assets.append(
                EdgeAsset(
                    unitName: row.unitName,
                    start: row.start,
                    end: row.end,
                    xOffset: row.xOffset,
                    yOffset: row.yOffset,
                    weight: row.weight,
                    state: row.state,
                    nativeFlipped: row.nativeFlipped,
                    bmName: row.bmName,
                    bitmap: try bitmap(named: row.bmName),
                    sample: row.sample,
                    paintBuffer: nil,
                    svgName: row.svgName,
                    commandScale: row.commandScale
                )
            )
        }
        if assets.isEmpty {
            throw ItemLoadError("UnitAssets zip has no packed bitmaps for \(rows.map(\.bmName))")
        }

        for asset in assets {
            let key = EdgeKey(
                unitName: asset.unitName,
                start: asset.start,
                end: asset.end,
                flipped: asset.nativeFlipped
            )
            edgeAssets[key] = [:]
        }
        for asset in assets {
            let key = EdgeKey(
                unitName: asset.unitName,
                start: asset.start,
                end: asset.end,
                flipped: asset.nativeFlipped
            )
            var states = edgeAssets[key] ?? [:]
            states[asset.state] = asset
            edgeAssets[key] = states
        }
        attachSidecars(zip: zip, unitName: assets[0].unitName)
    }

    /// Manifest entry name for paint-buffer sidecars.
    static let sidecarManifest = "bonepaper.json"

    /// Sidecar entry for `bmName` (which already ends in `.png`): `bone_1_2.png` keeps `bone_1_2.png.x2.png`.
    static func sidecarEntry(for bmName: String) -> String {
        bmName + ".x2.png"
    }

    /// Sidecar entries for save: one `<bm>.x2.png` per buffered picture plus the manifest.
    /// `pngs` must be the exact 1x bytes being saved (from `pngFiles`), keyed by bmName; the manifest
    /// hashes those so load detects a picture replaced without its buffer. Empty when no buffers and no drawingConfig.
    func sidecarFiles(unitName: String, pngs: [String: Data]) throws -> [(name: String, data: Data)] {
        let name = Self.removeNumber(unitName)
        var seen = Set<String>()
        var files: [(name: String, data: Data)] = []
        let cleanConfig = drawingConfigs[name]?.sanitized()
        let savedConfig = (cleanConfig?.isEmpty == false) ? cleanConfig : nil
        var manifest = BonePaperManifest(version: 1, buffers: [:], drawingConfig: savedConfig)
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if seen.contains(asset.bmName) { continue }
                seen.insert(asset.bmName)
                guard let buffer = asset.paintBuffer else { continue }
                guard let png = pngs[asset.bmName] else {
                    throw SceneLoadError(message: "UnitAssets sidecar '\(asset.bmName)' has no live PNG")
                }
                let entry = Self.sidecarEntry(for: asset.bmName)
                files.append((name: entry, data: buffer))
                manifest.buffers[asset.bmName] = BonePaperManifest.Entry(entry: entry, sha256: Self.sha256Hex(png))
            }
        }
        guard !files.isEmpty || savedConfig != nil else { return [] }
        files.append((name: Self.sidecarManifest, data: try manifest.encode()))
        return files.sorted { $0.name < $1.name }
    }

    /// Attach validated sidecar buffers to the just-installed edge assets. Anything unexpected —
    /// missing manifest, malformed JSON, replaced picture, bad size — drops the buffer with a log,
    /// never a crash. The picture itself always loads.
    private func attachSidecars(zip: Data, unitName: String) {
        let names: Set<String>
        do {
            names = Set(try ZipStore.namesThrowing(in: zip))
        } catch {
            print("UnitAssets sidecars ignored: \(error)")
            return
        }
        guard names.contains(Self.sidecarManifest) else { return }
        let manifest: BonePaperManifest
        do {
            manifest = try JSONDecoder().decode(
                BonePaperManifest.self,
                from: try ZipStore.dataThrowing(named: Self.sidecarManifest, in: zip)
            )
        } catch {
            print("UnitAssets \(Self.sidecarManifest) ignored: \(error)")
            return
        }
        let unitKey = Self.removeNumber(unitName)
        if let config = manifest.drawingConfig?.sanitized(), !config.isEmpty {
            drawingConfigs[unitKey] = config
        }
        var sidecarCache: [String: (data: Data, image: CGImage)?] = [:]
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states {
                guard let record = manifest.buffers[asset.bmName] else { continue }
                let cached: (data: Data, image: CGImage)?
                if let seen = sidecarCache[asset.bmName] {
                    cached = seen
                } else {
                    let loaded = Self.validatedSidecar(
                        record: record,
                        asset: asset,
                        zip: zip,
                        names: names
                    )
                    sidecarCache[asset.bmName] = loaded
                    cached = loaded
                }
                guard let cached else { continue }
                var updated = asset
                updated.adoptSidecar(cached.data, name: asset.bmName, predecoded: cached.image)
                next[state] = updated
                changed = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
    }

    private static func predecodedSidecar(_ data: Data?, bitmap: CGImage, name: String) -> CGImage? {
        guard let data, !data.isEmpty, let raw = PNG.decodedImage(from: data) else { return nil }
        let factor = BonePaperDocument.sample
        guard raw.width == bitmap.width * factor,
              raw.height == bitmap.height * factor else { return nil }
        guard DevFlags.decodedBoneBitmaps else { return raw }
        do {
            return try PNG.decodedBitmap(raw, name: name)
        } catch {
            print("UnitAssets '\(name)' sidecar decode failed: \(error)")
            return nil
        }
    }

    /// Validated sidecar bytes and decoded image when they still describe `asset.bitmap`, nil with a log otherwise.
    private static func validatedSidecar(
        record: BonePaperManifest.Entry,
        asset: EdgeAsset,
        zip: Data,
        names: Set<String>
    ) -> (data: Data, image: CGImage)? {
        guard names.contains(record.entry) else {
            print("UnitAssets '\(asset.bmName)' sidecar missing '\(record.entry)'")
            return nil
        }
        guard names.contains(asset.bmName) else {
            print("UnitAssets '\(asset.bmName)' picture missing beside its sidecar")
            return nil
        }
        let png: Data
        let data: Data
        do {
            png = try ZipStore.dataThrowing(named: asset.bmName, in: zip)
            data = try ZipStore.dataThrowing(named: record.entry, in: zip)
        } catch {
            print("UnitAssets '\(asset.bmName)' sidecar ignored: \(error)")
            return nil
        }
        if sha256Hex(png) != record.sha256 {
            print("UnitAssets '\(asset.bmName)' sidecar stale, picture changed")
            return nil
        }
        guard let raw = PNG.decodedImage(from: data) else {
            print("UnitAssets '\(asset.bmName)' sidecar is not a PNG")
            return nil
        }
        let sample = BonePaperDocument.sample
        guard raw.width == asset.bitmap.width * sample,
              raw.height == asset.bitmap.height * sample else {
            print("UnitAssets '\(asset.bmName)' sidecar size \(raw.width)x\(raw.height) != \(asset.bitmap.width * sample)x\(asset.bitmap.height * sample)")
            return nil
        }
        let decoded: CGImage
        if DevFlags.decodedBoneBitmaps {
            do {
                decoded = try PNG.decodedBitmap(raw, name: asset.bmName)
            } catch {
                print("UnitAssets '\(asset.bmName)' sidecar decode failed: \(error)")
                return nil
            }
        } else {
            decoded = raw
        }
        return (data, decoded)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func captureRest(from model: StickmanUnit) throws {
        var lengths: [Int: CGFloat] = [:]
        for point in model.points {
            if point.isBase { continue }
            guard let parentId = point.parentId else { continue }
            let parent = try model.point(id: parentId)
            let rest = hypot(point.x - parent.x, point.y - parent.y)
            if rest > 0 {
                lengths[point.id] = rest
            }
        }
        restModel[Self.removeNumber(model.name)] = lengths
    }

    private func edgeStates(_ key: EdgeKey) -> [Int: EdgeAsset] {
        if let existing = edgeAssets[key] {
            return existing
        }
        let empty: [Int: EdgeAsset] = [:]
        edgeAssets[key] = empty
        return empty
    }
}

nonisolated struct EdgeAssetRow {
    var unitName: String
    var start: Int
    var end: Int
    var xOffset: CGFloat
    var yOffset: CGFloat
    var weight: Int
    var state: Int
    var nativeFlipped: Bool
    var bmName: String
    var svgName: String?
    var commandScale: String?
    /// Bitmap pixels per page pixel. Absent in XML means `1`.
    var sample: Int = 1
}

/// Which `.x2.png` buffer belongs to which picture, plus the SHA-256 of the 1x bytes it was saved with.
struct BonePaperManifest: Codable {
    struct Entry: Codable {
        var entry: String
        var sha256: String
    }

    var version: Int
    var buffers: [String: Entry]
    var drawingConfig: BonePaperDrawingConfig?

    func encode() throws -> Data {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            throw SceneLoadError(message: "UnitAssets bonepaper.json encode: \(error)")
        }
    }
}

private enum PNG {
    /// Nil instead of a crash for untrusted bytes (sidecars).
    static func decodedImage(from data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func loaded(from data: Data, name: String) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw ItemLoadError("UnitAssets '\(name)' has no data provider")
        }
        guard let image = CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw ItemLoadError("UnitAssets '\(name)' is not a PNG")
        }
        if DevFlags.decodedBoneBitmaps {
            return try decodedBitmap(image, name: name)
        }
        return image
    }

    /// Copy PNG pixels into a plain bitmap so later draws do not inflate the file again.
    static func decodedBitmap(_ source: CGImage, name: String) throws -> CGImage {
        let width = source.width
        let height = source.height
        if width < 1 || height < 1 {
            throw ItemLoadError("UnitAssets '\(name)' decoded size \(width)x\(height)")
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ItemLoadError("UnitAssets '\(name)' could not allocate \(width)x\(height)")
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw ItemLoadError("UnitAssets '\(name)' decoded bitmap failed")
        }
        return image
    }

    static func data(from image: CGImage, name: String) throws -> Data {
        if image.width < 1 || image.height < 1 {
            throw SceneLoadError(message: "UnitAssets '\(name)' encode size \(image.width)x\(image.height)")
        }
        guard let data = UIImage(cgImage: image).pngData(), !data.isEmpty else {
            throw SceneLoadError(message: "UnitAssets '\(name)' PNG encode failed")
        }
        return data
    }
}

enum AssetsXML {
    static func serialize(rows: [EdgeAssetRow], fullName: String) throws -> Data {
        if fullName.isEmpty {
            throw SceneLoadError(message: "AssetsXML serialize has empty unit name")
        }
        if rows.isEmpty {
            throw SceneLoadError(message: "AssetsXML serialize '\(fullName)' has no rows")
        }
        var xml = XMLWrite.header
        xml += "<unit"
        xml += XMLWrite.attr("name", fullName)
        xml += XMLWrite.attr("version", XMLWrite.versionCode())
        xml += ">\n"
        for row in rows {
            xml += "<edgeAsset"
            xml += XMLWrite.attr("start", "\(row.start)")
            xml += XMLWrite.attr("end", "\(row.end)")
            xml += XMLWrite.attr("weight", "\(row.weight)")
            xml += XMLWrite.attr("x_offset", XMLWrite.float(row.xOffset))
            xml += XMLWrite.attr("y_offset", XMLWrite.float(row.yOffset))
            xml += XMLWrite.attr("state", "\(row.state)")
            xml += XMLWrite.attr("bm", row.bmName)
            if row.nativeFlipped {
                xml += XMLWrite.attr("flipped", "true")
            }
            if let scale = row.commandScale {
                xml += XMLWrite.attr("command_scale", scale)
            }
            if let svg = row.svgName {
                xml += XMLWrite.attr("svg", svg)
            }
            if row.sample != 1 {
                xml += XMLWrite.attr("sample", "\(row.sample)")
            }
            xml += " />\n"
        }
        xml += "</unit>\n"
        return try XMLWrite.data(xml)
    }

    static func parse(_ data: Data) throws -> [EdgeAssetRow] {
        let parser = XMLParser(data: data)
        let sink = Sink()
        parser.delegate = sink
        let ok = parser.parse()
        if let message = sink.failure {
            throw ItemLoadError(message)
        }
        if !ok {
            let detail = parser.parserError.map { String(describing: $0) } ?? "unknown"
            throw ItemLoadError("UnitAssets assets.xml parse failed: \(detail)")
        }
        if sink.assets.isEmpty {
            throw ItemLoadError("UnitAssets assets.xml has no edgeAsset rows")
        }
        return sink.assets
    }

    nonisolated private final class Sink: NSObject, XMLParserDelegate {
        var unitName: String?
        var assets: [EdgeAssetRow] = []
        var failure: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes: [String: String] = [:]
        ) {
            if failure != nil { return }
            if elementName == "unit" {
                unitName = attributes["name"].map(PackAlias.resolveUnitName)
                return
            }
            if elementName != "edgeAsset" { return }
            guard let name = unitName else {
                fail(parser, "UnitAssets edgeAsset outside unit")
                return
            }
            guard let startText = attributes["start"], let start = Int(startText) else {
                fail(parser, "UnitAssets edgeAsset missing start")
                return
            }
            guard let endText = attributes["end"], let end = Int(endText) else {
                fail(parser, "UnitAssets edgeAsset missing end")
                return
            }
            guard let xText = attributes["x_offset"], let x = Double(xText) else {
                fail(parser, "UnitAssets edgeAsset \(start)-\(end) missing x_offset")
                return
            }
            guard let yText = attributes["y_offset"], let y = Double(yText) else {
                fail(parser, "UnitAssets edgeAsset \(start)-\(end) missing y_offset")
                return
            }
            guard let bm = attributes["bm"], !bm.isEmpty else {
                fail(parser, "UnitAssets edgeAsset \(start)-\(end) missing bm")
                return
            }
            let sample: Int
            if let text = attributes["sample"] {
                guard let parsed = Int(text), parsed >= 1 else {
                    fail(parser, "UnitAssets edgeAsset \(start)-\(end) sample '\(text)'")
                    return
                }
                sample = parsed
            } else {
                sample = 1
            }
            assets.append(
                EdgeAssetRow(
                    unitName: name,
                    start: start,
                    end: end,
                    xOffset: CGFloat(x),
                    yOffset: CGFloat(y),
                    weight: Int(attributes["weight"] ?? "") ?? 0,
                    state: Int(attributes["state"] ?? "") ?? UnitAssets.stateDefault,
                    nativeFlipped: attributes["flipped"] == "true",
                    bmName: bm,
                    svgName: attributes["svg"],
                    commandScale: attributes["command_scale"],
                    sample: sample
                )
            )
        }

        private func fail(_ parser: XMLParser, _ message: String) {
            if failure == nil {
                failure = message
            }
            parser.abortParsing()
        }
    }
}
