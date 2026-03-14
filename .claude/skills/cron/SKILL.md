---
name: cron
description: >
  Manage personal cron tasks and reminders. Use when the user says "cron",
  "remind me", "schedule", "recurring", or wants to add, edit, list, or remove
  a scheduled task.
argument-hint: "[what to schedule]"
allowed-tools: Read, Write, Edit, Bash
---

# Cron Task Manager

Cron tasks are defined in `workspace/cron.yaml` and run automatically
by the claude-code-slack daemon. Changes take effect within 30 seconds — no
restart needed.

## List current tasks

Read the file and show all tasks with their schedule and description:

```bash
cat workspace/cron.yaml
```

## Add or edit a task

Edit `workspace/cron.yaml`. Each task has:

```yaml
tasks:
  - name: unique-task-name          # identifier, no spaces
    schedule: "0 9 * * 1-5"        # cron expression
    description: "Human label"      # shown in Slack when it fires
    prompt: >                       # what Claude Code will be asked to do
      Your prompt here.
```

### Common schedule expressions

| Schedule | Expression |
|---|---|
| Every minute | `* * * * *` |
| Every hour | `0 * * * *` |
| Daily at 9am | `0 9 * * *` |
| Weekdays at 9am | `0 9 * * 1-5` |
| Mondays at 10am | `0 10 * * 1` |
| Every 30 minutes | `*/30 * * * *` |

Format: `minute hour day-of-month month day-of-week`

## Remove a task

Delete the task's entry from `workspace/cron.yaml`.

## State tracking

For tasks that need to persist state between runs (e.g. "already done this month"), write
Markdown files (`.md`) into the `workspace/` directory. Example:

```
workspace/invoice_reminder_state.md
workspace/concert_check_state.md
```

Use plain Markdown with a short human-readable summary. Claude can read and overwrite
these files on each run to detect changes.

## How it works

When a cron fires, the daemon:
1. Runs Claude Code with the prompt
2. Posts Claude's response directly to the configured cron channel
3. The message is session-tracked — you can reply in a thread to continue the conversation

## User request: $ARGUMENTS

Help the user with the above. If they want to add or modify a task, read the
current `workspace/cron.yaml` first, then make the change with Edit or
Write. Show them the final cron expression and confirm what it means in plain
English.
