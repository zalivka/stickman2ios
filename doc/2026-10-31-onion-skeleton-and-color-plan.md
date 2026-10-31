# Onion Skeleton & Skeleton Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a light-gray (`#CCCCCC`) onion skeleton of the previous frame in the scene editor, and add a "Color of skeletons" setting that changes only normal orange bones/nodes (`#FF7100` by default).

**Architecture:** Persist `showOnionSkeleton` (`Bool`, default `true`) and `skeletonColorRGB` (`Int`, default `0xFF7100`) in `AppSettings`. Expose an "Editor" section in `AppSettingsSheet` with an Onion Skeleton toggle card and a Color of Skeletons picker card using `FlexColorPickerSheet`. Update `SkeletonCanvas` to read both settings via `@AppStorage`, draw `previousFrameUnits` as a dimmed (`#CCCCCC`) skeleton pass before the current frame's skeletons, and use the configured skeleton color only for normal non-special bones and points in `.editor` mode.

**Tech Stack:** Swift, SwiftUI, UIKit, FlexColorPicker

## Global Constraints

- Do not build iOS or Android unless explicitly ordered by the user.
- Do not write tests unless explicitly ordered by the user.
- Skeleton color affects only normal orange bones/nodes in `.editor` mode (`#FF7100` default); stretchable (`.black`), selected (`boneSelected`), `.skeleton` mode colors (`boneCommon`, `boneSlave`, `boneMaster`, `boneInvisible`), and dimmed onion skeletons (`#CCCCCC`) remain unchanged.

---

### Task 1: Add `showOnionSkeleton` and `skeletonColorRGB` to `AppSettings`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/Model/AppSettings.swift`

**Interfaces:**
- Produces:
  - `AppSettings.showOnionSkeletonKey: String` (`"showOnionSkeleton"`)
  - `AppSettings.skeletonColorRGBKey: String` (`"skeletonColorRGB"`)
  - `AppSettings.defaultSkeletonColorRGB: Int` (`0xFF7100`)
  - `AppSettings.showOnionSkeleton: Bool`
  - `AppSettings.skeletonColorRGB: Int`
  - `AppSettings.color(fromRGB rgb: Int) -> Color`
  - `AppSettings.hexString(fromRGB rgb: Int) -> String`
  - `AppSettings.rgb(from color: UIColor) -> Int?`

- [ ] **Step 1: Update `Shared/Model/AppSettings.swift`**

Add `SwiftUI` and `UIKit` imports and the new keys, properties, and RGB conversion helpers:

```swift
import BonePaper
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Persisted app settings. `boot` copies them into BonePaper before any drawing.
enum AppSettings {
    private static let paperDrawAntialiasingKey = "paperDrawAntialiasing"
    private static let brushOffsetKey = "paperDrawBrushOffset"
    static let showOnionSkeletonKey = "showOnionSkeleton"
    static let skeletonColorRGBKey = "skeletonColorRGB"
    #if DEBUG
    /// Display-only. Missing key is off. A separate key from the retired "No sidecar" switch.
    static let ignoreBmSampleKey = "debugIgnoreBmSample"
    #endif

    static let maxBrushOffset = 70
    static let brushOffsetStep = 10
    static let defaultSkeletonColorRGB = 0xFF7100

    /// Show gray skeleton of the previous frame in the scene editor. Missing key defaults to `true`.
    static var showOnionSkeleton: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showOnionSkeletonKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: showOnionSkeletonKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showOnionSkeletonKey)
        }
    }

    /// 24-bit `0xRRGGBB` color for normal editor skeleton bones/nodes. Defaults to `0xFF7100`.
    static var skeletonColorRGB: Int {
        get {
            guard UserDefaults.standard.object(forKey: skeletonColorRGBKey) != nil else {
                return defaultSkeletonColorRGB
            }
            return UserDefaults.standard.integer(forKey: skeletonColorRGBKey) & 0xFFFFFF
        }
        set {
            UserDefaults.standard.set(newValue & 0xFFFFFF, forKey: skeletonColorRGBKey)
        }
    }

    static func color(fromRGB rgb: Int) -> Color {
        let clamped = rgb & 0xFFFFFF
        let r = Double((clamped >> 16) & 0xFF) / 255.0
        let g = Double((clamped >> 8) & 0xFF) / 255.0
        let b = Double(clamped & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func uiColor(fromRGB rgb: Int) -> UIColor {
        let clamped = rgb & 0xFFFFFF
        let r = CGFloat((clamped >> 16) & 0xFF) / 255.0
        let g = CGFloat((clamped >> 8) & 0xFF) / 255.0
        let b = CGFloat(clamped & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    static func hexString(fromRGB rgb: Int) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }

    static func rgb(from color: UIColor) -> Int? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let converted = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
                  let comps = converted.components,
                  comps.count >= 3
            else {
                return nil
            }
            r = comps[0]
            g = comps[1]
            b = comps[2]
        }
        let ri = Int((min(max(r, 0), 1) * 255).rounded())
        let gi = Int((min(max(g, 0), 1) * 255).rounded())
        let bi = Int((min(max(b, 0), 1) * 255).rounded())
        return (ri << 16) | (gi << 8) | bi
    }
```

