# Bone paper: recording, generating and SVG export

Reference for agents that record real BonePaper drawings, generate drawings that look hand-made in the editor, replay them, or convert them to SVG.

**Core idea.** BonePaper keeps only a bitmap, but a user can change that bitmap in exactly four ways, all calls on `BonePaperDocument`:

- a stroke: `beginStroke` → `stampDotWorld` → `stampWorld` × n → `endStroke` or `cancelStroke`;
- a bucket fill: `fillWorld`;
- `undo`;
- `redo`.

A log of those calls (`session.json`) fully describes a drawing. The device records it, the generator writes it, and the replay and SVG tools read it. Anything replayed from a valid log could have been drawn in the editor.

## Quick start

```bash
cd tools/bonepaper_gen
python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt

.venv/bin/python forest_castle.py out/forest_castle 1        # generate: session.json + replay.png
.venv/bin/python replay.py out/forest_castle                 # re-render any session dir → replay.png
.venv/bin/python svg_export.py out/forest_castle             # → drawing.svg (polylines + fill paths)
.venv/bin/python svg_export.py out/forest_castle --flat      # → drawing_flat.svg (everything as filled paths)
rsvg-convert -w 640 -h 480 out/forest_castle/drawing.svg -o /tmp/check.png   # verify
```

## File map

| path | role |
|---|---|
| `Vendor/BonePaper/Sources/BonePaper/BonePaperDocument.swift` | Paint buffer, stroke and fill engine, undo. Owns `recorder`; calls it inside each drawing method. |
| `Vendor/BonePaper/Sources/BonePaper/BonePaperCanvas.swift` | `BonePaperDrawView`: touches → document calls. Feeds the recorder raw touches and zoom. |
| `Vendor/BonePaper/Sources/BonePaper/BonePaperRecorder.swift` | Recorder: builds the log, saves the session folder. |
| `Vendor/BonePaper/Sources/BonePaper/BonePaperScreen.swift` | `apply()` saves the recording (`#if DEBUG`) and exports. |
| `Vendor/BonePaper/Sources/BonePaper/BonePaperToolbar.swift` | Brush limits (`BonePaperBrush.sizeRange`, `opacityRange`), colour presets (`BonePaperColorStore.presets`). |
| `at_elements/Info.plist` | `UIFileSharingEnabled = true`, so Documents is visible in Finder. |
| `tools/bonepaper_gen/hand.py` | Hand model: shape key points → log ops. |
| `tools/bonepaper_gen/forest_castle.py`, `space_station.py` | Example scenes; use them as templates. |
| `tools/bonepaper_gen/replay.py` | Approximate Pillow renderer for any `session.json`. |
| `tools/bonepaper_gen/svg_export.py` | `session.json` → SVG via `shapely`. |
| `tools/bonepaper_gen/requirements.txt` | Pinned `pillow` and `shapely`; the SVG output is only byte-stable with these versions. |
| `tools/bonepaper_gen/out/<scene>/` | Generated `session.json`, `replay.png`, SVGs. |

Callers of BonePaper in the app:

- `SkeletonScreen.swift`: bone mode, drawing on a bone with an onion-skin image.
- `BgAnimatorScreen.swift`: sheet mode, drawing a background on a fixed page.

## Coordinate systems

| system | range | used by |
|---|---|---|
| **world** | 0…2048 square (`BonePaperDocument.maxSide`), y down | Document API, the log, touch → `worldPoint` |
| **page** (document px) | 0…width, 0…height, y down | `result.png` (1×), SVG, `hand.py` scene code |
| **buffer** | page × `sample` (2) | Internal paint buffer, fills, sheet-mode export |
| **bitmap** | page, y flipped | Internal only (`bitmapFromWorld`); never in the log |

The page sits centred in the world: `originX = (2048 - width) / 2` and `originY = (2048 - height) / 2`, both integer division.

- A 640×480 sheet has origin (704, 784).
- A 512×512 free document has origin (768, 768).
- Page from world: `page = world - (origin - extra)`, where `extraLeft`/`extraTop` come from the log's `final` block.
- Example: world (1000, 1000) on a 640×480 sheet is page (296, 216).

