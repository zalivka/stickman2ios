"""CV front-end for photographic backgrounds: a photo to brushable shapes and ink strokes.

`flat.py regions()` needs flat colour. A photo is continuous tone, so its
`color_centers()` bucketing makes one band per shade and the tracer emits
hundreds of crescent slivers that die in `hand.py`. This module replaces that
step with segmentation that is aware of the brush's minimum feature size:

1. `cv2.pyrMeanShiftFiltering` flattens gradients while keeping silhouettes.
2. k-means in CIE Lab, with the chroma axes weighted so a turquoise dome is not
   merged into the brick behind it. Perceptual, unlike `(rgb // 16) * 16`.
3. Every cluster is split into connected components. A component is classified
   by its Euclidean distance transform (local half-width), the same measure
   `ink.py` uses:
   - half-width >= REGION_R: a region, traced to a polygon.
   - mid-scale and high contrast: still a polygon, just a small one (a dome, a
     turret). Too narrow to survive `inset()` at the region brush width, so it
     is buffered less and drawn on top.
   - thin: a centre-line stroke, at the width the EDT measured.
4. Canny on a bilateral-filtered luma adds the structural edges that a colour
   cluster cannot express (rooflines, window rows, railings).

The page contract stays `flat.py`'s: 640x480, one shape reaching three edges
supplies the paper colour, everything goes through `shape_lint` before the brush.
"""
import math

import numpy as np
from scipy.ndimage import distance_transform_edt
from shapely.affinity import translate
from shapely.geometry import LineString, Polygon

# Local half-width at which a blob is wide enough to keep as a region. A 14 px
# brush and `inset()` need about 7.5 px inside before the outline stops eating it.
REGION_R = 7.5
REGION_AREA = 220
# A mid-scale blob: too thin for `inset()`, but still a picture (a dome, a turret).
MID_R = 3.8
MID_AREA = 75
DETAIL_AREA = 40
DETAIL_REACH = 10
# OKLab distance below which a detail blob is just antialias fringe of its host.
DETAIL_CONTRAST = 0.075
# A thin blob becomes a stroke only when its long axis clears this. Below it, the
# blob is a fleck of texture and skeletonising it just adds scribble.
STROKE_SPAN = 26

# Cluster count when the caller does not pass one.
COLORS = 24
# Chroma weight for the k-means. Grey sky splitting into many bands is harmless
# (they merge into polygons); a saturated dome merging into grey brick is not.
CHROMA = 1.6
# Adjacent regions closer than this in OKLab are one region. `svg_export.NEIGHBOUR`
# is 0.06 and a fill tap recolours both below it, so anything under that is not
# merely similar: it is un-paintable as two shapes.
MERGE_DELTA = 0.055
MERGE_PASSES = 12
# Canny hysteresis on the bilateral luma. The low threshold is above sky noise.
EDGE_LOW = 55
EDGE_HIGH = 130
EDGE_SIZE = 3.8


def _cv2():
    try:
        import cv2
    except ImportError:
        raise SystemExit("photo segmentation needs opencv-python-headless; "
                         "run .venv/bin/pip install opencv-python-headless")
    return cv2


def _hex(rgb):
    return "#{:02X}{:02X}{:02X}".format(*[int(max(0, min(255, v))) for v in rgb])


def _reach(geom):
    ring = list(geom.exterior.coords)[:-1]
    if len(ring) < 3:
        return 0.0
    return max(math.dist(ring[0], q) for q in ring)


def _reach_span(blob):
    """Longest side of a blob's bounding box, in pixels."""
    ys, xs = np.nonzero(blob)
    return float(max(np.ptp(ys), np.ptp(xs)) + 1)


def _polygons(mask, cv2):
    """Exterior polygons of a boolean mask, in pixel coordinates."""
    u8 = mask.astype(np.uint8) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    import svg_export
    out = []
    for contour in contours:
        if len(contour) < 4:
            continue
        poly = Polygon([(float(p[0][0]), float(p[0][1])) for p in contour])
        if not poly.is_valid:
            poly = poly.buffer(0)
        out.extend(part for part in svg_export.polygons_of(poly) if part.area >= 30)
    return out


