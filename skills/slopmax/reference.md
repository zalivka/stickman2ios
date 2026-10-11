# Slopmax reference

Collected from `doc/slopmax.md`, `doc/vectorize-bone.md`, and the drawing sections of `doc/bone-paper-recording.md`. Those files stay the long source. Read this instead of hunting them.

## Classify a bone before tracing

Solid pixels are `alpha > 200`.

| Kind | Test | What to paint first |
|------|------|---------------------|
| Ink | At least 80% of solid pixels are `rgb <= 24` (black stickman, bullet) | Mark `alpha > 32` and `rgb <= 40` as `(160, 160, 160)`. Recolor every shape `#222222`. The tracer drops real black. |
| Line art | More than 40 black pixels and more than 40 near-white pixels (sword, pistol) | Near-white (`peak >= 220`, saturation `< 16`) becomes the sentinel `(255, 0, 180)`. Black becomes `(160, 160, 160)`. After the trace, sentinel → `#FFFFFF`, gray → `#222222`. |
| Colour | Anything else (hand, explosion, shuttle) | Trace as-is. |

`rgb >= 240` is paper to the tracer. A white fuselage, a white blade, or a blast core disappears unless it was marked with the sentinel first. Rename that sentinel back to `#FFFFFF`. Do not leave `(255, 0, 180)` in the item.

The tracer drops white (`rgb >= 240`) and black ink (`rgb <= 24`), plus a one-pixel fringe around that ink so the dark edge of a black stroke is not its own colour. Gray limbs (low saturation, peak `>= 70`) stay. A near-black outline such as `#2C2C2B` does not.

## Colour split

Round remaining pixels to 16, then merge centres within 36. Assign every solid pixel to the nearest centre. A blob under 40 pixels is ignored. The colour written later is the median of the solid pixels in that blob, not the rounded centre.

The moon's craters are gray 128 against gray 160 (difference 32), so a merge of 36 makes one blob. The moon run merges at 16. Put the tighter merge back when that item is done.

Black strokes used to sit between two colours and leave a white crack once they were removed. Grow each colour across the silhouette (`alpha > 32`) for up to 16 steps so neighbouring regions meet. Then `buffer(2.5)` the polygon before simplifying.

## Outline

Walk the pixel-corner edges of the mask. Interior is on the left, y down. At a corner, take the sharpest left turn so the loop stays on the boundary. A loop shorter than 4 corners, or a polygon under area 30, is dropped. A representative point must land inside the mask, which throws away a hole that was walked the wrong way.

`shapely` `simplify(1.8, preserve_topology=True)` removes the pixel stairs. Those stairs sit about half a pixel off the true edge, so 1.8 turns a straight side into a straight side. The bumps on the finished limbs are not from this step.

A ring loses its outline. The tracer keeps a loop only when a representative point lands inside the mask, so a star's red rim and a sword's black rim are thrown away and only the centre survives. The slopmaxing script keeps the largest loop anyway. Inner colours paint over that fill, which is how the explosion stays a red rim, an orange star, and a yellow centre.

## Brush numbers

`hand.stroke` at `jitter = 0.5`, brush 14. `jitter = 2.0` is too much: sideways waves scale with `jitter * min(4, 1.2 + extent/90)`, and a limb about 190 px across comes out near 6.6. Three waves then add to an 8–12 px swing, and a side only ~150 px long gets one fat hump. At 0.5 that swing is about 3 px. The trace was already within 1.8 px of straight before the brush ran.

`hand.poly` draws straight segments and turns the finger at each vertex. A 24-gon on a large shape shows facets under a 14 px brush. Sample a large outline so edges are about 5 px (on the order of 128 points for a tall rock). `hand.curve` is Catmull-Rom with about 2 px steps. `svg_export` simplifies fill paths at 0.25 px and does not smooth the stroke ring.

The traced ring breaks that rule. `brush_svg` hands the `buffer(2.5).simplify(1.8)` ring to `hand.poly` as it is:

| Disc radius | Corners | Longest edge | Mean edge |
|---|---|---|---|
| 30 | 12 | 23 px | 17 px |
| 60 | 16 | 29 px | 25 px |
| 120 | 27 | 43 px | 29 px |

Stroke a round traced part as `hand.curve(ring, closed=True)`. Keep `hand.poly` for parts with real corners.

## Why not a tracing library

Potrace, vtracer, and autotrace return Bezier contours. `brush_svg` needs flat-colour shapely polygons and reads only the exterior: a limb uses the long axis of the minimum rotated rectangle, and a compact part uses the ring. The shipped SVG is rebuilt by `svg_export` from the stroke log, so no tracer path reaches the file.

None of them do the colour policy above: merge across black ink, use the white sentinel, drop `#2C2C2B`-style outlines, and drop blobs under 40 px and loops under area 30. Potrace is one bit per pass, so it would only replace `boundary_loops`. For speed, `cv2.findContours` on each colour mask replaces that same step without Beziers.

