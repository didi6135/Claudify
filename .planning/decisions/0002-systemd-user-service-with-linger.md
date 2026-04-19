# ADR 0002: systemd user service with linger

**Status:** Accepted
**Date:** 2026-04-19

## Context

The Claude+Telegram bot must run continuously on the target server:
- Survive operator SSH disconnect (the operator is not always logged in)
- Survive server reboot
- Auto-restart on crash
- Stream logs somewhere we can inspect later

The server is a typical headless Linux VPS with systemd. We need to
choose how the bot process is supervised.

## Decision

Run the bot as a **systemd user service** (`~/.config/systemd/user/claude-telegram.service`)
with **linger enabled** for the operator account.

`linger` keeps the user's systemd instance alive even when no SSH session
exists. Without it, the service would die the moment the operator logs out.

Linger requires `sudo loginctl enable-linger <user>` once. The installer
prompts for sudo natively in the terminal and runs this if it isn't
already enabled.

## Consequences

- **Good:**
  - systemd is universal on modern Linux — no extra dependency
  - Auto-restart, log rotation via `journalctl`, native dependency ordering
  - Service runs as the operator user — no root daemon, no privilege creep
  - Per-user filesystem layout (`~/.claude/...`) Just Works

- **Bad:**
  - One-time sudo prompt during first install (linger). Acceptable cost.
  - User-level systemd is slightly less familiar than system-level, so docs
    must spell out `systemctl --user` and `journalctl --user`

- **Ugly:**
  - Without linger, the service appears to start in the install session
    and silently dies on disconnect. We must detect this and refuse to
    proceed unless linger is enabled (see Phase 1 task 1.B.4).

## Alternatives considered

- **System-level systemd unit** (`/etc/systemd/system/...`) — Rejected.
  Requires sudo for every operation (start, stop, status, logs). Runs as
  root unless we add user-switching boilerplate. Worse fit for a
  single-user assistant.
- **PM2** — Rejected. Adds a Node dependency to manage; gives auto-restart
  but no native reboot survival without extra setup; introduces a second
  process supervisor on a system that already has one.
- **tmux/screen detached session** — Rejected. No reboot survival, no
  auto-restart, no structured logs. Fine for ad-hoc but not production.
- **`nohup ... &`** — Rejected for the same reasons as tmux, plus no
  service abstraction at all.
- **Docker** — Rejected. Heavyweight for what is essentially "run a
  Node process forever." Forces a docker daemon, image build/pull,
  bind-mount semantics for `~/.claude/`, and an extra layer between the
  user and their bot. Considered for Phase 5 if isolation becomes a
  real concern.
