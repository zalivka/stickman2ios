"""Saint-Petersburg Palace Square at Evening — single source SVG (`src.svg`) for both
`ink.py svg` (sketch) and `flat.py` (region brush).

Every stroke that is linework (a contour or a black structural line) is written as
`data-role="outline"`; `--nooutlines` drops exactly those and nothing else.

  .venv/bin/python flat.py lint out/palace_square/build.py
  .venv/bin/python out/palace_square/build.py
  .venv/bin/python out/palace_square/build.py --nooutlines
  .venv/bin/python ink.py svg out/palace_square/src.svg -o out/palace_square/sketch/palace_square_sketch.zip --wash-opacity 0.85 --slop 0.75
  .venv/bin/python ink.py svg out/palace_square/src.svg --nooutlines -o out/palace_square/sketch_nooutlines/palace_square_sketch.zip --wash-opacity 0.85 --slop 0.75
"""
import argparse
import math
import sys
import zipfile
from pathlib import Path

from shapely import affinity
from shapely.geometry import LineString, Point, Polygon

HERE = Path(__file__).resolve().parent
GEN = HERE.parents[1]
sys.path.insert(0, str(GEN))
from hand import Hand
import flat as engine

src = engine.tracer

W, H = 640, 480
PAPER = "#F2E3D2"
SUN_DISC = "#FFF6DF"
CLOUD_WARM = "#E8BC96"
GLOW_LOW = "#F4CF92"

STAFF_OCHRE = "#C89A58"
STAFF_SHADOW = "#946B36"
ARCH_VOID = "#252F40"
CHARIOT_BRONZE = "#35423E"

PALACE_TEAL = "#4E8A86"
PALACE_DARK = "#335E5B"
WHITE_TRIM = "#F4F1EC"

GRANITE_RED = "#8E453D"
GRANITE_HI = "#B86B60"
BRONZE = "#3E4B46"
PEDESTAL_DARK = "#2D3634"
GOLD = "#F0C252"
GOLD_WARM = "#F9DA78"

SQUARE_STONE = "#7D8594"
SQUARE_FOREGROUND = "#545C6C"
PAVING_LINE = "#B8C0CA"
INK = "#161D28"

OUTLINE = "outline"
DETAIL = "detail"

CX = 336


def poly(points):
    geom = Polygon(points)
    if not geom.is_valid:
        geom = geom.buffer(0)
    if geom.is_empty or geom.geom_type != "Polygon":
        raise SystemExit(f"polygon failed: {points[:4]}")
    return geom


def ellipse(cx, cy, rx, ry):
    quads = max(8, int(round(math.pi * max(rx, ry) / 2 / 5)))
    return affinity.translate(affinity.scale(Point(0, 0).buffer(1, quad_segs=quads), rx, ry), cx, cy)


def column_footprint():
    """The Alexander Column's front-most silhouette, base to capital.

    Everything behind the column is clipped by this. Background detail (lit
    windows, the General Staff cornice, the horizon) is painted *after* the
    column in painter's order and is not masked by it, so without this the
    windows shine straight through the granite shaft.
    """
    return (
        poly([(CX - 48, 392), (CX + 48, 392), (CX + 42, 350), (CX - 42, 350)])
        .union(poly([(CX - 30, 354), (CX + 30, 354), (CX + 26, 290), (CX - 26, 290)]))
        .union(poly([(CX - 17, 294), (CX + 17, 294), (CX + 14, 94), (CX - 14, 94)]))
        .union(poly([(CX - 25, 96), (CX + 25, 96), (CX + 17, 68), (CX - 17, 68)]))
    )


