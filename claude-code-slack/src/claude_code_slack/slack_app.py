"""Slack Bot Socket Mode handlers."""

import logging
import re
import subprocess
import urllib.request

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from claude_code_slack.claude_runner import run_claude
from claude_code_slack.config import (
    ATTACHMENTS_DIR,
    UPLOADS_DIR,
    CLAUDE_WORKING_DIR,
    slack_app_dm_channel,
    slack_app_token,
    slack_bot_token,
)
from claude_code_slack.cron_scheduler import start_cron_scheduler
from claude_code_slack.store import VALID_MODELS, ModelStore, SessionStore
from claude_code_slack.web_server import start_web_server

logger = logging.getLogger(__name__)

store = SessionStore()
model_store = ModelStore()

_ATTACHMENT_RE = re.compile(r"<attachment>(.*?)</attachment>")


def _download_slack_files(files: list[dict], bot_token: str) -> list[str]:
    """Download Slack file attachments to the uploads directory.

    Returns a list of saved file paths.
    """
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    saved: list[str] = []
    for f in files:
        url = f.get("url_private_download") or f.get("url_private")
        if not url:
            continue
        name = f.get("name", "unknown")
        dest = UPLOADS_DIR / name
        # Deduplicate filenames
        if dest.exists():
            from pathlib import Path
            base_stem = Path(name).stem
            suffix = Path(name).suffix
            counter = 1
            while dest.exists():
                dest = UPLOADS_DIR / f"{base_stem}_{counter}{suffix}"
                counter += 1
        try:
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {bot_token}"})
            with urllib.request.urlopen(req) as resp, open(dest, "wb") as out:
                out.write(resp.read())
            saved.append(str(dest))
            logger.info(f"Downloaded Slack file {name} -> {dest}")
        except Exception:
            logger.error(f"Failed to download Slack file {name}", exc_info=True)
    return saved


def _extract_and_upload_attachments(text: str, client, channel: str, thread_ts: str) -> str:
    """Find <attachment>filename</attachment> tags in text, upload the files, and strip the tags."""
    matches = _ATTACHMENT_RE.findall(text)
    if not matches:
        return text

    for filename in matches:
        filepath = ATTACHMENTS_DIR / filename
        if not filepath.exists():
            logger.warning(f"Attachment file not found: {filepath}")
            continue
        try:
            client.files_upload_v2(
                channel=channel,
                thread_ts=thread_ts,
                file=str(filepath),
                filename=filename,
            )
            logger.info(f"Uploaded attachment {filepath} to channel={channel}")
        except Exception:
            logger.error(f"Failed to upload attachment {filepath}", exc_info=True)

    # Strip attachment tags from the message text
    return _ATTACHMENT_RE.sub("", text).strip()


