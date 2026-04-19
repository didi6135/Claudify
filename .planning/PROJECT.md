# claudify

> **A personal assistant powered by your own Claude Code subscription.**
> **Deploy once, reach it from anywhere.**

## Vision
*"Just claudify it."* — one command on any OS (Windows, macOS, Linux)
takes you from a fresh VPS to a running personal assistant that remembers
you, talks to your email / calendar / drive, and is secured to just you.

## Why this exists
The official Claude Code + Telegram plugin is powerful, but standing it up
on a server is fiddly: Node install, Bun, plugin marketplace, systemd, auth,
allowlists, MCP configs. `claudify` collapses all of that into one script
and maintains it over time (update, backup, doctor, uninstall).

## Goals (what claudify does)
1. **Bootstrap** — fresh server → running assistant in <5 minutes
2. **Cross-platform install UX** — same command works from Windows / macOS / Linux / WSL
3. **Lifecycle** — update, backup, restore, uninstall, diagnose
4. **Capabilities** — ship with Telegram + Gmail + Calendar + Drive MCPs preconfigured
5. **Security** — secrets managed properly, permissions policy, audit log, cost ceiling
6. **Observability** — logs, health checks, cost tracking

## Non-goals (what claudify does NOT do)
- Not a hosted service — user brings their own server and API key
- Not a multi-tenant platform — one operator, one assistant
- Not a Claude Code fork — wraps the official CLI, does not replace it
- Not a GUI — command-line deploy tool; Telegram is the UX

## Status
**Phase 0 — Planning.** Existing `deploy.sh` works but has known bugs and
missing features. Roadmap in [ROADMAP.md](ROADMAP.md).

## Stakeholders
- **Operator / user:** one person (see [who-am-i.md](who-am-i.md))
- **Future:** potentially shared on GitHub if it matures

## Name rationale
`claudify` — one word, verb form (*"claudified my VPS in 2 minutes"*),
professional register, available as a package name. Works in both Hebrew
and English pronunciation.