def scene_polygons():
    """(color, geom, expect, angle_deg, wash_mode, stroke_col, role)."""
    return [
        # Evening sun glow & warm sunset cloud bands high in the sky
        (SUN_DISC, ellipse(195, 132, 36, 36), "compact", 0, "stamp", GLOW_LOW, DETAIL),
        (CLOUD_WARM, ellipse(92, 118, 56, 22), "compact", 0, None, None, DETAIL),
        (CLOUD_WARM, ellipse(488, 112, 68, 22), "compact", 0, None, None, DETAIL),
        # Cobblestone square ground plane + deeper foreground band
        (SQUARE_STONE, poly([(-20, 312), (660, 312), (660, 490), (-20, 490)]), "compact", 0, None, None, DETAIL),
        (SQUARE_FOREGROUND, poly([(-20, 418), (660, 418), (660, 490), (-20, 490)]), "compact", 0, None, None, DETAIL),
        # General Staff Building: left wing, central Triumphal Arch block, right curving wing
        (STAFF_OCHRE, poly([(-20, 224), (126, 228), (126, 314), (-20, 314)]), "compact", 0, None, INK, OUTLINE),
        (STAFF_SHADOW, poly([(126, 178), (264, 178), (264, 314), (126, 314)]), "compact", 0, None, INK, OUTLINE),
        (STAFF_OCHRE, poly([(264, 230), (398, 234), (398, 314), (264, 314)]), "compact", 0, None, INK, OUTLINE),
        # Chariot of Glory plinth + sculptural group atop the arch
        (CHARIOT_BRONZE, poly([(156, 134), (234, 134), (242, 178), (148, 178)]), "compact", 0, "stamp", INK, OUTLINE),
        # Great semicircular archway opening + warm glowing inner court
        (ARCH_VOID, poly([(158, 314), (158, 240), (170, 218), (195, 208), (220, 218), (232, 240), (232, 314)]), "compact", 90, None, INK, OUTLINE),
        (GLOW_LOW, poly([(172, 314), (172, 258), (182, 244), (195, 238), (208, 244), (218, 258), (218, 314)]), "compact", 90, "stamp", INK, OUTLINE),
        # Winter Palace on the right: turquoise baroque facade + darker lower rustication
        (PALACE_TEAL, poly([(412, 198), (510, 198), (534, 172), (558, 198), (660, 194), (660, 316), (412, 316)]), "compact", 0, None, INK, OUTLINE),
        (PALACE_DARK, poly([(412, 270), (660, 268), (660, 316), (412, 316)]), "compact", 0, None, INK, OUTLINE),
        # Alexander Column: stepped granite base (compact), bronze pedestal, monolithic red granite shaft, capital + dome
        (PEDESTAL_DARK, poly([(CX - 48, 392), (CX + 48, 392), (CX + 42, 350), (CX - 42, 350)]), "compact", 0, None, INK, OUTLINE),
        (BRONZE, poly([(CX - 30, 354), (CX + 30, 354), (CX + 26, 290), (CX - 26, 290)]), "compact", 0, None, INK, OUTLINE),
        (GRANITE_RED, poly([(CX - 17, 294), (CX + 17, 294), (CX + 14, 94), (CX - 14, 94)]), "limb", 90, None, INK, OUTLINE),
        (GOLD, poly([(CX - 25, 96), (CX + 25, 96), (CX + 17, 68), (CX - 17, 68)]), "compact", 0, "stamp", INK, OUTLINE),
    ]


def clip_to_column(strokes):
    """Clip bands that belong to the buildings behind the column.

    Painter's order is the whole point: these strokes land *after* the column
    polygons, so nothing masks them and a window at x=330 draws straight over
    the granite shaft. Cutting the line at the column footprint is the only
    honest fix that survives into src.svg, and every engine inherits it.
    """
    footprint = column_footprint()
    out = []
    for pts, color, size, op, role in strokes:
        parts = LineString(pts).difference(footprint)
        for part in getattr(parts, "geoms", [parts]):
            # A piece shorter than hand.py's SLOP cannot be drawn; hand.py raises
            # instead of faking it, so dropping the crumb here is the only option.
            if part.is_empty or part.length < 14.0:
                continue
            if part.geom_type != "LineString":
                continue
            out.append(([tuple(c) for c in part.coords], color, size, op, role))
    return out


def courtyard_windows():
    """Lit windows seen *through* the Triumphal Arch, inside its opening.

    These are in front of nothing, so they are never clipped by the column.
    Each is 22 px tall: hand.py raises `stroke shorter than slop` below 12 px,
    and a short bar also gets stretched into a dash by the wobble.
    """
    return [
        ([(177, 252), (177, 274)], GOLD_WARM, 5.0, 0.85, DETAIL),
        ([(213, 252), (213, 274)], GOLD_WARM, 5.0, 0.85, DETAIL),
    ]


