"""Five more cartoon backgrounds. The lower middle of each stays empty.

usage: python3.12 cartoons2.py <out_dir> [seed]
"""
import json
import sys
from pathlib import Path

from hand import Hand
import replay
from cartoons import ORIGIN, W, H, session, band, box, blob

WALL = "#F3E2CC"
FLOOR = "#C9A36A"
FRAME = "#6B4A32"
BOARD = "#2F5D46"
CHALK = "#FFFFFF"
DESK = "#8C6E63"
WIN = "#9ED8FF"
CLOCK = "#FFFFFF"
INK = "#2B2B2B"
SKY = "#9ED8FF"
SUN = "#FCD936"
SAND = "#E8C07A"
ROAD = "#6E6E73"
DASH = "#FCD936"
MESA = "#C0643A"
CANOPY = "#E63836"
PUMP = "#1F87E6"
CACTUS = "#3E8E3A"
STORE = "#F2F0E8"
SHELF = "#D9D2C5"
TILE = "#C5CED6"
SALE = "#E63836"
LAMP = "#FCD936"
GOODS = ["#E63836", "#FCD936", "#1F87E6", "#5DBB3F", "#F28C28", "#B05BD6"]
WINTER = "#BFD9EE"
SNOW = "#F7FAFC"
ROCK = "#9FB0C4"
HUT = "#A0673F"
PINE = "#1F6B3A"
SMOKE = "#A8ADB3"
SNOWLINE = "#4E5D73"
CARROT = "#F28C28"
DEEP = "#1B4F80"
WATER = "#2F7FB8"
SEABED = "#E6CF94"
RAY = "#6FB4E0"
WRECK = "#2A4A60"
CORAL = "#F06A8A"
CORAL2 = "#F28C28"
WEED = "#3E9E4A"
CHEST = "#8C5A32"
GOLD = "#FCD936"
BUBBLE = "#DDF1FF"


def classroom(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 340, FLOOR, (320, 420))
    box(hand, 170, 40, 470, 190, FRAME, jitter=0.4)
    hand.fill((320, 115), BOARD)
    hand.stroke(hand.curve([(200, 80), (230, 68), (262, 86), (292, 70)]), CHALK, size=6)
    hand.stroke(hand.poly([(210, 120), (250, 120)]), CHALK, size=6)
    hand.stroke(hand.poly([(230, 104), (230, 138)]), CHALK, size=6)
    hand.stroke(hand.poly([(280, 116), (310, 116)]), CHALK, size=6)
    hand.stroke(hand.poly([(280, 128), (310, 128)]), CHALK, size=6)
    hand.stroke(hand.curve([(340, 150), (380, 140), (420, 156), (444, 146)]), CHALK, size=6)
    box(hand, 30, 50, 130, 190, FRAME, jitter=0.4)
    hand.fill((80, 120), WIN)
    hand.stroke(hand.poly([(80, 56), (80, 184)]), FRAME, size=8)
    blob(hand, 560, 78, 30, CLOCK)
    hand.stroke(hand.poly([(560, 80), (560, 60)]), INK, size=5)
    hand.stroke(hand.poly([(560, 80), (576, 88)]), INK, size=5)
    box(hand, 16, 240, 176, 336, DESK)
    box(hand, 520, 270, 660, 336, DESK)
    hand.fill((320, 270), WALL)
    return session(hand, WALL)


def desert(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 222, SAND, (320, 300))
    road = [(300, 224), (340, 224), (560, 490), (80, 490)]
    hand.stroke(hand.poly(road, closed=True), ROAD, closed=True, jitter=0.45)
    hand.fill((320, 380), ROAD)
    for top, bottom in ((248, 262), (296, 318), (362, 394), (440, 478)):
        hand.stroke(hand.poly([(320, top), (321, bottom)]), DASH, size=8)
    mesa = [(430, 222), (462, 150), (598, 150), (630, 222)]
    hand.stroke(hand.poly(mesa, closed=True), MESA, closed=True, jitter=0.45)
    hand.fill((530, 188), MESA)
    blob(hand, 560, 70, 30, SUN)
    box(hand, 20, 104, 220, 144, CANOPY, jitter=0.4)
    for x in (50, 190):
        hand.stroke(hand.poly([(x, 144), (x, 300)]), FRAME)
    box(hand, 100, 232, 140, 300, PUMP, jitter=0.4)
    hand.stroke(hand.poly([(600, 344), (600, 256)]), CACTUS, size=18)
    hand.stroke(hand.poly([(600, 300), (624, 300), (624, 272)]), CACTUS, size=14)
    hand.stroke(hand.poly([(600, 318), (578, 318), (578, 292)]), CACTUS, size=14)
    hand.fill((320, 60), SKY)
    return session(hand, SKY)


def _shelf(hand, near, far):
    """Perspective shelf: outer edge at x=near spans y 20..400, back edge at x=far spans 150..250."""
    def top(x):
        return 20 + (x - near) * 130 / (far - near)

    def bottom(x):
        return 400 - (x - near) * 150 / (far - near)

    outline = [(near, 20), (far, 150), (far, 250), (near, 400)]
    hand.stroke(hand.poly(outline, closed=True), FRAME, closed=True, jitter=0.4)
    for f in (1 / 3, 2 / 3):
        a = (near, top(near) + f * (bottom(near) - top(near)))
        b = (far, top(far) + f * (bottom(far) - top(far)))
        hand.stroke(hand.poly([a, b]), FRAME)
    cuts = [near + (far - near) * k for k in (0.3, 0.55, 0.78)]
    for x in cuts:
        hand.stroke(hand.poly([(x, top(x)), (x, bottom(x))]), FRAME)
    edges = [near] + cuts + [far]
    for col in range(4):
        x = (edges[col] + edges[col + 1]) / 2
        for row in range(3):
            f = (row + 0.5) / 3
            y = top(x) + f * (bottom(x) - top(x))
            hand.fill((x, y), GOODS[(col * 3 + row + (near > far)) % len(GOODS)])


