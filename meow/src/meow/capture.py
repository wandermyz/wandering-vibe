"""Microphone capture into a numpy queue at the device's native sample rate.

Resampling to YAMNet's 16 kHz happens downstream, not in the audio callback.
"""

from __future__ import annotations

import queue

import numpy as np
import sounddevice as sd

TARGET_RATE = 16000
BLOCK_SECONDS = 0.5


def query_default_input() -> dict:
    return sd.query_devices(kind="input")


def open_input_stream(
    audio_q: "queue.Queue[np.ndarray]",
    device_rate: int,
) -> sd.InputStream:
    def callback(indata: np.ndarray, frames: int, time_info, status) -> None:
        if status:
            print(f"[capture] status: {status}", flush=True)
        audio_q.put(indata[:, 0].copy())

    return sd.InputStream(
        samplerate=device_rate,
        channels=1,
        dtype="float32",
        callback=callback,
        blocksize=int(device_rate * BLOCK_SECONDS),
    )


def describe_default_input() -> str:
    info = query_default_input()
    return f"{info['name']} (native {int(info['default_samplerate'])} Hz)"