---

### Task 2: Add Onion Skeleton and Skeleton Color controls to `AppSettingsSheet`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/AppSettingsSheet.swift`

**Interfaces:**
- Consumes: `AppSettings.showOnionSkeleton`, `AppSettings.skeletonColorRGB`, `AppSettings.defaultSkeletonColorRGB`, `AppSettings.color(fromRGB:)`, `AppSettings.uiColor(fromRGB:)`, `AppSettings.hexString(fromRGB:)`, `AppSettings.rgb(from:)`, `FlexColorPickerSheet`

- [ ] **Step 1: Add state and UI cards in `Shared/UI/AppSettingsSheet.swift`**

Add `@State private var showOnionSkeleton: Bool`, `@State private var skeletonColorRGB: Int`, and `@State private var showingSkeletonColorPicker = false`.
Save them in `applyButton` (and `tutorialCard`), and render an `"Editor"` section with `onionSkeletonCard` and `skeletonColorCard`, plus `.sheet(isPresented: $showingSkeletonColorPicker)` presenting `FlexColorPickerSheet`.

```swift
    @State private var antialiasing: Bool
    @State private var brushOffset: Double
    @State private var showOnionSkeleton: Bool
    @State private var skeletonColorRGB: Int
    @State private var showingSkeletonColorPicker = false
```

In `init`:
```swift
        _antialiasing = State(initialValue: AppSettings.paperDrawAntialiasing)
        _brushOffset = State(initialValue: Double(AppSettings.brushOffset))
        _showOnionSkeleton = State(initialValue: AppSettings.showOnionSkeleton)
        _skeletonColorRGB = State(initialValue: AppSettings.skeletonColorRGB)
```

In `applyButton`:
```swift
            AppSettings.paperDrawAntialiasing = antialiasing
            AppSettings.brushOffset = Int(brushOffset.rounded())
            AppSettings.showOnionSkeleton = showOnionSkeleton
            AppSettings.skeletonColorRGB = skeletonColorRGB
```

In `formBody`:
```swift
                Text("Editor")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SkeletonChrome.toolLabel)
                    .textCase(.uppercase)
                onionSkeletonCard
                skeletonColorCard
```

Card implementations:
```swift
    private var onionSkeletonCard: some View {
        Button {
            showOnionSkeleton.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(Color(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Onion skeleton")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Show gray skeleton of previous frame")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: showOnionSkeleton ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(showOnionSkeleton ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Onion skeleton")
        .accessibilityAddTraits(showOnionSkeleton ? [.isSelected] : [])
    }

    private var skeletonColorCard: some View {
        let isCustom = skeletonColorRGB != AppSettings.defaultSkeletonColorRGB
        return HStack(alignment: .center, spacing: 12) {
            Button {
                showingSkeletonColorPicker = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(AppSettings.color(fromRGB: skeletonColorRGB))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Color of skeletons")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(AppSettings.hexString(fromRGB: skeletonColorRGB))
                            .font(.system(size: 13).monospaced())
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color of skeletons")

            if isCustom {
                Button {
                    skeletonColorRGB = AppSettings.defaultSkeletonColorRGB
                } label: {
                    Text("Reset")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset skeleton color")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCustom ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
        )
        .sheet(isPresented: $showingSkeletonColorPicker) {
            FlexColorPickerSheet(initial: AppSettings.uiColor(fromRGB: skeletonColorRGB)) { picked in
                if let rgb = AppSettings.rgb(from: picked) {
                    skeletonColorRGB = rgb
                }
                showingSkeletonColorPicker = false
            }
        }
    }
```

---

### Task 3: Render Onion Skeleton and Custom Skeleton Color in `SkeletonCanvas` and wire `SceneEditorScreen`

**Files:**
- Modify: `/Users/zalivka/wsios/elements/at_elements/Shared/UI/SkeletonCanvas.swift`
- Modify: `/Users/zalivka/wsios/elements/at_elements/at_elements/Screens/SceneEditorScreen.swift`

**Interfaces:**
- Consumes: `AppSettings.showOnionSkeletonKey`, `AppSettings.skeletonColorRGBKey`, `AppSettings.defaultSkeletonColorRGB`, `AppSettings.color(fromRGB:)`
- Produces: `SkeletonCanvas.previousFrameUnits: [StickmanUnit]`

- [ ] **Step 1: Update `Shared/UI/SkeletonCanvas.swift`**

Add `static let onionSkeletonColor = Color(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255)` (Android `Color.LTGRAY`), `var previousFrameUnits: [StickmanUnit] = []`, and `@AppStorage` properties for `showOnionSkeleton` and `skeletonColorRGB`:

```swift
    /// Android `DefaultSkeletonDrawer.DIM_COLOR` (`Color.LTGRAY`).
    static let onionSkeletonColor = Color(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255)
```

