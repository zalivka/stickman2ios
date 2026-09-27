"""Evening lakeside with trees. The lower middle stays empty.

Two pines stand across the shoreline, a round tree and a sail cross the far shore. Each gets one tap;
`Hand.fill` re-taps the part that lies over the other colour.

usage: .venv/bin/python lake.py [out_dir]
"""
import json
import subprocess
import sys
from pathlib import Path

from cartoons import ORIGIN, W, H, session, band, blob
from hand import Hand
from svg_export import Scene

DUSK = "#4B3F7A"
SKY = "#F2A56B"
SUN = "#F9C74F"
STAR = "#FFF3C4"
HILLS = "#8A5C8E"
LAKE = "#3E5C91"
GLINT = "#F9C74F"
GRASS = "#3F5E34"
PINE = "#1E3F2A"
CROWN = "#2F7A4A"
CROWN_LINE = "#14301C"
TRUNK = "#5A3A22"
HULL = "#8A4B2E"
HULL_LINE = "#3A2014"
SAIL = "#F4EBDD"
MAST = "#4A3222"


def draw(seed):
    hand = Hand(seed, ORIGIN, (W, H))
    band(hand, 390, GRASS, (320, 440))
    hand.stroke(hand.curve([(-16, 250), (656, 251)]), LAKE)
    hand.fill((320, 320), LAKE)
    hills = [(-16, 200), (90, 165), (200, 190), (300, 140), (430, 140), (540, 130), (656, 190)]
    hand.stroke(hand.curve(hills), HILLS)
    hand.fill((300, 200), HILLS)
    hand.stroke(hand.curve([(-16, 50), (656, 51)]), DUSK)
    hand.fill((320, 20), DUSK)
    for x, y in ((70, 24), (410, 30), (600, 20)):
        hand.stroke(hand.poly([(x - 8, y), (x + 8, y)]), STAR, size=6)
        hand.stroke(hand.poly([(x, y - 8), (x, y + 8)]), STAR, size=6)
    blob(hand, 250, 95, 28, SUN)
    for x0, x1, y, size in ((218, 282, 272, 8), (230, 270, 296, 7), (242, 258, 318, 6)):
        hand.stroke(hand.poly([(x0, y), (x1, y)]), GLINT, size=size)

    hull = [(360, 288), (470, 288), (452, 326), (378, 326)]
    hand.stroke(hand.poly(hull, closed=True), HULL_LINE, closed=True, jitter=0.4)
    hand.fill((415, 307), HULL)
    sail = [(390, 170), (390, 290), (480, 290)]
    hand.stroke(hand.poly(sail, closed=True), SAIL, closed=True, jitter=0.4)
    hand.fill((420, 273), SAIL)
    hand.stroke(hand.poly([(390, 292), (390, 158)]), MAST, size=8)

    hand.stroke(hand.poly([(575, 440), (575, 312)]), TRUNK, size=18)
    crown = [(575 + 55 * c, 255 + 55 * s) for c, s in
             ((1, 0), (0.7, 0.7), (0, 1), (-0.7, 0.7), (-1, 0), (-0.7, -0.7), (0, -1), (0.7, -0.7))]
    hand.stroke(hand.curve(crown, closed=True), CROWN_LINE, closed=True, jitter=0.4)
    hand.fill((548, 285), CROWN)

    for x, tip, base in ((70, 300, 440), (150, 320, 448)):
        tree = [(x - 48, base), (x, tip), (x + 48, base)]
        hand.stroke(hand.poly(tree, closed=True), PINE, closed=True, jitter=0.5)
        hand.fill((x, base - 22), PINE)

    hand.fill((320, 110), SKY)
    return session(hand, SKY)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "out" / "lake"
    out.mkdir(parents=True, exist_ok=True)
    data = draw(1)
    (out / "session.json").write_text(json.dumps(data, sort_keys=True))
    scene = Scene(data)
    scene.run(data["ops"])
    svg = out / "drawing.svg"
    svg.write_text(scene.svg(flat=False))
    png = out / "lake.png"
    subprocess.run(["rsvg-convert", "-w", "1280", "-h", "960", "-o", str(png), str(svg)], check=True)
    fills = sum(1 for op in data["ops"] if op["op"] == "fill")
    strokes = sum(1 for op in data["ops"] if op["op"] == "stroke")
    print(png, f"strokes {strokes} fills {fills} duration {data['duration']}")


if __name__ == "__main__":
    main()
