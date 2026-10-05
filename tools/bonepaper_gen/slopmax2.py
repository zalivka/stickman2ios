"""Slopmax in one command: item, scene, background, or a shape lint.

  .venv/bin/python slopmax2.py item newstickman:sword
  .venv/bin/python slopmax2.py item /tmp/lion.ati --name lion
  .venv/bin/python slopmax2.py scene ../../at_elements/demo/demo_camera.ats -o ../../at_elements/demo/demo_camera2.ats
  .venv/bin/python slopmax2.py bg picture.png -o out/picture/picture.zip
  .venv/bin/python slopmax2.py lint out/storypic/build.py

The tracer is bluehairsvg (components, boundary_loops, brush_svg). Every traced
shape list goes through shape_lint before the brush: fatal issues stop the run,
warnings are printed. `lint` exits non-zero on any issue.
"""
import argparse
import importlib.util
import io
import json
import math
import re
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from shapely.geometry import LineString, Polygon

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))
import shape_lint
from hand import Hand

spec = importlib.util.spec_from_file_location("bluehairsvg", GEN / "out/bluehairsvg/build.py")
tracer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tracer)

REPO = GEN.parents[1]
PACKS = REPO / "at_elements/packs"
SAMPLE = tracer.SAMPLE
PAD = tracer.PAD
PAGE = (640, 480)
SENTINEL = (255, 0, 180)
INK_MARK = (160, 160, 160)
# A background has gray rocks, so its black cannot become gray 160. It gets its own mark.
BLACK_SENTINEL = (0, 200, 90)
BUNDLE = "zalivka.animation"
APP_DIR = "Library/Application Support/at_elements"


def seed_for(label):
    return 17 + (sum(label.encode()) % 80)


# --- bone tracing -----------------------------------------------------------

def prepare(im, kind=None):
    """Ink and line art carry black and white the tracer would drop. Mark them first."""
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.int16)
    alpha = arr[:, :, 3]
    solid = alpha > 200
    count = int(solid.sum())
    if count < 10:
        raise SystemExit("empty bitmap")
    dark = solid & np.all(rgb <= 24, axis=2)
    peak = rgb.max(axis=2)
    white = solid & (peak >= 220) & ((peak - rgb.min(axis=2)) < 16)
    if kind is None:
        if int(dark.sum()) >= 0.8 * count:
            kind = "ink"
        elif int(dark.sum()) > 40 and int(white.sum()) > 40:
            kind = "line"
        else:
            kind = "color"
    if kind == "color":
        return im.convert("RGBA"), kind
    arr = arr.copy()
    if kind == "line":
        arr[white] = (*SENTINEL, 255)
    mark = (alpha > 32) & np.all(rgb <= 40, axis=2)
    arr[mark] = (*INK_MARK, 255)
    return Image.fromarray(arr), kind


def paint_color(kind, color):
    if kind == "ink":
        return "#222222"
    if kind != "line":
        return color
    rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
    if all(abs(c - s) < 30 for c, s in zip(rgb, SENTINEL)):
        return "#FFFFFF"
    if max(rgb) - min(rgb) < 24:
        return "#222222"
    return color