def scene_strokes():
    """(points, color, size, opacity, role)."""
    strokes = [
        # General Staff arch structural outlines (in front of the courtyard glow)
        ([(158, 312), (158, 240), (170, 218), (195, 208), (220, 218), (232, 240), (232, 312)], INK, 3.5, 0.95, OUTLINE),
        # Chariot of Glory: victory figure, triumphal arch crown, flanking horses
        ([(182, 138), (195, 114), (208, 138)], GOLD, 5.0, 1.0, DETAIL),
        ([(150, 156), (134, 134)], INK, 3.5, 1.0, OUTLINE),
        ([(240, 156), (256, 134)], INK, 3.5, 1.0, OUTLINE),
    ]
    strokes.extend(courtyard_windows())

    # --- Everything below is behind the column: clipped by its footprint ------
    behind = [
        # Horizon line along the cobblestone square
        ([(-12, 314), (652, 314)], INK, 3.0, 0.85, OUTLINE),
        # General Staff white cornice lines
        ([(-12, 232), (122, 236)], WHITE_TRIM, 4.2, 0.95, DETAIL),
        ([(130, 184), (260, 184)], WHITE_TRIM, 4.5, 0.95, DETAIL),
        ([(268, 238), (394, 242)], WHITE_TRIM, 4.2, 0.95, DETAIL),
        # Winter Palace white entablatures, pediment & colonnade pilasters
        ([(416, 204), (510, 202), (534, 178), (558, 202), (654, 198)], WHITE_TRIM, 4.5, 0.95, DETAIL),
        ([(416, 268), (654, 264)], WHITE_TRIM, 4.2, 0.95, DETAIL),
    ]
    for x in (438, 486, 534, 582, 628):
        behind.append(([(x, 208), (x, 262)], WHITE_TRIM, 3.8, 0.92, DETAIL))
    # Lit palace & General Staff windows ( >= 18 px travel so hand.py never drops them )
    for x in (16, 62, 102, 286, 330, 372):
        behind.append(([(x, 252), (x, 272)], GOLD_WARM, 6.5, 0.95, DETAIL))
        behind.append(([(x, 282), (x, 302)], GOLD_WARM, 6.5, 0.95, DETAIL))
    for x in (458, 506, 554, 602):
        behind.append(([(x, 222), (x, 244)], GOLD_WARM, 7.5, 0.95, DETAIL))
        behind.append(([(x, 278), (x, 298)], GOLD_WARM, 7.0, 0.95, DETAIL))
    strokes.extend(clip_to_column(behind))

    # --- The column itself: never clipped by its own footprint ---------------
    strokes.extend([
        ([(CX - 15, 292), (CX - 13, 96)], INK, 3.2, 0.92, OUTLINE),
        ([(CX + 15, 292), (CX + 13, 96)], INK, 3.2, 0.92, OUTLINE),
        ([(CX - 7, 284), (CX - 5, 104)], GRANITE_HI, 5.0, 0.90, DETAIL),
        # Bronze relief plaque on the pedestal. It is bronze, not gold or white:
        # a pale bar here reads as light shining *through* the column.
        ([(CX - 12, 322), (CX + 12, 322)], BRONZE, 9.0, 0.95, DETAIL),
        # Shaft/foot shadow where the pedestal meets the shaft, not a white band.
        ([(CX - 38, 352), (CX + 38, 352)], BRONZE, 3.5, 0.55, DETAIL),
        ([(CX, 70), (CX, 42)], BRONZE, 6.5, 1.0, DETAIL),
        ([(CX - 14, 58), (CX, 48), (CX + 14, 56)], INK, 3.2, 1.0, DETAIL),
        # Angel figure: bronze body, gold cross above it
        ([(CX + 6, 66), (CX + 6, 26)], GOLD, 3.4, 1.0, DETAIL),
        ([(CX - 4, 36), (CX + 16, 36)], GOLD, 3.2, 1.0, DETAIL),
        # Column evening cast shadow across the cobblestones
        ([(CX + 44, 382), (590, 408)], INK, 11.0, 0.42, DETAIL),
        # Geometric cobblestone arcs
        ([(126, 398), (236, 380), (336, 376), (436, 380), (546, 398)], PAVING_LINE, 3.6, 0.78, DETAIL),
        ([(36, 448), (188, 420), (336, 414), (484, 420), (614, 448)], PAVING_LINE, 4.2, 0.72, DETAIL),
    ])
    for x_end in (68, 195, 480, 592):
        strokes.append(([(CX, 392), (x_end, 472)], PAVING_LINE, 3.0, 0.58, DETAIL))
    # Warm evening reflections on the cobblestones
    for x, y, w in ((195, 338, 18), (195, 358, 14), (478, 340, 16), (576, 344, 16), (82, 346, 14)):
        strokes.append(([(x - w, y), (x + w, y + 2)], GOLD_WARM, 5.5, 0.78, DETAIL))
    # Flanking classical streetlamps (post + glowing lantern)
    for lx, ly_b, ly_t in ((96, 388, 304), (548, 390, 302), (238, 338, 284), (432, 338, 284)):
        strokes.append(([(lx, ly_b), (lx, ly_t)], INK, 3.6, 1.0, DETAIL))
        strokes.append(([(lx - 9, ly_t), (lx + 9, ly_t)], GOLD_WARM, 9.0, 0.98, DETAIL))
    # Three evening swifts/gulls in the upper sky
    for x, y in ((88, 74), (248, 66), (486, 72)):
        strokes.append(([(x - 12, y + 6), (x, y - 3), (x + 12, y + 6)], INK, 2.5, 1.0, DETAIL))
    return strokes


