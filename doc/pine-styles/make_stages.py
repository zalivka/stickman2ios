"""Stage images for doc/pine-styles/index.html.

Drives the real functions - never re-implements them:

  flat stages   flat.mark_page, flat.regions, flat.inset
  comic stages  flat.flatten, flat.ink_strokes
  sketch stages ink.ink_hysteresis, ink.edt_radius, ink.region_mask

The final renders are copied from the actual command output, not redrawn here.
Run from tools/bonepaper_gen with .venv/bin/python.
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GEN = Path(__file__).resolve().parents[2] / "tools/bonepaper_gen"
sys.path.insert(0, str(GEN))
import flat
import ink

DOC = Path(__file__).resolve().parent
SRC = DOC / "src"
OUT = DOC
RUNS = GEN / "out"
PAGE = (640, 480)


def render(shapes, paper, path, scale=2):
    """Fill each shapely polygon in its colour on a paper rect. No brush, no wobble."""
    im = Image.new("RGB", PAGE, paper)
    d = ImageDraw.Draw(im)
    for _, color, geom in shapes:
        geoms = flat.tracer.svg_export.polygons_of(geom)
        for poly in geoms:
            ring = [(x, y) for x, y in poly.exterior.coords]
            if len(ring) >= 3:
                d.polygon(ring, fill=color)
    im.resize((PAGE[0] * scale, PAGE[1] * scale), Image.LANCZOS).save(path)
    print("wrote", path.name)


def mask_png(mask, path, on=(34, 34, 34), off=(255, 255, 255), scale=2, thicken=3):
    """Ink masks are 1-3 px lines; widen for display so they read at page scale."""
    if thicken:
        mask = np.array(
            Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(thicken))
        ) > 0
    im = Image.fromarray(np.where(mask[:, :, None], np.array(on, np.uint8), np.array(off, np.uint8)))
    im.resize((PAGE[0] * scale, PAGE[1] * scale), Image.NEAREST).save(path)
    print("wrote", path.name)


def stage_flat():
    src = Image.open(SRC / "pine_flat.png").convert("RGB")
    im = flat.fit_page(src)

    # 1. sentinel swap: pure white and black are marked before tracing
    marked = flat.mark_page(im.convert("RGBA")).convert("RGB")
    marked.resize((1280, 960), Image.LANCZOS).save(OUT / "1-flat-sentinels.png")
    print("wrote 1-flat-sentinels.png")

    # 2. closed colour regions, still polygons
    shapes = flat.regions(marked.convert("RGBA"), 36)
    shapes = [(area, flat.page_color(color), geom) for area, color, geom in shapes]

    def spans(geom):
        x0, y0, x1, y1 = geom.bounds
        return sum((x0 <= 3, y0 <= 3, x1 >= PAGE[0] - 3, y1 >= PAGE[1] - 3)) >= 3

    pages = [item for item in shapes if spans(item[2])]
    page = max(pages, key=lambda item: item[0])
    paper = page[1]
    body = [item for item in shapes if item is not page]
    render(body, paper, OUT / "2-flat-regions.png")

    # 3. insets: each compact outline pulled in by size/2 - 2.5
    inset = [flat.inset(item) for item in body]
    inset = [item for item in inset if item is not None]
    render(inset, paper, OUT / "3-flat-insets.png")
    return len(shapes), len(body), paper


def stage_comic():
    # comic eats a picture that already has ink over flat fills
    src = Image.open(SRC / "pine_ink.png").convert("RGB")
    im = flat.fit_page(src)

    # 1. flatten: ink removed, octree to 24 colours, 7 px mode filter
    flat_im, ink_mask = flat.flatten(im, 24)
    flat_im.resize((1280, 960), Image.LANCZOS).save(OUT / "4-comic-flatten.png")
    print("wrote 4-comic-flatten.png")

    # 2. the ink layer that flatten() set aside
    mask_png(ink_mask, OUT / "5-comic-ink-mask.png")

    # 3. that ink redrawn as centre-line strokes
    strokes = flat.ink_strokes(im, ink_mask, flat_im)
    canvas = Image.new("RGB", PAGE, (255, 255, 255))
    d = ImageDraw.Draw(canvas)
    for pts, color, size in strokes:
        d.line([(x, y) for x, y in pts], fill=color, width=max(1, int(size)), joint="curve")
    canvas.resize((1280, 960), Image.LANCZOS).save(OUT / "6-comic-strokes.png")
    print("wrote 6-comic-strokes.png")
    return len(strokes)


def overlay_png(src, mask, path, color=(214, 40, 40), scale=2, thicken=3):
    """Mask painted over the source, so the reader sees which marks were caught."""
    if thicken:
        mask = np.array(
            Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(thicken))
        ) > 0
    base = np.array(src.convert("RGB")).astype(np.float32)
    base = 255 - (255 - base) * 0.35  # wash the source out so the mask reads
    base[mask] = color
    im = Image.fromarray(base.astype(np.uint8))
    im.resize((PAGE[0] * scale, PAGE[1] * scale), Image.NEAREST).save(path)
    print("wrote", path.name)


def stage_sketch():
    src = Image.open(SRC / "pine_ink.png").convert("RGB")
    im = flat.fit_page(src)
    arr = np.array(im).astype(np.int16)

    # 1. hysteresis ink mask, shown over a faded source
    ink_mask = ink.ink_hysteresis(arr)
    overlay_png(im, ink_mask, OUT / "7-sketch-ink-mask.png")

    # 2. EDT split: region cores vs strokes, same colours as edt_split.png.
    #    Strokes are 1-3 px, so widen them 2 px for legibility at page scale.
    radius = ink.edt_radius(ink_mask)
    regions = ink.region_mask(ink_mask, radius)
    strokes = ink_mask & ~regions
    vis = np.zeros((*ink_mask.shape, 3), np.uint8)
    vis[:] = 255
    thick = np.array(
        Image.fromarray((strokes * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
    ) > 0
    vis[thick] = (40, 40, 40)
    vis[regions] = (200, 80, 80)
    Image.fromarray(vis).resize((1280, 960), Image.NEAREST).save(OUT / "8-sketch-edt-split.png")
    print("wrote 8-sketch-edt-split.png", f"region_px={int(regions.sum())} stroke_px={int(strokes.sum())}")
    return int(ink_mask.sum()), int(regions.sum()), int(strokes.sum())


def copy_finals():
    for src, dst in (
        (RUNS / "pine_flat/bg.png", OUT / "9-final-flat.png"),
        (RUNS / "pine_comic/bg.png", OUT / "10-final-comic.png"),
        (RUNS / "pine_sketch/bg.png", OUT / "11-final-sketch.png"),
        (RUNS / "pine_sketch/pockets.png", OUT / "12-sketch-pockets.png"),
    ):
        shutil.copyfile(src, dst)
        print("copied", dst.name)


if __name__ == "__main__":
    print("flat:", stage_flat())
    print("comic strokes:", stage_comic())
    print("sketch:", stage_sketch())
    copy_finals()
