# lib/args.sh — CLI argument parsing, help text, dry-run plumbing
#
# Owns the user-facing flag surface for install.sh.
# Exposes:
#   parse_args "$@"   — sets DRY_RUN / RESET_CONFIG; exits on --help/--version
#   show_help         — prints help text
#   run <cmd…>        — executes cmd unless DRY_RUN=1, in which case prints it

DRY_RUN=0
RESET_CONFIG=0

show_help() {
  cat <<HELP
claudify install.sh — bootstrap Claude+Telegram on this server

Usage:
  bash install.sh [flags]

Flags:
  --dry-run         Print actions without modifying the system
  --reset-config    Overwrite existing token/allowlist (default: preserve)
  --version         Print version and exit
  --help            Show this help

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
      --dry-run)      DRY_RUN=1 ;;
      --reset-config) RESET_CONFIG=1 ;;
      --version)      echo "claudify $SCRIPT_VERSION"; exit 0 ;;
      -h|--help)      show_help; exit 0 ;;
      *)              fail "Unknown flag: $1 (try --help)" ;;
    esac
    shift
  done
}

# Run a command unless DRY_RUN=1, in which case echo it instead.
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] $*"
  else
    eval "$@"
  fi
}
