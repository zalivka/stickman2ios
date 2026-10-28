# BonePaper Drawing Config, Per-Item Palette, and Slider Marks Design

**Date:** 2026-10-28  
**Platform:** iOS (`at_elements` / `BonePaper`)

## Overview

When coloring bone pictures in `BonePaperScreen`, the user needs immediate continuity across sessions:
1. **Last-used tool state (`BonePaperToolStore` in `UserDefaults`)** — restores the active brush size, eraser size, opacity, and active color across `BonePaperScreen` launches (matching Android `BonePaperActivity` `PREF_BRUSH_SIZE`, `PREF_ERASER_SIZE`, `PREF_OPACITY`, `PREF_COLOR`).
2. **Per-item drawing history (`BonePaperDrawingConfig` in `bonepaper.json`)** — stores the item's used colors (palette), used brush sizes, used eraser sizes, and used opacity values inside the item's `.ati` archive (`bonepaper.json`), plus a global fallback in `BonePaperToolStore` for sheet/background sessions.
3. **Slider tick marks & magnetic snapping** — `BonePaperDragControl` displays up to 5 previously used values as tick marks on the slider track, snaps to them within a 6 pt magnetic zone while dragging, and jumps directly to a mark when tapped while pinned open.
4. **Top-of-strip item palette** — `BonePaperColorStrip` surfaces colors actually painted on the item at the top of the swatch strip (right after `.transparent`), followed by global custom colors and default presets without duplicates.

---

## 1. Data Model & Persistence

### 1.1 `BonePaperDrawingConfig` (`Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`)

```swift
public struct BonePaperDrawingConfig: Codable, Equatable, Sendable {
    public static let maxSliderMarks = 5
    public static let maxPaletteColors = 16

    public var palette: [String]      // "#RRGGBB" MRU, max 16
    public var brushSizes: [CGFloat]  // Rounded integers in 1...48, MRU, max 5
    public var eraserSizes: [CGFloat] // Rounded integers in 1...48, MRU, max 5
    public var opacities: [CGFloat]   // Rounded to 0.01 in 0.01...1.0, MRU, max 5

    public init(
        palette: [String] = [],
        brushSizes: [CGFloat] = [],
        eraserSizes: [CGFloat] = [],
        opacities: [CGFloat] = []
    )
}
```

### 1.2 Mutating Helpers on `BonePaperDrawingConfig`

- **`recordPenOrFill(colorHex: String?, brushSize: CGFloat?, opacity: CGFloat)`**:
  - If `colorHex` is non-nil (i.e., not `.clear`), normalizes to uppercase `#RRGGBB`, removes any existing match in `palette`, inserts at index `0`, and trims `palette` to `maxPaletteColors` (`16`).
  - If `brushSize` is non-nil (pen stroke/dot), rounds to `CGFloat(Int(brushSize.rounded()))` clamped to `1...48`, removes any existing match in `brushSizes`, inserts at index `0`, and trims to `maxSliderMarks` (`5`).
  - Rounds `opacity` to `CGFloat((opacity * 100).rounded()) / 100` clamped to `0.01...1.0`, removes any existing match in `opacities`, inserts at index `0`, and trims to `maxSliderMarks` (`5`).
- **`recordEraser(eraserSize: CGFloat)`**:
  - Rounds `eraserSize` to `CGFloat(Int(eraserSize.rounded()))` clamped to `1...48`, removes any existing match in `eraserSizes`, inserts at index `0`, and trims to `maxSliderMarks` (`5`).

### 1.3 `BonePaperToolStore` (`Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`)

Persists in `UserDefaults.standard`:
- `bonepaper.brush_size` (`Double`, default `14`, clamped `1...48`)
- `bonepaper.eraser_size` (`Double`, default `14`, clamped `1...48`)
- `bonepaper.opacity` (`Double`, default `1.0`, clamped `0.01...1.0`)
- `bonepaper.color` (`String`, `"#RRGGBB"` or `"CLEAR"`, default `"#000000"`)
- `bonepaper.fallback_drawing_config` (`Data` JSON-encoded `BonePaperDrawingConfig` for sheet/background mode when no item config is supplied)

### 1.4 `BonePaperManifest` & `UnitAssets` (`Shared/Model/UnitAssets.swift`)

- Extend `BonePaperManifest`:
  ```swift
  struct BonePaperManifest: Codable {
      struct Entry: Codable {
          var entry: String
          var sha256: String
      }

      var version: Int
      var buffers: [String: Entry]
      var drawingConfig: BonePaperDrawingConfig?
  }
  ```
- `UnitAssets` stores `private var drawingConfigs: [String: BonePaperDrawingConfig] = [:]` keyed by `Self.removeNumber(unitName)` (and includes `drawingConfigs` in `UnitAssets.Snapshot` for undo/redo consistency).
- `drawingConfig(for unitName: String) -> BonePaperDrawingConfig` and `setDrawingConfig(_ config: BonePaperDrawingConfig, for unitName: String)` read and update the per-unit config.
- In `attachSidecars(zip:)`: if `manifest.drawingConfig` is present for the unit being installed, store a sanitized copy in `drawingConfigs[unitKey]`.
- In `sidecarFiles(unitName:pngs:)`: write `bonepaper.json` whenever `!files.isEmpty` **or** `drawingConfigs[name]` is non-empty, so `drawingConfig` persists inside `.ati` archives.

---

## 2. Recording Used Values on Canvas Commit