**Growth:**

- Free and bone documents (`fixed = false`) grow when a stroke goes past the edge. Growth happens in 64 px chunks, up to 2048. Each growth moves the origin and increases `extraLeft`/`extraTop`.
- Sheets (`fixed = true`) never grow; strokes past the edge are clipped.
- World coordinates of old points stay valid after growth, which is why the log stores world coordinates.

The draw view's bounds are the 2048 world square, so `touch.location(in: paperView)` is already a world point at any zoom. The stroke start threshold is therefore 12 world px regardless of zoom.

## Editor mechanics and constants

### Touch → document calls (`BonePaperDrawView`)

- **Touch down:** remembers the world point; nothing is drawn.
- **First move ≥ 12 px from the down point** (`strokeSlop`): calls `beginStroke`, then `stampDotWorld(downPoint)`, then `stampWorld(downPoint → current)`. Moves shorter than 12 px draw nothing, so a pen tap draws nothing and becomes a `noop` in the log. The first segment is always a straight line from the down point.
- **Each further move:** `stampWorld(last → current)`, using only the event's main touch. Coalesced samples go to the log's `raw`, not to the drawing.
- **Lift:** `endStroke`. With the fill tool, lift calls `fillWorld(lastPoint)` instead.
- **A second finger or a pinch:** `cancelStroke`. The stroke is discarded and its undo snapshot popped; the log records `end: "cancel"`.
- **While a fill is running** (`document.filling`), all touches are ignored and a "Filling" overlay is shown.

### Stroke rendering

- Each segment is a round-capped, round-joined line of width `size`, at full alpha, drawn into a separate stroke layer. The start dot is a filled circle.
- `endStroke` merges that layer into the buffer at the stroke's `opacity`. Self-overlap within one stroke never darkens; separate strokes stack.
- The eraser draws with `.clear` blend straight into the buffer.

### Bucket fill (`fillWorld`)

A contiguous, 4-connected fill over the 2× buffer, run asynchronously on a serial queue. The tapped pixel decides the mode:

- **Empty space** (tapped alpha < 26/255): the fill grows through pixels whose `coverDistance` stays small, then paints *behind* (destination-over) into those pixels. It also grows `fillRing` = 3 buffer px (1.5 page px) into the anti-aliased edges of lines. Opaque ink is claimed but never crossed. In effect, any fairly opaque line of any colour stops it; a gap wider than about 1 px leaks.
- **Recolour** (tapped alpha ≥ 26): the fill grows through painted pixels whose `colorDistance` (OKLab) is close, and writes the new colour at each pixel's own alpha. If the tapped pixel isn't dark ink, dark pixels act as walls (`ink = alpha·(1 − L) > limit`).

| constant | value | meaning |
|---|---|---|
| `fillNeighbourLimit` | 0.06 | Maximum OKLab step from the neighbouring pixel |
| `fillSeedLimit` | 0.20 | Maximum OKLab distance from the tapped pixel |
| `fillInkLimit` | 0.55 | Above this is a wall (recolour mode) |
| `fillRecolorAlpha` | 26 | Tapped alpha at or above this means recolour mode |
| `fillRing` | 3 buffer px | Growth under line edges (empty mode) |
| `fillStreakCap` / `fillSeedStep` / `fillInkStep` / `fillInkMax` | 4 / 0.1 / 0.1 / 0.95 | Repeated taps with the same colour and opacity loosen the limits: neighbour × (1 + streak), seed + 0.1·streak, ink + 0.1·streak |

### Other limits and defaults

