# Stretchable Bones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `stretchable="true"` bones behave on iOS the way they do on Android: a bottom-left hold button in the scene editor and skeleton preview, translate-instead-of-rotate dragging while held, bone pictures stretched along the bone, double-tap to restore rest length, and the authoring checkbox in the skeleton editor.

**Architecture:** `StickmanUnit` gains the Android `PointManipulator.stretchMove` / `restoreRestLength` primitives plus the kinematic-chain queries from `EditUnit`. A new `BoneStretch` helper derives the Android `BonePictureStretch` ratio from `model.xml` rest lengths, and the three draw stacks (`SkeletonCanvas`, `FrameRasterizer`, `SkeletonOnion`) insert one `scaleBy(x: ratio, y: 1)` after the bone rotation. `SkeletonCanvas` takes a `stretchHold` binding and routes the drag to the stretch primitive. `StretchHoldButton` (bottom-left, `skel_edit_shift.png`, `HoldTouchPad`) is wired into `SceneEditorScreen` and `SkeletonPreviewScreen`. `EditPointDialog` gets the "Stretchable bone" card and `SkeletonScreen` clears covered flags on save.

**Tech Stack:** Swift, SwiftUI, CoreGraphics, UIKit (`UILongPressGestureRecognizer`).

## Global Constraints

- Do NOT build iOS or Android (`xcodebuild`, `./gradlew`) unless the user explicitly orders it directly.
- Do NOT write automated tests unless the user explicitly asks for them.
- Prefer loud failures (`throw SceneLoadError`, `assertionFailure`) over silent fake defaults.
- Every behaviour below must match the Android reference named in the step; when in doubt, re-read that Android file before deviating.
- Rest lengths are captured from `model.xml` in **unscaled item pixels** (`UnitAssets.captureRest`), so world rest is `rest * unit.scale` and the ratio is `edgeLength / (rest * unit.scale)` — the exact formula in `BonePictureStretch.apply`.

---

### Task 1: Model primitives in `StickmanUnit`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/StickmanScene.swift`

**Interfaces:**
- Consumes: nothing (pure model).
- Produces:
  - `mutating func stretchMove(id: Int, destX: CGFloat, destY: CGFloat) throws`
  - `mutating func restoreRestLength(id: Int, rest: CGFloat) throws`
  - `func kinematicChainPointIds() -> Set<Int>`
  - `mutating func clearStretchableOnKinematicChain() -> Bool`
  - `mutating func applyPointProps(id: Int, attachable: Attachable, fixed: Bool, stretchable: Bool?) throws`

- [ ] **Step 1: Add the stretch move and rest-length restore next to `movePointAndDescendants`**

`movePointAndDescendants` (line ~321) is Android `PointManipulator.stretchMove` minus the slave bookkeeping, which `SceneEditorScreen` already does through `followAttachedSlaves`. Add the rest-length restore directly beneath it:

```swift
    /// Android `PointManipulator.stretchMove`: place `id` exactly at the destination and
    /// translate its descendants by the same delta. No rotation, no length clamp —
    /// the picture stretches to cover whatever length the user drags.
    mutating func stretchMove(id: Int, destX: CGFloat, destY: CGFloat) throws {
        let grabbed = try point(id: id)
        if grabbed.isBase {
            throw SceneLoadError(message: "StickmanUnit '\(name)' cannot stretch base \(id)")
        }
        let dx = destX - grabbed.x
        let dy = destY - grabbed.y
        for moveId in [id] + (try descendants(of: id)) {
            guard let index = points.firstIndex(where: { $0.id == moveId }) else {
                throw SceneLoadError(message: "StickmanUnit '\(name)' missing point \(moveId)")
            }
            points[index].x += dx
            points[index].y += dy
        }
    }

    /// Android `PointManipulator.restoreRestLength`: puts `id` back on the same ray from its
    /// parent at `rest * scale`. `rest` is the unscaled model length from `model.xml`.
    mutating func restoreRestLength(id: Int, rest: CGFloat) throws {
        let target = try point(id: id)
        if target.isBase {
            throw SceneLoadError(message: "StickmanUnit '\(name)' cannot restore base \(id)")
        }
        guard let parentId = target.parentId else {
            throw SceneLoadError(message: "StickmanUnit '\(name)' point \(id) has no parent")
        }
        if rest <= 0 || scale <= 0 {
            throw SceneLoadError(
                message: "StickmanUnit '\(name)' point \(id) rest \(rest) scale \(scale)"
            )
        }
        let parent = try point(id: parentId)
        let dx = target.x - parent.x
        let dy = target.y - parent.y
        let current = hypot(dx, dy)
        if current <= 0 {
            throw SceneLoadError(message: "StickmanUnit '\(name)' point \(id) sits on its parent")
        }
        let factor = (rest * scale) / current
        try stretchMove(id: id, destX: parent.x + dx * factor, destY: parent.y + dy * factor)
    }
```

- [ ] **Step 2: Add the kinematic-chain queries beside `descendants()`**

