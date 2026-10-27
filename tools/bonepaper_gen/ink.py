"""BonePaper sketch: EDT-based line-art and hybrid backgrounds.

  .venv/bin/python ink.py sketch picture.png -o out/picture/picture.zip
  .venv/bin/python ink.py sketch picture.png --wash -o out/picture/picture.zip

`ink.py sketch` replaces the hybrid MinFilter-depth background scripts
(glasses, redface, …). Local half-width
comes from the Euclidean distance transform; stroke width is 2*r at each skeleton
pixel; region cores are r >= REGION_R grown only +2 px on their own ink island.
"""
from __future__ import annotations

import argparse
import math
import sys
import time
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import binary_closing, binary_dilation, distance_transform_edt, label, median_filter
from shapely.affinity import rotate, translate
from shapely.geometry import LineString, MultiLineString, Polygon

GEN = Path(__file__).resolve().parent
sys.path.insert(0, str(GEN))
import lineart
import shape_lint
import flat
from hand import Hand

tracer = flat.tracer
svg_export = tracer.svg_export
PAD = flat.PAD
PAGE = flat.PAGE
JITTER = tracer.JITTER
INK_MIN = flat.INK_MIN

# EDT half-width (px) at which a pixel is a region core, not a stroke.
# Matches the glasses depth>=7 lesson: brows ~5 stay strokes; pupils/hair cores.
REGION_R = 7.0
# Grow recovers antialias fringe only (+2 px). MaxFilter(21) swelled pupils.
GROW_MAX = 5
# Split a skeleton chain when consecutive radii jump this much (px half-width).
SPLIT_DR = 1.5
# Brush size = 2*r, clamped.
SIZE_LO, SIZE_HI = 2.0, 8.0
# Hysteresis on (local_median - luma): high = definite ink, low = fade tails.
HYST_HIGH = 40
HYST_LOW = 18
# Ink-budget grid: fail if any cell's dark-ratio ratio is outside [1/BUDGET, BUDGET].
BUDGET = 2.5
GRID = 8


def maybe_lift(arr: np.ndarray) -> np.ndarray:
    """Gamma-lift dark stills so ink clears the contrast floor (busnight lesson)."""
    med = float(np.median(arr.reshape(-1, 3).max(axis=1)))
    if med >= 60:
        return arr
    g = 0.45
    lifted = ((arr.astype(np.float32) / 255.0) ** g * 255.0).clip(0, 255).astype(np.uint8)
    print(f"dark still: median peak {med:.0f} -> gamma {g}")
    return lifted


def extend_fade_ends(core: np.ndarray, fade_mask: np.ndarray, max_walk: int = 24) -> np.ndarray:
    """Walk each raw skeleton endpoint outward through fade_mask along its tangent.

    A marker stroke ends in a light ramp where the core threshold stops but the
    visible line continues. Walking only skeleton endpoints along their tangent
    (cos >= 0.35) extends faded tips (like redface's neck and hair tips) without
    fattening strokes or welding parallel strands.
    """
    h, w = core.shape
    sk_raw = flat.prune_l_corners(flat.skeleton(core))
    pts = set(zip(*[v.tolist() for v in np.nonzero(sk_raw)]))
    ends = []
    for y, x in pts:
        nbs = [(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)
               if (dy or dx) and (y + dy, x + dx) in pts]
        if len(nbs) == 1:
            ends.append(((y, x), nbs[0]))
    out = core.copy()
    for (y, x), (py, px) in ends:
        dyv, dxv = y - py, x - px
        walk = [(y, x)]
        cy, cx = y, x
        for _ in range(max_walk):
            ny, nx = cy + dyv, cx + dxv
            if not (0 <= ny < h and 0 <= nx < w):
                break
            if out[ny, nx]:
                break
            if not fade_mask[ny, nx]:
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
                if not out[wy, wx]:
                    out[max(0, wy - 1):min(h, wy + 2), max(0, wx - 1):min(w, wx + 2)] = True
    return out


