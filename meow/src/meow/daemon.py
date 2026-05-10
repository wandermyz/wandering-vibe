"""Main loop: mic -> resample -> boost -> YAMNet -> stdout + Slack."""

from __future__ import annotations

import logging
import math
import queue
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly

from .capture import (
    TARGET_RATE,
    describe_default_input,
    open_input_stream,
    query_default_input,
)
from .config import Config, config_path
from .detector import YamnetDetector
from .enhance import boost
from .notifier import SlackNotifier

WINDOW_SECONDS = 1.0
HOP_SECONDS = 0.5
WINDOW_SAMPLES = int(TARGET_RATE * WINDOW_SECONDS)
HOP_SAMPLES = int(TARGET_RATE * HOP_SECONDS)

TRIGGER_CLASSES = ("Meow", "Cat", "Caterwaul")
TRIGGER_THRESHOLD = 0.30
TRIGGER_CONSECUTIVE = 1

SNIPPET_SECONDS = 3.0
SNIPPET_SAMPLES = int(TARGET_RATE * SNIPPET_SECONDS)
COOLDOWN_SECONDS = 60.0

LOG_DIR = Path.home() / ".yuki-conductor" / "workspace" / "logs"
LOG_FILE = LOG_DIR / "meow.log"
LOG_MAX_BYTES = 10 * 1024 * 1024
LOG_BACKUP_COUNT = 1

log = logging.getLogger("meow")


def _setup_logging() -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(name)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    root = logging.getLogger("meow")
    root.setLevel(logging.INFO)
    root.handlers.clear()
    root.propagate = False

    sh = logging.StreamHandler()
    sh.setFormatter(fmt)
    root.addHandler(sh)

    fh = RotatingFileHandler(LOG_FILE, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT)
    fh.setFormatter(fmt)
    root.addHandler(fh)
    return LOG_FILE


def run() -> None:
    log_path = _setup_logging()
    log.info("log file: %s (rolls at %d MB)", log_path, LOG_MAX_BYTES // (1024 * 1024))

    info = query_default_input()
    device_rate = int(info["default_samplerate"])
    log.info("input device: %s", describe_default_input())
    log.info("capture at %d Hz, resample to %d Hz", device_rate, TARGET_RATE)

    cfg = Config.load()
    notifier: SlackNotifier | None = None
    if cfg.slack is not None:
        notifier = SlackNotifier(cfg.slack)
        log.info("slack notifier enabled, channel=%s", cfg.slack.channel)
    else:
        log.info("no slack config at %s — stdout/log only", config_path())

    log.info("loading YAMNet (first run downloads weights)...")
    detector = YamnetDetector()
    log.info("tracking classes: %s", list(detector.target_indices))
    log.info(
        "trigger: max%s >= %.2f for %d consecutive windows; cooldown=%ds; snippet=%ds",
        TRIGGER_CLASSES, TRIGGER_THRESHOLD, TRIGGER_CONSECUTIVE,
        int(COOLDOWN_SECONDS), int(SNIPPET_SECONDS),
    )

    up, down = _resample_ratio(TARGET_RATE, device_rate)
    audio_q: "queue.Queue[np.ndarray]" = queue.Queue()
    inference_buffer = np.zeros(0, dtype=np.float32)
    snippet_buffer = np.zeros(0, dtype=np.float32)
    consecutive = 0
    last_trigger_at = 0.0

    with open_input_stream(audio_q, device_rate):
        log.info("listening. Ctrl-C to stop.")
        while True:
            chunk = audio_q.get()
            resampled = resample_poly(chunk, up, down).astype(np.float32)

            inference_buffer = np.concatenate([inference_buffer, resampled])
            snippet_buffer = np.concatenate([snippet_buffer, resampled])
            if len(snippet_buffer) > SNIPPET_SAMPLES:
                snippet_buffer = snippet_buffer[-SNIPPET_SAMPLES:]

            while len(inference_buffer) >= WINDOW_SAMPLES:
                window = inference_buffer[:WINDOW_SAMPLES]
                inference_buffer = inference_buffer[HOP_SAMPLES:]
                rms = float(np.sqrt(np.mean(window ** 2)))
                dbfs = 20.0 * math.log10(max(rms, 1e-10))
                scores = detector.score(boost(window))
                trigger_score = max(scores[c] for c in TRIGGER_CLASSES)
                if trigger_score >= TRIGGER_THRESHOLD:
                    consecutive += 1
                else:
                    consecutive = 0
                _log_window(dbfs, scores, trigger_score, consecutive)

                if consecutive == TRIGGER_CONSECUTIVE:
                    now = time.monotonic()
                    if now - last_trigger_at < COOLDOWN_SECONDS:
                        log.info(
                            "trigger reached but in cooldown (%ds remaining)",
                            int(COOLDOWN_SECONDS - (now - last_trigger_at)),
                        )
                    else:
                        last_trigger_at = now
                        snippet = snippet_buffer.copy()
                        log.info(
                            "*** TRIGGER *** trigger_score=%.3f snippet_samples=%d",
                            trigger_score, len(snippet),
                        )
                        if notifier is not None:
                            notifier.notify(scores, trigger_score, snippet, TARGET_RATE)


def _resample_ratio(target: int, source: int) -> tuple[int, int]:
    g = math.gcd(target, source)
    return target // g, source // g


def _log_window(dbfs: float, scores: dict[str, float], trigger_score: float, consecutive: int) -> None:
    parts = []
    for name, score in scores.items():
        marker = "*" if name in TRIGGER_CLASSES and score >= TRIGGER_THRESHOLD else " "
        parts.append(f"{marker}{name}={score:.3f}")
    log.info(
        "dBFS=%6.1f trig=%.3f run=%d  %s",
        dbfs, trigger_score, consecutive, " ".join(parts),
    )
