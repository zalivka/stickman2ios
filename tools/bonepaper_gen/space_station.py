"""Inside a space station: two huge windows, Mars in the big one, a control desk and an astronaut.

usage: python3.12 space_station.py <out_dir> [seed]
"""
import json
import math
import sys
from pathlib import Path

from hand import Hand
import replay

W, H = 640, 480
ORIGIN = (704, 784)

FLOOR_LINE = "#3A3D4A"
FLOOR = "#5B5F73"
WALL = "#D6DEE8"
FRAME = "#5A6F8A"
SPACE = "#0B0B2A"
MARS = "#E0662C"
MARS_DARK = "#A8401C"
WHITE = "#FFFFFF"
STAR = "#FCD936"
MOON = "#9E9E9E"
DESK = "#8A96A8"
SCREEN = "#26C7D9"
VISOR = "#8FD3FF"
SUIT_LINE = "#9E9E9E"
RED = "#E63836"
GREEN = "#7DB343"
YELLOW = "#FCD936"

BIG = (30, 40, 410, 280)
SMALL = (450, 40, 610, 260)


def blob(hand, cx, cy, r, n=8, bump=0.12):
    keys = []
    for i in range(n):
        a = i * 2 * math.pi / n + hand.rng.uniform(-0.15, 0.15)
        rr = r * (1 + hand.rng.uniform(-bump, bump))
        keys.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return hand.curve(keys, closed=True)


def rect(hand, x0, y0, x1, y1):
    return hand.poly([(x0, y1), (x0, y0), (x1, y0), (x1, y1)], closed=True)


def star(hand, x, y, color, plus):
    if plus:
        hand.stroke(hand.poly([(x - 9, y), (x + 9, y + 1)]), color)
        hand.stroke(hand.poly([(x, y - 9), (x + 1, y + 9)]), color)
    else:
        hand.stroke(hand.poly([(x - 7, y - 2), (x + 7, y + 2)]), color)


def windows(hand):
    hand.stroke(rect(hand, *BIG), FRAME, closed=True, jitter=0.7)
    hand.stroke(rect(hand, *SMALL), FRAME, closed=True, jitter=0.7)


def mars(hand):
    cx, cy, r = 225, 165, 90
    hand.stroke(blob(hand, cx, cy, r, n=10, bump=0.03), MARS, closed=True)
    hand.fill((cx, cy), MARS)
    for dx, dy, rr in [(-38, 10, 17), (30, 36, 14), (22, -16, 11)]:
        hand.stroke(blob(hand, cx + dx, cy + dy, rr, n=6, bump=0.2), MARS_DARK, closed=True)
        hand.fill((cx + dx, cy + dy), MARS_DARK)
    hand.stroke(hand.curve([(cx - 88, cy - 54), (cx, cy - 64), (cx + 88, cy - 54)]), WHITE)
    hand.fill((cx, cy - 80), WHITE)


def space(hand):
    hand.fill((60, 250), SPACE)
    hand.fill((580, 230), SPACE)
    hand.stroke(blob(hand, 525, 100, 20, n=6, bump=0.2), MOON, closed=True)
    hand.fill((525, 100), MOON)
    for x, y, color, plus in [(70, 75, WHITE, True), (360, 70, STAR, False), (380, 150, WHITE, False),
                              (345, 235, STAR, True), (75, 190, WHITE, False), (120, 250, STAR, False),
                              (130, 60, STAR, False), (585, 75, WHITE, True), (490, 180, STAR, False),
                              (575, 215, WHITE, False)]:
        star(hand, x, y, color, plus)


def floor(hand):
    hand.stroke(hand.curve([(-12, 382), (200, 378), (420, 381), (652, 379)]), FLOOR_LINE)
    hand.fill((320, 460), FLOOR)


def desk(hand):
    hand.stroke(hand.poly([(140, 446), (170, 326), (470, 326), (500, 446)], closed=True), FLOOR_LINE,
                closed=True, jitter=0.7)
    hand.fill((320, 350), DESK)
    hand.fill((320, 420), DESK)
    hand.stroke(rect(hand, 245, 340, 395, 372), FLOOR_LINE, closed=True, jitter=0.6)
    hand.fill((320, 356), SCREEN)
    hand.stroke(hand.poly([(265, 358), (285, 350), (300, 362), (320, 348), (340, 360), (375, 352)]), WHITE)
    for x, color in [(190, RED), (220, YELLOW), (420, GREEN), (450, RED)]:
        hand.stroke(hand.poly([(x - 6, 405), (x + 7, 407)]), color)
    hand.stroke(hand.poly([(320, 425), (338, 400)]), FLOOR_LINE)


def astronaut(hand):
    x = 560
    hand.stroke(blob(hand, x, 303, 32, n=8, bump=0.05), SUIT_LINE, closed=True)
    hand.stroke(hand.curve([(x - 20, 292), (x, 285), (x + 20, 292), (x + 18, 316), (x - 18, 316)], closed=True),
                SUIT_LINE, closed=True, jitter=0.5)
    hand.fill((x, 302), VISOR)
    hand.stroke(rect(hand, x - 24, 335, x + 24, 400), SUIT_LINE, closed=True, jitter=0.6)
    hand.stroke(hand.poly([(x - 24, 345), (x - 48, 382)]), SUIT_LINE)
    hand.stroke(hand.poly([(x + 24, 345), (x + 50, 372)]), SUIT_LINE)
    hand.stroke(hand.poly([(x - 12, 400), (x - 14, 446)]), SUIT_LINE)
    hand.stroke(hand.poly([(x + 12, 400), (x + 15, 446)]), SUIT_LINE)
    hand.stroke(hand.poly([(x - 8, 356), (x + 8, 358)]), RED)


def draw(seed: int) -> dict:
    hand = Hand(seed, ORIGIN)
    windows(hand)
    mars(hand)
    space(hand)
    floor(hand)
    desk(hand)
    astronaut(hand)
    hand.fill((430, 150), WALL)
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
