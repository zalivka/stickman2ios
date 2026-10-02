# Slopmax

Slopmaxing an item redraws each bone bitmap with the sloppy brush and packs a 4× `.ati`. Slopmaxing a scene does that for every drawable unit, embeds the new items, and divides those units' scene scales by 4.

The slopmaxing script for a scene is `tools/bonepaper_gen/out/camera/build.py` (`demo_camera` → `demo_camera2`). One-item runs live beside it (`out/sun`, `out/shuttle`, `out/earth`, `out/space_rest`, `out/lion`). The tracer they call is `tools/bonepaper_gen/out/bluehairsvg/build.py`, written up in [vectorize-bone.md](vectorize-bone.md). Do not edit `hand.py`.

Python is `tools/bonepaper_gen/.venv/bin/python`. Plain `python3` has no Pillow.

The sun, picture by picture, is [sun-steps/index.html](sun-steps/index.html).

This is not an SVG restyle ([restyle-svg-item.md](restyle-svg-item.md) never writes an `.ati`) and not a template upscale ([item_upscale.md](item_upscale.md) doubles path numbers and leaves `meta.txt` scale at 0.5).

## One bone

Classify the solid pixels (`alpha > 200`) before tracing.

| Kind | Test | What to paint first |
|---|---|---|
| Ink | At least 80% of solid pixels are `rgb <= 24` (the black stickman, the bullet) | Mark `alpha > 32` and `rgb <= 40` as `(160, 160, 160)`. Recolor every shape `#222222`. The tracer drops real black. |
| Line art | More than 40 black pixels and more than 40 near-white pixels (the sword, the pistol) | Near-white (`peak >= 220`, saturation `< 16`) becomes the sentinel `(255, 0, 180)`. Black becomes `(160, 160, 160)`. After the trace, sentinel → `#FFFFFF`, gray → `#222222`. |
| Colour | Anything else (the hand, the explosion, the shuttle) | Trace as-is. |

`rgb >= 240` is paper to the tracer, so a white fuselage, a white blade, or a blast core disappears unless it was marked with the sentinel first. Rename that sentinel back to `#FFFFFF`. Do not leave `(255, 0, 180)` in the item.

Colour centres merge when the max channel difference is `<= 36`. The moon's craters are gray 128 against gray 160 (difference 32), so that disk becomes one blob. The moon run merges at 16. Put the tighter merge back when that item is done.

A ring loses its outline. The tracer keeps a loop only when a representative point lands inside the mask, so a star's red rim and a sword's black rim are thrown away and only the centre survives. The slopmaxing script keeps the largest loop anyway. Inner colours paint over that fill, which is how the explosion stays a red rim, an orange star, and a yellow centre.

Brush constants are the tracer's: `JITTER = 0.5`, brush 14, `PAD = 40`, `SAMPLE = 4`. A limb (short side `< 42` and long side `> short × 2.2`) is one stroke. A compact part is a closed outline plus one fill. A fill bigger than 85% of the canvas is a leak. Stop.

Empty bitmap, no colour, and no regions are loud failures. Do not substitute a blank bone.

## Pixels and the joint

Rasterize the full padded canvas with `rsvg-convert` at 4×. Do not crop to the alpha box. A crop moves the joint, and two boil frames cropped apart will not share one.

```text
joint in the source bitmap = (-old_x_offset, -old_y_offset)
new offset                 = -((joint + 40) * 4)
```

The sword's old offset is `-13, -13`. The joint sits at `(13, 13)`. The new offset is `-((13 + 40) * 4) = -212, -212`.

Write that with a normal f-string:

```python
f'x_offset="{xo:.4f}" y_offset="{yo:.4f}"'
```

An rf-string that ends in `\"` stores the backslash. `y_offset="-459\""` does not load.

Multiply every `<point x y>` by 4. `meta.txt` `scale` becomes the old scale divided by 4. A missing scale counts as 1, so a pack item lands at `0.25`. The camera stickman and the hand were `0.5`, so they land at `0.125`.

Keep `weight`, `flipped`, `start`, `end`, and `state`. The pistol's flipped edge is a second bitmap (`pistol_flip.png`) and the tag is split across lines, so the rewrite has to be `re.DOTALL` through `/>`. One converted PNG per bitmap. Each edge gets an offset from its own old offset. Shared stickman bitmaps happen to share one offset, so they stay shared.

## The scene scale is the one on the unit

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

Pack items are not embedded in the `.ats`. After the rename the scene looks up `@:sword`, so `sword.ati` has to sit at the archive root and in customs. Items that were already `@:` keep their filenames (`Чёрный_СтикМан.ati`, `item_1477936548.ati`). Attachments such as `@:Чёрный_СтикМан#1&amp;7` resolve through `removeNumber`, which strips `#`.

Leave `camera=`, the thumbs, and `metadata.txt`. Leave the background unless asked. `demo_camera` is `bg_name="usermade:1477936027689"`, `_bgs/1477936027689.zip`, and `bg="1.0 0.0 0.0 0.0"` on every frame. `demo_space2` got a new sky only as its own request. That raster is 1280×960, so those frames use `bg="0.5 0.0 0.0 0.0"` to fill 640×480.

Do not add boil frames unless asked. The sun's three frames and `animations_v2.txt` are a separate pass. Every boil frame uses the same uncropped canvas and the same offset.

## Where they go

`at_elements/demo/` is bundled on the next build. `DemoSeeder` copies bundle demos once, so an install that already ran will not see a new file. Copy the `.ats` into Application Support `at_elements/saved/` and each `.ati` into `at_elements/customs/` with one `devicectl` file copy per file. Do not pass `--remove-existing-content`. A directory copy with that flag hands the folder to root. Leave the scene list and reopen it. Do not build unless asked.

Done this way: `@:lion`, the `demo_space2` set (`@:sun`, `@:earth`, `@:moon`, `@:mks`, `@:ufo`, `@:shuttle`, `@:laser_beam`, `@:blast`), and `demo_camera2` (hand, black stickman, sword, pistol, explosion, bullet). The graph paper and the sign in `demo_camera2` were left as they were.
