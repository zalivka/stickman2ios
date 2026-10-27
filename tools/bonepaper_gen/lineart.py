"""Line-art backgrounds: centre-line trace, one hand stroke per skeleton path.

regions() classifies every blob of the stroke as a limb and brushes it along
its rotated-rect axis, so a curved hair spike comes out as disconnected
straight sausages. A line-art picture is strokes, not regions: separate the
ink from the paper, close 1 px mask breaks, thin to centre lines, join what
the thinning split, and emit one hand stroke per chain. The paper is a rect.
Same session/scene/svg plumbing as brush_svg.

A per-picture script is data (see out/lineflower/build.py):
    PAPER   ink test: the mask of stroke pixels on the page
    NAME, SRC, MIN_BLOB, MAX_SIZE, CONTACT, COS_MIN as in lineart.line_art_bg
"""
import math
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from shapely.geometry import LineString

GEN = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(GEN))
import flat
import shape_lint
from hand import Hand

tracer = flat.tracer
svg_export = tracer.svg_export
PAD = tracer.PAD
JITTER = tracer.JITTER
INK_MIN = flat.INK_MIN


def close_breaks(ink):
    """MaxFilter(3) then MinFilter(3): 1 px JPEG breaks close, real gaps stay."""
    m = Image.fromarray((ink * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    return np.array(m) > 0


def line_art_bg(NAME, SRC, PAPER, out=None, MIN_BLOB=40, MAX_SIZE=8.0,
                CONTACT=5.0, COS_MIN=0.65, FADE=None, quiet=False):
    """SRC through the centre-line tracer. Writes bg.svg/bg.png/thumb/zip beside SRC."""
    im = flat.fit_page(Image.open(SRC).convert("RGB"))
    arr = np.array(im).astype(np.int16)
    if im.size != flat.PAGE:
        raise SystemExit(f"{NAME}: page is {im.size[0]}x{im.size[1]}, wanted {flat.PAGE}; "
                         "fit_page failed")
    ink = close_breaks(PAPER(arr))
    if not ink.any():
        raise SystemExit("no ink found")
    h, w = ink.shape
    paper = "#{:02X}{:02X}{:02X}".format(*[int(v) for v in np.median(arr[:4].reshape(-1, 3), axis=0)])

    if FADE is not None:
        """Walk each skeleton path end outward through a fade band.

        A marker stroke ends in a light ramp: the mask (the core test) stops
        where the fade begins, and the visible line runs on. Growing the whole
        mask fattens every stroke and welds parallel strands, so instead each
        end is extended along its own direction: step forward while the
        CURRENT pixel is ink OR the fade test hits AND the next step stays on
        course (cos >= 0.35 over the last 3 steps). Strokes never widen; only
        ends move. FADE = (fade_test, MAX_WALK) as page-px array functions.
        """
        fade_test, max_walk = FADE
        # raw (unclosed) core mask: fades must not bridge across the close
        core = PAPER(arr)
        sk_raw = flat.skeleton(core)
        ends = []
        # endpoint isolation on the RAW skeleton: a pixel with one neighbour
        pts = set(zip(*[v.tolist() for v in np.nonzero(sk_raw)]))
        for p in list(pts):
            y, x = p
            nbs = [(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                   if (dy or dx) and (y + dy, x + dx) in pts]
            if len(nbs) == 1:
                prev = nbs[0]
                ends.append((p, prev))
        added = 0
        for (y, x), (py, px) in ends:
            dy0, dx0 = y - py, x - px
            walk = [(y, x)]
            cy, cx, dyv, dxv = y, x, dy0, dx0
            for _ in range(max_walk):
                ny, nx = cy + dyv, cx + dxv
                if not (0 <= ny < h and 0 <= nx < w):
                    break
                if core[ny, nx]:
                    # still core ink: the end already had support, stop
                    break
                if not fade_test(arr, ny, nx):
                    break
                if len(walk) >= 3:
                    (ay, ax), (by, bx) = walk[-3], walk[-1]
                    last = (bx - ax, by - ay)
                    new = (nx - bx, ny - by)
                    ln = math.hypot(*last) or 1.0
                    nn_ = math.hypot(*new) or 1.0
                    if (last[0] * new[0] + last[1] * new[1]) / (ln * nn_) < 0.35:
                        break
                walk.append((ny, nx))
                cy, cx = ny, nx
            if len(walk) >= 2:
                for wy, wx in walk:
                    if not core[wy, wx]:
                        core[wy, wx] = True
                        added += 1
        print(f"fade: {len(ends)} raw ends, {added} px extended")
        ink = close_breaks(core)

    hand = Hand(flat.seed_for(NAME), (0, 0))
    padded = (w + PAD * 2, h + PAD * 2)
    session = {
        "version": 1, "started": "generated", "duration": 0, "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": padded[0], "height": padded[1], "originX": 0, "originY": 0, "fixed": True},
        "final": {"width": padded[0], "height": padded[1], "extraLeft": 0, "extraTop": 0},
        "paper": None, "ops": hand.ops,
    }
    scene = svg_export.Scene(session)

    strokes = 0
    dropped = 0
    paths = []  # (pts, tone, size, npix) per skeleton path, page px pre-PAD
    for pixels in tracer.components(ink):
        if len(pixels) < MIN_BLOB:
            dropped += 1
            continue
        ys = np.array([p[0] for p in pixels])
        xs = np.array([p[1] for p in pixels])
        y0, y1 = max(0, ys.min() - 1), min(h, ys.max() + 2)
        x0, x1 = max(0, xs.min() - 1), min(w, xs.max() + 2)
        blob = np.zeros((y1 - y0, x1 - x0), bool)
        blob[ys - y0, xs - x0] = True
        sk = flat.skeleton(blob)
        length = int(sk.sum())
        if length == 0:
            dropped += 1
            continue
        size = float(np.clip(len(pixels) / length + 1.5, 3.5, MAX_SIZE))
        tone = "#{:02X}{:02X}{:02X}".format(*[int(v) for v in np.median(
            arr[ys.clip(0, h - 1), xs.clip(0, w - 1)], axis=0)])
        for path in flat.skeleton_paths(sk):
            if len(path) < INK_MIN:
                continue
            pts = [(x + x0 + 0.5, y + y0 + 0.5) for y, x in path]
            paths.append((pts, tone, size, len(pixels)))

    # --- connect what thinning actually split ----------------------------------
    # skeleton_paths cuts at every junction, and the loop-walk leaves small gaps
    # where the skeleton branch order differed from the drawn order. Endpoints
    # that TOUCH (<= TOUCH px) merge regardless of direction: at a junction or
    # a sharp turn the 4-point direction window is meaningless, and a 0-2 px
    # bridge cannot hop between features (the face-meander failure came from
    # 14 px hops). Farther pairs must continue each other's direction
    # (>= COS_MIN on both sides); everything else is a separate feature.
    TOUCH = 2.5
    def unit(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1.0
        return dx / n, dy / n

    def dotp(u, v):
        return u[0] * v[0] + u[1] * v[1]

    def outward(i, s):
        pts = paths[i][0]
        k = min(4, len(pts) - 1)
        return unit(pts[-1 - k], pts[-1]) if s == 1 else unit(pts[k], pts[0])

    def inward(i, t):
        pts = paths[i][0]
        k = min(4, len(pts) - 1)
        return unit(pts[0], pts[k]) if t == 0 else unit(pts[-1], pts[-1 - k])

    def contact_pt(i, s):
        pts = paths[i][0]
        return pts[-1] if s == 1 else pts[0]

    cands = []
    for i in range(len(paths)):
        for j in range(i + 1, len(paths)):
            for s in (0, 1):
                for t in (0, 1):
                    a, b = contact_pt(i, s), contact_pt(j, t)
                    dist = math.dist(a, b)
                    if dist > CONTACT:
                        continue
                    if dist <= TOUCH:
                        cands.append((-3.0, dist, i, s, j, t))  # touching ends always merge
                        continue
                    d = unit(a, b)
                    c1, c2 = dotp(outward(i, s), d), dotp(inward(j, t), d)
                    if c1 < COS_MIN or c2 < COS_MIN:
                        continue
                    cands.append(((1 - c1) + (1 - c2), dist, i, s, j, t))
    cands.sort()
    match = {}
    for _, _, i, s, j, t in cands:
        if (i, s) in match or (j, t) in match:
            continue
        match[(i, s)] = (j, t)
        match[(j, t)] = (i, s)

    # Walk glued paths into chains; a path with both ends free stands alone.
    used = set()
    chains = []  # (pts, tone, size)
    for start in range(len(paths)):
        if start in used:
            continue
        cur_side = 0 if (start, 0) not in match else 1
        chain, best = [], paths[start]
        cur = start
        while True:
            used.add(cur)
            pts, tone, size, npix = paths[cur]
            if best[3] < npix:
                best = paths[cur]
            chain.extend(pts if cur_side == 0 else reversed(pts))
            exit_side = 1 - cur_side
            nxt = match.get((cur, exit_side))
            if nxt is None:
                break
            nxt_i, nxt_t = nxt
            if nxt_i in used:
                break  # cycle closure; the ends already overlap
            a, b = contact_pt(cur, exit_side), contact_pt(nxt_i, nxt_t)
            if math.dist(a, b) > 2:
                chain.append(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2))
            cur, cur_side = nxt_i, nxt_t
        chains.append((chain, best[1], best[2]))

    for pts, tone, size in chains:
        reach = max(math.dist(pts[0], q) for q in pts)
        if reach < shape_lint.SLOP + 1:
            (ax, ay), (bx, by) = pts[0], pts[-1]
            d = math.dist((ax, ay), (bx, by)) or 1.0
            ux, uy = (bx - ax) / d, (by - ay) / d
            mx, my = (ax + bx) / 2, (ay + by) / 2
            pts = [(mx - ux * 7, my - uy * 7), (mx + ux * 7, my + uy * 7)]
        else:
            pts = list(LineString(pts).simplify(1.0).coords)
        keys = [(x + PAD, y + PAD) for x, y in pts]
        hand.stroke(hand.curve(keys), tone, size=size, jitter=JITTER)
        scene.stroke(hand.ops[-1])
        strokes += 1

    if strokes == 0:
        raise SystemExit("no strokes survived the minimum length")
    if not quiet:
        print(f"{NAME}: paper={paper} paths={len(paths)} chains={strokes} speck blobs dropped={dropped}")
    session["duration"] = round(hand.t, 3)
    svg = flat.page_svg(scene, paper)
    # The SVG window is PAGE; strokes live on the padded canvas. If the shape
    # data came from a different canvas the viewBox crops/rescales the scene,
    # so verify before rendering.
    if (w, h) != flat.PAGE:
        raise SystemExit(f"{NAME}: page-svg from a {w}x{h} canvas, wanted {flat.PAGE}")
    png = flat.rasterize(svg, 1280, 960)
    extrema = png.convert("RGB").getextrema()
    if all(v[1] - v[0] < 8 for v in extrema):
        raise SystemExit(f"{NAME}: render is a uniform colour; the scene content was lost")
    out = Path(out) if out else Path(SRC).resolve().parent
    out.mkdir(parents=True, exist_ok=True)
    out.joinpath("bg.svg").write_text(svg)
    png.save(out / "bg.png")
    flat.cover_thumb(png).save(out / "thumb.png")
    with zipfile.ZipFile(out / f"{NAME}.zip", "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name in ("bg.png", "bg.svg", "thumb.png"):
            z.write(out / name, name)
    if not quiet:
        print("wrote", out / f"{NAME}.zip", (out / f"{NAME}.zip").stat().st_size)
    return svg, png


def compare(src_path, out_path, bg_path=None):
    """Vertical review stack: the fit_page'd source over the brushed bg, both 640x480."""
    a = flat.fit_page(Image.open(src_path).convert("RGB"))
    b = Image.open(bg_path or Path(out_path).parent / "bg.png").convert("RGB")
    if b.size != (1280, 960):
        raise SystemExit(f"bg is {b.size}, expected the 1280x960 raster")
    a = a.resize((640, 480), Image.LANCZOS)
    b = b.resize((640, 480), Image.LANCZOS)
    canvas = Image.new("RGB", (644, 968), (200, 200, 200))
    canvas.paste(a, (2, 2))
    canvas.paste(b, (2, 486))
    canvas.save(out_path)


def default_paper(arr, delta=60):
    """Ink is much darker than the median paper, on any paper colour.

    delta 60 is the JPEG-safe default: it misses the faint antialiased pixels
    of thin strokes and leaves breaks in the mask. A clean PNG with thin line
    art takes delta 35 (see out/lineflower); lower starts catching shading.
    """
    luma = arr @ np.array([299, 587, 114]) // 1000
    return luma < np.median(luma[arr[:4].reshape(-1)]) - delta