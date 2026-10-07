# BonePaper Transparent Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fixed transparent swatch at the start of BonePaper's vertical palette that clears connected regions with the fill tool and is inert with the pen.

**Architecture:** Represent fill intent explicitly as either colored paint or clearing instead of encoding transparency in `#RRGGBB` or overloading zero-alpha paint. Carry that intent through document mutation, recording, and replay. Keep the transparent palette entry local to the vertical strip so custom-color persistence and the horizontal row remain RGB-only.

**Tech Stack:** Swift, SwiftUI, UIKit, Core Graphics, BonePaper's flood-fill engine and JSON session recorder.

## Global Constraints

- Change only the vertical `BonePaperColorStrip`; leave `BonePaperColorRow` unchanged.
- The transparent swatch is fixed before custom and preset colors.
- Selecting transparent leaves the current tool unchanged.
- Transparent fill clears the tapped connected painted region and supports undo, redo, recording, and replay.
- Transparent pen input is a no-op with no empty undo entry.
- Existing eraser and RGB color behavior remain unchanged.
- Do not add tests or build the iOS app unless explicitly requested.

---

### Task 1: Explicit clear-fill document operation

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift:90-96,240-325,677-689,900-942`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperRecorder.swift:9-25,172-187`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperPlayer.swift:145-175,306-340,445-480,518-527`

**Interfaces:**
- Produces: `enum BonePaperFill { case color(UIColor, opacity: CGFloat); case clear }`
- Produces: `BonePaperDocument.fillWorld(at: CGPoint, fill: BonePaperFill)`
- Produces: `BonePaperRecorder.fill(at: CGPoint, fill: BonePaperFill)`
- Recording JSON adds optional `clear: true`; recordings without it continue decoding as colored fills.

- [ ] **Step 1: Add the explicit fill intent and internal comparable operation**

In `BonePaperDocument.swift`, define the cross-file input near the document type:

```swift
enum BonePaperFill {
    case color(UIColor, opacity: CGFloat)
    case clear
}
```

Replace `lastFillPaint` with a comparable operation:

```swift
private enum FillOperation: Equatable {
    case color(FillPaint)
    case clear
}

