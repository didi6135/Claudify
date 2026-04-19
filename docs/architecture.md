# Architecture

How Claudify runs on your server.

## High level

```
        ┌────────────────────────┐
        │  Your phone / desktop  │
        │       Telegram         │
        └───────────┬────────────┘
                    │  bot polling (HTTPS)
                    ▼
   ┌───────────────────────────────────┐
   │       Your Linux server           │
   │                                   │
   │   systemd --user                  │
   │   └─ claude-telegram.service      │
   │      └─ claude --channels         │
   │            plugin:telegram@…      │
   │            (Claude Code CLI)      │
   │                                   │
   │   ~/.claude/                      │
   │   ├─ channels/telegram/.env       │
   │   ├─ channels/telegram/access.json│
   │   ├─ memory/                      │
   │   └─ ...                          │
   └───────────────────────────────────┘
```

## What runs

| Component | Where | Purpose |
|---|---|---|
| **Claude Code CLI** | `npm -g @anthropic-ai/claude-code` | The brains. Talks to Claude using your subscription's OAuth token. |
| **Telegram channel plugin** | `claude plugin install telegram@claude-plugins-official` | Bridges the bot's Telegram messages into Claude Code's `--channels` mode. |
| **systemd user service** | `~/.config/systemd/user/claude-telegram.service` | Keeps the process alive across reboots, crashes, and SSH disconnects. |
| **`linger` for the user** | systemd state | Lets your user-level systemd run without an active SSH session. |

## What lives where on the server

| Path | What |
|---|---|
| `~/.claude/channels/telegram/.env` | Bot token (`chmod 600`) |
| `~/.claude/channels/telegram/access.json` | Allowlist of Telegram user IDs |
| `~/.claude/memory/` | Claude's persistent notes about you |
| `~/workspace/<workspace-name>/` | Working directory for the bot's Claude Code session |
| `~/.config/systemd/user/claude-telegram.service` | The service unit file |
| `/tmp/claudify-install-*.log` | Install-time logs |
| `journalctl --user -u claude-telegram` | Runtime logs |

## Why systemd user (not system)

See [ADR 0002](../.planning/decisions/0002-systemd-user-service-with-linger.md).
TL;DR — keeps the bot under your user, no root daemon, native
auto-restart and log rotation.

## Why subscription OAuth (not API key)

See [ADR 0003](../.planning/decisions/0003-oauth-not-apikey.md). TL;DR —
your subscription is the cost ceiling.

## Lifecycle

- **First install:** ~3 minutes. One sudo prompt (linger), one OAuth
  pause (`claude setup-token`).
- **Re-install:** under 60 seconds. No sudo, no OAuth, no destructive
  overwrites of your config.
- **Updates:** re-run the installer (or wait for `update.sh` in Phase 3).
- **Stop:** `systemctl --user stop claude-telegram`.
- **Start:** `systemctl --user start claude-telegram`.
- **Logs:** `journalctl --user -u claude-telegram -f`.
