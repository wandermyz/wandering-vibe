"""Audio pre-processing for distant / quiet sources.

Fixed-gain + tanh soft-clip. Streaming-friendly: per-sample, no lookahead.
"""

from __future__ import annotations

import numpy as np

GAIN = 10.0


def boost(wav: np.ndarray) -> np.ndarray:
    return np.tanh(wav * GAIN).astype(np.float32)
