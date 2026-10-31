# Bone picture compatibility

An item archive has two pictures for a bone drawn in Paper Draw, and one number that only new builds read.

| Entry | What it is |
| --- | --- |
| `bm` PNG (`bone_1_2.png`) | The bone picture. One file pixel per `x_offset` unit. The downscaled export. |
| `<bm>.x2.png` | The paint buffer. Each side is `sample` times the `bm` PNG. |
| `sample` on `edgeAsset` | How a new build chooses which picture to draw. Omitted when `1`. |

`x_offset` and `y_offset` stay in `bm` pixels. They are not multiplied by `sample`.

## New build

- `sample="2"` and the sidecar decodes to exactly twice the `bm` PNG on each side: draw the sidecar at `unit.scale / 2`. A 1024×1024 sidecar over a 512×512 `bm` covers the same bone as the `bm` drawn at `unit.scale`.
- `sample` absent or `sample="1"`: draw the `bm` PNG at `unit.scale`.
- `sample="2"` but the sidecar is missing, not a PNG, or not `bm × 2`: draw the `bm` PNG at `unit.scale`. Do not shrink the main picture. Log the sidecar and drop it.

Debug **Ignore bm sample** draws the `bm` PNG and skips the sidecar, matching an old build. It does not change what is saved.

Paper Draw reopens from the sidecar when it passes that size check, copied in with no scale. The document size is the `bm` size in `x_offset` units. Bounds, the onion, split, and picture scale use that `bm` size. The sidecar is the pixels drawn into that size, not a larger picture.

The same rule applies on the skeleton, the animation screen, item preview, and export. They share one draw. A path that draws the `bm` PNG and ignores `sample` will show a sharp edit as the soft downsample.

## Old build

Android loads only the file named by `bm`. It does not read `sample`. It does not open `<bm>.x2.png`.

Nothing changes for that build when both are true:

- `bm` is the downscaled picture, one file pixel per `x_offset` unit, the picture that build already drew.
- `sample` and `<bm>.x2.png` are extra. Unknown XML attributes and unreferenced zip entries are ignored.

## Out of contract

Storing the paint buffer as the `bm` PNG and omitting the sidecar is not this contract. `sample="2"` then describes a file the old build will draw at twice the size, because it never divides by `sample`.

A file already saved that way (2× PNG as `bm`, `sample="2"`, no sidecar) does not match. A new build will not find a sidecar and will draw that PNG at full size, so the bone is twice as big. Draw the bone again under this contract.
