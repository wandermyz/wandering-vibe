"""Local persistence of trigger snippets for TP/FP labeling.

Layout under `~/.yuki-conductor/meow/snippets/`:

    inbox/        meow-YYYYMMDD-HHMMSS.wav   <- new events land here
                  meow-YYYYMMDD-HHMMSS.json  <- sidecar with scores + meta
    tp/           <- TPs (via Slack reaction or `mv`)
    fp/           <- FPs (via Slack reaction or `mv`)
    pending.json  <- (channel, ts) -> stem map for Slack-reaction labeling

Outside `workspace/` because snippets are bulky/churny and don't belong
in the Obsidian sync.
"""

from __future__ import annotations

import json
import logging
import threading
from datetime import datetime
from pathlib import Path

import numpy as np

from .notifier import encode_wav

SNIPPETS_DIR = Path.home() / ".yuki-conductor" / "meow" / "snippets"
INBOX_DIR = SNIPPETS_DIR / "inbox"
TP_DIR = SNIPPETS_DIR / "tp"
FP_DIR = SNIPPETS_DIR / "fp"
PENDING_FILE = SNIPPETS_DIR / "pending.json"

_pending_lock = threading.Lock()

log = logging.getLogger(__name__)


def _ensure_dirs() -> None:
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    TP_DIR.mkdir(exist_ok=True)
    FP_DIR.mkdir(exist_ok=True)


def save(
    scores: dict[str, float],
    trigger_score: float,
    dbfs: float,
    wav: np.ndarray,
    sample_rate: int,
) -> Path:
    _ensure_dirs()
    now = datetime.now()
    stem = f"meow-{now:%Y%m%d-%H%M%S}"
    wav_path = INBOX_DIR / f"{stem}.wav"
    meta_path = INBOX_DIR / f"{stem}.json"

    wav_path.write_bytes(encode_wav(wav, sample_rate))
    meta = {
        "timestamp": now.isoformat(timespec="seconds"),
        "trigger_score": round(trigger_score, 4),
        "dbfs": round(dbfs, 2),
        "sample_rate": sample_rate,
        "duration_s": round(len(wav) / sample_rate, 3),
        "scores": {k: round(v, 4) for k, v in scores.items()},
    }
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")

    log.info("saved snippet: %s", wav_path)
    return wav_path


def _pending_key(channel: str, ts: str) -> str:
    return f"{channel}:{ts}"


def _load_pending() -> dict[str, str]:
    if not PENDING_FILE.exists():
        return {}
    try:
        return json.loads(PENDING_FILE.read_text())
    except json.JSONDecodeError:
        log.warning("pending.json is malformed; starting empty")
        return {}


def _save_pending(data: dict[str, str]) -> None:
    tmp = PENDING_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    tmp.replace(PENDING_FILE)


def record_pending(channel: str, ts: str, stem: str) -> None:
    """Remember that Slack message (channel, ts) maps to local snippet `stem`."""
    _ensure_dirs()
    with _pending_lock:
        data = _load_pending()
        data[_pending_key(channel, ts)] = stem
        _save_pending(data)


def list_pending() -> dict[str, str]:
    with _pending_lock:
        return _load_pending()


def label(channel: str, ts: str, verdict: str) -> Path | None:
    """Move the snippet identified by (channel, ts) to tp/ or fp/.

    `verdict` must be "tp" or "fp". Returns the new wav path, or None if the
    message was unknown (e.g. someone reacted to an unrelated bot message).
    Idempotent: re-labeling moves the files to the new verdict's directory.
    """
    if verdict not in ("tp", "fp"):
        raise ValueError(f"verdict must be 'tp' or 'fp', got {verdict!r}")
    _ensure_dirs()
    key = _pending_key(channel, ts)
    with _pending_lock:
        data = _load_pending()
        stem = data.get(key)
        if stem is None:
            return None
        dest_dir = TP_DIR if verdict == "tp" else FP_DIR
        moved_wav: Path | None = None
        # Search inbox + the other verdict dir (in case of re-label).
        for src_dir in (INBOX_DIR, TP_DIR, FP_DIR):
            if src_dir == dest_dir:
                continue
            for suffix in (".wav", ".json"):
                src = src_dir / f"{stem}{suffix}"
                if src.exists():
                    dest = dest_dir / src.name
                    src.replace(dest)
                    if suffix == ".wav":
                        moved_wav = dest
        if moved_wav is None:
            log.warning("label: pending entry %s had no files on disk", stem)
            data.pop(key, None)
            _save_pending(data)
            return None
        data.pop(key, None)
        _save_pending(data)
        log.info("labeled %s as %s -> %s", stem, verdict, moved_wav)
        return moved_wav