- **Undo:** the stack keeps at most 5 snapshots (`undoCap`). A snapshot is pushed at `beginStroke` and at each fill.
- **Brush size:** 4–48, default 14; the eraser also defaults to 14.
- **Opacity:** 0.05–1, default 1.
- **Colour:** default black.
- **Presets:** `#E63836 #FF9900 #FCD936 #7DB343 #1F87E6 #8F24AB #000000 #9E9E9E #FFFFFF #FFE0B3 #8C6E63 #26C7D9 #F58FB0`. Custom colours are stored in UserDefaults under `bonepaper.custom_colors`.
- **Tools:** pen, eraser, fill. The pan tool is hidden (`showsMoveTool = false`); two fingers pan and pinch zoom (0.1–8).
- **Export:**
  - Free and bone modes: `export()` returns a 1× PNG plus `extraLeft`/`extraTop`.
  - Sheet mode: `exportBuffer()` returns the 2× buffer. The paper colour is not baked in; the export is transparent where nothing was painted.

## Recording on the device

**Debug builds only:** the save call in `BonePaperScreen.apply()` sits inside `#if DEBUG`. Release builds still record into memory but never write.

### Hooks

- Document methods call `recorder.begin / dot / line / end / cancel / fill / undo / redo`, each after that method's `if filling { return }` and bounds guards. Anything the log contains really happened.
- The draw view calls:
  - `touchDown(samples, input:)` in `touchesBegan`;
  - `touchMoved(samples)` in `touchesMoved` and `touchesEnded`, where `samples` are the coalesced touches as (world point, `UITouch.timestamp`);
  - `touchUp()` after `finishStroke`;
  - `touchAbort()` on pinch, a second finger or cancel;
  - `zoom = …` in `setZoom`.
- Samples arriving between `touchDown` and the stroke's `begin` are carried into that stroke's `raw`. Samples of a gesture that no op consumes become a `noop` on `touchUp`. Aborted gestures are dropped.

### Recorder checks

The recorder calls `fatalError` if calls arrive in an impossible order:

- `dot` or `line` without an open stroke;
- `begin` while a stroke is open;
- a `line` that doesn't continue from the previous point (tolerance 0.01);
- brush size, colour or erase changing inside a stroke;
- `fill` or `save` while a stroke is open.

### Saved files

On **Apply** the recorder writes `Documents/BonePaperRecordings/<yyyyMMdd-HHmmss>/`, named after the session's start time:

| file | when | content |
|---|---|---|
| `session.json` | always | The log (schema below), JSON with sorted keys; nil fields omitted |
| `result.png` | always | What the caller got: sheet mode 2× buffer, other modes 1× |
| `base.png` | the document started from an image | Bone and free modes: the `source` image at 1×. Sheet mode: the reopened buffer at 2×. |
| `onion.png` | bone mode with onion skin | 2048×2048 world-sized reference image |

**Back** (leaving without Apply) saves nothing.

### Getting the files

- **Finder:** select the device → Files → at_elements → drag out `BonePaperRecordings`.
- **Terminal:**

  ```bash
  xcrun devicectl list devices
  xcrun devicectl device copy from --device <ID> \
    --domain-type appDataContainer --domain-identifier zalivka.at-elements \
    --source Documents/BonePaperRecordings --destination ./recordings
  ```

  `devicectl` must run outside the agent sandbox; inside it, CoreDevice times out. The device used so far is iPhone SE (iPhone12,8), identifier `6DFF0468-9398-5DD8-B92F-A1759959D19E`.

## session.json schema

### Header

| key | type | notes |
|---|---|---|
| `version` | int | 1 |
| `started` | string | ISO 8601; `"generated"` for `hand.py` output |
| `duration` | number | Seconds from editor open to save |
| `device` | string | `UIDevice.model + " " + systemVersion`, or `"hand.py"` |
| `screenScale` | number | Display scale |
| `mode` | string | `sheet` if a paper colour is set, otherwise `bone` if a bone was given, otherwise `free` |
| `worldSize` | int | 2048 |
| `sample` | int | 2 (buffer px per page px) |
| `canvas` | object | Starting `{width, height, originX, originY, fixed}` |
| `final` | object | `{width, height, extraLeft, extraTop}` at save time |
| `paper` | string? | `#RRGGBB`, sheet mode only |
| `boneStart`, `boneTip` | [x, y]? | Page px of the starting image, bone mode only |
| `base`, `onion` | string? | File names, if saved |
| `ops` | array | In time order |

### Ops

