"""A still background: a trolleybus built from a loaf of bread.

usage: .venv/bin/python bread_bus.py [out_dir]
"""
import json
import math
import subprocess
import sys
from pathlib import Path

from cartoons import ORIGIN, W, H, session, band
from hand import Hand
from svg_export import Scene

SKY = "#9ED8FF"
ROAD = "#8E8E93"
CRUST = "#E2A04A"
CRUMB = "#F6D7A8"
SCORE = "#C4782E"
FRAME = "#6B4A32"
GLASS = "#C5E4F8"
DOOR = "#F3C56E"
SIGN = "#F7F3EA"
INK = "#2B2B2B"
SUN = "#FCD936"
WHEEL = "#2B2B2B"
WIRE = "#3A3A3A"
POLE = "#5C5348"
PORE = "#C4A574"


def ellipse(cx, cy, rx, ry, n=8):
    return [(cx + rx * math.cos(a), cy + ry * math.sin(a)) for a in (i * 2 * math.pi / n for i in range(n))]


def rect(hand, x0, y0, x1, y1, color, jitter=0.4):
    hand.stroke(hand.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], closed=True), color, closed=True, jitter=jitter)


def draw(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 300, ROAD, (320, 400))
    hand.stroke(hand.curve([(-16, 44), (656, 40)]), WIRE, size=6)
    hand.stroke(hand.curve([(-16, 62), (656, 58)]), WIRE, size=6)

    loaf = [(140, 278), (162, 176), (250, 140), (400, 134), (500, 148), (536, 200), (530, 278)]
    hand.stroke(hand.poly(loaf, closed=True), CRUST, closed=True, jitter=0.4)
    hand.stroke(hand.curve(ellipse(198, 226, 34, 44), closed=True), CRUMB, closed=True, jitter=0.35)
    rect(hand, 258, 168, 328, 222, FRAME)
    rect(hand, 350, 164, 424, 220, FRAME)
    rect(hand, 458, 188, 510, 274, FRAME)
    hand.stroke(hand.curve(ellipse(518, 210, 12, 12), closed=True), SUN, closed=True, jitter=0.3)

    hand.fill((300, 250), CRUST)
    hand.fill((198, 226), CRUMB)
    hand.fill((293, 195), GLASS)
    hand.fill((387, 192), GLASS)
    hand.fill((484, 230), DOOR)
    hand.fill((518, 210), SUN)

    for a, b in (((210, 168), (250, 148)), ((310, 150), (360, 138)), ((430, 146), (480, 158))):
        hand.stroke(hand.poly([a, b]), SCORE, size=8)
    for x, y in ((184, 214), (210, 236), (188, 248)):
        hand.stroke(hand.poly([(x, y), (x + 14, y + 6)]), PORE, size=6)

    for cx, cy in ((230, 286), (470, 286)):
        hand.stroke(hand.curve(ellipse(cx, cy, 28, 28), closed=True), WHEEL, closed=True, size=16, jitter=0.25)
        hand.stroke(hand.curve(ellipse(cx, cy, 10, 10), closed=True), SIGN, closed=True, size=8, jitter=0.2)

    hand.stroke(hand.poly([(300, 148), (268, 44)]), POLE, size=8)
    hand.stroke(hand.poly([(440, 142), (492, 58)]), POLE, size=8)
    hand.stroke(hand.poly([(250, 44), (286, 44)]), WIRE, size=8)
    hand.stroke(hand.poly([(474, 58), (510, 58)]), WIRE, size=8)
    hand.stroke(hand.poly([(474, 228), (500, 228)]), INK, size=6)
    hand.fill((320, 24), SKY)
    return session(hand, SKY)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "out" / "bread_bus"
    out.mkdir(parents=True, exist_ok=True)
    data = draw(1)
    (out / "session.json").write_text(json.dumps(data, sort_keys=True))
    scene = Scene(data)
    scene.run(data["ops"])
    svg = out / "drawing.svg"
    svg.write_text(scene.svg(flat=False))
    png = out / "bread_bus.png"
    subprocess.run(["rsvg-convert", "-w", "1280", "-h", "960", "-o", str(png), str(svg)], check=True)
    print(png, f"{W}x{H}")


if __name__ == "__main__":
    main()
