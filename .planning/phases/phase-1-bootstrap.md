# Phase 1 — Rock-solid bootstrap

**Status:** planning
**Goal:** `deploy.sh` is trustworthy, idempotent, debuggable.

---

## Scope
This phase is about hardening what already exists. No new features, no new
channels, no new MCPs. Just making the current bootstrap bulletproof.

## Why this phase first
Every other phase builds on top of `deploy.sh`. If it's flaky, every
phase after it inherits the flakiness. Fix the foundation first.

---

## Tasks

### 1.1 — Fix the auth verification bug
**Problem:** [deploy.sh:202-203](../../deploy.sh#L202-L203) greps for
`"loggedIn": true` from `claude auth status` output. That command does not
emit JSON by default, so the grep always fails → user sees a spurious
warning even on successful auth.
**Action:** verify the real output format on a live server, then rewrite the
check using the correct marker. Fall back to a clear message if Claude Code
changes the format.

### 1.2 — Make the `'skip'` prompt actually skip
**Problem:** [deploy.sh:199](../../deploy.sh#L199) prompts *"ENTER when done,
or 'skip' if already authenticated"*, but the `$skip` variable is read and
discarded — the auth check runs regardless.
**Action:** honor `skip` input (bypass the verification and service start?
or just the verification?). Decide semantics, then implement.

### 1.3 — Idempotent secret & config writes
**Problem:** `.env` and `access.json` are overwritten every deploy. Any
manual edits (extra allowlist entries, added env vars) are lost on
re-deploy.
**Action:** if files exist, preserve them unless user passes
`--force-reset-config`. Merge new allowlist entry into existing
`access.json` via `jq` if available.

### 1.4 — Input validation
**Problem:** no sanity check on `BOT_TOKEN` (should match
`\d+:[A-Za-z0-9_-]+`), `TG_USER_ID` (numeric), or `WORKSPACE` (no spaces,
no shell metachars).
**Action:** validate each after collection, re-prompt on bad input.

### 1.5 — Dry-run mode
**Problem:** no way to preview what the script will do on the server.
**Action:** `DRY_RUN=1 ./deploy.sh` prints every remote command instead of
executing it.

### 1.6 — Deploy log file
**Problem:** when something fails, user has nothing to share for
troubleshooting.
**Action:** tee all output to
`./logs/deploy-<host>-<YYYYMMDD-HHMMSS>.log` automatically, and print the
log path in the final summary.

### 1.7 — `doctor.sh`
**Problem:** half-broken installs require the user to SSH in and poke
around manually.
**Action:** new script that runs remote diagnostics:
- Is the service running? (`systemctl --user status`)
- Is Claude authenticated?
- Is the bot token present and non-empty?
- Is the allowlist readable?
- Is `node` / `claude` / `bun` on PATH under systemd?
- Last 20 lines of journal logs
Prints a green-or-red check for each, plus next-step hints on red.

### 1.8 — Remove dead code
**Problem:** `TEMPLATES_DIR` declared but unused; Bun installed but not
required; `templates/` contains files that aren't read.
**Action:** either wire up `envsubst`-driven template rendering (cleaner)
or delete the templates folder + unused variables.

---

## Acceptance criteria
Phase 1 is done when all of these are true:
- [ ] `./deploy.sh` runs clean on a fresh VPS with no warnings
- [ ] Re-running `./deploy.sh` on an already-deployed server is safe and
      preserves user edits to `access.json` / `.env`
- [ ] `DRY_RUN=1 ./deploy.sh` works end-to-end
- [ ] Every deploy produces a timestamped log file locally
- [ ] `./doctor.sh` correctly reports status on a working and a broken
      server
- [ ] No dead code or unreferenced files in the repo
- [ ] At least one successful real-world deploy using the improved script

---

## Open questions
- Do we have a test server for real-world verification? *(blocks 1.1 and
  final acceptance)*
- Keep `templates/` and use `envsubst`, or delete and inline the heredocs?
  *(decide during 1.8)*

## Out of scope for this phase
- Cross-OS install UX → Phase 2
- New channels or MCPs → Phase 4
- Cost tracking, audit log → Phase 5
