# Onion Skeleton & Skeleton Color Design

## Goal

Add two features to the iOS app (`at_elements`), matching Android Stickman (`DefaultSkeletonDrawer.java`, `StickmanViewDrawer.java`, `Settings.java`):

1. **Onion skeleton**: Show a light-gray (`#CCCCCC`) skeleton of the previous frame (`currentFrameIndex - 1`) in the scene editor (`SkeletonCanvas` in `.editor` mode).
2. **Skeleton color setting**: Allow the user to customize the skeleton color, affecting **only normal (otherwise orange `#FF7100`) bones** and leaving special bone colors (stretchable black, kinematic hot pink `#FF69B4`, slave red, master green, attachable cyan) and special point handles unchanged.

## 1. Settings (`AppSettings.swift`)

Add two persisted properties to `AppSettings`:

- **`showOnionSkeleton: Bool`**:
  - Key: `"at_elements.showOnionSkeleton"`
  - Default: `true`
- **`skeletonColorRGB: Int`**:
  - Key: `"at_elements.skeletonColorRGB"`
  - Default: `0xFF7100` (matching Android `DefaultSkeletonDrawer` default `#FF7100`)
  - Helper `skeletonColor: Color`: converts between 24-bit RGB `Int` (`0xRRGGBB`) and SwiftUI `Color`.

## 2. Settings UI (`AppSettingsSheet.swift`)

Add an **"Editor"** section in `AppSettingsSheet`:

- **Onion skeleton** (`Toggle`): bound to `AppSettings.showOnionSkeleton`, subtitle `"Show gray skeleton of previous frame"`.
- **Color of skeletons** (`Button` row): shows title `"Color of skeletons"`, current hex subtitle (`#RRGGBB`), and a circular color swatch of the current `skeletonColor`, plus a `"Reset"` action when different from `#FF7100`. Tapping opens `FlexColorPickerSheet` to pick a new color.

## 3. Skeleton Color (`SkeletonCanvas.swift`)

In `SkeletonCanvas.drawSkeleton`:

- Replace the hardcoded `Self.color` (`#FF7100`) for normal non-dim bones with `skeletonColor` (passed into `SkeletonCanvas`, defaulting to `AppSettings.skeletonColor`).
- Specifically, in `drawSkeleton` when `dim == false`:
  ```swift
  let boneColor: Color = if edge.group.isStretchable {
      .black
  } else if isKinematicEdge(edge) {
      Color(red: 1, green: 0x69 / 255.0, blue: 0xB4 / 255.0)
  } else {
      skeletonColor
  }
  ```
- Special bone colors (stretchable `.black`, kinematic `#FF69B4`), attachment/selection colors (`slaveColor`, `masterColor`, `attachableColor`, `selectedColor`, `lockedColor`), and base/point node colors remain unchanged.

## 4. Onion Skeleton (`SkeletonCanvas.swift` & `SceneEditorScreen.swift`)

Matching Android `StickmanViewDrawer.drawEditor` + `DefaultSkeletonDrawer.drawSkeleton`:

- **`SkeletonCanvas` inputs**:
  - `previousFrame: StickmanFrame? = nil`
  - `showOnionSkeleton: Bool = AppSettings.showOnionSkeleton`
  - `skeletonColor: Color = AppSettings.skeletonColor`
- **Draw order in `.editor` mode**:
  1. Scene background & camera rect.
  2. Current frame's filled units (`drawUnit`).
  3. **Onion skeleton pass** (when `showOnionSkeleton`, `!hideAllBones`, and `let previousFrame`):
     - Iterate over `unitsToDraw(in: previousFrame)` (filtering out hidden units via `hiddenUnitIndices`).
     - Call `drawOnionSkeleton(context: &context, unit: unit, scale: scale)`.
  4. Current frame's skeletons (`drawSkeleton` with `dim: unit.locked || isDimmed(idx)`).
- **`drawOnionSkeleton` behavior**:
  - Matches Android `DefaultSkeletonDrawer` when `dim == true` (`DIM_COLOR = Color.LTGRAY` = `#CCCCCC`, full opacity `1.0`):
  - All visible bones (`!edge.group.isInvisible`, or `showInvisibleBones`) are drawn in `Self.onionSkeletonColor` (`Color(red: 0xCC / 255.0, green: 0xCC / 255.0, blue: 0xCC / 255.0)`), with line width `max(2.0, 2.0 * scale)`.
  - Every non-invisible joint node (including base point and child endpoints) is drawn as a circle of radius `pointRadius` (`6.0 * scale`) filled with `Self.onionSkeletonColor` (`#CCCCCC`) with a `1 * scale` black stroke (no white inner dot on the base point, matching Android `if (!dim) { draw white inner circle }` in `DefaultSkeletonDrawer.java` lines 163–167).
  - Non-interactive: `hitTestPoint` only inspects `frame`, never `previousFrame`.
- **`SceneEditorScreen`**:
  - Passes `previousFrame: currentFrameIndex > 0 ? scene.frames[currentFrameIndex - 1] : nil`, `showOnionSkeleton: showOnionSkeleton`, and `skeletonColor: skeletonColor` to `SkeletonCanvas`.
  - Refreshes state when `AppSettingsSheet` closes or settings change.