All points are `[x, y, t]` in **world** coordinates. `t` is seconds since the editor opened (same clock as `UITouch.timestamp`). Rounding: coordinates to 0.01, `t` to 0.0001, `opacity`/`zoom` to 0.001, `size` to 0.01.

| op | fields | meaning |
|---|---|---|
| `stroke` | `t`, `t1`, `input`, `erase`, `color` (absent for eraser), `size`, `opacity`, `zoom`, `points`, `raw`, `end` | `t` is when the stroke began (after the 12 px threshold); `t1` is its end. `points[0]` is the dot; each `points[i]` is a segment from `points[i-1]`. `points` times are when the call ran; `raw` times are the real touch timestamps. `raw` covers the whole gesture, including movement before the threshold. `end` is `commit` or `cancel`. |
| `fill` | `t`, `input`, `color`, `opacity`, `zoom`, `at`, `raw` | Tap at `at` (world [x, y]). Taps outside the page are not logged. |
| `undo`, `redo` | `t` | Only logged when something was actually undone or redone |
| `noop` | `t`, `input`, `raw` | A gesture that changed nothing: a pen tap under 12 px, or a fill tap outside the page. Touches during a running fill are ignored before recording and don't appear at all. |

`input` is `finger`, `pencil`, `indirect`, `pointer` or `unknown`.

### Minimal example

```json
{
  "version": 1, "started": "2026-09-25T00:34:43Z", "duration": 6.8, "device": "iPhone 17.5.1",
  "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
  "canvas": {"width": 640, "height": 480, "originX": 704, "originY": 784, "fixed": true},
  "final":  {"width": 640, "height": 480, "extraLeft": 0, "extraTop": 0},
  "paper": "#FFFFFF",
  "ops": [
    {"op": "stroke", "input": "finger", "erase": false, "color": "#000000", "size": 14, "opacity": 1,
     "zoom": 0.715, "t": 1.20, "t1": 1.45, "end": "commit",
     "points": [[1000,1000,1.20],[1014,996,1.23],[1030,998,1.25],[1044,1008,1.28],[1050,1024,1.31],
                [1044,1040,1.35],[1028,1048,1.38],[1012,1044,1.41],[1002,1030,1.43],[1001,1008,1.45]],
     "raw":    [[1000,1000,1.183],[1006,998,1.20],[1014,996,1.23],[1030,998,1.25],[1044,1008,1.28],
                [1050,1024,1.31],[1044,1040,1.35],[1028,1048,1.38],[1012,1044,1.41],[1002,1030,1.43],
                [1001,1008,1.45]]},
    {"op": "noop", "input": "finger", "t": 2.10, "raw": [[1300,900,2.10],[1302,901,2.17]]},
    {"op": "fill", "input": "finger", "color": "#FCD936", "opacity": 1, "zoom": 0.715,
     "at": [1025,1022], "t": 3.40, "raw": [[1025,1022,3.40],[1025,1022,3.47]]},
    {"op": "undo", "t": 5.10}
  ]
}
```

## Replay semantics

This is exactly what the editor did:

```text
doc = sheet mode ? BonePaperDocument(sheet: width×height, paper)       // fixed
                 : BonePaperDocument(width, height, source: base.png)  // grows
for op in ops:
  stroke: doc.beginStroke(erase, opacity)
          doc.stampDotWorld(points[0], color, size, erase)
          for i in 1..<n: doc.stampWorld(points[i-1], points[i], color, size, erase)
          end == "commit" ? doc.endStroke() : doc.cancelStroke()
  fill:   doc.fillWorld(at, color, opacity); wait until !doc.filling
  undo / redo: doc.undo() / doc.redo()
  noop:   nothing
```

- `BonePaperDocument` and its methods are `internal`. An exact Swift replayer must live inside the BonePaper module (the package has no test target yet) or those methods must be made public.
- `replay.py` is the Python stand-in:
  - strokes use a Pillow `line(joint="curve")` plus a circle at each point, at 2×, merged at the stroke's opacity;
  - fills use `ImageDraw.floodfill(thresh=60)`, which has none of BonePaper's OKLab limits, ring growth, recolour-at-own-alpha or loosening on repeated taps.
