# BonePaper Brush Offset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a screen-space vertical brush offset (`0...70 pt` in `10 pt` steps) with a live target cursor on the BonePaper canvas and a `"Drawing tools"` settings section in `AppSettingsSheet`.

**Architecture:** `BonePaperFlags.brushOffset` stores the upward screen-point offset (`CGFloat`), persisted by `AppSettings.brushOffset` in `UserDefaults` (`"paperDrawBrushOffset"`) and configured via a slider card under `"Drawing tools"` in `AppSettingsSheet`. `BonePaperDrawView` and `BonePaperStageView.sampleColor(atWindow:)` shift touch/window coordinates upward by `BonePaperFlags.brushOffset` in stage/window space before converting to `paper`/world coordinates, while `BonePaperStageView` renders a dual-contrast ring + crosshair `CAShapeLayer` cursor at the offset target point during active touches.

**Tech Stack:** Swift 5.9+, SwiftUI, UIKit (`CAShapeLayer`, `UIView`), `BonePaper` local Swift package.

## Global Constraints

- **Do NOT build iOS or Android** after editing code unless the user orders it directly.
- **Do NOT write unit tests** unless explicitly asked by the user.
- **iOS only**: all changes are in `/Users/zalivka/wsios/elements/at_elements`.
- Prefer loud failure (`fatalError`) over silent fallback where invariants are violated, matching existing `BonePaper` style.

---

### Task 1: Add `BonePaperFlags.brushOffset` and `AppSettings.brushOffset` Persistence

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/AppSettings.swift`

**Interfaces:**
- Produces:
  - `BonePaperFlags.brushOffset: CGFloat` (default `0`)
  - `AppSettings.maxBrushOffset: Int = 70`
  - `AppSettings.brushOffsetStep: Int = 10`
  - `AppSettings.brushOffset: Int` (`0...70`, rounded to nearest step of `10`, synced to `BonePaperFlags.brushOffset`)

- [ ] **Step 1: Add `brushOffset` to `BonePaperFlags.swift`**

Update `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift` so it reads:

```swift
import CoreGraphics

/// Drawing switches shared by the live canvas and `BonePaperBench`.
/// Defaults match the baseline; the bench flips one flag at a time to measure it.
public enum BonePaperFlags {
    public static var antialiasing = true
    public static var fillStreakLoosening = false
    /// Upward screen-space offset (in points) applied to finger/touch input on the canvas.
    public static var brushOffset: CGFloat = 0
}
```

- [ ] **Step 2: Add `brushOffset` persistence and clamping to `AppSettings.swift`**

Update `/Users/zalivka/wsios/elements/at_elements/Shared/Model/AppSettings.swift` so it reads:

```swift
import BonePaper
import CoreGraphics
import Foundation

/// Persisted app settings. `boot` copies them into BonePaper before any drawing.
enum AppSettings {
    private static let paperDrawAntialiasingKey = "paperDrawAntialiasing"
    private static let brushOffsetKey = "paperDrawBrushOffset"

    static let maxBrushOffset = 70
    static let brushOffsetStep = 10

    /// Paper Draw brush and eraser antialiasing. A missing key stays on, matching BonePaper's own default.
    static var paperDrawAntialiasing: Bool {
        get {
            guard UserDefaults.standard.object(forKey: paperDrawAntialiasingKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: paperDrawAntialiasingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: paperDrawAntialiasingKey)
            BonePaperFlags.antialiasing = newValue
        }
    }

    /// Upward screen-space brush offset in points (`0...70`, step `10`). Defaults to `0`.
    static var brushOffset: Int {
        get {
            guard UserDefaults.standard.object(forKey: brushOffsetKey) != nil else {
                return 0
            }
            return clampBrushOffset(UserDefaults.standard.integer(forKey: brushOffsetKey))
        }
        set {
            let clamped = clampBrushOffset(newValue)
            UserDefaults.standard.set(clamped, forKey: brushOffsetKey)
            BonePaperFlags.brushOffset = CGFloat(clamped)
        }
    }

    static func clampBrushOffset(_ raw: Int) -> Int {
        let clamped = min(max(raw, 0), maxBrushOffset)
        let rounded = Int((Double(clamped) / Double(brushOffsetStep)).rounded()) * brushOffsetStep
        return min(max(rounded, 0), maxBrushOffset)
    }

    static func boot() {
        BonePaperFlags.antialiasing = paperDrawAntialiasing
        BonePaperFlags.brushOffset = CGFloat(brushOffset)
    }
}
```

- [ ] **Step 3: Commit Task 1**

```bash
git -C /Users/zalivka/wsios/elements/at_elements add Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift Shared/Model/AppSettings.swift
git -C /Users/zalivka/wsios/elements/at_elements commit -m "Add brushOffset to BonePaperFlags and AppSettings"
```

---

### Task 2: Add "Drawing tools" Section with Brush Offset Slider to `AppSettingsSheet`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/AppSettingsSheet.swift`

