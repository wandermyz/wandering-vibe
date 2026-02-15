"""Slack Bot Socket Mode handlers."""

import logging

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from claude_code_slack.claude_runner import run_claude
from claude_code_slack.config import slack_app_token, slack_bot_token
from claude_code_slack.session_store import SessionStore

logger = logging.getLogger(__name__)

store = SessionStore()


def create_app() -> App:
    app = App(token=slack_bot_token())

    @app.event("message")
    def handle_message(event, say, client):
        # Skip bot messages, edits, and other subtypes
        if event.get("subtype"):
            return

        text = event.get("text", "").strip()
        if not text:
            return

        channel = event["channel"]
        ts = event["ts"]
        thread_ts = event.get("thread_ts")

        # Add hourglass reaction while processing
        try:
            client.reactions_add(channel=channel, name="hourglass_flowing_sand", timestamp=ts)
        except Exception:
            logger.debug("Could not add reaction", exc_info=True)

        if thread_ts:
            # Thread reply — resume session if we have one
            session_id = store.get(thread_ts)
            if session_id is None:
                # Unknown thread, ignore
                _remove_reaction(client, channel, ts)
                return
            result = run_claude(text, session_id=session_id)
            if result.session_id:
                store.set(thread_ts, result.session_id)
            say(text=result.text, thread_ts=thread_ts)
        else:
            # New top-level message — start new session
            result = run_claude(text)
            if result.session_id:
                store.set(ts, result.session_id)
            say(text=result.text, thread_ts=ts)

        _remove_reaction(client, channel, ts)

    return app


def _remove_reaction(client, channel: str, ts: str) -> None:
    try:
        client.reactions_remove(channel=channel, name="hourglass_flowing_sand", timestamp=ts)
    except Exception:
        logger.debug("Could not remove reaction", exc_info=True)


def start() -> None:
    """Start the Slack bot in Socket Mode (blocking)."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    app = create_app()
    handler = SocketModeHandler(app, slack_app_token())
    logger.info("Starting claude-code-slack in Socket Mode...")
    handler.start()
