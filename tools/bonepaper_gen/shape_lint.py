"""Checks a shape list before bluehairsvg.brush_svg draws it.

A shape is (color, geom) or (color, geom, expect) with expect "limb" or "compact".
Coordinates are the bitmap or page, without PAD. Classification is the same
test brush_svg uses, so the table printed here is what the brush will do.

Fatal issues are the ones that crash the hand or leak a fill. Warnings are
the ones that come out wrong on the page: a notch the brush closes, a part
thinner than its outline, two touching colours a recolour tap treats as one.
Distance between separate shapes is not checked: an arm touching a head is meant.
"""
import math
from dataclasses import dataclass

from shapely.geometry import Polygon

import svg_export

BRUSH = 14.0
WIDE = 42.0
PAD = 40
# hand.SLOP: a stroke has to get this far from its start.
SLOP = 12.0
# Minimum feature and gap at brush 14 (castle battlements at 13 px welded, 22 px held).
GAP = 22.0
LEAK = 0.85


@dataclass
class Issue:
    fatal: bool
    text: str


@dataclass
class Plan:
    index: int
    color: str
    geom: Polygon
    expect: str | None
    kind: str
    short: float
    long: float
    size: float
    corners: int


def plan(index, color, geom, expect=None):
    """What brush_svg will do with this shape. Mirrors its limb test exactly."""
    ring = list(geom.exterior.coords)[:-1]
    rect = geom.minimum_rotated_rectangle
    corners = list(rect.exterior.coords)[:4]
    edges = [math.dist(corners[i], corners[(i + 1) % 4]) for i in range(len(corners))]
    short = min(edges) if len(edges) == 4 else WIDE
    long_len = max(edges) if len(edges) == 4 else 0.0
    if not math.isfinite(short):
        short = WIDE
    elongated = short < WIDE and long_len > short * 2.2
    if elongated or len(ring) < 4:
        kind = "limb"
        size = min(48.0, max(BRUSH, short))
    else:
        kind = "compact"
        size = BRUSH if short >= WIDE else max(6.0, short * 0.4)
    return Plan(index, color, geom, expect, kind, short, long_len, size, len(ring))


def _where(geom):
    p = geom.representative_point()
    return f"({p.x:.0f}, {p.y:.0f})"


def _pieces(geom, min_area):
    return [part for part in svg_export.polygons_of(geom) if part.area > min_area]


def _shape_issues(p, canvas_area):
    tag = f"#{p.index} {p.color} {p.kind}"
    if p.geom.area > canvas_area * LEAK:
        return [Issue(True, f"{tag}: area {p.geom.area:.0f} is over {LEAK:.0%} of the padded canvas; the fill leaks")]
    if p.corners < 3:
        return [Issue(True, f"{tag}: {p.corners} corners; brush_svg would skip it")]
    out = []
    if p.expect and p.expect != p.kind:
        out.append(Issue(True, f"{tag}: expected {p.expect} (short={p.short:.0f} long={p.long:.0f})"))
    if p.kind == "limb":
        if p.corners == 3 and p.expect != "limb":
            out.append(Issue(False, f"{tag} at {_where(p.geom)}: 3 corners, drawn as one stroke"))
        return out
    ring = list(p.geom.exterior.coords)[:-1]
    reach = max(math.dist(ring[0], q) for q in ring)
    if reach < SLOP:
        out.append(Issue(True, f"{tag} at {_where(p.geom)}: loop never gets {SLOP:.0f} px from its start"))
    # Just under half, so a notch of exactly GAP stays open.
    half = GAP / 2 - 0.1
    closed = p.geom.buffer(half, join_style="round").buffer(-half, join_style="round")
    for notch in _pieces(closed.difference(p.geom), GAP * GAP / 4):
        out.append(Issue(False, f"{tag}: notch under {GAP:.0f} px at {_where(notch)} closes under the brush"))
    r = p.size / 2
    opened = p.geom.buffer(-r, join_style="round").buffer(r, join_style="round")
    for thin in _pieces(p.geom.difference(opened), p.size * p.size * 2):
        out.append(Issue(False, f"{tag}: part narrower than its {p.size:.0f} px outline at {_where(thin)}; it comes out solid and rounded"))
    return out


def _pair_issues(a, b):
    if a.color == b.color or a.geom.distance(b.geom) > max(a.size, b.size):
        return []
    distance = svg_export.color_distance(a.color, b.color)
    if distance >= svg_export.NEIGHBOUR:
        return []
    return [Issue(False, f"#{a.index} {a.color} and #{b.index} {b.color}: OKLab {distance:.3f} < {svg_export.NEIGHBOUR}; a fill tap recolours both")]


def lint(shapes, size):
    """shapes: [(color, geom)] or [(color, geom, expect)]. size: (width, height) without PAD."""
    canvas_area = (size[0] + PAD * 2) * (size[1] + PAD * 2)
    plans, issues = [], []
    for index, shape in enumerate(shapes):
        color, geom = shape[0], shape[1]
        expect = shape[2] if len(shape) > 2 else None
        if expect not in (None, "limb", "compact"):
            raise SystemExit(f"#{index}: expect must be limb or compact, got {expect!r}")
        if geom.is_empty or geom.geom_type != "Polygon" or not geom.is_valid or geom.area < 30:
            issues.append(Issue(True, f"#{index} {color}: not a valid polygon of area >= 30"))
            continue
        p = plan(index, color, geom, expect)
        plans.append(p)
        issues.extend(_shape_issues(p, canvas_area))
    for i, a in enumerate(plans):
        for b in plans[i + 1:]:
            issues.extend(_pair_issues(a, b))
    return plans, issues


def report(plans, issues, label=""):
    head = f"{label}: " if label else ""
    limbs = sum(1 for p in plans if p.kind == "limb")
    print(f"{head}{len(plans)} shapes, {limbs} limbs, {len(plans) - limbs} compact")
    for p in plans:
        print(f"  #{p.index:<3} {p.color} {p.kind:<7} short={p.short:4.0f} long={p.long:4.0f} brush={p.size:4.1f} corners={p.corners}")
    for issue in issues:
        print(f"  {'FATAL' if issue.fatal else 'warn '} {issue.text}")
