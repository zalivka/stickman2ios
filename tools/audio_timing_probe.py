#!/usr/bin/env python3
"""Measure what the exported video does to audio at the end of a scene.

Builds a synthetic "beep ruler" (one beep every 100 ms) and runs the *exact*
ffmpeg chains from:

  Android  StageAudio.mergeClips / AudioMerger.mergeTimedFiles
  Android  FramesGeneratorService.buildFFmpegCommand
  iOS      AudioMerger.makeArguments / JpegVideoAssembler.assemble

Then decodes the produced file and reports, beep by beep, what survived, so
preview and export can be compared against the same ruler.

Usage:
    python3 audio_timing_probe.py --scene <path.ats> [--work DIR] [--keep]
    python3 audio_timing_probe.py --keyframes 16 --interframes 12
"""

from __future__ import annotations

import argparse
import array
import json
import math
import re
import shutil
import subprocess
import sys
import wave
import zipfile
from pathlib import Path

FPS = 60
ANDROID_PREVIEW_TICK_MS = 1000 // FPS  # MoviePlayerUseCase: int division -> 16
SAMPLE_RATE = 22050
BEEP_MS = 50
BEEP_STEP_MS = 100
RULER_MS = 4000  # how much of the ruler we place on the timeline


# --------------------------------------------------------------------------
# scene arithmetic (mirrors Scene / ThriftMovieGeneratorUseCase / SceneAudioTimeline)
# --------------------------------------------------------------------------

def read_scene(path: Path) -> tuple[int, int, bool]:
    with zipfile.ZipFile(path) as zf:
        model = zf.read("model.xml").decode("utf-8")
    scene_tag = re.search(r"<scene\b([^>]*)>", model)
    if scene_tag is None:
        raise SystemExit(f"no <scene> in {path}")
    attrs = scene_tag.group(1)
    interframes = int(re.search(r'interframes="(\d+)"', attrs).group(1))
    no_interp = re.search(r'no_interpolation="(true|false)"', attrs).group(1) == "true"
    if no_interp:
        interframes = int(re.search(r'no_interpolation_frames="(\d+)"', attrs).group(1))
    keyframes = len(re.findall(r"<frame\b", model))
    return keyframes, interframes, no_interp


def parse_clips(raw: str) -> list[tuple[int, int]]:
    if not raw.strip():
        return []
    out = []
    for item in raw.split(","):
        parts = item.split(":")
        if len(parts) == 1:
            out.append((int(parts[0]), 1000))
        elif len(parts) == 2:
            out.append((int(parts[0]), int(parts[1])))
        else:
            raise SystemExit(f"bad --clips entry: {item}")
    return out


def generated_frame_count(keyframes: int, interframes: int) -> int:
    """ConstantLengthInterpolator emits `duration` frames + the f2 clone per span."""
    return (keyframes - 1) * (interframes + 1)


def frame_ms() -> float:
    return 1000.0 / FPS


# --------------------------------------------------------------------------
# synthetic audio
# --------------------------------------------------------------------------

def write_wav(path: Path, samples: list[int]) -> None:
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(array.array("h", samples).tobytes())


def beep_schedule(total_ms: int) -> list[int]:
    return list(range(BEEP_STEP_MS, total_ms + 1, BEEP_STEP_MS))


def build_ruler(path: Path, total_ms: int) -> list[int]:
    """One 50 ms beep every 100 ms. Frequency steps every 500 ms so a
    spectrogram (and the ear) can identify a beep by its pitch."""
    n = int(SAMPLE_RATE * total_ms / 1000)
    data = [0] * n
    times = beep_schedule(total_ms)
    for index, start_ms in enumerate(times):
        freq = 400.0 + 100.0 * (index // 5)
        start = int(SAMPLE_RATE * start_ms / 1000)
        length = int(SAMPLE_RATE * BEEP_MS / 1000)
        for i in range(length):
            if start + i >= n:
                break
            env = math.sin(math.pi * i / length)  # soft edges, no clicks
            data[start + i] = int(18000 * env * math.sin(2 * math.pi * freq * i / SAMPLE_RATE))
    write_wav(path, data)
    return times


def decode_to_wav(source: Path, target: Path) -> None:
    run([
        "ffmpeg", "-v", "error", "-y", "-i", str(source),
        "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", str(target),
    ])


def detect_beeps(path: Path) -> list[tuple[int, int]]:
    """Return [(start_ms, peak)] for each 10 ms window above threshold."""
    with wave.open(str(path), "rb") as wf:
        if wf.getsampwidth() != 2 or wf.getnchannels() != 1:
            raise SystemExit("decode_to_wav must produce mono s16")
        rate = wf.getframerate()
        raw = array.array("h", wf.readframes(wf.getnframes()))
    window = int(rate * 0.010)
    found: list[tuple[int, int]] = []
    loud = False
    for pos in range(0, len(raw) - window, window):
        chunk = raw[pos:pos + window]
        peak = max(abs(v) for v in chunk)
        if peak > 1500 and not loud:
            found.append((int(pos / rate * 1000), peak))
            loud = True
        elif peak <= 1500:
            loud = False
    return found


# --------------------------------------------------------------------------
# ffmpeg chains, copied from the app
# --------------------------------------------------------------------------

def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"failed: {' '.join(cmd)}\n{proc.stderr[-4000:]}")


