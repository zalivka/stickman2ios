# BonePaper Transparent Fill Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selecting BonePaper's transparent swatch immediately activates fill and visibly disables the brush-size and opacity controls until an opaque color is selected.

**Architecture:** Keep transparent selection explicit at the vertical palette boundary by adding a dedicated callback that selects fill in `BonePaperScreen`. Let `BonePaperStrokeControls` derive availability from its existing `color` input and pass an `enabled` state into only the brush and opacity drag controls; eraser and other controls remain independent.

**Tech Stack:** Swift, SwiftUI, UIKit, BonePaper.

## Global Constraints

- Change only the vertical BonePaper drawing UI.
- Transparent selection activates fill immediately.
- Brush-size and opacity controls are disabled, dimmed to 35%, and close any open slider while transparent is selected.
- Eraser, fill, undo, and redo remain enabled.
- Selecting an opaque palette color restores brush and opacity and retains the existing pen-selection behavior.
- Keep the document's transparent-pen no-op guard.
- Do not add tests or build the iOS app unless explicitly requested.

---

### Task 1: Transparent selection and control availability

**Files:**
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift:179-255,347-556,810-958`
- Modify: `Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift:167-200`

**Interfaces:**
- Consumes: the existing `BonePaperColorStrip` transparent palette entry and `BonePaperStrokeControls.color`.
- Produces: `BonePaperColorStrip.onPickTransparent: () -> Void`.
- Produces: `BonePaperDragControl.enabled: Bool`.

- [ ] **Step 1: Route transparent selection separately**

Add a second callback to `BonePaperColorStrip`:

```swift
var onPick: () -> Void
var onPickTransparent: () -> Void
```

In the transparent tap branch, call it immediately after setting the color:

```swift
case .transparent:
    color = .clear
    onPickTransparent()
case .color(let hex):
    color = BonePaperColorStore.color(from: hex)
    onPick()
```

Keep opaque selection on `onPick()` so it continues to select the pen.

- [ ] **Step 2: Select fill from the screen**

Replace the trailing-closure `BonePaperColorStrip` construction with explicit callbacks:

```swift
BonePaperColorStrip(
    color: $color,
    hover: $hoverColor,
    stage: stage,
    onPick: {
        if tool != .fill {
            tool = .pen
        }
    },
    onPickTransparent: {
        tool = .fill
    }
)
```

This changes the tool only for a deliberate vertical-palette selection; unrelated color updates remain unaffected.

- [ ] **Step 3: Derive brush and opacity availability**

In `BonePaperStrokeControls`, derive one value from the existing color:

```swift
private var brushAndOpacityEnabled: Bool {
    UIColor(color).cgColor.alpha > 0
}
```

Pass it to the brush-size and opacity controls, and keep eraser enabled:

```swift
BonePaperDragControl(
    setting: .size,
    value: $brushSize,
    range: BonePaperBrush.sizeRange,
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
    color: color,
    selected: tool == .eraser,
    enabled: true,
    activeSetting: $activeSetting,
    onActivate: { tool = .eraser },
    onSeeking: onSeeking
)
```

- [ ] **Step 4: Make disabled drag controls inert and dimmed**

Add the stored input:

```swift
var enabled: Bool
```

Prevent disabled controls from displaying an active slider:

```swift
private var isActive: Bool {
    enabled && (pinned || activeSetting == setting)
}
```

At the end of the drag control body, add disabled semantics and the required visual state:

```swift
.opacity(enabled ? 1 : 0.35)
.disabled(!enabled)
.animation(.easeOut(duration: 0.12), value: enabled)
```

Close an open or pinned slider as soon as the control becomes disabled:

```swift
.onChange(of: enabled) { _, next in
    if !next {
        dragStartValue = nil
        pinned = false
        swallowNextTap = false
        if activeSetting == setting {
            activeSetting = nil
            onSeeking(false)
        }
    }
}
```

Guard all custom gesture paths because the control uses explicit gestures:

```swift
private var drag: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
        .onChanged { drag in
            if !enabled { return }
            if dragStartValue == nil {
                dragStartValue = value
                onActivate()
                onSeeking(true)
            }
            activeSetting = setting
            guard let start = dragStartValue else {
                fatalError("BonePaper drag started without a value")
            }
            let valueStart = Self.side + Self.trackGap + Self.trackPadding
            let valueWidth = Self.trackWidth - Self.trackPadding * 2
            if valueWidth <= 0 {
                fatalError("BonePaper slider track width is \(valueWidth)")
            }
            if drag.location.x < valueStart {
                value = start
                return
            }
            let t = min(max((drag.location.x - valueStart) / valueWidth, 0), 1)
            let span = range.upperBound - range.lowerBound
            value = range.lowerBound + t * span
        }
        .onEnded { _ in
            if !enabled { return }
            dragStartValue = nil
            onSeeking(false)
            if !pinned {
                activeSetting = nil
            }
        }
}

private func pinSeekBar() {
    if !enabled { return }
    pinned = true
    activeSetting = setting
    swallowNextTap = true
    onActivate()
}

private func handleTap() {
    if !enabled { return }
    onActivate()
    if swallowNextTap {
        swallowNextTap = false
        return
    }
    if pinned {
        pinned = false
        activeSetting = nil
    }
}
```

Do not disable the containing stroke-control stack, because eraser, fill, undo, and redo must stay interactive.

- [ ] **Step 5: Verify statically and commit**

Run only static checks:

```bash
git diff --check -- \
  Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift
rg "onPickTransparent|brushAndOpacityEnabled|enabled:" \
  Vendor/BonePaper/Sources/BonePaper
```

Expected:

- transparent invokes `onPickTransparent`, which selects fill;
- opaque colors retain `onPick`, which selects pen;
- size and opacity receive the derived enabled state;
- eraser receives `enabled: true`;
- no whitespace errors.

Use IDE diagnostics on both edited files. Do not build or run tests.

Commit only the implementation files:

```bash
git add Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift \
  Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift
git commit -m "Lock BonePaper controls for transparent fill"
```
