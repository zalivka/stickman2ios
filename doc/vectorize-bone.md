# Vectorize a bone bitmap, then redraw it with the sloppy brush

The intro man (`AT_Man.ati` inside `tutorial/intro.ats`) was turned into the custom item `@:bluehairsvg` by tracing each bone PNG to outlines and stroking those outlines with the BonePaper hand. The script is `tools/bonepaper_gen/out/bluehairsvg/build.py`.

The source is the raster, `bm_*_state_0.png`. Black marks are dropped. What remains is split by colour, and each blob becomes a simplified polygon. That polygon is what gets brushed.

## Colour split

Work on solid pixels only (`alpha > 200`). Drop white (`rgb >= 240`) and the black ink (`rgb <= 24`), plus a one-pixel fringe around that ink so the dark edge of a black stroke is not its own colour. Gray limbs (low saturation, peak `>= 70`) stay. A near-black outline such as `#2C2C2B` does not.

Bucket the remaining pixels into flat colours: round to 16, then merge centres within 36. Assign every solid pixel to the nearest centre. A blob under 40 pixels is ignored. The colour written later is the median of the solid pixels in that blob, not the rounded centre.

Black strokes used to sit between two colours and leave a white crack once they were removed. Grow each colour across the silhouette (`alpha > 32`) for up to 16 steps so neighbouring regions meet. Then `buffer(2.5)` the polygon before simplifying, and later put a flat fill of `buffer(1.5)` under the brush, because the wobble walks off the traced edge.

## Outline

Walk the pixel-corner edges of the mask. Interior is on the left, y down. At a corner, take the sharpest left turn so the loop stays on the boundary. A loop shorter than 4 corners, or a polygon under area 30, is dropped. A representative point must land inside the mask, which throws away a hole that was walked the wrong way.

`shapely` `simplify(1.8, preserve_topology=True)` removes the pixel stairs. Those stairs sit about half a pixel off the true edge, so 1.8 is enough to turn a straight side into a straight side. The bumps on the finished limbs are not from this step.

## Brush

`hand.stroke` at `jitter = 0.5`, brush 14. `jitter = 2.0` is too much: the hand's sideways waves scale with `jitter * min(4, 1.2 + extent/90)`, and a limb about 190 px across comes out near 6.6. Three waves then add to an 8–12 px swing, and a side only ~150 px long gets one fat hump. At 0.5 that swing is about 3 px. The trace was already within 1.8 px of straight before the brush ran.

How a polygon is drawn:

| Shape | Test | Draw |
|---|---|---|
| Limb | short side `< 42` and long side `> short × 2.2` | One stroke down the long axis. Width is the short side, clamped to 14…48. Inset each end by half that width so the round cap stays inside the part. |
| Compact part (eye, ear, torso patch) | anything else with at least 4 corners | Closed outline. Brush is 14 when the short side is `≥ 42`, otherwise `max(6, short × 0.4)`. One fill tap in the inset interior. |

A fill whose area is more than 85% of the canvas is a leak. Stop.

## Pixels on the phone

Rasterize with `rsvg-convert` at 4× (`SAMPLE = 4`) and keep those pixels. A 1× picture stretched on the phone turns a one-pixel antialiased edge into a staircase.

Bone points are multiplied by 4. `x_offset` / `y_offset` become the joint's place in the cropped 4× bitmap, negated. Item `meta.txt` `scale` is `0.5 / 4 = 0.125`, so a newly dropped item is the same size as the original `AT_Man` (whose scale is 0.5) rather than four times bigger.

An item already placed in a scene keeps the old skeleton and the old scale. Remove it and add `bluehairsvg` again.