- `replay.py` raises on unknown ops, and also on `undo` and `redo`, which it doesn't implement. `svg_export.py` does handle `undo` and `redo`.
- Accuracy: on the first real recording, `replay.py` differed from `result.png` on 0.30% of pixels (threshold 40), all along edges.

## First real recording: measured numbers

A 640×480 white sheet, 66 s, 6 ops: a navy mountain outline in one stroke plus a fill, and three green loops, one of them filled.

| quantity | value |
|---|---|
| Brush / opacity / zoom | 14 / 1 / 0.715 for every op; sliders never touched, page fully on screen |
| Colours | `#1E2A58`, `#3AD235`, both custom, not presets |
| Mean speed | 500–900 world px/s |
| Point spacing | mean 8–15 px, median 6–15 px, 90th percentile 14–21 px, max about 20–25 px (one outlier of 60 in the long stroke) |
| Speed profile | Roughly constant; peak about 1.4–1.5× mean; doesn't start from zero |
| Sample rate | about 60 Hz (dt 0.016 s); `raw` ≈ `points` on this 60 Hz device |
| Loop closure | Start–end distance 14–35 px; filled loops held, since the end ran over the stroke |
| Long stroke | 2404 px in 3.65 s with 218 points (mountains plus the bottom edge in one go) |

Analysis snippet for new recordings:

```python
import json, math, statistics as st
s = json.load(open("session.json"))
for o in s["ops"]:
    if o["op"] != "stroke": continue
    p = o["points"]; d = [math.dist(p[i][:2], p[i-1][:2]) for i in range(2, len(p))]
    L = sum(d); dur = o["t1"] - o["t"]
    print(o["color"], o["size"], len(p), f"len {L:.0f} {L/dur:.0f}px/s mean {st.mean(d):.1f} max {max(d):.1f}",
          "gap", round(math.dist(p[0][:2], p[-1][:2])))
```

## Generator: `hand.py`

Scene code works in **page px** (y down). `Hand` converts to world with `origin` and appends ops to `hand.ops`.

```python
hand = Hand(seed, origin=(704, 784))       # rng = random.Random(seed); t starts at 0.5 s
hand.size = 14; hand.opacity = 1.0         # defaults, as a real user leaves them
pieces = hand.curve(keys, closed=False)    # Catmull-Rom through keys, ~2 px steps, one motion
pieces = hand.poly(keys, closed=False)     # straight segments; each corner is its own motion
hand.stroke(pieces, "#000000", closed=False, jitter=1.0, size=None)
hand.fill((x, y), "#FCD936")               # tap; jittered ±3 px
```

What `stroke()` does, in order:

1. **Loop run-on** (`closed=True`): the path continues past its start by 4–14% of its length, so a later fill holds.
2. **Wobble:** three sine waves of sideways offset along the path, wavelength 60–240 px, amplitude `0.3–0.7 × jitter × min(4, 1.2 + extent/90)`.
3. **Timing:** mean speed is drawn uniformly from 500–900 px/s per stroke. Each piece lasts `max(length/speed, 0.08 s)`. The profile is `EASE = 0.4` minimum-jerk blended with 60% constant speed. Samples are taken at 60 Hz with Gaussian tremor σ = 0.25 px.
4. **Start threshold:** `points` = the first sample plus every sample from the first one ≥ 12 px away; `raw` = all samples. A stroke that never gets 12 px from its start raises `SystemExit`.
5. **Think-time:** 0.35–1.8 s after a stroke, 0.4–1.2 s after a fill. `zoom` is logged as 0.715 and `input` as `finger`.

It's deterministic: the same scene and seed give the same log.

### Scene template

