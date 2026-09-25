"""Noir city: skyscrapers across the back, an empty road in front. The lower middle stays clear.

usage: python3.12 noir_city.py <out_dir> [seed]
"""
import json
import math
import sys
from pathlib import Path

from hand import Hand
import replay

W, H = 640, 480
ORIGIN = (704, 784)

SKY = "#121624"
SIDEWALK = "#3A3E4C"
ROAD = "#22252E"
CURB = "#4E5260"
DARK = "#161A24"
MID = "#222838"
PALE = "#2C3142"
WINDOW = "#F6D56A"
MOON = "#E4E0D2"
POLE = "#8C909C"
LANE = "#C8C4B0"

GROUND = 270


def block(hand, x0, top, x1, color):
    keys = [(x0, GROUND + 6), (x0, top), (x1, top), (x1, GROUND + 6)]
    hand.stroke(hand.poly(keys, closed=True), color, closed=True, jitter=0.55)
    hand.fill(((x0 + x1) / 2, (top + GROUND) / 2), color)


def windows(hand, spots):
    for x, y in spots:
        hand.stroke(hand.poly([(x, y), (x + 18, y + 1)]), WINDOW)


def lamp(hand, x, arm):
    hand.stroke(hand.poly([(x, GROUND + 8), (x, 430)]), POLE)
    hand.stroke(hand.poly([(x, 312), (x + arm, 304)]), POLE)
    hand.stroke(hand.poly([(x + arm - 16, 298), (x + arm + 4, 300)]), WINDOW)


def moon(hand, cx, cy, r):
    keys = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in (i * math.pi / 4 for i in range(8))]
    hand.stroke(hand.curve(keys, closed=True), MOON, closed=True, jitter=0.5)
    hand.fill((cx, cy), MOON)


def draw(seed: int) -> dict:
    hand = Hand(seed, ORIGIN)
    hand.stroke(hand.curve([(-16, GROUND), (652, GROUND + 2)]), SIDEWALK)
    hand.fill((24, 450), SIDEWALK)

    road = [(36, 520), (250, 300), (390, 300), (604, 520)]
    hand.stroke(hand.poly(road, closed=True), CURB, closed=True, jitter=0.6)
    hand.fill((320, 400), ROAD)

    for x0, top, x1, color in [
        (-12, 34, 56, DARK), (74, 92, 132, MID), (148, 18, 204, DARK), (218, 118, 262, PALE),
        (276, 176, 320, MID), (332, 196, 376, DARK),
        (390, 104, 444, PALE), (458, 16, 520, DARK), (534, 68, 586, MID), (600, 42, 656, DARK),
    ]:
        block(hand, x0, top, x1, color)

    moon(hand, 320, 86, 28)
    hand.stroke(hand.poly([(489, 36), (491, -8)]), POLE)

    windows(hand, [
        (8, 64), (22, 128), (10, 196),
        (90, 124), (104, 188),
        (164, 48), (178, 112), (160, 176), (188, 220),
        (232, 156), (236, 214),
        (404, 136), (418, 196),
        (474, 46), (492, 108), (470, 168), (496, 214),
        (548, 104), (562, 168),
        (614, 78), (612, 150),
    ])
    for x, y, length in [(314, 312, 12), (308, 336, 20), (300, 366, 30)]:
        hand.stroke(hand.poly([(x, y), (x + length, y + length * 0.35)]), LANE)
    lamp(hand, 96, 30)
    lamp(hand, 548, -30)

    hand.fill((320, 36), SKY)
    return {
        "version": 1, "started": "generated", "duration": round(hand.t, 3), "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": W, "height": H, "originX": ORIGIN[0], "originY": ORIGIN[1], "fixed": True},
        "final": {"width": W, "height": H, "extraLeft": 0, "extraTop": 0},
        "paper": SKY, "ops": hand.ops,
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
