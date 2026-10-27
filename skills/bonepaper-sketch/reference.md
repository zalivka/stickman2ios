# Ink engine reference

EDT sketch and marker-wash engine (`tools/bonepaper_gen/ink.py`). Distilled
from `glasses`, `wojak`, `redface`, `lineflower`, `busnight`, and `whale`.

## Why EDT + L-corner pruning

| Old (`build.py` copies) | Failure | `ink.py` fix |
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
   - A white pocket is not an interior. The 45 px close turns the paper between two strokes that nearly touch — stem and leaf, arm and body, stick and head — into a pocket, and `background-gap` only rejects pockets that reach the bottom of the drawing. Tint a pocket only when `pockets.png` shows it inside one outline. If deleting one of the two bounding strokes joins that pocket to the page background, it is the gap between them. The tulip wedges (`296,236` left of the stem, `322,309` right of it) were logged as `(white)` and are that gap.

### 2. Hatch & outline geometry rules (`hatch_region` & `sloppy_outline_strokes`)

Controlled by `--slop FLOAT` (`default = 1.0`, `0.0` = clean/tight, `>1.0` = looser):

1. **Controlled wide wash (`hatch_region(..., slop=1.0)`)**:
   - Uses a light inward buffer (`-0.15 * brush_size`) so wide round brush caps (`size = 26..30 px`, randomized `(1 - 0.12*slop)..(1 + 0.16*slop)×`) kiss or slightly cross the boundary without shooting far outside.
   - Scales variation with `slop`: row spacing jitter (`1 ± 0.2*slop`), endpoint jitter (`±3.0*slop px`), y-tilt (`±2.8*slop px`), midpoint bow (`±2.5*slop px`), angle wobble (`±2.2*slop°`), and stroke jitter (`0.4 + 0.55*slop`).
   - `--tint-size < 30` is a tight fill: the brush is `min(tint_size, short * 0.72)`, the cap is inset, rows overlap, and stroke jitter drops to `0.15 + 0.25*slop`. Angle wobble does not get that extra cut, but `±2.2*0.1°` is still a ruled comb. The reviewed hand-drawn fill is `--slop 0.7` with a different `@angle` on each pocket. Strokes that share one angle stay parallel no matter the slop.
2. **Sloppy region outline (`sloppy_outline_strokes(..., slop=1.0)`)**:
   - At `slop <= 0.05`, draws a single closed ring (`closed=True`).
   - Otherwise coarsens `geom.exterior` (`simplify(2.0 + 5.5*slop)`), perturbs control points (`±4.5*slop px`), splits the perimeter into 3 overlapping open arcs with `(2.0*slop)..(7.0*slop) px` tangent tail overshoots, and draws them with `jitter = 0.8 + 1.4*slop` so the border looks loosely hand-sketched.
3. **Serpentine tip linking (avoiding bald spike tips & `SLOP` crashes)**:
   - `hand.py` fatally aborts on any stroke with travel `< 12 px` (`shape_lint.SLOP`), and raises `IndexError: list index out of range` (`start = samples[0]`) when a curved or hooked stroke with raw reach `13..14 px` shrinks below `12 px` after `simplify(1.0)` + Catmull-Rom + wobble. `ink.py` guards stroke chains at `reach < SLOP + 3` (`15 px`) and stretches kept short ticks to `15.6 px`.
   - Slicing hair spikes or acute corners produces short scanlines (`3–12 px`). Dropping them leaves white uncolored tips; connecting *every* scanline draws ugly boundary lines across wide bays.
   - Rule: link a scanline to the active chain **only** when either segment is `< SLOP + 1` (13 px) **and** the step between their endpoints is `<= 1.9 * spacing`. Keep long scanlines independent with alternating direction (`flip = not flip`).
4. **Two-pass `--tint` for grain & gap-free coverage (`pirate_roller`)**:
   - A single `--tint` pass (`spacing = 21`) on a long diagonal shape can leave narrow white paper slits between adjacent strokes.
   - Passing two `--tint` specs with slightly different colours and angles (e.g. `--tint "auto:#C08238@-26" --tint "auto:#D89E54@-24"`) seeds each pass independently (`seed = 100 + spec_i * 17 + ti`), filling inter-row slits while creating a two-tone surface/wood-grain wash.

## Shaded photo on white paper → synthetic line art (`pirate_roller`)

Feeding a continuous-tone product photo directly into `ink.py sketch` fails badly: `ink_hysteresis` looks for near-black pixels (`luma < 55`) or sharp local contrast (`>= 40`). On a lit 3D object (like warm brown wood on white paper), the sunlit upper edge has almost zero luma contrast against white paper and disappears, while the dark underside shadow becomes a floating gray blob.

