"""Thread-safe JSON store mapping channel_id -> model alias."""

import json
import threading
from pathlib import Path

from claude_code_slack.config import MODELS_FILE

VALID_MODELS = {"sonnet", "opus", "haiku"}


class ModelStore:
    def __init__(self, path: Path | None = None):
        self._path = path or MODELS_FILE
        self._lock = threading.Lock()

    def get(self, channel: str) -> str | None:
        with self._lock:
            data = self._read()
            return data.get(channel)

    def set(self, channel: str, model: str) -> None:
        with self._lock:
            data = self._read()
            data[channel] = model
            self._write(data)

    def _read(self) -> dict[str, str]:
        if not self._path.exists():
            return {}
        try:
            return json.loads(self._path.read_text())
        except (json.JSONDecodeError, OSError):
            return {}

    def _write(self, data: dict[str, str]) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(json.dumps(data, indent=2))