def android_merge_cmd(inputs: list[Path], offsets: list[int], durations: list[int], out: Path) -> list[str]:
    """AudioMerger.makeMergeAudioCommand: atrim, volume, adelay, amix longest."""
    cmd = ["ffmpeg", "-y"]
    for f in inputs:
        cmd += ["-i", str(f)]
    chains = []
    for index, (offset, duration) in enumerate(zip(offsets, durations)):
        play = max(duration, 1)
        chains.append(
            f"[{index}:a]atrim=start=0:duration={play / 1000:.6f},asetpts=PTS-STARTPTS,"
            f"volume=1.0000,adelay={offset}|{offset}[a{index}]"
        )
    mix = "".join(f"[a{i}]" for i in range(len(inputs)))
    filt = "; ".join(chains) + f"; {mix}amix=inputs={len(inputs)}:duration=longest"
    cmd += ["-filter_complex", filt, str(out)]
    return cmd


def export_cmd(audio: Path | None, frames_dir: Path, gen_frames: int, out: Path) -> list[str]:
    """FramesGeneratorService.buildFFmpegCommand / JpegVideoAssembler.assemble."""
    duration = gen_frames * frame_ms() / 1000.0 + 1  # "-t N/60 + 1"
    cmd = ["ffmpeg"]
    if audio is not None:
        cmd += ["-i", str(audio)]
    cmd += [
        "-f", "image2", "-framerate", str(FPS), "-start_number", "0",
        "-i", str(frames_dir / "frame%04d.jpeg"),
        "-y", "-c:v", "mpeg4", "-qscale:v", "1",
    ]
    if audio is not None:
        cmd += ["-c:a", "aac"]
    else:
        cmd += ["-an"]
    cmd += ["-t", f"{duration:.2f}", str(out)]
    return cmd


