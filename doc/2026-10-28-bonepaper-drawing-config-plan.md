# BonePaper Drawing Config, Per-Item Palette, and Slider Marks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist last-used BonePaper drawing settings across launches in `UserDefaults`, record used colors and slider values (brush size, eraser size, opacity) per item in `bonepaper.json` on stroke/fill commit, display tick marks with magnetic snap and tap-to-jump on sliders, and surface the item's used colors at the top of the right-hand palette strip.

**Architecture:** Introduce `BonePaperDrawingConfig` (Codable MRU history of palette colors, brush sizes, eraser sizes, and opacities) and `BonePaperToolStore` (`UserDefaults` persistence for active tool settings + global fallback config) inside the `BonePaper` package. Extend `BonePaperManifest` (`bonepaper.json`) and `UnitAssets` to load/save per-item `BonePaperDrawingConfig`, hook stroke/fill commits in `BonePaperCanvas` to record used values, add tick marks + magnetic snap + tap-to-jump in `BonePaperDragControl`, and render the per-item palette section at the top of `BonePaperColorStrip`.

**Tech Stack:** Swift, SwiftUI, UIKit, CoreGraphics, Foundation (`UserDefaults`, `Codable`).

## Global Constraints

- Do NOT run `xcodebuild` or compile iOS/Android sources unless explicitly ordered by the user. Use `ReadLints` after edits to verify zero warnings/errors.
- Do NOT write unit tests unless explicitly ordered by the user.
- Brush & eraser size range: `1...48` (marks rounded to integer `CGFloat`, max 5 MRU marks).
- Opacity range: `0.01...1.0` (marks rounded to `0.01` increments, max 5 MRU marks).
- Item palette cap: max 16 `#RRGGBB` uppercase hex colors in MRU order.
- Slider magnetic snap radius: `6` pt on track; tap-to-jump radius when pinned open: `14` pt on track.

---

### Task 1: `BonePaperDrawingConfig` and `BonePaperToolStore` Models

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift:1-15`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift:15-26`

**Interfaces:**
- Produces:
  - `public struct BonePaperDrawingConfig: Codable, Equatable, Sendable`
    - `public static let maxSliderMarks = 5`
    - `public static let maxPaletteColors = 16`
    - `public var palette: [String]`
    - `public var brushSizes: [CGFloat]`
    - `public var eraserSizes: [CGFloat]`
    - `public var opacities: [CGFloat]`
    - `public var isEmpty: Bool`
    - `public func sanitized() -> BonePaperDrawingConfig`
    - `public mutating func recordPenOrFill(colorHex: String?, brushSize: CGFloat?, opacity: CGFloat)`
    - `public mutating func recordEraser(eraserSize: CGFloat)`
  - `enum BonePaperToolStore`
    - `static var brushSize: CGFloat { get set }`
    - `static var eraserSize: CGFloat { get set }`
    - `static var opacity: CGFloat { get set }`
    - `static var color: Color { get set }`
    - `static var fallbackConfig: BonePaperDrawingConfig { get set }`

- [ ] **Step 1: Add `BonePaperDrawingConfig` and `BonePaperToolStore` to `BonePaperToolbar.swift`**

Edit `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift` right after `enum BonePaperBrush`:

