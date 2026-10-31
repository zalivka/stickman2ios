# Palace Square session: `-nooutlines`, and light through the column

Date: 2026-10-31. Scene: `tools/bonepaper_gen/out/palace_square/`.

Both a sketch (`ink.py svg`) and a flat (`flat.py` region brush) version of
Saint-Petersburg Palace Square at evening, from one source `src.svg`.

## What was added

### `-nooutlines` on both engines

One flag, one meaning: drop only linework the *author* tagged, keep every fill.

Source SVG elements carry `data-role`:

| role | is | with `-nooutlines` |
|---|---|---|
| `outline` | polygon contours, black structural lines | dropped |
| `detail` | windows, cornices, paving, lamps, birds, gold highlights | kept |

Tagging is what makes the flag honest. "Skip every black stroke" would also
delete the birds and the lamp posts.

- `ink.py svg ... -nooutlines` — `svg_sketch(outlines=False)` skips items whose
  `role == "outline"` in pass 2. `_load_svg_scene` now reads `data-role` into
  each item (`_elem_style` already carried it once listed alongside
  `data-angle` / `data-wash`).
- `flat.py bg ... -nooutlines` — `brush_svg(..., outlines=False)` keeps
  `_stamp` and `_fill_inside` for every shape but skips both contour emitters
  (the compact ring and the elongated limb stroke).
- The scene script exposes it too: `build.py -nooutlines` renders to
  `out/palace_square/nooutlines/`.

Defaults are byte-identical to before the flag existed, so nothing else moved.

### Light through the column

Symptom: lit windows and pale bands appeared on top of the Alexander Column.

Two independent causes, and the second was the one actually visible:

1. **Painter's order.** Window strokes for the buildings *behind* the column
   were drawn after the column polygons and nothing masked them, so the window
   at `x=330` landed inside the shaft (x 319–353). Fixed with
   `clip_to_column()`, which cuts those bands against `column_footprint()`.
2. **The column's own decoration.** A 10 px opaque `GOLD` bar at `y=322` and a
   `WHITE_TRIM` band at `y=352` were painted across the pedestal. Pale and
   opaque, they read exactly like light shining through granite. Both are now
   `BRONZE`.

The column's own strokes live in a separate list so `column_footprint()` never
clips the column against itself.

## Numbers

Shaft interior (x 324–348, y 110–285), bright pixels with luma > 150:

| | before | after |
|---|---|---|
| sketch | band present | **0 / 16800** |
| flat | band present | **0 / 16800** |

Stroke polylines in the emitted SVG:

| | with outlines | `-nooutlines` |
|---|---|---|
| sketch | 211 | 192 |
| flat | 86 | 62 |

`flat.py bg` CLI on a 1280×960 source: **120 → 0** polylines.

Gates were proven able to fail: deleting each `if outlines` guard restored the
un-gated counts (sketch 192 → 209, flat 62 → 77).

## Traps hit

- **`hand.py` `SLOP = 12`.** A stroke shorter than that raises
  `stroke shorter than slop` and aborts the whole render. Two 12 px courtyard
  windows killed *both* flat renders silently — and because the previous PNGs
  were still on disk, the run looked successful with stale images. Windows are
  22 px now, and `clip_to_column` drops sub-14 px clip remnants on purpose
  instead of letting hand.py throw.
- **Stale previews.** Re-rendering to the same paths made an IDE preview look
  unchanged twice. Render "after" images to fresh paths (`v2/`,
  `v2_sketch/`) before claiming a visual fix.
- **Wrong metric.** Counting "gold inside the column bbox" includes the gold
  capital and plaque, so it never reaches 0 and says nothing. The metric that
  actually distinguishes the bug is bright pixels strictly inside the shaft
  interior.
- **`flat.py bg -nooutlines` was a no-op.** The flag was defined on the `bg`
  subparser but never passed to `tracer.brush_svg`, so the CLI silently drew
  outlines anyway. Only the scene script honoured it. Now passed in `cmd_bg`.

## Files

Changed:

- `tools/bonepaper_gen/ink.py` — `data-role` parsing, `outlines` param, CLI flag.
- `tools/bonepaper_gen/flat.py` — `bg --nooutlines` flag and pass-through.
- `tools/bonepaper_gen/out/bluehairsvg/build.py` — `brush_svg(outlines=...)`,
  plus a loud exit if `outlines=False` leaves no fills at all. **Note: this file
  is gitignored** (`.gitignore:69` ignores `tools/bonepaper_gen/out/`), so the
  flat engine's half of this feature is an untracked edit. It must be mirrored
  anywhere that tracer is vendored, or the flat flag will silently stop
  existing.

Created:

- `out/palace_square/build.py` — single source of truth: emits `src.svg`, then
  renders the flat version.
- `out/palace_square/src.svg` — the authored page both engines consume.

Outputs:

```
out/palace_square/bg.png                        flat
out/palace_square/nooutlines/bg.png             flat, -nooutlines
out/palace_square/sketch/bg.png                 sketch
out/palace_square/sketch_nooutlines/bg.png      sketch, -nooutlines
out/palace_square/v2*/                          same four, fresh paths
```

## Commands

```sh
cd tools/bonepaper_gen

.venv/bin/python flat.py lint out/palace_square/build.py
.venv/bin/python out/palace_square/build.py
.venv/bin/python out/palace_square/build.py -nooutlines

.venv/bin/python ink.py svg out/palace_square/src.svg \
    -o out/palace_square/sketch/palace_square_sketch.zip \
    --wash-opacity 0.85 --slop 0.75
.venv/bin/python ink.py svg out/palace_square/src.svg -nooutlines \
    -o out/palace_square/sketch_nooutlines/palace_square_sketch_nooutlines.zip \
    --wash-opacity 0.85 --slop 0.75
```
