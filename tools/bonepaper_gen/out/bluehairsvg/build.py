"""Trace AT_Man bone bitmaps to outlines, redraw them with the sloppy hand brush, pack @:bluehairsvg.

Black ink is left out. Each remaining colour blob becomes a simplified outline, then a
BonePaper finger stroke (wide parts also get a fill). The raster stays at 4x so the
phone is not stretching a thumbnail.
"""
import math
import re
import subprocess
import sys
import zipfile
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.affinity import translate
from shapely.geometry import Polygon
from shapely.ops import polylabel

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from hand import Hand
import svg_export

SRC = Path("/tmp/atman/AT_Man.ati")
OUT = Path(__file__).resolve().parent
NAME = "bluehairsvg"
BRUSH = 14.0
WIDE = 42.0
# 2.0 swung a straight side by 8–12 px (one fat hump). 0.5 is the hand's normal slop.
JITTER = 0.5
PAD = 40
SAMPLE = 4
# Pixel stairs sit about half a pixel off the true edge.
STRAIGHTEN = 1.8


def is_black(rgb):
    return int(max(rgb)) <= 16


def boundary_loops(mask):
    """Closed outlines in pixel-corner coordinates. Interior is on the left, y down."""
    height, width = mask.shape
    outgoing = {}

    def add(start, end):
        outgoing.setdefault(start, []).append(end)

    for r in range(height):
        for c in range(width):
            if not mask[r, c]:
                continue
            if r == 0 or not mask[r - 1, c]:
                add((c + 1, r), (c, r))
            if r + 1 == height or not mask[r + 1, c]:
                add((c, r + 1), (c + 1, r + 1))
            if c == 0 or not mask[r, c - 1]:
                add((c, r), (c, r + 1))
            if c + 1 == width or not mask[r, c + 1]:
                add((c + 1, r + 1), (c + 1, r))

    def pop_next(prev, cur):
        options = outgoing.get(cur)
        if not options:
            return None
        if prev is None or len(options) == 1:
            return options.pop()
        incoming = math.atan2(cur[1] - prev[1], cur[0] - prev[0])
        best_at, best_turn = 0, None
        for index, nxt in enumerate(options):
            turn = (math.atan2(nxt[1] - cur[1], nxt[0] - cur[0]) - incoming) % (2 * math.pi)
            if best_turn is None or turn < best_turn:
                best_turn = turn
                best_at = index
        return options.pop(best_at)

    loops = []
    for start, edges in list(outgoing.items()):
        while edges:
            nxt = edges.pop()
            loop = [start]
            prev, cur = start, nxt
            while cur != start:
                loop.append(cur)
                nxt = pop_next(prev, cur)
                if nxt is None:
                    raise SystemExit(f"outline broke at {cur}")
                prev, cur = cur, nxt
                if len(loop) > width * height * 4:
                    raise SystemExit("outline did not close")
            if len(loop) >= 4:
                loops.append(loop)
    return loops


def components(mask):
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        pixels = []
        while stack:
            y, x = stack.pop()
            pixels.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        found.append(pixels)
    return found


