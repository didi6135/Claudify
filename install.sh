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
#   layout.sh     — claudify on-disk paths (CLAUDIFY_ROOT, _WORKSPACE, _TELEGRAM, CREDS_FILE)
#   engine.sh     — picks the engine adapter and sources lib/engines/<id>.sh
#                   into scope (defines all engine_* contract functions)
#   manifest.sh   — registry + per-instance manifest read/write helpers (uses jq)
#   onboarding.sh — intro, BotFather/userinfobot walkthroughs, collect_inputs
#   configs.sh    — bot .env + access.json + workspace persona (CLAUDE.md)
#   service.sh    — systemd unit write/start + final summary (uses engine_run_args)
#   oauth.sh      — interactive OAuth orchestration (uses engine_auth_check, engine_auth_setup)
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
# shellcheck source=lib/layout.sh
source "$LIB_DIR/layout.sh"
# shellcheck source=lib/engine.sh
source "$LIB_DIR/engine.sh"
# shellcheck source=lib/manifest.sh
source "$LIB_DIR/manifest.sh"
# shellcheck source=lib/onboarding.sh
source "$LIB_DIR/onboarding.sh"
# shellcheck source=lib/configs.sh
source "$LIB_DIR/configs.sh"
# shellcheck source=lib/service.sh
source "$LIB_DIR/service.sh"
# shellcheck source=lib/oauth.sh
source "$LIB_DIR/oauth.sh"

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

  engine_install                                # install the engine binary
  engine_seed_state "$CLAUDIFY_WORKSPACE"       # skip theme + trust prompts
  engine_install_channel_plugin telegram        # marketplace + plugin
  write_configs
  write_service
  seed_persona                                  # starter CLAUDE.md (preserved)
  oauth_setup
  start_service

  # Manifest writes — every entrypoint reads these afterwards.
  # Today's only instance is "default"; 3.4.5 introduces multi-instance.
  manifest_register_instance default
  manifest_init_instance     default
  manifest_set_channel       default telegram ""

  final_summary
}

main "$@"
