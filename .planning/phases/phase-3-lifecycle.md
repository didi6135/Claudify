# Phase 3 — Lifecycle

**Status:** in progress (started 2026-04-23)
**Goal:** Claudify is safe to run for months, not just install once. Clean
uninstall, in-place updates that preserve state, backup/restore for
server migrations.

Language choice for this phase: **bash for small things (uninstall),
TypeScript-via-Bun for anything bigger.** Per ADR 0005.

---

## End-state target

```bash
# Safe uninstall — leaves Claude Code itself, removes only Claudify
curl -fsSL .../uninstall.sh | bash

# Update without losing state (OAuth token + bot token + allowlist preserved)
curl -fsSL .../update.sh | bash

# Backup everything Claudify owns to a tarball
bash update.sh --backup    # (or separate backup.sh)

# Restore from a tarball onto a fresh server
bash restore.sh ./claudify-backup-2026-04-30.tar.gz
```

---

## Tasks

Ordered small → large. Don't start the next until the previous is
merged and tested on Station11.

### 3.1 — `uninstall.sh` (bash, ~30 min)

**Goal:** one command cleanly removes everything Claudify installed,
leaving the system exactly as it was before (minus whatever the
operator added outside Claudify's scope).

**Scope:**
- Stop + disable systemd service
- Remove `~/.config/systemd/user/claude-telegram.service`
- `rm -rf ~/.claudify/` (all per-bot state)
- `systemctl --user daemon-reload`
- Print a summary of what was removed

**Explicitly NOT removed** (the operator may have other uses):
- `~/.claude/` (Claude Code's user-wide state — plugins cache, settings)
- `~/.claude.json` (Claude Code's onboarding state)
- `~/.bun/` (Bun runtime — also useful for other things)
- `~/.npm-global/` (npm prefix — may have other globals)
- Linger for the user (rarely wants to flip back off)

Each exclusion gets a line in the summary output so the operator sees
what's left and can decide to remove it manually.

**Delivery:**
- `uninstall.sh` at repo root, committable
- Curl URL works: `bash <(curl -fsSL .../uninstall.sh)`
- Mentioned in README under "Uninstall"

### 3.2 — `update.sh` + `install.sh --preserve-state` flag (bash, ~1–2 hrs)

**Goal:** pull the latest `install.sh` from main and re-run in a mode
that keeps existing `credentials.env`, `telegram/.env`, and
`telegram/access.json`. Only the systemd unit, claude/plugin binaries,
and `~/.claude.json` seed get refreshed.

**Scope:**
- New flag on `install.sh`: `--preserve-state`
  - Behaves like normal install, but:
    - `credentials.env`, `telegram/.env`, `telegram/access.json` are
      preserved if present (no rewrite even if env vars differ)
    - `oauth_setup` skipped entirely if credentials.env exists
    - `write_service` still rewrites the unit (so unit changes land)
    - `seed_claude_state` still runs (harmless no-op when already seeded)
- `update.sh` at repo root: fetches latest `dist/install.sh`, invokes
  with `--preserve-state --non-interactive`
- Target: 10–20 seconds total on a healthy install

**Delivery:**
- Curl URL for `update.sh`
- Tested: deliberately modify a file, run update, confirm state preserved

### 3.3 — Seed starter `CLAUDE.md` persona (bash, ~30 min)

> *Note:* This is technically a Phase 4 (Capabilities) item, pulled
> forward because it's small and makes the bot feel personal. It's what
> turns generic Claude into *"my* Claude."

**Goal:** after install, `~/.claudify/workspace/CLAUDE.md` exists with
a starter persona the operator can edit. Claude reads it on every
session start (that's how Claude Code's `--add-dir` and CWD-based
CLAUDE.md discovery works).

**Scope:**
- New step in `install.sh` after `write_service`: writes
  `~/.claudify/workspace/CLAUDE.md` **only if it doesn't already exist**
  (idempotent; never clobbers operator edits)
- Default contents: minimal skeleton with TODO-style placeholders for
  name, language preference, timezone, response-style guidance
- Over time, the skeleton can absorb fields from `who-am-i.md`

**Delivery:**
- Tested: after install, bot replies in a style that matches the seed
- Operator can edit `~/.claudify/workspace/CLAUDE.md` and see behavior change on next message

### 3.4 — `backup.sh` + `restore.sh` (bash, ~2 hrs)

**Goal:** serialize everything Claudify state into a single tarball
that can be dropped onto a fresh server to re-spawn the bot.

**Scope:**
- `backup.sh`: tar `~/.claudify/` + the systemd unit file + the
  relevant `~/.claude.json` trust entry → `claudify-backup-<host>-<timestamp>.tar.gz`
- `restore.sh <tarball>`: untar in the right places, `daemon-reload`,
  start service, run doctor
- Both scripts: `--to <dir>` / `--from <dir>` for non-interactive use

**Delivery:**
- Round-trip tested: backup on Station11 → restore on a fresh VPS (or
  simulated via scrub-then-restore on Station11)
- doctor reports 28 green after restore

### 3.5 — Update README + ROADMAP after each task lands

Keeps docs in sync rather than all at once at the end of the phase.

---

## Acceptance criteria

Phase 3 is **done** when:
- [ ] `uninstall.sh` removes Claudify state cleanly and reports what was kept
- [ ] `update.sh` upgrades an install in <20s without re-OAuth
- [ ] `CLAUDE.md` lives in `~/.claudify/workspace/`, persists across updates, demonstrably changes bot behavior
- [ ] `backup.sh` produces a tarball; `restore.sh` rehydrates it on a fresh server; doctor passes
- [ ] All four scripts ship with a curl-one-liner documented in README
- [ ] `phase-3-lifecycle.md` updated with status markers as tasks close

---

## Out of scope for Phase 3

- Gmail / Calendar / Drive MCPs (Phase 4)
- Multi-workspace support (Phase 4)
- Cost ceiling, audit log, health check endpoint (Phase 5)
- Migration of any existing `update.sh` / `backup.sh` to TypeScript
  (deferred to whenever the scripts outgrow bash comfortably)