def color_centers(rgb, solid, merge):
    samples = rgb[solid]
    if len(samples) == 0:
        return []
    uniq = np.unique((samples // 16) * 16, axis=0)
    centers = []
    for color in uniq:
        color = color.astype(np.int32)
        if any(np.abs(color - center).max() <= merge for center in centers):
            continue
        centers.append(color)
    return centers


def regions(png, merge):
    """bluehairsvg.regions with a merge distance, and a ring keeps its outer loop.

    A loop is kept when its representative point lands in the blob. A ring (a
    star's rim, a sword's outline) fails that test, so the largest loop is kept
    anyway and the colours inside paint over its fill.
    """
    arr = np.array(png.convert("RGBA"))
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3]
    black = (alpha > 32) & np.all(rgb <= 24, axis=2)
    fringe = black.copy()
    fringe[1:] |= black[:-1]
    fringe[:-1] |= black[1:]
    fringe[:, 1:] |= black[:, :-1]
    fringe[:, :-1] |= black[:, 1:]
    white = np.all(rgb >= 240, axis=2)
    peak = rgb.max(axis=2)
    gray = ((peak - rgb.min(axis=2)) < 24) & (peak >= 70)
    solid = (alpha > 200) & ~fringe & ~white & (gray | (peak >= 110))
    centers = color_centers(rgb, solid, merge)
    if not centers:
        raise SystemExit("no colour")
    flat = rgb.reshape(-1, 3).astype(np.int32)
    nearest = np.stack([np.abs(flat - center).sum(axis=1) for center in centers]).argmin(axis=0)
    nearest = nearest.reshape(alpha.shape)
    silhouette = alpha > 32
    assigned = np.full(alpha.shape, -1, np.int16)
    assigned[solid] = nearest[solid].astype(np.int16)
    for _ in range(16):
        nxt = assigned.copy()
        up = np.full_like(assigned, -1)
        up[1:, :] = assigned[:-1, :]
        down = np.full_like(assigned, -1)
        down[:-1, :] = assigned[1:, :]
        left = np.full_like(assigned, -1)
        left[:, 1:] = assigned[:, :-1]
        right = np.full_like(assigned, -1)
        right[:, :-1] = assigned[:, 1:]
        for moved in (up, down, left, right):
            take = (nxt < 0) & silhouette & (moved >= 0)
            nxt[take] = moved[take]
        if np.array_equal(nxt, assigned):
            break
        assigned = nxt
    shapes = []
    for index in range(len(centers)):
        mask = assigned == index
        if mask.sum() < 40:
            continue
        for pixels in tracer.components(mask):
            if len(pixels) < 40:
                continue
            blob = np.zeros_like(mask)
            ys, xs = zip(*pixels)
            blob[list(ys), list(xs)] = True
            seeds = solid & blob
            if int(seeds.sum()) < 20:
                continue
            tone = np.median(rgb[seeds], axis=0)
            loops = []
            for loop in tracer.boundary_loops(blob):
                poly = Polygon(loop)
                if not poly.is_valid:
                    poly = poly.buffer(0)
                if poly.is_empty or poly.area < 30:
                    continue
                probe = poly.representative_point()
                x, y = int(probe.x), int(probe.y)
                inside = 0 <= y < blob.shape[0] and 0 <= x < blob.shape[1] and bool(blob[y, x])
                loops.append((poly, inside))
            kept = [poly for poly, inside in loops if inside]
            if loops:
                biggest, inside = max(loops, key=lambda item: item[0].area)
                if not inside:
                    kept.append(biggest)
            for outer in kept:
                geom = outer.buffer(2.5, join_style="round", quad_segs=4).simplify(tracer.STRAIGHTEN, preserve_topology=True)
                if geom.is_empty or geom.geom_type != "Polygon" or geom.area < 30:
                    continue
                shapes.append((geom.area, "#{:02X}{:02X}{:02X}".format(*[int(v) for v in tone]), geom))
    if not shapes:
        raise SystemExit("no regions")
    shapes.sort(key=lambda item: item[0], reverse=True)
    return shapes


def checked(shapes, size, label):
    plans, issues = shape_lint.lint([(color, geom) for _, color, geom in shapes], size)
    fatal = [issue for issue in issues if issue.fatal]
    warns = [issue for issue in issues if not issue.fatal]
    limbs = sum(1 for p in plans if p.kind == "limb")
    print(f"{label}: {len(plans)} shapes ({limbs} limbs), {len(warns)} warnings")
    for issue in warns:
        print(f"  warn  {issue.text}")
    if fatal:
        for issue in fatal:
            print(f"  FATAL {issue.text}")
        raise SystemExit(f"{label}: {len(fatal)} fatal shape issues")


def rasterize(svg, width, height):
    proc = subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height), "-f", "png"],
        input=svg.encode(), capture_output=True, check=True,
    )
    out = Image.open(io.BytesIO(proc.stdout)).convert("RGBA")
    if out.size != (width, height):
        raise SystemExit(f"rsvg gave {out.size}, wanted {(width, height)}")
    return out