Android `EditUnit.collectKinematicChainPoints`: walk up from every nonzero `kinematicStart` point, adding each point, stopping at the base, a `kinematicStop` parent, or a `fixed` parent.

```swift
    /// Android `EditUnit.collectKinematicChainPoints`: every point covered by a
    /// Start → Stop/Base/fixed segment, inclusive of both ends.
    func kinematicChainPointIds() -> Set<Int> {
        var chain: Set<Int> = []
        let byId = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        for start in points where start.kinematicStart && !start.isBase {
            var current: StickmanPoint? = start
            while let point = current, !point.isBase {
                chain.insert(point.id)
                guard let parentId = point.parentId, let parent = byId[parentId] else {
                    break
                }
                chain.insert(parent.id)
                if parent.isBase || parent.kinematicStop || parent.fixed {
                    break
                }
                current = parent
            }
        }
        return chain
    }

    /// Android `EditUnit.clearStretchableCoveredByKinematics`. IK wins over stretch, so a
    /// point on a kinematic chain must not carry the flag into a saved item.
    /// - Returns: true when any flag was cleared.
    mutating func clearStretchableOnKinematicChain() -> Bool {
        let chain = kinematicChainPointIds()
        var cleared = false
        for index in points.indices where chain.contains(points[index].id) && points[index].stretchable {
            points[index].stretchable = false
            cleared = true
        }
        return cleared
    }
```

- [ ] **Step 3: Extend `applyPointProps` with the nullable stretch flag**

Android keeps the stored value when the checkbox is disabled; `nil` expresses exactly that, without a fake default.

```swift
    /// Android `EditPointDialog` Apply: attachable + invisible (`fixed`) + stretchable.
    /// Slave is base-only. `stretchable == nil` keeps the stored flag (Android keeps it
    /// while the checkbox is disabled by kinematics).
    mutating func applyPointProps(
        id: Int,
        attachable: Attachable,
        fixed: Bool,
        stretchable: Bool?
    ) throws {
        guard let index = points.firstIndex(where: { $0.id == id }) else {
            throw SceneLoadError(message: "StickmanUnit '\(name)' missing point \(id)")
        }
        let isBase = points[index].isBase
        if attachable == .slave && !isBase {
            throw SceneLoadError(message: "StickmanUnit '\(name)' slave only on base, got point \(id)")
        }
        points[index].fixed = isBase ? false : fixed
        points[index].attachable = attachable
        if let stretchable {
            points[index].stretchable = !isBase && stretchable
        }
    }
```

- [ ] **Step 4: Check the two call sites still resolve**

Run: `grep -rn "applyPointProps" /Users/zalivka/wsios/elements/at_elements --include=*.swift`
Expected: one definition (this step) and one call in `SkeletonScreen.swift:812`. That call is updated in Task 9; until then the file does not compile, which is expected — Task 9 closes it.

---

### Task 2: `BoneStretch` ratio helper

**Files:**
- Create: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/BoneStretch.swift`

**Interfaces:**
- Consumes: `StickmanUnit`, `StickmanEdge`, `UnitAssets.restLength(unitName:endId:)`.
- Produces:
  - `enum BoneStretch`
  - `static func ratio(unit: StickmanUnit, edge: StickmanEdge, assets: UnitAssets) -> CGFloat?`
  - `static func hasStretchablePoint(_ unit: StickmanUnit) -> Bool`

- [ ] **Step 1: Create the file**

`ratio` returns `nil` for every "draw as authored" case instead of `1`, so callers cannot confuse "not stretchable" with "stretched to identity". `hasStretchablePoint` is the Android `hasSelectedUnitWithStretchableBone` predicate (stretchable and not a kinematic start).

```swift
import CoreGraphics

/// Android `BonePictureStretch`: the horizontal factor a bone picture must be drawn at so it
/// still covers its bone after the bone is stretched away from its model rest length.
enum BoneStretch {
    /// Android `MainEditor.hasSelectedUnitWithStretchableBone` / `ItemPreview`:
    /// a kinematic start drives the bone through IK, so its own stretch flag is ignored.
    static func hasStretchablePoint(_ unit: StickmanUnit) -> Bool {
        unit.points.contains { $0.stretchable && !$0.kinematicStart }
    }

