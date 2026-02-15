"""Tests for session_store module."""

import threading
from pathlib import Path

from claude_code_slack.session_store import SessionStore


def test_roundtrip(tmp_path: Path):
    store = SessionStore(path=tmp_path / "sessions.json")
    store.set("ts_1", "session_abc")
    assert store.get("ts_1") == "session_abc"


def test_missing_key(tmp_path: Path):
    store = SessionStore(path=tmp_path / "sessions.json")
    assert store.get("nonexistent") is None


def test_file_creation(tmp_path: Path):
    path = tmp_path / "subdir" / "sessions.json"
    store = SessionStore(path=path)
    store.set("ts_1", "s1")
    assert path.exists()


def test_overwrite(tmp_path: Path):
    store = SessionStore(path=tmp_path / "sessions.json")
    store.set("ts_1", "old")
    store.set("ts_1", "new")
    assert store.get("ts_1") == "new"


def test_concurrent_access(tmp_path: Path):
    store = SessionStore(path=tmp_path / "sessions.json")
    errors: list[Exception] = []

    def writer(i: int):
        try:
            store.set(f"ts_{i}", f"session_{i}")
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer, args=(i,)) for i in range(20)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert not errors
    for i in range(20):
        assert store.get(f"ts_{i}") == f"session_{i}"
