# Bone Split Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive Bone Split tool to the iOS Skeleton Editor (`at_elements`) that splits a bone `S → B` and its attached bitmap into two overlapping halves (`S → A` and `A → B`) joined by a circular disc of user-controlled radius \(R\).

**Architecture:** `BonePictureSplit` handles pure CoreGraphics vector-path clipping and tight horizontal cropping of `1×` bitmaps and `2×` `BonePaper` paint buffers. `StickmanUnit.splitEdge` mutates the skeleton point tree, and `UnitAssets.splitEdgeAssets` updates edge assets, draw-order weights, and unattached gallery copies. `SkeletonEditSession` holds the live `BoneSplitDraft`, `SkeletonCanvas` renders and manipulates the circle/cut-line/handle gizmo, and `SkeletonScreen` + `SkeletonBonesTools` provide the entry button and floating `Cancel / Apply` confirmation bar.

**Tech Stack:** Swift, SwiftUI, CoreGraphics, UIKit (`UIGraphicsImageRenderer`, `CGContext`).

## Global Constraints

- Do NOT build iOS or Android (`xcodebuild`, `./gradlew`) unless the user explicitly orders it directly.
- Do NOT write automated unit tests unless the user explicitly asks for them.
- Prefer loud failures (`throw SceneLoadError`, `assertionFailure`) over silent fake defaults.
- Preserve `2×` `BonePaperDocument.sample` paint buffers across splits by doubling integer `1×` crop bounds so the buffer size is strictly `2 * width × 2 * height`.

---

### Task 1: Pure Bitmap & Paint-Buffer Splitter (`BonePictureSplit`)

**Files:**
- Create: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/BonePictureSplit.swift`

**Interfaces:**
- Produces:
  - `enum BonePictureSplit`
  - `struct BonePictureSplit.Half { var image: CGImage; var paintBuffer: Data?; var xOffset: CGFloat; var yOffset: CGFloat }`
  - `struct BonePictureSplit.Pair { var proximal: Half; var distal: Half }`
  - `static func split(bitmap: CGImage, paintBuffer: Data?, xOffset: CGFloat, yOffset: CGFloat, splitDistance: CGFloat, radius: CGFloat, name: String) throws -> Pair`
  - `static func defaultRadius(bitmap: CGImage, xOffset: CGFloat, yOffset: CGFloat, splitDistance: CGFloat, boneLength: CGFloat) -> CGFloat`

- [ ] **Step 1: Create `Shared/Model/BonePictureSplit.swift`**

Write the complete implementation of `BonePictureSplit`:

```swift
import BonePaper
import CoreGraphics
import Foundation
import UIKit

/// Splits a bone bitmap (and its optional 2x BonePaper paint buffer) at `splitDistance`
/// along the bone's local +X axis, giving both halves the circular disc `D(split, radius)`.
enum BonePictureSplit {
    struct Half {
        var image: CGImage
        var paintBuffer: Data?
        var xOffset: CGFloat
        var yOffset: CGFloat
    }

    struct Pair {
        var proximal: Half
        var distal: Half
    }