def _merge_labels(labels, rgb, cv2):
    """Fold neighbouring clusters that are too close to paint as two fills.

    `shape_lint` rejects two touching colours under `NEIGHBOUR` = 0.06: one fill
    tap recolours both. A photo's sky quantises into a dozen such bands, so they
    are merged into whichever neighbour is nearest-and-darkest-hue-compatible,
    largest first, before anything is traced.
    """
    import svg_export
    current = labels.copy()
    for _ in range(MERGE_PASSES):
        ids = np.unique(current)
        ids = ids[ids >= 0]
        if len(ids) < 2:
            break
        tones = {int(i): _hex(np.median(rgb[current == i], axis=0)) for i in ids}
        area = {int(i): int((current == i).sum()) for i in ids}
        pairs = set()
        for dy, dx in ((0, 1), (1, 0)):
            a = current[: current.shape[0] - dy, : current.shape[1] - dx]
            b = current[dy:, dx:]
            edge = a != b
            for p, q in zip(a[edge].tolist(), b[edge].tolist()):
                if p != q:
                    pairs.add((min(p, q), max(p, q)))
        union = {}
        gone_all = set()
        for p, q in sorted(pairs, key=lambda pair: -min(area[pair[0]], area[pair[1]])):
            if p in gone_all or q in gone_all:
                continue
            if svg_export.color_distance(tones[p], tones[q]) >= MERGE_DELTA:
                continue
            # The smaller one gives way, so a big sky keeps its colour.
            keep, gone = (p, q) if area[p] >= area[q] else (q, p)
            union[gone] = keep
            gone_all.add(gone)
            area[keep] += area[gone]
        if not union:
            break
        flat_map = np.arange(current.max() + 1)
        for gone, keep in union.items():
            flat_map[gone] = keep
        current = flat_map[current]
        print(f"photo: merged {len(union)} near-identical regions")
    return current


def _components(labels):
    """(mask, max_radius, area) per connected component of every surviving cluster."""
    cv2 = _cv2()
    found = []
    for k in range(int(labels.max()) + 1):
        mask = (labels == k).astype(np.uint8)
        n, cc, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=4)
        for cid in range(1, n):
            area = int(stats[cid, cv2.CC_STAT_AREA])
            if area < DETAIL_AREA:
                continue
            blob = cc == cid
            found.append((blob, float(distance_transform_edt(blob).max()), area))
    return found


def _skeleton_strokes(blob, rgb, index, tracer, shape_lint, min_len):
    """Centre-line strokes of one thin feature, at the width the EDT measured."""
    import flat
    ys, xs = np.nonzero(blob)
    y0, y1 = max(0, ys.min() - 2), min(blob.shape[0], ys.max() + 3)
    x0, x1 = max(0, xs.min() - 2), min(blob.shape[1], xs.max() + 3)
    sk = flat.skeleton(blob[y0:y1, x0:x1])
    tone = _hex(np.median(rgb[blob], axis=0))
    size = float(np.clip(index * 2.0, 4.0, 10.0))
    out = []
    for path in flat.skeleton_paths(sk):
        if len(path) < min_len:
            continue
        pts = list(LineString([(x + x0 + 0.5, y + y0 + 0.5) for y, x in path]).simplify(1.0).coords)
        reach = max(math.dist(pts[0], q) for q in pts)
        if reach < shape_lint.SLOP + 3.5:
            # A tick under the hand's start threshold is stretched along its own
            # direction instead of dropped: a window mullion is not fringe.
            (ax, ay), (bx, by) = pts[0], pts[-1]
            span = math.dist((ax, ay), (bx, by))
            if span < 3.0:
                continue
            ux, uy = (bx - ax) / span, (by - ay) / span
            mx, my = (ax + bx) / 2, (ay + by) / 2
            pts = [(mx - ux * 8.0, my - uy * 8.0), (mx + ux * 8.0, my + uy * 8.0)]
        out.append((pts, tone, size))
    return out


def _edge_strokes(rgb, cv2, tracer, shape_lint):
    """Structural edges as ink: rooflines, window rows, railings Canny can see."""
    import flat
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    smooth = cv2.bilateralFilter(gray, 9, 45, 45)
    edges = cv2.Canny(smooth, EDGE_LOW, EDGE_HIGH)
    edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)) > 0
    sk = flat.skeleton(edges)
    h, w = gray.shape
    out = []
    for path in flat.skeleton_paths(sk):
        if len(path) < 12:
            continue
        pts = list(LineString([(x + 0.5, y + 0.5) for y, x in path]).simplify(1.2).coords)
        if max(math.dist(pts[0], q) for q in pts) < shape_lint.SLOP + 4:
            continue
        ys = np.clip([p[0] for p in path], 1, h - 2)
        xs = np.clip([p[1] for p in path], 1, w - 2)
        # The dark side of the edge carries the ink tone of the object it bounds.
        dark = np.minimum(np.minimum(rgb[ys - 1, xs], rgb[ys + 1, xs]),
                          np.minimum(rgb[ys, xs - 1], rgb[ys, xs + 1]))
        out.append((pts, _hex(np.median(dark, axis=0) * 0.72), EDGE_SIZE))
    return out


