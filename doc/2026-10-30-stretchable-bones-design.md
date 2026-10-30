# Stretchable Bones Design

**Date:** 2026-10-30
**Platform:** iOS (`at_elements` / `BonePaper`)
**Android reference:** `stickman` (`MainEditor`, `ItemPreview`, `PointManipulator`, `BonePictureStretch`, `DefaultSkeletonDrawer`), `fingerpaint` (`EditView`, `EditPointDialog`, `EditUnit`, `SkeletonActivity`)

## Overview

A bone point can be flagged `stretchable="true"` in `model.xml`. On Android that flag turns the
point's drag behaviour from *rotate around the parent* into *translate the point and its
descendants*, and it makes the bone picture stretch along its bone so the artwork keeps covering
the longer bone.

iOS already parses and writes the flag (`ItemLoader`, `StickmanPoint.stretchable`) but nothing
reads it: no runtime stretch, no picture scaling, no authoring UI. This design closes those gaps.

## 1. Runtime interaction

### 1.1 Hold button

Android: `main_shift` (`shift_main.png`) sits at the top-start of the scene, visible only while the
active unit has a stretchable point — `mShift` in `MainEditor`, `item_preview_shift` in
`ItemPreview`, both driven by `hasUnitWithStretchableBone()` (stretchable, not `kinematicStart`)
and forced visible while held (`setVisibility(GONE)` would cancel the touch).

iOS: a floating hold button in the **bottom-left corner**, drawn with the existing
`chrome/skel_edit_shift.png` (same icon artefact the skeleton editor's DRAW panel already uses for
Shift Bone). It is placed with the same leading offset rule as `FullscreenBackButton`, so it slides
right when the left tool column opens:

- scene editor: `MainPanel.width + backExtraLeading + 8`
- skeleton item preview: `SkeletonChrome.sidebarWidth + 8`

Bottom padding uses the existing `paddingBottomSafeArea()` modifier, and horizontal the existing
`offsetLeadingIsland()`.

The touch surface is the existing `HoldTouchPad` (`UILongPressGestureRecognizer` with
`minimumPressDuration = 0`, simultaneous recognition), which survives a second finger on the canvas
— the same reason the NEW and Shift Bone buttons use it.

Held-state banner, mirroring `main_shift_hold_tip`: "Keep holding to move a stretchable point".

### 1.2 Drag semantics

`SkeletonCanvas` already has both move primitives:

- `StickmanUnit.drag(id:destX:destY:)` — Android `PointManipulator.simpleMove` (rotate about parent)
- `StickmanUnit.movePointAndDescendants(id:destX:destY:)` — Android `PointManipulator.stretchMove`

While the hold button is down and the captured point is `stretchable && !isBase && !kinematicStart`,
the drag calls `movePointAndDescendants` instead of `drag`. Everything else — undo push, slave
carry-over (`followAttachedSlaves`), retweening on finger-up — is unchanged because the canvas'
existing capture path is reused.

Non-stretchable points keep rotating while the button is held, exactly like Android
(`PointManipulator.move` falls through to `simpleMove`).

### 1.3 Rest-length restore

Android `TouchPointUseCase.noteOrRestoreStretchTap`: while Shift is held, a double tap on the same
stretchable point within `ViewConfiguration.getDoubleTapTimeout()` calls
`PointManipulator.restoreRestLength`, which puts the point back on the same ray from its parent at
`rest * unit.scale`.

On iOS the canvas already receives `onDoubleTap`; while the button is held it resolves the hit
point and calls `StickmanUnit.restoreRestLength(id:rest:)` with `UnitAssets.restLength`.

### 1.4 Expose circles

Android `UnitDrawer`: while Shift is held, blue `#4DA3FF` circles at `EXPOSE_OPACITY` (170) mark
every stretchable, non-kinematic-start point of the active unit. iOS draws the same circles at
`StickmanUnit.exposeMarkerRadius` (the same screen radius `drawAttachExpose` uses).

## 2. Rendering

Android `BonePictureStretch.apply` post-multiplies the bone matrix with
`rotate(-a) · scale(ratio, 1) · rotate(a)` about the joint, where
`ratio = edgeLength / (rest * unit.scale)`. The picture therefore widens along the bone; its
offsets (`x_offset`) stretch with it.

The SwiftUI/`CGContext` draw stacks already do `translate(start) · rotate(angle)`, so the same
result is a single `scaleBy(x: ratio, y: 1)` inserted right after the rotation.

Three renderers share that stack and all need the ratio:

- `Shared/UI/SkeletonCanvas.swift` — `drawBitmaps` (editor, skeleton editor, previews, posters)
- `Shared/Loaders/FrameRasterizer.swift` — `drawBitmaps` (video export, thumbnails)
- `Shared/Model/SkeletonOnion.swift` — the BonePaper onion overlay

`ratio` returns `nil` (draw as authored) when the point is not stretchable, the model rest length
is unknown, or the bone is currently at rest length.

## 3. Authoring

Android only lets you *set* the flag in the skeleton editor: `EditPointDialog` has a
"Stretchable bone" checkbox that is disabled when the point is the base or lies on a kinematic
chain (`EditUnit.collectKinematicChainPoints`), keeps its stored value when disabled, and warns
(`stretchable_disabled_by_kinematics`) when a kinematics edit newly covers a stretchable point.
`SkeletonActivity.doSave` then clears the flag on every kinematics-covered point
(`clearStretchableCoveredByKinematics`), because IK would fight the stretch.

iOS mirrors that:

- `EditPointDialog` gains a "Stretch" section with the same enable/keep rules.
- `StickmanUnit` gains `kinematicChainPointIds()` and `clearStretchableOnKinematicChain()`.
- `SkeletonScreen.saveItem` clears covered flags before saving.
- `.skeleton` mode paints stretchable points and their upstream edge black (`COLOR_STRETCHABLE`),
  same as `DefaultSkeletonDrawer`.

## Out of scope

- No changing `FeatureFlags`.
- No new Android behaviour.
- No automated tests.
