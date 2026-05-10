"""YAMNet wrapper. Returns scores for the cat-related AudioSet classes."""

from __future__ import annotations

import csv

import numpy as np
import tensorflow_hub as hub

YAMNET_URL = "https://tfhub.dev/google/yamnet/1"
TARGET_CLASSES = ("Meow", "Cat", "Hiss", "Caterwaul", "Purr")


class YamnetDetector:
    def __init__(self) -> None:
        self.model = hub.load(YAMNET_URL)
        class_map_path = self.model.class_map_path().numpy().decode()
        all_names = self._load_class_names(class_map_path)
        self.target_indices: dict[str, int] = {}
        for name in TARGET_CLASSES:
            try:
                self.target_indices[name] = all_names.index(name)
            except ValueError:
                print(f"[detector] warning: class '{name}' not in YAMNet label map", flush=True)

    @staticmethod
    def _load_class_names(path: str) -> list[str]:
        with open(path) as f:
            return [row["display_name"] for row in csv.DictReader(f)]

    def score(self, waveform: np.ndarray) -> dict[str, float]:
        """Run YAMNet on a 1-D float32 waveform; return max score per target class across frames."""
        scores, _embeddings, _spec = self.model(waveform)
        scores_np = scores.numpy()
        max_per_class = scores_np.max(axis=0)
        return {name: float(max_per_class[idx]) for name, idx in self.target_indices.items()}