def color_centers(rgb, solid):
    """Flat colours in the solid pixels. Antialiased fringe is not its own colour."""
    samples = rgb[solid]
    if len(samples) == 0:
        return []
    rounded = (samples // 16) * 16
    uniq = np.unique(rounded, axis=0)
    centers = []
    for color in uniq:
        color = color.astype(np.int32)
        if any(np.abs(color - center).max() <= 36 for center in centers):
            continue
        centers.append(color)
    return centers


def regions(png):
    """Simplified polygons of each non-black colour blob, largest first."""
    arr = np.array(png.convert("RGBA"))
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3]
    # Black marks and the dark pixels on their edge. Gray limbs (around 82–194) stay.
    black = (alpha > 32) & np.all(rgb <= 24, axis=2)
    fringe = black.copy()
    fringe[1:] |= black[:-1]
    fringe[:-1] |= black[1:]
    fringe[:, 1:] |= black[:, :-1]
    fringe[:, :-1] |= black[:, 1:]
    white = np.all(rgb >= 240, axis=2)
    # Dark fringe around the black marks is not a colour of its own. Gray limbs
    # are neutral and stay. A near-black outline such as #2C2C2B does not, and
    # neither does a brown or blue shadow pixel.
    peak = rgb.max(axis=2)
    gray = ((peak - rgb.min(axis=2)) < 24) & (peak >= 70)
    solid = (alpha > 200) & ~fringe & ~white & (gray | (peak >= 110))
    centers = color_centers(rgb, solid)
    if not centers:
        raise SystemExit("no colour")
    flat = rgb.reshape(-1, 3).astype(np.int32)
    nearest = np.stack([np.abs(flat - center).sum(axis=1) for center in centers]).argmin(axis=0)
    nearest = nearest.reshape(alpha.shape)
    # Black lines used to sit between colours. Grow each colour across that gap
    # so the traces meet, instead of leaving a white crack under the brush.
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
    for index, center in enumerate(centers):
        mask = assigned == index
        if mask.sum() < 40:
            continue
        for pixels in components(mask):
            if len(pixels) < 40:
                continue
            blob = np.zeros_like(mask)
            ys, xs = zip(*pixels)
            blob[list(ys), list(xs)] = True
            seeds = solid & blob
            if int(seeds.sum()) < 20:
                continue
            tone = np.median(rgb[seeds], axis=0)
            kept = []
            for loop in boundary_loops(blob):
                poly = Polygon(loop)
                if not poly.is_valid:
                    poly = poly.buffer(0)
                if poly.is_empty or poly.area < 30:
                    continue
                probe = poly.representative_point()
                x, y = int(probe.x), int(probe.y)
                if not (0 <= y < blob.shape[0] and 0 <= x < blob.shape[1] and bool(blob[y, x])):
                    continue
                kept.append(poly)
            for outer in kept:
                # Grow a little so neighbouring colours meet under the brush instead of leaving a gap.
                geom = outer.buffer(2.5, join_style="round", quad_segs=4).simplify(STRAIGHTEN, preserve_topology=True)
                if geom.is_empty or geom.geom_type != "Polygon" or geom.area < 30:
                    continue
                shapes.append((geom.area, "#{:02X}{:02X}{:02X}".format(*[int(v) for v in tone]), geom))
    if not shapes:
        raise SystemExit("no regions")
    shapes.sort(key=lambda item: item[0], reverse=True)
    return shapes


def _stamp(scene, geom, color):
    """Flat shape at the current layer, not under the whole drawing.

    A window's rectangle used to be inserted at the bottom of the SVG. The wall
    fill, drawn earlier but painted later, covered it. The flood fill then
    recoloured only the colour it tapped, and the rest of the window stayed wall.
    """
    grown = translate(geom.buffer(1.5, join_style="round", quad_segs=3), PAD, PAD)
    for part in svg_export.polygons_of(grown):
        if part.area < 1:
            continue
        scene.layers.append(svg_export.Layer("fill", part, color, 1.0))


def _fill_inside(hand, scene, keys, color, size):
    """Tap every colour the outline already crosses.

    One fill recolours only the tapped colour. A window drawn over a wall and a
    shadow stays half empty if you tap just the wall. Same rule as the village
    pines in bone-paper-recording.
    """
    inner = Polygon(keys).buffer(-(size / 2 + 4))
    if inner.is_empty:
        return
    pieces = scene.foreign_pieces(inner, color)
    anchor = inner.representative_point()
    if len(pieces) == 1 and pieces[0].contains(anchor):
        hand.fill((anchor.x, anchor.y), color)
        scene.fill(hand.ops[-1])
        return
    for part in pieces:
        pt = polylabel(part, tolerance=1.0)
        if not part.contains(pt):
            pt = part.representative_point()
        clear = part.boundary.distance(pt)
        hand.fill((pt.x, pt.y), color, wander=0 if clear < 4 else 3)
        scene.fill(hand.ops[-1])


