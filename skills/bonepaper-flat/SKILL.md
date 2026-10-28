---
name: bonepaper-flat
description: >-
  The region engine (tools/bonepaper_gen/flat.py). Traces a
  flat-colour picture into closed colour regions and brushes them, and redraws
  an existing .ati / .ats. Use when the user says slopmax or slopmax2 (old
  names for this engine), to
  redraw an item, scene, or flat cartoon background without writing a build.py,
  for `bg --comic` on a comic with ink over flats, or to lint a shape list
  before the brush draws it.
---

# BonePaper flat (region engine)

New to the three engines? [Three ways to draw a pine tree](../../doc/pine-styles/index.html) walks one scene through the region engine, `bg --comic` and the ink engine with real stage images and numbers.

One command replaces the per-job `build.py` copies (`out/camera`, `out/lion`, `out/sun`, …). The brush rules, joint formula, scene-scale rules, and the hand-drawn item route are in [common reference](../bonepaper-common/reference.md). This skill only says how to run them.

Run from `tools/bonepaper_gen` with `.venv/bin/python`. Do not edit `hand.py`. The tracer is still `out/bluehairsvg/build.py`.

## Commands

| Job | Command | Writes |
|-----|---------|--------|
| Item | `flat.py item newstickman:sword` or `item /tmp/lion.ati --name lion` | `out/<name>/<name>.ati`, one review PNG per bone |
| Scene | `flat.py scene ../../at_elements/demo/demo_camera.ats -o ../../at_elements/demo/demo_camera2.ats` | the `.ats`, plus every `.ati` and bone PNG in `out/<output stem>/` |
| Background | `flat.py bg picture.png -o out/picture/picture.zip` | zip with `bg.png` (1280×960), `bg.svg` (640×480 page), `thumb.png` (100×100), and the three files beside it |
| Lint | `flat.py lint out/storypic/build.py` | prints the plan, exits 1 on any issue |

**Nothing exists to trace** (a mug, a hat, a new creature): `draw`, not `item`, and read [bonepaper-draw](../bonepaper-draw/SKILL.md). The script is data — `NAME`, `W`, `H`, `JOINT`, `EDGE`, `parts()`, optional `underlay(hand)` / `details(hand)` — and `itemkit.py` does the rest. Do not write a per-job `build.py` with its own `poly`/`disc`/zip code; those copies are what this replaced. Worked examples in `out/`: `beer_mug` (handle as underlay), `shotgun`, and `corvette` (curvy vehicle, the reference). **When a source SVG exists, it is the single source of truth — port it 1:1 (coords, colours, page size), never re-invent the shape list;** see [bonepaper-draw](../bonepaper-draw/SKILL.md). The part rules, the vehicle recipe, and the two failure modes lint does not catch (a shallow part rejected as `expected compact`; a sub-12 px stroke dying at render time) are in [common reference](../bonepaper-common/reference.md), "Hand-drawn item".

**The picture is line art (strokes on one paper colour) or a hybrid with solid areas**: `bg` is the wrong tool — use **[bonepaper-sketch](../bonepaper-sketch/SKILL.md)** (`ink.py sketch`). A full-colour comic with ink on top of flats can still use `bg --comic`. Per-picture ink tests, bridge/fade rules, object removal, and canvas-contract guards are in [common reference](../bonepaper-common/reference.md); EDT constants and ink-budget rules are in the sketch reference.

`pack:item` resolves `newstickman` or `zalivka.newstickman` to exactly one `at_elements/packs/*.atp`, then reads `items/<item>.ati`.

Options:

| Option | Use |
|--------|-----|
| `--color-merge DIST` | Merge colour centres closer than DIST (default 36). Gray 128 on 160 (moon craters) and gray rocks on a cream sky need 16. |
| `--bone-class ink\|line\|color` | Force the bone class for every bitmap when the auto test is wrong. Not on `bg`. |
| `--skip-unit UNIT` | Scene only. Leave that base unit name untouched (no trace, no scale change). Repeatable. |
| `--deploy DEVICE` | `devicectl` copy to the at_elements container: `.ats` to `saved/`, `.ati` to `customs/`, background to `bgs/<millis>.zip` (`usermade:<millis>`). Runs outside the sandbox. Do not build. |
| `-o, --output` | `item`/`draw`: output directory. `scene`: the `.ats` path. `bg`: the `.zip` path. |

## What each mode does

**Item.** Classifies each bitmap, then traces with ring keep, lints, brushes, and rasterizes the full padded canvas at 4×. The offset becomes `-((joint + 40) * 4)` and points are multiplied by 4. `meta.txt` scale is divided by 4, and the unit is renamed to `@:<name>`. Output matches `out/camera` byte for byte (checked on sword, pistol, explosion, bullet).

