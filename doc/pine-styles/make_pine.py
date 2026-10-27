"""Source bitmaps for the pine-tree style page.

One scene, two raster inputs:

  src/pine_flat.png  flat colours, hard edges, no outlines.
                     Feeds `flat.py bg` and `flat.py bg --comic`.
  src/pine_ink.png   the same scene, every object outlined in #222222.
                     Feeds `ink.py sketch`.

No ink touches the canvas edge, and no frame encloses the whole page. Both are
constraints of the ink engine, not stylistic choices:

  - The page SVG clips at the canvas edge, so an edge stroke is lost and
    `ink_budget` reports it as missing ink.
  - A washable region must be closed by ink. A full-page rectangle is ink in
    every border cell, which the coverage gate cannot match either.

So the ground is a closed mound inside the page, with paper margins all round.
That is how line art on paper actually looks.

Tiers alternate dark and light on purpose: two similar greens merge into one blob
at 640x480 and the shape stops reading as a pine.

The palette stays above luma 90 on purpose. `ink_hysteresis` keeps any pixel
darker than that once it touches a stroke, so a dark fill becomes an ink stamp
instead of a washable pocket.
"""
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 640, 480
M = 28  # paper margin, all four sides
OUT = Path(__file__).resolve().parent / "src"
OUT.mkdir(parents=True, exist_ok=True)

PAPER = "#FFFFFF"
MOUND = "#8CC46A"
PINE_DARK = "#3E8460"
PINE_LIGHT = "#7CBE92"
TRUNK = "#A9744C"
SUN = "#F7D764"
BUSH = "#4E8F63"
CLOUD = "#F2FAFD"
INK = "#222222"

CX = W // 2


def ell(d, box, color, ol=None):
    d.ellipse(box, fill=color, outline=ol, width=3 if ol else 0)


def poly(d, pts, color, ol=None):
    d.polygon(pts, fill=color, outline=ol, width=3 if ol else 0)


def paint(d, ink):
    """Every part once. ink=False paints fills only, otherwise fill plus outline."""
    ol = INK if ink else None

    # the mound: one closed shape, wider than the tree, inside the margins
    poly(d, [(M, 396), (M, 452), (W - M, 452), (W - M, 396),
             (548, 366), (440, 352), (CX, 346), (196, 352), (88, 366)], MOUND, ol)

    # sun, upper left
    ell(d, (96, 46, 176, 126), SUN, ol)

    # clouds, upper right
    ell(d, (398, 48, 508, 96), CLOUD, ol)
    ell(d, (444, 34, 556, 78), CLOUD, ol)

    # trunk, behind the lowest tier, standing on the mound
    poly(d, [(CX - 14, 320), (CX + 14, 320), (CX + 14, 424), (CX - 14, 424)], TRUNK, ol)

    # pine: three tiers that share edges instead of overlapping. Overlapping
    # triangles let the draw order decide what survives the inset, and the tree
    # came out with a paper hole in its middle.
    poly(d, [(CX, 58), (CX + 58, 176), (CX - 58, 176)], PINE_DARK, ol)
    poly(d, [(CX - 58, 176), (CX + 58, 176), (CX + 106, 292), (CX - 106, 292)], PINE_LIGHT, ol)
    poly(d, [(CX - 106, 292), (CX + 106, 292), (CX + 152, 404), (CX - 152, 404)], PINE_DARK, ol)

    # a bush, so the frame is not one vertical
    ell(d, (72, 306, 158, 376), BUSH, ol)


if __name__ == "__main__":
    for name, ink in (("pine_flat.png", False), ("pine_ink.png", True)):
        im = Image.new("RGB", (W, H), PAPER)
        paint(ImageDraw.Draw(im), ink)
        im.save(OUT / name)
        print("wrote", OUT / name)
