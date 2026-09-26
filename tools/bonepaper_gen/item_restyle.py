"""Redraw an SVG-sourced item with the BonePaper hand model, one session per part, and assemble it in rest pose.

usage: .venv/bin/python item_restyle.py <pack.atp> <item.ati> <out_dir> <name> <display_width> [outline_hex]
display_width: the item's width in BonePaper page px where it will be shown (sets brush scale).
Parts at least WIDE_BRUSHES brushes across are outlined and filled; thinner parts become one stroke along the bone.
Writes <name>_still.png and <name>_<i>.png (line-boil copies) at RASTER px wide.
"""
import math
import random
import subprocess
import sys
from pathlib import Path

from shapely.geometry import Polygon

import boil
import item_boil
import svg_export
from hand import Hand

BRUSH = 14.0
WIDE_BRUSHES = 3.0
STROKE_MIN, STROKE_MAX = 6.0, 48.0
MARGIN = 30.0          # page px around a part's own sheet
RASTER = 900
COUNT = 3


def outline(loops):
    """Corners of the part's first outline, in bone units."""
    poly = Polygon(loops[0]).buffer(0)
    return poly.simplify(1.0)


def part_session(part, k, seed, outline_color):
    loops, style = part["shapes"][0]
    if len(part["shapes"]) != 1:
        raise SystemExit(f"item_restyle: part with {len(part['shapes'])} paths")
    color = style["fill"]
    poly = outline(loops)
    minx, miny, maxx, maxy = poly.bounds
    page = lambda p: ((p[0] - minx) * k + MARGIN, (p[1] - miny) * k + MARGIN)
    width = math.ceil((maxx - minx) * k + 2 * MARGIN)
    height = math.ceil((maxy - miny) * k + 2 * MARGIN)
    hand = Hand(seed, (0, 0))
    rect = poly.minimum_rotated_rectangle
    corners = list(rect.exterior.coords)[:4]
    edges = [(math.dist(corners[i], corners[i + 1]), i) for i in range(2)]
    short = min(edges)[0] * k
    if short < WIDE_BRUSHES * BRUSH:
        # Thin part: one stroke down the long axis of its bounding rectangle.
        long_i = max(edges)[1]
        a, b = corners[long_i], corners[long_i + 1]
        c, d = corners[(long_i + 2) % 4], corners[(long_i + 3) % 4]
        mid1 = ((a[0] + d[0]) / 2, (a[1] + d[1]) / 2)
        mid2 = ((b[0] + c[0]) / 2, (b[1] + c[1]) / 2)
        size = min(STROKE_MAX, max(STROKE_MIN, short))
        inset = size / 2 / k
        length = math.dist(mid1, mid2)
        ux, uy = (mid2[0] - mid1[0]) / length, (mid2[1] - mid1[1]) / length
        p1 = page((mid1[0] + ux * inset, mid1[1] + uy * inset))
        p2 = page((mid2[0] - ux * inset, mid2[1] - uy * inset))
        hand.stroke(hand.curve([p1, p2]), color, size=size, jitter=0.5)
        kind = f"stroke {size:.0f}px"
    else:
        keys = [page(p) for p in list(poly.exterior.coords)[:-1]]
        hand.stroke(hand.poly(keys, closed=True), outline_color or color, closed=True, jitter=0.5)
        inner = Polygon(keys).buffer(-(BRUSH / 2 + 6))
        if inner.is_empty:
            raise SystemExit("item_restyle: outlined part has no room for a fill tap")
        tap = inner.representative_point()
        hand.fill((tap.x, tap.y), color)
        kind = "outline + fill"
    session = {
        "version": 1, "started": "generated", "duration": round(hand.t, 3), "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": width, "height": height, "originX": 0, "originY": 0, "fixed": True},
        "final": {"width": width, "height": height, "extraLeft": 0, "extraTop": 0},
        "paper": None, "ops": hand.ops,
    }
    return session, (minx, miny), kind


def body(scene):
    svg = scene.svg(False)
    return svg[svg.index(">") + 1:svg.rindex("</svg>")]


def main():
    pack, item, out_dir, name = sys.argv[1], sys.argv[2], Path(sys.argv[3]), sys.argv[4]
    display = float(sys.argv[5])
    outline_color = sys.argv[6] if len(sys.argv) > 6 else None
    parts = item_boil.load(pack, item)
    _, box = item_boil.render(parts, None, None)
    k = display / (box[2] - box[0])
    sessions = []
    for i, part in enumerate(parts):
        session, origin, kind = part_session(part, k, 100 + i, outline_color)
        print(f"part weight {part['weight']}: {kind}")
        sessions.append((part, session, origin))
    pad = (MARGIN + STROKE_MAX) / k
    x0, y0 = box[0] - pad, box[1] - pad
    w, h = box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad
    height = round(RASTER * h / w)
    out_dir.mkdir(parents=True, exist_ok=True)
    labels = ["still"] + [str(i) for i in range(COUNT)]
    for n, label in enumerate(labels):
        groups = []
        for j, (part, session, origin) in enumerate(sessions):
            if label == "still":
                traced = session
            else:
                base = boil.fills(session)[1]
                for attempt in range(boil.TRIES):
                    traced = boil.variant(session, random.Random(1000 * n + 10 * j + attempt))
                    if boil.leaks(base, boil.fills(traced)[1]) is None:
                        break
                else:
                    raise SystemExit(f"item_restyle: part {j} copy {label} leaked {boil.TRIES} times")
            scene = svg_export.Scene(traced)
            scene.run(traced["ops"])
            sx, sy = part["start"]
            groups.append(
                f'<g transform="translate({sx:.3f},{sy:.3f}) rotate({part["angle"]:.4f}) '
                f'translate({origin[0]:.3f},{origin[1]:.3f}) scale({1 / k:.6f}) translate({-MARGIN},{-MARGIN})">'
                + body(scene) + "</g>")
        svg = out_dir / f"{name}_{label}.svg"
        svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{RASTER}" height="{height}" '
                       f'viewBox="{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}">' + "".join(groups) + "</svg>")
        png = out_dir / f"{name}_{label}.png"
        subprocess.check_call(["rsvg-convert", "-w", str(RASTER), "-h", str(height), str(svg), "-o", str(png)])
        svg.unlink()
        print(png)


if __name__ == "__main__":
    main()
