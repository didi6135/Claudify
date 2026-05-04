# Changelog

All notable changes to Claudify are logged here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic
versioning per [semver.org](https://semver.org).

This file is maintained as a **rolling `## [Unreleased]` section**
that collects the current batch of changes; when a version is cut, the
Unreleased header is replaced with `## [X.Y.Z] - YYYY-MM-DD` and a
fresh Unreleased block goes back on top.

## [Unreleased]

### Added

- **Resumable install.** If `install.sh` is interrupted (Ctrl-C,
  network drop, lost SSH session, etc.) after the operator has typed
  their bot token + Telegram user ID + workspace name, those inputs
  are now saved to `~/.claudify/.install-partial` (chmod 600) the
  moment they're collected. Re-running the install picks up exactly
  where it stopped — no `--resume` flag, no "Would you like to
  resume?" prompt, no re-paste. The file is removed on successful
  finish (in `final_summary`) and on `--reset-config`. Honours
  `--preserve-state` and pre-set env vars (those win over the
  partial state). See task spec
  `.planning/phases/phase-3-tasks/3.4.2.1-resume-install.md`.

### Fixed

- **`claude setup-token` rendering as stacked splash screens during
  install.** ui.sh's `setup_logging` redirects stdout into a `tee` pipe
  for the install log, so claude-code's TUI saw no-TTY-on-stdout and
  fell back to a degraded mode that re-painted the entire welcome
  banner on every spinner tick. `oauth.sh` now wraps setup-token in
  `script(1)` (real PTY) with stdin/stdout pinned to `$TTY_DEV`,
  bypassing the tee so the user gets a live, in-place TUI render. The
  long-lived token is captured to a `chmod 600` temp file and shredded
  after `_persist_oauth_token` grep-extracts it (no more reliance on
  the install log holding the token).

### Added

- **Repo skeleton for Phase 3.4** — `lib/engines/`, `src/` (TypeScript
  scaffold: `tsconfig.json`, `package.json`, `src/lib/`),
  `tests/bash/` + `tests/ts/` with one canary test each, and
  `test.sh` at repo root that runs both suites and warn-skips a
  missing runner (bats or bun). Empty folders for now — real engine
  adapter, TS modules, and entrypoint tests land in 3.4.3, 3.5, 3.4.x.
- **`docs/architecture.md`** — canonical reference for how Claudify
  is built. 11 sections covering invariants, layering, repo + runtime
  folder structure, the four extension types (channels / MCPs /
  skills / hooks), manifest schema, engine abstraction, entrypoint
  responsibilities, test strategy, contributor walkthrough, migration
  roadmap, and a full security model with explicit threat-model
  boundaries.
- **Multi-instance design committed** — every install becomes an
  *instance* with its own state under `~/.claudify/instances/<name>/`,
  its own systemd unit (`claudify-<name>.service`), and its own
  personal CLI command (`<name> doctor`, `<name> update`, etc.).
  Implementation lands in Phase 3.4.
- **Engine abstraction design** — `lib/engines/<engine-id>.sh`
  contract with 6 functions (`engine_install`, `engine_auth_check`,
  `engine_auth_setup`, `engine_run_args`, `engine_status`,
  `engine_uninstall`). Today's only adapter: `claude-code.sh`.
  Future engines plug in by writing one file. (See ADR 0005.)

### Changed

- **`lib/steps.sh` split into 5 focused modules** to comply with the
  300-line file / 50-line function limits in `CLAUDE.md` rule 1.
  The 615-line catch-all became `onboarding.sh` (intro + Telegram
  walkthroughs + input collection), `claude.sh` (TEMP — Claude Code
  install + plugin install + first-run-state seeding + auth probe;
  also holds Claudify-layout constants until 3.4.3 splits them out
  into the engine adapter), `configs.sh` (bot `.env` + allowlist +
  starter persona), `service.sh` (systemd unit + start + final
  summary), `oauth.sh` (`claude setup-token` + token capture). Pure
  refactor; no behavior change. Verified via Station11 round-trip
  (`--preserve-state --non-interactive`) — install completes clean,
  service stays up, doctor reports 28/28.
- **Phase 3 scope expanded** from 3.4 (just backup/restore) to 3.4
  (architectural refactor — multi-instance, engine abstraction,
  manifests, personal commands, lib/steps.sh split), 3.5
  (backup/restore in TypeScript), 3.6 (security hardening pass),
  3.7 (docs sync). See `phase-3-lifecycle.md` for the breakdown.

### Removed

- **Unused `templates/` files** — `access.json`,
  `claude-telegram.service`, and the folder's `README.md`. Both
  config files were artifacts of the original `deploy.sh` flow and
  were never read at runtime; the live install renders these inline
  via heredocs in `lib/steps.sh`. Folder is gone.

---

## [0.1.0-dev] - 2026-04-24

Pre-release development snapshot. Phase 1 + 2 closed, Phase 3 is 3/5
done. Covers everything in git history through commit `5ef1446`.

### Added

- **`install.sh`** — one-command target-side install on Ubuntu/Debian.
  Curl-pipe-bash UX matching Bun/Tailscale/k3s. Flags: `--dry-run`,
  `--reset-config`, `--preserve-state`, `--non-interactive`,
  `--version`, `--help`.
- **`dist/install.sh`** — built single-file distributable served from
  GitHub Raw for `curl … | bash`. Regenerated from `lib/` by
  `build.sh`.
- **Modular sources** under `lib/` — `ui.sh`, `args.sh`, `prompts.sh`,
  `validate.sh`, `preflight.sh`, `steps.sh`.
- **`doctor.sh`** — 28-check standalone diagnostic covering
  environment, dependencies, `.claudify/` layout, Claude Code state,
  systemd service, and Telegram reachability. Each failure prints a
  concrete next-step hint.
- **`uninstall.sh`** — one-command clean removal. Stops + disables
  service, removes unit file, `rm -rf ~/.claudify`. Leaves
  `~/.claude/`, `~/.bun/`, `~/.npm-global/`, and linger untouched by
  default (operator may have other uses).
- **`update.sh`** — in-place refresh that preserves tokens,
  allowlist, OAuth credentials. Pulls latest `dist/install.sh` from
  main and runs with `--preserve-state --non-interactive`. Typical
  run ~10 seconds. Cache-busts the raw.githubusercontent URL to
  avoid stale CDN edges.
- **Starter persona** seeded to `~/.claudify/workspace/CLAUDE.md`
  during install. Briefing-style, Israel-context-aware, never
  clobbered on re-install so operator edits survive forever.
- **Guided onboarding walkthroughs** — step-by-step BotFather and
  userinfobot instructions printed inline during install, skipped
  when env vars are pre-filled.
- **Automatic dependency installation** — Bun (required by plugin),
  Node.js via NodeSource (if missing), `jq` via apt (optional but
  recommended). Each prompts for consent unless `--non-interactive`.
- **`seed_claude_state`** step — merges `hasCompletedOnboarding` and
  per-project `hasTrustDialogAccepted` into `~/.claude.json` so the
  TUI's theme and workspace-trust prompts don't block the systemd
  service.
- **`bypassPermissionsModeAccepted`** pre-accepted in `~/.claude.json`.
- **Auto-allow** of the four telegram plugin tools in
  `~/.claude/settings.json.permissions.allow` (redundant with bypass
  mode but kept as a safety net).
- **Project scaffolding** — `docs/`, `lib/`, `templates/`, `.planning/`
  (with `decisions/` ADRs, `phases/`, `conventions.md`,
  `upstream-wishlist.md`, `who-am-i.md`).
- **5 Architecture Decision Records:**
  - `0001` bash as implementation language
  - `0002` systemd user service with linger
  - `0003` OAuth via `setup-token`, not API key
  - `0004` target-side curl install, not operator-side SSH push
  - `0005` upstream plugin + bash/TS layering
- **Operator-local autoinstall template** at
  `.planning/LOCAL-autoinstall.sh` (gitignored) — end-to-end test
  harness: scrubs state, pre-seeds OAuth, runs latest install,
  verifies service + bot reachability.

### Changed

- **Architecture.** Moved from operator-side SSH-push (`deploy.sh` on
  laptop) to target-side curl install (`install.sh` on the server
  itself). See ADR 0004.
- **All per-install state relocated** to `~/.claudify/` — hidden
  single-folder layout with `workspace/`, `credentials.env`, and
  `telegram/{.env, access.json}`. `rm -rf ~/.claudify` is the full
  uninstall.
- **OAuth token persistence** — install.sh now auto-captures the
  `sk-ant-oat01-…` token from `claude setup-token`'s output log and
  writes it to `~/.claudify/credentials.env` (chmod 600). Systemd
  service loads it via `EnvironmentFile`.
- **Service runs with** `--permission-mode bypassPermissions` — no
  per-tool approval prompts (personal-bot trust model; see ADR 0005).
- **Systemd PATH** includes `~/.bun/bin:~/.npm-global/bin` so the
  plugin's MCP server subprocess can find `bun`.
- **README** rewritten for the curl-install model (originally described
  the retired deploy.sh flow).

### Fixed

- **Press-ENTER prompts printing garbage** (`varname=_ (from env)`) —
  caused by `_` as throwaway variable name colliding with bash's
  special `$_`. New `wait_enter` helper bypasses env-prefill logic.
- **OAuth detection grep** — was looking for `logged.in` (9-char
  pattern). Real output is `loggedIn` (8 chars, JSON). Now matches
  exact JSON: `"loggedIn"[[:space:]]*:[[:space:]]*true`.
- **Service blocking at theme prompt** — service sat forever at
  Claude Code's first-run theme selection. Fixed by seeding
  `hasCompletedOnboarding: true` in `~/.claude.json`.
- **Service blocking at workspace trust prompt** — fixed by seeding
  `projects[<workspace-path>].hasTrustDialogAccepted: true`.
- **Bun missing from preflight** — the telegram plugin's MCP server
  requires `bun` via its `.mcp.json`. Without it, `claude --channels`
  launches but silently fails to spawn the plugin. Added Bun to
  auto-install and to the service PATH.
- **Telegram prompting for permission on every reply** — the plugin's
  2-button UI was treating each message as one-shot approval. Fixed
  by switching to `--permission-mode bypassPermissions` (see ADR 0005).
- **Raw.githubusercontent CDN staleness** in `update.sh` — appended a
  timestamp query string so cache keys on the URL.
- **`--version` / `--help` creating empty `/tmp/claudify-install-*.log`
  files** — moved `setup_logging` to after `parse_args` so early-exit
  flags don't open the log.
- **Dry-run printing false-success lines** (e.g. `✓ claude installed:`
  when nothing was installed) — new `ok_done` helper suppresses
  confirmation messages when `DRY_RUN=1`.
- **Linger preflight swallowing real failures** — removed the
  `|| true` silent fallback; now either runs `sudo loginctl
  enable-linger` successfully or fails loudly with a copy-pasteable
  manual command.

### Removed

- **`deploy.sh`** — the original operator-side SSH push installer.
  Superseded by `install.sh` (target-side curl model).
- **`legacy/` folder** — brief resting place for `deploy.sh` while
  the pivot stabilized; deleted once the new install proved out.

### Security

- **Secrets redacted** in all captured command output via `sed` before
  pasting into chat / logs (`sk-ant-oat01-…` and bot-token patterns).
- **`credentials.env`, `telegram/.env`** written with chmod 600;
  `access.json` with chmod 644.
- **`.gitignore`** — `.planning/LOCAL*` pattern ensures operator-local
  files (with real secrets) never commit.
- **Tool auto-allow** scoped to the four telegram plugin tools only,
  not Bash/Edit/Write/Read which still go through the (bypassed)
  permission system.

### Deferred / parked

- **SMB / Israel-first pivot** — considered and deliberately parked
  until the baseline is more polished. Re-entering requires the
  7-question vision exercise in `.planning/PROJECT.md` (Deferred
  section).
- **Short install URL** (`claudify.sh/install`) — Phase 2 follow-up;
  raw.githubusercontent URL works today.
- **Versioned GitHub Releases** with signed tarballs — Phase 2
  follow-up.
- **TypeScript migration** for scripts larger than bash is comfortable
  with — per ADR 0005, next candidate is `backup.sh`/`restore.sh`
  in Phase 3.4 (TBD).
