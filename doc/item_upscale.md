# Upscale a template item 2× from its SVG

Double a `template.basic` item that ships vector source: bone points, SVG commands, and the bone bitmaps. The iOS pack is `at_elements/packs/template.basic.atp`. Leave the Android copy of that pack alone.

Done this way: `trex`, `man1`, `man2`, `dog`, `catapult`, and `gun` (the pistol; there is no `handgun` item). Pack `meta.txt` `version` is 8 after those edits.

## What stays

| Field | Why |
|---|---|
| Item `sname`, unit name, bone ids, `par` / `fixed` / `attachable` | System ids. Only `x` and `y` on `<point>` change. |
| `meta.txt` inside the `.ati`, including `"scale": 0.5` | Placement scale. Bones are already 2×, so a newly dropped item is twice as big on the page. |
| Kurwa canvas on the SVG (`width`, `height`, `viewBox`, usually `2232×1080`, `2460×1080` on the gun) | Editor page, not the bitmap. Path coordinates live in bone space and are often negative, outside that viewBox. |
| An edge with no `svg=` | Nothing to redraw. The gun’s `bm_6176_state_0.png` is a 1×1 transparent connector at offset `0, 0`. Leave it. |

## Coordinate space

A bone bitmap is drawn in bone space: `+x` runs from the start point along the bone, then the bone’s `atan2` rotates that into the pose. `x_offset` / `y_offset` are the bitmap’s top-left in that space (`x_offset` is `-mXPad` after the transparent trim).

The SVG `<path d>` numbers are the same space. Playback uses the PNG, not the SVG. The SVG is the re-edit source, so after the upscale its numbers must match the new PNG: 1 SVG unit = 1 bitmap pixel.

## Steps

1. Unzip `items/<name>.ati` out of the `.atp`.
2. For each `svg/v_<id>_state_0.svg`:
   - Multiply every number in each `d="..."` by 2.
   - Multiply `stroke-width` by 2 (`4.6` → `9.2`, `5.75` → `11.5`). A width of `0` stays `0`.
   - If an `<image>` has `transform="matrix(...)"`, multiply all six matrix numbers by 2. Do not rename `svg_embedded/` or the `dbid` in the href; the filename encodes the PNG’s pixel size.
3. Rasterize the paths with `rsvg-convert -f png -b none`. Do not render the 2232×1080 canvas.
   - Bounds are the control-point box of every path, outset by `stroke/2 + 1` (the same pad as `PathCommand.boundingBox`).
   - Snap that box to integers and use it as the SVG `viewBox`, with `width`/`height` in px equal to the box. Then 1 unit is 1 pixel.
   - Trim fully transparent edges.
   - `x_offset = viewBoxLeft + trimLeft`, `y_offset = viewBoxTop + trimTop`.
4. Multiply every `<point x y>` by 2. Keep the original number of decimal places (`94.32092` → `188.64184`, `-319.0` → `-638.0`). The base stays `(0, 0)`.
5. Write those offsets onto every `<edgeAsset>` that uses the bitmap. Shared art (one PNG on two legs) keeps one pair of offsets.
6. Rebuild `poster.png` (480, transparent) and `thumb.png` (196, white) by drawing the bones in `weight` order with the same transform as `FrameRasterizer.drawBitmaps`. Fit the pose into about 88% of the frame. Skip a poster the item never had (`gun`).
7. Put the `.ati` back and bump the pack `meta.txt` `version` by 1 so the bundle is a new pack.

Check the composite before repacking. A part that no longer meets its joint means the offset and the bitmap came from different boxes.

## When the SVG is already 2× the PNG

`gun` failed the plain double. Its path box was already about twice the saved PNG (legacy command space: command units ≈ 2 × bitmap pixels). Doubling the `d` numbers and rasterizing 1:1 made bitmaps ~4× (`511×289` → `2041×1154`) while the bones only doubled, so the art was twice the skeleton.

For that item, leave the SVG numbers as they were and rasterize them 1:1. The PNG comes out ~2× (`511×289` → `1021×578`) and the new offset is about 2× the old one (`-103.6` → `-207`). Bones are still doubled. The stored SVG then matches the new PNG 1:1, which is what a later re-edit will rasterize.

Tell the two cases apart before scaling: rasterize the SVG unchanged and compare to the current PNG. About the same size means scale the paths. About twice the PNG means the vector is already the 2× source; only rasterize it and scale the points.

## man2 torso

`svg/v_95_state_0.svg` is an opaque blue path over `svg_embedded/svg_bm_436x108_….png`. The href is `data:image/png;dbid,…`, which `rsvg-convert` cannot load, and the path covers the image anyway. Rasterize the path. Scale the matrix from `matrix(0.50, 0, 0, 0.50, -29, -28)` to `matrix(1.00, 0, 0, 1.00, -58, -56)` and keep the embedded PNG at 436×108 so the dbid still matches. Displayed size doubles because the transform scale doubled.
