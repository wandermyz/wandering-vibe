"""Slack Socket Mode listener for reaction-based TP/FP labeling.

Subscribes to `reaction_added` events on the Slack app. When a reaction is
added to a meow alert message:

  - :white_check_mark:  -> label TP
  - :x:                 -> label FP
  - anything else       -> ignore

Only reacts to messages whose (channel, ts) is in the pending map, so
reactions on unrelated channels/messages are silently dropped.

Also runs a startup sweep: for every pending entry, calls `reactions.get`
to catch reactions added while the daemon was offline.
"""

from __future__ import annotations

import logging
import threading

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient

from . import snippets
from .config import SlackConfig

log = logging.getLogger(__name__)

TP_EMOJI = "white_check_mark"
FP_EMOJI = "x"


def _verdict_for(emoji: str) -> str | None:
    if emoji == TP_EMOJI:
        return "tp"
    if emoji == FP_EMOJI:
        return "fp"
    return None


def _sweep_offline_reactions(client: WebClient) -> None:
    """For each pending message, ask Slack what reactions it currently has and
    apply them. Catches reactions made while the daemon was down.
    """
    pending = snippets.list_pending()
    if not pending:
        return
    log.info("reactions: sweeping %d pending message(s) for offline reactions", len(pending))
    for key in list(pending.keys()):
        channel, ts = key.split(":", 1)
        try:
            resp = client.reactions_get(channel=channel, timestamp=ts, full=True)
        except Exception as e:  # noqa: BLE001
            log.warning("reactions.get failed for %s: %s", key, e)
            continue
        message = resp.get("message") or {}
        for r in message.get("reactions") or []:
            verdict = _verdict_for(r.get("name", ""))
            if verdict is None:
                continue
            path = snippets.label(channel, ts, verdict)
            if path is not None:
                log.info("reactions(offline): labeled %s as %s", path.stem, verdict)
            break  # one verdict is enough


def start(cfg: SlackConfig) -> None:
    """Start the Socket Mode listener in a background thread. No-op if
    `cfg.app_token` is unset.
    """
    if not cfg.app_token:
        log.info("reactions: app_token not configured; skipping listener")
        return

    app = App(token=cfg.bot_token)
    # Quiet "Unhandled request" warnings — this app handles only reaction_added.
    logging.getLogger("slack_bolt.App").setLevel(logging.ERROR)

    @app.event("reaction_added")
    def on_reaction(event, logger):  # noqa: ARG001 — bolt requires this shape
        verdict = _verdict_for(event.get("reaction", ""))
        if verdict is None:
            return
        item = event.get("item") or {}
        if item.get("type") != "message":
            return
        channel = item.get("channel")
        ts = item.get("ts")
        if not channel or not ts:
            return
        path = snippets.label(channel, ts, verdict)
        if path is not None:
            log.info("reactions: labeled %s as %s", path.stem, verdict)

    # Catch any reactions added while we were offline.
    try:
        _sweep_offline_reactions(app.client)
    except Exception as e:  # noqa: BLE001
        log.warning("reactions: offline sweep failed: %s", e)

    handler = SocketModeHandler(app, cfg.app_token)

    def _run() -> None:
        try:
            log.info("reactions: starting Socket Mode listener")
            handler.start()
        except Exception as e:  # noqa: BLE001
            log.warning("reactions: listener crashed: %s", e)

    t = threading.Thread(target=_run, name="meow-slack-reactions", daemon=True)
    t.start()