    static func split(
        bitmap: CGImage,
        paintBuffer: Data?,
        xOffset: CGFloat,
        yOffset: CGFloat,
        splitDistance: CGFloat,
        radius: CGFloat,
        name: String
    ) throws -> Pair {
        if splitDistance <= 0 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' splitDistance \(splitDistance) <= 0")
        }
        if radius <= 0 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' radius \(radius) <= 0")
        }
        let width = bitmap.width
        let height = bitmap.height
        if width < 1 || height < 1 {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' size \(width)x\(height)")
        }

        let xSplit = -xOffset + splitDistance
        let ySplit = -yOffset

        // Tight horizontal crop bounds in 1x pixel coordinates (integer-aligned so 2x buffer scales exact).
        let proxMinX = 0
        let proxMaxX = min(width, max(1, Int(ceil(xSplit + radius))))

        let distMinX = max(0, min(width - 1, Int(floor(xSplit - radius))))
        let distMaxX = width

        let proxImage = try renderHalf(
            source: bitmap,
            cropMinX: proxMinX,
            cropMaxX: proxMaxX,
            height: height,
            xSplit: xSplit,
            ySplit: ySplit,
            radius: radius,
            isProximal: true,
            name: name
        )
        let distImage = try renderHalf(
            source: bitmap,
            cropMinX: distMinX,
            cropMaxX: distMaxX,
            height: height,
            xSplit: xSplit,
            ySplit: ySplit,
            radius: radius,
            isProximal: false,
            name: name
        )

        var proxBuffer: Data?
        var distBuffer: Data?
        let sample = BonePaperDocument.sample
        if let data = paintBuffer,
           let bufferImage = UnitAssets.pngImage(from: data),
           bufferImage.width == width * sample,
           bufferImage.height == height * sample {
            let s = CGFloat(sample)
            if let proxBufImg = try? renderHalf(
                source: bufferImage,
                cropMinX: proxMinX * sample,
                cropMaxX: proxMaxX * sample,
                height: height * sample,
                xSplit: xSplit * s,
                ySplit: ySplit * s,
                radius: radius * s,
                isProximal: true,
                name: name
            ), proxBufImg.width == proxImage.width * sample,
               proxBufImg.height == proxImage.height * sample {
                proxBuffer = try? UnitAssets.pngData(from: proxBufImg, name: name)
            }
            if let distBufImg = try? renderHalf(
                source: bufferImage,
                cropMinX: distMinX * sample,
                cropMaxX: distMaxX * sample,
                height: height * sample,
                xSplit: xSplit * s,
                ySplit: ySplit * s,
                radius: radius * s,
                isProximal: false,
                name: name
            ), distBufImg.width == distImage.width * sample,
               distBufImg.height == distImage.height * sample {
                distBuffer = try? UnitAssets.pngData(from: distBufImg, name: name)
            }
        }

        let proximal = Half(
            image: proxImage,
            paintBuffer: proxBuffer,
            xOffset: xOffset + CGFloat(proxMinX),
            yOffset: yOffset
        )
        let distal = Half(
            image: distImage,
            paintBuffer: distBuffer,
            xOffset: CGFloat(distMinX) - xSplit,
            yOffset: yOffset
        )
        return Pair(proximal: proximal, distal: distal)
    }

    /// Scans the vertical column at `xSplit` for non-transparent pixels (`alpha > 16`)
    /// and returns half the thickness clamped to `[8, min(boneLength / 2, 120)]`.
    static func defaultRadius(
        bitmap: CGImage,
        xOffset: CGFloat,
        yOffset: CGFloat,
        splitDistance: CGFloat,
        boneLength: CGFloat
    ) -> CGFloat {
        let fallback = min(max(boneLength * 0.18, 8), 60)
        let width = bitmap.width
        let height = bitmap.height
        let col = Int(((-xOffset) + splitDistance).rounded())
        guard width >= 1, height >= 1, col >= 0, col < width else {
            return fallback
        }
        var pixel = [UInt8](repeating: 0, count: height * 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }
        context.draw(
            bitmap,
            in: CGRect(x: -CGFloat(col), y: 0, width: CGFloat(width), height: CGFloat(height))
        )
        var firstY: Int?
        var lastY: Int?
        for y in 0..<height {
            let alpha = pixel[y * 4 + 3]
            if alpha > 16 {
                if firstY == nil { firstY = y }
                lastY = y
            }
        }
        guard let first = firstY, let last = lastY, last >= first else {
            return fallback
        }
        let halfSpan = CGFloat(last - first + 1) / 2
        let cap = max(8, min(boneLength / 2, 120))
        return min(max(halfSpan, 8), cap)
    }

    private static func renderHalf(
        source: CGImage,
        cropMinX: Int,
        cropMaxX: Int,
        height: Int,
        xSplit: CGFloat,
        ySplit: CGFloat,
        radius: CGFloat,
        isProximal: Bool,
        name: String
    ) throws -> CGImage {
        let outW = max(1, cropMaxX - cropMinX)
        let outH = max(1, height)
        let fullW = CGFloat(source.width)
        let fullH = CGFloat(source.height)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outW, height: outH),
            format: format
        )
        let drawn = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.translateBy(x: -CGFloat(cropMinX), y: 0)

            let clipPath = CGMutablePath()
            if isProximal {
                if xSplit > 0 {
                    clipPath.addRect(CGRect(x: 0, y: 0, width: xSplit, height: fullH))
                }
            } else {
                if fullW > xSplit {
                    clipPath.addRect(CGRect(x: xSplit, y: 0, width: fullW - xSplit, height: fullH))
                }
            }
            clipPath.addEllipse(
                in: CGRect(
                    x: xSplit - radius,
                    y: ySplit - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            cg.addPath(clipPath)
            cg.clip(using: .winding)

            UIImage(cgImage: source).draw(in: CGRect(x: 0, y: 0, width: fullW, height: fullH))
        }
        guard let cg = drawn.cgImage else {
            throw SceneLoadError(message: "BonePictureSplit '\(name)' produced no bitmap")
        }
        return cg
    }
}
```

- [ ] **Step 2: Check lints on `BonePictureSplit.swift`**

Use `ReadLints` on `/Users/zalivka/wsios/elements/at_elements/Shared/Model/BonePictureSplit.swift` to verify there are no syntax or type errors.

---

### Task 2: Skeleton Topology & Asset Splitting (`StickmanUnit.splitEdge` & `UnitAssets.splitEdgeAssets`)

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/StickmanScene.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/UnitAssets.swift`

