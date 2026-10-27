"""Shared kit for hand-drawn pictures: geometry, the brush, and item packing.

A hand-drawn part is (color, geom) or (color, geom, expect) in page pixels,
y down, no PAD. brush() lints those parts and stamps them through bluehairsvg
exactly the way a traced shape list is stamped, so the wobble, the fill and the
4x raster match `flat.py item`. What tracing gives for free — a near-black
outline — is ink_under(): every coloured part grows a black silhouette under it.
Parts that cannot be shapes (a C-shaped handle fails the elongated test, so it
would come out as a compact outline instead of a stroke) go through `underlay`
as strokes spliced below every part, where their ends can hide.

An item script is data plus three functions, and `flat.py draw` runs it:

    NAME = "beer_mug"
    W, H = 260, 260
    JOINT = (52, 162)   # where an edge attaches, page px
    EDGE = 190          # bone length in page px, along +x from the joint

    def parts(): ...
    def underlay(hand): ...   # optional
    def details(hand): ...    # optional

pack() wraps one bone into an .ati: bm_1_state_0.png, meta scale 0.25,
name @:<NAME>, offset -((JOINT + PAD) * 4).
"""
import io
import math
import sys
import zipfile
from pathlib import Path

from shapely import affinity
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))
import shape_lint
import flat
from hand import Hand

src = flat.tracer
SAMPLE = src.SAMPLE
PAD = src.PAD
JITTER = src.JITTER
INK = "#222222"
# Width of the black outline carried by the silhouette under each part.
RIM = 10


# --- geometry -------------------------------------------------------------

def poly(points):
    geom = Polygon(points)
    if not geom.is_valid:
        geom = geom.buffer(0)
    if geom.is_empty or geom.geom_type != "Polygon":
        raise SystemExit(f"polygon failed: {points[:4]}")
    return geom


def disc(cx, cy, r):
    """Round part with edges about 5 px, so the 14 px brush shows no facets."""
    quads = max(8, int(round(math.pi * r / 2 / 5)))
    geom = Point(cx, cy).buffer(r, quad_segs=quads)
    if geom.geom_type != "Polygon":
        raise SystemExit(f"disc {(cx, cy, r)} failed")
    return geom


def ellipse(cx, cy, rx, ry):
    quads = max(8, int(round(math.pi * max(rx, ry) / 2 / 5)))
    geom = affinity.translate(
        affinity.scale(Point(0, 0).buffer(1, quad_segs=quads), rx, ry), cx, cy
    )
    if geom.geom_type != "Polygon":
        raise SystemExit(f"ellipse {(cx, cy, rx, ry)} failed")
    return geom


def capsule(p1, p2, rad, n=8):
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    base = math.atan2(dy, dx)
    pts = [(p2[0] + rad * math.cos(base + math.pi / 2 - math.pi * i / n),
            p2[1] + rad * math.sin(base + math.pi / 2 - math.pi * i / n))
           for i in range(n + 1)]
    pts += [(p1[0] + rad * math.cos(base - math.pi / 2 - math.pi * i / n),
             p1[1] + rad * math.sin(base - math.pi / 2 - math.pi * i / n))
            for i in range(n + 1)]
    return poly(pts)


def union(geoms):
    """Merged into one polygon, stairs smoothed for the brush."""
    merged = unary_union(list(geoms))
    if merged.geom_type != "Polygon":
        raise SystemExit(f"union is {merged.geom_type}, not one polygon")
    return merged.simplify(1.2, preserve_topology=True)


def ink_under(parts, rim=RIM):
    """Prepend a black silhouette grown by `rim` under each coloured part.

    The part's own stamp and closed stroke cover the middle, so what survives
    is a `rim` wide ring: the near-black outline a traced part gets for free.
    A part already inked is left alone. The ink silhouette is always stamped
    and filled, never stroked, so it carries no expect: the grown ring of a
    limb reads compact, and passing the limb's expect down would contradict.
    """
    out = []
    for shape in parts:
        color, geom = shape[0], shape[1]
        if color != INK:
            out.append((INK, geom.buffer(rim, join_style="round")))
        out.append(shape)
    return out


# --- brush -----------------------------------------------------------------

class Drawing:
    def __init__(self, svg, canvas, scene, session, seed):
        self.svg = svg
        self.canvas = canvas
        self.scene = scene
        self.session = session
        self.seed = seed

    def details(self, paint):
        """Strokes on top of every part: light edges, shade, ticks, bubbles."""
        hand = Hand(self.seed + 1, (0, 0))
        hand.t = self.session["duration"]
        paint(hand)
        self.scene.run(hand.ops)
        self.svg = rescale(self.scene.svg(False), self.canvas)
        return self

    def raster(self):
        """The 4x bitmap, uncropped, so the joint stays where pack() puts it."""
        return flat.rasterize(self.svg, self.canvas[0] * SAMPLE, self.canvas[1] * SAMPLE)


def rescale(svg, canvas):
    """Rewrite the header for 4x pixels. Same two swaps bluehairsvg does."""
    width, height = canvas
    svg = svg.replace(
        f'width="{width}" height="{height}"',
        f'width="{width * SAMPLE}" height="{height * SAMPLE}"',
        1,
    )
    return svg.replace(
        f'viewBox="0 0 {width} {height}"',
        f'viewBox="0 0 {width} {height}" shape-rendering="geometricPrecision"',
        1,
    )


def page_points(points, pad=PAD):
    """Page coords to padded-canvas coords, for underlay() and details()."""
    return [(x + pad, y + pad) for x, y in points]


