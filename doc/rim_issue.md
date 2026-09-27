# Fill rim between a line and a same-colour fill

## Symptom

1. Fill the whole page with a colour (e.g. grey).
2. Draw a closed brush outline on it (e.g. dark blue).
3. Tap inside the outline with the same blue.

A thin light line, 1–2 px wide, stays between the outline and the fill. It appears at 100% opacity too. On a blank page (no background fill) it does not appear.

Pixels sampled from a device screenshot, left to right across the inner edge of the outline:

| Where | RGB |
|---|---|
| Page | (174, 181, 173) |
| Outline | (35, 47, 211) |
| Rim | (45, 57, 217), (48, 60, 220) |
| Fill | (35, 47, 211) |

The screenshot is downscaled, so the rim in the buffer is lighter than these numbers suggest. In a reproduction the worst rim pixel was 200 brightness units (R+G+B) above the paint, which is almost the page grey.

## Background: the two fill modes

`BonePaperDocument.fillWorld` picks a mode from the alpha of the tapped pixel:

- **Empty fill** (alpha < 26, `fillRecolorAlpha`): the page there is transparent. The region grows through transparent pixels. Then `growRing` extends it by `fillRing` (3 buffer px, 8 neighbours) into the line's anti-aliased edge, and `paintBehind` paints destination-over. The line's soft edge stays on top and the paint tucks under it, so the result has no gap.
- **Recolour** (alpha ≥ 26): the page there is already painted. The region grows through pixels of similar colour (OKLab, neighbour step < 0.06, distance from seed < 0.2). The new colour is written into region pixels at each pixel's own alpha.

## Cause

A brush line is anti-aliased: its edge is a band of pixels that blend the line colour with whatever was under it.

- **Blank page:** under the line there was nothing, so an edge pixel is blue at partial alpha, e.g. blue at alpha 0.4. Tapping inside is an **empty fill**. The ring claims the partial-alpha pixels and `paintBehind` fills the missing 0.6 with paint. Blue at 0.4 plus blue paint behind gives solid blue. No rim.
- **Coloured page:** under the line there was opaque grey paint, so an edge pixel is **opaque**: e.g. 40% grey + 60% blue = (91, 101, 196). Tapping inside is a **recolour**, because the tapped pixel is grey paint at alpha 255.
  - The region grows through grey and stops where the colour starts shifting to blue: the neighbour and seed limits reject the blend pixels.
  - Recolour had **no edge step**. The blend pixels were never touched, so they still held 40% grey after the fill.
  - Result: solid blue fill, a line of grey-blue pixels, then solid blue outline. That line is the rim.

The earlier attempt (diagonal neighbours in `growRing`) could not help. `growRing` only runs for empty fills, and this was a recolour.

Opacity was not the cause either. At 100% the blend pixels are still skipped.

## Anti-aliasing flag

The band only exists because brush edges are anti-aliased. `BonePaperFlags.antialiasing` (in `Vendor/BonePaper/Sources/BonePaper/BonePaperFlags.swift`) switches it:

- **Off (default):** `BonePaperDocument.paint` calls `setShouldAntialias(false)` for brush, dot and eraser stamps. Every stamped pixel is either pure line colour or untouched. Edges are hard, and curves are stair-stepped at buffer resolution (2× the document). A recolour reaches right up to the line, and the edge step below is skipped.
- **On:** soft edges, and the recolour runs the edge step.

## Fix

`BonePaperRecolor.apply` (`BonePaperRecolor.swift`) repaints the island and, with anti-aliasing on, the edge band around it.

1. **Before** the region is repainted, collect pixels up to `fillRing` (8-neighbour steps) outside the region.
2. For each such pixel `p`:
   - `S` = the old island colour: the straight (un-premultiplied) RGB of the tapped pixel.
   - `L` = the line colour: the neighbour outside the region whose colour is most different from `S`. `p` itself is a candidate too.
   - Read `p` as a blend `p = t·L + (1 − t)·S`. Get `t` by projecting `p − S` onto `L − S`, clamped to 0…1.
   - The island share is `1 − t`.
3. Repaint the region as before.
4. For each edge pixel, swap the island share for the paint: `p' = p + (P − S) · (1 − t) · opacity`, with `P` the paint colour. Write it back premultiplied at the pixel's own alpha.

Example with grey `S` = (174, 181, 173), blue line `L` = paint `P` = (35, 47, 211):

| Pixel | t | Before | After |
|---|---|---|---|
| Solid outline | 1.0 | (35, 47, 211) | unchanged |
| 60% blue edge | 0.6 | (91, 101, 196) | (35, 47, 211) |
| 20% blue edge | 0.2 | (146, 154, 181) | (35, 47, 211) |

With a different fill colour the edge stays smooth. Filling red inside a blue outline turns the 60% blue pixel into 60% blue + 40% red, which is exactly what the edge would have been if the red had been there when the line was drawn.

### Guards

- **Pure line pixels are left alone:** if `t = 1` the pixel is not changed.
- **No crossing thin lines:** growth continues only through pixels with `t < 0.9`. A pixel that is almost pure line colour stops the growth, so the edge step does not reach the far side of a 1–2 px line.
- **Specks inside the region:** a pixel whose own colour is the most different from `S` (no neighbour is further) gets `t = 1` and is not changed.
- **Read before write:** all shares are computed from the original pixels before the region or any edge pixel is repainted, so the result doesn't depend on visit order.
- **Opacity:** the swap is scaled by the tool opacity, matching how region pixels are mixed.

## Verification

A standalone reproduction, `tools/bonepaper_gen/out/fillrim/recolor.swift`, paints a grey page, strokes a blue circle (width 14 at 2× sample) and recolour-fills inside with the same blue. It counts pixels inside the stroke's centre radius that are more than 12 units (R+G+B) brighter than the paint.

| Code | Light pixels | Worst extra brightness |
|---|---|---|
| Recolour only (old) | 393 | 200 |
| Recolour + edge (new) | 0 | 1 |

Run it with `swift recolor.swift 0 before.png` or `swift recolor.swift 1 after.png`.

On macOS, build the test colours in `CGColorSpaceCreateDeviceRGB()`. A plain `CGColor(red:green:blue:alpha:)` gets colour-matched to the display profile, and the stroke bytes stop matching the fill bytes. That is a quirk of the test on macOS, not an app bug; on iOS DeviceRGB is sRGB.

Confirmed on device: filling the page, drawing an outline and filling inside with the same colour no longer leaves a rim.