    /// Nil when the edge must be drawn as authored: the tip is not stretchable, the tip is a
    /// kinematic start, `model.xml` rest length is unknown, the unit has no scale, or the bone
    /// sits exactly at rest length.
    static func ratio(unit: StickmanUnit, edge: StickmanEdge, assets: UnitAssets) -> CGFloat? {
        guard let tip = unit.point(optionalId: edge.to),
              let from = unit.point(optionalId: edge.from)
        else {
            return nil
        }
        if tip.isBase || !tip.stretchable || tip.kinematicStart {
            return nil
        }
        if unit.scale <= 0 {
            assertionFailure("BoneStretch '\(unit.name)' scale is \(unit.scale)")
            return nil
        }
        let rest = assets.restLength(unitName: unit.name, endId: edge.to)
        if rest <= 0 {
            return nil
        }
        let restWorld = rest * unit.scale
        let length = hypot(tip.x - from.x, tip.y - from.y)
        if length <= 0 || restWorld <= 0 {
            return nil
        }
        let ratio = length / restWorld
        if !ratio.isFinite || ratio <= 0 {
            return nil
        }
        if abs(ratio - 1) < 0.0005 {
            return nil
        }
        return ratio
    }
}
```

- [ ] **Step 2: Confirm the file is picked up by the target**

Run: `grep -c "BoneStretch.swift" /Users/zalivka/wsios/elements/at_elements/at_elements.xcodeproj/project.pbxproj`
Expected: `0` — the project uses folder-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so a file dropped into `Shared/Model/` joins the target without a project edit. Confirm the project is folder-synchronized with:

Run: `grep -c "PBXFileSystemSynchronizedRootGroup" /Users/zalivka/wsios/elements/at_elements/at_elements.xcodeproj/project.pbxproj`
Expected: a non-zero count. If it is `0`, add the file to the target manually before continuing.

---

### Task 3: Stretch the artwork in `SkeletonCanvas`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift` (`drawBitmaps`, line ~875-940)

**Interfaces:**
- Consumes: `BoneStretch.ratio(unit:edge:assets:)` from Task 2.
- Produces: nothing consumed later; visual only.

- [ ] **Step 1: Carry the edge into the `Bone` struct**

The ratio needs the edge, which the local `Bone` struct currently drops.

```swift
        struct Bone {
            var weight: Int
            var start: CGPoint
            var end: CGPoint
            var edge: StickmanEdge
            var asset: UnitAssets.EdgeAsset
        }
```

and in the append:

```swift
            bones.append(
                Bone(
                    weight: asset.weight,
                    start: CGPoint(x: from.x, y: from.y),
                    end: CGPoint(x: to.x, y: to.y),
                    edge: edge,
                    asset: asset
                )
            )
```

- [ ] **Step 2: Insert the bone-axis scale right after the rotation**

Android order is `setScale → postTranslate(offset) → postRotate(angle about start) → stretch(rotate/scale/rotate about start)`. In this `drawLayer` stack `translate(start) · rotate(angle)` is already the rotation about the joint, so scaling X there by the ratio is the same operation, and the offset translate below it is stretched with the picture exactly like `BonePictureStretch` does.

```swift
            let angle = atan2(bone.end.y - bone.start.y, bone.end.x - bone.start.x)
            // Android `BonePictureStretch.apply` — stretch along the bone so the picture
            // still covers it. Nil draws the picture as authored.
            let stretchRatio = BoneStretch.ratio(unit: drawn, edge: bone.edge, assets: assets)
            let mirror = drawn.flipped && !bone.asset.nativeFlipped
```

and inside the layer, after `ctx.rotate(by: Angle(radians: angle))`:

```swift
                if let stretchRatio {
                    ctx.scaleBy(x: stretchRatio, y: 1)
                }
```

- [ ] **Step 3: Verify the guard order by reading the finished function**

Run: `sed -n '870,950p' /Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`
Expected: `let stretchRatio` computed before `drawLayer`, and `ctx.scaleBy(x: stretchRatio, y: 1)` between `ctx.rotate(by:)` and `ctx.translateBy(x: (bone.asset.xOffset + live.dx)...)`. If the scale lands after the offset translate, the picture will not stretch its offsets — move it up.

---

### Task 4: Stretch the artwork in the export rasterizer and the BonePaper onion

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Loaders/FrameRasterizer.swift` (`drawBitmaps`, line ~169-211)
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/SkeletonOnion.swift` (`worldOverlay`, line ~27-100)

**Interfaces:**
- Consumes: `BoneStretch.ratio`.
- Produces: nothing consumed later. Video frames, thumbnails, and the BonePaper onion now show stretched bones instead of rest-length artwork.

- [ ] **Step 1: `FrameRasterizer` — add the edge and the scale**

Add `var edge: StickmanEdge` to the local `Bone` struct and fill it in the append (same shape as Task 3 Step 1), then:

```swift
            let ratio = BoneStretch.ratio(unit: drawn, edge: bone.edge, assets: assets)
```

and in the context stack, after `context.rotate(by: angle)`:

```swift
            if let ratio {
                context.scaleBy(x: ratio, y: 1)
            }
```

- [ ] **Step 2: `SkeletonOnion` — add the edge and the scale**

`SkeletonOnion` works in unscaled item coordinates (`point.x / unit.scale`) to match the BonePaper page. The ratio is scale-invariant (`length / (rest * scale)` divides out), so the same helper applies.

Add `var edge: StickmanEdge` to the local `Bone` struct and fill it in the append, then before the draw loop:

```swift
        let stretchRatios = bones.map { BoneStretch.ratio(unit: unit, edge: $0.edge, assets: assets) }
```

