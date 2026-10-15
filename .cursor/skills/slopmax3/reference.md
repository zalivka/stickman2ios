# Slopmax3 reference

EDT sketch and marker-wash engine (`tools/bonepaper_gen/slopmax3.py`). Distilled
from `glasses`, `wojak`, `redface`, `lineflower`, `busnight`, and `whale`.

## Why EDT + L-corner pruning

| Old (`build.py` copies) | Failure | Slopmax3 fix |
|---|---|---|
| Pass/fail `MinFilter(11)` | Brows (half-width ~5) became blob regions | Continuous `r = edt(ink)`; `r >= 7.0` is region core |
| `MaxFilter(21)` grow | Pupils swelled 25→45 px outside eyes | Exact EDT distance grow `dist(~seed) <= REGION_R - 0.5` on own island |
| `MaxFilter(5)` (+2 px) on `r >= 7` core | Left a 5-px un-grown collar in `stroke_m` → double-ringed eyes | Growing by `REGION_R - 0.5` restores the full pupil to the eyelid boundary |
| Zhang-Suen raw `skeleton_paths` | 8-connected staircase L-corners have 3 neighbours → 674 fragments on `wojak` | `prune_l_corners(sk)` removes 90° L-corner redundancies → 5 smooth strokes |
| `tracer._stamp(translate(geom, PAD, PAD))` | `_stamp` adds `PAD` internally → pupils shifted `(+40,+40)` onto cheeks | Never pre-translate for `_stamp`; for pupil-scale (`short < 36`), append `Layer("fill", translate(geom, PAD, PAD))` directly without `buffer(1.5)` or outline |
| `area / skeleton_length` per blob | 2 px lashes glued to 7.3 px cheek drew at 7.3 px | `size = 2 * median(r)` per run; split where `\|Δr\| >= 1.5`; do not glue across `\|Δsize\| >= 2.0` |
| Per-picture `PAPER` / `FADE` lambdas | Marker tips left neck/petal gaps; LANCZOS upscale halos fattened strokes | Light-paper strict black vs coloured-paper channel drop + automatic `extend_fade_ends` tangent walk |

## Coloring: Wide-Brush Marker Wash (`--wash` & `--tint`)

Replacing flat `<path fill=...>` sticker cutouts with parallel wide translucent
brush strokes creates an organic marker / watercolor wash where paper texture and
overlap tones breathe through.

### 1. Two kinds of washable regions

1. **Ink masses (`--wash`, `--wash-color`)**:
   - Extracted from `regions_m` (where `EDT >= 7.0`).
   - Only hair-scale masses (`area >= 5000` or `short >= 70`) get hatched (`size = 26..30`, `spacing = 18..21`, `opacity = 0.32`, angle alternating `-20°` / `+25°`), followed by a sloppy open-arc outline (`outline_size = 4.0 px` cap — never scale outline by `0.12 * short` on hair or it creates a 21-px border).
   - Smaller region cores (brows, pupils) **never** use `--wash` — a wide brush turns them into fat blotches.
