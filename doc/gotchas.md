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

## Missing frame `bg_name` / `bg`

Older scenes omit `bg_name` and sometimes `bg=`. Android `Frame` defaults to `#ffffff` and identity `PictureMove`. Do not fatal on a missing attr; still fatal on an unknown non-empty `bg_name`. Solid colors are Android `Color.parseColor`: `#rrggbb` or `#aarrggbb` (`demo_faces` uses `#ff202020`). Bitmap backgrounds are `_bgs/<own>.zip` + `bg_name="usermade:<own>"`, not a root `bg.png`.

## Speech bubble is plain text

Android `type="bubble"` draws a 9-patch (`bubble.9.png`) then `StaticLayout` text. iOS has no 9-patch. Load `meta` (URL-decoded JSON) and draw the string only: color, `max(22, 30 - count/4) * scale`, wrap at 150 when `oneLiner` is false. Place at point 1, rotate with the 1→2 edge. Do not bone-stretch `.9.png` to fake a bubble. Font must be `default` until scene `fonts/` exists.

## `.atp` packs are unpacked, then Manifest reads the tree

An `.atp` is distribution only. `ExternalPack` copies bundle `packs/*.atp` into Application Support when `meta.txt` `version` is newer, then Manifest indexes `manifest.xml` + `items/<sname>.ati` + `translate_<lang>.xml` (else `en`). Bump `version` to force re-unpack. Native `assets/scenes/*` packs are out of scope.

`Manifest` is a serial queue. `schedule(task, then:)` enqueues both jobs together so nothing interleaves. Two separate `await`s are not a chain. Call `requestReload()` on app start (not from the widget). `reloadPack` / `reloadAll` only run inside `schedule`.

Insert queries one pack at a time (`Query(packName)`). Do not mix `common` or custom `@` into every pack the way Android `Query.setPacks` does.

## Unit alpha can be > 1

Scene XML stores `alpha` as a raw float. Android parses it as-is (`demo_camera` has `@:Чёрный_СтикМан#2` at `1.08`). Draw only applies a transparency layer when `alpha < 1`, so values at or above 1 are opaque. Do not reject `alpha > 1` on load. Still fatal on `alpha < 0`.
