# Onion Skeleton & Skeleton Color Design

## Goal

Add two features to the iOS app (`at_elements`), matching Android Stickman (`DefaultSkeletonDrawer.java`, `StickmanViewDrawer.java`, `Settings.java`):

1. **Onion skeleton**: Show a light-gray (`#CCCCCC`) skeleton of the previous frame (`currentIndex - 1`) in the scene editor (`SkeletonCanvas` in `.editor` mode).
2. **Skeleton color setting**: Allow the user to customize the skeleton color, affecting **only normal (otherwise orange `#FF7100`) bones and nodes** and leaving special bone/node colors (`boneStretchable`, `boneSelected`, `.skeleton` mode `boneCommon` / `boneSlave` / `boneMaster` / `boneInvisible`, and dimmed onion skeletons) unchanged.

## 1. Settings (`Shared/Model/AppSettings.swift`)

Add two persisted keys and properties to `AppSettings`:

- **`showOnionSkeletonKey = "showOnionSkeleton"`** & **`showOnionSkeleton: Bool`**:
  - Defaults to `true` when key is missing in `UserDefaults.standard`.
- **`skeletonColorRGBKey = "skeletonColorRGB"`** & **`skeletonColorRGB: Int`**:
  - `static let defaultSkeletonColorRGB = 0xFF7100` (matching `SkeletonCanvas.color` / Android `DefaultSkeletonDrawer` default `#FF7100`).
  - Defaults to `0xFF7100` when key is missing, masked with `& 0xFFFFFF`.
  - Helper `static func color(fromRGB rgb: Int) -> Color` and `static func rgb(from color: UIColor) -> Int?` for 24-bit RGB (`0xRRGGBB`) conversion.

## 2. Settings UI (`Shared/UI/AppSettingsSheet.swift`)

Add an **"Editor"** section at the top of `AppSettingsSheet.formBody` (after `#if DEBUG` if present) matching `doc/good_dialog.md` card chrome:

- **`onionSkeletonCard`**:
  - Toggle card matching `antialiasingCard` style (`checkmark.square.fill` / `square`), bound to `@State private var showOnionSkeleton: Bool`.
  - Title: `"Onion skeleton"`, subtitle: `"Show gray skeleton of previous frame"`.
- **`skeletonColorCard`**:
  - Card showing an 18pt circle filled with the selected `Color(fromRGB: skeletonColorRGB)` (with a 1pt white/25% stroke), title `"Color of skeletons"`, subtitle showing `#RRGGBB` hex string, and a `"Reset"` capsule button when `skeletonColorRGB != AppSettings.defaultSkeletonColorRGB`.
  - Tapping the card opens `FlexColorPickerSheet` with the current color; confirming updates `skeletonColorRGB`.
- **`applyButton`** (and DEBUG `tutorialCard`):
  - Saves `AppSettings.showOnionSkeleton = showOnionSkeleton` and `AppSettings.skeletonColorRGB = skeletonColorRGB`.

## 3. Skeleton Color & Onion Skeleton (`Shared/UI/SkeletonCanvas.swift` & `at_elements/Screens/SceneEditorScreen.swift`)

Matching Android `StickmanViewDrawer.drawEditor` + `DefaultSkeletonDrawer.drawSkeleton`:

- **`SkeletonCanvas` constants & inputs**:
  - `static let onionSkeletonColor = Color(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255)` (Android `Color.LTGRAY`).
  - `var previousFrameUnits: [StickmanUnit] = []`
  - `@AppStorage(AppSettings.showOnionSkeletonKey) private var showOnionSkeleton = true`
  - `@AppStorage(AppSettings.skeletonColorRGBKey) private var skeletonColorRGB = AppSettings.defaultSkeletonColorRGB`
- **Draw order in `.editor` mode**:
  1. Scene background & scene bound.
  2. Current frame's unit contents (`drawUnitContent`).
  3. Attach/stretch expose circles (`drawAttachExpose`, `drawStretchExpose`).
  4. **Onion skeleton pass** (when `showSkeleton && showOnionSkeleton` and `!previousFrameUnits.isEmpty`):
     - Sort `previousFrameUnits` by `(arrange, name)` (same ordering as `unitsToDraw`).
     - Draw each unit with `drawSkeleton(drawn, context: &context, layout: layout, dim: true)`.
  5. Current frame's skeletons (`drawUnitSkeleton` -> `drawSkeleton(drawn, context: &context, layout: layout, dim: false)`).
  6. Camera rectangle, handlers, touch point.
- **`drawSkeleton(_ drawn: StickmanUnit, context: inout GraphicsContext, layout: SkeletonLayout, dim: Bool = false)`**:
  - Let `normalColor = dim ? Self.onionSkeletonColor : AppSettings.color(fromRGB: skeletonColorRGB)`.
  - **Edges**:
    - When `dim == true`: `edgeColor = Self.onionSkeletonColor` (matching Android `DefaultSkeletonDrawer`: `!dim && sk_edge.mEnd.mStretchable ? COLOR_STRETCHABLE : simpleColor`).
    - When `dim == false`: `isSelected` -> `Self.boneSelected`; `stretchable` -> `Self.boneStretchable`; `bones` (`.skeleton` mode) -> `Self.boneCommon`; otherwise -> `normalColor`.
  - **Points**:
    - Skip points where `!bones && !drawn.canBeDragged(point)` (matches Android `if (!Frame.canBeDragged(point)) return 0`).
    - When `dim == true`: `color = Self.onionSkeletonColor` (matching Android `nodeColor`: when `dim` is true, returns `DIM_COLOR` even for stretchable points).
    - When `dim == false`: `isSelected` -> `Self.boneSelected`; `point.stretchable` -> `Self.boneStretchable`; `bones` -> `Self.boneColor(point)`; otherwise -> `normalColor`.
- **`SceneEditorScreen`**:
  - Pass `previousFrameUnits: scene.currentIndex > 0 ? scene.frames[scene.currentIndex - 1].units : []` to `SkeletonCanvas`.