def write_source_svg(svg_path: Path = HERE / "src.svg"):
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'  <rect width="{W}" height="{H}" fill="{PAPER}"/>',
    ]
    for color, geom, _expect, ang, wash_mode, stroke_col, role in scene_polygons():
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in list(geom.exterior.coords)[:-1])
        st_attr = f'stroke="{stroke_col}" stroke-width="2.6"' if stroke_col else 'stroke="none"'
        wm_attr = f' data-wash="{wash_mode}"' if wash_mode else ""
        role_attr = f' data-role="{role}"' if stroke_col else ""
        lines.append(f'  <polygon points="{pts}" fill="{color}" {st_attr} data-angle="{ang}"{wm_attr}{role_attr}/>')
    for pts, color, size, op, role in scene_strokes():
        d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts)
        lines.append(
            f'  <path d="{d}" fill="none" stroke="{color}" stroke-width="{size}" '
            f'stroke-opacity="{op}" stroke-linecap="round" stroke-linejoin="round" data-role="{role}"/>'
        )
    lines.append("</svg>")
    svg_path.parent.mkdir(parents=True, exist_ok=True)
    svg_path.write_text("\n".join(lines) + "\n")


def parts():
    return [(color, geom, expect) for color, geom, expect, _a, _w, _s, _r in scene_polygons()]


def details(hand, outlines: bool = True):
    j = src.JITTER
    pad = src.PAD
    old_op = hand.opacity
    for pts, color, size, op, role in scene_strokes():
        if not outlines and role == OUTLINE:
            continue
        hand.opacity = op
        hand.stroke(hand.curve([(x + pad, y + pad) for x, y in pts]), color, size=size, jitter=j)
    hand.opacity = old_op


def render(out_dir: Path = HERE, outlines: bool = True):
    write_source_svg(HERE / "src.svg")
    out_dir.mkdir(parents=True, exist_ok=True)
    shapes = []
    for color, geom, _expect in parts():
        if geom.is_empty or geom.geom_type != "Polygon" or geom.area < 30:
            raise SystemExit(f"{color} is not a shape")
        shapes.append((geom.area, color, geom))
    dummy = type("Png", (), {"size": (W, H)})()
    seed = 17 + (sum(b"palace_square") % 80)
    src.brush_svg(dummy, shapes, seed, outlines=outlines)
    scene = src.brush_svg.scene
    hand = Hand(seed + 1, (0, 0))
    hand.t = src.brush_svg.session["duration"]
    details(hand, outlines=outlines)
    scene.run(hand.ops)
    svg = engine.page_svg(scene, PAPER)
    (out_dir / "bg.svg").write_text(svg)
    png = engine.rasterize(svg, W * 2, H * 2)
    png.save(out_dir / "bg.png")
    engine.cover_thumb(png).save(out_dir / "thumb.png")
    name = "palace_square_flat" if outlines else "palace_square_flat_nooutlines"
    out = out_dir / f"{name}.zip"
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for n in ("bg.png", "bg.svg", "thumb.png"):
            z.write(out_dir / n, n)
    print("wrote", out, out.stat().st_size)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Palace Square at evening: src.svg + flat bg zip")
    p.add_argument("--nooutlines", "-nooutlines", dest="outlines", action="store_false",
                   help="draw no data-role=\"outline\" stroke (contours and black structural lines)")
    p.add_argument("--out-dir", type=Path, default=None,
                   help="output directory (default: out/palace_square, or .../nooutlines with --nooutlines)")
    args = p.parse_args()
    out_dir = args.out_dir or (HERE if args.outlines else HERE / "nooutlines")
    render(out_dir, outlines=args.outlines)
