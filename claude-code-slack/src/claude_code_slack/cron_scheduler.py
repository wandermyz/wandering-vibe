"""Cron scheduler that reads tasks from workspace YAML and triggers Claude runs."""

import logging
import threading
from dataclasses import dataclass
from datetime import datetime

import yaml
from croniter import croniter

from claude_code_slack.claude_runner import run_claude
from claude_code_slack.config import CRON_FILE, WORKSPACE_DIR, slack_cron_channel
from claude_code_slack.session_store import SessionStore

logger = logging.getLogger(__name__)

store = SessionStore()


@dataclass
class CronTask:
    name: str
    schedule: str
    description: str
    prompt: str


def _ensure_workspace() -> None:
    """Create the workspace directory if it doesn't exist."""
    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
    logger.info(f"Workspace directory ensured at {WORKSPACE_DIR}")


def _load_cron_tasks() -> list[CronTask]:
    """Load cron tasks from the workspace YAML file."""
    if not CRON_FILE.exists():
        logger.info(f"No cron file found at {CRON_FILE}, skipping cron scheduling")
        return []

    with open(CRON_FILE) as f:
        data = yaml.safe_load(f)

    if not data or "tasks" not in data:
        logger.warning(f"Cron file {CRON_FILE} has no 'tasks' key")
        return []

    tasks = []
    for entry in data["tasks"]:
        try:
            task = CronTask(
                name=entry["name"],
                schedule=entry["schedule"],
                description=entry.get("description", ""),
                prompt=entry["prompt"],
            )
            # Validate cron expression
            croniter(task.schedule)
            tasks.append(task)
        except (KeyError, ValueError) as e:
            logger.error(f"Invalid cron task entry: {entry} — {e}")

    logger.info(f"Loaded {len(tasks)} cron task(s) from {CRON_FILE}")
    return tasks


def _run_cron_task(task: CronTask, slack_client) -> None:
    """Execute a single cron task: post to Slack, run Claude, post result."""
    channel = slack_cron_channel()

    # Post initial message to start a new thread
    header = f":alarm_clock: *Cron: {task.description or task.name}*\n> Running: `{task.prompt[:200]}`"
    try:
        response = slack_client.chat_postMessage(channel=channel, text=header)
        thread_ts = response["ts"]
    except Exception:
        logger.error(f"Failed to post cron start message for task={task.name}", exc_info=True)
        return

    # Run Claude with the cron prompt
    result = run_claude(task.prompt)

    # Store session for potential follow-up in the thread
    if result.session_id:
        store.set(thread_ts, result.session_id)

    # Post the result as a thread reply
    try:
        slack_client.chat_postMessage(channel=channel, text=result.text, thread_ts=thread_ts)
    except Exception:
        logger.error(f"Failed to post cron result for task={task.name}", exc_info=True)


def _scheduler_loop(tasks: list[CronTask], slack_client, stop_event: threading.Event) -> None:
    """Main loop that checks cron schedules and fires tasks."""
    # Build croniter instances with the current time as base
    iters = [(task, croniter(task.schedule, datetime.now())) for task in tasks]
    # Pre-compute next fire times
    next_times = {task.name: it.get_next(datetime) for task, it in iters}

    while not stop_event.is_set():
        now = datetime.now()
        for task, it in iters:
            fire_at = next_times[task.name]
            if now >= fire_at:
                logger.info(f"Cron firing task={task.name} (scheduled={fire_at})")
                # Run in a separate thread so we don't block other cron tasks
                threading.Thread(
                    target=_run_cron_task,
                    args=(task, slack_client),
                    name=f"cron-{task.name}",
                    daemon=True,
                ).start()
                next_times[task.name] = it.get_next(datetime)

        # Sleep for a short interval before checking again
        stop_event.wait(timeout=30)


def start_cron_scheduler(slack_client) -> threading.Event | None:
    """Initialize workspace, load cron tasks, and start the scheduler thread.

    Returns a stop_event that can be set to stop the scheduler, or None if
    no cron tasks were found.
    """
    _ensure_workspace()
    tasks = _load_cron_tasks()
    if not tasks:
        return None

    stop_event = threading.Event()
    thread = threading.Thread(
        target=_scheduler_loop,
        args=(tasks, slack_client, stop_event),
        name="cron-scheduler",
        daemon=True,
    )
    thread.start()
    logger.info("Cron scheduler started")
    return stop_event
