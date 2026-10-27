---
name: bonepaper-draw
description: >-
  The hand-drawn item route (tools/bonepaper_gen/flat.py draw): a python script
  describes the parts as geometry, itemkit lints, brushes, rasterizes at 4x and
  packs the .ati in one run. Use when nothing exists to trace — a new mug, hat,
  vehicle, or creature — or when the user asks for a new item built from
  shapes.
---

# BonePaper draw

For an item that has no source picture. If a bitmap or an `.ati` already exists,
this is the wrong skill: use [bonepaper-flat](../bonepaper-flat/SKILL.md) `item`
or [bonepaper-sketch](../bonepaper-sketch/SKILL.md).

Run from `tools/bonepaper_gen` with `.venv/bin/python`. Do not edit `hand.py`.

**A source SVG is the single source of truth.** When the same art also goes
through `ink.py svg` (or any other renderer), one hand-authored SVG owns the
geometry, colours, and page size; `build.py` ports its coordinates 1:1 — same
page, same palette, no redesign. Author the source at the full 640×480 page:
a small canvas forces the port to drop features to satisfy the fixed 14 px
brush and 10 px rim. Fixes land in the SVG first, then every engine re-runs.
Deviate only when the user says so.

## Command

```bash
.venv/bin/python flat.py draw out/beer_mug/build.py
```

Writes `out/<dir>/<name>.ati`, `drawing.svg`, and one review PNG per bone. Lint,
brush, 4× raster, pack — one run, about a second. `-o DIR` overrides the output
directory (defaults to the script's own).

`lint` is the same check on its own, for a shape script that is not an item:

```bash
.venv/bin/python flat.py lint out/storypic/build.py
```

## What the script is

Data, not code. `itemkit.py` does the rest, so do not write a per-job `build.py`
with its own `poly` / `disc` / zip code — those copies are what this route
replaced.

| Name | Meaning |
|------|---------|
| `NAME` | item name, used for the seed and the `.ati` |
| `W`, `H` | page size; omit only for 640×480 |
| `JOINT` | where the item attaches, in page pixels |
| `EDGE` | which edge of the item the joint sits on |
| `parts()` | the shape list, `(color, geom)` or `(color, geom, "limb"\|"compact")` |
| `underlay(hand)` | optional strokes behind the parts — a handle behind a mug |
| `details(hand)` | optional strokes on top |

The part rules (limb vs compact, the width clamps, the fill-leak limit) are in
[bonepaper-common](../bonepaper-common/reference.md).

## Worked examples in `out/`

| Script | Shows |
|--------|-------|
| `beer_mug` | handle drawn as `underlay` |
| `shotgun` | straight-edged composite |
| `corvette` | curvy vehicle — the reference for smooth multi-part bodies |

## Two failures lint does not catch

1. A shallow part is reported as `expected compact`: the limb test passed on a
   part that is visually compact. Fix the part, not the lint.
2. A stroke shorter than 12 px dies at render time inside `hand.py`. Lint cannot
   see it because the length is only known after Catmull-Rom. Lengthen the
   stroke.
