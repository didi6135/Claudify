# Claudify

> **A personal assistant powered by your own Claude Code subscription.**
> **Deploy once, reach it from anywhere.**

Claudify takes a fresh Linux server and turns it into a personal Claude
Code assistant you can talk to from Telegram. One curl command, one
sudo prompt, one browser login — that's the whole setup.

---

## Install

SSH into your server, then:

```bash
curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash
```

The installer walks you through everything: creating a Telegram bot,
installing Claude Code, configuring the systemd service, completing
Claude OAuth. **First install takes about 3–5 minutes.**

### Preview without changing anything

```bash
curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash -s -- --dry-run
```

Shows every action the installer would take, without doing any of them.

---

## Prerequisites

- **A Linux server with systemd.** Ubuntu 24.04 LTS is the tested
  baseline; Debian 12+, Fedora 39+ should also work.
- **`sudo` access** for one-time setup (enables `loginctl linger` so
  your bot survives logouts and reboots). The installer will offer to
  install Node.js and `jq` automatically if missing.
- **A Claude subscription** (Pro or Max) — the installer pauses once
  for you to complete OAuth.
- **A Telegram bot token** from [@BotFather](https://t.me/BotFather) —
  the installer walks you through creating one if you don't have it.
- **Your numeric Telegram user ID** from
  [@userinfobot](https://t.me/userinfobot) — same.

Full prerequisites: [docs/prerequisites.md](docs/prerequisites.md).

---

## After install

The bot runs as `claude-telegram.service` under your user systemd:

```bash
systemctl --user status  claude-telegram      # is it running?
journalctl --user -u     claude-telegram -f   # follow logs
systemctl --user restart claude-telegram      # restart
systemctl --user stop    claude-telegram      # stop
```

### Everything lives here

All per-install state is under a single hidden folder:
```
~/.claudify/
├── workspace/           claude's WorkingDirectory
├── credentials.env      Claude OAuth token (chmod 600)
└── telegram/            TELEGRAM_STATE_DIR
    ├── .env             bot token (chmod 600)
    └── access.json      user allowlist
```
To uninstall everything Claudify installed:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/uninstall.sh)
```
(One script, prompts for confirmation, leaves Claude Code itself + Bun + npm
alone — you can remove those manually if you want a completely clean system.)

## Diagnose (doctor)

When something looks off, run:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/doctor.sh)
```

It prints 28 health checks (deps, layout, auth, systemd, Telegram
reachability) and gives a concrete next-step hint on every failure.

---

## Update

Pulls latest Claudify from main and re-runs in-place, preserving your
bot token, allowlist, and OAuth credentials. Typically ~10 seconds.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/update.sh)
```

What survives: `BOT_TOKEN`, `TG_USER_ID` allowlist, Claude OAuth token,
your edits to `~/.claudify/workspace/CLAUDE.md`.
What changes: the systemd unit, claude CLI / plugin (if newer is out),
`~/.claude.json` seed (idempotent), service restart.

To overwrite tokens on purpose:
```bash
curl -fsSL .../install.sh | bash -s -- --reset-config
```

---

## How it works

Architecture diagram, file layout, and the rationale behind each
component: [docs/architecture.md](docs/architecture.md).

When something breaks: [docs/troubleshooting.md](docs/troubleshooting.md).

Common questions: [docs/faq.md](docs/faq.md).

---

## Development

Source layout:

| Path | Purpose |
|---|---|
| `install.sh` | thin orchestrator (modular development form) |
| `lib/*.sh` | bash modules sourced by `install.sh` |
| `lib/engines/` | engine adapters (`claude-code.sh`, …) — see `docs/architecture.md §6` |
| `build.sh` | concatenates `lib/` + `install.sh` → `dist/install.sh` |
| `dist/install.sh` | the single-file installer that curl serves |
| `src/` | TypeScript modules (Bun) — `backup`/`restore` helpers |
| `tests/` | `tests/bash/` (bats) + `tests/ts/` (bun test) |
| `test.sh` | repo-root entry that runs both test suites |
| `docs/` | user-facing documentation |
| `.planning/` | project planning, roadmap, ADRs |

After editing `install.sh` or anything under `lib/`, run:

```bash
bash build.sh
```

…to regenerate `dist/install.sh` (the file curl users actually fetch).

To run the test suites:

```bash
bash test.sh                 # both suites; warn-skips a missing runner
bash test.sh --bash          # bash only (bats)
bash test.sh --ts            # TS only (bun test)
```

Conventions: [.planning/conventions.md](.planning/conventions.md).
Architectural decisions: [.planning/decisions/](.planning/decisions/).

---

## License

(TBD)
