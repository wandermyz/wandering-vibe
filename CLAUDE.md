# wandering-vibe

A hybrid monorepo and personal assistant workspace. It contains multiple independent projects version-controlled with git, alongside personal data stored outside the repo:

- **`~/.yuki-conductor/workspace/`** — Personal tracking (memory, reminder states, cron). Lives outside the repo so it's never accidentally committed; shared with yuki-conductor.
- **`obsidian/`** — Personal notes (Obsidian vault). Gitignored.

**Personal information should never be committed to git.**

## Projects

- **[yuki-conductor](yuki-conductor/)** — Slack integration for Claude Code. **Lives in its own git repository** at [github.com/wandermyz/yuki-conductor](https://github.com/wandermyz/yuki-conductor); the local directory is gitignored from this monorepo. Run git commands inside `yuki-conductor/` to work with its history. See [yuki-conductor/CLAUDE.md](yuki-conductor/CLAUDE.md) for project-specific development reference.
- **[ai-personality](ai-personality/)** — Voice-interactive AI with a 3D animated sphere. See [ai-personality/CLAUDE.md](ai-personality/CLAUDE.md) for project-specific development reference.
- **[openclaw-control](openclaw-control/)** — Control and configuration for the local OpenClaw gateway. See [openclaw-control/CLAUDE.md](openclaw-control/CLAUDE.md) for project-specific development reference.
- **[wandering-md](wandering-md/)** — Minimal iOS app for viewing Markdown files with GitHub-style rendering. See [wandering-md/CLAUDE.md](wandering-md/CLAUDE.md) for project-specific development reference.
- **[od-notes](od-notes/)** — iOS app for browsing and editing Markdown notes from Enterprise OneDrive via File Provider. See [od-notes/CLAUDE.md](od-notes/CLAUDE.md) for project-specific development reference.
- **[nav-mcp](nav-mcp/)** — MCP server exposing Google Routes API for travel-time/distance queries from Claude Code. See [nav-mcp/README.md](nav-mcp/README.md) for setup.

Each project has its own `docs/` folder for documentation. Project plans should always be saved under `<project_dir>/docs/plans/<YYYY-MM-DD>-<plan-title>.md`.

## Memory System

Project memory is stored as plain Markdown files in `~/.yuki-conductor/workspace/memory/`. Only what is written to files persists across sessions.

### Files

- **`~/.yuki-conductor/workspace/memory/MEMORY.md`** — Long-term memory. Stores durable facts, decisions, and preferences about the project (architecture choices, recurring user preferences, important context). Updated when something worth remembering permanently comes up.
- **`~/.yuki-conductor/workspace/memory/YYYY-MM-DD.md`** — Daily logs. Append-only notes capturing what was discussed or done in a session.

### Loading Memory at Session Start

At the start of every session, always read:
1. `~/.yuki-conductor/workspace/memory/MEMORY.md` — long-term facts
2. Today's daily log: `~/.yuki-conductor/workspace/memory/YYYY-MM-DD.md` (if it exists)
3. Yesterday's daily log: `~/.yuki-conductor/workspace/memory/YYYY-MM-DD.md` (if it exists)

### Writing Memory

- **During a session**: append notable decisions, context, or facts to today's daily log.
- **Before context compaction**: flush any lasting notes to today's daily log immediately.
- **Long-term facts**: when something is durable and project-wide (a recurring user preference, an important architectural decision, a fact that would be useful in any future session), add it to `MEMORY.md`.
- **When the user says "remember this"**: write it to the appropriate file right away.

### What to Store

| Long-term (`MEMORY.md`) | Daily log (`YYYY-MM-DD.md`) |
|---|---|
| Architectural decisions | What was worked on today |
| Recurring user preferences | Decisions made this session |
| Important project context | Open questions / follow-ups |
| Key constraints or rules | Bugs found or fixed |
