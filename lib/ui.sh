# lib/ui.sh — output helpers, log file setup
#
# Defines color helpers, the step / ok / warn / fail message functions,
# and a setup_logging() that tees subsequent output to a per-run log
# file under /tmp.
#
# Sourced first by install.sh because every other module relies on these.
# No side effects on source — main() calls setup_logging() explicitly so
# --help / --version exit cleanly without creating empty log files.

LOG_FILE="${LOG_FILE:-/tmp/claudify-install-$(date +%Y%m%d-%H%M%S).log}"

setup_logging() {
  exec > >(tee -a "$LOG_FILE") 2>&1
}

c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

step() { echo; c_cyan "━━━ $* ━━━"; }
ok()   { c_green "  ✓ $*"; }
warn() { c_yellow "  ⚠ $*"; }
fail() { c_red   "  ✗ $*"; exit 1; }

print_banner() {
  c_bold "╭────────────────────────────────────────────────────────────╮"
  printf '\033[1m│        Claudify install.sh  (v%-22s)        │\033[0m\n' "${SCRIPT_VERSION:-?}"
  c_bold "╰────────────────────────────────────────────────────────────╯"
}