**Interfaces:**
- Consumes:
  - `AppSettings.brushOffset: Int`
  - `AppSettings.maxBrushOffset: Int`
  - `AppSettings.brushOffsetStep: Int`
  - `AppSettings.clampBrushOffset(_: Int) -> Int`

- [ ] **Step 1: Update `AppSettingsSheet.swift` with `@State private var brushOffset` and the `"Drawing tools"` section**

Modify `/Users/zalivka/wsios/elements/at_elements/Shared/UI/AppSettingsSheet.swift`:

1. Add `@State private var brushOffset: Double` alongside `@State private var antialiasing: Bool`, and initialize it in `init`:
```swift
    @Environment(\.dismiss) private var dismiss
    @State private var antialiasing: Bool
    @State private var brushOffset: Double
    /// When set, a DEBUG-only Tutorial button discards the current scene and
    /// replays the intro. Nil (e.g. item editor) hides the button entirely.
    let onTutorial: (() -> Void)?

    init(onTutorial: (() -> Void)? = nil) {
        _antialiasing = State(initialValue: AppSettings.paperDrawAntialiasing)
        _brushOffset = State(initialValue: Double(AppSettings.brushOffset))
        self.onTutorial = onTutorial
    }
```

2. Update `applyButton` (and `tutorialCard` in `#if DEBUG`) to save `AppSettings.brushOffset = Int(brushOffset.rounded())`:
```swift
    private var applyButton: some View {
        Button {
            AppSettings.paperDrawAntialiasing = antialiasing
            AppSettings.brushOffset = Int(brushOffset.rounded())
            dismiss()
        } label: {
            Text("Apply")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 72)
                .padding(.vertical, 8)
                .background(Self.applyGreen)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply")
    }
```

3. In `formBody`, add the `"Drawing tools"` section header and `brushOffsetCard` right below `antialiasingCard`:
```swift
    private var formBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paper draw")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                antialiasingCard
                Text("Drawing tools")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                brushOffsetCard
                #if DEBUG
                if onTutorial != nil {
                    tutorialCard
                }
                #endif
                privacyCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
```

4. Add `brushOffsetCard` implementation right after `antialiasingCard`:
```swift
    private var brushOffsetCard: some View {
        let currentOffset = AppSettings.clampBrushOffset(Int(brushOffset.rounded()))
        let isActive = currentOffset > 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(isActive ? SkeletonChrome.bonesAccent : Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Brush offset")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Shift drawing point above finger")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Text("\(currentOffset) / \(AppSettings.maxBrushOffset)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Slider(
                value: $brushOffset,
                in: 0...Double(AppSettings.maxBrushOffset),
                step: Double(AppSettings.brushOffsetStep)
            )
            .tint(SkeletonChrome.bonesAccent)
            .accessibilityLabel("Brush offset")
            .accessibilityValue("\(currentOffset) points")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        )
    }
```

5. Also update `presentationDetents` on `AppSettingsSheet.body` from `[.medium]` to `[.medium, .large]` so small iPhone screens in landscape or compact heights can comfortably view all cards without cramping.

- [ ] **Step 2: Commit Task 2**

```bash
git -C /Users/zalivka/wsios/elements/at_elements add Shared/UI/AppSettingsSheet.swift
git -C /Users/zalivka/wsios/elements/at_elements commit -m "Add Drawing tools Brush offset slider to AppSettingsSheet"
```

---

### Task 3: Apply Screen-Space Offset and Live Target Cursor in `BonePaperCanvas` & `BonePaperToolbar`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`

**Interfaces:**
- Consumes: `BonePaperFlags.brushOffset: CGFloat`
- Produces:
  - `BonePaperStage.clearCursor()`
  - `BonePaperStageView.updateOffsetCursor(atStage: CGPoint, tool: BonePaperTool, brushSize: CGFloat)`
  - `BonePaperStageView.hideOffsetCursor()`

- [ ] **Step 1: Add cursor layer and offset coordinate handling to `BonePaperStage` and `BonePaperStageView`**

In `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift`:

1. In `BonePaperStage`, add `clearCursor()`:
```swift
    func clearCursor() {
        view?.hideOffsetCursor()
    }
```

2. In `BonePaperStageView`, add two `CAShapeLayer` properties (`cursorHaloLayer` and `cursorStrokeLayer`) for the dual-contrast target cursor:
```swift
    private let cursorHaloLayer = CAShapeLayer()
    private let cursorStrokeLayer = CAShapeLayer()
```

