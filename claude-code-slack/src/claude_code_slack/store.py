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


class SessionStore:
    """Maps Slack thread_ts -> (session_id, channel_id, title).

    Extended from the original KV store to include channel_id for
    constructing Slack thread URLs and title for display.
    Auto-migrates the old schema.
    """

    MAX_TITLE_LEN = 100

    def __init__(self, db_path: Path | None = None):
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
                    "CREATE TABLE IF NOT EXISTS sessions "
                    "(key TEXT PRIMARY KEY, value TEXT NOT NULL)"
                )
                # Auto-migrate: add columns if missing
                cols = {
                    row[1]
                    for row in con.execute("PRAGMA table_info(sessions)").fetchall()
                }
                if "channel_id" not in cols:
                    con.execute(
                        "ALTER TABLE sessions ADD COLUMN channel_id TEXT"
                    )
                if "title" not in cols:
                    con.execute(
                        "ALTER TABLE sessions ADD COLUMN title TEXT"
                    )
                con.commit()
            finally:
                con.close()

    def get(self, key: str) -> str | None:
        """Return session_id for a thread_ts, or None."""
        with self._lock:
            con = self._connect()
            try:
                row = con.execute(
                    "SELECT value FROM sessions WHERE key = ?", (key,)
                ).fetchone()
                return row[0] if row else None
            finally:
                con.close()

    def set(self, key: str, value: str, channel_id: str | None = None,
            title: str | None = None) -> None:
        """Store session_id (and optionally channel_id/title) for a thread_ts."""
        if title and len(title) > self.MAX_TITLE_LEN:
            title = title[:self.MAX_TITLE_LEN - 1] + "\u2026"
        with self._lock:
            con = self._connect()
            try:
                con.execute(
                    "INSERT OR REPLACE INTO sessions (key, value, channel_id, title) "
                    "VALUES (?, ?, ?, ?)",
                    (key, value, channel_id, title),
                )
                con.commit()
            finally:
                con.close()

    def set_title(self, key: str, title: str) -> bool:
        """Update just the title for an existing session. Returns True if found."""
        if len(title) > self.MAX_TITLE_LEN:
            title = title[:self.MAX_TITLE_LEN - 1] + "\u2026"
        with self._lock:
            con = self._connect()
            try:
                cur = con.execute(
                    "UPDATE sessions SET title = ? WHERE key = ?",
                    (title, key),
                )
                con.commit()
                return cur.rowcount > 0
            finally:
                con.close()

    def list_all(self) -> list[dict]:
        """Return all sessions as dicts with thread_ts, session_id, channel_id, title."""
        with self._lock:
            con = self._connect()
            try:
                rows = con.execute(
                    "SELECT key, value, channel_id, title FROM sessions ORDER BY key DESC"
                ).fetchall()
                return [
                    {
                        "thread_ts": row[0],
                        "session_id": row[1],
                        "channel_id": row[2],
                        "title": row[3],
                    }
                    for row in rows
                ]
            finally:
                con.close()


class ModelStore(_SqliteKVStore):
    """Maps Slack channel_id -> model alias."""

    def __init__(self, db_path: Path | None = None):
        super().__init__("models", db_path)


VALID_MODELS = {"sonnet", "opus", "haiku"}
