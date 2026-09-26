"""Line-boil copies of an SVG-sourced item, assembled in its rest pose.

usage: .venv/bin/python item_boil.py <pack.atp> <item.ati> <out_dir> <name> [count]
Writes <name>_still.png (no wobble) and <name>_<i>.png. Each part is placed on its bone the way
SkeletonCanvas.drawBitmaps places the bitmap: translate to the asset's start point, rotate along the bone.
SVG path coordinates are already in that bone frame; the bitmap is the path bounds plus half the stroke.
"""
import io
import math
import random
import re
import subprocess
import sys
import zipfile
from pathlib import Path

AMP = (1.4, 2.2)       # displacement amplitude per plane wave, item units
WAVE = (120.0, 260.0)  # plane wave length, item units
NUDGE = 1.0            # whole-part shift, item units
STEP = 2.0             # flattening step, item units
MARGIN = 12.0
WIDTH = 900            # raster width, px


def attrs(tag):
    return dict(re.findall(r'(\w+)="([^"]*)"', tag))


def cubic(p0, p1, p2, p3):
    length = math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)
    n = max(2, int(length / STEP))
    out = []
    for k in range(1, n + 1):
        u = k / n
        a, b, c, d = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def flatten(d):
    """Absolute M/C/Z paths (the Kurwa export) to closed point loops."""
    tokens = re.findall(r'[MCZmcz]|-?\d+(?:\.\d+)?(?:e-?\d+)?', d)
    loops, pts, i, cmd = [], [], 0, None
    while i < len(tokens):
        t = tokens[i]
        if t in "MCZmcz":
            if t in "mc":
                raise SystemExit(f"item_boil: relative path command {t}")
            cmd = t.upper()
            i += 1
            if cmd == "Z":
                if pts:
                    loops.append(pts)
                pts = []
            continue
        if cmd == "M":
            if pts:
                loops.append(pts)
            pts = [(float(tokens[i]), float(tokens[i + 1]))]
            i += 2
        elif cmd == "C":
            c = [float(v) for v in tokens[i:i + 6]]
            pts += cubic(pts[-1], (c[0], c[1]), (c[2], c[3]), (c[4], c[5]))
            i += 6
        else:
            raise SystemExit(f"item_boil: unexpected token {t} after {cmd}")
    if pts:
        loops.append(pts)
    return [dedupe(loop) for loop in loops]


def dedupe(loop):
    out = [loop[0]]
    for p in loop[1:]:
        if math.dist(p, out[-1]) > 0.2:
            out.append(p)
    if len(out) > 1 and math.dist(out[0], out[-1]) < 0.2:
        out.pop()
    return out


def field(rng):
    """Smooth 2D displacement: a few plane waves per axis. Nearby points move together, so corners stay corners."""
    def waves():
        out = []
        for _ in range(3):
            theta = rng.uniform(0, 2 * math.pi)
            k = 2 * math.pi / rng.uniform(*WAVE)
            out.append((rng.uniform(*AMP) / 3, k * math.cos(theta), k * math.sin(theta), rng.uniform(0, 2 * math.pi)))
        return out
    wx, wy = waves(), waves()

    def move(p):
        dx = sum(a * math.sin(kx * p[0] + ky * p[1] + ph) for a, kx, ky, ph in wx)
        dy = sum(a * math.sin(kx * p[0] + ky * p[1] + ph) for a, kx, ky, ph in wy)
        return (p[0] + dx, p[1] + dy)
    return move


def load(pack, item):
    z = zipfile.ZipFile(pack)
    matches = [n for n in z.namelist() if n.endswith("/" + item) or n == item]
    if len(matches) != 1:
        raise SystemExit(f"item_boil: {item} matches {matches} in {pack}")
    inner = zipfile.ZipFile(io.BytesIO(z.read(matches[0])))
    model = inner.read("model.xml").decode()
    points = {}
    for tag in re.findall(r'<point ([^>]*)/>', model):
        a = attrs(tag)
        points[a["id"]] = (float(a["x"]), float(a["y"]))
    parts = []
    for tag in re.findall(r'<edgeAsset ([^>]*)/>', inner.read("assets.xml").decode()):
        a = attrs(tag)
        if a.get("state", "0") != "0":
            continue
        if "svg" not in a:
            raise SystemExit(f"item_boil: {a['bm']} has no svg source")
        svg = inner.read(a["svg"]).decode()
        shapes = []
        for path in re.findall(r'<path ([^>]*)/>', svg):
            p = attrs(path)
            style = dict(kv.split(":", 1) for kv in (s.strip() for s in p["style"].split(";")) if kv)
            style = {k.strip(): v.strip() for k, v in style.items()}
            shapes.append((flatten(p["d"]), style))
        start, end = points[a["start"]], points[a["end"]]
        parts.append({
            "weight": int(a["weight"]), "start": start, "start_id": int(a["start"]), "end_id": int(a["end"]),
            "angle": math.degrees(math.atan2(end[1] - start[1], end[0] - start[0])), "shapes": shapes,
        })
    parts.sort(key=lambda part: part["weight"])
    return parts


def placed(part, loop):
    c, s = math.cos(math.radians(part["angle"])), math.sin(math.radians(part["angle"]))
    x0, y0 = part["start"]
    return [(x0 + x * c - y * s, y0 + x * s + y * c) for x, y in loop]


def render(parts, rng, out):
    body, xs, ys = [], [], []
    for part in parts:
        dx, dy = (rng.uniform(-NUDGE, NUDGE), rng.uniform(-NUDGE, NUDGE)) if rng else (0.0, 0.0)
        move = field(rng) if rng else None
        for loops, style in part["shapes"]:
            d = []
            for loop in loops:
                pts = placed(part, [move(p) for p in loop] if move else loop)
                pts = [(x + dx, y + dy) for x, y in pts]
                xs += [p[0] for p in pts]
                ys += [p[1] for p in pts]
                d.append("M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z")
            keep = ";".join(f"{k}:{v}" for k, v in style.items())
            body.append(f'<path d="{" ".join(d)}" style="{keep}"/>')
    return body, (min(xs), min(ys), max(xs), max(ys))


def main():
    pack, item, out_dir, name = sys.argv[1], sys.argv[2], Path(sys.argv[3]), sys.argv[4]
    count = int(sys.argv[5]) if len(sys.argv) > 5 else 3
    parts = load(pack, item)
    out_dir.mkdir(parents=True, exist_ok=True)
    still, box = render(parts, None, None)
    # One frame for every copy so the parts stay registered while boiling.
    x0, y0 = box[0] - MARGIN - max(AMP) - NUDGE, box[1] - MARGIN - max(AMP) - NUDGE
    w, h = box[2] - box[0] + 2 * (MARGIN + max(AMP) + NUDGE), box[3] - box[1] + 2 * (MARGIN + max(AMP) + NUDGE)
    height = round(WIDTH * h / w)
    variants = [("still", still)] + [(str(i), render(parts, random.Random(i + 1), None)[0]) for i in range(count)]
    for label, body in variants:
        svg = out_dir / f"{name}_{label}.svg"
        svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" '
                       f'viewBox="{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}">' + "".join(body) + "</svg>")
        png = out_dir / f"{name}_{label}.png"
        subprocess.check_call(["rsvg-convert", "-w", str(WIDTH), "-h", str(height), str(svg), "-o", str(png)])
        svg.unlink()
        print(png, f"{WIDTH}x{height}")


if __name__ == "__main__":
    main()
