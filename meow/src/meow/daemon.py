"""Phase-1 main loop: mic -> resample to 16 kHz -> boost -> YAMNet -> stdout."""

from __future__ import annotations

import math
import queue
import time

import numpy as np
from scipy.signal import resample_poly

from .capture import (
    TARGET_RATE,
    describe_default_input,
    open_input_stream,
    query_default_input,
)
from .detector import YamnetDetector
from .enhance import boost

WINDOW_SECONDS = 1.0
HOP_SECONDS = 0.5
WINDOW_SAMPLES = int(TARGET_RATE * WINDOW_SECONDS)
HOP_SAMPLES = int(TARGET_RATE * HOP_SECONDS)

TRIGGER_CLASSES = ("Meow", "Cat", "Caterwaul")
TRIGGER_THRESHOLD = 0.30
TRIGGER_CONSECUTIVE = 2


def run() -> None:
    info = query_default_input()
    device_rate = int(info["default_samplerate"])
    print(f"[meow] input device: {describe_default_input()}", flush=True)
    print(f"[meow] capture at {device_rate} Hz, resample to {TARGET_RATE} Hz", flush=True)

    print("[meow] loading YAMNet (first run downloads weights)...", flush=True)
    detector = YamnetDetector()
    print(f"[meow] tracking classes: {list(detector.target_indices)}", flush=True)
    print(
        f"[meow] trigger: max{TRIGGER_CLASSES} >= {TRIGGER_THRESHOLD} "
        f"for {TRIGGER_CONSECUTIVE} consecutive windows",
        flush=True,
    )

    up, down = _resample_ratio(TARGET_RATE, device_rate)
    audio_q: "queue.Queue[np.ndarray]" = queue.Queue()
    buffer = np.zeros(0, dtype=np.float32)
    consecutive = 0

    with open_input_stream(audio_q, device_rate):
        print("[meow] listening. Ctrl-C to stop.", flush=True)
        while True:
            chunk = audio_q.get()
            resampled = resample_poly(chunk, up, down).astype(np.float32)
            buffer = np.concatenate([buffer, resampled])
            while len(buffer) >= WINDOW_SAMPLES:
                window = buffer[:WINDOW_SAMPLES]
                buffer = buffer[HOP_SAMPLES:]
                boosted = boost(window)
                scores = detector.score(boosted)
                trigger_score = max(scores[c] for c in TRIGGER_CLASSES)
                if trigger_score >= TRIGGER_THRESHOLD:
                    consecutive += 1
                else:
                    consecutive = 0
                _print_line(scores, trigger_score, consecutive)
                if consecutive == TRIGGER_CONSECUTIVE:
                    print(
                        f"[meow] *** TRIGGER *** "
                        f"trigger_score={trigger_score:.3f} "
                        f"scores={ {k: round(v, 3) for k, v in scores.items()} }",
                        flush=True,
                    )


def _resample_ratio(target: int, source: int) -> tuple[int, int]:
    g = math.gcd(target, source)
    return target // g, source // g


def _print_line(scores: dict[str, float], trigger_score: float, consecutive: int) -> None:
    ts = time.strftime("%H:%M:%S")
    parts = []
    for name, score in scores.items():
        marker = "*" if name in TRIGGER_CLASSES and score >= TRIGGER_THRESHOLD else " "
        parts.append(f"{marker}{name}={score:.3f}")
    state = f"trig={trigger_score:.3f} run={consecutive}"
    print(f"[{ts}] {state}  {' '.join(parts)}", flush=True)
