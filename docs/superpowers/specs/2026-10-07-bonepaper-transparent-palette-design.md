# BonePaper Transparent Palette Color

## Scope

Add a fixed transparent swatch as the first color in BonePaper's vertical drawing palette. Do not change the reusable horizontal color row.

## Palette behavior

- The transparent swatch appears before custom and preset colors and cannot be removed or reordered.
- It uses a checkerboard treatment so transparency remains visible against the dark palette.
- Selecting it marks it as the current color and immediately selects the fill tool.
- The transparent entry is a dedicated palette value, not a persisted custom color or an RGB hex string.

## Drawing behavior

- Transparent clears the connected painted region under a fill tap.
- Clearing participates in the existing undo, redo, fill serialization, recording, and preview update paths.
- While transparent is selected, brush-size and opacity controls are disabled and shown at 35% opacity.
- Selecting transparent closes any open brush-size or opacity slider.
- Eraser, fill, undo, and redo controls remain enabled.
- The document retains its transparent-pen no-op guard as a safety invariant.
- Selecting an opaque palette color restores brush-size and opacity controls and retains the existing behavior of selecting the pen.
- Existing eraser behavior remains unchanged.

## Implementation boundaries

- Model vertical palette entries explicitly so transparent is distinct from RGB-backed swatches.
- Route transparent selection separately from opaque-color selection so tool changes are explicit.
- Derive brush/opacity availability from whether the selected color is transparent; do not duplicate palette state.
- Add a clear-region branch to BonePaper's flood-fill operation. Do not overload a zero-alpha `FillPaint`: the current recolor algorithm treats its alpha as tool opacity and would perform no change.
- Keep custom-color persistence and `#RRGGBB` conversion unchanged.
- Keep `BonePaperColorRow` unchanged.

## Verification

Do not add tests or build the iOS app unless explicitly requested. Review the changed paths statically for:

- transparent being first only in the vertical palette;
- correct checkerboard and selection indicator rendering;
- transparent selection activating fill and dimming/disabling brush and opacity;
- opaque color selection restoring brush and opacity;
- eraser, fill, undo, and redo remaining available with transparent selected;
- fill clearing a connected painted region;
- pen gestures with transparent causing no paint and no undo mutation;
- ordinary colors, fill, eraser, undo, and redo retaining their existing behavior.