def stroke(hand, points, color, size, closed=False, jitter=None):
    """One hand stroke in page coords. Curve, so a long edge stays smooth."""
    hand.stroke(
        hand.curve(page_points(points)) if not closed
        else hand.curve(page_points(points), closed=True),
        color, size=size, jitter=JITTER if jitter is None else jitter, closed=closed,
    )


def brush(parts, size, name, underlay=None, jitter=None):
    """Lint, stamp, outline, fill, splice the underlay below, rewrite at 4x.

    size is the page (width, height) in px without PAD; the canvas grows by
    PAD on every side. underlay(hand) draws strokes that end up under every
    part, so their ends can disappear behind a neighbouring shape. jitter
    scales the brush wobble; the tracer's own 0.5 when None, and 0 for
    crisp edges. A module may set JITTER to pass it down from item().
    """
    jitter = JITTER if jitter is None else jitter
    plans, issues = shape_lint.lint(parts, size)
    shape_lint.report(plans, issues, name)
    if issues:
        raise SystemExit(f"{name}: {len(issues)} shape issues")
    shapes = []
    for shape in parts:
        color, geom = shape[0], shape[1]
        if geom.is_empty or geom.geom_type != "Polygon" or geom.area < 30:
            raise SystemExit(f"{color} is not a shape of area >= 30")
        shapes.append((geom.area, color, geom))
    seed = flat.seed_for(name)
    dummy = type("Png", (), {"size": tuple(size)})()
    own = src.JITTER
    src.JITTER = jitter
    try:
        _, canvas = src.brush_svg(dummy, shapes, seed)
    finally:
        src.JITTER = own
    scene, session = src.brush_svg.scene, src.brush_svg.session
    if underlay is not None:
        hand = Hand(seed + 1, (0, 0))
        hand.t = session["duration"]
        underlay(hand)
        cut = len(scene.layers)
        scene.run(hand.ops)
        scene.layers = scene.layers[cut:] + scene.layers[:cut]
    return Drawing(rescale(scene.svg(False), canvas), canvas, scene, session, seed)


# --- item --------------------------------------------------------------------

def pack(drawing, out_dir, name, joint, edge_len):
    """Write <out_dir>/<name>.ati with one bone. The joint is in page px.

    new_offset = -((joint + PAD) * SAMPLE), the formula `flat.py item`
    derives from the old offset. Android groups frames by `bm_<id>_state_<n>`,
    so the bone is bm_1_state_0.png.
    """
    out_dir = Path(out_dir)
    png = drawing.raster()
    jx, jy = (joint[0] + PAD) * SAMPLE, (joint[1] + PAD) * SAMPLE
    if not (0 <= jx < png.width and 0 <= jy < png.height):
        raise SystemExit(f"joint ({jx}, {jy}) is off the {png.size} bitmap")
    bone = "bm_1_state_0.png"
    model = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<unit name="@:{name}">\n'
        '\t<point id="1" x="0" y="0" base="true" attachable="slave" />\n'
        f'\t<point id="2" x="{edge_len * SAMPLE:.0f}" y="0" par="1" />\n'
        "</unit>\n"
    )
    assets = (
        "<?xml version='1.0' encoding='UTF-8' standalone='no' ?>"
        f'<unit name="@:{name}">'
        f'<edgeAsset start="1" end="2" bm="{bone}" '
        f'x_offset="{-jx:.4f}" y_offset="{-jy:.4f}" weight="0" state="0"/>'
        "</unit>"
    )
    meta = (
        '{"author":"","name":"' + name + '","pack":"@","appVersion":66,'
        f'"face_len":0,"multiframed":false,"scale":{1 / SAMPLE}}}'
    )
    thumb = png.copy()
    thumb.thumbnail((160, 160))
    (out_dir / "drawing.svg").write_text(drawing.svg)
    path = out_dir / f"{name}.ati"
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as out:
        out.writestr("model.xml", model)
        out.writestr("assets.xml", assets)
        out.writestr("meta.txt", meta)
        out.writestr(f"{name}.name", b"")
        out.writestr("thumb.png", _bytes(thumb))
        out.writestr("poster.png", _bytes(png))
        out.writestr(bone, _bytes(png))
    print(f"{name}: bitmap {png.size} joint ({jx:.0f}, {jy:.0f}) scale {1 / SAMPLE}")
    print("wrote", path, path.stat().st_size)
    return path


def item(module, out_dir=None):
    """Run an item module: NAME, W, H, JOINT, EDGE, parts(), maybe underlay/details."""
    name = getattr(module, "NAME", None)
    if not name:
        raise SystemExit(f"{module.__file__} has no NAME")
    for attr in ("JOINT", "EDGE"):
        if not hasattr(module, attr):
            raise SystemExit(f"{name}: no {attr}")
    out_dir = Path(out_dir) if out_dir else Path(module.__file__).resolve().parent
    out_dir.mkdir(parents=True, exist_ok=True)
    # A module's JITTER tightens every stroke: parts and details alike.
    own = globals()["JITTER"]
    globals()["JITTER"] = getattr(module, "JITTER", own)
    try:
        drawing = brush(
            module.parts(), (module.W, module.H), name,
            underlay=getattr(module, "underlay", None),
            jitter=globals()["JITTER"],
        )
    finally:
        globals()["JITTER"] = own
    details = getattr(module, "details", None)
    if details is not None:
        drawing.details(details)
    return pack(drawing, out_dir, name, module.JOINT, module.EDGE)


def _bytes(im):
    raw = io.BytesIO()
    im.save(raw, format="PNG")
    return raw.getvalue()