**Interfaces:**
- Consumes: `BonePictureSplit.split(...)` from Task 1
- Produces:
  - `StickmanUnit.splitEdge(from: Int, to: Int, t: CGFloat) throws -> Int`
  - `UnitAssets.splitEdgeAssets(from: Int, mid: Int, to: Int, unitName: String, splitDistance: CGFloat, radius: CGFloat) throws`

- [ ] **Step 1: Add `splitEdge(from:to:t:)` to `StickmanUnit` in `Shared/Model/StickmanScene.swift`**

In `/Users/zalivka/wsios/elements/at_elements/Shared/Model/StickmanScene.swift`, right after `addGalleryBonePoint(parentId:length:)` (around line 116), add:

```swift
    /// Splits edge `from → to` at fraction `t` in `(0, 1)`, inserting a new intermediate point `A`
    /// with `parentId = from` and reparenting `to` under `A`. Returns the new point id `A`.
    @discardableResult
    mutating func splitEdge(from: Int, to: Int, t: CGFloat) throws -> Int {
        if t <= 0 || t >= 1 {
            throw SceneLoadError(message: "StickmanUnit '\(name)' splitEdge t \(t) out of (0, 1)")
        }
        let start = try point(id: from)
        guard let endIndex = points.firstIndex(where: { $0.id == to }) else {
            throw SceneLoadError(message: "StickmanUnit '\(name)' missing point \(to)")
        }
        if points[endIndex].parentId != from {
            throw SceneLoadError(message: "StickmanUnit '\(name)' edge \(from)->\(to) is not parent->child")
        }
        let end = points[endIndex]
        let newId = (points.map(\.id).max() ?? 0) + 1
        if points.contains(where: { $0.id == newId }) {
            throw SceneLoadError(message: "StickmanUnit '\(name)' already has point \(newId)")
        }
        let midX = start.x + t * (end.x - start.x)
        let midY = start.y + t * (end.y - start.y)
        let midPoint = StickmanPoint(
            id: newId,
            x: midX,
            y: midY,
            isBase: false,
            parentId: from
        )
        points[endIndex].parentId = newId
        points.append(midPoint)
        try link()
        return newId
    }
```

- [ ] **Step 2: Add `splitEdgeAssets` to `UnitAssets` in `Shared/Model/UnitAssets.swift`**

In `/Users/zalivka/wsios/elements/at_elements/Shared/Model/UnitAssets.swift`, right after `clearEdgeArtwork(start:end:unitName:)` (around line 405), add:

```swift
    /// Splits every state/flip asset on edge `from → to` into proximal (`from → mid`) and distal (`mid → to`)
    /// assets using `BonePictureSplit`, keeps the original default-state asset in `looseBones` if unused
    /// elsewhere, and places distal draw weight directly above proximal (`weight + 1`).
    func splitEdgeAssets(
        from: Int,
        mid: Int,
        to: Int,
        unitName: String,
        splitDistance: CGFloat,
        radius: CGFloat
    ) throws {
        let name = Self.removeNumber(unitName)
        let matchingKeys = edgeAssets.keys.filter { key in
            key.unitName == name
                && ((key.start == from && key.end == to) || (key.start == to && key.end == from))
        }
        if matchingKeys.isEmpty {
            return
        }

        // Collect all (key, states) for this edge before mutating edgeAssets.
        var collected: [(key: EdgeKey, states: [Int: EdgeAsset])] = []
        for key in matchingKeys {
            if let states = edgeAssets.removeValue(forKey: key), !states.isEmpty {
                collected.append((key, states))
            }
        }
        if collected.isEmpty {
            return
        }

        // Keep original default-state asset in looseBones (gallery) if no other edge still references its bmName.
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

        // Base weight of the split bone. Shift all strictly higher weights up by +1 so distal sits at baseWeight + 1.
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

        // Cache split results by (bmName, xOffset, yOffset) so shared bitmaps aren't split twice.
        var splitCache: [String: (proxBm: String, distBm: String, pair: BonePictureSplit.Pair)] = [:]

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
                let cacheKey = "\(asset.bmName)|\(asset.xOffset)|\(asset.yOffset)"
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
                        name: asset.bmName
                    )
                    let proxBm = uniqueBmName(start: from, end: mid)
                    // Reserve proxBm before generating distBm so they never collide.
                    let distBm = uniqueBmName(start: mid, end: to, extraUsed: [proxBm])
                    cached = (proxBm, distBm, pair)
                    splitCache[cacheKey] = cached
                }

                let proxAsset = EdgeAsset(
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
                    paintBuffer: cached.pair.proximal.paintBuffer,
                    svgName: nil,
                    commandScale: nil
                )
                let distAsset = EdgeAsset(
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
                    paintBuffer: cached.pair.distal.paintBuffer,
                    svgName: nil,
                    commandScale: nil
                )
                proxStates[state] = proxAsset
                distStates[state] = distAsset
            }

            edgeAssets[proxKey] = proxStates
            edgeAssets[distKey] = distStates
        }
    }
```

