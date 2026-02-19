# openclaw-control

Control and configuration helpers for the local OpenClaw gateway.

## What is OpenClaw

OpenClaw is a self-hosted gateway that bridges messaging platforms (Slack, WhatsApp, iMessage, Telegram, Discord) to AI coding agents. It runs as a local daemon (`ai.openclaw.gateway` via launchd).

- **Docs**: https://docs.openclaw.ai
- **Quickstart**: https://docs.openclaw.ai/start/quickstart

## Key Paths

| Path | Description |
|---|---|
| `~/.openclaw/openclaw.json` | Main configuration (channels, agents, models, gateway settings) |
| `~/.openclaw/credentials/` | API keys and secrets |
| `~/.openclaw/workspace/` | Agent workspace (IDENTITY.md, SOUL.md, TOOLS.md, etc.) |
| `~/.openclaw/logs/gateway.log` | Gateway stdout log |
| `~/.openclaw/logs/gateway.err.log` | Gateway stderr log |
| `~/.openclaw/cron/jobs.json` | Scheduled jobs |
| `~/.openclaw/devices/paired.json` | Paired mobile/remote devices |
| `~/.openclaw/exec-approvals.json` | Exec approval settings |

## Gateway Management

```bash
# Check health
openclaw health

# View status (channel health + recent sessions)
openclaw status

# Stop the gateway
openclaw gateway stop

# Start the gateway (launchd will also auto-restart)
openclaw gateway

# Restart (stop then start)
openclaw gateway stop && openclaw gateway

# Launchd direct control
launchctl bootout gui/$UID/ai.openclaw.gateway   # stop
launchctl bootstrap gui/$UID <plist-path>         # start

# View logs
openclaw logs

# Health checks and quick fixes
openclaw doctor
```

## Common CLI Commands

```bash
# Configuration
openclaw config get <key>          # Read a config value
openclaw config set <key> <value>  # Set a config value
openclaw config unset <key>        # Remove a config value
openclaw configure                 # Interactive setup wizard

# Channels
openclaw channels login            # Pair a messaging channel
openclaw status                    # Channel health overview

# Agents
openclaw agents                    # Manage agent workspaces/routing
openclaw sessions                  # List conversation sessions

# Models
openclaw models                    # Model configuration

# Skills & Plugins
openclaw skills                    # Manage skills (image gen, whisper, etc.)
openclaw plugins                   # Manage channel plugins

# Devices
openclaw devices                   # Device pairing and tokens

# Cron
openclaw cron                      # Scheduled job management

# Maintenance
openclaw doctor                    # Health checks + fixes
openclaw update                    # CLI update helpers
openclaw dashboard                 # Open the web Control UI
```

## Current Configuration Summary

- **Gateway port**: 18372 (loopback only, token auth)
- **Default agent model**: `minimax/MiniMax-M2.5`
- **Configured channels**: Slack (socket mode, enabled), iMessage (disabled)
- **Installed skills**: openai-image-gen, openai-whisper-api, notion
- **Max concurrent agents**: 4 (subagents: 8)
- **Heartbeat**: every 30 minutes
