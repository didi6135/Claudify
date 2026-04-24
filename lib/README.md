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
| `steps.sh` | install steps + onboarding walkthroughs | `intro`, `guide_botfather`, `guide_userinfobot`, `collect_inputs`, `install_claude`, `seed_claude_state`, `install_telegram_plugin`, `write_configs`, `write_service`, `seed_persona`, `oauth_setup`, `start_service`, `final_summary` |

## When to split a module further

`steps.sh` is the largest. If it crosses ~400 lines or develops
multiple unrelated concerns (e.g. updates separate from initial
install), split into `lib/steps/<step>.sh` files and update both
`install.sh` and `build.sh` accordingly.