and inside the loop, after `cg.rotate(by: bone.angle)`:

```swift
                if let ratio = stretchRatios[index] {
                    cg.scaleBy(x: ratio, y: 1)
                }
```

The loop must become `for (index, bone) in bones.enumerated()`.

- [ ] **Step 3: Read both finished functions**

Run: `sed -n '169,215p' /Users/zalivka/wsios/elements/at_elements/Shared/Loaders/FrameRasterizer.swift; sed -n '80,105p' /Users/zalivka/wsios/elements/at_elements/Shared/Model/SkeletonOnion.swift`
Expected: in both, `scaleBy(x: ratio, y: 1)` sits after the bone rotation and before the offset translate / image scale.

---

### Task 5: Stretch drag and rest-length double tap in `SkeletonCanvas`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`

**Interfaces:**
- Consumes: `StickmanUnit.stretchMove`, `StickmanUnit.restoreRestLength`, `BoneStretch.hasStretchablePoint`, `UnitAssets.restLength`.
- Produces:
  - `var stretchHold: Binding<Bool> = .constant(false)` (new input)
  - `var onMessage: ((String) -> Void)? = nil` (new input, for the missing-rest-length case)

- [ ] **Step 1: Add the new inputs next to the other bindings**

Insert beside `boneSplit` (line ~189):

```swift
    /// Android `TempState.sShift` for this canvas — the hold button is down.
    var stretchHold: Binding<Bool> = .constant(false)
    /// Short user-facing message the owning screen toasts (Android `UIUtils.niceToast`).
    var onMessage: ((String) -> Void)? = nil
```

and the accessor beside `shiftHoldFlag` (line ~425):

```swift
    private var stretchHoldFlag: Bool {
        stretchHold.wrappedValue
    }
```

- [ ] **Step 2: Track the captured drag as stretching**

Add to `DragRef` (line ~243-257):

```swift
        /// Android `TempState.sShift && point.mStretchable` at touch-down.
        var stretching = false
```

Reset it everywhere the other drag fields are reset — in `endTouch()` beside `dragRef.panning = false`:

```swift
        dragRef.stretching = false
```

- [ ] **Step 3: Decide at touch-down whether this drag stretches**

In `handleDrag`, the block that resolves the captured node ends at line 1284 with
`dragRef.panning = allowsSceneMovements && dragRef.nodeId == nil`. Insert the new lines **immediately before** that statement, so `dragRef.nodeId` is already final:

```swift
                dragRef.stretching = false
                if mode == .editor, stretchHoldFlag, let id = dragRef.nodeId,
                   let point = liveUnit.point(optionalId: id),
                   point.stretchable, !point.isBase, !point.kinematicStart {
                    dragRef.stretching = true
                }
```

Ordering matters: this must run *after* `dragRef.nodeId` is set and *before* the move branch below, so the same touch that captured a point already stretches.

- [ ] **Step 4: Route the move to the stretch primitive**

Replace the skeleton/editor branch of the point-drag block (lines 1355-1363: the `do { if mode == .skeleton { … } else { … } }` inside `if let id = dragRef.nodeId`):

```swift
            do {
                if dragRef.stretching {
                    // Android `PointManipulator.stretchMove` — no rotation about the parent.
                    try liveUnit.stretchMove(id: id, destX: destX, destY: destY)
                } else if mode == .skeleton {
                    try liveUnit.movePointAndDescendants(id: id, destX: destX, destY: destY)
                } else {
                    try liveUnit.drag(id: id, destX: destX, destY: destY)
                }
            } catch {
                onEditError?(error)
                return
            }
```

- [ ] **Step 5: Restore rest length on double tap while held**

Android `TouchPointUseCase.noteOrRestoreStretchTap` → `PointManipulator.restoreRestLength`. At the top of `handleEmptyDoubleTap(at:size:)` (line ~1370), before the deselect branch:

```swift
    private func handleEmptyDoubleTap(at location: CGPoint, size: CGSize) {
        guard mode == .editor else { return }
        let current = resolvedLayout(size: size)
        if stretchHoldFlag, restoreRestLength(at: location, layout: current) {
            return
        }
        if hitAnyUnit(at: location, layout: current) == nil {
            selectedUnitName.wrappedValue = nil
            endTouch()
        }
    }

    /// Android `PointManipulator.restoreRestLength` — the point snaps back onto its parent's ray
    /// at the model rest length. Only stretchable, non-kinematic points qualify.
    private func restoreRestLength(at location: CGPoint, layout: SkeletonLayout) -> Bool {
        guard let hit = hitAnyUnit(at: location, layout: layout, radius: Self.hitRadius, in: [liveUnit]) else {
            return false
        }
        guard let point = hit.unit.point(optionalId: hit.pointId),
              point.stretchable, !point.isBase, !point.kinematicStart
        else {
            return false
        }
        guard let assets else {
            assertionFailure("SkeletonCanvas stretch restore without assets")
            return false
        }
        let rest = assets.restLength(unitName: hit.unit.name, endId: hit.pointId)
        if rest <= 0 {
            // Android `R.string.bone_rest_length_missing`
            onMessage?("This bone has no rest length to restore")
            return true
        }
        onPrepareUndo?()
        do {
            try liveUnit.restoreRestLength(id: hit.pointId, rest: rest)
        } catch {
            onEditError?(error)
            return true
        }
        editSession?.select(hit.pointId)
        selectedPointNameIfNeeded(hit.unit.name)
        onPoseEditEnded?()
        return true
    }
```

