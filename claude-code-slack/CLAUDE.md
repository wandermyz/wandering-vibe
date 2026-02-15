# claude-code-slack Development Reference

## Project Structure

```
src/claude_code_slack/
  cli.py          — argparse entry point (run, daemon, simulate)
  config.py       — env loading, path constants
  session_store.py — thread-safe JSON session store
  claude_runner.py — subprocess wrapper for claude CLI
  slack_app.py    — slack-bolt Socket Mode handlers
  daemon.py       — macOS LaunchAgent management
```

## Key Commands

- `uv run pytest` — run all tests
- `uv run claude-code-slack --help` — show CLI help
- `uv run claude-code-slack simulate message "test"` — test without Slack

## Architecture

- **Session tracking**: JSON file at `~/.claude-code-slack/sessions.json` maps `thread_ts → session_id`
- **Concurrency**: slack-bolt's default thread pool (10 threads); each handler blocks on `subprocess.run`
- **Claude invocation**: `claude -p --dangerously-skip-permissions --output-format json [-r session_id] "prompt"`
- **Environment**: Must unset `CLAUDECODE` env var in subprocess to avoid nested session errors

## Testing

- `test_session_store.py` — unit tests for JSON store (roundtrip, concurrent access)
- `test_claude_runner.py` — mocked subprocess tests (flag construction, errors, timeouts)
- `test_cli_simulate.py` — integration tests via simulate commands
