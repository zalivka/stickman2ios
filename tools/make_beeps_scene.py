#!/usr/bin/env python3
"""Swap Cartoon_269's audio for a short pitch ladder, keeping the picture identical.

Six beeps, each a different pitch, all ending well before the point where
preview is *supposed* to stop (3104 ms for this 195-frame movie). Nothing here
should be truncated in preview: if a beep is missing on playback, that is the
bug. Export is expected to play all six too.

    python3 tools/make_beeps_scene.py
"""

from __future__ import annotations

import array
import json
import math
import shutil
import subprocess
import wave
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT.parent / "files/Cartoon_269.ats"
OUT = ROOT / "out/Cartoon_269_beeps.ats"

SAMPLE_RATE = 22050
BEEP_MS = 120
BASE_FREQ = 440.0
FREQ_STEP = 110.0

# Picture ends at 3250 ms; preview stops at 3104 ms. Keep every beep clear of
# both, with margin, so nothing is expected to be cut.
BEEP_TIMES_MS = [250, 750, 1250, 1750, 2250, 2750]
TOTAL_MS = 3300


def envelope(i: int, length: int) -> float:
    return math.sin(math.pi * i / length)


def build_beeps(path: Path) -> list[tuple[int, float]]:
    n = int(SAMPLE_RATE * TOTAL_MS / 1000)
    data = [0.0] * n
    beeps: list[tuple[int, float]] = []

    for index, at_ms in enumerate(BEEP_TIMES_MS):
        freq = BASE_FREQ + index * FREQ_STEP
        start = int(SAMPLE_RATE * at_ms / 1000)
        length = int(SAMPLE_RATE * BEEP_MS / 1000)
        for i in range(length):
            if start + i < n:
                data[start + i] += envelope(i, length) * math.sin(
                    2 * math.pi * freq * i / SAMPLE_RATE
                )
        beeps.append((at_ms, freq))

    peak = max(abs(v) for v in data) or 1.0
    scale = 0.85 * 32767 / peak
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(array.array("h", [int(v * scale) for v in data]).tobytes())
    return beeps


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"missing source scene: {SRC}")

    build = ROOT / "out" / "beeps_build"
    if build.exists():
        shutil.rmtree(build)
    build.mkdir(parents=True)

    beeps_file = build / "beeps.wav"
    beeps = build_beeps(beeps_file)

    with zipfile.ZipFile(SRC) as zf:
        entries = {info.filename: zf.read(info.filename) for info in zf.infolist()}

    for name in list(entries):
        if name.startswith("audio_v1/"):
            del entries[name]

    entries["audio_v1/beeps.wav"] = beeps_file.read_bytes()
    entries["audio_v1/dialogue.json"] = b"[]"
    entries["audio_v1/palette.json"] = json.dumps(
        [{"key": "beeps", "filename": "beeps.wav", "durationMs": TOTAL_MS}],
        separators=(",", ":"),
    ).encode()
    entries["audio_v1/clips.json"] = json.dumps(
        [{"key": "beeps", "frameIndex": 0, "filename": "beeps.wav",
          "durationMs": TOTAL_MS, "colorIndex": 0, "volume": 1.0}],
        separators=(",", ":"),
    ).encode()

    meta = json.loads(entries["metadata.txt"])
    meta["speechUsed"] = False
    meta["mName"] = "Cartoon_269_beeps"
    entries["metadata.txt"] = json.dumps(meta, separators=(",", ":")).encode()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, payload in entries.items():
            zf.writestr(name, payload)

    print(f"packed {OUT}")
    print(f"  {len(beeps)} beeps, {BEEP_MS} ms each, total audio {TOTAL_MS} ms")
    print(f"  picture ends 3250 ms | preview stops 3104 ms | every beep below both")
    for at_ms, freq in beeps:
        print(f"    {at_ms:5d} ms  {freq:6.0f} Hz")

    subprocess.run(["adb", "push", str(OUT), "/sdcard/Download/Cartoon_269_beeps.ats"],
                   check=True, capture_output=True)
    subprocess.run(["adb", "push", str(OUT), "/data/local/tmp/Cartoon_269_beeps.ats"],
                   check=True, capture_output=True)
    subprocess.run(
        ["adb", "shell",
         "run-as com.zalivka.animation2 cp /data/local/tmp/Cartoon_269_beeps.ats "
         "/data/data/com.zalivka.animation2/app_saved/Cartoon_269_beeps.ats"],
        check=True, capture_output=True,
    )
    print("installed app_saved/Cartoon_269_beeps.ats")


if __name__ == "__main__":
    main()
