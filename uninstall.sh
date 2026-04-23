#!/usr/bin/env bash
# uninstall.sh — remove Claudify from this server (leaves Claude Code itself alone).
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/uninstall.sh)
#   bash uninstall.sh
#   bash uninstall.sh --yes        # no confirmation prompt (for scripts)
#   bash uninstall.sh --help
#
# What gets removed:
#   • systemd user service (claude-telegram.service), stopped + disabled
#   • ~/.config/systemd/user/claude-telegram.service (the unit file)
#   • ~/.claudify/                 (ALL per-install state: tokens, workspace, logs)
#
# What stays (the operator may have other uses — remove manually if desired):
#   • ~/.claude/                   Claude Code's user-wide state
#   • ~/.claude.json               Claude Code's onboarding + per-project trust
#   • ~/.bun/                      Bun runtime
#   • ~/.npm-global/               npm global prefix (where `claude` lives)
#   • loginctl linger (if on)

set -uo pipefail   # NOT -e: we want to continue past missing files

# ─── Output helpers ───────────────────────────────────────────────────────
c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m\n'  "$*"; }

section() { echo; c_cyan "━━━ $* ━━━"; echo; }
ok()   { echo "  $(c_green '✓') $*"; }
skip() { echo "  $(c_yellow '·') $*"; }
warn() { echo "  $(c_yellow '⚠') $*"; }
fail() { echo "  $(c_red   '✗') $*"; exit 1; }

# ─── Args ─────────────────────────────────────────────────────────────────
ASSUME_YES=0

show_help() {
  cat <<HELP
Claudify uninstall.sh

Usage:
  bash uninstall.sh              Prompts before removing.
  bash uninstall.sh --yes        No confirmation (use in scripts).
  bash uninstall.sh --help       This help.

Removes:
  • claude-telegram.service (stopped + disabled + unit file deleted)
  • ~/.claudify/             (all per-bot state — tokens, workspace)

Leaves untouched:
  ~/.claude/, ~/.claude.json, ~/.bun/, ~/.npm-global/, linger.
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)  ASSUME_YES=1 ;;
    --help|-h) show_help; exit 0 ;;
    *) fail "Unknown flag: $1 (try --help)" ;;
  esac
  shift
done

# ─── Resolve paths ────────────────────────────────────────────────────────
CLAUDIFY_ROOT="$HOME/.claudify"
SERVICE_UNIT="$HOME/.config/systemd/user/claude-telegram.service"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ─── Preview ──────────────────────────────────────────────────────────────
c_bold "╭────────────────────────────────────────────────────────────╮"
c_bold "│              Claudify  —  uninstall                        │"
c_bold "╰────────────────────────────────────────────────────────────╯"

echo
echo "  This will remove everything Claudify installed on this server."
echo
c_bold "  Will remove:"
if systemctl --user list-unit-files claude-telegram.service 2>/dev/null | grep -q claude-telegram; then
  echo "    • systemd service  claude-telegram.service  (active: $(systemctl --user is-active claude-telegram 2>/dev/null || echo no))"
else
  echo "    • systemd service  $(c_yellow '(not installed — nothing to remove)')"
fi
if [[ -f "$SERVICE_UNIT" ]]; then
  echo "    • unit file        $SERVICE_UNIT"
else
  echo "    • unit file        $(c_yellow '(already absent)')"
fi
if [[ -d "$CLAUDIFY_ROOT" ]]; then
  size=$(du -sh "$CLAUDIFY_ROOT" 2>/dev/null | cut -f1)
  echo "    • $CLAUDIFY_ROOT  (${size:-?})"
else
  echo "    • $CLAUDIFY_ROOT  $(c_yellow '(already absent)')"
fi

echo
c_bold "  Will NOT touch (remove manually if you want):"
for p in "$HOME/.claude" "$HOME/.claude.json" "$HOME/.bun" "$HOME/.npm-global"; do
  if [[ -e "$p" ]]; then
    echo "    · $p"
  fi
done

linger=$(loginctl show-user "$USER" 2>/dev/null | grep '^Linger=' | cut -d= -f2 || true)
if [[ "$linger" == "yes" ]]; then
  echo "    · linger enabled for $USER  (disable with: sudo loginctl disable-linger $USER)"
fi

# ─── Confirm ──────────────────────────────────────────────────────────────
if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo
  # Resolve a terminal for the prompt even under curl|bash (stdin is the script)
  if [[ -t 0 ]]; then
    TTY=/dev/stdin
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    TTY=/dev/tty
  else
    fail "Non-interactive run with no --yes. Re-run with --yes to proceed without prompt."
  fi
  read -r -p "  Proceed? [y/N]: " reply < "$TTY"
  [[ "$reply" =~ ^[Yy]$ ]] || { echo; c_yellow "  Aborted. Nothing removed."; exit 0; }
fi

# ─── Remove ───────────────────────────────────────────────────────────────
section "Removing"

# 1. Stop + disable the service
if systemctl --user list-unit-files claude-telegram.service 2>/dev/null | grep -q claude-telegram; then
  systemctl --user stop claude-telegram 2>/dev/null
  systemctl --user disable claude-telegram 2>/dev/null
  ok "service stopped + disabled"
else
  skip "service already gone"
fi

# 2. Remove the unit file
if [[ -f "$SERVICE_UNIT" ]]; then
  rm -f "$SERVICE_UNIT" && ok "unit file removed ($SERVICE_UNIT)"
else
  skip "unit file already gone"
fi

# 3. Reload systemd so it forgets the unit
systemctl --user daemon-reload 2>/dev/null && ok "systemctl daemon-reload" || skip "daemon-reload skipped (no user bus)"

# 4. Remove the Claudify root folder
if [[ -d "$CLAUDIFY_ROOT" ]]; then
  rm -rf "$CLAUDIFY_ROOT" && ok "$CLAUDIFY_ROOT removed"
else
  skip "$CLAUDIFY_ROOT already gone"
fi

# ─── Summary ──────────────────────────────────────────────────────────────
section "Done"

c_green "  Claudify has been removed from this server."
echo
echo "  Left untouched (remove manually if you want a completely clean system):"
for p in "$HOME/.claude" "$HOME/.claude.json" "$HOME/.bun" "$HOME/.npm-global"; do
  if [[ -e "$p" ]]; then
    echo "    rm -rf $p"
  fi
done
if [[ "$linger" == "yes" ]]; then
  echo "    sudo loginctl disable-linger $USER"
fi
echo
echo "  To reinstall later:"
echo "    curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash"
echo
