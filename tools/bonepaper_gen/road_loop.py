"""Ten-frame loop of the desert road driving toward the camera.

The sky, sun, sand, grey road and both mesas are drawn once. The mesas sit on
the horizon and do not move; the right one is tall enough that the sun stays
behind it. Yellow dashes march down the centre of the road and wrap. A stone
on the left shoulder and the cactus are each drawn twice: one copy leaves the
edge while its twin comes in small at the horizon, so frame 10 matches frame 0.
"""

import math
import subprocess
from pathlib import Path

from cartoons import ORIGIN, Hand, band, blob, session
from cartoons2 import CACTUS, DASH, MESA, ROAD, SAND, SKY, SUN
from svg_export import Scene

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "at_elements" / "testdata" / "road"
SCRATCH = Path(__file__).resolve().parent / "out" / "road"
FRAMES = 10
STONE = "#8A6244"
SHADE = "#7A341C"
VANISH = (320, 224)
RASTER = (1280, 960)


def inner(hand, paper=None):
    sess = session(hand, paper)
    scene = Scene(sess)
    scene.run(sess["ops"])
    text = scene.svg(flat=False)
    lines = text.splitlines()
    body = lines[1:-1]
    if paper is not None and body and body[0].lstrip().startswith("<rect"):
        body = body[1:]
    return "\n".join(body)


def ground():
    hand = Hand(1, ORIGIN)
    band(hand, 222, SAND, (320, 300))
    road = [(300, 224), (340, 224), (560, 490), (80, 490)]
    hand.stroke(hand.poly(road, closed=True), ROAD, closed=True, jitter=0.45)
    hand.fill((320, 380), ROAD)
    return inner(hand, SKY)


def sun():
    hand = Hand(1, ORIGIN)
    blob(hand, 560, 70, 30, SUN)
    return inner(hand)


def mesa_right():
    hand = Hand(2, ORIGIN)
    shape = [(430, 222), (462, 36), (598, 36), (630, 222)]
    hand.stroke(hand.poly(shape, closed=True), MESA, closed=True, jitter=0.45)
    hand.stroke(hand.poly([(548, 36), (586, 222)]), MESA, jitter=0.35)
    hand.fill((500, 140), MESA)
    hand.fill((600, 130), SHADE)
    return inner(hand)


def mesa_left():
    hand = Hand(5, ORIGIN)
    shape = [(18, 222), (72, 96), (128, 140), (188, 48), (248, 222)]
    hand.stroke(hand.poly(shape, closed=True), MESA, closed=True, jitter=0.5)
    hand.stroke(hand.poly([(188, 48), (168, 222)]), MESA, jitter=0.35)
    hand.fill((90, 185), MESA)
    hand.fill((210, 155), SHADE)
    return inner(hand)


def stone():
    hand = Hand(3, ORIGIN)
    shape = [(100, 360), (118, 328), (156, 332), (172, 358), (148, 392), (112, 388)]
    hand.stroke(hand.poly(shape, closed=True), STONE, closed=True, jitter=0.5)
    hand.fill((136, 360), STONE)
    return inner(hand)


def cactus():
    hand = Hand(4, ORIGIN)
    hand.stroke(hand.poly([(600, 344), (600, 256)]), CACTUS, size=18)
    hand.stroke(hand.poly([(600, 300), (624, 300), (624, 272)]), CACTUS, size=14)
    hand.stroke(hand.poly([(600, 318), (578, 318), (578, 292)]), CACTUS, size=14)
    return inner(hand)


def radial(markup, scale):
    vx, vy = VANISH
    return (
        f'<g transform="translate({vx},{vy}) scale({scale:.4f}) translate({-vx},{-vy})">'
        f"{markup}</g>"
    )


def dashes(phase):
    parts = []
    for i in range(4):
        u = (i / 4 + phase) % 1
        y0 = 230 + 300 * (u ** 1.2)
        length = 7 + 34 * (u ** 1.1)
        y1 = y0 + length
        width = 3.5 + 6 * u
        x0 = 320 + 1.6 * math.sin(y0 * 0.09)
        x1 = 320 + 1.6 * math.sin(y1 * 0.09 + 0.4)
        parts.append(
            f'<polyline points="{x0:.1f},{y0:.1f} {x1:.1f},{y1:.1f}" fill="none" '
            f'stroke="{DASH}" stroke-width="{width:.2f}" stroke-linecap="round"/>'
        )
    return "\n".join(parts)


def placed(markup, far, near, phase):
    chunks = []
    for shift in (0.0, 0.5):
        s = (phase + shift) % 1
        chunks.append(radial(markup, far + (near - far) * s))
    return "\n".join(chunks)


def frame_svg(index, ground_svg, sun_svg, left_svg, right_svg, stone_svg, cactus_svg):
    # One dash slot per loop. The stone and cactus sit half a cycle apart;
    # one loop is that half cycle, so the twin arrives where the first one started.
    dash_phase = index / FRAMES * 0.25
    prop_phase = index / FRAMES * 0.5
    chunks = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480" viewBox="0 0 640 480">',
        f'<rect width="640" height="480" fill="{SKY}"/>',
        ground_svg,
        sun_svg,
        left_svg,
        right_svg,
        dashes(dash_phase),
        placed(stone_svg, 0.18, 2.55, prop_phase),
        placed(cactus_svg, 0.18, 1.72, prop_phase),
        "</svg>",
    ]
    return "\n".join(chunks) + "\n"


def raster(svg_path, png_path):
    subprocess.run(
        ["rsvg-convert", "-w", str(RASTER[0]), "-h", str(RASTER[1]), "-o", str(png_path), str(svg_path)],
        check=True,
    )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    plate = ground()
    sun_svg = sun()
    stone_svg = stone()
    cactus_svg = cactus()
    left_svg = mesa_left()
    right_svg = mesa_right()
    pngs = []
    for i in range(FRAMES):
        svg_path = SCRATCH / f"frame_{i}.svg"
        png_path = OUT / f"frame_{i}.png"
        svg_path.write_text(frame_svg(i, plate, sun_svg, left_svg, right_svg, stone_svg, cactus_svg))
        raster(svg_path, png_path)
        pngs.append(png_path)
        print(png_path)
    contact(pngs)


def contact(pngs):
    from PIL import Image

    tile_w, tile_h = 256, 192
    cols = 5
    rows = (len(pngs) + cols - 1) // cols
    sheet = Image.new("RGB", (tile_w * cols, tile_h * rows), (158, 216, 255))
    for i, path in enumerate(pngs):
        im = Image.open(path).convert("RGB").resize((tile_w, tile_h), Image.Resampling.LANCZOS)
        sheet.paste(im, ((i % cols) * tile_w, (i // cols) * tile_h))
    out = SCRATCH / "contact.png"
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