If `selectedUnitName` is not yet assigned for this unit, set it so the owning screen retweens the right structure:

```swift
    private func selectedPointNameIfNeeded(_ name: String) {
        if selectedUnitName.wrappedValue != name {
            selectedUnitName.wrappedValue = name
        }
    }
```

- [ ] **Step 6: Draw the blue expose circles while held**

Android `UnitDrawer`: `#4DA3FF` at alpha 170 over stretchable, non-kinematic-start points of the active unit. Add the color beside the other expose colors (line ~150-160):

```swift
    /// Android `UnitDrawer.STRETCHABLE_POINT_COLOR`.
    static let exposeStretchable = Color(red: 0x4D / 255, green: 0xA3 / 255, blue: 0xFF / 255).opacity(170 / 255)
```

and the drawing, called from the `.editor` case next to `drawAttachExpose` (line ~284):

```swift
    private func drawStretchExpose(context: inout GraphicsContext, layout: SkeletonLayout) {
        guard mode == .editor, stretchHoldFlag, let name = selectedUnitName.wrappedValue else { return }
        guard let held = unitsToDraw.first(where: { $0.name == name }) else { return }
        let radius = StickmanUnit.exposeMarkerRadius
        for point in held.points where point.stretchable && !point.kinematicStart && !point.isBase {
            let center = layout.screenPoint(x: point.x, y: point.y)
            context.fill(
                Path(ellipseIn: Self.square(around: center, radius: radius)),
                with: .color(Self.exposeStretchable)
            )
        }
    }
```

- [ ] **Step 7: Sanity-read the finished drag path**

Run: `grep -n "stretchHoldFlag\|dragRef.stretching\|stretchMove\|restoreRestLength" /Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`
Expected, in this order: the `stretchHoldFlag` accessor, the `DrawStretchExpose` guard, the touch-down `dragRef.stretching = true` decision, the move branch, the double-tap restore, and the `endTouch` reset. A missing `endTouch` reset would let a later drag on a non-stretchable point keep stretching — check it explicitly.

---

### Task 6: `StretchHoldButton` chrome

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonToolsPanel.swift` (append after `SkeletonDrawTools`, line ~500)

**Interfaces:**
- Consumes: the file-private `HoldTouchPad` and `chromeImage`, `SkeletonChrome.shiftIdle/shiftPressed/holdBanner`.
- Produces:
  - `struct StretchHoldButton: View { var leading: CGFloat; var isActive: Bool; var onHoldStart: () -> Void; var onHoldEnd: () -> Void }`
  - `struct StretchHoldBanner: View`

- [ ] **Step 1: Add the button**

It must live in this file because `HoldTouchPad` is `private` at file scope. Same zero-duration long press as NEW / Shift Bone, so a second finger on the canvas cannot cancel it.

```swift
/// Android `main_shift` / `item_preview_shift`: hold to keep the next point drag from rotating.
/// Bottom-left, carrying the same leading offset rule as `FullscreenBackButton` so it slides
/// right when a left panel opens.
struct StretchHoldButton: View {
    var leading: CGFloat
    var isActive: Bool
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? SkeletonChrome.shiftPressed : SkeletonChrome.shiftIdle)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(decorative: Self.icon, scale: 3)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
            HoldTouchPad(onBegan: onHoldStart, onEnded: onHoldEnd)
                .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
        .padding(.leading, leading)
        .padding(.bottom, 20)
        .accessibilityLabel("Hold to stretch bones")
    }

    private static let icon: CGImage = chromeImage("skel_edit_shift")
}

