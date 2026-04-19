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

# Confirm a successful action. In dry-run, suppress — the preceding
# `[DRY] …` line already conveys what would have happened, so a success
# checkmark would be misleading.
ok_done() {
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return
  ok "$@"
}

# Center text inside a 60-wide │ box.
BANNER_WIDTH=60
banner_line() {
  local text="$1" color_code="${2:-\033[1m}"
  local pad_left=$(( (BANNER_WIDTH - ${#text}) / 2 ))
  local pad_right=$(( BANNER_WIDTH - ${#text} - pad_left ))
  printf '%b│%*s%s%*s│\033[0m\n' "$color_code" "$pad_left" "" "$text" "$pad_right" ""
}

print_banner() {
  c_bold "╭────────────────────────────────────────────────────────────╮"
  banner_line "Claudify install.sh  (v${SCRIPT_VERSION:-?})"
  c_bold "╰────────────────────────────────────────────────────────────╯"
}