private var lastFillOperation: FillOperation?
```

Reset `lastFillOperation` in the same stroke, undo, and redo locations that currently reset `lastFillPaint`.

- [ ] **Step 2: Replace the fill API with color/clear branching**

Change the document entry point to:

```swift
func fillWorld(at world: CGPoint, fill: BonePaperFill) {
```

After validating the point and pixel buffer, derive the operation:

```swift
let operation: FillOperation
switch fill {
case .color(let color, let opacity):
    operation = .color(Self.fillPaint(color: color, opacity: opacity))
case .clear:
    operation = .clear
}
```

Use `lastFillOperation` to preserve same-operation streak loosening. Determine whether the seed is painted from its alpha. For `.clear`, return before recording or `pushUndo()` when the seed is already transparent:

```swift
let seedPainted = pixels[py * stride + px * 4 + 3] >= Self.fillRecolorAlpha
if operation == .clear, !seedPainted {
    return
}
```

Record only after that no-op guard:

```swift
recorder.fill(at: world, fill: fill)
```

Generate the flood mask with `recolor: seedPainted`. In the asynchronous mutation, switch on the operation:

```swift
switch operation {
case .clear:
    Self.clearRegion(pixels: pixels, mask: mask, width: width, stride: stride)
case .color(let paint):
    if seedPainted {
        BonePaperRecolor.apply(
            pixels: pixels,
            mask: mask,
            width: width,
            height: height,
            stride: stride,
            seed: py * width + px,
            paint: paint
        )
    } else {
        if BonePaperFlags.antialiasing {
            Self.growRing(pixels: pixels, mask: &mask, width: width, height: height, stride: stride)
        }
        Self.paintBehind(pixels: pixels, mask: mask, width: width, stride: stride, paint: paint)
    }
}
```

Add a focused helper beside `paintBehind`:

```swift
private static func clearRegion(
    pixels: UnsafeMutablePointer<UInt8>,
    mask: [UInt8],
    width: Int,
    stride: Int
) {
    for m in mask.indices where mask[m] == 1 {
        let i = (m / width) * stride + (m % width) * 4
        pixels[i] = 0
        pixels[i + 1] = 0
        pixels[i + 2] = 0
        pixels[i + 3] = 0
    }
}
```

Keep the existing undo push, redo clearing, fill queue, preview publishing, and stack publishing around this switch.

- [ ] **Step 3: Record clear fills without inventing an RGBA hex format**

Add `clear` to `BonePaperRecorder.Op`:

```swift
var clear: Bool?
```

Replace the recorder fill signature and build the color fields explicitly:

```swift
func fill(at point: CGPoint, fill: BonePaperFill) {
    if open != nil {
        fatalError("BonePaperRecorder fill with an open stroke")
    }
    let color: String?
    let opacity: Double?
    let clear: Bool?
    switch fill {
    case .color(let value, let valueOpacity):
        color = BonePaperColorStore.hex(from: value)
        opacity = Self.round(valueOpacity, 1000)
        clear = nil
    case .clear:
        color = nil
        opacity = nil
        clear = true
    }
    ops.append(Op(
        op: "fill",
        t: now(),
        input: pendingInput,
        clear: clear,
        color: color,
        opacity: opacity,
        zoom: Self.round(zoom, 1000),
        at: [Self.round(point.x, 100), Self.round(point.y, 100)],
        raw: pendingRaw
    ))
    pendingRaw = []
}
```

- [ ] **Step 4: Decode and replay both old colored fills and new clear fills**

Add `var clear: Bool?` to `BonePaperSessionFile.Op`. Change `Step.fill` to carry `BonePaperFill`:

```swift
case fill(at: CGPoint, time: Double, fill: BonePaperFill)
```

Update its pattern matches in `start`, `point`, and `advance`. Replay with:

```swift
document.fillWorld(at: at, fill: fill)
```

In `timeline`, require only the point first, then decode the operation:

```swift
guard let at = op.at, at.count == 2 else {
    fatalError("BonePaperPlayer fill at \(op.t) without point")
}
let fill: BonePaperFill
if op.clear == true {
    fill = .clear
} else {
    guard let hex = op.color, let opacity = op.opacity else {
        fatalError("BonePaperPlayer fill at \(op.t) without colour or opacity")
    }
    fill = .color(UIColor(BonePaperColorStore.color(from: hex)), opacity: CGFloat(opacity))
}
steps.append(.fill(
    at: CGPoint(x: at[0] + offset.x, y: at[1] + offset.y),
    time: playedStart,
    fill: fill
))
```

This keeps existing version-1 recordings valid because `clear` is optional.

- [ ] **Step 5: Review and commit the document operation**

Run only static checks:

```bash
git diff --check -- \
  Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperRecorder.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperPlayer.swift
rg "fillWorld\\(|recorder\\.fill\\(" Vendor/BonePaper/Sources/BonePaper
```

Expected: no whitespace errors; every fill call uses `BonePaperFill`.

Commit only these files:

```bash
git add Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperRecorder.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperPlayer.swift
git commit -m "Add transparent BonePaper fill operation"
```

### Task 2: Vertical transparent swatch and inert pen behavior

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift:316-331,780-899`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift:580-605,629-641`

**Interfaces:**
- Consumes: `BonePaperFill.clear` and `BonePaperFill.color(_:opacity:)` from Task 1.
- Produces: a vertical-only `BonePaperPaletteEntry` model with `.transparent` and `.color(String)`.
- Produces: transparent pen gestures that never call `beginStroke`.

- [ ] **Step 1: Model vertical palette entries explicitly**

Near `BonePaperColorStrip`, add:

```swift
private enum BonePaperPaletteEntry: Hashable {
    case transparent
    case color(String)
}
```

Replace the vertical strip's `swatches` and `rows` only:

```swift
private var swatches: [BonePaperPaletteEntry] {
    [.transparent] + (extras + BonePaperColorStore.presets).map(BonePaperPaletteEntry.color)
}

private var rows: [[BonePaperPaletteEntry]] {
    stride(from: 0, to: swatches.count, by: 2).map { index in
        Array(swatches[index..<min(index + 2, swatches.count)])
    }
}
```

Do not alter `BonePaperColorRow.swatches`.

- [ ] **Step 2: Render and select the fixed checkerboard swatch**

Add a rounded checkerboard view:

```swift
private struct BonePaperTransparentSwatch: View {
    var body: some View {
        Canvas { context, size in
            let cell = size.width / 4
            for row in 0..<4 {
                for column in 0..<4 {
                    let rect = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    let shade = (row + column).isMultiple(of: 2)
                        ? Color(white: 0.92)
                        : Color(white: 0.62)
                    context.fill(Path(rect), with: .color(shade))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
```

Change the vertical `swatchButton` to accept `BonePaperPaletteEntry`. Derive its display, selected state, accessibility label, tap, and long-press behavior with a switch:

```swift
let isTransparent = UIColor(color).cgColor.alpha == 0
let selected: Bool
switch entry {
case .transparent:
    selected = isTransparent
case .color(let hex):
    selected = !isTransparent && BonePaperColorStore.hex(from: UIColor(color)) == hex
}
```

Use `BonePaperTransparentSwatch()` for `.transparent` and the existing filled rounded rectangle for `.color(hex)`. Preserve the border and selected-dot overlays for both.

On tap:

```swift
switch entry {
case .transparent:
    color = .clear
case .color(let hex):
    color = BonePaperColorStore.color(from: hex)
    onPick()
}
```

Not calling `onPick()` for transparent is deliberate: the screen's callback switches non-fill tools to pen, while transparent must leave the current tool unchanged. Long press shows `"Transparent"` for the sentinel and the existing hex toast for RGB colors. Set the accessibility label to `"Transparent"` or the hex respectively.

- [ ] **Step 3: Route fill taps and suppress transparent pen strokes**

In `BonePaperCanvas.swift`, guard before `beginStroke` in `touchesMoved`:

```swift
if tool == .pen, color.cgColor.alpha == 0 {
    return
}
```

This leaves the gesture unopened, so `touchUp()` records only its existing `"noop"` touch entry and no document undo snapshot is created. Do not apply this guard to `.eraser`.

In `finishStroke`, replace the fill call:

```swift
if tool == .fill {
    if let point = lastWorld {
        let fill: BonePaperFill = color.cgColor.alpha == 0
            ? .clear
            : .color(color, opacity: opacity)
        document?.fillWorld(at: point, fill: fill)
    }
} else if stroking {
    document?.endStroke()
}
```

- [ ] **Step 4: Review and commit the palette integration**

Run only static checks:

```bash
git diff --check -- \
  Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift
rg "private var swatches|BonePaperPaletteEntry|BonePaperFill" \
  Vendor/BonePaper/Sources/BonePaper
```

Expected: the vertical strip contains the transparent entry; the horizontal row still returns `extras + BonePaperColorStore.presets`; no whitespace errors.

Commit only these files:

```bash
git add Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift
git commit -m "Add transparent swatch to BonePaper palette"
```

### Task 3: Final static verification

**Files:**
- Review: all five implementation files from Tasks 1 and 2.

**Interfaces:**
- Consumes: the completed document, recording, replay, palette, and canvas changes.
- Produces: no new code unless review finds a defect.

- [ ] **Step 1: Confirm scope and compatibility**

Run:

```bash
git diff HEAD~2 -- \
  Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperRecorder.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperPlayer.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift
```

Review that:

- transparent is first only in `BonePaperColorStrip`;
- `BonePaperColorStore` remains `#RRGGBB`;
- clear fill returns on a clear seed before recording or undo;
- a painted seed is flood-selected and cleared;
- clear recordings replay as clear while old colored recordings still decode;
- transparent pen never begins a stroke;
- eraser still reaches the existing clear-blend stroke path.

- [ ] **Step 2: Check repository hygiene without building**

Run:

```bash
git diff --check HEAD~2..HEAD
git status --short
```

Expected: no whitespace errors. Existing unrelated working-tree changes remain untouched. Do not run Xcode, Swift compilation, or tests.