```python
from hand import Hand
import json, replay
W, H, ORIGIN = 640, 480, (704, 784)
hand = Hand(1, ORIGIN)
hand.stroke(hand.curve([(-12, 320), (320, 300), (652, 318)]), "#5DBB3F")  # ground line past both edges
hand.fill((320, 440), "#5DBB3F")                                          # fill below it
hand.stroke(hand.poly([(280, 300), (280, 220), (360, 220), (360, 300)], closed=True), "#8C6E63", closed=True)
hand.fill((320, 260), "#8C6E63")
hand.fill((320, 40), "#9ED8FF")                                           # sky last
session = {"version": 1, "started": "generated", "duration": hand.t, "device": "hand.py", "screenScale": 2,
           "mode": "sheet", "worldSize": 2048, "sample": 2,
           "canvas": {"width": W, "height": H, "originX": ORIGIN[0], "originY": ORIGIN[1], "fixed": True},
           "final": {"width": W, "height": H, "extraLeft": 0, "extraTop": 0}, "paper": "#FFFFFF", "ops": hand.ops}
```

Then write `session.json` and render with `replay.render(session)`. The scene files already do both in `main()`.

### Scene-authoring rules (learned the hard way)

1. **Anything you fill must be drawn with `closed=True`.** Otherwise the fill leaks through the gap and floods the surrounding area.
2. **Minimum feature size is about 2× the brush (≥ 22–28 px at size 14).** Castle battlements 13 px wide came out as blobs; 22 px worked.
3. **The inside of a shape you will tap must be clearly wider than the brush.** Aim for at least 20 px clear inside, and put the tap at least `size/2 + 3` px from any line (the tap jitters ±3 px). A 32×24 visor outline left almost no inside to tap.
4. **Overlapping outlines split regions; each region needs its own tap.** For example, a pine crossing the horizon needs one fill above the ground line and one on the ground. Either avoid overlaps (the forest uses non-overlapping rows) or plan a tap per region.
5. **A line dividing a same-coloured shape must cross the whole outline band:** reach radius + `size/2` + a few px past the edge. Otherwise a recolour runs along the outline around the line's end. The Mars polar cap turned the whole planet white twice until its line poked into space.
6. **Recolour behaviour:** a tap on existing paint recolours the connected area of similar colour, bounded by lines of a different colour. Filling the part of a crown that overlaps the ground works this way.
7. **Draw order that works:**
   1. background lines and their fills (ground);
   2. each object's outline, then its fill;
   3. details (stars, buttons, windows) as short strokes after the fills;
   4. the sky or wall as one final tap. It flows around everything and leaves small white pockets in closed gaps, which is realistic.
8. **Dots:** a real "dot" is a short stroke of at least 12 px. Use a dash of 14–18 px, or two crossing strokes for a star.
9. **Lines ending on the page edge:** run them 10–12 px past the edge so an edge-bounded fill (ground, floor) doesn't leak around the end.
10. **Size and length:** real scenes so far have been 35–40 strokes and 14–31 fills, about 60–80 s of drawing time. Keep brush 14 and opacity 1 unless there's a reason to change them.

### Checking a generated scene