2. **Enclosed paper pockets (`--tint SPEC`)**:
   - Line art rarely has a closed polygon around skin/face: the jaw/neck is open at the bottom, hairline/ears have gaps, and interior strokes (glasses, nose bridge, mouth) subdivide the face into multiple pockets.
   - `extract_enclosed_tint_mask(ink, regions_m, seed_spec)`:
     - Builds a temporary barrier via padded `binary_closing(ink_pad, ones(45, 45))` (padding with `False` prevents `scipy.ndimage.binary_closing` border-erosion artifacts) plus a bottom-collar seal across the lowest ink row span.
     - Floods from the page borders; inverts to get `inside_coarse`.
     - Regrows `interior` up to 120 steps inside `allowed = ~binary_dilation(ink | reg, 3x3) & row_span & inside_coarse` so narrow corridors (like a neck) fill completely without dilating `barrier` bridges out into open sky bays between separate objects (e.g. between a held stick/club and the head).
     - For `auto`, welds adjacent interior pockets across thin interior strokes via `binary_closing(interior, ones(15, 15)) & ~binary_dilation(reg, 3x3)`. For an exact `x,y` seed, selects the unwelded connected component first (so adjacent differently-colored pockets like a brown club and pink face don't merge) and then runs the `15×15` closing on that single pocket to weld internal feature holes (mouth, nose, collarbone) so the inset buffer in `hatch_region` doesn't split the wash.
   - Painted **first** (underneath ink regions and strokes) at `opacity = 0.45, size = 30.0, spacing = 21`.
   - Syntax:
     - `--tint "#FCE4DC"` or `--tint "auto:#FCE4DC@25"` → largest enclosed pocket.
     - `--tint "350,250:#FCE4DC@-15"` → pocket containing `(350, 250)` in 640×480 page coords.

### 2. Hatch & outline geometry rules (`hatch_region` & `sloppy_outline_strokes`)

Controlled by `--slop FLOAT` (`default = 1.0`, `0.0` = clean/tight, `>1.0` = looser):

1. **Controlled wide wash (`hatch_region(..., slop=1.0)`)**:
   - Uses a light inward buffer (`-0.15 * brush_size`) so wide round brush caps (`size = 26..30 px`, randomized `(1 - 0.12*slop)..(1 + 0.16*slop)×`) kiss or slightly cross the boundary without shooting far outside.
   - Scales variation with `slop`: row spacing jitter (`1 ± 0.2*slop`), endpoint jitter (`±3.0*slop px`), y-tilt (`±2.8*slop px`), midpoint bow (`±2.5*slop px`), angle wobble (`±2.2*slop°`), and stroke jitter (`0.4 + 0.55*slop`).
2. **Sloppy region outline (`sloppy_outline_strokes(..., slop=1.0)`)**:
   - At `slop <= 0.05`, draws a single closed ring (`closed=True`).
   - Otherwise coarsens `geom.exterior` (`simplify(2.0 + 5.5*slop)`), perturbs control points (`±4.5*slop px`), splits the perimeter into 3 overlapping open arcs with `(2.0*slop)..(7.0*slop) px` tangent tail overshoots, and draws them with `jitter = 0.8 + 1.4*slop` so the border looks loosely hand-sketched.
3. **Serpentine tip linking (avoiding bald spike tips & `SLOP` crashes)**:
   - `hand.py` fatally aborts on any stroke with travel `< 12 px` (`shape_lint.SLOP`), and raises `IndexError: list index out of range` (`start = samples[0]`) when a curved or hooked stroke with raw reach `13..14 px` shrinks below `12 px` after `simplify(1.0)` + Catmull-Rom + wobble. `slopmax3.py` guards stroke chains at `reach < SLOP + 3` (`15 px`) and stretches kept short ticks to `15.6 px`.
   - Slicing hair spikes or acute corners produces short scanlines (`3–12 px`). Dropping them leaves white uncolored tips; connecting *every* scanline draws ugly boundary lines across wide bays.
   - Rule: link a scanline to the active chain **only** when either segment is `< SLOP + 1` (13 px) **and** the step between their endpoints is `<= 1.9 * spacing`. Keep long scanlines independent with alternating direction (`flip = not flip`).
4. **Two-pass `--tint` for grain & gap-free coverage (`pirate_roller`)**:
   - A single `--tint` pass (`spacing = 21`) on a long diagonal shape can leave narrow white paper slits between adjacent strokes.
   - Passing two `--tint` specs with slightly different colours and angles (e.g. `--tint "auto:#C08238@-26" --tint "auto:#D89E54@-24"`) seeds each pass independently (`seed = 100 + spec_i * 17 + ti`), filling inter-row slits while creating a two-tone surface/wood-grain wash.

## Shaded photo on white paper → synthetic line art (`pirate_roller`)

Feeding a continuous-tone product photo directly into `slopmax3.py sketch` fails badly: `ink_hysteresis` looks for near-black pixels (`luma < 55`) or sharp local contrast (`>= 40`). On a lit 3D object (like warm brown wood on white paper), the sunlit upper edge has almost zero luma contrast against white paper and disappears, while the dark underside shadow becomes a floating gray blob.

To convert a clean object photo into a `slopmax3` sketch + wash:

1. **Crop UI chrome / marketplace captions** (`Хуй пирата / 999 ₽`, grey letterbox bars) before fitting the page.
2. **Extract the object silhouette** against white paper using chroma + luma (`(spread >= 25) | (luma < 225)`), closed with `binary_closing(..., ones(7, 7))`.
3. **Build synthetic ink**:
   - **Outer contour**: `sil & ~binary_erosion(sil, ones(5, 5))` (5 px wide → EDT half-width `2.5` → crisp `size = 5.0` stroke).
   - **Internal structural seams**: inside `binary_erosion(sil, ones(6, 6))`, threshold Difference of Gaussians (`gaussian_filter(luma, 4.0) - gaussian_filter(luma, 1.0) >= 7.5`) and keep connected components `>= 60 px` so wood grain noise is ignored while turned-wood collar grooves survive.
4. **Run `slopmax3.py sketch`** on the synthetic line-art PNG with two `--tint` washes along the object's main axis (`@-26` / `@-24`) using the photo's median object tones and `--skip-budget` (since the source is a synthetic contour).

## Ink budget gate (`ink_budget`)

 Compares `src_fit` (`ink_hysteresis` mask) against `bg.png` downscaled to 640×480 across an 8×8 grid:
- **Solid mode**: output mark is `max(R,G,B) < 90`, max ratio drift `2.5×`.
- **Wash mode (`--wash`)**: output mark is `luma < 200`, max ratio drift `3.5×`. Using `luma < 200` catches gray marker washes on hair while ignoring pale skin tints like `#FCE4DC` (`luma ≈ 234`) that sit on white paper.
