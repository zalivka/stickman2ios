# BonePaper Brush Offset — iOS Design Spec

## Overview

When drawing with a finger on a touchscreen, the user's fingertip occludes the exact pixel being painted, erased, filled, or sampled. **Brush Offset** shifts the active tool target vertically upward in screen space (`-Y` by `0...70 pt` in `10 pt` steps) and displays a live crosshair/ring cursor at the offset target point while the user's finger is touching the canvas.

The setting is configured in `AppSettingsSheet` under a new **"Drawing tools"** section so that the BonePaper left tool rail requires no extra buttons or scrolling on iPhone.

---

## 1. Settings Persistence (`AppSettings` & `BonePaperFlags`)

### `BonePaperFlags` (`Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift`)
- Add `public static var brushOffset: CGFloat = 0`.
- Represents the upward vertical offset in screen points (`>= 0`).

### `AppSettings` (`Shared/Model/AppSettings.swift`)
- Add key `private static let brushOffsetKey = "paperDrawBrushOffset"`.
- Constants:
  - `static let maxBrushOffset: Int = 70`
  - `static let brushOffsetStep: Int = 10`
- `static var brushOffset: Int`:
  - Reads `UserDefaults.standard.integer(forKey: brushOffsetKey)` (defaults to `0` when absent).
  - Clamps to `0...maxBrushOffset` and rounds to nearest multiple of `brushOffsetStep` (`10`).
  - Setter writes the clamped integer to `UserDefaults` and sets `BonePaperFlags.brushOffset = CGFloat(clamped)`.
- `AppSettings.boot()` copies `CGFloat(brushOffset)` to `BonePaperFlags.brushOffset` at app launch alongside `BonePaperFlags.antialiasing`.

---

## 2. Settings UI (`AppSettingsSheet`)

### "Drawing tools" Section (`Shared/UI/AppSettingsSheet.swift`)
- Add `@State private var brushOffset: Double` initialized to `Double(AppSettings.brushOffset)` in `AppSettingsSheet.init`.
- In `applyButton`, persist `AppSettings.brushOffset = Int(brushOffset.rounded())` alongside `AppSettings.paperDrawAntialiasing = antialiasing`.
- In `formBody`, add a `"Drawing tools"` header (`12 pt bold`, `SkeletonChrome.toolLabel`, uppercase — matching `"Paper draw"`) and a `brushOffsetCard`:
  - **Header Row**:
    - Leading `18 × 18` status dot (`SkeletonChrome.bonesAccent` when `brushOffset > 0`, grey `0x999999` when `0`).
    - Title: `"Brush offset"` (`16 pt semibold`, white) and subtitle: `"Shift drawing point above finger"` (`13 pt`, `white.opacity(0.55)`).
    - Trailing value readout: `"\(Int(brushOffset.rounded())) / \(AppSettings.maxBrushOffset)"` (`15 pt bold monospacedDigit`, white).
  - **Slider Row**:
    - `Slider(value: $brushOffset, in: 0...Double(AppSettings.maxBrushOffset), step: Double(AppSettings.brushOffsetStep))` tinted with `SkeletonChrome.bonesAccent`.
  - **Card Background**:
    - `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled with `Color.white.opacity(brushOffset > 0 ? 0.12 : 0.05)`.

---

## 3. Coordinate Transformation in `BonePaperCanvas`

### Why Screen-Space Vertical Offset
`BonePaperDrawView` (`paper`) is transformed by `BonePaperStageView` with rotation (`angle`), optional horizontal/vertical flip (`mirror`), and scale (`zoom`). Applying the offset in `BonePaperStageView` / window coordinates before converting into `paper` ensures that **"above the finger"** is always straight up on the physical screen (`y - BonePaperFlags.brushOffset`) regardless of bone rotation or zoom.

### Touch & Pipette Coordinate Pipeline (`Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift`)
1. **Pen, Eraser, Fill (`BonePaperDrawView`)**:
   - Helper `offsetLocation(for touch: UITouch) -> CGPoint` inside `BonePaperDrawView`:
     - Let `offset = BonePaperFlags.brushOffset`.
     - If `offset <= 0` or `superview == nil`, return `touch.location(in: self)`.
     - Otherwise, take `stagePt = touch.location(in: superview)`, shift `shiftedStagePt = CGPoint(x: stagePt.x, y: stagePt.y - offset)`, and return `convert(shiftedStagePt, from: superview)`.
   - `worldPoint(_ touch: UITouch)` uses `offsetLocation(for: touch)` instead of `touch.location(in: self)`.
   - Note: `pendingView` / `strokeSlop` distance check continues to measure finger movement in screen/view space (or shifted view space — the delta `dx, dy` is identical because the offset is constant during a stroke).
2. **Pipette (`BonePaperStageView.sampleColor(atWindow:)`)**:
   - Shift the incoming window point upward by `BonePaperFlags.brushOffset`:
     \[
     \text{targetWindow} = \left(\text{point.x},\; \text{point.y} - \text{BonePaperFlags.brushOffset}\right)
     \]
   - Convert `targetWindow` into `paper` and sample the pixel as before.

---

## 4. Live Canvas Target Cursor (`BonePaperStageView`)

### Visual Design
When `BonePaperFlags.brushOffset > 0` and the user touches the canvas with Pen, Eraser, Fill, or drags the Pipette:
- `BonePaperStageView` renders a non-interactive `cursorLayer: CAShapeLayer` above `paper` at the shifted stage point `targetStage = CGPoint(x: fingerStage.x, y: fingerStage.y - offset)`:
  - **Pen / Eraser**:
    - Circle of radius `max(brushSize / 2 * zoom, 4)` centered at `targetStage` so the user sees the actual brush/eraser footprint, plus a small center crosshair (`±5 pt` arms).
  - **Fill / Pipette**:
    - Compact target ring (`radius = 6 pt`) + crosshair (`±9 pt` arms) centered at `targetStage`.
  - **Dual-Contrast Stroke**:
    - Underlay white halo (`lineWidth = 3`, `UIColor.white.withAlphaComponent(0.85)`) + overlay dark/accent stroke (`lineWidth = 1.5`, `UIColor.black.withAlphaComponent(0.85)`) so the cursor is clearly visible over dark ink, white fills, and the grey checker backdrop alike.

### Cursor Lifecycle
- **Show / Move**:
  - `BonePaperDrawView.touchesBegan` and `touchesMoved` notify `stageView?.updateOffsetCursor(touch: touch, brushSize: brushSize, tool: tool)`.
  - `BonePaperStage.sampleColor(atWindow:)` updates the cursor at the offset stage point while the pipette drag is active, and `BonePaperStage.clearCursor()` hides it when the pipette drag ends.
- **Hide**:
  - Hidden immediately on `touchesEnded`, `touchesCancelled`, `abortStroke()` (e.g. when a second finger starts a pinch/pan), or when `BonePaperFlags.brushOffset <= 0`.

---

## 5. Files Affected

- `Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift`: Add `public static var brushOffset: CGFloat = 0`.
- `Shared/Model/AppSettings.swift`: Add `brushOffset` (`0...70`, step `10`) persisted in `UserDefaults` and synced in `boot()`.
- `Shared/UI/AppSettingsSheet.swift`: Add `"Drawing tools"` section with the `"Brush offset"` slider card.
- `Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift`: Apply screen-space upward offset in `BonePaperDrawView` and `BonePaperStageView.sampleColor`, and render/manage the live target cursor layer on `BonePaperStageView`.
- `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`: Call `stage.clearCursor()` when `BonePaperPipetteButton` drag ends.