Also update `uniqueBmName(start: Int, end: Int)` in `Shared/Model/UnitAssets.swift` (around line 732) to accept an optional `extraUsed: Set<String> = []`:

```swift
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
```

- [ ] **Step 3: Check lints on `StickmanScene.swift` and `UnitAssets.swift`**

Use `ReadLints` on both files to verify clean compilation types.

---

### Task 3: Split Session State & Tools Panel Button (`SkeletonEditSession` & `SkeletonToolsPanel`)

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonEditSession.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonToolsPanel.swift`

**Interfaces:**
- Produces:
  - `struct BoneSplitDraft: Equatable { static let minEndMargin: CGFloat = 10; static let minRadius: CGFloat = 4; static let maxRadiusCap: CGFloat = 125; var edgeFrom: Int; var edgeTo: Int; var t: CGFloat; var radius: CGFloat }`
  - `SkeletonEditSession.boneSplit: BoneSplitDraft?`
  - `SkeletonEditSession.setBoneSplit(_ draft: BoneSplitDraft?)`
  - `SkeletonSecondaryContent.bones` gains `onSplit: () -> Void` and `canSplit: Bool`

- [ ] **Step 1: Add `BoneSplitDraft` to `Shared/UI/SkeletonEditSession.swift`**

Update `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonEditSession.swift` to define `BoneSplitDraft` and store `boneSplit: BoneSplitDraft?`:

```swift
import CoreGraphics
import Foundation

struct BoneSplitDraft: Equatable {
    /// Minimum distance from either bone endpoint in unscaled item-pixel units.
    static let minEndMargin: CGFloat = 10
    static let minRadius: CGFloat = 4
    static let maxRadiusCap: CGFloat = 125

    var edgeFrom: Int
    var edgeTo: Int
    /// Normalized position along `edgeFrom → edgeTo` in `(0, 1)`.
    var t: CGFloat
    /// Joint circle radius in unscaled item-pixel units.
    var radius: CGFloat

    static func clampT(_ raw: CGFloat, boneLength: CGFloat) -> CGFloat {
        guard boneLength > minEndMargin * 2 else { return 0.5 }
        let marginT = minEndMargin / boneLength
        return min(max(raw, marginT), 1 - marginT)
    }

    static func clampRadius(_ raw: CGFloat, boneLength: CGFloat) -> CGFloat {
        let maxR = max(minRadius, min(boneLength * 0.9, maxRadiusCap))
        return min(max(raw, minRadius), maxR)
    }
}

/// Shared mutable editor session so canvas touch callbacks always see live hold/selection state.
final class SkeletonEditSession {
    let undo = SkeletonUndo()
    var boneCreateHoldMode = false
    var shiftHoldMode = false
    var boneSplit: BoneSplitDraft?
    var selectedPointId: Int?
    /// When true, canvas draws green vacant-point circles (Android `toggleVacantPoints`).
    var exposeVacantPoints = false
    /// Bumped to force SwiftUI refresh when selection or hold mode changes outside @State.
    var revision = 0
    /// Canvas zoom and pan as last drawn, so BonePaper can open with the bone where it was on screen.
    var layout: SkeletonLayout?
    /// Canvas top-left in window coordinates.
    var canvasOrigin: CGPoint = .zero

    func setHoldMode(_ on: Bool) {
        boneCreateHoldMode = on
        revision += 1
    }

    func setShiftHold(_ on: Bool) {
        shiftHoldMode = on
        revision += 1
    }

    func setBoneSplit(_ draft: BoneSplitDraft?) {
        boneSplit = draft
        revision += 1
    }

    func select(_ id: Int?) {
        selectedPointId = id
        revision += 1
    }

    func setExposeVacantPoints(_ on: Bool) {
        exposeVacantPoints = on
        revision += 1
    }
}
```

- [ ] **Step 2: Add `Split` button to `SkeletonBonesTools` in `Shared/UI/SkeletonToolsPanel.swift`**

In `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonToolsPanel.swift`, update `SkeletonSecondaryPanel`, `SkeletonSecondaryContent`, and `SkeletonBonesTools` to include `onSplit: () -> Void` and `canSplit: Bool`:

```swift
                case .bones(let onBoneHoldStart, let onBoneHoldEnd, let onProps, let canProps, let onSplit, let canSplit, let onDelete, let onMoveDown, let onMoveUp):
                    SkeletonBonesTools(
                        onBoneHoldStart: onBoneHoldStart,
                        onBoneHoldEnd: onBoneHoldEnd,
                        onProps: onProps,
                        canProps: canProps,
                        onSplit: onSplit,
                        canSplit: canSplit,
                        onDelete: onDelete,
                        onMoveDown: onMoveDown,
                        onMoveUp: onMoveUp
                    )
