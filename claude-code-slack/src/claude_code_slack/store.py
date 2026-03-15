"""Thread-safe SQLite stores for sessions and model preferences."""

import sqlite3
import threading
from pathlib import Path

from claude_code_slack.config import DB_FILE


class _SqliteKVStore:
    """Generic key-value store backed by a SQLite table."""

    def __init__(self, table: str, db_path: Path | None = None):
        self._table = table
        self._db_path = db_path or DB_FILE
        self._lock = threading.Lock()
        self._init_table()

    def _connect(self) -> sqlite3.Connection:
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        return sqlite3.connect(str(self._db_path))

    def _init_table(self) -> None:
        with self._lock:
            con = self._connect()
            try:
                con.execute(
                    f"CREATE TABLE IF NOT EXISTS {self._table} "
                    "(key TEXT PRIMARY KEY, value TEXT NOT NULL)"
                )
                con.commit()
            finally:
                con.close()

    def get(self, key: str) -> str | None:
        with self._lock:
            con = self._connect()
            try:
                row = con.execute(
                    f"SELECT value FROM {self._table} WHERE key = ?", (key,)
                ).fetchone()
                return row[0] if row else None
            finally:
                con.close()

    def set(self, key: str, value: str) -> None:
        with self._lock:
            con = self._connect()
            try:
                con.execute(
                    f"INSERT OR REPLACE INTO {self._table} (key, value) VALUES (?, ?)",
                    (key, value),
                )
                con.commit()
            finally:
                con.close()


class SessionStore(_SqliteKVStore):
    """Maps Slack thread_ts -> Claude session_id."""

    def __init__(self, db_path: Path | None = None):
        super().__init__("sessions", db_path)


class ModelStore(_SqliteKVStore):
    """Maps Slack channel_id -> model alias."""

    def __init__(self, db_path: Path | None = None):
        super().__init__("models", db_path)


VALID_MODELS = {"sonnet", "opus", "haiku"}