`item` brushes whatever bitmap it is given. Point it at art that already has outlines — a rig packed from SVG `<path stroke>`, or a previous `item` run — and you get both rims and merged shades, which reads on the device as the art having been drawn twice. Feed it unbrushed art, or build from shapes with `draw`. For an articulated item that needs several bones in one `.ati`, see "A rig with several bones" and "Verifying a rig lands where the source says" in [common reference](../bonepaper-common/reference.md).

**Scene.** Every unit without `type` is traced. `type="bubble"` is left alone, and any other `type` stops the run. An `@:X` unit needs `X.ati` in the archive. A `pack:item` unit becomes `@:item`, with `item.ati` added at the archive root. The rename also covers `#n` suffixes and `&amp;` attachments. Each traced unit's `scale` is divided by 4. The background, camera, thumbs, and `metadata.txt` are copied unchanged.

**Background.** Any aspect ratio is padded to 4:3: a wide picture gets top rows in the top-row colour, and a tall one gets side columns in each side's colour. Then the picture is scaled to 640×480 with LANCZOS. The input should be flat colour. Gradients, soft shading, and translucent marks split into bands or vanish. On a small flat cartoon LANCZOS invents extra shades (one blue head becomes several blues), those become shapes, and a short ink path then dies with `stroke shorter than slop`. Resize to 640×480 with nearest-neighbor first, so this scale is a no-op.

`--comic [COLORS]` is for line art and comics, with a default of 24 colours. It writes `flat.png` beside the zip.
1. Ink is removed and the neighbouring colours grow over it. Ink is luma `< 90`, or 35 darker than the 9 px median around it, grown by 1 px. Large dark masses (EDT half-width `>= 7`, grown back 6.5 px on their own ink island) are protected and kept as flat colour — a navy suit or black silhouette is a fill, not a stroke, and no longer dies as "ink pixels left after 64 grow steps".
2. The palette is cut with an octree to COLORS. Median cut drops the small saturated parts, such as sails.
3. A 7 px mode filter erases the hatching. The flat regions are traced and brushed as usual.
4. The ink is redrawn as hand strokes on top. It is thinned to centre lines (Zhang-Suen) and split at junctions. `skeleton_paths` starts with `prune_l_corners`, the same fix as the ink engine. An 8-connected diagonal (a chin, a nose) is a junction at every staircase corner, and each crumb is then stretched to a 14 px dash. A horizontal mouth stays one stroke. Each piece is one stroke in the median source colour under it, so outlines stay near-black and grass ticks dark green. The width is the blob's ink area over its centre-line length, clamped to 3.5–7. A tick shorter than 12 px is stretched to 14.
5. An ink blob whose surroundings are more than 90% page colour is a caption or leader line, and it is dropped. Ink joined to the art stays. A flag pole touching its tower stays, and a lone stroke in the sky goes.

This is one command and about 3 s, with `--color-merge 36`. The bay picture gave 56 shapes and 310 ink strokes. Fills can come out patchy (trees, tower beige drifting to gray), but the line art carries the picture. When exact colours and parts matter, build it from shapes (`out/meme_bay/build.py`), which takes much longer.
- White (`rgb >= 240`) and black (`rgb <= 40`) are marked with sentinels before tracing and painted back afterwards (`#FFFFFF`, `#222222`). If the picture already contains a sentinel colour, the run stops.
- The largest shape that reaches at least three page edges becomes the paper `<rect>`. A sky touches the top and both sides, and the ground covers the bottom. If no shape does, the run stops.
- A page is a partition, so each compact outline is pulled in by `size/2 - 2.5` and stays inside its region. Without that, rocks drawn after a figure eat its legs.
- Leftovers that are too small to stroke are antialias fringe and are dropped.

## Lint

`shape_lint.lint(shapes, (w, h))` uses the same limb-or-compact test as `brush_svg`, so the printed table is what the brush will do. A shape is `(color, geom)` or `(color, geom, "limb"|"compact")`.

| Severity | Check |
|----------|-------|
| Fatal | Invalid geometry or area under 30. Area over 85% of the padded canvas (the fill leaks). Fewer than 3 corners. A closed loop that never gets 12 px from its start (the hand raises `SystemExit`). A shape whose stated `expect` does not match its kind. |
| Warn | A notch under 22 px inside a compact shape (the brush welds it shut). A part narrower than its own outline brush. A shape with 3 corners drawn as one stroke. Touching shapes of different colours within OKLab 0.06 (one fill tap recolours both). |

Gaps between separate shapes are not checked, because an arm touching a head is intended.

Traced runs (`item`, `scene`, `bg`) stop on fatal issues and print the warnings. `lint` treats every issue as a failure, and so does `draw`. The script must expose `parts()`, plus `W` and `H` if the page is not 640×480.

`draw` lints as its first step, so a hand-built item is one command: fix the part list, rerun `draw`, until it is clean and the picture is right. Standalone `lint` is for shape scripts that are not items (a page like `out/storypic`).
