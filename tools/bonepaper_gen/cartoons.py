"""Five cartoon backgrounds. The lower middle of each stays empty.

usage: python3.12 cartoons.py <out_dir> [seed]
"""
import json
import math
import sys
from pathlib import Path

from hand import Hand
import replay

W, H = 640, 480
ORIGIN = (704, 784)

WALL = "#F3E2CC"
FLOOR_K = "#C9A36A"
TABLE = "#8C6E63"
PLATE = "#FFFFFF"
CUP = "#1F87E6"
WIN = "#9ED8FF"
FRAME = "#6B4A32"
SUN = "#FCD936"
SKY = "#9ED8FF"
GRASS = "#5DBB3F"
SCHOOL = "#E7D7BE"
ROOF = "#E63836"
DOOR = "#8C6E63"
PINE = "#1F6B3A"
TRUNK = "#8C6E63"
SEA = "#1F6B9A"
DECK = "#C4A06A"
RAIL = "#5C4030"
SAIL = "#FFFFFF"
HALL = "#E4EAF0"
TILE = "#C5CED6"
HDOOR = "#3D7A4A"
SIGN = "#E63836"
NIGHT = "#121624"
CAMP = "#3A5A38"
TENT = "#E24B3A"
FIRE = "#F6D56A"
MOON = "#E4E0D2"
LOG = "#6E4B32"


def session(hand, paper):
    return {
        "version": 1, "started": "generated", "duration": round(hand.t, 3), "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": W, "height": H, "originX": ORIGIN[0], "originY": ORIGIN[1], "fixed": True},
        "final": {"width": W, "height": H, "extraLeft": 0, "extraTop": 0},
        "paper": paper, "ops": hand.ops,
    }


def band(hand, y, color, tap):
    hand.stroke(hand.curve([(-16, y), (656, y + 1)]), color)
    hand.fill(tap, color)


def box(hand, x0, top, x1, bottom, color, jitter=0.55):
    keys = [(x0, bottom), (x0, top), (x1, top), (x1, bottom)]
    hand.stroke(hand.poly(keys, closed=True), color, closed=True, jitter=jitter)
    hand.fill(((x0 + x1) / 2, (top + bottom) / 2), color)


def blob(hand, cx, cy, r, color, n=8):
    keys = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in (i * 2 * math.pi / n for i in range(n))]
    hand.stroke(hand.curve(keys, closed=True), color, closed=True, jitter=0.45)
    hand.fill((cx, cy - r * 0.2), color)


def kitchen(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 300, FLOOR_K, (320, 420))
    box(hand, 70, 188, 570, 312, TABLE)
    box(hand, 36, 28, 196, 168, FRAME, jitter=0.4)
    hand.fill((110, 90), WIN)
    blob(hand, 150, 78, 26, SUN)
    blob(hand, 200, 248, 36, PLATE)
    box(hand, 300, 214, 348, 276, CUP, jitter=0.4)
    hand.stroke(hand.poly([(312, 214), (308, 196)]), CUP)
    hand.fill((400, 80), WALL)
    return session(hand, WALL)


def schoolyard(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 268, GRASS, (320, 400))
    box(hand, 28, 78, 250, 274, SCHOOL)
    roof = [(16, 86), (140, 16), (264, 86)]
    hand.stroke(hand.poly(roof, closed=True), ROOF, closed=True, jitter=0.5)
    hand.fill((140, 60), ROOF)
    box(hand, 108, 168, 168, 274, DOOR, jitter=0.4)
    for x, y in ((52, 120), (188, 120), (52, 180), (188, 180)):
        hand.stroke(hand.poly([(x, y), (x + 22, y + 1)]), WIN)
    crown = [(518, 40), (430, 210), (606, 210)]
    hand.stroke(hand.poly(crown, closed=True), PINE, closed=True, jitter=0.55)
    hand.fill((518, 150), PINE)
    box(hand, 500, 206, 536, 274, TRUNK, jitter=0.4)
    hand.fill((380, 36), SKY)
    return session(hand, SKY)


def ship(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 168, SEA, (320, 200))
    band(hand, 248, DECK, (320, 400))
    hand.stroke(hand.poly([(70, 248), (70, -8)]), RAIL)
    hand.stroke(hand.poly([(40, 248), (100, 248)]), RAIL)
    sail = [(78, 36), (78, 200), (210, 130)]
    hand.stroke(hand.poly(sail, closed=True), SAIL, closed=True, jitter=0.5)
    hand.fill((120, 120), SAIL)
    flag = [(70, 8), (118, 22), (70, 40)]
    hand.stroke(hand.poly(flag, closed=True), ROOF, closed=True, jitter=0.4)
    hand.fill((90, 22), ROOF)
    for x in (200, 320, 460, 600):
        hand.stroke(hand.poly([(x, 248), (x, 292)]), RAIL)
    hand.stroke(hand.curve([(40, 292), (660, 294)]), RAIL)
    hand.fill((500, 40), SKY)
    return session(hand, SKY)


def hospital(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 250, TILE, (320, 400))
    for x0 in (36, 470):
        box(hand, x0, 70, x0 + 120, 256, HDOOR, jitter=0.45)
        hand.stroke(hand.poly([(x0 + 96, 170), (x0 + 108, 172)]), SUN)
    box(hand, 250, 28, 390, 78, SIGN, jitter=0.4)
    hand.stroke(hand.poly([(308, 40), (332, 42)]), PLATE)
    hand.stroke(hand.poly([(318, 28), (320, 64)]), PLATE)
    hand.fill((180, 40), HALL)
    return session(hand, HALL)


def campsite(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 286, CAMP, (320, 420))
    tent = [(24, 292), (150, 150), (276, 292)]
    hand.stroke(hand.poly(tent, closed=True), TENT, closed=True, jitter=0.5)
    hand.fill((150, 230), TENT)
    hand.stroke(hand.poly([(150, 292), (150, 168)]), FRAME)
    for x, top in ((40, 70), (560, 40)):
        hand.stroke(hand.poly([(x, 292), (x, top), (x + 70, 292)], closed=True), PINE, closed=True, jitter=0.5)
        hand.fill((x + 24, 200), PINE)
    blob(hand, 500, 300, 22, FIRE, n=7)
    hand.stroke(hand.poly([(470, 330), (530, 318)]), LOG)
    hand.stroke(hand.poly([(476, 346), (528, 338)]), LOG)
    blob(hand, 330, 78, 26, MOON, n=8)
    hand.fill((330, 24), NIGHT)
    return session(hand, NIGHT)


SCENES = [
    ("kitchen", kitchen),
    ("schoolyard", schoolyard),
    ("ship", ship),
    ("hospital", hospital),
    ("campsite", campsite),
]


def main():
    out = Path(sys.argv[1])
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    for name, draw in SCENES:
        folder = out / name
        folder.mkdir(parents=True, exist_ok=True)
        data = draw(seed)
        (folder / "session.json").write_text(json.dumps(data, sort_keys=True))
        image = replay.render(data)
        image.resize((W, H), replay.Image.LANCZOS).save(folder / "replay.png")
        strokes = sum(1 for op in data["ops"] if op["op"] == "stroke")
        fills = sum(1 for op in data["ops"] if op["op"] == "fill")
        print(name, f"strokes {strokes} fills {fills}")


if __name__ == "__main__":
    main()
