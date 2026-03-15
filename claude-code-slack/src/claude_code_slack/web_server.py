"""FastAPI HTTP server for the agent conductor web UI."""

import logging
import os
import threading
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, Query
from fastapi.staticfiles import StaticFiles

from claude_code_slack.store import SessionStore

logger = logging.getLogger(__name__)

WEB_PORT = int(os.environ.get("WEB_PORT", "2333"))
SLACK_WORKSPACE = os.environ.get("SLACK_WORKSPACE", "wandermyz")

# Resolve path to the built frontend assets
_WEB_DIST = Path(__file__).resolve().parent.parent.parent / "web" / "dist"

store = SessionStore()


def _slack_thread_url(channel_id: str, thread_ts: str) -> str:
    ts_no_dot = thread_ts.replace(".", "")
    return f"https://{SLACK_WORKSPACE}.slack.com/archives/{channel_id}/p{ts_no_dot}"


def create_api() -> FastAPI:
    api = FastAPI(title="Agent Conductor")

    @api.get("/api/sessions")
    def list_sessions(days: int = Query(default=7, ge=1, le=365)):
        cutoff = time.time() - days * 86400
        sessions = store.list_all()
        result = []
        for s in sessions:
            # thread_ts is a Slack timestamp like "1773529834.114199"
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
        return result

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
