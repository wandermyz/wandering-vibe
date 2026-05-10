"""Offline evaluation of YAMNet on example recordings.

Decodes audio files via ffmpeg, runs YAMNet at 16 kHz mono, prints
per-frame target-class scores and peaks. Also reports the result of
peak-normalizing the waveform first, to assess whether simple gain
helps for distant meows.

Usage:
    uv run python scripts/eval_recordings.py [files...]
    uv run python scripts/eval_recordings.py /path/to/meow-example/
"""

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import numpy as np
import tensorflow_hub as hub

YAMNET_URL = "https://tfhub.dev/google/yamnet/1"
TARGET_RATE = 16000
TARGET_CLASSES = ("Meow", "Cat", "Hiss", "Caterwaul", "Purr")
FRAME_HOP_SEC = 0.48  # YAMNet hop


def decode_to_mono16k(path: Path) -> np.ndarray:
    cmd = [
        "ffmpeg", "-v", "error", "-i", str(path),
        "-ac", "1", "-ar", str(TARGET_RATE),
        "-f", "f32le", "-",
    ]
    result = subprocess.run(cmd, capture_output=True, check=True)
    return np.frombuffer(result.stdout, dtype=np.float32).copy()


def load_class_names(model) -> list[str]:
    path = model.class_map_path().numpy().decode()
    with open(path) as f:
        return [row["display_name"] for row in csv.DictReader(f)]


def analyze(model, target_indices: dict[str, int], wav: np.ndarray, label: str) -> None:
    scores, _emb, _spec = model(wav)
    s = scores.numpy()  # (num_frames, 521)
    print(f"  [{label}] frames={s.shape[0]} duration={len(wav) / TARGET_RATE:.2f}s "
          f"rms={float((wav ** 2).mean() ** 0.5):.4f} peak={float(np.abs(wav).max()):.4f}")
    # Per-target peak
    for name, idx in target_indices.items():
        col = s[:, idx]
        peak_frame = int(np.argmax(col))
        peak_score = float(col[peak_frame])
        peak_time = peak_frame * FRAME_HOP_SEC
        print(f"  [{label}] {name:<10} peak={peak_score:.3f} at t={peak_time:5.2f}s")
    # Frames where Meow or Cat exceeds 0.05
    interesting = []
    meow_idx = target_indices["Meow"]
    cat_idx = target_indices["Cat"]
    for i in range(s.shape[0]):
        m = float(s[i, meow_idx])
        c = float(s[i, cat_idx])
        if m >= 0.05 or c >= 0.05:
            interesting.append((i * FRAME_HOP_SEC, m, c))
    if interesting:
        print(f"  [{label}] frames with Meow>=0.05 or Cat>=0.05:")
        for t, m, c in interesting[:12]:
            print(f"    t={t:5.2f}s  Meow={m:.3f}  Cat={c:.3f}")
        if len(interesting) > 12:
            print(f"    ... ({len(interesting) - 12} more)")
    else:
        print(f"  [{label}] no frames with Meow>=0.05 or Cat>=0.05")


def collect_paths(args: list[str]) -> list[Path]:
    paths: list[Path] = []
    for arg in args:
        p = Path(arg).expanduser()
        if p.is_dir():
            paths.extend(sorted(p.iterdir()))
        else:
            paths.append(p)
    return [p for p in paths if p.is_file() and p.suffix.lower() in {".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg"}]


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: eval_recordings.py <files-or-dir> [...]", file=sys.stderr)
        return 2
    paths = collect_paths(argv)
    if not paths:
        print("no audio files found", file=sys.stderr)
        return 2

    print(f"loading YAMNet from {YAMNET_URL} ...", flush=True)
    model = hub.load(YAMNET_URL)
    class_names = load_class_names(model)
    target_indices = {n: class_names.index(n) for n in TARGET_CLASSES}
    print(f"target indices: {target_indices}", flush=True)

    for path in paths:
        print(f"\n=== {path.name} ===", flush=True)
        try:
            wav = decode_to_mono16k(path)
        except subprocess.CalledProcessError as e:
            print(f"  ffmpeg failed: {e.stderr.decode(errors='replace').strip()}")
            continue
        analyze(model, target_indices, wav, "raw      ")
        peak = float(np.abs(wav).max())
        if peak > 0:
            normalized = (wav / peak * 0.95).astype(np.float32)
            analyze(model, target_indices, normalized, "peak0.95 ")
        # Fixed gain 10x with tanh soft-clip
        gained = np.tanh(wav * 10.0).astype(np.float32)
        analyze(model, target_indices, gained, "gain10x  ")
        # RMS-target normalization (target RMS = 0.05) capped so peak<=0.95
        rms = float((wav ** 2).mean() ** 0.5)
        if rms > 0:
            scale = min(0.05 / rms, 0.95 / max(peak, 1e-9))
            rms_norm = (wav * scale).astype(np.float32)
            analyze(model, target_indices, rms_norm, f"rms0.05@{scale:5.1f}x")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
