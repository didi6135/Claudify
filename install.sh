#!/usr/bin/env bash
# claudify install.sh — bootstrap Claude Code + Telegram on this Linux server
#
# Usage:
#   bash install.sh
#   bash install.sh --dry-run
#   BOT_TOKEN=… TG_USER_ID=… WORKSPACE=… bash install.sh
#
# When distributed, this file is the BUILT single-file output of build.sh
# (concatenates lib/ + this orchestrator). For local development the
# modular sources under lib/ are used directly via `source` below.
#
# Dependencies on this server:
#   - bash, coreutils, util-linux (provides /usr/bin/script), curl
#   - node >= 20 + npm
#   - sudo (used ONCE for `loginctl enable-linger`)
#
# See:
#   - .planning/phases/phase-1-bootstrap.md  build plan
#   - docs/architecture.md                   what this installs
#   - docs/troubleshooting.md                when something breaks

set -euo pipefail

SCRIPT_VERSION="0.1.0-dev"

# Resolve LIB_DIR even when invoked via symlink.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Order matters:
#   ui.sh         — opens the log file, defines colors and ok/warn/fail
#   args.sh       — parse_args + run() (depends on fail)
#   prompts.sh    — TTY detect + ask family (depends on fail)
#   validate.sh   — pure validators
#   preflight.sh  — uses ui + prompts
#   steps.sh      — uses everything above
# shellcheck source=lib/ui.sh
source "$LIB_DIR/ui.sh"
# shellcheck source=lib/args.sh
source "$LIB_DIR/args.sh"
# shellcheck source=lib/prompts.sh
source "$LIB_DIR/prompts.sh"
# shellcheck source=lib/validate.sh
source "$LIB_DIR/validate.sh"
# shellcheck source=lib/preflight.sh
source "$LIB_DIR/preflight.sh"
# shellcheck source=lib/steps.sh
source "$LIB_DIR/steps.sh"

main() {
  parse_args "$@"          # may exit on --help / --version
  setup_logging            # only after we know we're really running
  detect_tty
  print_banner

  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY-RUN — no system changes will be made"
  fi

  preflight_os
  preflight_prereqs
  preflight_linger

  collect_inputs

  install_claude
  install_telegram_plugin
  write_configs
  write_service
  oauth_setup
  start_service

  final_summary
}

main "$@"