```swift
public struct BonePaperDrawingConfig: Codable, Equatable, Sendable {
    public static let maxSliderMarks = 5
    public static let maxPaletteColors = 16

    public var palette: [String]
    public var brushSizes: [CGFloat]
    public var eraserSizes: [CGFloat]
    public var opacities: [CGFloat]

    public init(
        palette: [String] = [],
        brushSizes: [CGFloat] = [],
        eraserSizes: [CGFloat] = [],
        opacities: [CGFloat] = []
    ) {
        self.palette = palette
        self.brushSizes = brushSizes
        self.eraserSizes = eraserSizes
        self.opacities = opacities
    }

    public var isEmpty: Bool {
        palette.isEmpty && brushSizes.isEmpty && eraserSizes.isEmpty && opacities.isEmpty
    }

    public func sanitized() -> BonePaperDrawingConfig {
        var cleanPalette: [String] = []
        for raw in palette {
            let hex = raw.uppercased()
            guard Self.isValidHex(hex), !cleanPalette.contains(hex) else { continue }
            cleanPalette.append(hex)
            if cleanPalette.count == Self.maxPaletteColors { break }
        }
        return BonePaperDrawingConfig(
            palette: cleanPalette,
            brushSizes: Self.cleanSizes(brushSizes),
            eraserSizes: Self.cleanSizes(eraserSizes),
            opacities: Self.cleanOpacities(opacities)
        )
    }

    public mutating func recordPenOrFill(colorHex: String?, brushSize: CGFloat?, opacity: CGFloat) {
        if let rawHex = colorHex {
            let hex = rawHex.uppercased()
            if Self.isValidHex(hex) {
                palette.removeAll { $0 == hex }
                palette.insert(hex, at: 0)
                if palette.count > Self.maxPaletteColors {
                    palette.removeLast(palette.count - Self.maxPaletteColors)
                }
            }
        }
        if let brushSize {
            let sizeMark = Self.clampSize(brushSize)
            brushSizes.removeAll { $0 == sizeMark }
            brushSizes.insert(sizeMark, at: 0)
            if brushSizes.count > Self.maxSliderMarks {
                brushSizes.removeLast(brushSizes.count - Self.maxSliderMarks)
            }
        }
        let opacityMark = Self.clampOpacity(opacity)
        opacities.removeAll { $0 == opacityMark }
        opacities.insert(opacityMark, at: 0)
        if opacities.count > Self.maxSliderMarks {
            opacities.removeLast(opacities.count - Self.maxSliderMarks)
        }
    }

    public mutating func recordEraser(eraserSize: CGFloat) {
        let sizeMark = Self.clampSize(eraserSize)
        eraserSizes.removeAll { $0 == sizeMark }
        eraserSizes.insert(sizeMark, at: 0)
        if eraserSizes.count > Self.maxSliderMarks {
            eraserSizes.removeLast(eraserSizes.count - Self.maxSliderMarks)
        }
    }

    static func clampSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 14 }
        let rounded = CGFloat(Int(value.rounded()))
        return min(max(rounded, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
    }

    static func clampOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let rounded = CGFloat((value * 100).rounded()) / 100
        return min(max(rounded, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
    }

    static func isValidHex(_ hex: String) -> Bool {
        guard hex.count == 7, hex.hasPrefix("#") else { return false }
        return Int(hex.dropFirst(), radix: 16) != nil
    }

    private static func cleanSizes(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for v in values where v.isFinite {
            let clamped = clampSize(v)
            if !result.contains(clamped) {
                result.append(clamped)
                if result.count == maxSliderMarks { break }
            }
        }
        return result
    }

    private static func cleanOpacities(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for v in values where v.isFinite {
            let clamped = clampOpacity(v)
            if !result.contains(clamped) {
                result.append(clamped)
                if result.count == maxSliderMarks { break }
            }
        }
        return result
    }
}

enum BonePaperToolStore {
    private static let brushSizeKey = "bonepaper.brush_size"
    private static let eraserSizeKey = "bonepaper.eraser_size"
    private static let opacityKey = "bonepaper.opacity"
    private static let colorKey = "bonepaper.color"
    private static let fallbackConfigKey = "bonepaper.fallback_drawing_config"
    private static let clearToken = "CLEAR"

    static var brushSize: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: brushSizeKey) != nil else { return 14 }
            let val = CGFloat(UserDefaults.standard.double(forKey: brushSizeKey))
            guard val.isFinite else { return 14 }
            return min(max(val, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: brushSizeKey)
        }
    }

    static var eraserSize: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: eraserSizeKey) != nil else { return 14 }
            let val = CGFloat(UserDefaults.standard.double(forKey: eraserSizeKey))
            guard val.isFinite else { return 14 }
            return min(max(val, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.sizeRange.lowerBound), BonePaperBrush.sizeRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: eraserSizeKey)
        }
    }

    static var opacity: CGFloat {
        get {
            guard UserDefaults.standard.object(forKey: opacityKey) != nil else { return 1 }
            let val = CGFloat(UserDefaults.standard.double(forKey: opacityKey))
            guard val.isFinite else { return 1 }
            return min(max(val, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, BonePaperBrush.opacityRange.lowerBound), BonePaperBrush.opacityRange.upperBound)
            UserDefaults.standard.set(Double(clamped), forKey: opacityKey)
        }
    }

    static var color: Color {
        get {
            guard let stored = UserDefaults.standard.string(forKey: colorKey) else {
                return .black
            }
            if stored == clearToken {
                return .clear
            }
            let upper = stored.uppercased()
            guard BonePaperDrawingConfig.isValidHex(upper) else {
                return .black
            }
            return BonePaperColorStore.color(from: upper)
        }
        set {
            let uiColor = UIColor(newValue)
            if uiColor.cgColor.alpha == 0 {
                UserDefaults.standard.set(clearToken, forKey: colorKey)
            } else {
                UserDefaults.standard.set(BonePaperColorStore.hex(from: uiColor), forKey: colorKey)
            }
        }
    }

    static var fallbackConfig: BonePaperDrawingConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: fallbackConfigKey),
                  let decoded = try? JSONDecoder().decode(BonePaperDrawingConfig.self, from: data) else {
                return BonePaperDrawingConfig()
            }
            return decoded.sanitized()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.sanitized()) {
                UserDefaults.standard.set(data, forKey: fallbackConfigKey)
            }
        }
    }
}
```

