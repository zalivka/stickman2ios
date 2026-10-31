#!/usr/bin/env python3
"""Cartoon_269 variant: each beep is its own clip, spread across the timeline.

The last beep ends exactly when Android preview stops: 3104 ms.

    195 generated frames, preview ticks 16 ms  ->  (195-1) * 16 = 3104 ms
    clip on source frame f  ->  generated offset int(f * 13 * 1000/60)

Six clips on frames 0, 3, 6, 8, 11, 14 give the offsets below; the last one
gets a 71 ms beep so its trimmed audio ends on 3104 exactly.

    python3 tools/make_beeps_clips_scene.py
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
OUT = ROOT / "out/Cartoon_269_beeps_clips.ats"

SAMPLE_RATE = 22050
FPS = 60
KEYFRAMES = 16
INTERFRAMES = 12
GEN_FRAMES = (KEYFRAMES - 1) * (INTERFRAMES + 1)
PREVIEW_END_MS = (GEN_FRAMES - 1) * (1000 // FPS)  # (1000/60 int) = 16

BEEP_FREQS = [440.0, 550.0, 660.0, 770.0, 880.0, 990.0]
FRAMES = [0, 3, 6, 8, 11, 14]
BEEP_LEN_MS = 120


def offset_ms(frame_index: int) -> int:
    """StageAudio.toGeneratedOffsetMs: first generated frame of that span."""
    return int(frame_index * (INTERFRAMES + 1) * (1000.0 / FPS))


def bleep(path: Path, length_ms: int, freq: float) -> None:
    n = int(SAMPLE_RATE * length_ms / 1000)
    samples = []
    for i in range(n):
        env = math.sin(math.pi * i / n)
        samples.append(int(0.85 * 32767 * env * math.sin(2 * math.pi * freq * i / SAMPLE_RATE)))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(array.array("h", samples).tobytes())


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"missing source scene: {SRC}")

    build = ROOT / "out" / "clips_build"
    if build.exists():
        shutil.rmtree(build)
    build.mkdir(parents=True)

    clips = []
    palette = []
    for index, (frame, freq) in enumerate(zip(FRAMES, BEEP_FREQS)):
        offset = offset_ms(frame)
        is_last = index == len(FRAMES) - 1
        # last beep is trimmed to land exactly on the preview stop
        duration = PREVIEW_END_MS - offset if is_last else BEEP_LEN_MS
        if duration <= 0:
            raise SystemExit(f"frame {frame} starts at {offset} ms, past preview end")

        name = f"beep{index + 1}.wav"
        # file must be at least as long as the trim, or atrim would cut silently
        file_ms = max(duration, BEEP_LEN_MS)
        bleep(build / name, file_ms, freq)

        clips.append({
            "key": f"beep{index + 1}",
            "frameIndex": frame,
            "filename": name,
            "durationMs": duration,
            "colorIndex": index % 4,
            "volume": 1.0,
        })
        palette.append({"key": f"beep{index + 1}", "filename": name, "durationMs": file_ms})

        end = offset + duration
        mark = "  <-- exactly at preview end" if is_last else ""
        print(f"beep{index + 1}: frame {frame:2d}  offset {offset:5d} ms  "
              f"dur {duration:3d} ms  ends {end:5d} ms  {freq:.0f} Hz{mark}")

    with zipfile.ZipFile(SRC) as zf:
        entries = {info.filename: zf.read(info.filename) for info in zf.infolist()}

    for name in list(entries):
        if name.startswith("audio_v1/"):
            del entries[name]

    entries["audio_v1/dialogue.json"] = b"[]"
    entries["audio_v1/palette.json"] = json.dumps(palette, separators=(",", ":")).encode()
    entries["audio_v1/clips.json"] = json.dumps(clips, separators=(",", ":")).encode()
    for clip in clips:
        entries[f"audio_v1/{clip['filename']}"] = (build / clip["filename"]).read_bytes()

    meta = json.loads(entries["metadata.txt"])
    meta["speechUsed"] = False
    meta["mName"] = "Cartoon_269_beeps_clips"
    entries["metadata.txt"] = json.dumps(meta, separators=(",", ":")).encode()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, payload in entries.items():
            zf.writestr(name, payload)

    print(f"\npacked {OUT}")
    print(f"preview end {PREVIEW_END_MS} ms, picture end {int(GEN_FRAMES * 1000 / FPS)} ms")

    subprocess.run(["adb", "push", str(OUT), "/data/local/tmp/Cartoon_269_beeps_clips.ats"],
                   check=True, capture_output=True)
    subprocess.run(
        ["adb", "shell",
         "run-as com.zalivka.animation2 cp /data/local/tmp/Cartoon_269_beeps_clips.ats "
         "/data/data/com.zalivka.animation2/app_saved/Cartoon_269_beeps_clips.ats"],
        check=True, capture_output=True,
    )
    print("installed app_saved/Cartoon_269_beeps_clips.ats")


if __name__ == "__main__":
    main()
