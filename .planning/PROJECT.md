# Claudify

> **A personal assistant powered by your own Claude Code subscription.**
> **Deploy once, reach it from anywhere.**

## Install model
**One curl command, run on the target server.** Same UX as
[OpenCode](https://opencode.ai), [Bun](https://bun.sh), [Tailscale](https://tailscale.com),
[k3s](https://k3s.io):

```bash
ssh you@your-server.com
curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash
```

> A short vanity URL (`https://claudify.sh/install`) is on the Phase 2
> follow-up list; the GitHub raw URL above works today and is what
> README.md documents.

Everything runs locally on the server. No operator-side CLI, no remote-push
machinery, no key-management dance.

## Vision
*"Just claudify it."* — one curl command takes a bare Linux server to a
running personal assistant that remembers you, talks to your email /
calendar / drive, and is secured to just you.

## Why this exists
The official Claude Code + Telegram plugin is powerful, but standing it up
on a server is fiddly: installing the right Node version, the plugin
marketplace, systemd user services, linger, OAuth, allowlists, MCP
configs. `claudify` collapses all of that into a single command and
maintains it over time (update, backup, doctor, uninstall).

## Goals
1. **One-command install** — `curl … | bash` on the server, < 3 minutes to a running bot
2. **Zero-friction redeploy** — re-running the install is safe and < 60 seconds
3. **Lifecycle** — update, backup, restore, uninstall, diagnose
4. **Capabilities** — ship with Telegram + Gmail + Calendar + Drive MCPs preconfigured
5. **Security** — secrets managed properly, permissions policy, audit log, cost ceiling
6. **Observability** — logs, health checks, cost tracking
7. **Quality from day one** — every script documented, every architectural decision recorded as an ADR, folder structure intentional

## Non-goals
- **Not a hosted service** — user brings their own server and Claude subscription
- **Not multi-tenant** — one operator, one assistant per server
- **Not a Claude Code fork** — wraps the official CLI, does not replace it
- **Not an operator-side CLI** — no laptop-to-server push tool. The user SSHes to their server first, then runs the install. This is intentional simplicity.
- **Not a GUI** — the install is CLI; the day-to-day UX is Telegram (and later, other channels)

## Status
**Phase 1 + 2 done** (2026-04-21) — one-command install works end-to-end,
repo is public, `doctor.sh` reports 28 checks.
**Phase 3 (Lifecycle) is next.**
See [ROADMAP.md](ROADMAP.md).

## Stakeholders
- **Operator / user:** one person (see [who-am-i.md](who-am-i.md))
- **Public repo:** [github.com/didi6135/Claudify](https://github.com/didi6135/Claudify)
  (public since 2026-04-21; MIT / TBD license)

## Deferred / under consideration

Ideas that came up during development, deliberately parked to keep the
current product focused. Revisit when the baseline is solid.

### SMB / country-first pivot (discussed 2026-04-23)
**Direction considered:** reposition from "personal Claude via Telegram"
to "AI assistant for small businesses, country by country, starting in
Israel." Target = non-technical business owners; channel shifts to
WhatsApp Business (dominant in Israel); integrations go
country-specific (e.g. Israeli accounting: iCount, Hashavshevet).

**Why parked:** the current product isn't polished enough to carry a
pivot yet — Phase 3 (lifecycle) and Phase 4 (capabilities) should land
first. The pivot also implies architectural changes (managed hosting?
WhatsApp Business API? localization stack?) worth thinking about
without time pressure.

**When to pick it back up:** after Phase 3 and at least some of Phase 4
ship. Before touching this again, do the 7-question vision exercise
(ideal first customer, first-wow moment, deploy path, languages,
pricing model, etc.) and rewrite this PROJECT.md accordingly — don't
just bolt the new target on top of the old one.

---

## Project conventions
Code style, doc style, ADR format, and file-header rules live in
[conventions.md](conventions.md). Architectural decisions are recorded
under [decisions/](decisions/).

## Name rationale
`claudify` — one word, verb form (*"claudified my VPS in 2 minutes"*),
professional register, available as a package name. Works in both Hebrew
and English pronunciation.
