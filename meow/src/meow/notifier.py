"""Slack notifier: posts a message + uploads a 3 s WAV snippet of the trigger."""

from __future__ import annotations

import io
import logging
import time
import wave
from datetime import datetime

import numpy as np
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

from .config import SlackConfig

log = logging.getLogger(__name__)


def encode_wav(wav: np.ndarray, sample_rate: int) -> bytes:
    """Encode a mono float32 [-1, 1] waveform as 16-bit PCM WAV bytes."""
    pcm = np.clip(wav * 32767.0, -32768, 32767).astype(np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


class SlackNotifier:
    def __init__(self, cfg: SlackConfig) -> None:
        self.cfg = cfg
        self.client = WebClient(token=cfg.bot_token)

    def notify(
        self,
        scores: dict[str, float],
        trigger_score: float,
        wav: np.ndarray,
        sample_rate: int,
    ) -> None:
        wav_bytes = encode_wav(wav, sample_rate)
        when = datetime.now().strftime("%H:%M:%S")
        score_str = ", ".join(f"{k}={v:.2f}" for k, v in scores.items())
        text = (
            f":cat: meow detected at {when} — "
            f"trigger={trigger_score:.2f}  ({score_str})"
        )
        try:
            self.client.files_upload_v2(
                channel=self.cfg.channel,
                file=wav_bytes,
                filename=f"meow-{int(time.time())}.wav",
                title="meow snippet",
                initial_comment=text,
            )
        except SlackApiError as e:
            err = e.response.get("error") if e.response else e
            log.warning("slack error: %s", err)
        except Exception as e:  # noqa: BLE001 — daemon must not die on transient errors
            log.warning("unexpected error: %s", e)