/// Android `main_shift_hold_tip`: the same amber banner, bottom-centre so it clears the button.
struct StretchHoldBanner: View {
    var body: some View {
        Text("Keep holding to move a stretchable point")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(SkeletonChrome.holdBanner)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Verify the file still compiles as one unit**

Run: `grep -n "private struct HoldTouchPad\|struct StretchHoldButton\|func chromeImage" /Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonToolsPanel.swift`
Expected: `HoldTouchPad` and `chromeImage` are declared in this same file, above or below `StretchHoldButton`, so both are reachable.

---

### Task 7: Wire the button into the scene editor

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SceneEditorScreen.swift`

**Interfaces:**
- Consumes: `StretchHoldButton`, `StretchHoldBanner`, `SkeletonCanvas.stretchHold`, `SkeletonCanvas.onMessage`, `BoneStretch.hasStretchablePoint`.
- Produces: nothing consumed later.

- [ ] **Step 1: Add the hold state**

Beside `@State private var capturedUnitName: String?` (line ~49):

```swift
    @State private var stretchHold = false
```

- [ ] **Step 2: Pass the binding and the message sink to the canvas**

In the `SkeletonCanvas(...)` call at line ~173, after `capturedUnitName: $capturedUnitName,`:

```swift
                    stretchHold: $stretchHold,
                    onMessage: { showToast($0) },
```

- [ ] **Step 3: Show the button in the bottom-left, moving with the left panel**

Android: `main_shift` is visible only while the active unit has a stretchable point, and is never hidden while held (hiding cancels the touch and clears the flag — see `MainEditor.updateShiftButtonState`). Add an overlay next to the existing `.overlay(alignment: .topLeading)` for `FullscreenBackButton` (line ~379):

```swift
        .overlay(alignment: .bottomLeading) {
            if stretchButtonVisible {
                StretchHoldButton(
                    leading: MainPanel.width + backExtraLeading + 8,
                    isActive: stretchHold,
                    onHoldStart: {
                        stretchHold = true
                        onStretchHoldChanged(true)
                    },
                    onHoldEnd: {
                        stretchHold = false
                        onStretchHoldChanged(false)
                    }
                )
                .offsetLeadingIsland()
                .paddingBottomSafeArea()
            }
        }
```

- [ ] **Step 4: Add the visibility rule and the held banner**

```swift
    /// Android `MainEditor.hasSelectedUnitWithStretchableBone`; forced on while held for the
    /// same reason: hiding the button cancels the touch.
    private var stretchButtonVisible: Bool {
        if stretchHold {
            return true
        }
        guard tutorialStep == nil, let selectedUnit else { return false }
        return BoneStretch.hasStretchablePoint(selectedUnit)
    }

    private func onStretchHoldChanged(_ on: Bool) {
        if !on {
            stretchHold = false
        }
    }
```

Banner, as a second overlay beside the existing `.overlay(alignment: .top)` chips (line ~340):

```swift
        .overlay(alignment: .bottom) {
            if stretchHold {
                StretchHoldBanner()
                    .padding(.bottom, 24)
            }
        }
```

- [ ] **Step 5: Confirm the leading rule matches the Back button**

Run: `grep -n "MainPanel.width + backExtraLeading\|backExtraLeading: CGFloat" /Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SceneEditorScreen.swift`
Expected: the Back button passes `extraLeading: backExtraLeading` to `FullscreenBackButton`, which adds `MainPanel.width + 8`; the new button uses `MainPanel.width + backExtraLeading + 8`. Both must reach the same X for the same panel state — if they differ, the button will not move with Back.

`backExtraLeading` already returns only the *panel* width (`SideMenu.width`, `ItemChooserPanel.width`, …) and `FullscreenBackButton` adds `MainPanel.width` itself, so the sum above reaches the same X as the Back button. Do not add `MainPanel.width` twice.

---

### Task 8: Wire the button into the skeleton item preview

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonPreviewScreen.swift`

**Interfaces:**
- Consumes: `StretchHoldButton`, `BoneStretch.hasStretchablePoint`, `SkeletonCanvas.stretchHold`.
- Produces: nothing consumed later.

- [ ] **Step 1: Add the state**

```swift
    @State private var stretchHold = false
```

- [ ] **Step 2: Pass it to the canvas and add the button**

```swift
            SkeletonCanvas(
                unit: $unit,
                assets: assets,
                sceneWidth: sceneWidth,
                sceneHeight: sceneHeight,
                sceneFill: canvasPane,
                canvasPane: canvasPane,
                mode: .editor,
                stretchHold: $stretchHold,
                onMessage: { ToastCenter.show($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
```

and after `SkeletonPreviewPanel(...)` inside the `ZStack`:

```swift
            if stretchHold || BoneStretch.hasStretchablePoint(unit) {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        StretchHoldButton(
                            leading: SkeletonChrome.sidebarWidth + 8,
                            isActive: stretchHold,
                            onHoldStart: { stretchHold = true },
                            onHoldEnd: { stretchHold = false }
                        )
                        .offsetLeadingIsland()
                        .paddingBottomSafeArea()
                        Spacer(minLength: 0)
                    }
                }
            }
```

- [ ] **Step 3: Confirm the preview still lays the canvas under the rail**

Run: `sed -n '1,60p' /Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonPreviewScreen.swift`
Expected: `SkeletonPreviewPanel` is still the `ZStack` first child after the canvas, so the button overlay does not steal the rail's taps. If the button covers the rail, move the `if` above `SkeletonPreviewPanel`.

---

### Task 9: "Stretchable bone" in the point dialog

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/EditPointDialog.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift` (`PointPropsEdit`, `openPointProps`, `applyPointProps`)

**Interfaces:**
- Consumes: `StickmanUnit.kinematicChainPointIds()`, `StickmanUnit.applyPointProps(id:attachable:fixed:stretchable:)`.
- Produces:
  - `EditPointDialog.init(isBase:attachable:fixed:stretchable:canStretch:onApply:)` where
    `onApply: (Attachable, Bool, Bool) -> Void` (attachable, fixed, stretchable)

- [ ] **Step 1: Extend the dialog's inputs**

```swift
struct EditPointDialog: View {
    var isBase: Bool
    /// Android disables the checkbox for the base and for any point on a kinematic chain;
    /// while disabled the stored flag is kept as-is.
    var canStretch: Bool
    var onApply: (Attachable, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attachable: Attachable
    @State private var fixed: Bool
    @State private var stretchable: Bool
    @State private var showingHelp = false

    init(
        isBase: Bool,
        attachable: Attachable,
        fixed: Bool,
        stretchable: Bool,
        canStretch: Bool,
        onApply: @escaping (Attachable, Bool, Bool) -> Void
    ) {
        self.isBase = isBase
        self.canStretch = canStretch
        self.onApply = onApply
        _attachable = State(initialValue: attachable)
        _fixed = State(initialValue: isBase ? false : fixed)
        _stretchable = State(initialValue: isBase ? false : stretchable)
    }
```

- [ ] **Step 2: Add the "Stretch" section**

Android `edit_point_dialog_new.xml`: a "Stretch" caption above a single "Stretchable bone" checkbox. Insert after the Attach cards block and before `sectionTitle("Node")`:

```swift
                sectionTitle("Stretch")
                stretchableCard
```

and the card itself, modelled on `invisibleCard`:

```swift
    private var stretchableCard: some View {
        Button {
            stretchable.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stretchable bone")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(stretchSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: stretchable && canStretch ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(stretchable && canStretch ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .opacity(canStretch ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStretch)
        .accessibilityLabel("Stretchable bone")
        .accessibilityAddTraits(stretchable && canStretch ? [.isSelected] : [])
    }

    private var stretchSubtitle: String {
        if isBase {
            return "The base point cannot stretch"
        }
        if !canStretch {
            return "Unavailable: kinematics drive this point"
        }
        return "Moves instead of rotating; the picture stretches along the bone"
    }
```

- [ ] **Step 3: Apply the flag**

```swift
    private var applyButton: some View {
        Button {
            onApply(attachable, isBase ? false : fixed, isBase ? false : stretchable)
            dismiss()
        } label: {
```

- [ ] **Step 4: Resolve `canStretch` where the dialog is presented**

`openPointProps` already has the unit and point. Extend `PointPropsEdit` and the sheet:

```swift
    private struct PointPropsEdit: Identifiable {
        var id: Int { pointId }
        let pointId: Int
        let isBase: Bool
        let attachable: Attachable
        let fixed: Bool
        let stretchable: Bool
        /// False for the base and for points on a kinematic chain (Android `EditPointDialog`).
        let canStretch: Bool
    }
```

```swift
        pointProps = PointPropsEdit(
            pointId: id,
            isBase: point.isBase,
            attachable: point.attachable,
            fixed: point.fixed,
            stretchable: point.stretchable,
            canStretch: !point.isBase && !unit.kinematicChainPointIds().contains(id)
        )
```

and at line ~255:

```swift
        .sheet(item: $pointProps) { draft in
            EditPointDialog(
                isBase: draft.isBase,
                attachable: draft.attachable,
                fixed: draft.fixed,
                stretchable: draft.stretchable,
                canStretch: draft.canStretch
            ) { attachable, fixed, stretchable in
                // Android keeps the stored flag while the checkbox is disabled.
                applyPointProps(
                    id: draft.pointId,
                    attachable: attachable,
                    fixed: fixed,
                    stretchable: draft.canStretch ? stretchable : nil
                )
            }
        }
```

- [ ] **Step 5: Forward the flag in `applyPointProps`**

```swift
    private func applyPointProps(
        id: Int,
        attachable: Attachable,
        fixed: Bool,
        stretchable: Bool?
    ) {
        guard var unit = optionalUnit else {
            bail("point props with no unit")
            return
        }
        prepareUndo()
        do {
            try unit.applyPointProps(id: id, attachable: attachable, fixed: fixed, stretchable: stretchable)
        } catch {
            bail(error)
            return
        }
        writeUnit(unit)
        layerEpoch += 1
    }
```

- [ ] **Step 6: Check no other presenter of the dialog was missed**

Run: `grep -rn "EditPointDialog(" /Users/zalivka/wsios/elements/at_elements --include=*.swift`
Expected: exactly one call site, in `SkeletonScreen.swift`, with `stretchable:` and `canStretch:` supplied.

---

### Task 10: Skeleton editor — clear covered flags on save, paint stretchable bones black

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift` (`saveItem`, line ~1010)
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift` (`drawSkeleton`, line ~578; color table line ~139)

**Interfaces:**
- Consumes: `StickmanUnit.clearStretchableOnKinematicChain()`.
- Produces: nothing consumed later.

- [ ] **Step 1: Clear on save, before thumbnails and the archive are written**

Android `SkeletonActivity.doSave` calls `clearStretchableCoveredByKinematics()` on the live unit first, so the editor and the saved file agree. `saveItem` currently takes `let unit = frame.units[0]`:

```swift
        var unit = frame.units[0]
        // Android `SkeletonActivity.doSave`: IK wins over stretch, so covered flags never
        // reach the saved item — and the editor must show the same thing.
        if unit.clearStretchableOnKinematicChain() {
            writeUnit(unit)
            layerEpoch += 1
            guard let refreshed = optionalUnit else {
                bail("save after clearing stretchable flags lost the unit")
                return
            }
            unit = refreshed
        }
```

- [ ] **Step 2: Paint stretchable points and their upstream edge black in skeleton mode**

Android `EditView.COLOR_STRETCHABLE = Color.BLACK`, applied to the edge whose `mEnd` is stretchable and to the point itself, after the selection and kinematic colours.

Color table (line ~139-152):

```swift
    /// Android `EditView.COLOR_STRETCHABLE`.
    static let boneStretchable = Color.black
```

In `drawSkeleton`'s edge loop, the existing `else` chain becomes:

```swift
            let edgeColor: Color
            if isSelected {
                edgeColor = Self.boneSelected
            } else if bones, drawn.point(optionalId: edge.to)?.stretchable == true {
                edgeColor = Self.boneStretchable
            } else if bones {
                edgeColor = Self.boneCommon
            } else {
                edgeColor = Self.color
            }
```

and the point loop:

```swift
            let color: Color
            if isSelected {
                color = Self.boneSelected
            } else if bones, point.stretchable {
                color = Self.boneStretchable
            } else if bones {
                color = Self.boneColor(point)
            } else {
                color = Self.color
            }
```

- [ ] **Step 3: Read the save path top to bottom**

Run: `sed -n '1010,1060p' /Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SkeletonScreen.swift`
Expected: the clear runs before `SceneThumbRenderer.itemPair(unit:assets:)` and before `ItemSaver.save(unit:assets:...)`, and `showingSave` is untouched by the clear. A clear that happens after the thumbnail render would save a stretched thumbnail next to a rest-length model.

---

### Task 11: Documentation

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/doc/skeleton-from-picture.md` (append a "Stretchable bones" section) — or `doc/gotchas.md` if that file owns editor behaviour.
- Reference: `/Users/zalivka/wsios/elements/at_elements/doc/2026-10-30-stretchable-bones-design.md`

**Interfaces:**
- Consumes: everything above.
- Produces: prose only.

- [ ] **Step 1: Append the section**

```markdown
## Stretchable bones

`stretchable="true"` in `model.xml` (Android `EditPointDialog` → "Stretchable bone") makes a
point's drag translate it and its descendants instead of rotating it about the parent, and the
bone picture stretches along the bone to keep covering it.

- Hold the bottom-left button (`skel_edit_shift`) to stretch. It appears only while the selected
  unit has a stretchable point, and it moves right with the Back button when a left panel opens.
- While held, a blue `#4DA3FF` circle marks every stretchable point of the active unit.
- Double-tap a stretchable point while held to snap it back to its `model.xml` rest length.
- The ratio is `edgeLength / (rest * unit.scale)` (`BoneStretch.ratio`), applied identically in
  `SkeletonCanvas`, `FrameRasterizer`, and `SkeletonOnion`.
- Kinematics win: a point on a Start → Stop/Base/fixed chain cannot be stretchable, and
  `SkeletonScreen.saveItem` clears any flag that kinematics newly covered.
```

- [ ] **Step 2: Confirm no doc drift**

Run: `grep -rn "stretchable" /Users/zalivka/wsios/elements/at_elements/doc --include=*.md`
Expected: the design doc, this plan, and the new section — no contradicting statement elsewhere. If `doc/gotchas.md` says the flag is Android-only, fix that line.

---

## Manual verification (run only when the user asks for a build)

The user's standing rule forbids building unless ordered directly. When they do order it:

1. Open an item with a stretchable bone (author one on Android, or tick the box in the skeleton editor and save).
2. Scene editor: the button is bottom-left, moves right when Insert/Edit Unit/Menu opens, disappears for a unit with no stretchable point.
3. Hold → drag the stretchable point: it follows the finger and its children translate; the artwork spreads along the bone.
4. Release, hold again, drag a non-stretchable point: it rotates, exactly as without the button.
5. Double-tap the stretched point while held: bone and picture return to rest length.
6. Export a frame: the video frame must match the canvas (proves `FrameRasterizer` got the ratio).
7. Skeleton editor: open the point dialog on a kinematic-chain point — the checkbox is disabled and the flag survives Apply.

A check that cannot fail is not a check: for step 6, compare the exported frame against the canvas **with the ratio deliberately removed** from `FrameRasterizer` alone. If both renders look identical, the rasterizer insertion is in the wrong place.