3. In `BonePaperStageView.init(placement:)`, configure and add `cursorHaloLayer` and `cursorStrokeLayer` to `layer` right after `addSubview(paper)`, and link `paper.stageView = self`:
```swift
        addSubview(backdrop)
        addSubview(paper)
        paper.stageView = self

        cursorHaloLayer.fillColor = nil
        cursorHaloLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        cursorHaloLayer.lineWidth = 3
        cursorHaloLayer.lineCap = .round
        cursorHaloLayer.isHidden = true
        layer.addSublayer(cursorHaloLayer)

        cursorStrokeLayer.fillColor = nil
        cursorStrokeLayer.strokeColor = UIColor.black.withAlphaComponent(0.88).cgColor
        cursorStrokeLayer.lineWidth = 1.5
        cursorStrokeLayer.lineCap = .round
        cursorStrokeLayer.isHidden = true
        layer.addSublayer(cursorStrokeLayer)
```

4. In `BonePaperStageView`, add `updateOffsetCursor(atStage:tool:brushSize:)` and `hideOffsetCursor()`:
```swift
    func updateOffsetCursor(atStage targetStage: CGPoint, tool: BonePaperTool, brushSize: CGFloat) {
        guard BonePaperFlags.brushOffset > 0 else {
            hideOffsetCursor()
            return
        }
        let path = CGMutablePath()
        switch tool {
        case .pen, .eraser:
            let radius = max((brushSize * zoom) / 2, 4)
            path.addEllipse(in: CGRect(
                x: targetStage.x - radius,
                y: targetStage.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            let cross: CGFloat = 5
            path.move(to: CGPoint(x: targetStage.x - cross, y: targetStage.y))
            path.addLine(to: CGPoint(x: targetStage.x + cross, y: targetStage.y))
            path.move(to: CGPoint(x: targetStage.x, y: targetStage.y - cross))
            path.addLine(to: CGPoint(x: targetStage.x, y: targetStage.y + cross))
        case .fill, .pan:
            let radius: CGFloat = 6
            let cross: CGFloat = 9
            path.addEllipse(in: CGRect(
                x: targetStage.x - radius,
                y: targetStage.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            path.move(to: CGPoint(x: targetStage.x - cross, y: targetStage.y))
            path.addLine(to: CGPoint(x: targetStage.x + cross, y: targetStage.y))
            path.move(to: CGPoint(x: targetStage.x, y: targetStage.y - cross))
            path.addLine(to: CGPoint(x: targetStage.x, y: targetStage.y + cross))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorHaloLayer.path = path
        cursorStrokeLayer.path = path
        cursorHaloLayer.isHidden = false
        cursorStrokeLayer.isHidden = false
        CATransaction.commit()
    }

    func hideOffsetCursor() {
        if cursorHaloLayer.isHidden && cursorStrokeLayer.isHidden {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorHaloLayer.isHidden = true
        cursorStrokeLayer.isHidden = true
        CATransaction.commit()
    }
```

5. Update `BonePaperStageView.sampleColor(atWindow:)` to shift the stage point upward by `BonePaperFlags.brushOffset` and update the live cursor during pipette drag:
```swift
    /// Window point → paint-buffer pixel, through the same transform that draws the paper.
    /// A point outside the picture is black. A clear pixel is nil.
    func sampleColor(atWindow point: CGPoint) -> UIColor? {
        guard let document = paper.document else {
            return nil
        }
        let side = paper.bounds.width
        if side <= 0 {
            return nil
        }
        let rawStage = convert(point, from: nil)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - BonePaperFlags.brushOffset)
        updateOffsetCursor(atStage: targetStage, tool: .fill, brushSize: paper.brushSize)
        let local = paper.convert(targetStage, from: self)
        let world = CGFloat(document.worldSize)
        let at = CGPoint(x: local.x / side * world, y: local.y / side * world)
        let scale = CGFloat(BonePaperDocument.sample)
        let px = Int(floor((at.x - CGFloat(document.originX)) * scale))
        let py = Int(floor((at.y - CGFloat(document.originY)) * scale))
        if px < 0 || py < 0 || px >= document.pixelWidth || py >= document.pixelHeight {
            return .black
        }
        return document.color(atPixel: px, y: py)
    }
```

- [ ] **Step 2: Apply screen-space upward offset and cursor updates in `BonePaperDrawView`**

In `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift`:

1. Add `weak var stageView: BonePaperStageView?` to `BonePaperDrawView`:
```swift
    weak var stageView: BonePaperStageView?
    var document: BonePaperDocument?
```

