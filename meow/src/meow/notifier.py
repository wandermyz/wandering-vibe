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
    ) -> tuple[str, str] | None:
        """Post the alert message + WAV snippet. Returns (channel, message_ts)
        of the alert message so the caller can correlate it back to the local
        snippet for reaction-based labeling.

        The alert text is posted via chat.postMessage (whose response has a
        reliable `ts`); the WAV is then uploaded as a threaded reply.
        `files_upload_v2` does not expose the parent message ts synchronously
        (shares are filled in asynchronously), so we can't rely on it.
        """
        when = datetime.now().strftime("%H:%M:%S")
        score_str = ", ".join(f"{k}={v:.2f}" for k, v in scores.items())
        text = (
            f":cat: meow detected at {when} — "
            f"trigger={trigger_score:.2f}  ({score_str})\n"
            f"React :white_check_mark: for TP, :x: for FP."
        )
        try:
            post = self.client.chat_postMessage(channel=self.cfg.channel, text=text)
        except SlackApiError as e:
            err = e.response.get("error") if e.response else e
            log.warning("slack chat.postMessage error: %s", err)
            return None
        except Exception as e:  # noqa: BLE001 — daemon must not die on transient errors
            log.warning("unexpected error posting message: %s", e)
            return None

        channel = post.get("channel") or self.cfg.channel
        ts = post.get("ts")
        if not ts:
            log.warning("chat.postMessage returned no ts; cannot record pending")
            return None

        wav_bytes = encode_wav(wav, sample_rate)
        try:
            self.client.files_upload_v2(
                channel=channel,
                thread_ts=ts,
                file=wav_bytes,
                filename=f"meow-{int(time.time())}.wav",
                title="meow snippet",
            )
        except SlackApiError as e:
            err = e.response.get("error") if e.response else e
            log.warning("slack files_upload_v2 error: %s (message already posted)", err)
        except Exception as e:  # noqa: BLE001
            log.warning("unexpected upload error: %s (message already posted)", e)

        return (channel, ts)