Tracing a soft or photographic raster fails either way, because quantization makes a band per shade. Draw that kind of picture from shapes (`out/storypic`).

What `stroke()` does, in order:

1. Loop run-on (`closed=True`): the path continues past its start by 4–14% of its length, so a later fill holds.
2. Wobble: three sine waves, wavelength 60–240 px, amplitude `0.3–0.7 × jitter × min(4, 1.2 + extent/90)`.
3. Timing: base speed 500–900 px/s, scaled by `(length / 250)^0.2` and clamped to 0.75–1.1. Tight curves slow the finger. Each piece lasts at least 0.08 s. Samples are 60 Hz with tremor σ = 0.25 px.
4. Start threshold: the first sample plus every sample from the first one ≥ 12 px away. A stroke that never gets 12 px from its start raises `SystemExit`.
5. Same seed and same scene give the same log.

`hand.fill(at, color, wander=3)` jitters the tap ±3 px. `wander=0` stays on a thin colour that jitter would step off.

## Joint and 4× pixels

Rasterize the full padded canvas with `rsvg-convert` at 4×. Do not crop to the alpha box. `bluehairsvg` cropped each bone. Slopmaxing does not. Cropping moves the joint, and two frames cropped apart will not share one.

```text
joint in the source bitmap = (-old_x_offset, -old_y_offset)
new offset                 = -((joint + 40) * 4)
```

The sword's old offset is `-13, -13`. The joint sits at `(13, 13)`. The new offset is `-((13 + 40) * 4) = -212, -212`.

Write the offset with a normal f-string:

```python
f'x_offset="{xo:.4f}" y_offset="{yo:.4f}"'
```

An rf-string that ends in `\"` stores the backslash. `y_offset="-459\""` does not load.

Multiply every `<point x y>` by 4. `meta.txt` `scale` becomes the old scale divided by 4. A missing scale counts as 1, so a pack item lands at `0.25`. The camera stickman and the hand were `0.5`, so they land at `0.125`.

Keep `weight`, `flipped`, `start`, `end`, and `state`. The pistol's flipped edge is a second bitmap (`pistol_flip.png`) and the tag is split across lines, so the rewrite has to be `re.DOTALL` through `/>`. One converted PNG per bitmap. Each edge gets an offset from its own old offset.

A 1× picture stretched on the phone turns a one-pixel antialiased edge into a staircase. Keep the 4× pixels.

## Scene scale

Once a unit is placed, playback draws `bitmap * unit.scale`. `meta.txt` scale is only the rest pose of a newly dropped item. Dividing the meta scale and leaving the scene scale paints the part four times too big.

Divide `scale` on the scene `<unit>` whose name is one of the redrawn items, including a `#1` / `#2` suffix. Then rename the pack prefix.

```text
newstickman:sword      →  @:sword          1.0        →  0.25
newstickman:bullet#1   →  @:bullet#1
@:Чёрный_СтикМан#1     stays that name     0.5        →  0.125
@:item_1477936548      stays that name     1.8505772  →  0.4626443
common:sign            stays that name     1.0        stays 1.0
```

`common:sign` is `type="bubble"`. No bitmap. Do not trace it and do not divide its scale.

Pack items are not embedded in the `.ats`. After the rename the scene looks up `@:sword`, so `sword.ati` has to sit at the archive root and in customs. Items that were already `@:` keep their filenames. Attachments such as `@:Чёрный_СтикМан#1&amp;7` resolve through `removeNumber`, which strips `#`.

Leave `camera=`, the thumbs, and `metadata.txt`. Leave the background unless asked. Do not add boil frames unless asked. Every boil frame uses the same uncropped canvas and the same offset.

When those frames are written into an `.ati`, name them `bm_<id>_state_<n>.png` with one `<id>` for the bone. `<n>` matches `<edgeAsset state>`. Android (`Utils.BM_NAME_PATTERN`, `bm_(\\d+)_state_(\\d+).png`) reads the bone id and the frame from that name and does not read `state` on the tag. iOS playback still reads the attribute. iOS `galleryBones` groups the same pattern and shows the lowest state. A name that does not match, such as `sun_0.png`, is its own bone.

## Scene-authoring rules

1. Anything you fill must be drawn with `closed=True`. Otherwise the fill leaks through the gap.
2. Minimum feature size is about 2× the brush (≥ 22–28 px at size 14). Castle battlements 13 px wide came out as blobs; 22 px worked.
3. The inside of a shape you will tap must be clearly wider than the brush. Aim for at least 20 px clear inside, and put the tap at least `size/2 + 3` px from any line (the tap jitters ±3 px).
4. Count the colours already inside an outline, and tap each one. A fill recolours only the tapped colour. `brush_svg` does this after a closed outline. A bone on empty paper is still one tap. A window drawn across two greys gets two. The other way is to fill the shape before those colours exist.
5. A line dividing a same-coloured shape must cross the whole outline band: reach radius + `size/2` + a few px past the edge. Otherwise a recolour runs along the outline around the line's end.
6. A tap on existing paint recolours the connected area of similar colour, bounded by lines of a different colour.
7. Draw order that works: background lines and their fills; each object's outline, then its fill; details as short strokes after the fills; the sky or wall as one final tap.
8. A dot is a short stroke of at least 12 px. Use a dash of 14–18 px, or two crossing strokes for a star.
9. Lines ending on the page edge run 10–12 px past the edge so an edge-bounded fill does not leak around the end.
10. Keep brush 14 and opacity 1 unless there is a reason to change them.
11. Outline and fill colours must differ clearly (well over 0.06 OKLab). A similar-coloured outline is treated as part of the region and the recolour runs through it.
12. Small rings need a radius of at least about 8 px, or the loop never gets 12 px from its start.

