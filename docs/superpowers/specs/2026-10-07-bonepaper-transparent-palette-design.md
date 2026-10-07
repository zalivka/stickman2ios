# BonePaper Transparent Palette Color

## Scope

Add a fixed transparent swatch as the first color in BonePaper's vertical drawing palette. Do not change the reusable horizontal color row.

## Palette behavior

- The transparent swatch appears before custom and preset colors and cannot be removed or reordered.
- It uses a checkerboard treatment so transparency remains visible against the dark palette.
- Selecting it marks it as the current color and leaves the current drawing tool unchanged.
- The transparent entry is a dedicated palette value, not a persisted custom color or an RGB hex string.

## Drawing behavior

- With the fill tool selected, transparent clears the connected painted region under the tap.
- Clearing participates in the existing undo, redo, fill serialization, recording, and preview update paths.
- With the pen selected, transparent input is a no-op. It must not create opaque paint or an empty undo step.
- Existing eraser behavior remains unchanged.

## Implementation boundaries

- Model vertical palette entries explicitly so transparent is distinct from RGB-backed swatches.
- Add a clear-region branch to BonePaper's flood-fill operation. Do not overload a zero-alpha `FillPaint`: the current recolor algorithm treats its alpha as tool opacity and would perform no change.
- Keep custom-color persistence and `#RRGGBB` conversion unchanged.
- Keep `BonePaperColorRow` unchanged.

## Verification

Do not add tests or build the iOS app unless explicitly requested. Review the changed paths statically for:

- transparent being first only in the vertical palette;
- correct checkerboard and selection indicator rendering;
- fill clearing a connected painted region;
- pen gestures with transparent causing no paint and no undo mutation;
- ordinary colors, fill, eraser, undo, and redo retaining their existing behavior.
