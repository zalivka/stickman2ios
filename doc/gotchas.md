# Gotchas

## PictureMove transform order (CG vs Android)

Android `PictureMove.toMatrix` is `setScale` → `postRotate` → `postTranslate`. That is **scale, then rotate, then unscaled translate** (`T * R * S`). Translation is added after scale, in the same units as `x` / `y`.

Core Graphics chaining looks like the same order but is not:

```swift
CGAffineTransform.identity
    .scaledBy(x: scale, y: scale)
    .rotated(by: rotate)
    .translatedBy(x: x, y: y)
```

`scaledBy` then `translatedBy` is **translate, then scale**. The translation is multiplied by scale.

Example: camera `1.48 0 20 -200` must mean “zoom 1.48×, then move by `(20, -200)`”. The wrong chain does “move by `(20, -200)`, then zoom 1.48× around the origin”. The inverted editor camera rect sits too far left and down; Play bakes the fit origin through the same mistake.

Correct iOS build (`Shared/Model/PictureMove.swift` `toTransform()`):

```swift
CGAffineTransform(translationX: x, y: y)
    .rotated(by: rotate * .pi / 180)
    .scaledBy(x: scale, y: scale)
```

Same `PictureMove` is used for camera and `bg=`. Do not “fix” this back to `identity.scaledBy.translatedBy`.

## Packed `.ati`

Android extracts every zip entry ending in `.ati`, including `pack/items/name.ati`. Do not require items at the archive root. Match a unit to the entry whose last path component is `ownName.ati`.

## PackAlias on unit names and `attached=`

Native Android packs (`jungle`, `newstickman`, `common`) become dotted ATP ids. `PackAlias` rewrites unit `name=` (`jungle:lance` → `zalivka.jungle:lance`). The slave `attached="jungle:papuas&7"` master name must get the same rewrite or `SlavesRegistry.populate` never finds the master (`demo_lion`).

## Missing frame `bg_name` / `bg`

Older scenes omit `bg_name` and sometimes `bg=`. Android `Frame` defaults to `#ffffff` and identity `PictureMove`. Do not fatal on a missing attr; still fatal on an unknown non-empty `bg_name`. Solid colors are Android `Color.parseColor`: `#rrggbb` or `#aarrggbb` (`demo_faces` uses `#ff202020`). Bitmap backgrounds are `_bgs/<own>.zip` + `bg_name="usermade:<own>"`.

Some demos (`demo_space`, `demo_fight`) still use the pre-`bg_name` layout: root `bg.png` and `bg="1.0 0.0 0.0 0.0"` (that `bg=` is PictureMove, not a color). Android `SceneHelper` wraps the PNG as `usermade:<millis>` and stamps every frame. Do the same on load; do not leave those frames as `#ffffff`.

## Speech bubble is plain text

Android `type="bubble"` draws a 9-patch (`bubble.9.png` / `empty.9.png`) then `StaticLayout` text. iOS has no 9-patch. Load `meta` (URL-decoded JSON) and draw the string only: color, `max(22, 30 - count/4) * scale`, wrap at 150 when `oneLiner` is false. Place at point 1, rotate with the 1→2 edge. Do not bone-stretch `.9.png` to fake a bubble.

Fonts match Android `Fonts.getByName`: `default` is system; bundled keys `roboto/bold`, `roboto/regular`, `graffiti`, `rafale` from `fonts/*.ttf`. Scene zip `fonts/*.ttf|otf` install as custom (key = filename without extension). Unknown font names fatal. User ttf-picker install is not on iOS yet — `roboto/bold` is bundled, not installed.

`common:sign` ships as `zalivka.common` (`PackAlias` `common` → `zalivka.common`). The ATI has `type="bubble"` + meta, no `assets.xml`. Item load must keep type/meta; skip packed bitmaps for bubbles. Empty item `meta=""` is Android `BubbleMeta()` defaults (`text=Text`, black, `font=default`).

## `.atp` packs are unpacked, then Manifest reads the tree

An `.atp` is distribution only. `ExternalPack` copies bundle `packs/*.atp` into Application Support when `meta.txt` `version` is newer, then Manifest indexes `manifest.xml` + `items/<sname>.ati` + `translate_<lang>.xml` (else `en`). Bump `version` to force re-unpack. Native `assets/scenes/*` packs are out of scope.

