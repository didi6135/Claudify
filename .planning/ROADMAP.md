# Roadmap

Five phases, executed in order. Each has its own doc under [phases/](phases/)
with concrete tasks and acceptance criteria.

A phase is finished when **every** acceptance criterion passes — no
"90% done, moving on."

---

## Phase 1 — Bootstrap `install.sh`
**Goal:** a single curl-pipe-bash command takes a fresh Ubuntu/Debian
server to a running Claude+Telegram assistant in under 3 minutes,
end-to-end, with as little operator interaction as possible.

This phase **builds `install.sh` from scratch** in the new target-side
model. The legacy `deploy.sh` (SSH-from-laptop) is retired.

Includes: project structure, conventions doc, ADRs for the major
choices, robust install script with preflight, validation, idempotency,
inline linger handling, logging, dry-run, and verification.

→ [phase-1-bootstrap.md](phases/phase-1-bootstrap.md)

---

## Phase 2 — Distribution
**Goal:** the install command is a real curl-able URL, not "git clone first."

- Repo flips from private to public
- Stable install URL — either `raw.githubusercontent.com/didi6135/Claudify/main/install.sh` or a custom domain like `claudify.sh`
- Versioned releases (git tags + GitHub releases)
- `install.sh` accepts `CLAUDIFY_VERSION=v1.0.0` to pin
- README first instruction is the curl command, full stop

→ phases/phase-2-distribution.md *(to be written)*

---

## Phase 3 — Lifecycle
**Goal:** running an assistant for months, not just installing it once.

- `update.sh` — Claude Code, plugins, MCPs, Claudify itself
- `backup.sh` / `restore.sh` — `~/.claude`, workspaces, memories, secrets
- `uninstall.sh` — clean removal
- `doctor.sh` — already in Phase 1, but expanded here
- Optional auto-update on a cron

→ phases/phase-3-lifecycle.md *(to be written)*

---

## Phase 4 — Capabilities expansion
**Goal:** ship as a *full* assistant, not just Telegram.

- Gmail MCP (OAuth flow handled in install)
- Google Calendar MCP
- Google Drive MCP
- `settings.json` with sensible permissions policy
- Multi-workspace support (work / personal / learning)
- User-level `CLAUDE.md` seeded from `who-am-i.md`

→ phases/phase-4-capabilities.md *(to be written)*

---

## Phase 5 — Security & observability
**Goal:** safe to leave running unattended.

- Secret manager upgrade (move off plain `.env` to age/sops)
- Cost ceiling — hard cutoff at $X/day
- Audit log — every command the assistant ran
- Health check — external ping verifies alive-and-responsive
- Permission policy — what the assistant is / isn't allowed to do

→ phases/phase-5-security.md *(to be written)*

---

## Out of roadmap (intentionally)

These are things we **could** build but won't — they conflict with the
project's vision (see [PROJECT.md](PROJECT.md) non-goals):

- Operator-side CLI for managing many servers from one laptop
- A hosted SaaS version of Claudify
- Web/mobile UI alternatives to Telegram
- Multi-tenant deployments (multiple users sharing one assistant)

If a real need emerges, revisit by writing an ADR proposing the change.

---

## Progress tracking
Current phase: **Phase 1** — building `install.sh`.
Open tasks tracked in [phases/phase-1-bootstrap.md](phases/phase-1-bootstrap.md).
