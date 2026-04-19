# Roadmap

Five phases, executed in order. Each phase has its own doc under
[phases/](phases/) with concrete tasks and acceptance criteria.

Phases are finished when acceptance criteria pass — no "90% done, moving on."

---

## Phase 1 — Rock-solid bootstrap
**Goal:** the existing `deploy.sh` becomes trustworthy and idempotent.

- Fix known bugs (auth-check, `'skip'` prompt, token overwrite)
- Input validation (token format, user ID, workspace name)
- Dry-run mode
- Local log file per deploy
- `doctor.sh` — diagnose a half-broken install

→ [phase-1-bootstrap.md](phases/phase-1-bootstrap.md)

---

## Phase 2 — Cross-platform install UX
**Goal:** one command works from Windows (Git Bash), macOS, Linux, WSL.

- Test matrix: Git Bash, WSL, macOS zsh/bash, Ubuntu bash
- One-liner installer (`curl ... | bash`)
- README rewritten for non-technical operator
- Pre-flight compatibility checks

→ phases/phase-2-cross-platform.md *(to be written)*

---

## Phase 3 — Lifecycle scripts
**Goal:** running an assistant over months, not just deploying once.

- `update.sh` — Claude Code, plugins, MCPs
- `backup.sh` / `restore.sh` — `~/.claude`, workspaces, memories, secrets
- `uninstall.sh` — clean removal
- Scheduled auto-update opt-in

→ phases/phase-3-lifecycle.md *(to be written)*

---

## Phase 4 — Capabilities expansion
**Goal:** ship as a *full* assistant, not just Telegram.

- Gmail MCP (OAuth flow handled in deploy)
- Google Calendar MCP
- Google Drive MCP
- settings.json with sensible permissions policy
- Multi-workspace support (work / personal / learning)
- User-level `CLAUDE.md` seeded from `who-am-i.md`

→ phases/phase-4-capabilities.md *(to be written)*

---

## Phase 5 — Security & observability
**Goal:** safe to leave running unattended.

- Secret manager upgrade (move off plain `.env` to age/sops)
- Cost ceiling — hard cutoff when daily $ threshold hit
- Audit log — every command the assistant ran
- Health check — external ping can verify alive-and-responsive
- Permission policy — what the assistant is / isn't allowed to do

→ phases/phase-5-security.md *(to be written)*

---

## Progress tracking
Current phase: **Phase 1** (planning → execution).
See [phases/phase-1-bootstrap.md](phases/phase-1-bootstrap.md).
