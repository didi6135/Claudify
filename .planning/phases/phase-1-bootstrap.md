# Phase 1 — Bootstrap `install.sh`

**Status:** ✅ **Done** (closed 2026-04-21)
**Goal:** one curl command, run on the target server, takes Ubuntu/Debian
to a running Claude+Telegram assistant in under 3 minutes.

## Closed 2026-04-21

End-to-end success on Station11: operator runs one curl command, sees
the bot go live in ~60 seconds (subsequent runs, token cached). Every
acceptance criterion below passed. `doctor.sh` reports 28/28 green on a
working install.

Decisions during Phase 1 captured in ADRs 0001–0005. Outstanding
upstream UX asks filed in [upstream-wishlist.md](../upstream-wishlist.md).

---

## End-state target

```bash
ssh you@your-server.com
curl -fsSL https://claudify.sh/install | bash
# (one sudo prompt for linger, one OAuth pause for Claude — that's it)
# < 3 minutes later: bot is alive
```

Subsequent re-runs of the same command are safe and complete in
< 60 seconds (no auth pause, no sudo, no destructive overwrites).

## Context — what changed from the original plan

The original Phase 1 was "fix the bugs in `deploy.sh`." But `deploy.sh`
implements the *wrong model* — operator-side SSH push from a laptop. We
pivoted to the standard self-hosted-tool install pattern (`curl … | bash`
on the target). See ADR 0004 for the decision.

This means Phase 1 is no longer a refactor. It's **a fresh build of
`install.sh`** with all the quality concerns from the original Phase 1
baked in from line one. `deploy.sh` was removed; git history preserves
it if anyone needs to look back.

---

## Tasks

Grouped into three sub-phases. Within each group, tasks can be tackled
in any order; between groups, do them in sequence.

### 1.A — Foundation (do first)

**1.A.1 — Folder structure**
Create the agreed structure: `bin/` (or single `install.sh` for now),
`lib/`, `remote/`, `templates/`, `docs/`, `.planning/decisions/`. Add a
short README in each folder explaining what belongs there.

**1.A.2 — Conventions doc**
Write `.planning/conventions.md` covering: bash file headers, naming,
error handling, logging, ADR format, how to add a Phase task.

**1.A.3 — ADRs for decisions already made**
- `0001-bash-as-implementation-language.md`
- `0002-systemd-user-service-with-linger.md`
- `0003-oauth-not-apikey.md`
- `0004-target-side-curl-install-not-operator-push.md`

**1.A.4 — Remove `deploy.sh`**
Delete it from the working tree. Git history preserves it if needed.
(Decided 2026-04-19: keep the working tree focused on the new model.)

### 1.B — Install logic (do after 1.A)

**1.B.1 — `install.sh` skeleton**
Header comment, `set -euo pipefail`, color helpers, `step/ok/warn/fail`,
log file (tee to `/tmp/claudify-install-<timestamp>.log`), `--dry-run`
flag.

**1.B.2 — Stdin handling for `curl | bash`**
When piped from curl, stdin is the script — `read` won't work. Detect
this and read prompts from `/dev/tty` instead. Fail clearly if no TTY
and required values not in env.

**1.B.3 — Preflight checks**
- OS detection (Ubuntu/Debian supported; warn on others)
- node + npm present (fail loudly with install instructions if not)
- `script` binary present (`util-linux`)
- linger state (auto-handle in 1.B.4)
- internet connectivity to npm + bun.sh + telegram

**1.B.4 — Inline linger handling**
Detect via `loginctl show-user "$USER" | grep -q Linger=yes`. If
missing, prompt the user (`Continue? [Y/n]`), then run
`sudo loginctl enable-linger "$USER"` natively (sudo prompts in the same
terminal). On failure: fail loudly.

**1.B.5 — Input collection + validation**
- `BOT_TOKEN` — env or prompt; validate `^[0-9]+:[A-Za-z0-9_-]+$`
- `TG_USER_ID` — env or prompt; validate `^[0-9]+$`
- `WORKSPACE` — env or default `claude-bot`; validate `^[A-Za-z0-9._-]+$`
- All prompts loop on invalid input with clear "why it's wrong"

**1.B.6 — Package install (idempotent)**
- Claude Code via `npm install -g @anthropic-ai/claude-code` (skip if present, log skip)
- **Bun** via `curl -fsSL https://bun.sh/install | bash` — REQUIRED by the
  telegram plugin's MCP server (`.mcp.json` invokes `bun run start`).
  Omitting it causes the plugin to silently fail and the bot never polls
  Telegram. Discovered 2026-04-20 debugging Station11.
- Marketplace registration (skip if already registered)
- Telegram plugin install (skip if already installed)

**1.B.7 — Idempotent config writes**
- `~/.claude/channels/telegram/.env` — preserve if exists unless `--reset-config`
- `~/.claude/channels/telegram/access.json` — if exists and contains current `TG_USER_ID` in `allowFrom`, skip; otherwise merge with `jq`

**1.B.8 — systemd user service**
Render service file (envsubst on a `.tpl`), write to
`~/.config/systemd/user/claude-telegram.service`, `daemon-reload`,
`enable`, but **don't start yet** — wait for OAuth.

**1.B.9 — Interactive OAuth pause**
Print clear instructions to run `claude setup-token` in the same
terminal. Wait for user confirmation. After they confirm, verify auth
works by parsing the *real* `claude auth status` output (Task 1.B.10).

**1.B.10 — Verify auth (parse real output)**
Run `claude auth status` and check for the actual success marker (we
need to inspect real output to know what to grep for). If auth missing,
loop back to 1.B.9 with a clear error.

**1.B.11 — Start service + verify**
`systemctl --user restart claude-telegram`, sleep 3,
`systemctl --user is-active`, show last 10 journal lines. On failure:
print the journalctl command and exit non-zero.

**1.B.12 — Final summary**
- Bot is running
- Useful commands (status, logs, stop, restart)
- Where the install log lives
- "Send a message to your bot to test"

### 1.C — Quality of life (do alongside 1.B as you go)

**1.C.1 — Install log file**
`tee` everything to `/tmp/claudify-install-<host>-<YYYYMMDD-HHMMSS>.log`
from line one. Print the path in the final summary.

**1.C.2 — `--dry-run` mode**
Print every system-modifying command without executing.

**1.C.3 — `doctor.sh`**
Separate script for diagnosing a half-broken install:
- Service status
- Auth status
- Token + allowlist files present and well-formed
- linger enabled
- node / npm / claude / bun on PATH under systemd
- Last 20 journal lines
Each check prints green or red with next-step hints on red.

---

## Acceptance criteria

Phase 1 is **done** when ALL of these are true:

- [ ] Folder structure agreed and in place; conventions.md + 4 ADRs written
- [ ] `install.sh` runs clean on a fresh server (Station11 reset to baseline)
- [ ] `install.sh` re-run on a configured server is safe and ≤ 60s, no destructive overwrites
- [ ] `install.sh --dry-run` works end-to-end with no remote modifications
- [ ] Every install produces a timestamped log file at `/tmp/claudify-install-*.log`
- [ ] `doctor.sh` correctly distinguishes a healthy install from a broken one
- [ ] No dead code, no unused files, no half-finished functions
- [ ] At least one successful real-world install on Station11 with a NEW BotFather bot

---

## Out of scope for this phase

- Hosting `install.sh` at a public URL → Phase 2 (Distribution)
- Update / backup / uninstall scripts → Phase 3
- New channels / MCPs → Phase 4
- Cost tracking, audit log, secret manager → Phase 5
