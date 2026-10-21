---
name: slopmax3
description: >-
  EDT-based sketch backgrounds and wide-brush marker washes for line art and
  hybrid pictures (solid areas + thin strokes + enclosed interior tints) via
  tools/bonepaper_gen/slopmax3.py. Use when the user says slopmax3, asks to
  sketch/vectorize line art or wash regions without a custom build.py, or when
  slopmax2 bg/--flatten is the wrong tool for strokes-on-paper.
---

# Slopmax3

One command for line-art / hybrid backgrounds and marker-wash coloring. Local
half-width comes from the **Euclidean distance transform** (`distance_transform_edt`)
— not `MinFilter` erosion loops or `area / length` averages. Replaces per-picture
hybrid `build.py` scripts (`out/glasses`, `out/redface`, `out/wojak`, …).

Detailed math, coloring geometry, and failure modes live in [reference.md](reference.md)
and [slopmax reference](../../../skills/slopmax/reference.md).

Run from `tools/bonepaper_gen` with `.venv/bin/python`. Do not edit `hand.py`.
Needs `scipy` (see `requirements.txt`).

## When to use which tool

| Picture | Tool |
|---------|------|
| Flat colour cartoon / logo | `slopmax2.py bg` |
| Comic with fills + ink | `slopmax2.py bg --flatten` |
| Line art / hybrid (hair fills + thin face strokes + washes) | **`slopmax3.py sketch`** |
| Shaded photo of an object on white paper (`pirate_roller`) | Extract silhouette boundary + DoG internal seams → **`slopmax3.py sketch --tint`** |
| Nothing to trace (draw from shapes) | `slopmax2.py draw` |

## Commands

| Job | Command | Writes |
|-----|---------|--------|
| Sketch | `slopmax3.py sketch src.png -o out/name/name.zip` | `bg.png` 1280×960, `bg.svg`, `thumb.png`, zip, `compare.png`, `edt_split.png`, `pockets.png` |
| Sketch + hair wash | `slopmax3.py sketch src.png --wash -o out/name/name.zip` | same; hair-scale ink regions get pale wide-brush hatch |
| Sketch + wash + auto pocket tint | `slopmax3.py sketch src.png --wash --auto-tint -o out/name/name.zip` | same; auto-colors all enclosed pockets from source RGB + `--skin-tint` for white pockets |
| Sketch + wash + face tint | `slopmax3.py sketch src.png --wash --tint "#FCE4DC" -o out/name/name.zip` | same; enclosed face/body paper pocket washed under ink |

Options:

| Option | Use |
|--------|-----|
| `--wash` | Pale wide-brush hatch (`opacity=0.32, size=26..30`) for large ink regions (`area >= 5000` or `short >= 70`) instead of solid stamp fill |
| `--wash-color #HEX` | Colour for `--wash` strokes (default: `--ink`) |
| `--auto-tint` | Zero-seed automatic pocket coloring: colors already-tinted source pockets with their source RGB along their PCA major axis, and white pockets (`>= 800 px`) with `--skin-tint` |
| `--skin-tint #HEX` | Colour for white interior pockets when `--auto-tint` is used (default: `#FCE4DC`; pass `none` to skip white pockets) |
| `--remap OLD:NEW` | Remap source pocket colour in `--auto-tint` mode (e.g. `--remap "#B97A57:#505050"`, repeatable, matches within RGB distance 45) |
| `--tint SPEC` | Wash an enclosed paper pocket underneath ink: `#HEX` (auto largest pocket), `auto:#HEX@25`, or `x,y:#HEX[@angle]` (repeatable; seeds are printed to stdout and drawn on `pockets.png`) |
| `--slop FLOAT` | Looseness of wash & region outline (`0.0` = clean, `1.0` = default, `>1.0` = wilder; alias `--sloppiness`) |
| `--wash-opacity FLOAT` | Opacity override for tint and region wash strokes (default: `0.45` tint / `0.32` region; use `0.9` for nearly opaque marker fills) |
| `--tint-size FLOAT` | Brush width for `--tint` (default 30). Below 30 the cap is pulled inside and rows overlap; jitter also drops to `0.15 + 0.25*slop` |
| `--ink #222222` | Stroke and region outline colour |
| `--name NAME` | Zip / log label (default: output stem) |
| `--skip-budget` | Debug only: bypass the 8×8 ink-density gate |

## What the pipeline does

1. **Canvas contract**: `fit_page` → 640×480 before any tracing.
2. **Dark still lift**: if median channel peak < 60, gamma-lift 0.45 (`busnight`).
3. **Ink mask (`ink_hysteresis`)**:
   - Light paper (`paper_luma >= 200`): strict near-black core + local median-15 contrast hysteresis (avoids LANCZOS gray halos on upscaled small sources like `wojak`).
   - Coloured/dark paper (`redface`): RGB channel drop `max(paper_rgb - arr)` + hysteresis.
   - **Tangent endpoint walk (`extend_fade_ends`)**: walks raw skeleton endpoints outward through the marker fade band (`cos >= 0.35`), closing faded neck/petal tips without fattening strokes.
