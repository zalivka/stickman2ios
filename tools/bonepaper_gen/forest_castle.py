"""Forest with a far-away castle, drawn like the first real recording: 640x480 white sheet, outline then bucket.

usage: python3.12 forest_castle.py <out_dir> [seed]
"""
import json
import math
import sys
from pathlib import Path

from hand import Hand
import replay

W, H = 640, 480
ORIGIN = (704, 784)

GRASS = "#5DBB3F"
SKY = "#9ED8FF"
SUN = "#FCD936"
STONE_LINE = "#7A7A7A"
STONE = "#B4B4B4"
ROOF = "#E63836"
BLACK = "#000000"
TRUNK = "#8C6E63"
LEAVES = "#2E8B2E"
PINE = "#1F6B3A"


def horizon(hand):
    keys = [(-12, 318), (70, 312), (170, 304), (240, 282), (268, 236), (330, 230),
            (392, 238), (420, 284), (500, 306), (590, 312), (652, 308)]
    hand.stroke(hand.curve(keys), GRASS)
    hand.fill((320, 440), GRASS)


def sun(hand):
    cx, cy, r = 70, 70, 34
    keys = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in [i * math.pi / 4 - 2.4 for i in range(8)]]
    hand.stroke(hand.curve(keys, closed=True), SUN, closed=True)
    hand.fill((cx, cy), SUN)
    for i in range(7):
        a = -0.2 + i * 0.36
        hand.stroke(hand.poly([(cx + (r + 14) * math.cos(a), cy + (r + 14) * math.sin(a)),
                               (cx + (r + 38) * math.cos(a), cy + (r + 38) * math.sin(a))]), SUN)


def castle(hand):
    left, right, bottom = 262, 398, 232
    tower, top, wall = 34, 132, 180
    step = (right - left - 2 * tower) / 3
    x1 = left + tower
    outline = [(left, bottom), (left, top), (x1, top), (x1, wall),
               (x1, wall - 16), (x1 + step, wall - 16), (x1 + step, wall),
               (x1 + 2 * step, wall), (x1 + 2 * step, wall - 16), (x1 + 3 * step, wall - 16),
               (right - tower, top), (right, top), (right, bottom)]
    hand.stroke(hand.poly(outline, closed=True), STONE_LINE, closed=True, jitter=0.6)
    hand.fill((330, 205), STONE)
    for x0 in (left, right - tower):
        roof = [(x0 - 6, top), (x0 + tower / 2, top - 38), (x0 + tower + 6, top)]
        hand.stroke(hand.poly(roof, closed=True), ROOF, closed=True, jitter=0.6)
        hand.fill((x0 + tower / 2, top - 12), ROOF)
    pole = left + tower / 2
    hand.stroke(hand.poly([(pole, top - 38), (pole, top - 70)]), BLACK)
    hand.stroke(hand.poly([(pole, top - 70), (pole + 26, top - 62), (pole, top - 54)], closed=True), ROOF, closed=True)
    hand.stroke(hand.curve([(314, bottom), (313, 208), (330, 194), (347, 208), (346, bottom)]), BLACK)
    hand.fill((330, 220), BLACK)
    for x in (left + tower / 2, right - tower / 2):
        hand.stroke(hand.poly([(x, top + 16), (x + 1, top + 30)]), BLACK)


def small_pine(hand, x, base, height):
    half = height * 0.32
    keys = [(x - half, base), (x, base - height), (x + half, base)]
    hand.stroke(hand.poly(keys, closed=True), PINE, closed=True, jitter=0.7)
    hand.fill((x, base - height * 0.3), PINE)


def round_tree(hand, x, base):
    hand.stroke(hand.poly([(x - 13, base), (x - 11, base - 72), (x + 12, base - 72), (x + 14, base)], closed=True),
                TRUNK, closed=True, jitter=0.6)
    hand.fill((x, base - 36), TRUNK)
    cy, r = base - 72 - 52, 62
    keys = []
    for i in range(8):
        a = i * math.pi / 4 + 1.9
        rr = r * (1.08 if i % 2 else 0.9)
        keys.append((x + rr * math.cos(a), cy + rr * math.sin(a)))
    hand.stroke(hand.curve(keys, closed=True), LEAVES, closed=True)
    hand.fill((x, cy - 20), LEAVES)
    hand.fill((x - 30, cy + 38), LEAVES)


def big_pine(hand, x, base, height):
    hand.stroke(hand.poly([(x - 9, base), (x - 9, base - 30), (x + 9, base - 30), (x + 9, base)], closed=True),
                TRUNK, closed=True, jitter=0.5)
    hand.fill((x, base - 12), TRUNK)
    top = base - 30 - height
    tiers = 3
    right = []
    for k in range(1, tiers + 1):
        y = top + height * k / tiers
        wide = 12 + 14 * k
        right.append((x + wide, y))
        if k < tiers:
            right.append((x + wide * 0.45, y - 4))
    left = [(2 * x - px, py) for px, py in reversed(right)]
    keys = [(x, top)] + right + left
    hand.stroke(hand.poly(keys, closed=True), PINE, closed=True, jitter=0.7)
    hand.fill((x, top + height * 0.55), PINE)
    hand.fill((x, base - 30 - 12), PINE)


def draw(seed: int) -> dict:
    hand = Hand(seed, ORIGIN)
    horizon(hand)
    sun(hand)
    castle(hand)
    for x, h in [(78, 62), (155, 70), (212, 56), (446, 58), (492, 70), (568, 64)]:
        small_pine(hand, x, 308, h)
    for x, base, h in [(38, 452, 170), (118, 440, 150), (196, 458, 128), (452, 456, 132), (530, 442, 156), (606, 452, 176)]:
        big_pine(hand, x, base, h)
    hand.fill((330, 30), SKY)
    return {
        "version": 1, "started": "generated", "duration": round(hand.t, 3), "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": W, "height": H, "originX": ORIGIN[0], "originY": ORIGIN[1], "fixed": True},
        "final": {"width": W, "height": H, "extraLeft": 0, "extraTop": 0},
        "paper": "#FFFFFF", "ops": hand.ops,
    }


def main():
    out = Path(sys.argv[1])
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    out.mkdir(parents=True, exist_ok=True)
    session = draw(seed)
    (out / "session.json").write_text(json.dumps(session, sort_keys=True))
    image = replay.render(session)
    image.resize((W, H), replay.Image.LANCZOS).save(out / "replay.png")
    strokes = sum(1 for o in session["ops"] if o["op"] == "stroke")
    fills = sum(1 for o in session["ops"] if o["op"] == "fill")
    print(out / "replay.png", f"strokes {strokes} fills {fills} duration {session['duration']:.0f}s")


if __name__ == "__main__":
    main()