def brush_svg(png, shapes, seed, outlines=True):
    """Sloppy outline (and a fill on wide parts) in the bitmap's own pixel space.

    `outlines=False` keeps every fill (stamp, limb stroke, interior tap) and draws
    no contour ring, so the picture reads as flat colour with no linework.
    """
    width, height = png.size
    canvas_w = width + PAD * 2
    canvas_h = height + PAD * 2
    hand = Hand(seed, (0, 0))
    session = {
        "version": 1, "started": "generated", "duration": 0, "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": canvas_w, "height": canvas_h, "originX": 0, "originY": 0, "fixed": True},
        "final": {"width": canvas_w, "height": canvas_h, "extraLeft": 0, "extraTop": 0},
        "paper": None, "ops": hand.ops,
    }
    scene = svg_export.Scene(session)
    for _, color, geom in shapes:
        ring = [(x + PAD, y + PAD) for x, y in list(geom.exterior.coords)[:-1]]
        if len(ring) < 3:
            continue
        rect = geom.minimum_rotated_rectangle
        corners = list(rect.exterior.coords)[:4]
        edges = [(math.dist(corners[i], corners[(i + 1) % 4]), i) for i in range(4)]
        short = min(edges)[0]
        long_len = max(edge[0] for edge in edges)
        long_i = max(edges)[1]
        if not math.isfinite(short):
            short = WIDE
        # A long narrow part (a limb) is one stroke. A small compact part
        # (an eye, an ear) keeps its outline, with a brush that fits inside it.
        elongated = short < WIDE and long_len > short * 2.2
        if elongated or len(ring) < 4:
            a, b = corners[long_i], corners[(long_i + 1) % 4]
            c, d = corners[(long_i + 2) % 4], corners[(long_i + 3) % 4]
            mid1 = ((a[0] + d[0]) / 2 + PAD, (a[1] + d[1]) / 2 + PAD)
            mid2 = ((b[0] + c[0]) / 2 + PAD, (b[1] + c[1]) / 2 + PAD)
            length = math.dist(mid1, mid2) or 1
            size = min(48.0, max(BRUSH, short))
            inset = size / 2
            ux, uy = (mid2[0] - mid1[0]) / length, (mid2[1] - mid1[1]) / length
            p1 = (mid1[0] + ux * inset, mid1[1] + uy * inset)
            p2 = (mid2[0] - ux * inset, mid2[1] - uy * inset)
            if math.dist(p1, p2) < 16:
                p2 = (p1[0] + ux * 16, p1[1] + uy * 16)
            if outlines:
                hand.stroke(hand.curve([p1, p2]), color, size=size, jitter=JITTER)
                scene.stroke(hand.ops[-1])
            else:
                _stamp(scene, geom, color)
            continue
        keys = ring
        size = BRUSH if short >= WIDE else max(6.0, short * 0.4)
        _stamp(scene, geom, color)
        if outlines:
            hand.stroke(hand.poly(keys, closed=True), color, closed=True, jitter=JITTER, size=size)
            scene.stroke(hand.ops[-1])
        _fill_inside(hand, scene, keys, color, size)
    session["duration"] = round(hand.t, 3)
    for layer in scene.layers:
        if layer.kind == "fill" and layer.geom.area > canvas_w * canvas_h * 0.85:
            raise SystemExit("fill leaked across the bone")
    if not outlines and not scene.layers:
        raise SystemExit("nooutlines: the brush produced no fills, the page would be empty")
    svg = scene.svg(False)
    # Draw at 4x and keep those pixels. A 1x picture stretched on the phone looks faceted.
    svg = svg.replace(
        f'width="{canvas_w}" height="{canvas_h}"',
        f'width="{canvas_w * SAMPLE}" height="{canvas_h * SAMPLE}"',
        1,
    )
    svg = svg.replace(
        f'viewBox="0 0 {canvas_w} {canvas_h}"',
        f'viewBox="0 0 {canvas_w} {canvas_h}" shape-rendering="geometricPrecision"',
        1,
    )
    brush_svg.session = session
    brush_svg.scene = scene
    return svg, (canvas_w, canvas_h)


def raster(svg, size, joint, seed):
    svg_path = OUT / f"_bone_{seed}.svg"
    png_path = OUT / f"_bone_{seed}.png"
    svg_path.write_text(svg)
    width, height = size
    subprocess.check_call([
        "rsvg-convert", "-w", str(width * SAMPLE), "-h", str(height * SAMPLE),
        "-o", str(png_path), str(svg_path),
    ])
    image = Image.open(png_path).convert("RGBA")
    jx, jy = joint
    joint = ((jx + PAD) * SAMPLE, (jy + PAD) * SAMPLE)
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit("empty bone")
    cropped = image.crop(bbox)
    return cropped, (joint[0] - bbox[0], joint[1] - bbox[1])


def compose(bones, images, origin, size):
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    ox, oy = origin
    for x1, y1, x2, y2, bm, xo, yo in bones:
        im = images[bm]
        angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
        jx, jy = -xo, -yo
        layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
        layer.paste(im, (0, 0))
        cx, cy = im.size[0] / 2, im.size[1] / 2
        shifted = Image.new("RGBA", im.size, (0, 0, 0, 0))
        shifted.paste(layer, (round(cx - jx), round(cy - jy)))
        rotated = shifted.rotate(-angle, resample=Image.BICUBIC, expand=True)
        rx = x1 - rotated.size[0] / 2
        ry = y1 - rotated.size[1] / 2
        canvas.alpha_composite(rotated, (round(rx + ox), round(ry + oy)))
    bbox = canvas.getchannel("A").getbbox()
    return canvas.crop(bbox)