- Look at `replay.png` for leaks and missed fills only. Do not ship it; it has no antialiasing. The device bitmap is the SVG raster — see [Shipping a generated background to the device](#shipping-a-generated-background-to-the-device).
- Compare point spacing with the real numbers above: mean about 11–13 px, max about 20–25 px. Run the analysis snippet on the generated `session.json`.
- Export to SVG and compare the render with `replay.png`; about 0.3% differing pixels is normal.

## SVG export: `svg_export.py`

It replays the log as `shapely` geometry, not traced pixels.

The model is an ordered list of `Layer(kind, geom, color, opacity, points, size, cut)`, bottom to top:

1. **Page coordinates:** `world − (canvas.origin − final.extra)`; the page is `box(0, 0, final.width, final.height)`.
2. **Stroke:** the geometry is `LineString(points).buffer(size/2, quad_segs=8) ∩ page` (a `Point` buffer for a single point). It's appended on top.
3. **Eraser stroke:** each earlier layer's geometry is reduced by the eraser's geometry and marked `cut`; empty layers are dropped.
4. **Fill:** the covered area is the union of all layer geometries so far.
   - **Tap not covered (empty paper):** the fill is the piece of `page − covered` that contains the tap. It's grown by `FILL_RING = 1.5`, clipped to the page, and **inserted at the bottom**. Empty-paper fills only paint unpainted pixels, so the bottom of the drawing order is equivalent.
   - **Tap covered (recolour):** the seed colour is the topmost layer at the tap. Take each layer's visible part (its geometry minus everything above it), keep those whose colour is within `NEIGHBOUR = 0.06` OKLab of the seed, and join them. The fill is the joined piece containing the tap, **appended on top**.
   - If the tap is in no piece, the nearest piece within 1 px is used; otherwise the script exits with an error.
5. **Undo and redo:** snapshots of the layer list are taken before every committed stroke and every fill. Cancelled strokes and `noop`s are skipped.
6. **Output** is written bottom to top after a paper `<rect>`:
   - Default mode: uncut strokes become `<polyline fill="none" stroke-linecap="round" stroke-linejoin="round">` with the recorded points, or a `<circle>` for a single point.
   - Fills, cut strokes, and every stroke in `--flat` mode become `<path>` elements. The path is simplified with a 0.25 px tolerance, and `orient(sign=1)` winds holes opposite to their outer edge, so they cut out under the nonzero rule without `fill-rule`.
   - Numbers are written with 1 decimal. Opacity below 1 becomes `stroke-opacity` or `fill-opacity`.

**Differences from BonePaper's fill:**

- no loosening on repeated taps;
- no 0.2 limit on distance from the seed colour;
- partially transparent paint counts as fully covered;
- no ink walls;
- a recolour at partial opacity becomes a semi-transparent shape on top.

None of these mattered for the scenes so far.

**Determinism:** the output is byte-identical across runs. It was checked with SHA-256 over three runs (editable `4c4be5ed…`, flat `fb5ee5a2…` for the forest). Pin the library versions with `requirements.txt`; a different GEOS or `shapely` can move vertices.

**Forest result:** 66 elements, 40 KB editable or 46 KB flat. Rendered with `rsvg-convert`, it differs from `replay.png` on 0.27% / 0.30% of pixels.

## Antialiasing

Three renderers touch the same log, and only two of them soften edges.

| renderer | strokes | fills | use |
|---|---|---|---|
| BonePaper (`CGContext` in `BonePaperDocument`) | Antialiased. `stampWorld` strokes a round-cap line into the 2× buffer; partial coverage is real alpha along the edge. | Empty-paper fills grow `fillRing` (3 buffer px, 1.5 page px) under that fringe and paint behind it, so the soft edge stays on top of the fill. | What a drawing made in the editor looks like. Not available from `replay.py`. |
| `replay.py` (Pillow `ImageDraw`) | **No antialiasing.** `line` and `ellipse` write solid pixels. | Hard flood fill (`thresh=60`), no fringe. | Leak checks only. |
| `rsvg-convert` on the editable SVG | Antialiased. Polylines have `stroke-linecap="round"` and `stroke-linejoin="round"`, and librsvg covers the edge with partial alpha. | The fill is a polygon underneath the stroke, so the stroke's soft edge covers the boundary. There is no `fillRing` and no OKLab. | The bitmap to ship. |

`replay.png` hides the missing antialiasing. Scene scripts save it at page size (640×480) by shrinking the 1280×960 Pillow image with Lanczos, and that resize blurs the steps. The full-size Pillow image does not. The first noir-city zip used that full-size image and the towers and road looked stepped on the phone.

Ship `rsvg-convert -w <width×sample> -h <height×sample>` of the **editable** SVG (polylines, not `--flat`). `--flat` turns each stroke into a filled outline polygon; the rasterizer still antialiases the polygon edge, but the round cap is an 8-segment approximation (`quad_segs=8`) instead of a true round stroke. The noir city shipped this way (`usermade:1790320375379`) looked right. It is not pixel-identical to a BonePaper replay: outlines stay visible around fills (the road curb showed up; the Pillow fill had hidden it).

## Shipping a generated background to the device

The app stores a drawn background the way `BackgroundStore.saveDrawn` does (`Shared/Background/BackgroundStore.swift`):

- Path: `Library/Application Support/at_elements/bgs/<millis>.zip`
- Chooser name: `usermade:<millis>`, folder **My backgrounds**
- Zip entries: `bg.png` and `thumb.png`
- `bg.png` is opaque, at `sample` × the sheet (1280×960 for 640×480). The paper colour is already in the SVG `<rect>`, so the raster is the flattened picture.
- `thumb.png` is 100×100, cover scale, centre crop (`BackgroundStore.thumb`).

```bash
cd tools/bonepaper_gen
.venv/bin/python svg_export.py out/noir_city -o out/noir_city/drawing.svg
rsvg-convert -w 1280 -h 960 out/noir_city/drawing.svg -o out/noir_city/bg.png
# thumb: scale = max(100/w, 100/h), centre-crop 100×100, then zip bg.png + thumb.png
OWN=$(python3.12 -c 'import time; print(int(time.time()*1000))')
xcrun devicectl device copy to --device <ID> \
  --domain-type appDataContainer --domain-identifier zalivka.at-elements \
  --source out/noir_city/${OWN}.zip \
  --destination "Library/Application Support/at_elements/bgs/${OWN}.zip"
```

`devicectl` must run outside the sandbox. Replacing an existing zip keeps the `usermade:` name (noir city is `usermade:1790320375379`). Close the chooser and pick the picture again: the scene keeps the previous bitmap until then.

### Importing on Android

The importer is `SVGHelper.readCommandsFromString` in `stickman2/fingerpaint/app/src/main/java/com/caverock/svg/SVGHelper.java`. More detail is in the `kurwa-svg-background` skill in the stickman2 repo.

- **Supported:** `path` (M/L/C/Z), `polyline`, `polygon`, `rect`, `circle`, `ellipse`, `line`; `fill`, `stroke`, `fill-opacity`, `stroke-opacity`, `stroke-width`, `opacity`; transforms apply their translation only.
- **Not read:** masks, `clipPath`, gradients, patterns, filters, `<text>`, `<use>`, `fill-rule`, `stroke-linecap`, `stroke-linejoin`. Arcs become straight lines.
- **Consequences:**
  - Erasing is built into the shapes.
  - Holes rely on winding.
  - Use `--flat` when round stroke ends must survive import. Fingerpaint's own drawing paints use round caps, but it's unconfirmed which paint imported curves are drawn with.
- **Shipping as a Stickman background:** use `stickman/app/src/main/assets/bgs/<pack>/<name>/bg.svg` plus a 100×100 `thumb.png` (cover scale, centre crop). A new pack also needs registering in `BgPresenter.FOLDER_SCENES`. Keep the central bottom of the frame quiet, because characters stand there.

## Pitfalls for agents

- **The user's rules:**
  - Don't build iOS or Android unless explicitly told to.
  - Never compile Java or Kotlin.
  - Loud failures are preferred to fallbacks.
- **Python:**
  - The system `python3.12` has Pillow but not `shapely`. Use `.venv/bin/python` for `svg_export.py`.
  - The venv is created with `python3.12 -m venv .venv`; `pip install` needs network access.
  - Plain `python3` (3.13) has neither library.
- **Sandbox:**
  - `devicectl` and writes outside the workspace (for example `/tmp`) need to run unsandboxed.
  - Keep outputs under `tools/bonepaper_gen/out/`.
- **Recording:**
  - The recorder writes only in debug builds and only on Apply.
  - Recordings are named by start time; rename folders (e.g. `…-house`) to label the subject.
- **Replay:** `replay.py` doesn't implement undo or redo and raises on them. `svg_export.py` handles both.
- **Hand model limits:** it was fitted to one 60 Hz recording by one adult. Re-fit `EASE`, the speed range, the wobble amplitude and the run-on range as more recordings arrive; they are module constants and literals in `hand.py`.

## Open items

- An exact replay through `BonePaperDocument`: either a package test target that loads `session.json` and saves a PNG, or a debug screen.
- A debug screen that loads a generated `session.json` on the device, for side-by-side and blind tests.
- 10–20 more real drawings of varied subjects (people, animals, houses) from the target users, to tune the hand model. A 120 Hz device would give real `raw` detail.
- `undo`/`redo` in `replay.py`.