- [ ] **Step 2: Check lints on `BonePaperToolbar.swift`**

Run `ReadLints` on `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`.
Expected: 0 errors, 0 warnings.

---

### Task 2: Slider Tick Marks, Magnetic Snapping, and Tap-to-Jump in `BonePaperDragControl`

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift:180-585`

**Interfaces:**
- Consumes: `BonePaperDrawingConfig`
- Produces:
  - `BonePaperStrokeControls` accepts `var brushMarks: [CGFloat]`, `var opacityMarks: [CGFloat]`, `var eraserMarks: [CGFloat]`
  - `BonePaperDragControl` accepts `var marks: [CGFloat]` and renders tick marks, snaps within 6 pt during drag, and jumps on tap within 14 pt when pinned open.

- [ ] **Step 1: Update `BonePaperStrokeControls` and `BonePaperDragControl` in `BonePaperToolbar.swift`**

In `BonePaperStrokeControls`, add `var brushMarks: [CGFloat]`, `var opacityMarks: [CGFloat]`, and `var eraserMarks: [CGFloat]` and pass them to each `BonePaperDragControl`:

```swift
                    BonePaperDragControl(
                        setting: .size,
                        value: $brushSize,
                        range: BonePaperBrush.sizeRange,
                        marks: brushMarks,
                        color: color,
                        selected: tool == .pen,
                        enabled: brushAndOpacityEnabled,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .pen },
                        onSeeking: onSeeking
                    )
                    BonePaperDragControl(
                        setting: .opacity,
                        value: $opacity,
                        range: BonePaperBrush.opacityRange,
                        marks: opacityMarks,
                        color: color,
                        selected: false,
                        enabled: brushAndOpacityEnabled,
                        activeSetting: $activeSetting,
                        onActivate: { if tool != .fill { tool = .pen } },
                        onSeeking: onSeeking
                    )
                    BonePaperDragControl(
                        setting: .eraser,
                        value: $eraserSize,
                        range: BonePaperBrush.sizeRange,
                        marks: eraserMarks,
                        color: color,
                        selected: tool == .eraser,
                        enabled: true,
                        activeSetting: $activeSetting,
                        onActivate: { tool = .eraser },
                        onSeeking: onSeeking
                    )