def render_bone(im, label, opts):
    """Full padded canvas at SAMPLE. Not cropped, so the joint stays where new_offset puts it."""
    work, kind = prepare(im, opts.kind)
    shapes = regions(work, opts.merge)
    shapes = [(area, paint_color(kind, color), geom) for area, color, geom in shapes]
    checked(shapes, work.size, f"{label} [{kind}]")
    svg, canvas = tracer.brush_svg(work, shapes, seed=seed_for(label))
    out = rasterize(svg, canvas[0] * SAMPLE, canvas[1] * SAMPLE)
    if out.getchannel("A").getbbox() is None:
        raise SystemExit(f"{label}: empty bone")
    raw = io.BytesIO()
    out.save(raw, format="PNG")
    return raw.getvalue(), out


def new_offset(xo, yo):
    return (-(-xo + PAD) * SAMPLE, -(-yo + PAD) * SAMPLE)


def convert_ati(data, system_name, opts, review):
    """Redraw every bone bitmap. Points ×SAMPLE, offsets from the padded joint, meta scale ÷SAMPLE."""
    inner = zipfile.ZipFile(io.BytesIO(data))
    assets = inner.read("assets.xml").decode()
    model = inner.read("model.xml").decode()
    drawn = {}

    def edge_sub(match):
        tag = match.group(0)
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', tag))
        bm = attrs["bm"]
        if bm not in drawn:
            im = Image.open(io.BytesIO(inner.read(bm))).convert("RGBA")
            drawn[bm] = render_bone(im, f"{system_name}:{bm}", opts)
        xo, yo = new_offset(float(attrs["x_offset"]), float(attrs["y_offset"]))
        tag = re.sub(r'x_offset="[^"]*"', f'x_offset="{xo:.4f}"', tag, count=1)
        tag = re.sub(r'y_offset="[^"]*"', f'y_offset="{yo:.4f}"', tag, count=1)
        return tag

    assets = re.sub(r"<edgeAsset\b.*?/>", edge_sub, assets, flags=re.DOTALL)
    if not drawn:
        raise SystemExit(f"{system_name}: no edgeAsset bitmaps")
    old_name = re.search(r'<unit name="([^"]+)"', model).group(1)
    new_name = f"@:{system_name}"
    model = model.replace(f'name="{old_name}"', f'name="{new_name}"', 1)
    assets = assets.replace(f'name="{old_name}"', f'name="{new_name}"', 1)

    def scale_attr(match):
        return f'x="{float(match.group(1)) * SAMPLE:.6g}" y="{float(match.group(2)) * SAMPLE:.6g}"'

    model = re.sub(r'\bx="(-?\d+(?:\.\d+)?)"\s+y="(-?\d+(?:\.\d+)?)"', scale_attr, model)
    meta = json.loads(inner.read("meta.txt").decode()) if "meta.txt" in inner.namelist() else {}
    meta["scale"] = float(meta.get("scale", 1)) / SAMPLE
    meta["pack"] = "@"
    meta["name"] = system_name
    meta["multiframed"] = False
    largest = max(drawn.values(), key=lambda item: item[1].size[0] * item[1].size[1])[1]
    thumb = largest.copy()
    thumb.thumbnail((160, 160))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as out:
        out.writestr("model.xml", model)
        out.writestr("assets.xml", assets)
        out.writestr("meta.txt", json.dumps(meta, ensure_ascii=False))
        out.writestr(f"{system_name}.name", b"")
        thumb_buf = io.BytesIO()
        thumb.save(thumb_buf, format="PNG")
        out.writestr("thumb.png", thumb_buf.getvalue())
        for bm, (png, im) in drawn.items():
            out.writestr(bm, png)
            im.save(review / f"{system_name}_{Path(bm).stem}.png")
    print(f"{system_name}: bones={len(drawn)} scale={meta['scale']:.6g}")
    return buf.getvalue()


# --- sources ------------------------------------------------------------------

def find_pack(prefix):
    hits = [p for p in sorted(PACKS.glob("*.atp")) if p.stem == prefix or p.stem.endswith("." + prefix)]
    if len(hits) != 1:
        raise SystemExit(f"pack {prefix!r}: {len(hits)} matches in {PACKS}")
    return hits[0]


