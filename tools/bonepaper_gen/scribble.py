"""A scary head-scribble: black pen strokes, solid in the core, clawed at the rim.

usage: .venv/bin/python scribble.py <out_dir> [seed]
       .venv/bin/python scribble.py <out_dir> anim [count] [fps]
"""
import json
import math
import random
import sys
from pathlib import Path

from hand import Hand
import replay

W, H = 800, 800
ORIGIN = (704, 784)
CX, CY = 400, 400
INK = "#000000"
PAPER = "#F4F1EA"


def session(hand):
    return {
        "version": 1, "started": "generated", "duration": round(hand.t, 3), "device": "hand.py",
        "screenScale": 2, "mode": "sheet", "worldSize": 2048, "sample": 2,
        "canvas": {"width": W, "height": H, "originX": ORIGIN[0], "originY": ORIGIN[1], "fixed": True},
        "final": {"width": W, "height": H, "extraLeft": 0, "extraTop": 0},
        "paper": PAPER, "ops": hand.ops,
    }


def keep(p):
    return (min(W - 18, max(18, p[0])), min(H - 18, max(18, p[1])))


def walk(hand, rng, leash, steps, size, wild, start):
    """One pen stroke. Past the leash it turns back, so the edge frays instead of growing whiskers."""
    ang = rng.uniform(0, math.tau)
    r = start()
    x = CX + math.cos(ang) * r
    y = CY + math.sin(ang) * r
    heading = rng.uniform(0, math.tau)
    pts = [(x, y)]
    for _ in range(steps):
        heading += rng.choice((-1, 1)) * rng.uniform(0.2, wild)
        step = rng.uniform(16, 36)
        x += math.cos(heading) * step
        y += math.sin(heading) * step
        dx, dy = x - CX, y - CY
        dist = math.hypot(dx, dy)
        if dist > leash:
            heading = math.atan2(-dy, -dx) + rng.uniform(-0.8, 0.8)
        x = min(W - 24, max(24, x))
        y = min(H - 24, max(24, y))
        pts.append((x, y))
    if math.dist(pts[0], pts[-1]) < 36:
        return
    hand.stroke(hand.curve(pts), INK, jitter=0.28, size=size)


def gash(hand, rng):
    """A long slash across the mass. Sharper than the wandering strokes."""
    heading = rng.uniform(0, math.tau)
    ang = rng.uniform(0, math.tau)
    r = abs(rng.gauss(0, 50))
    x = CX + math.cos(ang) * r
    y = CY + math.sin(ang) * r
    pts = [(x, y)]
    for _ in range(rng.randint(2, 3)):
        heading += rng.uniform(-0.55, 0.55)
        step = rng.uniform(80, 150)
        x += math.cos(heading) * step
        y += math.sin(heading) * step
        pts.append(keep((x, y)))
    if math.dist(pts[0], pts[-1]) < 50:
        return
    hand.stroke(hand.poly(pts), INK, jitter=0.12, size=rng.uniform(2.0, 2.8))


def draw(seed):
    rng = random.Random(seed)
    hand = Hand(seed, ORIGIN)
    near = lambda: abs(rng.gauss(0, 40))
    mid = lambda: abs(rng.gauss(0, 78))
    rim = lambda: rng.uniform(150, 210)
    for _ in range(90):
        walk(hand, rng, leash=128, steps=rng.randint(8, 12), size=rng.uniform(5.0, 6.6), wild=0.8, start=near)
    for _ in range(170):
        walk(hand, rng, leash=205, steps=rng.randint(8, 13), size=rng.uniform(2.0, 2.8), wild=0.55, start=mid)
    for _ in range(36):
        gash(hand, rng)
    for _ in range(55):
        walk(hand, rng, leash=268, steps=rng.randint(4, 7), size=rng.uniform(1.6, 2.2), wild=0.7, start=rim)
    return session(hand)


def frame(seed):
    image = replay.render(draw(seed))
    return image.resize((W, H), replay.Image.LANCZOS).convert("RGB")


def animate(out, count, fps):
    frames_dir = out / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    for i in range(count):
        image = frame(i + 1)
        image.save(frames_dir / f"{i:02d}.png")
        frames.append(image)
        print(frames_dir / f"{i:02d}.png", "seed", i + 1)
    # One palette for the whole loop, so the paper does not flicker between frames.
    strip = replay.Image.new("RGB", (W, H * count))
    for i, image in enumerate(frames):
        strip.paste(image, (0, i * H))
    palette = strip.quantize(colors=32)
    gif_frames = [image.quantize(palette=palette, dither=replay.Image.Dither.NONE) for image in frames]
    gif = out / "scribble.gif"
    gif_frames[0].save(
        gif, save_all=True, append_images=gif_frames[1:],
        duration=round(1000 / fps), loop=0, disposal=2,
    )
    print(gif, f"{count} frames at {fps} fps")


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 2 and sys.argv[2] == "anim":
        count = int(sys.argv[3]) if len(sys.argv) > 3 else 20
        fps = float(sys.argv[4]) if len(sys.argv) > 4 else 10
        animate(out, count, fps)
        return
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    data = draw(seed)
    (out / "session.json").write_text(json.dumps(data))
    image = replay.render(data)
    image.resize((W, H), replay.Image.LANCZOS).save(out / "scribble.png")
    print(out / "scribble.png", "strokes", sum(1 for op in data["ops"] if op["op"] == "stroke"))


if __name__ == "__main__":
    main()
