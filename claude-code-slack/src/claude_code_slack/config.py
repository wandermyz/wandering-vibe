"""Configuration and path constants."""

import os
from pathlib import Path

from dotenv import load_dotenv

# Load .env from the project root (next to pyproject.toml), overriding any
# existing env vars so the project .env is always the source of truth.
_project_root = Path(__file__).resolve().parent.parent.parent
load_dotenv(_project_root / ".env", override=True)

DATA_DIR = Path(os.environ.get("CLAUDE_CODE_SLACK_DATA_DIR", Path.home() / ".claude-code-slack"))
SESSIONS_FILE = DATA_DIR / "sessions.json"
MODELS_FILE = DATA_DIR / "models.json"
LOG_FILE = DATA_DIR / "daemon.log"
ERR_LOG_FILE = DATA_DIR / "daemon.err.log"
PLIST_LABEL = "com.user.claude-code-slack"
PLIST_PATH = Path.home() / "Library" / "LaunchAgents" / f"{PLIST_LABEL}.plist"

CLAUDE_TIMEOUT = int(os.environ.get("CLAUDE_TIMEOUT", "300"))
CLAUDE_WORKING_DIR = os.environ.get("CLAUDE_WORKING_DIR", str(Path.home() / "Projects" / "wandering-vibe"))


def slack_bot_token() -> str:
    token = os.environ.get("SLACK_BOT_TOKEN", "")
    if not token:
        raise RuntimeError("SLACK_BOT_TOKEN not set")
    return token


def slack_app_token() -> str:
    token = os.environ.get("SLACK_APP_TOKEN", "")
    if not token:
        raise RuntimeError("SLACK_APP_TOKEN not set")
    return token