def pack_item(prefix, item):
    pack = find_pack(prefix)
    entry = f"items/{item}.ati"
    with zipfile.ZipFile(pack) as z:
        if entry not in z.namelist():
            raise SystemExit(f"{pack.name} has no {entry}")
        return z.read(entry)


def item_source(spec):
    """A path to an .ati, or pack:item (newstickman:sword, zalivka.newstickman:sword)."""
    path = Path(spec)
    if path.suffix == ".ati":
        if not path.exists():
            raise SystemExit(f"missing {path}")
        return path.read_bytes(), path.stem
    if ":" not in spec:
        raise SystemExit(f"{spec!r} is neither an .ati path nor pack:item")
    prefix, item = spec.split(":", 1)
    return pack_item(prefix, item), item


# --- device -------------------------------------------------------------------

def deploy(device, source, dest):
    """devicectl needs to run outside the agent sandbox. One file per call, no --remove-existing-content."""
    subprocess.run([
        "xcrun", "devicectl", "device", "copy", "to", "--device", device,
        "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
        "--source", str(source), "--destination", f"{APP_DIR}/{dest}",
    ], check=True)
    print("deployed", dest)


# --- commands -----------------------------------------------------------------

def cmd_item(args):
    data, stem = item_source(args.source)
    name = args.name or stem
    out_dir = Path(args.out) if args.out else GEN / "out" / name
    out_dir.mkdir(parents=True, exist_ok=True)
    built = convert_ati(data, name, args, out_dir)
    path = out_dir / f"{name}.ati"
    path.write_bytes(built)
    print("wrote", path, path.stat().st_size)
    if args.deploy:
        deploy(args.deploy, path, f"customs/{name}.ati")


UNIT_TAG = re.compile(r"<unit\b[^>]*>")


def scene_units(xml):
    """Base unit names to trace, and the bubbles left alone."""
    traced, skipped = [], []
    for tag in UNIT_TAG.findall(xml):
        name = re.search(r'name="([^"]+)"', tag).group(1).split("#")[0]
        kind = re.search(r'\btype="([^"]*)"', tag)
        if kind and kind.group(1) == "bubble":
            if name not in skipped:
                skipped.append(name)
            continue
        if kind:
            raise SystemExit(f"{name}: unit type {kind.group(1)!r} is not handled")
        if name not in traced:
            traced.append(name)
    return traced, skipped


def cmd_scene(args):
    demo = zipfile.ZipFile(args.source)
    xml = demo.read("model.xml").decode()
    traced, skipped = scene_units(xml)
    traced = [name for name in traced if name not in args.skip]
    missing = [name for name in args.skip if name not in xml]
    if missing:
        raise SystemExit(f"--skip names not in the scene: {missing}")
    print("trace:", ", ".join(traced))
    print("leave:", ", ".join(skipped + args.skip) or "-")
    review = GEN / "out" / Path(args.output).stem
    review.mkdir(parents=True, exist_ok=True)
    entries = set(demo.namelist())
    embedded, added, renames = {}, {}, {}
    for name in traced:
        prefix, item = name.split(":", 1)
        if prefix == "@":
            entry = f"{item}.ati"
            if entry not in entries:
                raise SystemExit(f"{name} is not embedded in {args.source}")
            embedded[entry] = convert_ati(demo.read(entry), item, args, review)
        else:
            if f"{item}.ati" in entries or f"@:{item}" in traced:
                raise SystemExit(f"{name} would become @:{item}, which the scene already has")
            added[f"{item}.ati"] = convert_ati(pack_item(prefix, item), item, args, review)
            renames[name] = f"@:{item}"

    names = set(traced)

    def fix(match):
        tag = match.group(0)
        base = re.search(r'name="([^"]+)"', tag).group(1).split("#")[0]
        if base not in names:
            return tag
        if not re.search(r'\bscale="', tag):
            raise SystemExit(f"{base}: unit has no scale")
        return re.sub(r'\bscale="([^"]+)"', lambda s: f'scale="{float(s.group(1)) / SAMPLE:.8g}"', tag, count=1)

    xml = UNIT_TAG.sub(fix, xml)
    for old, new in renames.items():
        xml = re.sub(re.escape(old) + r'(?=[#"&])', new, xml)
        if old in xml:
            raise SystemExit(f"{old} left in the scene")
    for name in skipped:
        if name not in xml:
            raise SystemExit(f"{name} was removed")

    output = Path(args.output)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as out:
        for info in demo.infolist():
            if info.filename == "model.xml":
                out.writestr(info.filename, xml.encode())
            elif info.filename in embedded:
                out.writestr(info.filename, embedded[info.filename])
            else:
                out.writestr(info.filename, demo.read(info.filename))
        for entry, data in added.items():
            out.writestr(entry, data)
    output.write_bytes(buf.getvalue())
    items = {**embedded, **added}
    for entry, data in items.items():
        (review / entry).write_bytes(data)
    print("wrote", output, output.stat().st_size)
    if args.deploy:
        deploy(args.deploy, output, f"saved/{output.name}")
        for entry in items:
            deploy(args.deploy, review / entry, f"customs/{entry}")


