# lib/ — bash modules sourced by install.sh

Each file is one focused concern. The orchestrator (`install.sh` at the
project root) sources them in dependency order at startup. For
distribution via `curl | bash`, `build.sh` concatenates them into a
single self-contained `dist/install.sh`.

## Rules

- Each file = one focused concern.
- Files in `lib/` **define functions and constants only**. No top-level
  work, no I/O on source. The orchestrator (`install.sh`) decides when
  to invoke setup steps explicitly (e.g. `setup_logging`).
- Modules **do not source each other**. Only the orchestrator sources
  lib files.
- Modules **do not have their own shebang** or `set -euo pipefail` —
  those belong on the orchestrator.
- Every file has a header comment listing its purpose and a
  `Exposes:` line enumerating the public functions / variables.
- Function names are `snake_case`. Variables defined here use
  `UPPER_SNAKE` if treated as constants; locals are `snake_case`.

## Current modules

| File | Purpose | Exposes |
|---|---|---|
| `ui.sh` | colors + status helpers + log file setup | `c_red/green/yellow/cyan/bold`, `step`, `ok`, `ok_done` (dry-run-aware), `warn`, `fail`, `banner_line`, `print_banner`, `setup_logging`, `LOG_FILE` |
| `args.sh` | CLI flag parsing + dry-run helper | `parse_args`, `show_help`, `run`, `DRY_RUN`, `RESET_CONFIG` |
| `prompts.sh` | TTY-safe interactive prompts | `detect_tty`, `ask`, `ask_secret`, `ask_validated`, `ask_secret_validated`, `TTY_DEV` |
| `validate.sh` | input format validators | `validate_bot_token`, `validate_user_id`, `validate_workspace` |
| `preflight.sh` | pre-install checks + auto-install of missing deps | `preflight_os`, `preflight_prereqs`, `preflight_linger`, `offer_apt_install`, `install_node` |
| `onboarding.sh` | welcome banner + Telegram walkthroughs + input collection | `intro`, `guide_botfather`, `guide_userinfobot`, `collect_inputs` |
| `claude.sh` | Claude Code engine + plugin install + auth probe + Claudify-layout constants (TEMP — gets split in 3.4.3 between `lib/engines/claude-code.sh` and engine-agnostic glue) | constants `NPM_PREFIX`, `CLAUDIFY_ROOT`, `CLAUDIFY_WORKSPACE`, `CLAUDIFY_TELEGRAM`, `CREDS_FILE`; functions `setup_npm_prefix`, `install_claude`, `install_telegram_plugin`, `seed_claude_state`, `claude_is_authed` |
| `configs.sh` | bot `.env` + allowlist + starter persona | `write_configs`, `seed_persona` |
| `service.sh` | systemd user unit + start + final summary | `write_service`, `start_service`, `final_summary` |
| `oauth.sh` | claude OAuth setup + long-lived token capture for systemd | `oauth_setup` |
| `engines/` | engine adapters (one file per LLM CLI) — see `lib/engines/README.md` and `docs/architecture.md §6` | each adapter exposes the 6-function contract: `engine_install`, `engine_auth_check`, `engine_auth_setup`, `engine_run_args`, `engine_status`, `engine_uninstall` |

## When to split a module further

Hard limits: ≤300 lines per file, ≤50 lines per function (per
`CLAUDIFY/CLAUDE.md` rule 1). When a file approaches the file limit,
or grows two distinct concerns, split it into a new `lib/<name>.sh`
and update both `install.sh` (source order) and `build.sh` (MODULES
array). The 3.4.2 split of the old `steps.sh` is the canonical
example — one ~430-line catch-all became five focused modules
(`onboarding`, `claude`, `configs`, `service`, `oauth`).