```

In `BonePaperDragControl`:
1. Add `var marks: [CGFloat]` property and constants:
   ```swift
   private static let snapRadius: CGFloat = 6
   private static let tapJumpRadius: CGFloat = 14
   ```
2. Update `TapGesture().onEnded` to `SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { event in handleTap(at: event.location) }`.
3. Render tick marks inside `track` right after `trackLine`:
   ```swift
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                let clamped = min(max(mark, range.lowerBound), range.upperBound)
                let markRatio = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
                let markX = Self.trackPadding + markRatio * lineWidth
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 2, height: 11)
                    .offset(x: markX - 1, y: 26)
            }
   ```
4. Update `drag.onChanged` to snap within `Self.snapRadius` (6 pt):
   ```swift
                let rawX = min(max(drag.location.x - valueStart, 0), valueWidth)
                let span = range.upperBound - range.lowerBound
                if let snapped = nearestMark(atTrackX: rawX, valueWidth: valueWidth, span: span, maxDistance: Self.snapRadius) {
                    value = snapped
                } else {
                    let t = rawX / valueWidth
                    value = range.lowerBound + t * span
                }
   ```
5. Update `handleTap(at location: CGPoint)` so tapping near a mark when `pinned` is `true` jumps to that mark without closing the bar:
   ```swift
    private func nearestMark(atTrackX rawX: CGFloat, valueWidth: CGFloat, span: CGFloat, maxDistance: CGFloat) -> CGFloat? {
        guard span > 0, valueWidth > 0 else { return nil }
        var bestMark: CGFloat?
        var bestDist = maxDistance
        for mark in marks {
            let clamped = min(max(mark, range.lowerBound), range.upperBound)
            let markX = ((clamped - range.lowerBound) / span) * valueWidth
            let dist = abs(rawX - markX)
            if dist <= bestDist {
                bestDist = dist
                bestMark = clamped
            }
        }
        return bestMark
    }

    private func handleTap(at location: CGPoint) {
        if !enabled { return }
        onActivate()
        if swallowNextTap {
            swallowNextTap = false
            return
        }
        if pinned {
            let trackLeft = Self.side + Self.trackGap
            if location.x >= trackLeft {
                let valueStart = trackLeft + Self.trackPadding
                let valueWidth = Self.trackWidth - Self.trackPadding * 2
                let rawX = min(max(location.x - valueStart, 0), valueWidth)
                let span = range.upperBound - range.lowerBound
                if let jumped = nearestMark(atTrackX: rawX, valueWidth: valueWidth, span: span, maxDistance: Self.tapJumpRadius) {
                    value = jumped
                    return
                }
            }
            pinned = false
            activeSetting = nil
        }
    }
   ```

- [ ] **Step 2: Check lints on `BonePaperToolbar.swift`**

Run `ReadLints` on `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`.
Expected: 0 errors, 0 warnings (except `BonePaperScreen` caller until Task 4).

---

### Task 3: Per-Item Palette Section in `BonePaperColorStrip`

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift:835-990`

**Interfaces:**
- Consumes: `BonePaperColorStore`
- Produces: `BonePaperColorStrip` accepts `var itemPalette: [String]` and renders `.transparent + itemPalette` rows at the top, separated by a subtle divider from deduplicated `extras + presets` rows.

- [ ] **Step 1: Update `BonePaperColorStrip` to display `itemPalette` at the top with a divider**

In `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`, update `BonePaperColorStrip`:

```swift
struct BonePaperColorStrip: View {
    @Binding var color: Color
    @Binding var hover: Color?
    var itemPalette: [String]
    var stage: BonePaperStage
    var onPick: () -> Void
    var onPickTransparent: () -> Void
```

Update swatch row computation and body inside `BonePaperColorStrip`:

```swift
            BonePaperPlainScroll {
                VStack(spacing: Self.gap) {
                    ForEach(Array(topRows.enumerated()), id: \.offset) { _, row in
                        swatchRow(row)
                    }
                    if !itemPalette.isEmpty, !bottomRows.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: Self.swatch * 2 + Self.gap, height: 1)
                            .padding(.vertical, 2)
                    }
                    ForEach(Array(bottomRows.enumerated()), id: \.offset) { _, row in
                        swatchRow(row)
                    }
                }
                .frame(maxWidth: .infinity)
            }
```

Where `topRows`, `bottomRows`, and `swatchRow` are:

```swift
    private var normalizedItemPalette: [String] {
        var result: [String] = []
        for raw in itemPalette {
            let hex = raw.uppercased()
            if BonePaperDrawingConfig.isValidHex(hex), !result.contains(hex) {
                result.append(hex)
            }
        }
        return result
    }

    private var topSwatches: [BonePaperPaletteEntry] {
        [.transparent] + normalizedItemPalette.map(BonePaperPaletteEntry.color)
    }

    private var bottomSwatches: [BonePaperPaletteEntry] {
        let used = Set(normalizedItemPalette)
        var rest: [String] = []
        for hex in extras + BonePaperColorStore.presets {
            let upper = hex.uppercased()
            if !used.contains(upper), !rest.contains(upper) {
                rest.append(upper)
            }
        }
        return rest.map(BonePaperPaletteEntry.color)
    }

    private var topRows: [[BonePaperPaletteEntry]] {
        let items = itemPalette.isEmpty ? (topSwatches + bottomSwatches) : topSwatches
        return Self.chunkRows(items)
    }

    private var bottomRows: [[BonePaperPaletteEntry]] {
        itemPalette.isEmpty ? [] : Self.chunkRows(bottomSwatches)
    }

    private static func chunkRows(_ entries: [BonePaperPaletteEntry]) -> [[BonePaperPaletteEntry]] {
        stride(from: 0, to: entries.count, by: 2).map { index in
            Array(entries[index..<min(index + 2, entries.count)])
        }
    }

    private func swatchRow(_ row: [BonePaperPaletteEntry]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(row, id: \.self) { entry in
                swatchButton(entry)
            }
            if row.count == 1 {
                Color.clear.frame(width: Self.swatch, height: Self.swatch)
            }
        }
    }
```

---