`Manifest` is a serial queue. `schedule(task, then:)` enqueues both jobs together so nothing interleaves. Two separate `await`s are not a chain. Call `requestReload()` on app start (not from the widget). `reloadPack` / `reloadAll` only run inside `schedule`.

Insert queries one pack at a time (`Query(packName)`). Do not mix `common` or custom `@` into every pack the way Android `Query.setPacks` does.

## Unit alpha can be > 1

Scene XML stores `alpha` as a raw float. Android parses it as-is (`demo_camera` has `@:Чёрный_СтикМан#2` at `1.08`). Draw only applies a transparency layer when `alpha < 1`, so values at or above 1 are opaque. Do not reject `alpha > 1` on load. Still fatal on `alpha < 0`.

## Slow physical-device launch with Xcode

If Xcode spends several seconds on **Waiting to attach**, followed by another delay before the first `App.init` log, the app is not causing that delay. Xcode is starting `debugserver`, connecting LLDB to the device, loading symbols and preparing breakpoints before application code runs.

For fast UI iteration, open **Product → Scheme → Edit Scheme → Run → Info** and uncheck **Debug executable**. The app then launches without LLDB; `print` / unified logging still works, but breakpoints, variable inspection, debugger commands, memory graph and view hierarchy debugging do not. Re-enable it when interactive debugging is needed.

## Two-finger gestures across separate `UIViewRepresentable`s

The skeleton editor needs one finger holding **New** (`HoldTouchPad` in `Shared/UI/SkeletonToolsPanel.swift`) while a second finger drags a bone out of a node on the canvas (`SkeletonTouchOverlay` in `Shared/UI/SkeletonCanvas.swift`). Three separate traps, all of which look like "the button is ignoring me":

**Never set `isExclusiveTouch` on the hold view.** It does not mean "this view keeps its own touch"; it means no other view in the window receives touches while this one tracks. Holding New then silently killed every canvas touch, so dragging did nothing at all.

**Do not track the hold with raw `touchesBegan`.** Touches reach a representable's `UIView` only after SwiftUI's recognizers on the hosting view finish arbitrating, which is a clearly perceptible delay. Use a `UILongPressGestureRecognizer` with `minimumPressDuration = 0`, `delaysTouchesBegan = false`, `delaysTouchesEnded = false`, `cancelsTouchesInView = false`. Zero duration enters `.began` on touch-down, ahead of that arbitration. Set `allowableMovement = .greatestFiniteMagnitude` or a thumb sliding a few points fails the gesture and drops hold mode mid-drag. The delegate must return `true` from `shouldRecognizeSimultaneouslyWith` so the canvas keeps its own recognizers.

**A clear representable is invisible to hit-testing.** Give the hold view a tiny `backgroundColor` alpha (0.01) and override `hitTest` to return `self` inside `bounds`; a `.background` modifier is not enough, the pad has to overlay the button's visuals directly. Without this the hold fires only sometimes.

Shared editor state (hold mode, selected point) lives in `SkeletonEditSession`, a class. Touch callbacks fire outside the SwiftUI update cycle, so a value type snapshotted into a closure reads stale.

## Frame next/prev: SwiftUI tap + long-press, then UIButton overflow

`DualNavigationChrome` next/prev must do Android's `ImageButton` pair: tap = one frame, long-press = page jump. Stacking `.onTapGesture` and `.onLongPressGesture` on the same SwiftUI view makes taps miss. The long-press `pressing:` callback claims the touch; a release before 0.35s fires neither tap nor long-press.

Use a `UIButton` (`touchUpInside` + `UILongPressGestureRecognizer`). Property is `minimumPressDuration`, not SwiftUI's `minimumDuration`. If the long-press begins, swallow the following `touchUpInside` so you do not also step one frame.

Do not put that `UIButton` in a 60×60 SwiftUI frame and `setImage` the chrome PNG at `UIScreen.main.scale`. `UIViewRepresentable` does not clip; the button's intrinsic size is the image in points and the artwork paints over `SeekFramesBar`. Size the `UIImage` so it displays at `barWidth / 1.5` (40pt), keep the control in the original 40+8+8 slot, and `clipsToBounds`.
