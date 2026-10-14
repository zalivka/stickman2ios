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
     - Builds a temporary barrier via `binary_closing(ink, ones(45, 45))` plus a bottom-collar seal across the lowest ink row span.
     - Floods from the page borders; inverts to get `inside_coarse`.
     - Regrows `interior` up to 24 steps inside `~binary_dilation(ink | reg, 3x3)` constrained to each row's `[min_ink_x, max_ink_x]` span so it meets the true hairline (`y >= 27`) and cheek contours without leaking out of open gaps.
     - Welds adjacent interior pockets across thin interior strokes via `binary_closing(interior, ones(15, 15)) & ~binary_dilation(reg, 3x3)` so forehead, glasses lenses, and cheeks merge into one continuous face silhouette instead of stopping at the glasses frame.
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
   - `hand.py` fatally aborts on any stroke with travel `< 12 px` (`shape_lint.SLOP`).
   - Slicing hair spikes or acute corners produces short scanlines (`3–12 px`). Dropping them leaves white uncolored tips; connecting *every* scanline draws ugly boundary lines across wide bays.
   - Rule: link a scanline to the active chain **only** when either segment is `< SLOP + 1` (13 px) **and** the step between their endpoints is `<= 1.8 * spacing`. Keep long scanlines independent with alternating direction (`flip = not flip`).

## Ink budget gate (`ink_budget`)

 Compares `src_fit` (`ink_hysteresis` mask) against `bg.png` downscaled to 640×480 across an 8×8 grid:
- **Solid mode**: output mark is `max(R,G,B) < 90`, max ratio drift `2.5×`.
- **Wash mode (`--wash`)**: output mark is `luma < 200`, max ratio drift `3.5×`. Using `luma < 200` catches gray marker washes on hair while ignoring pale skin tints like `#FCE4DC` (`luma ≈ 234`) that sit on white paper.
