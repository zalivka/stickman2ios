"""Export a BonePaper session.json to SVG by replaying it as vector geometry (shapely).

Strokes become round-capped polylines (outline polygons with --flat, or once an eraser cut them).
Bucket fills become polygons found the way BonePaper's flood fill finds its pixels:
- tap on empty paper: the unpainted face around the tap, grown by the fill ring and put under everything;
- tap on paint: the connected visible area of (nearly) the tapped colour, put on top.

usage: .venv/bin/python svg_export.py <session_dir> [--flat] [-o out.svg]
"""
import argparse
import json
import math
from pathlib import Path

from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

# BonePaperDocument.fillRing (3 sampled px) in sheet px.
FILL_RING = 1.5
# BonePaperDocument.fillNeighbourLimit, OKLab.
NEIGHBOUR = 0.06
SIMPLIFY = 0.25


def oklab(hex_color):
    def lin(v):
        c = v / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(int(hex_color[i:i + 2], 16)) for i in (1, 3, 5))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717876 * m - 0.8086757660 * s)


def color_distance(a, b):
    return math.dist(oklab(a), oklab(b))


class Layer:
    def __init__(self, kind, geom, color, opacity, points=None, size=None):
        self.kind = kind
        self.geom = geom
        self.color = color
        self.opacity = opacity
        self.points = points
        self.size = size
        self.cut = False

    def minus(self, shape):
        other = Layer(self.kind, self.geom.difference(shape), self.color, self.opacity, self.points, self.size)
        other.cut = True
        return other


class Scene:
    def __init__(self, session):
        canvas, final = session["canvas"], session["final"]
        self.ox = canvas["originX"] - final["extraLeft"]
        self.oy = canvas["originY"] - final["extraTop"]
        self.width, self.height = final["width"], final["height"]
        self.page = box(0, 0, self.width, self.height)
        self.paper = session.get("paper")
        self.layers = []
        self.undo_stack = []
        self.redo_stack = []

    def local(self, p):
        return (p[0] - self.ox, p[1] - self.oy)

    def run(self, ops):
        for op in ops:
            kind = op["op"]
            if kind == "stroke":
                if op["end"] == "commit":
                    self._push()
                    self.stroke(op)
            elif kind == "fill":
                self._push()
                self.fill(op)
            elif kind == "undo":
                self.redo_stack.append(self.layers)
                self.layers = self.undo_stack.pop()
            elif kind == "redo":
                self.undo_stack.append(self.layers)
                self.layers = self.redo_stack.pop()
            elif kind == "noop":
                continue
            else:
                raise SystemExit(f"svg_export: unsupported op {kind}")

    def _push(self):
        self.undo_stack.append(list(self.layers))
        self.redo_stack.clear()

    def stroke(self, op):
        pts = [self.local(p) for p in op["points"]]
        size = op["size"]
        line = LineString(pts) if len(set(pts)) > 1 else Point(pts[0])
        geom = line.buffer(size / 2, quad_segs=8).intersection(self.page)
        if op["erase"]:
            self.layers = [layer.minus(geom) for layer in self.layers]
            self.layers = [layer for layer in self.layers if not layer.geom.is_empty]
            return
        self.layers.append(Layer("stroke", geom, op["color"], op["opacity"], pts, size))

    def fill(self, op):
        at = Point(self.local(op["at"]))
        covered = unary_union([layer.geom for layer in self.layers])
        if not covered.contains(at):
            face = self._component(self.page.difference(covered), at)
            geom = face.buffer(FILL_RING, quad_segs=4).intersection(self.page)
            self.layers.insert(0, Layer("fill", geom, op["color"], op["opacity"]))
            return
        seed = self._top_color(at)
        visible = []
        above = Polygon()
        for layer in reversed(self.layers):
            part = layer.geom.difference(above)
            above = above.union(layer.geom)
            if color_distance(layer.color, seed) < NEIGHBOUR:
                visible.append(part)
        region = self._component(unary_union(visible), at)
        # Grown under the bounding lines: two antialiased edges on the same boundary leave a seam.
        geom = region.buffer(FILL_RING, quad_segs=4).intersection(self.page)
        self.layers.append(Layer("fill", geom, op["color"], op["opacity"]))

    def _top_color(self, at):
        for layer in reversed(self.layers):
            if layer.geom.contains(at):
                return layer.color
        raise SystemExit(f"svg_export: no paint under {at}")

    @staticmethod
    def _component(geom, at):
        parts = geom.geoms if isinstance(geom, MultiPolygon) else [geom]
        for part in parts:
            if part.contains(at):
                return part
        near = min(parts, key=lambda part: part.distance(at))
        if near.distance(at) > 1:
            raise SystemExit(f"svg_export: fill tap {at} is in no region")
        return near

    # --- SVG ------------------------------------------------------------------

    def svg(self, flat):
        out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
               f'viewBox="0 0 {self.width} {self.height}">']
        if self.paper:
            out.append(f'<rect x="0" y="0" width="{self.width}" height="{self.height}" fill="{self.paper}"/>')
        for layer in self.layers:
            if layer.kind == "stroke" and not flat and not layer.cut:
                out.append(self._polyline(layer))
            else:
                d = _path(layer.geom.simplify(SIMPLIFY))
                if d:
                    out.append(f'<path d="{d}" fill="{layer.color}"{_opacity("fill", layer.opacity)}/>')
        out.append("</svg>")
        return "\n".join(out) + "\n"

    @staticmethod
    def _polyline(layer):
        if len(set(layer.points)) == 1:
            x, y = layer.points[0]
            return (f'<circle cx="{_n(x)}" cy="{_n(y)}" r="{_n(layer.size / 2)}" fill="{layer.color}"'
                    f'{_opacity("fill", layer.opacity)}/>')
        pts = " ".join(f"{_n(x)},{_n(y)}" for x, y in layer.points)
        return (f'<polyline points="{pts}" fill="none" stroke="{layer.color}" stroke-width="{_n(layer.size)}"'
                f' stroke-linecap="round" stroke-linejoin="round"{_opacity("stroke", layer.opacity)}/>')


def _n(v):
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def _opacity(kind, value):
    return "" if value >= 1 else f' {kind}-opacity="{_n(value) if value >= 0.1 else round(value, 3)}"'


def _ring(coords):
    pts = list(coords)[:-1]
    return "M" + " L".join(f"{_n(x)} {_n(y)}" for x, y in pts) + " Z"


def _path(geom):
    """Holes wind opposite to their exterior, so the nonzero rule cuts them without fill-rule."""
    if geom.is_empty:
        return ""
    polys = geom.geoms if hasattr(geom, "geoms") else [geom]
    rings = []
    for poly in polys:
        if not isinstance(poly, Polygon) or poly.is_empty:
            continue
        poly = orient(poly, sign=1.0)
        rings.append(_ring(poly.exterior.coords))
        rings += [_ring(hole.coords) for hole in poly.interiors]
    return " ".join(rings)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("session_dir", type=Path)
    parser.add_argument("--flat", action="store_true", help="every stroke as its outline polygon")
    parser.add_argument("-o", "--out", type=Path)
    args = parser.parse_args()
    session = json.loads((args.session_dir / "session.json").read_text())
    scene = Scene(session)
    scene.run(session["ops"])
    out = args.out or args.session_dir / ("drawing_flat.svg" if args.flat else "drawing.svg")
    out.write_text(scene.svg(args.flat))
    print(out, f"{len(scene.layers)} elements, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
