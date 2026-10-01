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
        /// Compressed PNG of the full-resolution (`BonePaperDocument.sample` times `bitmap`) paint buffer,
        /// for lossless reopen in the Paper Drawer. Nil when the picture was never drawn or edited outside it.
        /// Touch only through `paintBuffer(bmName:)`, `replaceBitmap`, and `evictPaintBuffers`.
        var paintBuffer: Data?
        var svgName: String?
        var commandScale: String?
    }

    struct GalleryBone: Identifiable {
        var id: String { bmName }
        var bmName: String
        var thumb: CGImage
    }

    private var edgeAssets: [EdgeKey: [Int: EdgeAsset]] = [:]
    /// Unattached gallery pictures (Android bone-picture repo rows with no edge yet).
    private var looseBones: [String: EdgeAsset] = [:]
    private var restModel: [String: [Int: CGFloat]] = [:]
    private var archives: [String: StoredArchive] = [:]

    struct StoredArchive {
        var entryName: String
        var zip: Data
    }

    struct Snapshot {
        var edgeAssets: [EdgeKey: [Int: EdgeAsset]]
        var looseBones: [String: EdgeAsset]
    }

    func snapshot() -> Snapshot {
        Snapshot(edgeAssets: edgeAssets, looseBones: looseBones)
    }

    func restore(_ snapshot: Snapshot) {
        edgeAssets = snapshot.edgeAssets
        looseBones = snapshot.looseBones
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
            captureRest(from: model)
            return
        }
        let xml = try ZipStore.dataThrowing(named: "assets.xml", in: zip)
        let parsed = try AssetsXML.parse(xml)
        try install(parsed, zip: zip)
        archives[key] = StoredArchive(entryName: entryName, zip: zip)
        captureRest(from: model)
    }

    func archive(for unitName: String) -> StoredArchive {
        let key = Self.removeNumber(unitName)
        guard let stored = archives[key] else {
            fatalError("UnitAssets missing archive for '\(key)'")
        }
        return stored
    }

    static func atiEntryName(packName: String, systemName: String) -> String {
        if systemName.isEmpty {
            fatalError("UnitAssets empty systemName")
        }
        if packName == "@" {
            return systemName + ".ati"
        }
        if packName.isEmpty {
            fatalError("UnitAssets empty packName for '\(systemName)'")
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
            fatalError("UnitAssets unit name '\(unitName)' has empty own name")
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
            let start = unit.point(id: edge.from)
            let end = unit.point(id: edge.to)
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
            fatalError("UnitAssets combinedBounds '\(unit.name)' has no points")
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

    /// Unique bone bitmaps for the gallery rail, ordered by first-seen weight then bmName.
    func galleryBones(unitName: String) -> [GalleryBone] {
        let name = Self.removeNumber(unitName)
        struct Seen {
            var bmName: String
            var thumb: CGImage
            var weight: Int
        }
        var byBm: [String: Seen] = [:]
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if byBm[asset.bmName] != nil { continue }
                byBm[asset.bmName] = Seen(bmName: asset.bmName, thumb: asset.bitmap, weight: asset.weight)
            }
        }
        for asset in looseBones.values where asset.unitName == name {
            if byBm[asset.bmName] != nil { continue }
            byBm[asset.bmName] = Seen(bmName: asset.bmName, thumb: asset.bitmap, weight: asset.weight)
        }
        return byBm.values
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
            fatalError("UnitAssets attachBone empty bmName")
        }
        let name = Self.removeNumber(unitName)
        guard let template = firstAsset(bmName: bmName, unitName: name) else {
            fatalError("UnitAssets attachBone unknown bm '\(bmName)' for '\(name)'")
        }
        let key = EdgeKey(
            unitName: name,
            start: start,
            end: end,
            flipped: template.nativeFlipped
        )
        var asset = template
        asset.unitName = name
        asset.start = start
        asset.end = end
        asset.weight = nextWeight(unitName: name)
        asset.state = Self.stateDefault
        edgeAssets[key] = [Self.stateDefault: asset]
        looseBones.removeValue(forKey: bmName)
    }

    /// Android `BonePictureFactory.createEmpty` + `Constants.DEFAULT_LENGTH` Kurwa hint.
    func createEmptyGalleryBone(unitName: String, length: CGFloat = defaultBoneLength) -> EdgeAsset {
        if length <= 0 {
            fatalError("UnitAssets gallery bone length is \(length)")
        }
        let name = Self.removeNumber(unitName)
        let asset = makeEmptyAsset(
            unitName: name,
            start: -1,
            end: -1,
            length: length,
            bmName: uniqueGalleryBmName()
        )
        if looseBones[asset.bmName] != nil {
            fatalError("UnitAssets duplicate loose bm '\(asset.bmName)'")
        }
        looseBones[asset.bmName] = asset
        return asset
    }

    /// FastPainter empty frame: square `2*length`, pad so the bone sits on the mid-line.
    func ensureDrawable(
        start: Int,
        end: Int,
        unitName: String,
        length: CGFloat
    ) -> EdgeAsset {
        let name = Self.removeNumber(unitName)
        let key = EdgeKey(unitName: name, start: start, end: end, flipped: false)
        if let existing = getDrawable(key, state: Self.stateDefault) {
            return existing
        }
        let asset = makeEmptyAsset(
            unitName: name,
            start: start,
            end: end,
            length: length,
            bmName: uniqueBmName(start: start, end: end)
        )
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

    /// Slide by `dx`/`dy`, then scale and rotate the bitmap around the joint (`-xOffset`, `-yOffset`).
    func applyShift(bmName: String, dx: CGFloat, dy: CGFloat, scale: CGFloat, rotation: CGFloat) {
        if scale <= 0 {
            fatalError("UnitAssets applyShift '\(bmName)' scale \(scale)")
        }
        if dx != 0 || dy != 0 {
            applyShift(bmName: bmName, dx: dx, dy: dy)
        }
        if abs(scale - 1) > 0.001 || abs(rotation) > 0.001 {
            applyPictureTransform(bmName: bmName, factor: scale, radians: rotation)
        }
    }

    /// Android `PictureFrame.applyModifier`: `xpad -= dx` (`xOffset` is `-xpad`).
    func applyShift(bmName: String, dx: CGFloat, dy: CGFloat) {
        if bmName.isEmpty {
            fatalError("UnitAssets applyShift empty bmName")
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
            fatalError("UnitAssets applyShift unknown bm '\(bmName)'")
        }
    }

    /// Resample `bmName` around the joint so that pixel stays on the bone start.
    private func applyPictureTransform(bmName: String, factor: CGFloat, radians: CGFloat) {
        if factor <= 0 {
            fatalError("UnitAssets picture scale \(factor) for '\(bmName)'")
        }
        let matches = assets(bmName: bmName)
        if matches.isEmpty {
            fatalError("UnitAssets picture scale unknown bm '\(bmName)'")
        }
        let source = matches[0]
        for asset in matches.dropFirst() {
            if asset.xOffset != source.xOffset || asset.yOffset != source.yOffset {
                fatalError("UnitAssets '\(bmName)' offsets differ across edges")
            }
        }
        let jointX = -source.xOffset
        let jointY = -source.yOffset
        let scaled = BonePictureScale.transform(
            source.bitmap,
            aroundX: jointX,
            y: jointY,
            factor: factor,
            radians: radians
        )
        let xOffset = -scaled.jointX
        let yOffset = -scaled.jointY
        // Keep the paint buffer in step with the bitmap, so a later Paper Drawer session reopens
        // the transformed drawing instead of the upscaled 1x picture.
        //
        // Only scale/rotate reach this path: pure drags change `xOffset`/`yOffset` alone (see the
        // `applyShift(dx:dy:)` overload) and leave every pixel — bitmap and buffer — untouched.
        // A transform resamples instead, which softens edges by nature of interpolation. That
        // softening is inherent to the op and identical with or without this feature; the buffer
        // just preserves the transformed pixels exactly instead of adding another upscale on top.
        // Note the buffer is resampled at 2x while the bitmap is resampled at 1x, so reopening
        // from the buffer stays strictly sharper than reopening from the transformed bitmap.
        //
        // The buffer runs through the same `BonePictureScale.transform` with the joint doubled
        // (`joint * sample`), because buffer pixels are `sample` times bitmap pixels and the joint
        // must stay on the same drawing point. The op is affine, so the buffer span is exactly
        // twice the bitmap span — but each side rounds its canvas up independently
        // (`pixelW = ceil(span)`), and doubling does not commute with rounding up. Example:
        // a bitmap span of 10.3 rounds to 11 px, while the buffer span of 20.6 rounds to 21 px
        // instead of the required 11 * 2 = 22. Roughly half of all rotate/scale ops land this way.
        //
        // The reopen contract demands an exact double size (see `validatedBuffer` in
        // `SkeletonScreen` and `BonePaperScreen.init`), so a buffer that lands a pixel off is
        // dropped with a log rather than padded or force-fit: padding would shift pixel alignment
        // and silently move the drawing half a pixel, while relaxing the contract would reintroduce
        // the very scaling this feature removes. A dropped buffer only means that one bone reopens
        // from the 1x path — today's behavior, never a regression. A stored buffer is therefore
        // always either exact current state or absent; there is no stale low-quality copy.
        var scaledBuffer: Data?
        if let data = source.paintBuffer {
            let bufferImage = PNG.image(from: data, name: bmName)
            if bufferImage.width == source.bitmap.width * BonePaperDocument.sample,
               bufferImage.height == source.bitmap.height * BonePaperDocument.sample {
                let sample = CGFloat(BonePaperDocument.sample)
                let scaledBuf = BonePictureScale.transform(
                    bufferImage,
                    aroundX: jointX * sample,
                    y: jointY * sample,
                    factor: factor,
                    radians: radians
                )
                if scaledBuf.image.width == scaled.image.width * BonePaperDocument.sample,
                   scaledBuf.image.height == scaled.image.height * BonePaperDocument.sample {
                    scaledBuffer = PNG.data(from: scaledBuf.image, name: bmName)
                } else {
                    print("UnitAssets '\(bmName)' dropped paint buffer after transform: \(scaledBuf.image.width)x\(scaledBuf.image.height) != \(scaled.image.width * BonePaperDocument.sample)x\(scaled.image.height * BonePaperDocument.sample)")
                }
            } else {
                print("UnitAssets '\(bmName)' dropped stale paint buffer: \(bufferImage.width)x\(bufferImage.height)")
            }
        }
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states where asset.bmName == bmName {
                var updated = asset
                updated.bitmap = scaled.image
                updated.paintBuffer = scaledBuffer
                updated.xOffset = xOffset
                updated.yOffset = yOffset
                next[state] = updated
                changed = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
        if var loose = looseBones[bmName] {
            loose.bitmap = scaled.image
            loose.paintBuffer = scaledBuffer
            loose.xOffset = xOffset
            loose.yOffset = yOffset
            looseBones[bmName] = loose
        }
    }

    private func assets(bmName: String) -> [EdgeAsset] {
        var found: [EdgeAsset] = []
        for states in edgeAssets.values {
            for asset in states.values where asset.bmName == bmName {
                found.append(asset)
            }
        }
        if let loose = looseBones[bmName] {
            found.append(loose)
        }
        return found
    }

    /// Compressed PNG paint buffer for `bmName`, for lossless reopen in the Paper Drawer. Nil when absent.
    func paintBuffer(bmName: String) -> Data? {
        assets(bmName: bmName).first?.paintBuffer
    }

    /// PNG bytes for a paint buffer, for the screen layer (the `PNG` helper is file-private).
    static func pngData(from image: CGImage, name: String) -> Data {
        PNG.data(from: image, name: name)
    }

    /// Decoded buffer image, nil for bad bytes. Loud variant is `PNG.image`, kept for pack art.
    static func pngImage(from data: Data) -> CGImage? {
        PNG.decodedImage(from: data)
    }

    /// Drops every paint buffer. Bitmaps are untouched; pictures reopen from the upscaled 1x path.
    func evictPaintBuffers() {
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states where asset.paintBuffer != nil {
                var updated = asset
                updated.paintBuffer = nil
                next[state] = updated
                changed = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
        for (name, var loose) in looseBones where loose.paintBuffer != nil {
            loose.paintBuffer = nil
            looseBones[name] = loose
        }
    }

    func replaceBitmap(bmName: String, image: CGImage, buffer: Data? = nil, extraLeft: CGFloat = 0, extraTop: CGFloat = 0) {
        if bmName.isEmpty {
            fatalError("UnitAssets replaceBitmap empty bmName")
        }
        if image.width < 1 || image.height < 1 {
            fatalError("UnitAssets replaceBitmap '\(bmName)' size \(image.width)x\(image.height)")
        }
        if let buffer {
            let decoded = PNG.image(from: buffer, name: bmName)
            if decoded.width != image.width * BonePaperDocument.sample
                || decoded.height != image.height * BonePaperDocument.sample {
                fatalError("UnitAssets replaceBitmap '\(bmName)' buffer \(decoded.width)x\(decoded.height) != \(image.width * BonePaperDocument.sample)x\(image.height * BonePaperDocument.sample)")
            }
        }
        var found = false
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states where asset.bmName == bmName {
                var updated = asset
                updated.bitmap = image
                updated.paintBuffer = buffer
                updated.xOffset -= extraLeft
                updated.yOffset -= extraTop
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
            loose.paintBuffer = buffer
            loose.xOffset -= extraLeft
            loose.yOffset -= extraTop
            looseBones[bmName] = loose
            found = true
        }
        if !found {
            fatalError("UnitAssets replaceBitmap unknown bm '\(bmName)'")
        }
    }

    func pngFiles(unitName: String) -> [(name: String, data: Data)] {
        let name = Self.removeNumber(unitName)
        var seen: Set<String> = []
        var files: [(name: String, data: Data)] = []
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if seen.contains(asset.bmName) { continue }
                seen.insert(asset.bmName)
                files.append((name: asset.bmName, data: PNG.data(from: asset.bitmap, name: asset.bmName)))
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
    ) -> EdgeAsset {
        let safe = max(length, 1)
        let side = min(1024, max(2, Int(ceil(safe * 2))))
        let bitmap = Self.emptyBitmap(width: side, height: side)
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

    private func uniqueBmName(start: Int, end: Int) -> String {
        let used = usedBmNames()
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
                        commandScale: asset.commandScale
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

    private static func emptyBitmap(width: Int, height: Int) -> CGImage {
        if width < 1 || height < 1 {
            fatalError("UnitAssets emptyBitmap \(width)x\(height)")
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
            fatalError("UnitAssets emptyBitmap could not create \(width)x\(height)")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("UnitAssets emptyBitmap \(width)x\(height) makeImage failed")
        }
        return image
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
        attachSidecars(zip: zip)
    }

    /// Manifest entry name for paint-buffer sidecars.
    static let sidecarManifest = "bonepaper.json"

    /// Sidecar entry for `bmName` (which already ends in `.png`): `bone_1_2.png` keeps `bone_1_2.png.x2.png`.
    static func sidecarEntry(for bmName: String) -> String {
        bmName + ".x2.png"
    }

    /// Sidecar entries for save: one `<bm>.x2.png` per buffered picture plus the manifest.
    /// `pngs` must be the exact 1x bytes being saved (from `pngFiles`), keyed by bmName; the manifest
    /// hashes those so load detects a picture replaced without its buffer. Empty when no buffers.
    func sidecarFiles(unitName: String, pngs: [String: Data]) -> [(name: String, data: Data)] {
        let name = Self.removeNumber(unitName)
        var seen = Set<String>()
        var files: [(name: String, data: Data)] = []
        var manifest = BonePaperManifest(version: 1, buffers: [:])
        for (key, states) in edgeAssets where key.unitName == name {
            for asset in states.values {
                if seen.contains(asset.bmName) { continue }
                seen.insert(asset.bmName)
                guard let buffer = asset.paintBuffer else { continue }
                guard let png = pngs[asset.bmName] else {
                    fatalError("UnitAssets sidecar '\(asset.bmName)' has no live PNG")
                }
                let entry = Self.sidecarEntry(for: asset.bmName)
                files.append((name: entry, data: buffer))
                manifest.buffers[asset.bmName] = BonePaperManifest.Entry(entry: entry, sha256: Self.sha256Hex(png))
            }
        }
        guard !files.isEmpty else { return [] }
        files.append((name: Self.sidecarManifest, data: manifest.encode()))
        return files.sorted { $0.name < $1.name }
    }

    /// Attach validated sidecar buffers to the just-installed edge assets. Anything unexpected —
    /// missing manifest, malformed JSON, replaced picture, bad size — drops the buffer with a log,
    /// never a crash. The picture itself always loads.
    private func attachSidecars(zip: Data) {
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
        for (key, states) in edgeAssets {
            var next = states
            var changed = false
            for (state, asset) in states {
                guard let record = manifest.buffers[asset.bmName] else { continue }
                guard let buffer = Self.validatedSidecar(
                    record: record,
                    asset: asset,
                    zip: zip,
                    names: names
                ) else { continue }
                var updated = asset
                updated.paintBuffer = buffer
                next[state] = updated
                changed = true
            }
            if changed {
                edgeAssets[key] = next
            }
        }
    }

    /// Raw sidecar bytes when they still describe `asset.bitmap`, nil with a log otherwise.
    private static func validatedSidecar(
        record: BonePaperManifest.Entry,
        asset: EdgeAsset,
        zip: Data,
        names: Set<String>
    ) -> Data? {
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
        guard let image = PNG.decodedImage(from: data) else {
            print("UnitAssets '\(asset.bmName)' sidecar is not a PNG")
            return nil
        }
        let sample = BonePaperDocument.sample
        guard image.width == asset.bitmap.width * sample,
              image.height == asset.bitmap.height * sample else {
            print("UnitAssets '\(asset.bmName)' sidecar size \(image.width)x\(image.height) != \(asset.bitmap.width * sample)x\(asset.bitmap.height * sample)")
            return nil
        }
        return data
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func captureRest(from model: StickmanUnit) {
        var lengths: [Int: CGFloat] = [:]
        for point in model.points {
            if point.isBase { continue }
            guard let parentId = point.parentId else { continue }
            let parent = model.point(id: parentId)
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
}

/// Which `.x2.png` buffer belongs to which picture, plus the SHA-256 of the 1x bytes it was saved with.
struct BonePaperManifest: Codable {
    struct Entry: Codable {
        var entry: String
        var sha256: String
    }

    var version: Int
    var buffers: [String: Entry]

    func encode() -> Data {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            fatalError("UnitAssets bonepaper.json encode: \(error)")
        }
    }
}

private enum PNG {
    /// Nil instead of a crash for untrusted bytes (sidecars); `image(from:name:)` stays loud for pack art.
    static func decodedImage(from data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func image(from data: Data, name: String) -> CGImage {
        do {
            return try loaded(from: data, name: name)
        } catch {
            fatalError(ItemLoadError.text(error))
        }
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
    private static func decodedBitmap(_ source: CGImage, name: String) throws -> CGImage {
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

    static func data(from image: CGImage, name: String) -> Data {
        if image.width < 1 || image.height < 1 {
            fatalError("UnitAssets '\(name)' encode size \(image.width)x\(image.height)")
        }
        guard let data = UIImage(cgImage: image).pngData(), !data.isEmpty else {
            fatalError("UnitAssets '\(name)' PNG encode failed")
        }
        return data
    }
}

enum AssetsXML {
    static func serialize(rows: [EdgeAssetRow], fullName: String) -> Data {
        if fullName.isEmpty {
            fatalError("AssetsXML serialize has empty unit name")
        }
        if rows.isEmpty {
            fatalError("AssetsXML serialize '\(fullName)' has no rows")
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
            xml += " />\n"
        }
        xml += "</unit>\n"
        return XMLWrite.data(xml)
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
                    commandScale: attributes["command_scale"]
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