In `BonePaperCanvas.swift` (`BonePaperStageView`):
- Add `var onCommitStroke: (() -> Void)?` callback on `BonePaperStageView` (passed from `BonePaperCanvas` -> `BonePaperScreen`).
- Trigger `onCommitStroke?()` only when a real drawing action commits:
  1. `finishStroke(cancelled: false)` when `strokeMoved` is `true` (a drag stroke completed without being cancelled by a 2-finger pinch).
  2. Single-tap dot in `touchesEnded` when `!strokeMoved` and `tool == .pen || tool == .eraser`.
  3. Paint-bucket fill in `touchesEnded` when `tool == .fill`.
- In `BonePaperScreen`:
  - When `onCommitStroke` fires:
    - If `tool == .pen`: call `drawingConfig.recordPenOrFill(colorHex: currentHexOrNil, brushSize: brushSize, opacity: opacity)`. Also if `currentHexOrNil` is non-nil, call `BonePaperColorStore.remember(hex)` if it's a custom color.
    - If `tool == .fill`: call `drawingConfig.recordPenOrFill(colorHex: currentHexOrNil, brushSize: nil, opacity: opacity)` (fill uses color + opacity, not brush size).
    - If `tool == .eraser`: call `drawingConfig.recordEraser(eraserSize: eraserSize)`.
    - Persist updated tool values and fallback config to `BonePaperToolStore`.

---

## 3. Slider Track Marks & Snapping (`BonePaperDragControl`)

`BonePaperDragControl` receives `var marks: [CGFloat]`:

### 3.1 Visual Ticks
- For each mark `m` in `marks` (clamped to `range`):
  - Compute `markRatio = (m - range.lowerBound) / (range.upperBound - range.lowerBound)`.
  - Compute `markX = Self.trackPadding + markRatio * lineWidth`.
  - Render a vertical capsule tick (`width: 2`, `height: 11`) centered on the horizontal track line (`y: 26`), colored `Color.black.opacity(0.45)`.

### 3.2 Soft Magnetic Snapping While Dragging
- In `drag.onChanged`:
  - Compute raw track position `rawX = min(max(drag.location.x - valueStart, 0), valueWidth)`.
  - Find the nearest mark `m` in `marks` by horizontal distance `abs(rawX - markOffsetX)` where `markOffsetX = ((m - range.lowerBound) / span) * valueWidth`.
  - If the nearest mark is within `snapRadius = 6` pt, set `value = m`; otherwise set `value = range.lowerBound + (rawX / valueWidth) * span`.

### 3.3 Tap-to-Jump When Pinned Open
- When `pinned` is `true`, tapping on the open track at location `x >= valueStart` checks if `x - valueStart` is within `14` pt of any mark's `markOffsetX`.
- If a mark is within `14` pt, `value` jumps to that mark `m` (and triggers `onActivate()`), keeping the track pinned open. Tapping the tool icon itself (`x < Self.side`) still unpins and closes the bar as before.

---

## 4. Per-Item Palette Strip & Screen Integration

### 4.1 `BonePaperColorStrip`
- Accepts `var itemPalette: [String]`.
- Builds deduplicated swatches in order:
  1. `.transparent`
  2. `itemPalette` (`#RRGGBB` colors used on this item, MRU order)
  3. `extras` (`BonePaperColorStore.load()`, global custom colors not already in `itemPalette`)
  4. `BonePaperColorStore.presets` (standard presets not already in `itemPalette` or `extras`)
- If `itemPalette` is non-empty, renders a subtle `1 pt` divider line (`Color.white.opacity(0.22)`) between the rows containing `.transparent + itemPalette` and the remaining preset/global rows so the item's own palette is visually distinct at the top of the rail.

### 4.2 `BonePaperScreen` & `SkeletonScreen`
- `BonePaperScreen` initializers accept optional `initialDrawingConfig: BonePaperDrawingConfig? = nil` andInclude `public let drawingConfig: BonePaperDrawingConfig` on `BonePaperExport`.
- On `BonePaperScreen.init`, state initializes `brushSize`, `eraserSize`, `opacity`, and `color` from `BonePaperToolStore` (and switches `tool = .fill` if the restored color is `.clear`).
- Any change to `brushSize`, `eraserSize`, `opacity`, or `color` updates `BonePaperToolStore`.
- In `SkeletonScreen`:
  - `BonePaperEditSession` includes `var drawingConfig: BonePaperDrawingConfig`.
  - `openBonePaper` loads `assets.drawingConfig(for: unit.name)` into the session.
  - `applyBonePaper` saves `export.drawingConfig` back into `assets.setDrawingConfig(export.drawingConfig, for: unit.name)`.

---

## 5. Error Handling & Edge Cases

- **Backward compatibility with existing `bonepaper.json`**: `drawingConfig` is optional (`BonePaperDrawingConfig?`) in `BonePaperManifest`. Existing `.ati` archives without `drawingConfig` decode cleanly with `nil`.
- **Corrupted or out-of-range values in JSON**: `BonePaperDrawingConfig` sanitizes loaded arrays on decode/install (filtering out invalid hex strings, clamping sizes to `1...48` and opacities to `0.01...1.0`, deduplicating, and capping counts).
- **Cancelled strokes (pinch-to-zoom)**: `cancelStroke()` does not fire `onCommitStroke`, so accidental touches during 2-finger zoom never pollute slider marks or palette history.
