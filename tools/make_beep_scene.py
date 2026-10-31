#!/usr/bin/env python3
"""Pack a beep-ruler scene for on-device measurement.

One scene, 16 keyframes / 12 interframes, exactly like Cartoon_269, so the
device reproduces the same 195 generated frames (3250 ms). The ruler is placed
on the FIRST frame so that it is audible from the start: whatever is missing at
the end of the playback is what the pipeline dropped.

    tools/make_beep_scene.py            # writes tools/out/beep_ruler.ats
"""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
BUILD = OUT / "beep_build"

W, H = 640, 480
BG = "#111111"
KEYFRAMES = 16
INTERFRAMES = 12
RULER_MS = 4000
BEEP_MS = 50
BEEP_STEP_MS = 100
SAMPLE_RATE = 22050


def write_ruler(path: Path) -> list[int]:
    import array
    import wave

    n = int(SAMPLE_RATE * RULER_MS / 1000)
    data = [0] * n
    times = list(range(BEEP_STEP_MS, RULER_MS + 1, BEEP_STEP_MS))
    for index, start_ms in enumerate(times):
        freq = 400.0 + 100.0 * (index // 5)  # pitch identifies the region
        start = int(SAMPLE_RATE * start_ms / 1000)
        length = int(SAMPLE_RATE * BEEP_MS / 1000)
        for i in range(length):
            if start + i >= n:
                break
            env = math.sin(math.pi * i / length)
            data[start + i] = int(18000 * env * math.sin(2 * math.pi * freq * i / SAMPLE_RATE))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(array.array("h", data).tobytes())
    return times


def unit_xml(name: str, arrange: int, x: float, y: float) -> str:
    return (
        f'<unit name="{name}" type="unit" flipped="false" arrange="{arrange}" '
        f'scale="1.0" alpha="1.0" state="0">'
        f'<point id="0" x="{x:.4f}" y="{y:.4f}" base="true" />'
        f'<point id="1" x="{x:.4f}" y="{y - 80:.4f}" par="0" />'
        f"</unit>"
    )


def build_model() -> str:
    pivots = [{"index": i, "speedValue": 1.0} for i in range(KEYFRAMES)]
    frames = []
    for i in range(KEYFRAMES):
        # slow drift so the picture visibly keeps moving to the last frame
        t = i / (KEYFRAMES - 1)
        x = 80.0 + 480.0 * t
        body = unit_xml("@:circle_red", 0, x, 120.0)
        body += unit_xml("@:circle_blue", 1, x, 300.0)
        frames.append(
            f'<frame id="{i}" bg="1.0 0.0 0.0 0.0" camera="1.0 0.0 0.0 0.0" '
            f'bg_name="{BG}">{body}</frame>'
        )
    return (
        "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
        f'<scene version_code="365" w="{W}" h="{H}" interframes="{INTERFRAMES}" '
        f'no_interpolation="false" no_interpolation_frames="0" '
        f"pivot_points='{json.dumps(pivots, separators=(',', ':'))}'>"
        + "".join(frames)
        + "</scene>\n"
    )


def build_item(build: Path, name: str, color: str) -> Path:
    """Minimal single-state .ati: 80x80 bitmap on a vertical bone."""
    item_dir = build / name
    item_dir.mkdir(parents=True, exist_ok=True)
    png = item_dir / "bm_1_state_0.png"
    subprocess.run(
        ["magick", "-size", "80x80", "xc:none", "-fill", color, "-draw",
         "circle 40,40 40,2", str(png)],
        check=True,
    )
    model = (
        "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
        f'<unit name="@:{name}"><point id="0" x="0.0" y="0.0" base="true" attachable="slave" />'
        f'<point id="1" x="0.0" y="-80.0" par="0" /></unit>'
    )
    assets = (
        "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
        f'<unit name="@:{name}" version="365"><edgeAsset start="0" end="1" '
        f'bm="bm_1_state_0.png" x_offset="-40.0" y_offset="-40.0" weight="1" state="0" /></unit>'
    )
    meta = json.dumps({
        "appVersion": 365, "author": "", "face_len": 0, "kinematicDefault": False,
        "multiframed": False, "name": name, "pack": "@", "scale": 1.0,
    }, separators=(",", ":"))

    ati = build / f"{name}.ati"
    with zipfile.ZipFile(ati, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("model.xml", model)
        zf.writestr("assets.xml", assets)
        zf.writestr("meta.txt", meta)
        zf.writestr(f"{name}.name", name)
        zf.write(png, "bm_1_state_0.png")
        zf.write(png, "thumb.png")
    return ati


def main() -> None:
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)

    (BUILD / "model.xml").write_text(build_model(), encoding="utf-8")
    (BUILD / "unit_tweens_v1.txt").write_text('{"spans":[]}', encoding="utf-8")

    build_item(BUILD, "circle_red", "#e04040")
    build_item(BUILD, "circle_blue", "#4060e0")

    ruler = BUILD / "beep_ruler.wav"
    times = write_ruler(ruler)

    meta = {
        "audioFormat": 1,
        "mAppName": "com.zalivka.animation2",
        "mAppVersion": "1-dev",
        "mAuthor": "<no author>",
        "mContentVersion": 0,
        "mCreatedAt": int(time.time() * 1000),
        "mName": "beep_ruler",
        "speechUsed": False,
    }
    (BUILD / "metadata.txt").write_text(json.dumps(meta, separators=(",", ":")), encoding="utf-8")

    audio_dir = BUILD / "audio_v1"
    audio_dir.mkdir(exist_ok=True)
    (audio_dir / "dialogue.json").write_text("[]", encoding="utf-8")
    (audio_dir / "palette.json").write_text(
        json.dumps([{"key": "beep_ruler", "filename": "beep_ruler.wav", "durationMs": RULER_MS}],
                   separators=(",", ":")),
        encoding="utf-8",
    )
    (audio_dir / "clips.json").write_text(
        json.dumps([{"key": "beep_ruler", "frameIndex": 0, "filename": "beep_ruler.wav",
                     "durationMs": RULER_MS, "colorIndex": 0, "volume": 1.0}],
                   separators=(",", ":")),
        encoding="utf-8",
    )

    OUT.mkdir(exist_ok=True)
    ats = OUT / "beep_ruler.ats"
    with zipfile.ZipFile(ats, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(BUILD / "model.xml", "model.xml")
        zf.write(BUILD / "metadata.txt", "metadata.txt")
        zf.write(BUILD / "unit_tweens_v1.txt", "unit_tweens_v1.txt")
        for ati in ("circle_red.ati", "circle_blue.ati"):
            zf.write(BUILD / ati, ati)
        zf.write(audio_dir / "dialogue.json", "audio_v1/dialogue.json")
        zf.write(audio_dir / "palette.json", "audio_v1/palette.json")
        zf.write(audio_dir / "clips.json", "audio_v1/clips.json")
        zf.write(ruler, "audio_v1/beep_ruler.wav")

    gen = (KEYFRAMES - 1) * (INTERFRAMES + 1)
    print(f"packed {ats}")
    print(f"keyframes={KEYFRAMES} interframes={INTERFRAMES} -> {gen} generated frames")
    print(f"picture ends {gen * 1000 / 60:.1f} ms")
    print(f"ruler {len(times)} beeps every {BEEP_STEP_MS} ms ({RULER_MS} ms total)")
    print("export audio -t =", f"{gen * 1000 / 60 + 1000:.0f} ms")
    print("expected preview loss (android):",
          f"{(gen - 1) * 16:.0f} ms cut -> last audible beep "
          f"{max(t for t in times if t < (gen - 1) * 16)} ms")


if __name__ == "__main__":
    main()