`_stamp` order, which is rule 4 for a traced shape: append `buffer(1.5)` of the shape when it is drawn, then the outline (`hand.poly`), then a tap for each colour still showing inside. Do not splice every flat fill to the start of the SVG. Later wall fills cover those early rectangles, and the window tap recolours only the patch it hits.

## Stars

Drawn first, then spliced to the first non-sky layer so they sit behind every other object. Source opacity × 0.4 over the sky. Size from the radius. Slightly different colours. The 12 px minimum turns a 1 px dot into a plus, so draw the plus on purpose. A radius cutoff around 1.5 px keeps a tiny crater from becoming a star.

## SVG fill model

`svg_export.py` replays the log as shapely geometry, bottom to top.

- Stroke: `LineString(points).buffer(size/2) ∩ page`, appended on top.
- Empty-paper fill: the piece of `page − covered` that contains the tap, grown by `FILL_RING = 1.5`, inserted at the bottom.
- Recolour: topmost colour at the tap, joined with layers within `NEIGHBOUR = 0.06` OKLab, appended on top.
- A tap in no piece uses the nearest piece within 1 px, otherwise the script exits.
- Output paths are simplified at 0.25 px. Opacity below 1 becomes `stroke-opacity` or `fill-opacity`.

## Antialiasing

| Renderer | Strokes | Fills | Use |
|----------|---------|-------|-----|
| BonePaper | Antialiased | Empty-paper fills grow under the fringe | Editor only. Not available from `replay.py`. |
| `replay.py` (Pillow) | No antialiasing | Hard flood fill | Leak checks only. A Lanczos shrink of `replay.png` hides the steps. |
| `rsvg-convert` on the editable SVG | Antialiased round caps | Fill polygon under the stroke | The bitmap to ship. |

Ship `rsvg-convert -w <width×sample> -h <height×sample>` of the editable SVG (polylines, not `--flat`). `--flat` turns each stroke into an 8-segment cap.

## Page SVG and pack storage

The brushed drawing is a padded canvas: page plus `PAD` on every side (640×480 → 720×560), with `width`/`height` rewritten to `SAMPLE` times that and `viewBox` of the padded canvas. Cropping for a page SVG replaces the header with:

```xml
width="640" height="480" viewBox="40 40 640 480"
```

Android `SVGParser` reads `path` and `polyline`.

A pack background zip holds `bg.png` (1280×960 for a 640×480 page), `bg.svg` (the cropped drawing), and `thumb.png`. Existing pack thumbs are 90×90 cover crops. `BackgroundStore.thumbSide` for a usermade background is 100.

iOS `BackgroundStore.rasterEntry` returns `bg.png`, then `bg.jpg`, and ignores `bg.svg`. `fittedMove` scales a 1280×960 png onto a 640×480 scene by 0.5.

Android pack load (`BackgroundAsyncCache.loadFromArchive`, `processPackBg`) tries `bg.svg`, then `bg.png`, then `bg.jpg`. Both files can sit in the zip and Android still draws the SVG. A usermade archive is the exception: the SVG is used only when png and jpg are both absent.

iOS chooser folder is one `.atp`. Backgrounds inside it are flat `bgs/<name>.zip`. The folder title is `pack_name` from `translate_en.xml`, otherwise `mHumanName`. `mSysName` must contain a `.` and must equal the archive filename. `BackgroundCatalog` lists every bundle `.atp` that contains `bgs/*.zip`. Hiding an item-less pack from the item chooser is `Manifest.chooserHidden`, separate from the background list.

Day, evening, and night of one layout share one seed (`17 + sum(name) % 80` on the day name) so the brush wobble matches. Evening puts the sun in the horizon band, clipped by the sea drawn later. Night sets the sun to none and draws no moon.

## Where a finished scene goes

`at_elements/demo/` is bundled on the next build. `DemoSeeder` copies bundle demos once, so an install that already ran will not see a new file. Copy the `.ats` into Application Support `at_elements/saved/` and each `.ati` into `at_elements/customs/` with one `devicectl` file copy per file. Do not pass `--remove-existing-content`. A directory copy with that flag hands the folder to root. Do not build unless asked.

A drawn background the app saves itself is `Library/Application Support/at_elements/bgs/<millis>.zip`, chooser name `usermade:<millis>`, entries `bg.png` and `thumb.png`.