def page_svg(scene, paper):
    rest = scene.svg(False).split("\n", 1)[1]
    w, h = PAGE
    header = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="{PAD} {PAD} {w} {h}" shape-rendering="geometricPrecision">'
    )
    return header + "\n" + f'<rect x="{PAD}" y="{PAD}" width="{w}" height="{h}" fill="{paper}"/>' + "\n" + rest


def mark_page(im):
    """Paper is a rect, so white and black on the page are content. Mark both so the tracer keeps them."""
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.int16)
    for mark in (SENTINEL, BLACK_SENTINEL):
        if (np.abs(rgb - np.array(mark)).max(axis=2) < 40).any():
            raise SystemExit(f"the picture already has colour {mark}; it cannot be a sentinel")
    # What the tracer drops: paper rgb >= 240, ink rgb <= 24 and its dark fringe.
    white = np.all(rgb >= 240, axis=2)
    black = np.all(rgb <= 40, axis=2)
    arr = arr.copy()
    arr[:, :, 3] = 255
    arr[white, :3] = SENTINEL
    arr[black, :3] = BLACK_SENTINEL
    return Image.fromarray(arr)


def fit_page(im):
    """Pad to 4:3 with the colour of the edge that grows, then scale to the page.

    A wide picture gets rows on top in the top-row colour (sky). A tall one gets
    columns on each side in that side's colour.
    """
    w, h = PAGE
    arr = np.array(im.convert("RGB"))
    ih, iw = arr.shape[:2]
    if iw * h > ih * w + iw:
        new_h = round(iw * h / w)
        top = np.median(arr[:4].reshape(-1, 3), axis=0).astype(np.uint8)
        page = np.empty((new_h, iw, 3), np.uint8)
        page[:] = top
        page[new_h - ih:] = arr
        print(f"padded {iw}x{ih} with {new_h - ih} rows on top")
    elif ih * w > iw * h + ih:
        new_w = round(ih * w / h)
        left = np.median(arr[:, :4].reshape(-1, 3), axis=0).astype(np.uint8)
        right = np.median(arr[:, -4:].reshape(-1, 3), axis=0).astype(np.uint8)
        page = np.empty((ih, new_w, 3), np.uint8)
        side = (new_w - iw) // 2
        page[:, :side] = left
        page[:, side + iw:] = right
        page[:, side:side + iw] = arr
        print(f"padded {iw}x{ih} with {new_w - iw} columns on the sides")
    else:
        page = arr
    out = Image.fromarray(page)
    return out if out.size == PAGE else out.resize(PAGE, Image.LANCZOS)


INK_LUMA = 90
INK_CONTRAST = 35


