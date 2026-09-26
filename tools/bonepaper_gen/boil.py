"""Line-boil variants: re-trace every stroke of a session with fresh small drift, re-export, rasterise.

usage: .venv/bin/python boil.py <session.json> <out_dir> <name> [count]
Writes <out_dir>/<name>_<i>.png at 1280x960. A variant whose fills leak is re-rolled; too many leaks fail loudly.
"""
import copy
import json
import math
import random
import subprocess
import sys
from pathlib import Path

import svg_export

AMP = (1.2, 2.0)          # sideways drift amplitude range, page px
WAVE = (70.0, 200.0)      # drift wavelength range along the stroke, page px
SHIFT = 1.0               # whole-stroke nudge, page px
# A fill may change area by this share plus a band of this width along its boundary.
AREA_SHARE = 0.05
AREA_BAND = 3.0
TRIES = 3
RASTER = (1280, 960)


def retrace(points, rng):
    waves = [(rng.uniform(*AMP) / 2, rng.uniform(*WAVE), rng.uniform(0, 2 * math.pi)) for _ in range(2)]
    dx, dy = rng.uniform(-SHIFT, SHIFT), rng.uniform(-SHIFT, SHIFT)
    out, s = [], 0.0
    for i, p in enumerate(points):
        if i:
            s += math.dist(points[i - 1][:2], p[:2])
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        n = math.hypot(tx, ty) or 1.0
        off = sum(amp * math.sin(2 * math.pi * s / lam + ph) for amp, lam, ph in waves)
        out.append([round(p[0] - ty / n * off + dx, 2), round(p[1] + tx / n * off + dy, 2)] + p[2:])
    return out


def variant(session, rng):
    out = copy.deepcopy(session)
    for op in out["ops"]:
        if op["op"] == "stroke":
            op["points"] = retrace(op["points"], rng)
    return out


def fills(session):
    scene = svg_export.Scene(session)
    scene.run(session["ops"])
    return scene, [layer.geom for layer in scene.layers if layer.kind == "fill"]


def leaks(base, other):
    if len(base) != len(other):
        return f"fill count {len(base)} -> {len(other)}"
    for i, (a, b) in enumerate(zip(base, other)):
        allowed = AREA_SHARE * a.area + AREA_BAND * a.length
        if abs(b.area - a.area) > allowed:
            return f"fill {i} area {a.area:.0f} -> {b.area:.0f} (allowed ±{allowed:.0f})"
    return None


def main():
    src, out_dir, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    session = json.loads(src.read_text())
    _, base = fills(session)
    out_dir.mkdir(parents=True, exist_ok=True)
    seed = 1
    for i in range(count):
        for attempt in range(TRIES):
            rng = random.Random(seed)
            seed += 1
            traced = variant(session, rng)
            scene, got = fills(traced)
            reason = leaks(base, got)
            if reason is None:
                break
            print(f"{name}_{i}: seed {seed - 1} rejected: {reason}")
        else:
            raise SystemExit(f"boil: {name}_{i} leaked {TRIES} times")
        svg = out_dir / f"{name}_{i}.svg"
        svg.write_text(scene.svg(False))
        png = out_dir / f"{name}_{i}.png"
        subprocess.check_call(["rsvg-convert", "-w", str(RASTER[0]), "-h", str(RASTER[1]), str(svg), "-o", str(png)])
        svg.unlink()
        print(f"{name}_{i}: seed {seed - 1} -> {png}")


if __name__ == "__main__":
    main()