### Task 4: Hook Canvas Stroke/Fill Commits and Wire `BonePaperScreen`

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift:45-90, 425-655`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift:15-26, 405-455`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift`

**Interfaces:**
- Consumes: `BonePaperDrawingConfig`, `BonePaperToolStore`, `BonePaperStrokeControls`, `BonePaperColorStrip`
- Produces:
  - `BonePaperExport.drawingConfig: BonePaperDrawingConfig`
  - `BonePaperScreen.init` accepts `initialDrawingConfig: BonePaperDrawingConfig? = nil`
  - `BonePaperCanvas` / `BonePaperDrawView` invokes `onCommitStroke: () -> Void` when a pen/eraser stroke, dot, or fill commits.

- [ ] **Step 1: Add `drawingConfig` to `BonePaperExport` in `BonePaperDocument.swift`**

In `Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift`:
```swift
public struct BonePaperExport {
    public let image: CGImage
    /// Full-resolution (`sample` times document) paint buffer for lossless reopen, when the session started from one.
    /// Nil for sheet exports, where `image` already is the buffer.
    public let buffer: CGImage?
    public let extraLeft: CGFloat
    public let extraTop: CGFloat
    public var drawingConfig: BonePaperDrawingConfig
}
```
And initialize `drawingConfig: BonePaperDrawingConfig()` in `export()` and `exportBuffer()`.

- [ ] **Step 2: Add `onCommitStroke` callback to `BonePaperDrawView` and `BonePaperCanvas` in `BonePaperCanvas.swift`**

In `BonePaperCanvas.swift`:
1. Add `var onCommitStroke: () -> Void` to `BonePaperCanvas` and pass `view.paper.onCommitStroke = onCommitStroke` in `apply(_ view:)`.
2. In `BonePaperDrawView`, add `var onCommitStroke: (() -> Void)?`:
   - In `touchesEnded`: if `!stroking`, `tool == .pen || tool == .eraser`, and `let point = lastWorld`, support single-tap dot stamping (if `tool == .eraser` or `color.cgColor.alpha > 0`):
     - Wait: check how `BonePaperDrawView` currently handles `touchesEnded`:
       Currently `finishStroke()` checks `if tool == .fill { ... } else if stroking { document?.endStroke() }`.
       When `tool == .fill` and `let point = lastWorld`: after `document?.fillWorld(at: point, fill: fill)`, call `onCommitStroke?()`.
       When `stroking` is `true` in `finishStroke()`: after `document?.endStroke()`, call `onCommitStroke?()`.
       Note: `abortStroke()` is called on 2-finger pinch or `touchesCancelled` and sets `stroking = false` without calling `finishStroke()`, so cancelled strokes never trigger `onCommitStroke`.

- [ ] **Step 3: Wire `BonePaperToolStore` and `BonePaperDrawingConfig` in `BonePaperScreen.swift`**

In `Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift`:
1. Initialize `@State private var color: Color`, `@State private var brushSize: CGFloat`, `@State private var eraserSize: CGFloat`, `@State private var opacity: CGFloat`, `@State private var tool: BonePaperTool`, and `@State private var drawingConfig: BonePaperDrawingConfig` from `BonePaperToolStore` and `initialDrawingConfig ?? BonePaperToolStore.fallbackConfig`:
   - Add `initialDrawingConfig: BonePaperDrawingConfig? = nil` parameter to `BonePaperScreen.init(source:boneStart:boneTip:onion:placement:buffer:initialDrawingConfig:onApply:onClose:)`.
   - Restore `brushSize = BonePaperToolStore.brushSize`, `eraserSize = BonePaperToolStore.eraserSize`, `opacity = BonePaperToolStore.opacity`, `color = BonePaperToolStore.color`, and `tool = UIColor(restoredColor).cgColor.alpha == 0 ? .fill : .pen`.
2. Add `.onChange` handlers on `brushSize`, `eraserSize`, `opacity`, and `color` in `BonePaperScreen.body` to persist changes to `BonePaperToolStore`.
3. Pass `onCommitStroke: recordCommittedStroke` to `BonePaperCanvas`:
   ```swift
    private func recordCommittedStroke() {
        switch tool {
        case .pen:
            let uiColor = UIColor(color)
            guard uiColor.cgColor.alpha > 0 else { return }
            let hex = BonePaperColorStore.hex(from: uiColor)
            drawingConfig.recordPenOrFill(colorHex: hex, brushSize: brushSize, opacity: opacity)
            BonePaperColorStore.remember(hex)
        case .fill:
            let uiColor = UIColor(color)
            let hex = uiColor.cgColor.alpha > 0 ? BonePaperColorStore.hex(from: uiColor) : nil
            drawingConfig.recordPenOrFill(colorHex: hex, brushSize: nil, opacity: opacity)
            if let hex {
                BonePaperColorStore.remember(hex)
            }
        case .eraser:
            drawingConfig.recordEraser(eraserSize: eraserSize)
        case .pan:
            break
        }
        BonePaperToolStore.fallbackConfig = drawingConfig
    }
   ```
4. Pass `itemPalette: drawingConfig.palette` to `BonePaperColorStrip`, and `brushMarks: drawingConfig.brushSizes`, `opacityMarks: drawingConfig.opacities`, `eraserMarks: drawingConfig.eraserSizes` to `BonePaperStrokeControls`.
5. In `apply()`, set `export.drawingConfig = drawingConfig` before calling `onApply(export)`.

- [ ] **Step 4: Check lints on `BonePaper` files**

Run `ReadLints` on `BonePaperToolbar.swift`, `BonePaperDocument.swift`, `BonePaperCanvas.swift`, and `BonePaperScreen.swift`.
Expected: 0 errors, 0 warnings.

---

### Task 5: Persist Per-Item `BonePaperDrawingConfig` in `UnitAssets` (`bonepaper.json`) and Wire `SkeletonScreen`

**Files:**
- Modify: `Shared/Model/UnitAssets.swift:60-88, 1090-1180, 1260-1280`
- Modify: `at_elements/Screens/SkeletonScreen.swift:230-252, 325-336, 475-545`

**Interfaces:**
- Consumes: `BonePaperDrawingConfig`, `BonePaperExport.drawingConfig`, `BonePaperScreen.init(..., initialDrawingConfig:)`
- Produces:
  - `UnitAssets.drawingConfig(for unitName: String) -> BonePaperDrawingConfig`
  - `UnitAssets.setDrawingConfig(_ config: BonePaperDrawingConfig, for unitName: String)`
  - `BonePaperManifest.drawingConfig: BonePaperDrawingConfig?` persisted in `bonepaper.json`

- [ ] **Step 1: Extend `BonePaperManifest` and `UnitAssets` in `Shared/Model/UnitAssets.swift`**

1. Add `private var drawingConfigs: [String: BonePaperDrawingConfig] = [:]` to `UnitAssets`.
2. Add `var drawingConfigs: [String: BonePaperDrawingConfig]` to `UnitAssets.Snapshot`, `snapshot()`, and `restore(_:)`.
3. Add accessors on `UnitAssets`:
   ```swift
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
   ```
4. Update `BonePaperManifest`:
   ```swift
   struct BonePaperManifest: Codable {
       struct Entry: Codable {
           var entry: String
           var sha256: String
       }

       var version: Int
       var buffers: [String: Entry]
       var drawingConfig: BonePaperDrawingConfig?
   ```
5. In `sidecarFiles(unitName:pngs:)`:
   ```swift
        let config = drawingConfigs[name]?.sanitized()
        let nonEmptyConfig = (config?.isEmpty == false) ? config : nil
        var manifest = BonePaperManifest(version: 1, buffers: [:], drawingConfig: nonEmptyConfig)
        // ... loop over edgeAssets ...
        guard !files.isEmpty || nonEmptyConfig != nil else { return [] }
        files.append((name: Self.sidecarManifest, data: try manifest.encode()))
        return files.sorted { $0.name < $1.name }
   ```
6. In `install(_:zip:)`, pass `unitName: assets[0].unitName` to `attachSidecars(zip: zip, unitName: assets[0].unitName)`:
   In `attachSidecars(zip: Data, unitName: String)`:
   ```swift
        let unitKey = Self.removeNumber(unitName)
        if let config = manifest.drawingConfig?.sanitized(), !config.isEmpty {
            drawingConfigs[unitKey] = config
        }
   ```

- [ ] **Step 2: Wire `drawingConfig` in `SkeletonScreen.swift`**

1. Add `let drawingConfig: BonePaperDrawingConfig` to `BonePaperEdit` in `at_elements/Screens/SkeletonScreen.swift`.
2. In `presentBonePaper`:
   ```swift
        let config = (optionalUnit.flatMap { assets?.drawingConfig(for: $0.name) }) ?? BonePaperDrawingConfig()
        let edit = BonePaperEdit(
            source: asset.bitmap,
            buffer: validatedBuffer(asset: asset),
            boneStart: start,
            boneTip: tip,
            onion: onion,
            placement: placement,
            bmName: asset.bmName,
            drawingConfig: config
        )
   ```
3. In `.fullScreenCover(item: $bonePaperEdit)`: pass `initialDrawingConfig: session.drawingConfig` to `BonePaperScreen`.
4. In `applyBonePaper(bmName: String, export: BonePaperExport)`:
   ```swift
        if let unit = optionalUnit {
            assets.setDrawingConfig(export.drawingConfig, for: unit.name)
        }
   ```

- [ ] **Step 3: Check lints across all modified files**

Run `ReadLints` on `Shared/Model/UnitAssets.swift` and `at_elements/Screens/SkeletonScreen.swift`.
Expected: 0 errors, 0 warnings.
