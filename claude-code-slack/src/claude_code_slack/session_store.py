"""Thread-safe JSON session store mapping thread_ts -> session_id."""

import json
import threading
from pathlib import Path

from claude_code_slack.config import SESSIONS_FILE


class SessionStore:
    def __init__(self, path: Path | None = None):
        self._path = path or SESSIONS_FILE
        self._lock = threading.Lock()

    def get(self, thread_ts: str) -> str | None:
        with self._lock:
            data = self._read()
            return data.get(thread_ts)

    def set(self, thread_ts: str, session_id: str) -> None:
        with self._lock:
            data = self._read()
            data[thread_ts] = session_id
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