def ffprobe_duration(path: Path, selector: str) -> float:
    proc = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", selector,
         "-show_entries", "stream=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    raw = proc.stdout.strip().splitlines()
    return float(raw[0]) if raw and raw[0] else 0.0


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", type=Path, help="scene archive to mirror the frame count of")
    ap.add_argument("--keyframes", type=int)
    ap.add_argument("--interframes", type=int)
    ap.add_argument("--work", type=Path, default=Path("/tmp/audio_timing_probe"))
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--clips", type=str, default="",
                    help="comma separated sourceFrameIndex[:durationMs] placements, e.g. 8:6504,15:1000")
    args = ap.parse_args()

    if args.scene:
        keyframes, interframes, no_interp = read_scene(args.scene)
        label = args.scene.name
    elif args.keyframes and args.interframes:
        keyframes, interframes, no_interp = args.keyframes, args.interframes, False
        label = f"{keyframes}kf/{interframes}if"
    else:
        ap.error("pass --scene or --keyframes + --interframes")

    gen = generated_frame_count(keyframes, interframes)
    video_ms = gen * frame_ms()
    export_cut_ms = gen * frame_ms() + 1000.0  # "-t"
    android_preview_ms = (gen - 1) * ANDROID_PREVIEW_TICK_MS
    ios_preview_ms = (gen - 1) * frame_ms()

    work = args.work
    if work.exists():
        shutil.rmtree(work)
    frames_dir = work / "frames"
    frames_dir.mkdir(parents=True)

    print(f"scene            {label}")
    print(f"keyframes        {keyframes}  interframes={interframes} no_interpolation={no_interp}")
    print(f"generated frames {gen}")
    print(f"video duration   {video_ms:.1f} ms   (export -t cuts at {export_cut_ms:.1f} ms)")
    print(f"preview android  {android_preview_ms:.1f} ms  ({ANDROID_PREVIEW_TICK_MS} ms/frame)")
    print(f"preview ios      {ios_preview_ms:.1f} ms  ({frame_ms():.3f} ms/frame)")
    print()

    # 1. frames, generated the way the exporter sees them
    run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
         "-i", f"color=c=black:s=64x48:d={video_ms / 1000:.4f}:r={FPS}",
         str(frames_dir / "frame%04d.jpeg")])
    written = len(list(frames_dir.glob("frame*.jpeg")))
    print(f"frames written   {written} (expected {gen})")
    if written != gen:
        raise SystemExit("frame count mismatch — the probe would measure the wrong thing")
    print()

    # 2. ruler clip(s)
    ruler = work / "ruler.wav"
    times = build_ruler(ruler, RULER_MS)
    print(f"ruler            {len(times)} beeps every {BEEP_STEP_MS} ms, "
          f"{BEEP_MS} ms each, total {RULER_MS} ms")

    placements = parse_clips(args.clips) or [(0, RULER_MS)]

    def origin_offset(src: int) -> int:
        """StageAudio.toGeneratedOffsetMs. Origin indices only exist for spans
        0..keyframes-2; the last keyframe has no generated frame of its own."""
        for span in range(keyframes - 1):
            for index in range(interframes):
                if span == src:
                    return int(((span * (interframes + 1)) + index) * frame_ms())
            if span == src:
                return int(((span * (interframes + 1)) + interframes) * frame_ms())
        return int(gen * frame_ms())  # fallback: past the last generated frame

    inputs, offsets, durations = [], [], []
    for src, duration in placements:
        offset = origin_offset(src)
        print(f"clip             frame {src} -> adelay {offset} ms, play {duration} ms, "
              f"ends {offset + duration} ms")
        inputs.append(ruler)
        offsets.append(offset)
        durations.append(duration)
    print()

    # 3/4. one clip per run: overlapping beeps from two clips merge into a
    # single rising edge and hide each other.
    for run_index, (src, duration) in enumerate(placements):
        print(f"--- run {run_index + 1}: clip at source frame {src} "
              f"({duration} ms, offset {origin_offset(src)} ms) ---")
        merged = work / f"merged_{run_index}.wav"
        run(android_merge_cmd([ruler], [origin_offset(src)], [duration], merged))
        print(f"  merged.wav       {ffprobe_duration(merged, 'a') * 1000:.1f} ms")

        out = work / f"export_{run_index}.mp4"
        run(export_cmd(merged, frames_dir, gen, out))
        out_video = ffprobe_duration(out, "v") * 1000
        out_audio = ffprobe_duration(out, "a") * 1000
        print(f"  export.mp4       video {out_video:.1f} ms | audio {out_audio:.1f} ms")

        decoded = work / f"decoded_{run_index}.wav"
        decode_to_wav(out, decoded)
        heard_ms = [ms for ms, _ in detect_beeps(decoded)]
        print(f"  beeps heard: {heard_ms}")

        offset = origin_offset(src)
        for name, cut in (("export", out_audio),
                          ("preview android", android_preview_ms),
                          ("preview ios", ios_preview_ms)):
            if offset >= cut:
                print(f"  {name:<16} never starts")
                continue
            end = min(offset + duration, cut)
            audible = [t for t in times if offset < t + BEEP_MS and t < end]
            over = max(0.0, offset + duration - out_video)
            print(f"  {name:<16} {len(audible)} beeps audible up to {end:.0f} ms"
                  + (f"  [{over:.0f} ms of audio past the last picture]"
                     if name == "export" and over > 0 else ""))
        print(f"  dropped in export: {max(0.0, offset + duration - out_audio):.0f} ms")
        print(f"  dropped in android preview: {max(0.0, offset + duration - android_preview_ms):.0f} ms")
        print()

    print("where each pipeline stops the audio:")
    print(f"  preview android  {android_preview_ms:7.1f} ms  ({ANDROID_PREVIEW_TICK_MS} ms/frame)")
    print(f"  preview ios      {ios_preview_ms:7.1f} ms  ({frame_ms():.3f} ms/frame)")
    print(f"  export audio     gen_frames/60 + 1 s  = picture end + 1000 ms")
    print()
    print(f"android preview is {100 * (1 - android_preview_ms / video_ms):.1f}% shorter than the picture")

    if args.keep:
        print(f"\nartifacts kept in {work}")
    else:
        shutil.rmtree(work, ignore_errors=True)
        print("\nartifacts deleted (pass --keep to retain)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
