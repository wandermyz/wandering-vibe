"""Config loaded from ~/.yuki-conductor/workspace/meow/config.toml.

Override the path with the MEOW_CONFIG environment variable.

Schema:

    [slack]
    bot_token = "xoxb-..."
    channel   = "C0123456789"
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PATH = Path.home() / ".yuki-conductor" / "workspace" / "meow" / "config.toml"


def config_path() -> Path:
    return Path(os.environ.get("MEOW_CONFIG", DEFAULT_PATH))


@dataclass(frozen=True)
class SlackConfig:
    bot_token: str
    channel: str


@dataclass(frozen=True)
class Config:
    slack: SlackConfig | None

    @classmethod
    def load(cls) -> "Config":
        path = config_path()
        if not path.exists():
            return cls(slack=None)
        with open(path, "rb") as f:
            data = tomllib.load(f)
        slack = None
        if "slack" in data:
            s = data["slack"]
            slack = SlackConfig(bot_token=s["bot_token"], channel=s["channel"])
        return cls(slack=slack)
