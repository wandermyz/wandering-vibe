"""Config loaded from ~/.meow/.env via python-dotenv.

Override the path with the MEOW_ENV environment variable.

Schema (.env keys):

    MEOW_SLACK_BOT_TOKEN=xoxb-...
    MEOW_SLACK_APP_TOKEN=xapp-...    # optional; enables reaction-based TP/FP labeling
    MEOW_SLACK_CHANNEL=C0123456789

meow uses its **own** Slack app — not yuki-conductor's. Sharing an app token
across daemons load-balances events between sockets and drops messages.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

DEFAULT_PATH = Path.home() / ".meow" / ".env"


def env_path() -> Path:
    return Path(os.environ.get("MEOW_ENV", DEFAULT_PATH))


load_dotenv(env_path(), override=True)


@dataclass(frozen=True)
class SlackConfig:
    bot_token: str
    channel: str
    app_token: str | None = None


@dataclass(frozen=True)
class Config:
    slack: SlackConfig | None

    @classmethod
    def load(cls) -> "Config":
        bot = os.environ.get("MEOW_SLACK_BOT_TOKEN")
        channel = os.environ.get("MEOW_SLACK_CHANNEL")
        app = os.environ.get("MEOW_SLACK_APP_TOKEN") or None
        if not bot or not channel:
            return cls(slack=None)
        return cls(slack=SlackConfig(bot_token=bot, channel=channel, app_token=app))
