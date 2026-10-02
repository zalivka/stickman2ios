# Restyle details

Read this when a run fails or the still PNG looks wrong. The procedure is in [restyle-svg-item.md](restyle-svg-item.md).

## What the script does to one part

`item_boil.load` reads `model.xml` and each `svg/v_<id>_state_0.svg`. Path coordinates are already in the bone frame: the start point is the origin, +x runs along the bone.

`part_session` flattens `M`/`C`/`z` to about 2-unit steps, simplifies to corners, and scales by `k = display_width / rest_box_width`.

- Short side of the minimum rotated rectangle, times `k`, is at least 42: `hand.poly` around the corners (`closed=True`, jitter 0.5) and one `hand.fill` inside, inset by half the brush plus 6 px. Colour is the SVG `fill`.
- Otherwise: one `hand.curve` from end to end of the long axis, inset by half the stroke so the round cap stays inside the part. Width is the short side, clamped to 6–48. The dog tail was 13 px; the T-Rex legs were 18–41 px. A trapezoid leg (the dog's purple one) is wider because the stroke follows the bounding rectangle, not the bone.

`svg_export` turns the session back into polylines (`stroke-width` 14, round caps) and fill paths. The assembly places each part the way `SkeletonCanvas.drawBitmaps` does: translate to the start point, rotate by the bone angle, `weight` order. The unwobbled original (not the restyle) matches the pack `poster.png`; that check is `item_boil.py`.

## Boil copies

`boil.variant` adds sideways drift (1.2–2.0 px, wavelength 70–200) and a nudge of ±1, then `svg_export` recomputes the fills. A fill whose area changes by more than 5% plus a 3 px band is rejected. Three rejects in a row abort.

## Rejected

| Approach | Why it lost |
|----------|-------------|
| Noise-warp the PNG | Straight edges ripple. Needs no shader; a `.metal` file makes Xcode 26 ask for the Metal toolchain. |
| Push outline points along their normals | Spikes at corners and at the export's zero-length closing segments. |
| Dark outline `#2B2B2B` | At 14 px it covers a small head. Same-colour lines match the huts. |
| Shark (`template.basic`) | Many paths per part, opacity 0, `command_scale="auto"`. |
| Bitmap items (the sword) | No SVG. Slopmaxing covers that. See [slopmax.md](slopmax.md). |
