# lib/args.sh — CLI argument parsing, help text, dry-run plumbing
#
# Owns the user-facing flag surface for install.sh.
# Exposes:
#   parse_args "$@"   — sets DRY_RUN / RESET_CONFIG; exits on --help/--version
#   show_help         — prints help text
#   run <cmd…>        — executes cmd unless DRY_RUN=1, in which case prints it

DRY_RUN=0
RESET_CONFIG=0
NON_INTERACTIVE=0
PRESERVE_STATE=0

show_help() {
  cat <<HELP
claudify install.sh — bootstrap Claude+Telegram on this server

Usage:
  bash install.sh [flags]

Flags:
  --dry-run           Print actions without modifying the system
  --reset-config      Overwrite existing token/allowlist (default: preserve)
  --preserve-state    Update mode: reuse existing BOT_TOKEN, TG_USER_ID,
                      OAuth token from ~/.claudify; only refresh the
                      systemd unit + reseed claude.json. No prompts.
                      Typically invoked by update.sh.
  --non-interactive   Skip all "Press ENTER" pauses and confirmation
                      prompts. Useful for automated tests / CI. Requires
                      BOT_TOKEN, TG_USER_ID (+ linger already on OR
                      passwordless sudo).
  --version           Print version and exit
  --help              Show this help

Environment (any can be set to skip its prompt):
  BOT_TOKEN         Telegram bot token from @BotFather
  TG_USER_ID        Your numeric Telegram user ID from @userinfobot
  WORKSPACE         Workspace folder name (default: claude-bot)

Logs:
  $LOG_FILE
HELP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)         DRY_RUN=1 ;;
      --reset-config)    RESET_CONFIG=1 ;;
      --preserve-state)  PRESERVE_STATE=1; NON_INTERACTIVE=1 ;;  # implies non-interactive
      --non-interactive) NON_INTERACTIVE=1 ;;
      --version)         echo "claudify $SCRIPT_VERSION"; exit 0 ;;
      -h|--help)         show_help; exit 0 ;;
      *)                 fail "Unknown flag: $1 (try --help)" ;;
    esac
    shift
  done

  # --reset-config means "start clean" — wipe the resume crumbs too,
  # otherwise we'd silently re-load a stale BOT_TOKEN the operator
  # was trying to overwrite. clear_partial_state lives in
  # lib/onboarding.sh and is safe to call before sourcing finishes
  # because it's a function definition (resolved at call time).
  if [[ "$RESET_CONFIG" -eq 1 ]]; then
    clear_partial_state 2>/dev/null || true
  fi
}

# Run a command unless DRY_RUN=1, in which case echo it instead.
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] $*"
  else
    eval "$@"
  fi
}