2. Update `touchesBegan`, `touchesMoved`, `touchesEnded`, `abortStroke`, `finishStroke`, and `worldPoint` in `BonePaperDrawView`:
```swift
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if document?.filling == true { return }
        if tool == .pan { return }
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first else { return }
        updateStageCursor(for: touch)
        document?.recorder.touchDown(samples(touch, event), input: touch.type)
        lastWorld = worldPoint(touch)
        if tool == .fill {
            return
        }
        pendingView = touch.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if document?.filling == true { return }
        if event?.allTouches?.count != 1 {
            abortStroke()
            return
        }
        guard let touch = touches.first, let document else { return }
        updateStageCursor(for: touch)
        document.recorder.touchMoved(samples(touch, event))
        let point = worldPoint(touch)
        if tool == .fill {
            lastWorld = point
            return
        }
        let view = touch.location(in: self)
        if !stroking {
            guard let startView = pendingView, let startWorld = lastWorld else { return }
            let dx = view.x - startView.x
            let dy = view.y - startView.y
            let slop = Self.strokeSlop / max(zoomScale, 1)
            if hypot(dx, dy) < slop {
                return
            }
            if tool == .pen, color.cgColor.alpha == 0 {
                return
            }
            document.beginStroke(erase: tool == .eraser, opacity: opacity)
            stroking = true
            document.stampDotWorld(at: startWorld, color: color, size: brushSize, erase: tool == .eraser)
            document.stampWorld(from: startWorld, to: point, color: color, size: brushSize, erase: tool == .eraser)
            lastWorld = point
            return
        }
        guard let last = lastWorld else { return }
        document.stampWorld(from: last, to: point, color: color, size: brushSize, erase: tool == .eraser)
        lastWorld = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            document?.recorder.touchMoved(samples(touch, event))
        }
        finishStroke()
        document?.recorder.touchUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        abortStroke()
    }

    // Second finger or pinch: discard, do not endStroke() which would keep the speck.
    func abortStroke() {
        stageView?.hideOffsetCursor()
        if stroking {
            document?.cancelStroke()
        }
        document?.recorder.touchAbort()
        lastWorld = nil
        pendingView = nil
        stroking = false
    }

    private func finishStroke() {
        stageView?.hideOffsetCursor()
        if document?.filling == true {
            lastWorld = nil
            pendingView = nil
            stroking = false
            return
        }
        if tool == .fill {
            if let point = lastWorld {
                let fill: BonePaperFill = color.cgColor.alpha == 0
                    ? .clear
                    : .color(color, opacity: opacity)
                document?.fillWorld(at: point, fill: fill)
                onCommitStroke?()
            }
        } else if stroking {
            document?.endStroke()
            onCommitStroke?()
        }
        lastWorld = nil
        pendingView = nil
        stroking = false
    }

    private func updateStageCursor(for touch: UITouch) {
        guard let stageView else { return }
        let rawStage = touch.location(in: stageView)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - BonePaperFlags.brushOffset)
        stageView.updateOffsetCursor(atStage: targetStage, tool: tool, brushSize: brushSize)
    }

    private func offsetLocation(for touch: UITouch) -> CGPoint {
        let offset = BonePaperFlags.brushOffset
        guard offset > 0, let stageView else {
            return touch.location(in: self)
        }
        let rawStage = touch.location(in: stageView)
        let targetStage = CGPoint(x: rawStage.x, y: rawStage.y - offset)
        return convert(targetStage, from: stageView)
    }

    private func worldPoint(_ touch: UITouch) -> CGPoint {
        guard let document else {
            fatalError("BonePaperDrawView worldPoint with no document")
        }
        let p = offsetLocation(for: touch)
        let side = CGFloat(document.worldSize)
        return CGPoint(
            x: p.x / bounds.width * side,
            y: p.y / bounds.height * side
        )
    }
```

- [ ] **Step 3: Hide offset cursor when `BonePaperPipetteButton` drag ends**

In `/Users/zalivka/wsios/elements/at_elements/Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift`, update `BonePaperPipetteButton.sample` (around line 1047) to call `stage.clearCursor()` on drag end:

```swift
    private var sample: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                hover = stage.sampleColor(atWindow: value.location).map(Color.init)
            }
            .onEnded { value in
                if let picked = stage.sampleColor(atWindow: value.location) {
                    let hex = BonePaperColorStore.hex(from: picked)
                    color = BonePaperColorStore.color(from: hex)
                    BonePaperColorStore.remember(hex)
                    onPick()
                }
                stage.clearCursor()
                hover = nil
            }
    }
```

- [ ] **Step 4: Commit Task 3**

```bash
git -C /Users/zalivka/wsios/elements/at_elements add Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift
git -C /Users/zalivka/wsios/elements/at_elements commit -m "Apply screen-space brushOffset and target cursor on BonePaper canvas"
```
