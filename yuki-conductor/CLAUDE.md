# yuki-conductor Development Reference

## Project Structure

```
src/yuki_conductor/
  cli.py            — argparse entry point (run, daemon, simulate)
  config.py         — env loading, path constants
  store.py          — SQLite-backed session & model stores
  claude_runner.py  — subprocess wrapper for claude CLI
  slack_app.py      — slack-bolt Socket Mode handlers
  cron_scheduler.py — cron task scheduler (reads workspace/cron.yaml)
  daemon.py         — macOS LaunchAgent management
  web_server.py     — FastAPI HTTP server (agent conductor web UI)
web/                — React + Vite frontend (pnpm, TypeScript)
```

## Workspace

The personal workspace directory is `workspace/`. This is the place to store all personal information such as cron task definitions, personal notes, and any data that should persist across sessions. **Do not include any personal information in the repo itself** — anything in the repo can end up in git.

Key workspace files:
- `workspace/yuki-conductor.db` — SQLite database for session and model tracking
- `workspace/cron.yaml` — Cron task definitions (see `cron.example.yaml` for format)

## Cron Scheduler

The daemon supports scheduled tasks via `workspace/cron.yaml`. Each task specifies a cron expression, a description, and a Claude prompt. When the cron fires, it posts a new thread in the configured `SLACK_CRON_CHANNEL` and runs Claude Code with the prompt, posting the result as a thread reply. The thread is session-tracked, so follow-up replies in that thread continue the conversation.

Required env var: `SLACK_CRON_CHANNEL` — the Slack channel ID to post cron results to.

## Key Commands

- `uv run pytest` — run all tests
- `uv run yuki-conductor --help` — show CLI help
- `uv run yuki-conductor simulate message "test"` — test without Slack
- `cd web && pnpm dev` — start frontend dev server (proxies /api to port 2333)
- `cd web && pnpm build` — build frontend for production (output: web/dist/)

## Architecture

- **Session tracking**: SQLite database at `workspace/yuki-conductor.db` maps `thread_ts → (session_id, channel_id)` and `channel_id → model`
- **Web server**: FastAPI on port 2333 (env: `WEB_PORT`), serves React frontend and `/api/sessions` endpoint. Starts in a daemon thread alongside Slack Socket Mode.
- **Concurrency**: slack-bolt's default thread pool (10 threads); each handler blocks on `subprocess.run`
- **Claude invocation**: `claude -p --dangerously-skip-permissions --output-format json [-r session_id] "prompt"`
- **Environment**: Must unset `CLAUDECODE` env var in subprocess to avoid nested session errors

## Testing

- `test_store.py` — unit tests for SQLite store (roundtrip, concurrent access, separate tables)
- `test_claude_runner.py` — mocked subprocess tests (flag construction, errors, timeouts)
- `test_cli_simulate.py` — integration tests via simulate commands