def supermarket(seed):
    hand = Hand(seed, ORIGIN)
    _shelf(hand, -10, 250)
    _shelf(hand, 650, 390)
    hand.stroke(hand.poly([(250, 250), (390, 250)]), FRAME)
    hand.fill((320, 420), TILE)
    box(hand, 272, 164, 368, 206, SALE, jitter=0.4)
    hand.stroke(hand.curve([(290, 178), (306, 190), (322, 178), (338, 190), (352, 180)]), CHALK, size=6)
    for x in (160, 320, 480):
        hand.stroke(hand.poly([(x - 30, 22), (x + 30, 22)]), LAMP, size=10)
    hand.fill((320, 80), STORE)
    return session(hand, STORE)


def _snowman(hand, cx, cy, r):
    for y, radius in ((cy, r), (cy - r - r * 0.62, r * 0.66)):
        keys = [(cx + radius * c, y + radius * s) for c, s in
                ((1, 0), (0.7, 0.7), (0, 1), (-0.7, 0.7), (-1, 0), (-0.7, -0.7), (0, -1), (0.7, -0.7))]
        hand.stroke(hand.curve(keys, closed=True), SNOWLINE, closed=True, jitter=0.4, size=6)
    hand.stroke(hand.poly([(cx, cy - r * 1.62), (cx + 16, cy - r * 1.56)]), CARROT, size=6)


def village(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 300, SNOW, (320, 420))
    ridge = [(-16, 230), (90, 90), (190, 200), (300, 60), (420, 210), (520, 100), (660, 230)]
    hand.stroke(hand.poly(ridge), SNOWLINE, jitter=0.5)
    for x0, top, x1, peak in ((60, 234, 170, 180), (204, 250, 290, 208)):
        box(hand, x0, top, x1, 300, HUT, jitter=0.4)
        roof = [(x0 - 12, top + 6), ((x0 + x1) / 2, peak), (x1 + 12, top + 6)]
        hand.stroke(hand.poly(roof, closed=True), SNOWLINE, closed=True, jitter=0.4)
        hand.fill(((x0 + x1) / 2, (peak + top) / 2 + 6), SNOW)
        hand.stroke(hand.poly([(x0 + 22, top + 30), (x0 + 36, top + 31)]), SUN, size=10)
    hand.fill((300, 200), ROCK)
    for (lx, rx), y, peak in (((45, 140), 130, (90, 115)), ((255, 345), 100, (300, 84)), ((470, 578), 140, (520, 124))):
        hand.stroke(hand.poly([(lx, y), (rx, y + 1)]), SNOWLINE)
        hand.fill(peak, SNOW)
    for x in (470, 540):
        tree = [(x - 36, 340), (x, 232), (x + 36, 340)]
        hand.stroke(hand.poly(tree, closed=True), PINE, closed=True, jitter=0.5)
        hand.fill((x, 310), PINE)
    _snowman(hand, 610, 350, 22)
    hand.stroke(hand.curve([(150, 180), (140, 160), (156, 140), (144, 118), (158, 96)]), SMOKE, size=10)
    hand.fill((320, 30), WINTER)
    return session(hand, WINTER)


def seabed(seed):
    hand = Hand(seed, ORIGIN)
    band(hand, 340, SEABED, (320, 420))
    band(hand, 120, DEEP, (320, 40))
    hull = [(380, 340), (398, 290), (562, 290), (544, 340)]
    hand.stroke(hand.poly(hull, closed=True), WRECK, closed=True, jitter=0.45)
    hand.fill((470, 316), WRECK)
    hand.stroke(hand.poly([(470, 290), (474, 206)]), WRECK, size=10)
    hand.stroke(hand.poly([(430, 236), (512, 232)]), WRECK, size=8)
    blob(hand, 70, 300, 28, CORAL)
    blob(hand, 130, 312, 20, CORAL2, n=7)
    for keys in (
        [(200, 344), (188, 300), (208, 262), (194, 222)],
        [(232, 344), (244, 306), (226, 270), (240, 240)],
        [(596, 344), (584, 298), (604, 256), (590, 214)],
        [(622, 344), (634, 304), (616, 272)],
    ):
        hand.stroke(hand.curve(keys), WEED, size=12)
    box(hand, 560, 356, 630, 400, CHEST, jitter=0.4)
    hand.stroke(hand.poly([(566, 372), (624, 372)]), GOLD, size=8)
    hand.fill((320, 220), WATER)
    for x0 in (120, 280, 440):
        hand.stroke(hand.poly([(x0, -8), (x0 + 70, 200)]), RAY, size=10)
    for x, y, r in ((150, 250, 12), (162, 214, 10), (150, 182, 8), (500, 170, 11), (512, 138, 8)):
        hand.stroke(hand.curve([(x + r, y), (x, y + r), (x - r, y), (x, y - r)], closed=True), BUBBLE, closed=True, size=4)
    return session(hand, WATER)


SCENES = [
    ("classroom", classroom),
    ("desert", desert),
    ("supermarket", supermarket),
    ("village", village),
    ("seabed", seabed),
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
