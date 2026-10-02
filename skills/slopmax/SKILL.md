---
name: slopmax
description: >-
  Redraws Stickman bones, scenes, and backgrounds with the BonePaper sloppy
  brush (brush_svg, jitter 0.5, brush 14). Use when the user says slopmax,
  sloppy brush, BonePaper trace, partial fills, stars on a background, or
  asks to redraw a bitmap bone or a shape scene into that hand-drawn look.
---

# Slopmax

Redraw with the existing tracer. Do not reimplement the hand, and do not edit `hand.py`.

This is not [restyle-svg-item](../../.cursor/skills/restyle-svg-item/SKILL.md). That skill runs `item_restyle.py` on an SVG pack item and does not write an `.ati`.

Full tables, the joint formula, scene rules, and pack storage are in [reference.md](reference.md).

## Run

| What | Where |
|------|--------|
| Python | `tools/bonepaper_gen/.venv/bin/python`. Plain `python3` has no Pillow. |
| Tracer | `tools/bonepaper_gen/out/bluehairsvg/build.py` (`brush_svg`) |
| Item or scene packer | `tools/bonepaper_gen/out/camera/build.py` |
| One-item runs | `out/sun`, `out/shuttle`, `out/earth`, `out/space_rest`, `out/lion` |

## Brush

`JITTER = 0.5`, brush 14, `PAD = 40`, `SAMPLE = 4`.

| Shape | Test | Draw |
|-------|------|------|
| Limb | short side `< 42` and long side `> short × 2.2` | One stroke down the long axis. Width is the short side, clamped to 14…48. Inset each end by half that width. |
| Compact | anything else with at least 4 corners | Flat fill, then closed outline, then one tap per colour still inside. Brush is 14 when the short side is `≥ 42`, otherwise `max(6, short × 0.4)`. |

A fill whose area is more than 85% of the padded canvas is a leak. Stop.

A large outline drawn as a 24-gon shows facets under a 14 px brush. Sample it so `hand.poly` edges are about 5 px. `svg_export` simplify tolerance 0.25 affects the fill path only, not the stroke ring.

## Partial fills

A tap recolours only the colour under the tap. Count the colours inside the outline and tap each one.

Paint the flat fill when the shape is drawn. `_stamp` in `brush_svg` appends `buffer(1.5)`, then the outline, then a tap for any colour still showing inside. A block of fills spliced under the whole SVG is covered by whatever was drawn earlier. That is how five lunar-base windows stayed half wall.

## Strokes and stars

A stroke that never travels 12 px raises `SystemExit`. A star is two crossing strokes (a plus), not a 1 px dot.

Stars go behind every other object. Dim them (source opacity × 0.4 over the sky). Size comes from the radius. Give them slightly different colours. Splice their strokes to the first non-sky layer.

## Bones and scenes

Do not crop a bone to its alpha box. A crop moves the joint, and two frames cropped apart will not share one.

Name every frame of one bone `bm_<id>_state_<n>.png` with the same `<id>`. `<n>` matches that row's `<edgeAsset state>`. Android and the iOS gallery both treat that id as one bone. `sun_0.png` is a separate bone.

```text
joint in the source bitmap = (-old_x_offset, -old_y_offset)
new offset                 = -((joint + 40) * 4)
```

Rasterize the full padded canvas with `rsvg-convert` at 4×. Multiply every bone `<point>` by 4. `meta.txt` `scale` becomes the old scale divided by 4 (missing scale counts as 1, so a pack item lands at 0.25).

Playback draws `bitmap * unit.scale`. Dividing only `meta.txt` scale leaves a placed unit four times too big. Divide `scale` on each redrawn scene `<unit>`, including a `#1` / `#2` suffix. Do not trace a bubble (`common:sign`) and do not divide its scale.

Empty bitmap, no colour, and no regions are loud failures. Do not substitute a blank bone.

## Backgrounds

Draw on a 640×480 page. The brushed SVG is the padded canvas (720×560). A page SVG keeps that drawing and replaces the header:

```xml
width="640" height="480" viewBox="40 40 640 480"
```

Ship `rsvg-convert` of the editable SVG (polylines, round caps). Do not ship `replay.png`. It has no antialiasing, and a Lanczos shrink hides the steps.

Day, evening, and night of one place share one seed so the brush wobble matches. Evening puts the sun in the horizon band. Night has neither sun nor moon.

A pack background zip holds `bg.png`, `bg.svg`, and `thumb.png`. iOS draws `bg.png`. An Android pack draws `bg.svg` when both exist.