To convert a clean object photo into a `bonepaper-sketch` sketch + wash:

1. **Crop UI chrome / marketplace captions** (`Хуй пирата / 999 ₽`, grey letterbox bars) before fitting the page.
2. **Extract the object silhouette** against white paper using chroma + luma (`(spread >= 25) | (luma < 225)`), closed with `binary_closing(..., ones(7, 7))`.
3. **Build synthetic ink**:
   - **Outer contour**: `sil & ~binary_erosion(sil, ones(5, 5))` (5 px wide → EDT half-width `2.5` → crisp `size = 5.0` stroke).
   - **Internal structural seams**: inside `binary_erosion(sil, ones(6, 6))`, threshold Difference of Gaussians (`gaussian_filter(luma, 4.0) - gaussian_filter(luma, 1.0) >= 7.5`) and keep connected components `>= 60 px` so wood grain noise is ignored while turned-wood collar grooves survive.
4. **Run `ink.py sketch`** on the synthetic line-art PNG with two `--tint` washes along the object's main axis (`@-26` / `@-24`) using the photo's median object tones and `--no-budget-check` (since the source is a synthetic contour).

## Flat fills that must stay fills

On white paper the ink core is `luma < 55`. Any `luma < 90` pixel connected to that core is ink too. A fill darker than that, sharing the outline stroke, welds to the stroke and is stamped black. It never shows up as a colored pocket, so `--tint` cannot paint it.

- `#4a3428` (luma ~57) and `#6b4226` (luma ~82) vanished this way. `#8d5a32` (luma ~101) and `#c4956a` stayed pockets.
- A second dark mark inside the same outline (a `#2a1e18` char, two coal strokes stacked) joins the same blob. A core that should only shift the pocket median is `stroke="none"`.
- SVG `opacity` does not survive rasterization as a pocket. `#888` at `opacity="0.3"` on white becomes near-white and is logged `(white)` or missed. Bake the fade into RGB: `255*(1-a) + gray*a`.

`painted 0` after a pocket was printed means the hatch was discarded. `_wash_keys` drops reach `< 15` px and `hatch_region` drops length `< 13` px. A coal or thin log whose long axis is shorter than that paints nothing even though the seed is right. Point `@angle` along the long axis, or enlarge the shape. A brush bigger than the short side insets the pocket empty: a ~23 px-tall log painted 0 at `--tint-size 14` and painted at 8.

The wash exists only inside closed ink. Deleting the source stroke to hide an outline deletes the pocket. Sketch with the stroke, then remove the `<polyline stroke="#222222">` you do not want from `bg.svg` and re-raster (`rsvg-convert`). The wash strokes are already underneath.

`glue_chains` writes one polyline for ink that touches. A log outline that touches a puff is one `points` list: the wood run, then the climb into the smoke. Dropping that polyline because its bbox enters the smoke deletes the log. Split the point list on the boundary and keep the run that stays on the wood (on the smoke sheet that was `y >= 340` in padded SVG coords).

`--tint` specs contain `#`. In zsh an unquoted value is a comment, and argparse rejects a single token `"--tint 320,200:#C4956A@4"`. Pass two arguments, `--tint` and `320,200:#C4956A@4`, from a list rather than an unquoted shell variable.

## Deliver the strokes on transparency

Tracing needs the white page. `bg.svg` starts with `<rect x="40" y="40" width="640" height="480" fill="#FFFFFF"/>`, and `bg.png` is that page rasterized. That PNG is the proof sheet, not the sprite.

Anything that will be shown off white paper — an `.ati` bone bitmap, a sticker, a gif on a colored scene — is rasterized from the strokes alone:

1. Delete the `#FFFFFF` paper rect.
2. `rsvg-convert -f png -b none`. The stroke edge is paint color at partial alpha, not paint blended into white.

Do not composite onto white and then erase near-white pixels. A cutoff of `rgb >= 250` keeps `(250,250,249)` fully opaque. On a dark canvas that one pixel is a white rim around every puff and every black outline. The edge was already mixed with white in the bitmap, so no later threshold can recover the paint color.

## Ink budget gate (`ink_budget`)

 Compares `src_fit` (`ink_hysteresis` mask) against `bg.png` downscaled to 640×480 across an 8×8 grid:
- **Solid mode**: output mark is `max(R,G,B) < 90`, max ratio drift `2.5×`.
- **Wash mode (`--wash`)**: output mark is `luma < 200`, max ratio drift `3.5×`. Using `luma < 200` catches gray marker washes on hair while ignoring pale skin tints like `#FCE4DC` (`luma ≈ 234`) that sit on white paper.