def flatten(im, colors):
    """Line art to flat colour regions at page size.

    1. Ink is removed and the neighbouring colours grow over it, so text on sky
       becomes sky. Ink is luma < INK_LUMA, or INK_CONTRAST darker than the 9 px
       median around it (a JPEG outline is gray, not black), grown by 1 px for
       the antialiased edge.
    2. The palette is cut to `colors` entries with an octree. Median cut spends
       its entries on sky and grass and drops a small purple sail.
    3. A 7 px mode filter on palette indices erases hatching and specks.
    Returns the flat picture and the ink mask (before the 1 px grow), which
    ink_strokes() redraws as lines.
    """
    arr = np.array(im.convert("RGB")).astype(np.int16)
    luma = (arr @ np.array([299, 587, 114]) // 1000).astype(np.uint8)
    local = np.array(Image.fromarray(luma).filter(ImageFilter.MedianFilter(9))).astype(np.int16)
    core = (luma < INK_LUMA) | (luma.astype(np.int16) < local - INK_CONTRAST)
    ink = np.array(Image.fromarray((core * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
    if ink.all():
        raise SystemExit("the whole picture is ink")
    for _ in range(64):
        if not ink.any():
            break
        grown = arr.copy()
        still = ink.copy()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            src_ok = np.roll(~ink, (dy, dx), axis=(0, 1))
            src_rgb = np.roll(arr, (dy, dx), axis=(0, 1))
            take = still & src_ok
            grown[take] = src_rgb[take]
            still &= ~take
        arr, ink = grown, still
    if ink.any():
        raise SystemExit(f"{int(ink.sum())} ink pixels left after 64 grow steps")
    flat = Image.fromarray(arr.astype(np.uint8)).quantize(colors=colors, method=Image.Quantize.FASTOCTREE)
    flat = flat.filter(ImageFilter.ModeFilter(7))
    return flat.convert("RGB"), core


def skeleton(mask):
    """Zhang-Suen thinning to one-pixel centre lines."""
    img = np.pad(mask.astype(np.uint8), 1)
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            c = img[1:-1, 1:-1]
            p2, p3, p4 = img[:-2, 1:-1], img[:-2, 2:], img[1:-1, 2:]
            p5, p6, p7 = img[2:, 2:], img[2:, 1:-1], img[2:, :-2]
            p8, p9 = img[1:-1, :-2], img[:-2, :-2]
            ring = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            count = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            turns = sum(((ring[i] == 0) & (ring[i + 1] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                side = ((p2 * p4 * p6) == 0) & ((p4 * p6 * p8) == 0)
            else:
                side = ((p2 * p4 * p8) == 0) & ((p2 * p6 * p8) == 0)
            drop = (c == 1) & (count >= 2) & (count <= 6) & (turns == 1) & side
            if drop.any():
                c[drop] = 0
                changed = True
    return img[1:-1, 1:-1].astype(bool)


def skeleton_paths(sk):
    """Split a skeleton into pixel paths that end at tips and junctions; loops are walked once."""
    pts = set(zip(*[v.tolist() for v in np.nonzero(sk)]))

    def around(p):
        y, x = p
        return [(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy or dx) and (y + dy, x + dx) in pts]

    nodes = {p for p in pts if len(around(p)) != 2}
    used = set()
    seen = set()
    paths = []

    def walk(start, first):
        path = [start, first]
        used.add(frozenset((start, first)))
        prev, cur = start, first
        while cur not in nodes:
            nxt = [q for q in around(cur) if q != prev and frozenset((cur, q)) not in used]
            if not nxt:
                break
            used.add(frozenset((cur, nxt[0])))
            path.append(nxt[0])
            prev, cur = cur, nxt[0]
        seen.update(path)
        return path

    for node in nodes:
        for nb in around(node):
            if frozenset((node, nb)) not in used:
                paths.append(walk(node, nb))
    for p in pts:
        if p not in seen:
            nbs = around(p)
            if nbs:
                nodes.add(p)
                paths.append(walk(p, nbs[0]))
                nodes.discard(p)
    return paths


INK_MIN = 4


def ink_strokes(source, ink, flat):
    """The removed ink as hand strokes: (points in page px, colour, size).

    An ink blob whose surroundings are all page colour is a caption or a leader
    line and is dropped. A path is coloured with the source pixels under it
    (outlines stay near-black, grass ticks dark green). Its width is the blob's
    ink area over its centre-line length. A tick shorter than the hand's 12 px
    start is stretched to 14 px along its own direction.
    """
    src = np.array(source.convert("RGB")).astype(np.int16)
    flat_rgb = np.array(flat).astype(np.int16)
    paper = np.median(flat_rgb[:4].reshape(-1, 3), axis=0)
    is_paper = np.abs(flat_rgb - paper).max(axis=2) < 24
    out = []
    dropped = 0
    for pixels in tracer.components(ink):
        ys = np.array([p[0] for p in pixels])
        xs = np.array([p[1] for p in pixels])
        y0, y1 = max(0, ys.min() - 4), min(ink.shape[0], ys.max() + 5)
        x0, x1 = max(0, xs.min() - 4), min(ink.shape[1], xs.max() + 5)
        blob = np.zeros((y1 - y0, x1 - x0), bool)
        blob[ys - y0, xs - x0] = True
        grown = np.array(Image.fromarray((blob * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0
        around = grown & ~ink[y0:y1, x0:x1]
        if around.any() and is_paper[y0:y1, x0:x1][around].mean() > 0.9:
            dropped += 1
            continue
        sk = skeleton(blob)
        length = int(sk.sum())
        if length == 0:
            continue
        size = float(np.clip(len(pixels) / length + 1.5, 3.5, 7.0))
        for path in skeleton_paths(sk):
            if len(path) < INK_MIN:
                continue
            pts = [(x + x0 + 0.5, y + y0 + 0.5) for y, x in path]
            reach = max(math.dist(pts[0], q) for q in pts)
            if reach < shape_lint.SLOP + 1:
                (ax, ay), (bx, by) = pts[0], pts[-1]
                d = math.dist((ax, ay), (bx, by)) or 1.0
                ux, uy = (bx - ax) / d, (by - ay) / d
                if d < 1.0:
                    ux, uy = 0.0, 1.0
                mx, my = (ax + bx) / 2, (ay + by) / 2
                pts = [(mx - ux * 7, my - uy * 7), (mx + ux * 7, my + uy * 7)]
            else:
                pts = list(LineString(pts).simplify(1.0).coords)
            tone = np.median(src[[p[0] + y0 for p in path], [p[1] + x0 for p in path]], axis=0)
            out.append((pts, "#{:02X}{:02X}{:02X}".format(*[int(v) for v in tone]), size))
    print(f"ink: {len(out)} strokes, {dropped} caption blobs dropped")
    return out


def inset(item):
    """Pull a compact outline inside its region.

    A traced page is a partition: every region touches its neighbours. The closed
    outline is centred on the edge and spreads size/2 outward, over whatever was
    drawn before (rocks drawn after a figure ate its legs). regions() already grew
    each shape by 2.5, so shrink by size/2 - 2.5. A sliver that does not survive, or
    is too short for the hand's 12 px start, is antialias fringe and is dropped.
    Limbs are strokes as wide as the part and stay.
    """
    area, color, geom = item
    p = shape_lint.plan(0, color, geom)
    if p.kind == "limb":
        return item
    shrunk = geom.buffer(-(p.size / 2 - 2.5), join_style="round")
    parts = [
        part for part in tracer.svg_export.polygons_of(shrunk)
        if part.area >= 30 and max(part.bounds[2] - part.bounds[0], part.bounds[3] - part.bounds[1]) >= shape_lint.SLOP + 2
    ]
    if not parts:
        return None
    best = max(parts, key=lambda part: part.area)
    return (best.area, color, best)


def page_color(color):
    rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
    if all(abs(c - s) < 30 for c, s in zip(rgb, SENTINEL)):
        return "#FFFFFF"
    if all(abs(c - s) < 30 for c, s in zip(rgb, BLACK_SENTINEL)):
        return "#222222"
    return color


def cover_thumb(image, side=100):
    scale = max(side / image.width, side / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left = (resized.width - side) // 2
    top = (resized.height - side) // 2
    return resized.crop((left, top, left + side, top + side))


def cmd_bg(args):
    """A flat-colour 4:3 picture to bg.png, bg.svg and thumb.png in one zip.

    The largest shape reaching three page edges is the page colour (a sky stops at
    the ground, which covers the bottom of the rect). It becomes
    a rect, not a brushed shape. White and black are marked first, so they stay.
    With --flatten, line art and comics are flattened first (see flatten()).
    """
    w, h = PAGE
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    im = fit_page(Image.open(args.source).convert("RGB"))
    lines = []
    if args.flatten:
        source = im
        im, ink = flatten(source, args.flatten)
        im.save(output.parent / "flat.png")
        lines = ink_strokes(source, ink, im)
    work = mark_page(im.convert("RGBA"))
    shapes = regions(work, args.merge)
    shapes = [(area, page_color(color), geom) for area, color, geom in shapes]

    def spans(geom):
        x0, y0, x1, y1 = geom.bounds
        return sum((x0 <= 3, y0 <= 3, x1 >= w - 3, y1 >= h - 3)) >= 3

    pages = [item for item in shapes if spans(item[2])]
    if not pages:
        raise SystemExit("no shape reaches three page edges; there is no page colour")
    page = max(pages, key=lambda item: item[0])
    paper = page[1]
    shapes = [inset(item) for item in shapes if item is not page]
    shapes = [item for item in shapes if item is not None]
    label = output.stem
    checked(shapes, PAGE, f"{label} paper={paper}")
    tracer.brush_svg(work, shapes, seed=seed_for(label))
    scene = tracer.brush_svg.scene
    if lines:
        hand = Hand(seed_for(label) + 1, (0, 0))
        hand.t = tracer.brush_svg.session["duration"]
        for pts, color, size in lines:
            keys = [(x + PAD, y + PAD) for x, y in pts]
            hand.stroke(hand.curve(keys), color, size=size, jitter=tracer.JITTER)
        scene.run(hand.ops)
    svg = page_svg(scene, paper)
    if "#FF00B4" in svg:
        raise SystemExit("sentinel left in the background")
    png = rasterize(svg, w * 2, h * 2)
    (output.parent / "bg.svg").write_text(svg)
    png.save(output.parent / "bg.png")
    thumb = cover_thumb(png)
    thumb.save(output.parent / "thumb.png")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as out:
        for name in ("bg.png", "bg.svg", "thumb.png"):
            out.write(output.parent / name, name)
    print("wrote", output, output.stat().st_size)
    if args.deploy:
        millis = int(time.time() * 1000)
        deploy(args.deploy, output, f"bgs/{millis}.zip")
        print(f"chooser name usermade:{millis}")


def cmd_lint(args):
    path = Path(args.script).resolve()
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(path.stem + "_lint", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "parts"):
        raise SystemExit(f"{path} has no parts()")
    size = (getattr(module, "W", PAGE[0]), getattr(module, "H", PAGE[1]))
    plans, issues = shape_lint.lint(module.parts(), size)
    shape_lint.report(plans, issues, path.parent.name)
    if issues:
        raise SystemExit(f"{len(issues)} issues")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def trace_opts(p, bones=True):
        p.add_argument("--merge", type=int, default=36, help="colour centre merge (16 splits gray 128 from 160)")
        if bones:
            p.add_argument("--kind", choices=("ink", "line", "color"), help="force the bone class for every bitmap")
        p.add_argument("--deploy", metavar="DEVICE", help="devicectl device id; run outside the sandbox")

    p = sub.add_parser("item", help="redraw one .ati")
    p.add_argument("source", help="path/to/x.ati or pack:item")
    p.add_argument("--name", help="system name, default the item name")
    p.add_argument("--out", help="output dir, default out/<name>")
    trace_opts(p)
    p.set_defaults(run=cmd_item)

    p = sub.add_parser("scene", help="redraw every bitmap unit of an .ats")
    p.add_argument("source")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--skip", action="append", default=[], metavar="UNIT", help="base unit name to leave as is")
    trace_opts(p)
    p.set_defaults(run=cmd_scene)

    p = sub.add_parser("bg", help="redraw a flat-colour 4:3 picture as a background zip")
    p.add_argument("source")
    p.add_argument("-o", "--output", required=True, help="zip path; bg.png, bg.svg, thumb.png go beside it")
    p.add_argument("--flatten", type=int, nargs="?", const=24, metavar="COLORS", help="line art or comic: drop ink and text, octree to COLORS (24), mode filter")
    trace_opts(p, bones=False)
    p.set_defaults(run=cmd_bg)

    p = sub.add_parser("lint", help="check parts() of a shape script")
    p.add_argument("script")
    p.set_defaults(run=cmd_lint)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