def segment(rgb, colors=COLORS, edges=True, detail=True):
    """A photo to (shapes, lines, paper).

    shapes: (area, "#RRGGBB", Polygon) in page pixels, largest first.
    lines:  ([(x, y), ...], "#RRGGBB", brush_px) centre-line strokes.
    paper:  the page colour, taken from the shape that reaches three page edges.
    """
    import flat
    import shape_lint
    import svg_export

    cv2 = _cv2()
    tracer = flat.tracer
    h, w = rgb.shape[:2]

    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    smooth = cv2.pyrMeanShiftFiltering(bgr, sp=16, sr=26, maxLevel=2)
    lab = cv2.cvtColor(smooth, cv2.COLOR_BGR2LAB).reshape(-1, 3).astype(np.float32)
    lab[:, 1:] *= CHROMA
    cv2.setRNGSeed(42)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 0.5)
    _, labels, _ = cv2.kmeans(lab, colors, None, criteria, 5, cv2.KMEANS_PP_CENTERS)
    labels = labels.reshape((h, w))
    labels = _merge_labels(labels, rgb, cv2)

    regions, mids, details = [], [], []
    for blob, radius, area in _components(labels):
        long_side = max(np.ptp(np.nonzero(blob)[0]), np.ptp(np.nonzero(blob)[1])) + 1
        if radius >= REGION_R and area >= REGION_AREA and long_side >= 22:
            regions.append(blob)
        elif area >= DETAIL_AREA and long_side >= DETAIL_REACH:
            details.append((blob, radius, area))

    if not regions:
        raise SystemExit("photo segmentation found no region wide enough for the brush")

    # The page is a partition: every pixel belongs to the nearest region, so two
    # neighbouring outlines meet under the brush instead of leaving a crack.
    kept = np.zeros((h, w), bool)
    ids = np.zeros((h, w), np.int32)
    for index, blob in enumerate(regions, 1):
        ids[blob] = index
        kept |= blob
    _, (iy, ix) = distance_transform_edt(~kept, return_indices=True)
    page_ids = ids[iy, ix]

    tones = {}
    for index in range(1, len(regions) + 1):
        tones[index] = _hex(np.median(rgb[page_ids == index], axis=0))

    shapes = []
    for index in range(1, len(regions) + 1):
        mask = page_ids == index
        if int(mask.sum()) < 80:
            continue
        for outer in _polygons(mask, cv2):
            geom = outer.buffer(2.5, join_style="round", quad_segs=4).simplify(
                tracer.STRAIGHTEN, preserve_topology=True)
            for part in svg_export.polygons_of(geom):
                if part.area >= 30 and _reach(part) >= shape_lint.SLOP + 3:
                    shapes.append((part.area, tones[index], part))
    shapes.sort(key=lambda item: item[0], reverse=True)

    def spans(geom):
        x0, y0, x1, y1 = geom.bounds
        return sum((x0 <= 3, y0 <= 3, x1 >= w - 3, y1 >= h - 3)) >= 3

    pages = [item for item in shapes if spans(item[2])]
    if not pages:
        raise SystemExit("photo segmentation: no shape reaches three page edges; "
                         "the picture has no background band")
    page = max(pages, key=lambda item: item[0])
    paper = page[1]

    # No inset. `flat.inset` exists because `brush_svg` centres a 14 px closed
    # outline on the boundary and that would spill into the neighbour. A photo
    # page paints fills with no outline and a 3 px contour, so the partition is
    # already exact: insetting would only shrink the dark shapes away.
    drawn, dropped = [], 0
    for _, color, geom in shapes:
        if geom is page[2]:
            continue
        if _reach(geom) < shape_lint.SLOP + 3:
            dropped += 1
            continue
        drawn.append((geom.area, color, geom))

    lines = []
    if detail:
        for blob, radius, area in details:
            tone = _hex(np.median(rgb[blob], axis=0))
            host = tones.get(int(np.bincount(page_ids[blob]).argmax()), paper)
            if svg_export.color_distance(tone, host) < DETAIL_CONTRAST:
                dropped += 1
                continue
            if radius >= MID_R and area >= MID_AREA:
                # Wide enough to paint as a shape. Inset is what killed it in the
                # region pass, so buffer just the antialias fringe and draw on top.
                for outer in _polygons(blob, cv2):
                    geom = outer.buffer(1.5, join_style="round", quad_segs=4).simplify(
                        1.4, preserve_topology=True)
                    for part in svg_export.polygons_of(geom):
                        if part.area >= 45 and _reach(part) >= shape_lint.SLOP + 3:
                            drawn.append((part.area, tone, part))
            # A blob under MID_R stays a stroke only when it is genuinely ink-like:
            # long and narrow (a railing, a mast), not a 6 px fleck of texture.
            # Skeletonising every fleck is what turned the page into a scribble.
            elif _reach_span(blob) >= STROKE_SPAN:
                lines.extend(_skeleton_strokes(blob, rgb, radius, tracer, shape_lint, 6))
    if edges:
        lines.extend(_edge_strokes(rgb, cv2, tracer, shape_lint))

    print(f"photo: {len(regions)} regions, {len(shapes)} shapes, {len(details)} details, "
          f"{len(lines)} strokes, {dropped} dropped, paper={paper}")
    return drawn, lines, paper


