"""Integration tests for CLI simulate commands."""

from unittest.mock import patch

from claude_code_slack.cli import main


def _mock_claude_run(prompt, session_id=None, timeout=None):
    from claude_code_slack.claude_runner import ClaudeResult

    if session_id:
        return ClaudeResult(text=f"Resumed: {prompt}", session_id=session_id)
    return ClaudeResult(text=f"Response: {prompt}", session_id="sess_test_123")


def test_simulate_message(tmp_path, capsys):
    db_path = tmp_path / "test.db"

    with (
        patch("claude_code_slack.claude_runner.run_claude", side_effect=_mock_claude_run),
        patch("claude_code_slack.store.DB_FILE", db_path),
    ):
        main(["simulate", "message", "What is 2+2?"])

    captured = capsys.readouterr()
    assert "Response: What is 2+2?" in captured.out
    assert "sess_test_123" in captured.out


def test_simulate_message_then_reply(tmp_path, capsys):
    db_path = tmp_path / "test.db"

    with (
        patch("claude_code_slack.claude_runner.run_claude", side_effect=_mock_claude_run),
        patch("claude_code_slack.store.DB_FILE", db_path),
    ):
        main(["simulate", "message", "Hello"])

    captured = capsys.readouterr()
    # Extract the thread_ts from output
    for line in captured.out.splitlines():
        if line.startswith("thread_ts:"):
            thread_ts = line.split(":", 1)[1].strip()
            break

    with (
        patch("claude_code_slack.claude_runner.run_claude", side_effect=_mock_claude_run),
        patch("claude_code_slack.store.DB_FILE", db_path),
    ):
        main(["simulate", "reply", thread_ts, "Follow up"])

    captured = capsys.readouterr()
    assert "Resumed: Follow up" in captured.out