def ink_hysteresis(arr: np.ndarray) -> np.ndarray:
    """Ink mask: channel drop from paper + local contrast + tangent endpoint fade walk.

    Works on white paper (wojak, glasses) AND saturated coloured paper (redface,
    where paper RGB is [169,1,0] so standard luma is only 51 and luma contrast is
    compressed 3x). Measuring `drop = max(paper_rgb - arr)` across channels
    normalizes red/blue/white paper automatically.
    """
    luma = (arr.astype(np.int16) @ np.array([299, 587, 114]) // 1000).astype(np.uint8)
    paper_luma = float(np.median(luma[:4].reshape(-1)))
    paper_rgb = np.median(arr[:4].reshape(-1, 3), axis=0).astype(np.int16)
    drop = (paper_rgb - arr.astype(np.int16)).max(axis=2)

    local = np.array(Image.fromarray(luma).filter(ImageFilter.MedianFilter(15))).astype(np.int16)
    contrast = local - luma.astype(np.int16)

    if paper_luma >= 200:
        # Crisp / upscaled B&W on light paper: only near-black is core; mid-gray
        # LANCZOS halos are antialias, not ink.
        absolute = (luma < 55) | np.all(arr < 50, axis=2)
        high = absolute | (contrast >= HYST_HIGH)
        low = absolute | (luma < 90) | (contrast >= HYST_LOW)
        fade_m = luma < 140
    else:
        # Coloured or dark paper: use channel drop from paper_rgb.
        high = (drop >= 85) | np.all(arr < 45, axis=2) | (contrast >= HYST_HIGH)
        low = (drop >= 65) | (contrast >= HYST_LOW)
        fade_m = drop >= 38

    labeled, n = label(low)
    keep = np.zeros_like(low)
    for i in range(1, n + 1):
        comp = labeled == i
        if (comp & high).any():
            keep |= comp
    extended = extend_fade_ends(keep, fade_m)
    return lineart.close_breaks(extended)


def edt_radius(ink: np.ndarray) -> np.ndarray:
    """Local half-width at every ink pixel (distance to nearest paper pixel)."""
    # distance_transform_edt(True) = dist to nearest False.
    return distance_transform_edt(ink)


def island_labels(ink: np.ndarray) -> np.ndarray:
    labeled, _ = label(ink)
    return labeled


def region_mask(ink: np.ndarray, radius: np.ndarray) -> np.ndarray:
    """Region = EDT cores (r >= REGION_R) grown back by (REGION_R - 0.5) px.

    Why (REGION_R - 0.5)? Because a core is eroded inward by REGION_R px from
    the true boundary. Growing only +2 px on a 13-px pupil leaves a 5-px donut
    collar in stroke_m, creating a double ring around the pupil. Growing back
    by (REGION_R - 0.5) constrained to the same ink island restores the exact
    region boundary without swelling past the original shape.
    """
    core = ink & (radius >= REGION_R)
    if not core.any():
        return np.zeros_like(ink)
    islands = island_labels(ink)
    regions = np.zeros_like(ink)
    labeled_core, n = label(core)
    for i in range(1, n + 1):
        seed = labeled_core == i
        if int(seed.sum()) < 12:
            continue
        ys, xs = np.nonzero(seed)
        isl = islands[ys[len(ys) // 2], xs[len(xs) // 2]]
        if isl == 0:
            continue
        dist = distance_transform_edt(~seed)
        grown = (dist <= (REGION_R - 0.5)) & (islands == isl)
        regions |= grown
    return regions


def path_radii(path, radius, y0, x0):
    """Half-width samples along a skeleton path (path coords are local blob y,x)."""
    rs = []
    h, w = radius.shape
    for y, x in path:
        gy, gx = y + y0, x + x0
        if 0 <= gy < h and 0 <= gx < w:
            rs.append(float(radius[gy, gx]))
        else:
            rs.append(1.0)
    if len(rs) >= 5:
        rs = median_filter(np.array(rs, dtype=np.float32), size=5).tolist()
    return rs


def split_by_radius(pts, radii, tone):
    """Split a centre-line where half-width jumps >= SPLIT_DR (lash glued to cheek)."""
    if len(pts) < 2:
        return []
    segs = []
    start = 0
    for i in range(1, len(pts)):
        if abs(radii[i] - radii[i - 1]) >= SPLIT_DR:
            segs.append((pts[start:i], radii[start:i], tone))
            start = i
    segs.append((pts[start:], radii[start:], tone))
    out = []
    for p, r, t in segs:
        if len(p) < INK_MIN:
            continue
        size = float(np.clip(2.0 * float(np.median(r)), SIZE_LO, SIZE_HI))
        out.append((p, t, size))
    return out


def path_reach(pts):
    return max(math.dist(pts[0], q) for q in pts)


def glue_chains(paths, contact=5.0, cos_min=0.65):
    """Join skeleton paths the thinner split (same rules as lineart.line_art_bg).

    paths: list of (pts, tone, size). Returns glued (pts, tone, size) chains.
    """
    if not paths:
        return []
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
            # Do not glue across a large brush-width jump (lash ↔ cheek).
            if abs(paths[i][2] - paths[j][2]) >= 2.0:
                continue
            for s in (0, 1):
                for t in (0, 1):
                    a, b = contact_pt(i, s), contact_pt(j, t)
                    dist = math.dist(a, b)
                    if dist > contact:
                        continue
                    if dist <= TOUCH:
                        cands.append((-3.0, dist, i, s, j, t))
                        continue
                    d = unit(a, b)
                    c1, c2 = dotp(outward(i, s), d), dotp(inward(j, t), d)
                    if c1 < cos_min or c2 < cos_min:
                        continue
                    cands.append(((1 - c1) + (1 - c2), dist, i, s, j, t))
    cands.sort()
    match = {}
    for _, _, i, s, j, t in cands:
        if (i, s) in match or (j, t) in match:
            continue
        match[(i, s)] = (j, t)
        match[(j, t)] = (i, s)

    used = set()
    chains = []
    for start in range(len(paths)):
        if start in used:
            continue
        cur_side = 0 if (start, 0) not in match else 1
        chain_pts = []
        sizes = []
        tone = paths[start][1]
        keep_short = bool(paths[start][3]) if len(paths[start]) > 3 else False
        cur = start
        while True:
            used.add(cur)
            pts, t, size = paths[cur][:3]
            if len(paths[cur]) > 3 and paths[cur][3]:
                keep_short = True
            tone = t
            sizes.append(size)
            chain_pts.extend(pts if cur_side == 0 else reversed(pts))
            exit_side = 1 - cur_side
            nxt = match.get((cur, exit_side))
            if nxt is None:
                break
            nxt_i, nxt_t = nxt
            if nxt_i in used:
                break
            a, b = contact_pt(cur, exit_side), contact_pt(nxt_i, nxt_t)
            if math.dist(a, b) > 2:
                chain_pts.append(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2))
            cur, cur_side = nxt_i, nxt_t
        chains.append((chain_pts, tone, float(np.median(sizes)), keep_short))
    return chains


def _wash_keys(line):
    """Page points for one wash stroke, or None when the hand would reject it.

    A hatch slice whose farthest point is under 15 px from the start shrinks
    below the hand's 12 px minimum once it is curved, and hand.stroke aborts.
    """
    if len(line) < 2:
        return None
    reach = max(math.dist(line[0], q) for q in line[1:])
    if reach < shape_lint.SLOP + 3:
        return None
    return [(x + PAD, y + PAD) for x, y in line]


def hatch_region(geom, angle_deg=-20, spacing=20, brush_size=30.0, seed=42, slop=1.0, inset_frac=0.15):
    """Wide, slightly randomized marker wash strokes that stay better inside the contour.

    Uses a light inward buffer (-0.15 * brush_size) so round brush caps only
    barely kiss or slightly cross the outline rather than shooting far outside,
    while scaling spacing, tilt, bow, and width variation with `slop` (1.0 = default).
    `inset_frac` is that buffer as a fraction of the brush. A smaller brush passes
    a larger fraction so the round cap stays inside the pocket.
    """
    rng = np.random.default_rng(seed)
    s = max(0.0, float(slop))
    inset = geom.buffer(-brush_size * inset_frac, join_style="round", quad_segs=4)
    if inset.is_empty or inset.area < 40:
        inset = geom
    rot = rotate(inset, -angle_deg, origin=(0, 0))
    minx, miny, maxx, maxy = rot.bounds
    y = miny + spacing * 0.35
    rows = []
    step_lo, step_hi = max(0.5, 1.0 - 0.2 * s), 1.0 + 0.2 * s
    while y <= maxy:
        test_line = LineString([(minx - 20, y), (maxx + 20, y)])
        inter = rot.intersection(test_line)
        if not inter.is_empty:
            parts = inter.geoms if isinstance(inter, MultiLineString) else [inter]
            segs = []
            for part in parts:
                if isinstance(part, LineString) and part.length >= 2.0:
                    coords = list(part.coords)
                    x0, x1 = coords[0][0], coords[-1][0]
                    if x0 > x1:
                        x0, x1 = x1, x0
                    if s > 0:
                        x0 -= float(rng.uniform(-3.0 * s, 3.0 * s))
                        x1 += float(rng.uniform(-3.0 * s, 3.0 * s))
                    segs.append((x0, x1, y))
            segs.sort()
            if segs:
                rows.append(segs)
        y += spacing * (float(rng.uniform(step_lo, step_hi)) if s > 0 else 1.0)

    slop_min = shape_lint.SLOP + 1
    chains = []
    active = []  # [pts_list, last_x0, last_x1, last_y, flip_dir]
    max_jump = spacing * 2.3
    for segs in rows:
        used_active = set()
        new_active = []
        for x0, x1, y_cur in segs:
            best_idx = None
            for idx, (pts, ax0, ax1, ay, flip) in enumerate(active):
                if idx in used_active:
                    continue
                if abs(y_cur - ay) <= max_jump and min(x1, ax1) - max(x0, ax0) >= -spacing:
                    best_idx = idx
                    break
            dy0 = float(rng.uniform(-2.8 * s, 2.8 * s)) if s > 0 else 0.0
            dy1 = float(rng.uniform(-2.8 * s, 2.8 * s)) if s > 0 else 0.0
            bow = float(rng.uniform(-2.5 * s, 2.5 * s)) if s > 0 else 0.0
            xm = 0.5 * (x0 + x1)
            ym = y_cur + 0.5 * (dy0 + dy1) + bow
            if best_idx is not None:
                used_active.add(best_idx)
                pts, ax0, ax1, ay, flip = active[best_idx]
                seg_pts = (
                    [(x1, y_cur + dy1), (xm, ym), (x0, y_cur + dy0)]
                    if flip
                    else [(x0, y_cur + dy0), (xm, ym), (x1, y_cur + dy1)]
                )
                seg_len = x1 - x0
                prev_len = ax1 - ax0
                if (seg_len < slop_min or prev_len < slop_min) and math.dist(pts[-1], seg_pts[0]) <= spacing * 1.9:
                    pts.extend(seg_pts)
                    new_active.append([pts, x0, x1, y_cur, not flip])
                else:
                    chains.append(pts)
                    new_active.append([seg_pts, x0, x1, y_cur, not flip])
            else:
                new_active.append([[(x0, y_cur + dy0), (xm, ym), (x1, y_cur + dy1)], x0, x1, y_cur, True])
        for idx, item in enumerate(active):
            if idx not in used_active:
                chains.append(item[0])
        active = new_active
    for item in active:
        chains.append(item[0])

    res = []
    w_lo, w_hi = max(0.6, 1.0 - 0.12 * s), 1.0 + 0.16 * s
    for pts in chains:
        ls = LineString(pts)
        if ls.length >= slop_min:
            wobble_deg = angle_deg + (float(rng.uniform(-2.2 * s, 2.2 * s)) if s > 0 else 0.0)
            rot_back = rotate(ls, wobble_deg, origin=(0, 0))
            stroke_w = brush_size * (float(rng.uniform(w_lo, w_hi)) if s > 0 else 1.0)
            res.append((list(rot_back.coords), stroke_w))
    return res


def sloppy_outline_strokes(geom, seed=300, slop=1.0):
    """Break a region ring into loose, overlapping, coarsened hand-sketched segments."""
    s = max(0.0, float(slop))
    if s <= 0.05:
        ring = list(geom.exterior.coords)
        return [ring] if len(ring) >= 3 else []
    rng = np.random.default_rng(seed)
    coarse = geom.exterior.simplify(2.0 + 5.5 * s, preserve_topology=False)
    coords = list(coarse.coords)[:-1]
    if len(coords) < 4:
        coords = list(geom.exterior.coords)[:-1]
    n = len(coords)
    if n < 3:
        return []
    drift = 4.5 * s
    pts = [
        (x + float(rng.uniform(-drift, drift)), y + float(rng.uniform(-drift, drift)))
        for x, y in coords
    ]
    step = max(2, n // 3)
    arcs = []
    idx = 0
    while idx < n:
        end = min(n + 1, idx + step + 1)
        seg = [pts[k % n] for k in range(idx, end)]
        if len(seg) >= 2:
            (x0, y0), (x1, y1) = seg[0], seg[1]
            d0 = math.hypot(x1 - x0, y1 - y0) or 1.0
            ov0 = float(rng.uniform(2.0 * s, 7.0 * s))
            seg[0] = (x0 - (x1 - x0) / d0 * ov0, y0 - (y1 - y0) / d0 * ov0)
            (xa, ya), (xb, yb) = seg[-2], seg[-1]
            d1 = math.hypot(xb - xa, yb - ya) or 1.0
            ov1 = float(rng.uniform(2.0 * s, 7.0 * s))
            seg[-1] = (xb + (xb - xa) / d1 * ov1, yb + (yb - ya) / d1 * ov1)
        if LineString(seg).length >= shape_lint.SLOP + 1:
            arcs.append(seg)
        idx += step
    return arcs


def enclosed_interior_mask(ink: np.ndarray, reg: np.ndarray) -> np.ndarray:
    """Return raw unwelded boolean mask of all enclosed paper pockets."""
    h, w = ink.shape
    pad = 25
    ink_p = np.pad(ink, pad, mode="constant", constant_values=False)
    barrier = binary_closing(ink_p, structure=np.ones((45, 45), bool))[pad:-pad, pad:-pad]
    ys_ink, xs_ink = np.nonzero(ink)
    if len(ys_ink) == 0:
        return np.zeros_like(ink)
    y_max = int(ys_ink.max())
    bottom_band = ink[max(0, y_max - 25):y_max + 1, :]
    if bottom_band.any():
        bx = np.nonzero(bottom_band)[1]
        barrier[max(0, y_max - 2):y_max + 1, bx.min():bx.max() + 1] = True

    free_lab, _ = label(~barrier)
    border_labels = set(np.unique(np.concatenate([
        free_lab[0, :], free_lab[-1, :], free_lab[:, 0], free_lab[:, -1]
    ]))) - {0}
    inside_coarse = ~np.isin(free_lab, list(border_labels))
    interior = inside_coarse & ~ink & ~reg

    real_barrier = binary_dilation(ink | reg, structure=np.ones((3, 3), bool))
    row_span = np.zeros_like(ink)
    for y in range(h):
        xs = np.nonzero(ink[y, :])[0]
        if len(xs) >= 2:
            row_span[y, xs.min():xs.max() + 1] = True
    allowed = ~real_barrier & row_span & inside_coarse
    for _ in range(120):
        nxt = binary_dilation(interior, structure=np.ones((3, 3), bool)) & allowed
        if np.array_equal(nxt, interior):
            break
        interior = nxt
    return interior


def discover_pockets(ink: np.ndarray, reg: np.ndarray, arr: np.ndarray, min_px: int = 250):
    """Discover all enclosed pockets >= min_px with seed, area, median color, and PCA angle."""
    unwelded = enclosed_interior_mask(ink, reg)
    comp_lab, n = label(unwelded)
    pockets = []
    for i in range(1, n + 1):
        m = comp_lab == i
        px = int(m.sum())
        if px < min_px:
            continue
        ys, xs = np.nonzero(m)
        cy, cx = float(ys.mean()), float(xs.mean())
        idx = int(np.argmin((ys - cy) ** 2 + (xs - cx) ** 2))
        sy, sx = int(ys[idx]), int(xs[idx])
        med = [int(v) for v in np.median(arr[m], axis=0)]
        hex_col = "#{:02X}{:02X}{:02X}".format(*med)
        luma = (299 * med[0] + 587 * med[1] + 114 * med[2]) // 1000
        spread = max(med) - min(med)
        is_colored = luma < 240 or spread > 18
        dx = xs.astype(np.float64) - cx
        dy = ys.astype(np.float64) - cy
        cov_xx = float((dx * dx).mean())
        cov_yy = float((dy * dy).mean())
        cov_xy = float((dx * dy).mean())
        ang = 0.5 * math.degrees(math.atan2(2.0 * cov_xy, cov_xx - cov_yy))
        if ang > 65:
            ang -= 90
        elif ang < -65:
            ang += 90
        pockets.append({
            "label": i,
            "px": px,
            "seed": f"{sx},{sy}",
            "sx": sx,
            "sy": sy,
            "src_hex": hex_col,
            "is_colored": is_colored,
            "angle": round(ang, 0),
            "mask": m,
        })
    pockets.sort(key=lambda p: p["px"], reverse=True)
    # A white pocket whose bottom nearly reaches the drawing's ink floor is a
    # background gap (space between legs, under arms), not skin: skin pockets
    # sit well above the ink bottom (face bottom-gap fraction ~0.77 vs ~0.01
    # for a between-legs gap). Mark them so --auto-tint skips the skin fill.
    ys_ink, _ = np.nonzero(ink)
    if len(ys_ink):
        y_top, y_bot = int(ys_ink.min()), int(ys_ink.max())
        span = max(1, y_bot - y_top)
        for p in pockets:
            if not p["is_colored"]:
                ys_p, _ = np.nonzero(p["mask"])
                if (y_bot - int(ys_p.max())) / span <= 0.15:
                    p["is_background_gap"] = True
    return pockets


def extract_enclosed_tint_mask(ink: np.ndarray, reg: np.ndarray, seed_spec: str, close: int = 15) -> np.ndarray:
    """Extract enclosed paper silhouette (face/skin/body) bounded by ink strokes.

    Closes contour gaps up to 45 px and seals open bottom collars on a temporary
    barrier mask, floods from outside, and regrows the interior back to the tight
    1-px dilated ink/region boundary within the horizontal span of the drawing.
    seed_spec is either 'auto' (largest interior pocket) or 'x,y' in page coords.
    """
    h, w = ink.shape
    unwelded = enclosed_interior_mask(ink, reg)
    if seed_spec == "auto":
        return binary_closing(unwelded, structure=np.ones((close, close), bool)) & ~binary_dilation(
            reg, structure=np.ones((3, 3), bool)
        )

    sx, sy = [int(v) for v in seed_spec.split(",")]
    comp_lab, _ = label(unwelded)
    lbl = int(comp_lab[np.clip(sy, 0, h - 1), np.clip(sx, 0, w - 1)])
    if lbl == 0:
        y0, y1 = max(0, sy - 15), min(h, sy + 16)
        x0, x1 = max(0, sx - 15), min(w, sx + 16)
        sub = comp_lab[y0:y1, x0:x1]
        vals = sub[sub > 0]
        if len(vals) > 0:
            lbl = int(np.bincount(vals).argmax())
    if lbl == 0:
        raise SystemExit(f"tint seed ({sx},{sy}) did not land inside an enclosed pocket")
    pocket = comp_lab == lbl
    return binary_closing(pocket, structure=np.ones((close, close), bool)) & ~binary_dilation(
        reg, structure=np.ones((3, 3), bool)
    )


def parse_tint_spec(spec: str):
    """Parse '[auto|x,y:]#HEX[@angle]' -> (seed_spec, color_hex, angle_deg)."""
    angle = 25.0
    if "@" in spec:
        spec, ang_s = spec.rsplit("@", 1)
        angle = float(ang_s)
    if ":" in spec:
        seed_spec, color = spec.split(":", 1)
    else:
        seed_spec, color = "auto", spec
    if not color.startswith("#"):
        color = "#" + color
    return seed_spec, color, angle


def region_geoms(regions_m: np.ndarray):
    h, w = regions_m.shape
    geoms = []
    for pixels in tracer.components(regions_m):
        if len(pixels) < 60:
            continue
        blob = np.zeros((h, w), bool)
        ys, xs = zip(*pixels)
        blob[list(ys), list(xs)] = True
        for loop in tracer.boundary_loops(blob):
            poly = Polygon(loop)
            if not poly.is_valid:
                poly = poly.buffer(0)
            if poly.is_empty or poly.area < 60:
                continue
            buf = 0.5 if poly.area < 1200 else 2.0
            geom = poly.buffer(buf, join_style="round", quad_segs=4).simplify(
                tracer.STRAIGHTEN, preserve_topology=True
            )
            if geom.is_empty or geom.geom_type != "Polygon" or geom.area < 60:
                continue
            geoms.append(geom)
    geoms.sort(key=lambda g: g.area, reverse=True)
    return geoms


def outline_size(geom) -> float:
    """Trim outline: capped at 4.0 px for large hair masses so borders stay crisp.

    Using 0.12 * short on hair (short ~178) produced a 21 px monster outline.
    Pupil-scale (short < 28): floor 2, lighter trim — floor 3 + stamp already
    spilled wojak pupils onto the cheeks.
    """
    minx, miny, maxx, maxy = geom.bounds
    short = min(maxx - minx, maxy - miny)
    if short >= 70:
        return 4.0
    if short < 28:
        return max(2.0, 0.12 * short)
    return min(4.0, max(3.0, 0.12 * short))


def ink_budget(src_rgb: np.ndarray, bg_rgb: np.ndarray, name: str, wash: bool = False) -> None:
    """8x8 coverage check. Loud fail on fat pupils / missing strokes / crop.

    Solid mode compares dark pixels (max < 90). Wash mode compares any mark
    (not near-paper) because pale hatch fails a hard dark test by design.
    """
    a = src_rgb
    b = bg_rgb
    if b.shape[:2] != a.shape[:2]:
        b = np.array(Image.fromarray(b).resize((a.shape[1], a.shape[0]), Image.LANCZOS))
    # Compare like-for-like ink masks. Raw `max < 90` on a LANCZOS upscale
    # under-counts source ink (thin gray rings) vs opaque hand strokes.
    a_mark = ink_hysteresis(a.astype(np.int16))
    if wash:
        # Compare only dark/gray marks (luma < 120 AND low saturation): pale skin
        # tints (#FCE4DC) and bright colour fills (club brown, cloth orange) are
        # additive washes the source's ink mask intentionally doesn't contain.
        b_int = b.astype(np.int16)
        b_luma = (b_int @ np.array([299, 587, 114]) // 1000)
        b_spread = b_int.max(axis=2) - b_int.min(axis=2)
        b_mark = (b_luma < 65) & (b_spread < 60)
        limit = BUDGET * 1.4
        empty_out_tol = 0.25  # wide wash caps are allowed to overshoot contour into adjacent cells
    else:
        b_mark = b.max(axis=2) < 90
        limit = BUDGET
        empty_out_tol = 0.05
    h, w = a_mark.shape
    gh, gw = h // GRID, w // GRID
    bad = []
    for gy in range(GRID):
        for gx in range(GRID):
            y0, x0 = gy * gh, gx * gw
            y1, x1 = (gy + 1) * gh if gy < GRID - 1 else h, (gx + 1) * gw if gx < GRID - 1 else w
            sa = float(a_mark[y0:y1, x0:x1].mean()) + 1e-4
            sb = float(b_mark[y0:y1, x0:x1].mean()) + 1e-4
            ratio = sb / sa
            if ratio > limit or ratio < 1.0 / limit:
                if sa < 0.02 and sb < empty_out_tol:
                    continue
                bad.append((gx, gy, sa, sb, ratio))
    if bad:
        msg = "; ".join(
            f"cell({x},{y}) src={sa:.3f} out={sb:.3f} ratio={r:.2f}" for x, y, sa, sb, r in bad[:8]
        )
        raise SystemExit(f"{name}: ink budget failed ({len(bad)} cells): {msg}")


def save_pockets_debug(im: Image.Image, pockets: list[dict], out_path: Path) -> None:
    """Save a diagnostic map of all discovered enclosed pockets with x,y seed labels."""
    vis = np.array(im).copy()
    palette = [
        (255, 180, 190), (160, 220, 255), (255, 210, 140), (180, 240, 180),
        (220, 180, 255), (255, 240, 150), (160, 240, 230), (255, 190, 160),
    ]
    for idx, p in enumerate(pockets):
        col = np.array(palette[idx % len(palette)], dtype=np.uint8)
        m = p["mask"]
        vis[m] = (vis[m].astype(np.uint16) * 35 // 100 + col.astype(np.uint16) * 65 // 100).astype(np.uint8)
    pil_vis = Image.fromarray(vis)
    draw = ImageDraw.Draw(pil_vis)
    for idx, p in enumerate(pockets):
        sx, sy = p["sx"], p["sy"]
        tag = f"#{idx+1} {p['seed']} ({p['src_hex']})"
        draw.ellipse((sx - 3, sy - 3, sx + 3, sy + 3), fill=(220, 0, 0), outline=(255, 255, 255))
        draw.rectangle((sx + 5, sy - 7, sx + 5 + len(tag) * 6 + 4, sy + 6), fill=(255, 255, 255))
        draw.text((sx + 7, sy - 6), tag, fill=(0, 0, 0))
    pil_vis.save(out_path)


def parse_remap_specs(remap_list: list[str] | None) -> list[tuple[tuple[int, int, int], str]]:
    """Parse 'OLD_HEX:NEW_HEX' pairs into ((r,g,b), '#NEW_HEX')."""
    rules = []
    for item in (remap_list or []):
        if ":" not in item:
            raise SystemExit(f"--remap '{item}' must be OLD_HEX:NEW_HEX")
        old_s, new_s = item.split(":", 1)
        old_s = old_s.lstrip("#")
        if len(old_s) != 6:
            raise SystemExit(f"--remap old colour '{old_s}' must be 6-digit hex")
        rgb = (int(old_s[0:2], 16), int(old_s[2:4], 16), int(old_s[4:6], 16))
        if not new_s.startswith("#"):
            new_s = "#" + new_s
        rules.append((rgb, new_s.upper()))
    return rules


def remap_color(hex_col: str, remap_rules: list[tuple[tuple[int, int, int], str]], tol: float = 45.0) -> str:
    """Return remapped hex colour if within RGB Euclidean tolerance of any rule."""
    if not remap_rules:
        return hex_col
    s = hex_col.lstrip("#")
    rgb = (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    for target_rgb, new_hex in remap_rules:
        d = math.sqrt(sum((a - b) ** 2 for a, b in zip(rgb, target_rgb)))
        if d <= tol:
            return new_hex
    return hex_col


def sketch(src: Path, out: Path, name: str, wash: bool, ink_color: str, skip_budget: bool,
           tints=None, wash_color: str | None = None, slop: float = 1.0,
           wash_opacity: float | None = None, auto_tint: bool = False,
           skin_tint: str = "#FCE4DC", remaps: list[str] | None = None,
           tint_size: float = 30.0):
    # RGBA PNGs drop their alpha channel on convert("RGB"), keeping the raw RGB
    # under transparent pixels (usually black) — that black then masquerades as
    # paper and the ink mask finds halos around strokes instead of strokes.
    # Composite transparency on white paper first (meme PNGs are drawn for white).
    src_im = Image.open(src)
    if src_im.mode in ("RGBA", "LA", "P"):
        rgba = src_im.convert("RGBA")
        paper_im = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        src_im = Image.alpha_composite(paper_im, rgba)
    im = flat.fit_page(src_im.convert("RGB"))
    arr_u8 = maybe_lift(np.array(im))
    arr = arr_u8.astype(np.int16)
    if im.size != PAGE:
        raise SystemExit(f"{name}: page is {im.size}, wanted {PAGE}; fit_page failed")
    h, w = arr.shape[:2]

    ink = ink_hysteresis(arr)
    if not ink.any():
        raise SystemExit(f"{name}: no ink found")
    radius = edt_radius(ink)
    regions_m = region_mask(ink, radius)
    stroke_m = ink & ~regions_m

    paper = "#{:02X}{:02X}{:02X}".format(
        *[int(v) for v in np.median(arr[:4].reshape(-1, 3), axis=0)]
    )
    # Line art on white/cream: force white paper when border is near-white.
    if all(int(v) >= 240 for v in np.median(arr[:4].reshape(-1, 3), axis=0)):
        paper = "#FFFFFF"

    hand = Hand(flat.seed_for(name), (0, 0))
    padded = (w + PAD * 2, h + PAD * 2)
    session = {
        "version": 1, "started": "generated", "duration": 0, "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": padded[0], "height": padded[1], "originX": 0, "originY": 0, "fixed": True},
        "final": {"width": padded[0], "height": padded[1], "extraLeft": 0, "extraTop": 0},
        "paper": None, "ops": hand.ops,
    }
    scene = svg_export.Scene(session)

    # --- 1. Enclosed paper tints (skin/face/interior washes, bottom layer) -----
    pockets = discover_pockets(ink, regions_m, arr, min_px=250)
    if pockets:
        for idx, p in enumerate(pockets):
            kind = "colored" if p["is_colored"] else (
                "background-gap" if p.get("is_background_gap") else "white")
            print(f"{name}: pocket #{idx+1} seed={p['seed']} px={p['px']} src={p['src_hex']} ({kind}) angle={p['angle']:+.0f}")

    effective_tints = list(tints or [])
    if auto_tint and pockets:
        remap_rules = parse_remap_specs(remaps)
        skin_hex = skin_tint if skin_tint.startswith("#") else "#" + skin_tint
        for p in pockets:
            if p["is_colored"]:
                col = remap_color(p["src_hex"], remap_rules)
                effective_tints.append(f"{p['seed']}:{col}@{int(p['angle'])}")
            elif p["px"] >= 800 and skin_tint.lower() != "none" and not p.get("is_background_gap"):
                col = remap_color(skin_hex, remap_rules)
                effective_tints.append(f"{p['seed']}:{col}@25")

    for spec_i, tint_spec in enumerate(effective_tints):
        seed_spec, t_color, t_angle = parse_tint_spec(tint_spec)
        old_op = hand.opacity
        hand.opacity = wash_opacity if wash_opacity is not None else 0.45
        t_strokes = 0
        wash_jitter = 0.4 + 0.55 * max(0.0, float(slop))
        outline_jitter = 0.8 + 1.4 * max(0.0, float(slop))
        # 30 px is the face/body wash: caps kiss the outline, rows 21 px apart,
        # pockets welded across 15 px gaps. A smaller brush is a tight fill —
        # cap pulled inside, rows overlapping, only hairline gaps welded.
        tight = tint_size < 29.5
        close_px = 5 if tight else 15
        if tight:
            # Proportional, no floor. A 0.15 floor made --slop 0.5 look like 0.7.
            wash_jitter = 0.40 * max(0.0, float(slop))
        t_mask = extract_enclosed_tint_mask(ink, regions_m, seed_spec, close=close_px)
        # recompute geoms from the (possibly tighter) mask
        t_geoms = region_geoms(t_mask)
        if not t_geoms:
            raise SystemExit(f"{name}: tint '{tint_spec}' produced no region >= 60 px")
        target_geoms = t_geoms[:1] if seed_spec == "auto" else t_geoms
        # Offset seed by spec_i * 17 so stacked --tint passes (e.g. two-tone wood
        # grain on pirate_roller) don't trace identical scanline rows and wobble.
        for ti, tg in enumerate(target_geoms):
            minx, miny, maxx, maxy = tg.bounds
            short = max(1.0, min(maxx - minx, maxy - miny))
            size = min(float(tint_size), max(6.0, short * 0.72)) if tight else float(tint_size)
            inset_frac = max(0.15, 0.5 - 2.0 / size) if tight else 0.15
            spacing = max(5.0, size * 0.62) if tight else 21.0
            lines = hatch_region(
                tg, angle_deg=t_angle, spacing=spacing, brush_size=size,
                seed=100 + spec_i * 17 + ti, slop=slop, inset_frac=inset_frac,
            )
            if not lines and ti == 0:
                lines = hatch_region(
                    tg, angle_deg=t_angle, spacing=max(5.0, size * 0.5),
                    brush_size=max(6.0, size * 0.8),
                    seed=100 + spec_i * 17 + ti, slop=slop, inset_frac=0.15,
                )
            for line, sw in lines:
                keys = _wash_keys(line)
                if keys is None:
                    continue
                hand.stroke(hand.curve(keys), t_color, size=sw, jitter=wash_jitter)
                scene.stroke(hand.ops[-1])
                t_strokes += 1
        hand.opacity = old_op
        print(f"{name}: tint {t_color} ({seed_spec}) painted {t_strokes} wash strokes")

    geoms = region_geoms(regions_m)
    print(f"{name}: ink={int(ink.sum())} region_px={int(regions_m.sum())} "
          f"stroke_px={int(stroke_m.sum())} regions={len(geoms)}")

    # --- 2. Regions (wash hatch or stamp fill + trim outline) ------------------
    region_wash_color = wash_color or ink_color
    wash_jitter = 0.4 + 0.55 * max(0.0, float(slop))
    outline_jitter = 0.8 + 1.4 * max(0.0, float(slop))
    # Centre-line ink ignored --slop before, so a coal outline stayed put when slop dropped.
    ink_jitter = JITTER * max(0.0, float(slop))
    for gi, geom in enumerate(geoms):
        minx, miny, maxx, maxy = geom.bounds
        short = min(maxx - minx, maxy - miny)
        # Wash only hair-scale masses. Brows/pupils are regions too — a 18 px
        # pale hatch turns them into fat translucent blobs (glasses smoke test).
        use_wash = wash and (geom.area >= 5000 or short >= 70)
        if use_wash:
            angle = -20 if gi % 2 == 0 else 25
            spacing = 18 if geom.area < 20000 else 21
            size = 26.0 if geom.area < 20000 else 30.0
            old = hand.opacity
            hand.opacity = wash_opacity if wash_opacity is not None else 0.32
            for line, sw in hatch_region(geom, angle_deg=angle, spacing=spacing, brush_size=size, seed=200 + gi, slop=slop):
                keys = _wash_keys(line)
                if keys is None:
                    continue
                hand.stroke(hand.curve(keys), region_wash_color, size=sw, jitter=wash_jitter)
                scene.stroke(hand.ops[-1])
            hand.opacity = old
            is_closed_outline = slop <= 0.05
            for arc in sloppy_outline_strokes(geom, seed=300 + gi, slop=slop):
                keys = [(x + PAD, y + PAD) for x, y in arc]
                if len(keys) >= 2:
                    hand.stroke(hand.curve(keys, closed=is_closed_outline), ink_color, size=outline_size(geom), jitter=outline_jitter)
                    scene.stroke(hand.ops[-1])
        elif short < 36:
            # Pupil-scale: exact region stamp without extra buffer(1.5) or outline stroke.
            grown = translate(geom, PAD, PAD)
            for part in svg_export.polygons_of(grown):
                if part.area >= 1:
                    scene.layers.append(svg_export.Layer("fill", part, ink_color, 1.0))
        else:
            tracer._stamp(scene, geom, ink_color)
            ring = list(geom.exterior.coords)
            keys = [(x + PAD, y + PAD) for x, y in ring]
            if len(keys) >= 3:
                hand.stroke(hand.curve(keys, closed=True), ink_color, size=outline_size(geom), jitter=ink_jitter)
                scene.stroke(hand.ops[-1])

    # --- strokes: EDT per-run width, then glue what thinning split --------------
    raw_paths = []
    for pixels in tracer.components(stroke_m):
        if len(pixels) < 15:
            continue
        ys = np.array([p[0] for p in pixels])
        xs = np.array([p[1] for p in pixels])
        y0, y1 = max(0, ys.min() - 1), min(h, ys.max() + 2)
        x0, x1 = max(0, xs.min() - 1), min(w, xs.max() + 2)
        blob = np.zeros((y1 - y0, x1 - x0), bool)
        blob[ys - y0, xs - x0] = True
        sk = flat.skeleton(blob)  # skeleton_paths prunes the L-corners itself
        if int(sk.sum()) == 0:
            continue
        comp_paths = [p for p in flat.skeleton_paths(sk) if len(p) >= INK_MIN]
        # Feature cluster: a tiny blob (stubble patch, arm-hair ticks) is a
        # deliberate drawing feature even when it shatters into several short
        # paths; junction crumbs come from big stroke blobs instead.
        is_isolated_feature = len(pixels) < 250 or (len(comp_paths) == 1 and len(pixels) >= 20)
        for path in comp_paths:
            pts = [(x + x0 + 0.5, y + y0 + 0.5) for y, x in path]
            rs = path_radii(path, radius, y0, x0)
            for s_pts, s_tone, s_size in split_by_radius(pts, rs, ink_color):
                raw_paths.append((s_pts, s_tone, s_size, is_isolated_feature))

    strokes = 0
    dropped_short = 0
    for pts, tone, size, keep_short in glue_chains(raw_paths):
        reach = path_reach(pts)
        # A hooked or U-shaped chain with raw reach 13..15 px can shrink below
        # SLOP (12 px) after simplify(1.0) + Catmull-Rom + hand wobble, leaving
        # `samples` empty in hand.stroke (`IndexError: list index out of range`).
        # Guard at 15.0 px and stretch borderline keepers to 15.6 px (2 * 7.8).
        if reach < shape_lint.SLOP + 3:
            if not keep_short and reach < 8.5:
                dropped_short += 1
                continue
            # Stretch isolated features (nose ticks, short hair spikes) to ~15.6 px
            # along their tangent so hand.py draws them instead of dropping them.
            (ax, ay), (bx, by) = pts[0], pts[-1]
            d = math.dist((ax, ay), (bx, by))
            if d > 0.0:
                ux, uy = (bx - ax) / d, (by - ay) / d
            else:
                ux, uy = 0.0, 1.0
            mx, my = (ax + bx) / 2, (ay + by) / 2
            drawn = [(mx - ux * 7.8, my - uy * 7.8), (mx + ux * 7.8, my + uy * 7.8)]
        else:
            drawn = list(LineString(pts).simplify(1.0).coords)
        keys = [(x + PAD, y + PAD) for x, y in drawn]
        hand.stroke(hand.curve(keys), tone, size=size, jitter=ink_jitter)
        scene.stroke(hand.ops[-1])
        strokes += 1

    if strokes == 0 and not geoms:
        raise SystemExit(f"{name}: no strokes or regions survived")
    print(f"{name}: stroke chains={strokes} (raw={len(raw_paths)}, dropped_short={dropped_short})")

    session["duration"] = round(hand.t, 3)
    svg = flat.page_svg(scene, paper)
    if (w, h) != PAGE:
        raise SystemExit(f"{name}: page-svg from a {w}x{h} canvas, wanted {PAGE}")
    png = flat.rasterize(svg, 1280, 960)
    extrema = png.convert("RGB").getextrema()
    if all(v[1] - v[0] < 8 for v in extrema):
        raise SystemExit(f"{name}: render is a uniform colour; the scene content was lost")

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out_dir = out.parent if out.suffix == ".zip" else out
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out if out.suffix == ".zip" else out_dir / f"{name}.zip"

    out_dir.joinpath("bg.svg").write_text(svg)
    png.save(out_dir / "bg.png")
    flat.cover_thumb(png).save(out_dir / "thumb.png")
    dbg = np.zeros((h, w, 3), np.uint8)
    dbg[:] = 255
    dbg[stroke_m] = (40, 40, 40)
    dbg[regions_m] = (200, 80, 80)
    Image.fromarray(dbg).save(out_dir / "edt_split.png")
    if pockets:
        save_pockets_debug(im, pockets, out_dir / "pockets.png")
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for n in ("bg.png", "bg.svg", "thumb.png"):
            z.write(out_dir / n, n)
    lineart.compare(src, out_dir / "compare.png", out_dir / "bg.png")
    print("wrote", zip_path, zip_path.stat().st_size)

    if not skip_budget:
        src_fit = np.array(Image.fromarray(arr_u8).resize((640, 480), Image.LANCZOS))
        bg_fit = np.array(png.convert("RGB").resize((640, 480), Image.LANCZOS))
        ink_budget(src_fit, bg_fit, name, wash=wash)
    return zip_path


def main(argv=None):
    p = argparse.ArgumentParser(description="BonePaper sketch backgrounds (EDT line art + marker wash)")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sketch", help="line-art / hybrid picture -> bg zip")
    s.add_argument("src", type=Path)
    s.add_argument("-o", "--out", type=Path, required=True)
    s.add_argument("--name", default=None)
    s.add_argument("--wash", action="store_true",
                   help="pale wide-brush hatch for large ink regions instead of solid fill")
    s.add_argument("--wash-color", default=None,
                   help="hex colour for --wash strokes (default: --ink)")
    s.add_argument("--tint", action="append", default=[],
                   help="wash enclosed paper region: '#HEX', 'auto:#HEX', or 'x,y:#HEX[@angle]'")
    s.add_argument("--auto-tint", action="store_true",
                   help="automatically wash all discovered pockets (source colour for coloured pockets, --skin-tint for white pockets >= 800 px)")
    s.add_argument("--skin-tint", default="#FCE4DC",
                   help="hex colour for white interior pockets when --auto-tint is enabled (or 'none' to skip white pockets)")
    s.add_argument("--remap", action="append", default=[],
                   help="remap auto-tint colour: 'OLD_HEX:NEW_HEX' (matches within RGB distance 45)")
    s.add_argument("--slop", "--sloppiness", dest="slop", type=float, default=1.0,
                   help="looseness of wash & region outline (0.0=clean, 1.0=default, >1.0=wilder)")
    s.add_argument("--wash-opacity", type=float, default=None,
                   help="opacity for tint and region wash strokes (default: 0.45 tint / 0.32 region)")
    s.add_argument("--tint-size", type=float, default=30.0,
                   help="brush width for --tint washes (default 30). Below 30 the stroke is pulled inside the pocket and the rows overlap")
    s.add_argument("--ink", default="#222222")
    s.add_argument("--no-budget-check", "--skip-budget", dest="skip_budget", action="store_true",
                   help="debug only: do not fail on 8x8 ink-density mismatch")
    s.add_argument("--deploy", metavar="DEVICE", help="devicectl device id; run outside the sandbox")
    args = p.parse_args(argv)
    if args.cmd == "sketch":
        if args.name:
            name = args.name
        elif args.out.suffix == ".zip":
            name = args.out.stem
        else:
            name = args.out.name
        sketch(args.src, args.out, name, args.wash, args.ink, args.skip_budget,
               tints=args.tint, wash_color=args.wash_color, slop=args.slop,
               wash_opacity=args.wash_opacity, auto_tint=args.auto_tint,
               skin_tint=args.skin_tint, remaps=args.remap, tint_size=args.tint_size)
        if args.deploy:
            zip_path = args.out if args.out.suffix == ".zip" else args.out / f"{name}.zip"
            flat.deploy(args.deploy, zip_path, f"bgs/{int(time.time() * 1000)}.zip")
    else:
        raise SystemExit(f"unknown command {args.cmd}")


if __name__ == "__main__":
    main()
