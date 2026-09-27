"""Evening lakeside in the winter-village style. The lower middle stays empty.

A dusk band, a sunset band, dark hills, the lake, and a near shore. A small sail sits
on the water only, so it is one colour inside. Each pine crosses the water and the
shore, so it is tapped twice.

usage: .venv/bin/python evening_lake.py [out_dir]
"""
import json
import subprocess
import sys
from pathlib import Path

from cartoons import ORIGIN, session, blob
from hand import Hand
from svg_export import Scene

DUSK = "#3C2F6B"
GLOW = "#F2A56B"
SUN = "#F9C74F"
RIDGE = "#2A2438"
HILL = "#5A4E68"
WATER_LINE = "#16344C"
WATER = "#24557A"
SHORE = "#8A7356"
PINE = "#1F6B3A"
HULL_LINE = "#3A2014"
HULL = "#8A4B2E"
SAIL_LINE = "#5C5348"
SAIL = "#F4EBDD"
MAST = "#4A3222"


def draw(seed):
    hand = Hand(seed, ORIGIN)
    # Near shore first, then the lake above it, then hills, then the two sky bands.
    # Each band is still empty when it is tapped, so one tap fills it.
    # The shore edge is the same colour as the shore. A darker line would be a third colour
    # inside each pine, and the two pine taps would leave it as a bar.
    hand.stroke(hand.curve([(-16, 348), (656, 349)]), SHORE)
    hand.fill((320, 420), SHORE)
    hand.stroke(hand.curve([(-16, 228), (656, 229)]), WATER_LINE)
    hand.fill((320, 290), WATER)
    ridge = [(-16, 228), (80, 156), (180, 198), (300, 132), (420, 188), (530, 148), (656, 228)]
    hand.stroke(hand.poly(ridge), RIDGE, jitter=0.5)
    hand.fill((300, 186), HILL)
    hand.stroke(hand.curve([(-16, 78), (656, 79)]), RIDGE)
    hand.fill((320, 108), GLOW)
    hand.fill((320, 28), DUSK)
    # The sun sits wholly in the sunset band, above the highest ridge under it.
    blob(hand, 500, 108, 16, SUN)

    # Hull and sail stay between the waterline (y=228) and the shore (y=348).
    hull = [(400, 292), (448, 292), (436, 310), (412, 310)]
    hand.stroke(hand.poly(hull, closed=True), HULL_LINE, closed=True, jitter=0.4)
    hand.fill((424, 301), HULL)
    sail = [(418, 258), (418, 290), (444, 290)]
    hand.stroke(hand.poly(sail, closed=True), SAIL_LINE, closed=True, jitter=0.4)
    hand.fill((428, 280), SAIL)
    hand.stroke(hand.poly([(418, 308), (418, 252)]), MAST, size=6)

    # Each pine covers water above the shore line and shore below it.
    for x, tip, base in ((72, 268, 436), (588, 286, 448)):
        tree = [(x - 46, base), (x, tip), (x + 46, base)]
        hand.stroke(hand.poly(tree, closed=True), PINE, closed=True, jitter=0.5)
        hand.fill((x, (tip + 348) / 2), PINE)
        hand.fill((x, (348 + base) / 2), PINE)
    return session(hand, DUSK)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "out" / "evening_lake"
    out.mkdir(parents=True, exist_ok=True)
    data = draw(1)
    (out / "session.json").write_text(json.dumps(data, sort_keys=True))
    scene = Scene(data)
    scene.run(data["ops"])
    svg = out / "drawing.svg"
    svg.write_text(scene.svg(flat=False))
    png = out / "evening_lake.png"
    subprocess.run(["rsvg-convert", "-w", "1280", "-h", "960", "-o", str(png), str(svg)], check=True)
    fills = sum(1 for op in data["ops"] if op["op"] == "fill")
    strokes = sum(1 for op in data["ops"] if op["op"] == "stroke")
    print(png, f"strokes {strokes} fills {fills} duration {data['duration']}")


if __name__ == "__main__":
    main()
