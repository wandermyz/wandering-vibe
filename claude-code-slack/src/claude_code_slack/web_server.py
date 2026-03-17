"""FastAPI HTTP server for the agent conductor web UI."""

import asyncio
import concurrent.futures
import fcntl
import json
import logging
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import threading
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from claude_code_slack.config import CLAUDE_WORKING_DIR
from claude_code_slack.store import SessionStore
from claude_code_slack import zellij_manager

logger = logging.getLogger(__name__)

WEB_PORT = int(os.environ.get("WEB_PORT", "2333"))
SLACK_WORKSPACE = os.environ.get("SLACK_WORKSPACE", "wandermyz")

# Resolve path to the built frontend assets
_WEB_DIST = Path(__file__).resolve().parent.parent.parent / "web" / "dist"

store = SessionStore()
# Dedicated thread pool for PTY reads so they don't block the default executor
_pty_executor = concurrent.futures.ThreadPoolExecutor(max_workers=10, thread_name_prefix="pty")


def _slack_thread_url(channel_id: str, thread_ts: str) -> str:
    ts_no_dot = thread_ts.replace(".", "")
    return f"https://{SLACK_WORKSPACE}.slack.com/archives/{channel_id}/p{ts_no_dot}"


def create_api() -> FastAPI:
    api = FastAPI(title="Agent Conductor")

    @api.get("/api/sessions")
    def list_sessions(days: int = Query(default=7, ge=1, le=365)):
        cutoff = time.time() - days * 86400
        sessions = store.list_all()
        alive_sessions = set(zellij_manager.list_sessions())
        result = []
        for s in sessions:
            # Zellij sessions use "zellij:<name>" keys — always include them
            if s["session_type"] == "zellij":
                s["slack_url"] = None
                s["alive"] = s["session_id"] in alive_sessions
                result.append(s)
                continue
            # Slack sessions: filter by timestamp age
            try:
                ts_float = float(s["thread_ts"])
            except (ValueError, TypeError):
                continue
            if ts_float < cutoff:
                continue
            if s["channel_id"]:
                s["slack_url"] = _slack_thread_url(s["channel_id"], s["thread_ts"])
            else:
                s["slack_url"] = None
            result.append(s)
        result.sort(key=lambda s: s["thread_ts"], reverse=True)
        return result

    class TitleUpdate(BaseModel):
        title: str

    @api.patch("/api/sessions/{thread_ts:path}")
    def update_session_title(thread_ts: str, body: TitleUpdate):
        if not store.get(thread_ts):
            raise HTTPException(status_code=404, detail="Session not found")
        store.set_title(thread_ts, body.title)
        return {"ok": True, "title": body.title}

    class ZellijSessionCreate(BaseModel):
        name: str
        project: str
        worktree: str

    @api.post("/api/sessions/zellij")
    def create_zellij_session(body: ZellijSessionCreate):
        zellij_manager.create_session(body.name, body.worktree)
        key = store.create_zellij_session(
            zellij_session_name=body.name,
            title=body.name,
            project=body.project,
        )
        return {
            "thread_ts": key,
            "session_id": body.name,
            "session_type": "zellij",
            "project": body.project,
            "title": body.name,
        }

    @api.delete("/api/sessions/zellij/{session_key:path}")
    def delete_zellij_session(session_key: str):
        """Kill the Zellij process but keep the session record."""
        if not session_key.startswith("zellij:"):
            raise HTTPException(status_code=400, detail="Not a Zellij session")
        zellij_name = session_key[len("zellij:"):]
        zellij_manager.kill_session(zellij_name)
        return {"ok": True}

    @api.post("/api/sessions/zellij/{session_key:path}/reopen")
    def reopen_zellij_session(session_key: str):
        """Reopen a stopped Zellij session with claude --continue."""
        if not session_key.startswith("zellij:"):
            raise HTTPException(status_code=400, detail="Not a Zellij session")
        zellij_name = session_key[len("zellij:"):]
        zellij_manager.create_session(zellij_name, zellij_name, resume=True)
        return {"ok": True, "alive": True}

    @api.delete("/api/sessions/{thread_ts:path}")
    def delete_session(thread_ts: str):
        if not store.delete_session(thread_ts):
            raise HTTPException(status_code=404, detail="Session not found")
        return {"ok": True}

    @api.websocket("/ws/terminal/{session_key:path}")
    async def terminal_websocket(websocket: WebSocket, session_key: str):
        """Bridge a Zellij session to a browser terminal via WebSocket + PTY."""
        await websocket.accept()

        # Extract zellij session name from key
        if not session_key.startswith("zellij:"):
            await websocket.close(code=1008, reason="Not a Zellij session")
            return
        zellij_name = session_key[len("zellij:"):]

        # Wait for the initial resize message from the frontend
        # so we can set the PTY size before spawning zellij
        initial_msg = await websocket.receive()
        init_cols, init_rows = 80, 24
        if "text" in initial_msg:
            try:
                parsed = json.loads(initial_msg["text"])
                if parsed.get("type") == "resize":
                    init_cols = parsed.get("cols", 80)
                    init_rows = parsed.get("rows", 24)
            except (json.JSONDecodeError, ValueError):
                pass

        # Create a PTY and set initial size
        master_fd, slave_fd = pty.openpty()
        winsize = struct.pack("HHHH", init_rows, init_cols, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)
        env = os.environ.copy()
        env.update({
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "SHELL": "/bin/zsh",
            "LC_ALL": "en_US.UTF-8",
            "LANG": "en_US.UTF-8",
        })
        try:
            proc = subprocess.Popen(
                ["zellij", "attach", zellij_name, "--create"],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                cwd=CLAUDE_WORKING_DIR,
                env=env,
                start_new_session=True,
            )
        except FileNotFoundError:
            os.close(master_fd)
            os.close(slave_fd)
            await websocket.close(code=1011, reason="zellij not found")
            return

        os.close(slave_fd)  # Only the master side is needed

        loop = asyncio.get_event_loop()
        stop_event = threading.Event()

        def _blocking_read():
            """Read from PTY with select() so we can be interrupted."""
            while not stop_event.is_set():
                ready, _, _ = select.select([master_fd], [], [], 0.5)
                if ready:
                    try:
                        data = os.read(master_fd, 4096)
                        if not data:
                            return None
                        return data
                    except OSError:
                        return None
            return None

        async def pty_reader():
            """Read from PTY and send to WebSocket."""
            try:
                while not stop_event.is_set():
                    data = await loop.run_in_executor(
                        _pty_executor, _blocking_read
                    )
                    if not data:
                        break
                    await websocket.send_bytes(data)
            except (OSError, WebSocketDisconnect):
                pass

        reader_task = asyncio.create_task(pty_reader())

        try:
            while True:
                msg = await websocket.receive()
                if msg.get("type") == "websocket.disconnect":
                    break
                try:
                    if "bytes" in msg:
                        os.write(master_fd, msg["bytes"])
                    elif "text" in msg:
                        # Handle resize messages or text input
                        try:
                            parsed = json.loads(msg["text"])
                            if parsed.get("type") == "resize":
                                cols = parsed.get("cols", 80)
                                rows = parsed.get("rows", 24)
                                winsize = struct.pack("HHHH", rows, cols, 0, 0)
                                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
                                # Explicitly signal the process group
                                try:
                                    os.killpg(os.getpgid(proc.pid), signal.SIGWINCH)
                                except (OSError, ProcessLookupError):
                                    pass
                                continue
                        except (json.JSONDecodeError, ValueError):
                            pass
                        os.write(master_fd, msg["text"].encode())
                except OSError:
                    logger.debug("PTY write failed, closing WebSocket", exc_info=True)
                    break
        except WebSocketDisconnect:
            pass
        finally:
            stop_event.set()
            reader_task.cancel()
            try:
                os.close(master_fd)
            except OSError:
                pass
            proc.terminate()

    # Serve the React frontend (if built)
    if _WEB_DIST.is_dir():
        api.mount("/", StaticFiles(directory=str(_WEB_DIST), html=True), name="static")

    return api


# Module-level app for `uvicorn claude_code_slack.web_server:app`
app = create_api()


def start_web_server() -> None:
    """Start the web server in a daemon thread (non-blocking)."""
    app = create_api()

    def _run():
        uvicorn.run(app, host="0.0.0.0", port=WEB_PORT, log_level="info")

    thread = threading.Thread(target=_run, daemon=True, name="web-server")
    thread.start()
    logger.info(f"Web server started on port {WEB_PORT}")