def thumb(image):
    fitted = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    scale = min(92 / image.width, 92 / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.LANCZOS,
    )
    fitted.paste(resized, ((100 - resized.width) // 2, (100 - resized.height) // 2), resized)
    return fitted


def main():
    z = zipfile.ZipFile(SRC)
    assets = z.read("assets.xml").decode()
    model = z.read("model.xml").decode()
    edges = []
    for tag in re.findall(r"<edgeAsset ([^>]*)/>", assets):
        edges.append(dict(re.findall(r'(\w+)="([^"]*)"', tag)))
    points = {}
    for tag in re.findall(r"<point ([^>]*)/>", model):
        a = dict(re.findall(r'(\w+)="([^"]*)"', tag))
        points[a["id"]] = (float(a["x"]), float(a["y"]))
    unique = []
    for edge in edges:
        if edge["bm"] not in unique:
            unique.append(edge["bm"])

    images = {}
    joints = {}
    for i, bm in enumerate(unique):
        png = Image.open(BytesIO(z.read(bm))).convert("RGBA")
        xo = float(next(e["x_offset"] for e in edges if e["bm"] == bm))
        yo = float(next(e["y_offset"] for e in edges if e["bm"] == bm))
        shapes = regions(png)
        svg, size = brush_svg(png, shapes, 300 + i)
        drawn, joint = raster(svg, size, (-xo, -yo), 300 + i)
        images[bm] = drawn
        joints[bm] = joint
        drawn.save(OUT / f"new_{bm}")
        print(f"{bm} regions={len(shapes)} {png.size} -> {drawn.size} joint={joint[0]:.0f},{joint[1]:.0f}")

    bones = []
    for edge in edges:
        x1, y1 = points[edge["start"]]
        x2, y2 = points[edge["end"]]
        jx, jy = joints[edge["bm"]]
        bones.append((x1 * SAMPLE, y1 * SAMPLE, x2 * SAMPLE, y2 * SAMPLE, edge["bm"], -jx, -jy))
    poster = compose(bones, images, origin=(450 * SAMPLE, 700 * SAMPLE), size=(900 * SAMPLE, 1100 * SAMPLE))
    poster.save(OUT / "poster.png")
    thumb(poster).save(OUT / "thumb.png")
    print("poster", poster.size)

    new_assets = assets.replace('name="@:AT_Man"', f'name="@:{NAME}"')
    for bm, (jx, jy) in joints.items():
        xo, yo = f"{-jx:.0f}", f"{-jy:.0f}"
        new_assets = re.sub(
            rf'(bm="{re.escape(bm)}"[^>]*?x_offset=")[^"]*(" y_offset=")[^"]*',
            rf"\g<1>{xo}\g<2>{yo}",
            new_assets,
        )
    new_model = model.replace('name="@:AT_Man"', f'name="@:{NAME}"')

    def scale_attr(match):
        return f'x="{float(match.group(1)) * SAMPLE:.6g}" y="{float(match.group(2)) * SAMPLE:.6g}"'

    new_model = re.sub(r'\bx="(-?\d+(?:\.\d+)?)" y="(-?\d+(?:\.\d+)?)"', scale_attr, new_model)
    item_scale = 0.5 / SAMPLE
    meta = (
        '{"author":"","name":"' + NAME + '","pack":"@","appVersion":66,'
        f'"face_len":0,"multiframed":false,"scale":{item_scale}}}'
    )
    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as out:
        out.writestr("model.xml", new_model)
        out.writestr("assets.xml", new_assets)
        out.writestr("meta.txt", meta)
        out.writestr(f"{NAME}.name", b"")
        thumb_buf = BytesIO()
        thumb(poster).save(thumb_buf, format="PNG")
        out.writestr("thumb.png", thumb_buf.getvalue())
        poster_buf = BytesIO()
        poster.save(poster_buf, format="PNG")
        out.writestr("poster.png", poster_buf.getvalue())
        for bm, im in images.items():
            raw = BytesIO()
            im.save(raw, format="PNG")
            out.writestr(bm, raw.getvalue())
    local = OUT / f"{NAME}.ati"
    local.write_bytes(buf.getvalue())
    print("wrote", local, local.stat().st_size)


if __name__ == "__main__":
    main()