def create_app() -> App:
    app = App(token=slack_bot_token())

    @app.command("/yuki-model")
    def handle_model_command(ack, command, respond):
        ack()
        channel = command["channel_id"]
        arg = command.get("text", "").strip().lower()

        if not arg:
            current = model_store.get(channel) or "default (set by CLI)"
            models_list = ", ".join(sorted(VALID_MODELS))
            respond(f"Current model: *{current}*\nUsage: `/yuki-model [{models_list}]`")
            return

        if arg not in VALID_MODELS:
            models_list = ", ".join(sorted(VALID_MODELS))
            respond(f"Unknown model `{arg}`. Valid options: {models_list}")
            return

        model_store.set(channel, arg)
        respond(f"Model switched to *{arg}* for this channel.")

    @app.command("/yuki-title")
    def handle_title_command(ack, command, respond):
        """Rename the title of a conversation thread."""
        ack()
        respond("Reply with `!title <new title>` in a thread to rename it.")

    @app.command("/yuki-usage")
    def handle_usage_command(ack, command, respond):
        """Run `claude --stats` to show current usage and limits."""
        ack()
        respond("Fetching usage stats...")
        try:
            proc = subprocess.run(
                ["claude", "--stats"],
                capture_output=True,
                text=True,
                timeout=30,
                cwd=CLAUDE_WORKING_DIR,
            )
            output = (proc.stdout or "").strip()
            err = (proc.stderr or "").strip()
            if proc.returncode != 0:
                respond(f"```\n{err or output or 'claude --stats failed'}\n```")
            elif output:
                respond(f"```\n{output}\n```")
            else:
                respond("No output from `claude --stats`.")
        except subprocess.TimeoutExpired:
            respond("Timed out running `claude --stats`.")
        except FileNotFoundError:
            respond("`claude` CLI not found.")

    @app.command(re.compile(r"/yuki-.+"))
    def handle_skill_command(ack, command, respond, client):
        """Catch-all: map /yuki-<skill> to Claude's /<skill>."""
        ack()
        skill_name = command["command"].removeprefix("/yuki-")
        channel = command["channel_id"]
        arg = command.get("text", "").strip()
        prompt = f"/{skill_name} {arg}" if arg else f"/{skill_name}"
        model = model_store.get(channel)

        respond(f"Running `/{skill_name}`...")
        result = run_claude(prompt, model=model)

        response_text = _extract_and_upload_attachments(result.text, client, channel, None)
        if response_text:
            respond(response_text)

    @app.event("message")
    def handle_message(event, say, client):
        # Skip bot messages, edits, and other subtypes (but allow file_share)
        subtype = event.get("subtype")
        if subtype and subtype != "file_share":
            return

        text = event.get("text", "").strip()
        files = event.get("files", [])
        if not text and not files:
            return

        channel = event["channel"]
        ts = event["ts"]
        thread_ts = event.get("thread_ts")
        model = model_store.get(channel)
        logger.info(f"Received message in channel={channel}, channel_type={event.get('channel_type')}, ts={ts}")

        # Handle !title command in threads
        if thread_ts and text.startswith("!title "):
            new_title = text[len("!title "):].strip()
            if new_title and store.get(thread_ts):
                store.set_title(thread_ts, new_title)
                say(text=f"Title set to: *{new_title}*", thread_ts=thread_ts)
            else:
                say(text="No session found for this thread.", thread_ts=thread_ts)
            return

        # Download any Slack file attachments and prefix the prompt
        if files:
            saved_paths = _download_slack_files(files, slack_bot_token())
            attachment_prefix = "".join(f"<attachment>{p}</attachment>\n" for p in saved_paths)
            text = attachment_prefix + text

        if not text.strip():
            return

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
            result = run_claude(text, session_id=session_id, model=model)
            if result.session_id:
                store.set(thread_ts, result.session_id, channel_id=channel)
            reply_ts = thread_ts
        else:
            # New top-level message — start new session
            result = run_claude(text, model=model)
            if result.session_id:
                # Use the original message text (without attachment prefixes) as title
                raw_text = event.get("text", "").strip()
                store.set(ts, result.session_id, channel_id=channel, title=raw_text)
            reply_ts = ts

        # Extract <attachment> tags and upload files, then post the text
        response_text = _extract_and_upload_attachments(result.text, client, channel, reply_ts)
        logger.info(f"Posting reply to channel={channel}, thread_ts={reply_ts}")
        if response_text:
            say(text=response_text, thread_ts=reply_ts)

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

    # Start web server (background thread)
    start_web_server()

    # Start cron scheduler with the Slack Web API client
    start_cron_scheduler(app.client)

    handler = SocketModeHandler(app, slack_app_token())
    logger.info("Starting claude-code-slack in Socket Mode...")

    # Notify the app DM channel that the daemon has (re)started
    try:
        commit = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=CLAUDE_WORKING_DIR, capture_output=True, text=True,
        ).stdout.strip() or "unknown"
        app.client.chat_postMessage(
            channel=slack_app_dm_channel(),
            text=f":arrows_counterclockwise: claude-code-slack daemon restarted (commit `{commit}`).",
        )
    except Exception:
        logger.warning("Failed to send restart notification", exc_info=True)

    handler.start()
