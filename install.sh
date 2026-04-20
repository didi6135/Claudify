#!/usr/bin/env bash
# claudify install.sh — bootstrap Claude Code + Telegram on this Linux server
#
# Usage (target server, after SSH'ing in):
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash -s -- --dry-run
#   BOT_TOKEN=… TG_USER_ID=… WORKSPACE=… bash install.sh
#
# When distributed, the BUILT single-file output of build.sh
# (dist/install.sh) is what users actually fetch. This file (install.sh
# at the project root) is the modular development form that sources
# lib/*.sh below.
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

  intro                    # welcome message + ENTER to continue

  preflight_os
  preflight_prereqs        # offers to install missing deps (node, jq)
  preflight_linger

  collect_inputs           # walks user through BotFather + userinfobot

  install_claude
  install_telegram_plugin
  write_configs
  write_service
  oauth_setup
  start_service

  final_summary
}

main "$@"