In properties:
```swift
    var unit: Binding<StickmanUnit>? = nil
    var frameUnits: [StickmanUnit] = []
    var previousFrameUnits: [StickmanUnit] = []
```
and:
```swift
    @AppStorage(AppSettings.showOnionSkeletonKey) private var showOnionSkeleton = true
    @AppStorage(AppSettings.skeletonColorRGBKey) private var skeletonColorRGB = AppSettings.defaultSkeletonColorRGB
```

In `Canvas` `.editor` switch case (lines 285–298), draw the onion skeletons after unit content / expose circles and before current frame skeletons (matching `StickmanViewDrawer.drawEditor` on Android):
```swift
                case .editor:
                    drawScene(context: &context, layout: layout)
                    drawSceneBound(context: &context, layout: layout)
                    for drawn in unitsToDraw {
                        drawUnitContent(drawn, context: &context, layout: layout, ignoreSample: ignoreSample)
                    }
                    drawAttachExpose(context: &context, layout: layout)
                    drawStretchExpose(context: &context, layout: layout)
                    if showSkeleton, showOnionSkeleton {
                        for previous in previousUnitsToDraw {
                            drawSkeleton(previous, context: &context, layout: layout, dim: true)
                        }
                    }
                    for drawn in unitsToDraw {
                        drawUnitSkeleton(drawn, context: &context, layout: layout)
                    }
                    drawCameraRectangle(context: &context, layout: layout)
                    drawHandlers(context: &context, layout: layout)
                    drawTouchPoint(context: &context)
```

Add `previousUnitsToDraw`:
```swift
    private var previousUnitsToDraw: [StickmanUnit] {
        previousFrameUnits.sorted {
            if $0.arrange != $1.arrange {
                return $0.arrange < $1.arrange
            }
            return $0.name < $1.name
        }
    }
```

Update `drawSkeleton` to take `dim: Bool = false` and use `AppSettings.color(fromRGB: skeletonColorRGB)` for normal bones/nodes and `Self.onionSkeletonColor` when `dim == true`:
```swift
    private func drawSkeleton(
        _ drawn: StickmanUnit,
        context: inout GraphicsContext,
        layout: SkeletonLayout,
        dim: Bool = false
    ) {
        let bones = mode == .skeleton
        let selectedId = selectedPointId.wrappedValue
        let selectedEdge = selectedId.flatMap { drawn.upperEdge(of: $0) }
        let normalColor = dim ? Self.onionSkeletonColor : AppSettings.color(fromRGB: skeletonColorRGB)
        for edge in drawn.edges {
            guard let from = drawn.point(optionalId: edge.from), let to = drawn.point(optionalId: edge.to) else { continue }
            var path = Path()
            path.move(to: layout.screenPoint(x: from.x, y: from.y))
            path.addLine(to: layout.screenPoint(x: to.x, y: to.y))
            let isSelected = !dim && bones && selectedEdge?.from == edge.from && selectedEdge?.to == edge.to
            let edgeColor: Color
            if dim {
                edgeColor = Self.onionSkeletonColor
            } else if isSelected {
                edgeColor = Self.boneSelected
            } else if drawn.point(optionalId: edge.to)?.stretchable == true {
                edgeColor = Self.boneStretchable
            } else if bones {
                edgeColor = Self.boneCommon
            } else {
                edgeColor = normalColor
            }
            context.stroke(
                path,
                with: .color(edgeColor),
                style: StrokeStyle(lineWidth: bones ? Self.boneEdgeWidth : Self.edgeWidth, lineCap: .butt)
            )
        }
        for point in drawn.points {
            if !bones, !drawn.canBeDragged(point) {
                continue
            }
            let center = layout.screenPoint(x: point.x, y: point.y)
            let isSelected = !dim && bones && point.id == selectedId
            let color: Color
            if dim {
                color = Self.onionSkeletonColor
            } else if isSelected {
                color = Self.boneSelected
            } else if point.stretchable {
                color = Self.boneStretchable
            } else if bones {
                color = Self.boneColor(point)
            } else {
                color = normalColor
            }
            let radius: CGFloat
            if bones {
                radius = isSelected ? Self.boneNodeRadius * 1.5 : Self.boneNodeRadius
            } else {
                radius = point.isBase ? Self.baseNodeRadius : Self.nodeRadius
            }
            context.fill(Path(ellipseIn: Self.square(around: center, radius: radius)), with: .color(color))
            if bones, point.isBase {
                context.stroke(
                    Path(ellipseIn: Self.square(around: center, radius: Self.boneBaseRingRadius)),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: Self.boneBaseRingWidth)
                )
            }
        }
    }
```

- [ ] **Step 2: Pass `previousFrameUnits` in `at_elements/Screens/SceneEditorScreen.swift`**

In `SceneEditorScreen.editorStageContent`:
```swift
                SkeletonCanvas(
                    unit: frame.units.isEmpty ? nil : unitBinding,
                    frameUnits: frame.units,
                    previousFrameUnits: scene.currentIndex > 0 ? scene.frames[scene.currentIndex - 1].units : [],
                    assets: assets,
```