def _stroke(hand, points, color, size, closed=False, jitter=None):
    """Stroke one path unless no piece of it clears the hand's 12 px start.

    `hand.curve` returns a list of pieces, and `hand.stroke` exits the process on
    a piece that never gets 12 px from its own start. A contour that hugs a thin
    region trips that, and a per-shape check before the call keeps the run alive.
    """
    import flat
    import shape_lint
    jitter = flat.tracer.JITTER if jitter is None else jitter
    pieces = hand.curve(points, closed=closed)
    usable = []
    for piece in pieces:
        if len(piece) < 2:
            continue
        if max(math.dist(piece[0], q) for q in piece) < shape_lint.SLOP + 2:
            continue
        usable.append(piece)
    if not usable:
        return False
    hand.stroke(usable, color, closed=closed, jitter=jitter, size=size)
    return True


def render(drawing, shapes, lines, seed, outline=3.2):
    """A photo page: flat fills with a thin hand contour, plus the ink strokes.

    `flat.py bg` brushes every region with a 14 px closed outline and a fill tap.
    That is right for a cartoon of 8 flat parts and wrong for a photograph of 40
    regions: 40 fat rings cover the picture and the colour underneath never shows.
    A photo keeps the recursion instead — fill each region, then a contour, then
    the ink on top.

    Fills are appended to the scene first, so every hand stroke lands above them.
    `drawing` only needs `.size`, the same object `brush_svg` takes.
    """
    import flat
    import svg_export
    from hand import Hand

    tracer = flat.tracer
    w, h = drawing.size
    PAD = tracer.PAD
    canvas_w, canvas_h = w + PAD * 2, h + PAD * 2
    hand = Hand(seed, (0, 0))
    session = {
        "version": 1, "started": "generated", "duration": 0, "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": canvas_w, "height": canvas_h, "originX": 0, "originY": 0, "fixed": True},
        "final": {"width": canvas_w, "height": canvas_h, "extraLeft": 0, "extraTop": 0},
        "paper": None, "ops": hand.ops,
    }
    scene = svg_export.Scene(session)

    drawn = sorted(shapes, key=lambda item: -item[0])
    # Largest first, so it sits at the bottom of the layer stack and a small
    # region painted later lands on top of the one it sits inside.
    # No outline of its own: the contour below is the only ink on a boundary.
    for _, color, geom in drawn:
        for part in svg_export.polygons_of(geom):
            scene.layers.append(svg_export.Layer(
                "fill", translate(part, PAD, PAD), color, 1.0))

    if outline:
        for _, color, geom in drawn:
            ring = [(x + PAD, y + PAD) for x, y in list(geom.exterior.coords)[:-1]]
            if len(ring) < 3:
                continue
            _stroke(hand, ring, color, outline, closed=True)

    for pts, color, size in lines:
        _stroke(hand, [(x + PAD, y + PAD) for x, y in pts], color, size)

    scene.run(hand.ops)
    session["duration"] = round(hand.t, 3)
    return scene