4. **EDT radius (`edt_radius`)**: exact distance to nearest paper pixel at every ink pixel.
5. **Exact EDT region split (`region_mask`)**:
   - Seeds: `r >= 7.0`.
   - Reconstructs full region via `distance_transform_edt(~seed) <= REGION_R - 0.5` clipped to the seed's own ink island (eliminates the 5-px pupil collar double-ring).
6. **Coloring (`hatch_region` & `--tint`)**:
   - **Layer order**: enclosed paper `--tint` washes at bottom (`opacity=0.45, size=30`), then ink region `--wash` (`opacity=0.32, size=26..30`) + sloppy open-arc outline (`<= 4.0 px`), then crisp centre-line strokes on top.
   - **Controlled hand-colored wash**: light inward buffer (`-0.15 * brush_size`) so wide round caps slightly kiss/cross the outline without wild spillover, with randomized step spacing (`0.8..1.2×`), endpoint jitter (`±3 px`), per-stroke angle wobble (`±2.2°`), midpoint bow (`±2.5 px`), and brush width variation (`0.88..1.16×`).
   - **Sloppy region outline (`sloppy_outline_strokes`)**: coarsens the boundary (`simplify(7.5)`), perturbs vertices (`±4.5 px`), and draws 3 overlapping open arcs with tangent tail overshoots (`2..7 px`) and `jitter=2.2`.
   - **Serpentine tip linking**: links short tip slices (`< 13 px`) across adjacent scanlines (`jump <= 1.9 * spacing`) so narrow spikes get colored without triggering `hand.py` SLOP aborts.
   - **Scale gate**: pupil/brow-scale regions (`short < 70` and `area < 5000`) are never washed with a wide brush; pupil-scale (`short < 36`) stamps directly without extra buffer or outline stroke.
   - **False pockets**: a white pocket is not an interior. Tint it only when `pockets.png` shows it inside one outline. The test and the stem/leaf case are in the reference.
7. **Strokes (`prune_l_corners` + `split_by_radius` + `glue_chains`)**:
   - Prunes 8-connected L-corner staircase pixels from Zhang-Suen skeletons so diagonal curves don't shatter into 2-px fragments.
   - Median-5 smooths radii along each path; splits where `|Δr| >= 1.5` (`size = 2 * median(r)`, clamped 2–8).
   - Glues split branches when width jump `< 2.0 px`; preserves isolated short features (`nose` ticks) via tangent stretch while dropping junction crumbs.
8. **Ink-budget gate (`ink_budget`)**: 8×8 grid comparison against fitted source (`luma < 200` in wash mode, `max < 90` in solid mode); loud fail on >2.5× drift.

## Do not

- Write a per-picture `build.py` for line art, hybrid ink+fill, or face/hair washes — run `slopmax3.py sketch`.
- Feed a continuous-tone shaded photo directly into `slopmax3.py sketch` — `ink_hysteresis` only sees the dark cast-shadow side as ink and drops the lit contour entirely (`pirate_roller`). Convert the object's silhouette boundary + internal DoG creases into synthetic line art first, then wash with `--tint`.
- Pass pre-translated (`+PAD`) geometry to `tracer._stamp` — `_stamp` adds `PAD` internally (double-offset shifts pupils onto cheeks).
- Wash small regions (`short < 70`) with a wide brush or slice un-inset polygons.
- Tint every white pocket from the log. A pocket between two strokes that nearly touch (stem and leaf, arm and body) is the gap, not the interior. See the reference.
- Fill an interior darker than luma ~90 on white paper. `ink_hysteresis` keeps `luma < 90` once it touches a `luma < 55` stroke, so the fill is ink, not a pocket. `#4a3428` (luma ~57) and `#6b4226` (luma ~82) became black stamps; `#8d5a32` (luma ~101) stayed a pocket. A second dark mark inside the same outline welds into that blob. A highlight that should only shift the median colour is `stroke="none"`.
- Omit the source stroke to hide an outline. No closed ink means no pocket and no wash. Sketch with the stroke, then delete the unwanted `<polyline stroke="#222222">` from `bg.svg` and re-raster.
- Drop a whole polyline because part of it is unwanted. `glue_chains` joins touching outlines into one `points` list (a log chained onto a puff). Split at the boundary and keep the run you want.
- Treat `painted 0` as a missed seed. The pocket was found; every hatch stroke was shorter than 15 px, or a `--tint-size` bigger than the short side inset the shape to nothing. A ~23 px log painted 0 at size 14 and painted at size 8.
- Use `--slop` near 0 when the fill should look drawn. Wobble is only `±2.2*slop` degrees, and `--tint-size < 30` cuts jitter further. The reviewed hand-drawn fill is `--slop 0.7` plus a different `@angle` per pocket. Slop does not fan strokes that share one angle.
- Pass `--tint` and `x,y:#HEX@angle` as one shell word. `#` comments out the rest in zsh, and one argv token `"--tint 320,200:#C4956A@4"` is an unrecognized argument. Two arguments: `--tint` then `320,200:#C4956A@4`.
- Ship the page bitmap. `bg.svg` has a `<rect fill="#FFFFFF"/>` so the tracer has paper. The bitmap you deliver (item, sprite, gif that sits on a colored scene) is the strokes only: delete that rect and `rsvg-convert -b none`. Rasterizing the white rect, then punching out `rgb >= 250`, leaves the antialiased edge — `(250,250,249)` stayed opaque and drew a white rim on green.
