"""Configuration and path constants."""

import os
from pathlib import Path

from dotenv import load_dotenv

# Load .env from workspace/ (gitignored, contains secrets).
# Falls back to project root .env for backwards compatibility.
_project_root = Path(__file__).resolve().parent.parent.parent
_workspace_env = _project_root.parent / "workspace" / ".env"
_project_env = _project_root / ".env"
load_dotenv(_workspace_env if _workspace_env.exists() else _project_env, override=True)

DATA_DIR = Path(os.environ.get("CLAUDE_CODE_SLACK_DATA_DIR", Path.home() / ".claude-code-slack"))
LOG_FILE = DATA_DIR / "daemon.log"
ERR_LOG_FILE = DATA_DIR / "daemon.err.log"
PLIST_LABEL = "com.user.claude-code-slack"
PLIST_PATH = Path.home() / "Library" / "LaunchAgents" / f"{PLIST_LABEL}.plist"

WORKSPACE_DIR = _project_root.parent / "workspace"
DB_FILE = WORKSPACE_DIR / "claude-code-slack.db"
CRON_FILE = WORKSPACE_DIR / "cron.yaml"
ATTACHMENTS_DIR = WORKSPACE_DIR / "attachments"
UPLOADS_DIR = WORKSPACE_DIR / "uploads"

CLAUDE_TIMEOUT = int(os.environ.get("CLAUDE_TIMEOUT", "300"))
CLAUDE_WORKING_DIR = os.path.expanduser(os.environ.get("CLAUDE_WORKING_DIR", "~/Projects/wandering-vibe"))


def slack_cron_channel() -> str:
    channel = os.environ.get("SLACK_CRON_CHANNEL", "")
    if not channel:
        raise RuntimeError("SLACK_CRON_CHANNEL not set")
    return channel


def slack_app_dm_channel() -> str:
    channel = os.environ.get("SLACK_APP_DM_CHANNEL", "")
    if not channel:
        raise RuntimeError("SLACK_APP_DM_CHANNEL not set")
    return channel


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
