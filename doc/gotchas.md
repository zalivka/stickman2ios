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
