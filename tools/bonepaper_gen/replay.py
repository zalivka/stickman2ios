"""Approximate BonePaper replay of a session.json (Pillow). Strokes and fills match closely; the fill is simpler than BonePaper's.

usage: python3.12 replay.py <session_dir> [out.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def render(session: dict) -> Image.Image:
    c = session["canvas"]
    s = session["sample"]
    w, h = c["width"] * s, c["height"] * s
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    def px(p):
        return ((p[0] - c["originX"]) * s, (p[1] - c["originY"]) * s)

    for op in session["ops"]:
        kind = op["op"]
        if kind == "stroke":
            if op["end"] != "commit":
                continue
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            width = op["size"] * s
            color = "#000000" if op["erase"] else op["color"]
            pts = [px(p) for p in op["points"]]
            if len(pts) > 1:
                d.line(pts, fill=color, width=round(width), joint="curve")
            r = width / 2
            for x, y in pts:
                d.ellipse([x - r, y - r, x + r, y + r], fill=color)
            if op["erase"]:
                mask = layer.getchannel("A")
                ink.paste((0, 0, 0, 0), mask=mask)
            else:
                alpha = layer.getchannel("A").point(lambda v: round(v * op["opacity"]))
                layer.putalpha(alpha)
                ink.alpha_composite(layer)
        elif kind == "fill":
            rgb = Image.new("RGBA", (1, 1), op["color"]).getpixel((0, 0))
            color = (rgb[0], rgb[1], rgb[2], round(255 * op["opacity"]))
            x, y = px(op["at"])
            ImageDraw.floodfill(ink, (int(x), int(y)), color, thresh=60)
        elif kind in ("noop",):
            continue
        else:
            raise SystemExit(f"replay: unsupported op {kind}")

    if session.get("paper"):
        page = Image.new("RGBA", (w, h), session["paper"])
        page.alpha_composite(ink)
        return page
    return ink


def main():
    src = Path(sys.argv[1])
    session = json.loads((src / "session.json").read_text())
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else src / "replay.png"
    image = render(session)
    s = session["sample"]
    image.resize((image.width // s, image.height // s), Image.LANCZOS).save(out)
    print(out)


if __name__ == "__main__":
    main()