```

In `SkeletonSecondaryContent`:

```swift
    case bones(
        onBoneHoldStart: () -> Void,
        onBoneHoldEnd: () -> Void,
        onProps: () -> Void,
        canProps: Bool,
        onSplit: () -> Void,
        canSplit: Bool,
        onDelete: () -> Void,
        onMoveDown: () -> Void,
        onMoveUp: () -> Void
    )
```

In `SkeletonBonesTools`, add `var onSplit: () -> Void` and `var canSplit: Bool`, and place a `splitButton` right below `toolButton(title: "Props", ...)`:

```swift
struct SkeletonBonesTools: View {
    var onBoneHoldStart: () -> Void
    var onBoneHoldEnd: () -> Void
    var onProps: () -> Void
    var canProps: Bool
    var onSplit: () -> Void
    var canSplit: Bool
    var onDelete: () -> Void
    var onMoveDown: () -> Void
    var onMoveUp: () -> Void
    @State private var newPressed = false

    var body: some View {
        VStack(spacing: 0) {
            boneNewButton
            toolButton(title: "Props", icon: "skel_edit_point_active", enabled: canProps, action: onProps)
            splitButton
            toolButton(title: "Delete", icon: "skel_btn_del_active", action: onDelete)
            toolButton(title: "Down", icon: "bone_down_active", action: onMoveDown)
            toolButton(title: "Up", icon: "bone_up_active", action: onMoveUp)
        }
        .padding(.top, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitButton: some View {
        Button(action: onSplit) {
            VStack(spacing: 2) {
                Image(systemName: "scissors")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SkeletonChrome.bonesAccent)
                    .frame(width: 36, height: 36)
                Text("Split")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(canSplit ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSplit)
        .accessibilityLabel("Split bone")
    }
```

- [ ] **Step 3: Check lints on `SkeletonEditSession.swift` and `SkeletonToolsPanel.swift`**

Use `ReadLints` on both files.

---

### Task 4: Canvas Split Gizmo Rendering & Gesture Handling (`SkeletonCanvas`)

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`

**Interfaces:**
- Consumes: `BoneSplitDraft`, `editSession?.boneSplit` from Task 3
- Produces:
  - `var boneSplit: Binding<BoneSplitDraft?> = .constant(nil)` on `SkeletonCanvas`
  - `drawBoneSplitGizmo(context: inout GraphicsContext, layout: SkeletonLayout)`
  - Center handle drag (slides `t` along bone), rim handle drag (adjusts `radius`), pinch-to-scale `radius`, and tap-outside-to-select-another-point (cancels `boneSplit`).

- [ ] **Step 1: Add `boneSplit` binding and gizmo drawing to `Shared/UI/SkeletonCanvas.swift`**

In `SkeletonCanvas`:
1. Add property near `selectedPointId`:
```swift
    var boneSplit: Binding<BoneSplitDraft?> = .constant(nil)
```
2. In `DragRef`, add:
```swift
    private enum SplitDragKind {
        case center
        case rim
    }
```
and inside `DragRef`:
```swift
        var splitKind: SplitDragKind?
```
3. In `Canvas` `.skeleton` switch branch (around line 285), draw the gizmo right after `drawBoneCreatePreview`:
```swift
                    drawBoneCreatePreview(context: &context, layout: layout)
                    drawBoneSplitGizmo(context: &context, layout: layout)
```
4. Implement `drawBoneSplitGizmo(context: inout GraphicsContext, layout: SkeletonLayout)`:
```swift
    private func drawBoneSplitGizmo(context: inout GraphicsContext, layout: SkeletonLayout) {
        guard let draft = boneSplit.wrappedValue ?? editSession?.boneSplit else { return }
        guard let geom = splitScreenGeometry(draft: draft, layout: layout) else { return }

        let accent = SkeletonChrome.bonesAccent
        let circleRect = Self.square(around: geom.centerScreen, radius: geom.radiusScreen)

        // Translucent joint disc
        context.fill(
            Path(ellipseIn: circleRect),
            with: .color(accent.opacity(0.22))
        )

        // Perpendicular dashed cut line across diameter
        var cutLine = Path()
        cutLine.move(
            to: CGPoint(
                x: geom.centerScreen.x - geom.normal.x * geom.radiusScreen,
                y: geom.centerScreen.y - geom.normal.y * geom.radiusScreen
            )
        )
        cutLine.addLine(
            to: CGPoint(
                x: geom.centerScreen.x + geom.normal.x * geom.radiusScreen,
                y: geom.centerScreen.y + geom.normal.y * geom.radiusScreen
            )
        )
        context.stroke(
            cutLine,
            with: .color(accent.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
        )

        // Joint circle outline
        context.stroke(
            Path(ellipseIn: circleRect),
            with: .color(accent),
            style: StrokeStyle(lineWidth: 2)
        )

        // Center handle & Rim handle
        let handleRadius: CGFloat = 7
        for pt in [geom.centerScreen, geom.rimScreen] {
            let rect = Self.square(around: pt, radius: handleRadius)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(accent),
                style: StrokeStyle(lineWidth: 2.5)
            )
        }
    }

    private struct SplitScreenGeometry {
        var startScene: CGPoint
        var endScene: CGPoint
        var boneLengthItem: CGFloat
        var centerScene: CGPoint
        var centerScreen: CGPoint
        var rimScreen: CGPoint
        var radiusScreen: CGFloat
        var normal: CGPoint
    }

    private func splitScreenGeometry(draft: BoneSplitDraft, layout: SkeletonLayout) -> SplitScreenGeometry? {
        guard let from = liveUnit.point(optionalId: draft.edgeFrom),
              let to = liveUnit.point(optionalId: draft.edgeTo)
        else { return nil }
        let unitScale = max(liveUnit.scale, 0.01)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let sceneLen = hypot(dx, dy)
        guard sceneLen > 1e-4 else { return nil }
        let boneLengthItem = sceneLen / unitScale
        let ux = dx / sceneLen
        let uy = dy / sceneLen
        let nx = -uy
        let ny = ux

        let cx = from.x + draft.t * dx
        let cy = from.y + draft.t * dy
        let centerScene = CGPoint(x: cx, y: cy)
        let centerScreen = layout.screenPoint(x: cx, y: cy)
        let radiusScreen = draft.radius * unitScale * layout.scale
        let rimScreen = CGPoint(
            x: centerScreen.x + nx * radiusScreen,
            y: centerScreen.y + ny * radiusScreen
        )
        return SplitScreenGeometry(
            startScene: CGPoint(x: from.x, y: from.y),
            endScene: CGPoint(x: to.x, y: to.y),
            boneLengthItem: boneLengthItem,
            centerScene: centerScene,
            centerScreen: centerScreen,
            rimScreen: rimScreen,
            radiusScreen: radiusScreen,
            normal: CGPoint(x: nx, y: ny)
        )
    }
```

- [ ] **Step 2: Route touch and pinch gestures for the Split gizmo in `Shared/UI/SkeletonCanvas.swift`**

1. In `SkeletonTouchOverlay` inside `SkeletonCanvas.body`:
Update `onPinch` (around line 324) so pinching while `boneSplit` is active scales the joint circle radius if the user is not panning with two fingers, or scales `boneSplit.radius` directly:
```swift
                        onPinch: { focus, factor in
                            if shiftHoldFlag {
                                if FeatureFlags.shiftPinchScale {
                                    boneShift.pinch(factor)
                                }
                                return
                            }
                            if mode == .skeleton, var draft = boneSplit.wrappedValue ?? editSession?.boneSplit,
                               let current = layout,
                               let geom = splitScreenGeometry(draft: draft, layout: current) {
                                draft.radius = BoneSplitDraft.clampRadius(
                                    draft.radius * factor,
                                    boneLength: geom.boneLengthItem
                                )
                                boneSplit.wrappedValue = draft
                                editSession?.setBoneSplit(draft)
                                return
                            }
                            handlePinch(focus: focus, factor: factor)
                        },
```
2. In `handleDrag(at:size:began:)` (around line 1043), right after `boneCreateHoldFlag`, intercept touches when `mode == .skeleton` and a split draft is active:
```swift
        if mode == .skeleton, let draft = boneSplit.wrappedValue ?? editSession?.boneSplit {
            if handleBoneSplitDrag(at: location, layout: current, began: began, draft: draft) {
                return
            }
        }
```
And implement `handleBoneSplitDrag`:
```swift
    private func handleBoneSplitDrag(
        at location: CGPoint,
        layout: SkeletonLayout,
        began: Bool,
        draft: BoneSplitDraft
    ) -> Bool {
        guard let geom = splitScreenGeometry(draft: draft, layout: layout) else {
            return false
        }
        if began {
            let distRim = hypot(location.x - geom.rimScreen.x, location.y - geom.rimScreen.y)
            let distCenter = hypot(location.x - geom.centerScreen.x, location.y - geom.centerScreen.y)
            // Rim handle takes priority when both overlap at small radii; also accept touches near the circle perimeter.
            let distRing = abs(hypot(location.x - geom.centerScreen.x, location.y - geom.centerScreen.y) - geom.radiusScreen)
            if distRim <= Self.hitRadius {
                dragRef.splitKind = .rim
                dragRef.lastScreen = location
                return true
            }
            if distCenter <= Self.hitRadius {
                dragRef.splitKind = .center
                dragRef.lastScreen = location
                return true
            }
            if distRing <= 18 {
                dragRef.splitKind = .rim
                dragRef.lastScreen = location
                return true
            }
            // If user tapped another skeleton node outside the gizmo, exit split mode and let normal node selection run.
            if hitNode(at: location, layout: layout) != nil {
                dragRef.splitKind = nil
                boneSplit.wrappedValue = nil
                editSession?.setBoneSplit(nil)
                return false
            }
            // Empty canvas drag pans the canvas while keeping the split gizmo active.
            dragRef.splitKind = nil
            dragRef.panning = allowsSceneMovements
            dragRef.lastScreen = location
            return true
        }

        if let kind = dragRef.splitKind {
            var next = draft
            let graph = layout.graphPoint(screen: location)
            let unitScale = max(liveUnit.scale, 0.01)
            switch kind {
            case .center:
                let dx = geom.endScene.x - geom.startScene.x
                let dy = geom.endScene.y - geom.startScene.y
                let lenSq = dx * dx + dy * dy
                if lenSq > 1e-6 {
                    let rawT = ((graph.x - geom.startScene.x) * dx + (graph.y - geom.startScene.y) * dy) / lenSq
                    next.t = BoneSplitDraft.clampT(rawT, boneLength: geom.boneLengthItem)
                }
            case .rim:
                let distScene = hypot(graph.x - geom.centerScene.x, graph.y - geom.centerScene.y)
                next.radius = BoneSplitDraft.clampRadius(distScene / unitScale, boneLength: geom.boneLengthItem)
            }
            boneSplit.wrappedValue = next
            editSession?.setBoneSplit(next)
            dragRef.lastScreen = location
            return true
        }

        if dragRef.panning, let last = dragRef.lastScreen {
            let nextLayout = layout.panned(dx: location.x - last.x, dy: location.y - last.y)
            self.layout = nextLayout
            editSession?.layout = nextLayout
            dragRef.lastScreen = location
        }
        return true
    }
```
3. In `endTouch()`, reset `dragRef.splitKind = nil`.

- [ ] **Step 3: Check lints on `SkeletonCanvas.swift`**

Use `ReadLints` on `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`.

---

### Task 5: Wire Split Tool & Floating Confirmation Bar in `SkeletonScreen`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift`

**Interfaces:**
- Consumes:
  - `BonePictureSplit.defaultRadius(...)` from Task 1
  - `StickmanUnit.splitEdge(...)` and `UnitAssets.splitEdgeAssets(...)` from Task 2
  - `BoneSplitDraft`, `SkeletonEditSession.setBoneSplit(...)`, `SkeletonBonesTools` `onSplit`/`canSplit` from Task 3
  - `SkeletonCanvas(boneSplit: $boneSplit)` from Task 4

- [ ] **Step 1: Add `@State private var boneSplit: BoneSplitDraft?` and wire `SkeletonCanvas` & `SkeletonBonesTools` in `SkeletonScreen.swift`**

In `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift`:
1. Add `@State private var boneSplit: BoneSplitDraft?` next to `@State private var pointProps: PointPropsEdit?`.
2. Pass `boneSplit: $boneSplit` to `SkeletonCanvas(...)` (around line 60).
3. In `SkeletonLeftPanel` `onSelect` (around line 73), clear `setBoneSplit(nil)` when switching panels:
```swift
                        if next != .bones {
                            setHoldMode(false)
                            setBoneSplit(nil)
                        }
```
4. In `SkeletonSecondaryPanel` `.bones(...)` (around line 93), pass `onSplit: startBoneSplit` and `canSplit: canSplitBone`:
```swift
                        content: .bones(
                            onBoneHoldStart: {
                                setBoneSplit(nil)
                                setHoldMode(true)
                            },
                            onBoneHoldEnd: { setHoldMode(false) },
                            onProps: {
                                setBoneSplit(nil)
                                openPointProps()
                            },
                            canProps: selectedPointId != nil,
                            onSplit: startBoneSplit,
                            canSplit: canSplitBone,
                            onDelete: {
                                setBoneSplit(nil)
                                deleteSelected()
                            },
                            onMoveDown: { moveSelected(up: false) },
                            onMoveUp: { moveSelected(up: true) }
                        )
```
5. Add floating confirmation pill overlay at the bottom of `SkeletonScreen` (and banner text in `holdBannerText`):
```swift
        .overlay(alignment: .bottom) {
            if boneSplit != nil {
                boneSplitConfirmBar
                    .padding(.bottom, 24)
            }
        }
```
where `boneSplitConfirmBar` is:
```swift
    private var boneSplitConfirmBar: some View {
        HStack(spacing: 12) {
            Button {
                setBoneSplit(nil)
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SkeletonChrome.pane))
            }
            .buttonStyle(.plain)

            Button {
                applyBoneSplit()
            } label: {
                Text("Split Bone")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SkeletonChrome.bonesAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.65)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
```
6. Update `holdBannerText`:
```swift
    private var holdBannerText: String? {
        if boneCreateHoldMode {
            return "Hold the button and drag from a point to add a bone"
        }
        if shiftHoldMode {
            return "Hold the button and drag the bone picture"
        }
        if boneSplit != nil {
            return "Drag center to slide, drag rim handle to resize joint"
        }
        return nil
    }
```

- [ ] **Step 2: Implement `canSplitBone`, `startBoneSplit()`, and `applyBoneSplit()` in `SkeletonScreen.swift`**

Add the methods to `SkeletonScreen`:
```swift
    private var canSplitBone: Bool {
        guard let unit = optionalUnit, let id = selectedPointId else { return false }
        guard let edge = unit.upperEdge(of: id),
              let start = unit.point(optionalId: edge.from),
              let end = unit.point(optionalId: edge.to)
        else { return false }
        let unitScale = max(unit.scale, 0.01)
        let length = hypot(end.x - start.x, end.y - start.y) / unitScale
        return length >= BoneSplitDraft.minEndMargin * 2
    }

    private func setBoneSplit(_ draft: BoneSplitDraft?) {
        editSession.setBoneSplit(draft)
        boneSplit = draft
    }

    private func startBoneSplit() {
        guard let unit = optionalUnit, let assets, let id = selectedPointId else { return }
        guard let edge = unit.upperEdge(of: id),
              let start = unit.point(optionalId: edge.from),
              let end = unit.point(optionalId: edge.to)
        else { return }
        let unitScale = max(unit.scale, 0.01)
        let length = hypot(end.x - start.x, end.y - start.y) / unitScale
        guard length >= BoneSplitDraft.minEndMargin * 2 else {
            showToast("Bone is too short to split")
            return
        }
        let t = BoneSplitDraft.clampT(0.5, boneLength: length)
        let splitDist = t * length
        let key = UnitAssets.EdgeKey(
            unitName: UnitAssets.removeNumber(unit.name),
            start: edge.from,
            end: edge.to,
            flipped: false
        )
        let radius: CGFloat
        if let asset = assets.getDrawable(key, state: unit.assetsState) {
            radius = BoneSplitDraft.clampRadius(
                BonePictureSplit.defaultRadius(
                    bitmap: asset.bitmap,
                    xOffset: asset.xOffset,
                    yOffset: asset.yOffset,
                    splitDistance: splitDist,
                    boneLength: length
                ),
                boneLength: length
            )
        } else {
            radius = BoneSplitDraft.clampRadius(min(max(length * 0.18, 8), 60), boneLength: length)
        }
        setBoneSplit(
            BoneSplitDraft(
                edgeFrom: edge.from,
                edgeTo: edge.to,
                t: t,
                radius: radius
            )
        )
    }

    private func applyBoneSplit() {
        guard var unit = optionalUnit, let assets, let draft = boneSplit else { return }
        guard let start = unit.point(optionalId: draft.edgeFrom),
              let end = unit.point(optionalId: draft.edgeTo)
        else {
            setBoneSplit(nil)
            return
        }
        let unitScale = max(unit.scale, 0.01)
        let length = hypot(end.x - start.x, end.y - start.y) / unitScale
        let splitDistance = draft.t * length

        prepareUndo(includeAssets: true)
        do {
            let midId = try unit.splitEdge(from: draft.edgeFrom, to: draft.edgeTo, t: draft.t)
            try assets.splitEdgeAssets(
                from: draft.edgeFrom,
                mid: midId,
                to: draft.edgeTo,
                unitName: unit.name,
                splitDistance: splitDistance,
                radius: draft.radius
            )
            setBoneSplit(nil)
            writeUnit(unit)
            selectedPointId = midId
            editSession.select(midId)
            layerEpoch += 1
        } catch {
            setBoneSplit(nil)
            showToast("Could not split bone: \(ItemLoadError.text(error))")
        }
    }
```
Also clear `setBoneSplit(nil)` inside `performUndo()`, `performRedo()`, `openBonePaper()`, and `toggleMenu()`.

- [ ] **Step 3: Check lints on `SkeletonScreen.swift`**

Use `ReadLints` on `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift`.
