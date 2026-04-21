#!/usr/bin/env bash
# doctor.sh — diagnose a Claudify install on the server it runs on.
#
# Usage (from the target server):
#   bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/doctor.sh)
#   bash doctor.sh                  # if the repo is cloned
#
# Read-only. Runs as the user who owns the install (no sudo).
# Prints one line per check with a green ✓ / yellow ⚠ / red ✗ and, on
# failure, a concrete next-step hint. Final summary at the bottom.

# NOT set -e: we want every check to run even if some fail.
set -uo pipefail

# ─── Output helpers ───────────────────────────────────────────────────────
# Each prints a full line (\n included). When used inside $(…) the trailing
# newline is stripped, so nesting inside echo/printf works naturally too.
c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m\n'  "$*"; }

PASS=0
WARN=0
FAIL=0

section() { echo; c_cyan "━━━ $* ━━━"; echo; }

# check <description> <exit_status> [hint…]
# pass 0 for pass, 1 for fail, 2 for warn. Remaining args are hint lines printed on fail/warn.
check() {
  local desc="$1" status="$2"; shift 2
  case "$status" in
    0) echo "  $(c_green '✓') $desc"; PASS=$((PASS+1)) ;;
    1) echo "  $(c_red   '✗') $desc"; FAIL=$((FAIL+1))
       for line in "$@"; do echo "    → $line"; done ;;
    2) echo "  $(c_yellow '⚠') $desc"; WARN=$((WARN+1))
       for line in "$@"; do echo "    → $line"; done ;;
  esac
}

# ─── Constants (must mirror install.sh) ───────────────────────────────────
CLAUDIFY_ROOT="$HOME/.claudify"
CLAUDIFY_WORKSPACE="$CLAUDIFY_ROOT/workspace"
CLAUDIFY_TELEGRAM="$CLAUDIFY_ROOT/telegram"
CREDS_FILE="$CLAUDIFY_ROOT/credentials.env"
SERVICE_UNIT="$HOME/.config/systemd/user/claude-telegram.service"

# Systemctl --user needs this in a non-interactive SSH context
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Put bun + npm-global on PATH so `claude` and `bun` commands resolve
export PATH="$HOME/.bun/bin:$HOME/.npm-global/bin:$PATH"

# Load the OAuth token so `claude auth status` has what it needs
if [[ -s "$CREDS_FILE" ]]; then
  set -a; . "$CREDS_FILE"; set +a
fi

# ═════════════════════════════════════════════════════════════════════════
c_bold "╭────────────────────────────────────────────────────────────╮"
c_bold "│                  Claudify  —  doctor                       │"
c_bold "╰────────────────────────────────────────────────────────────╯"

# ─── Environment ──────────────────────────────────────────────────────────
section "Environment"
if [[ "$(uname -s)" == "Linux" ]]; then
  check "Linux host ($(uname -m))" 0
else
  check "Not Linux — this server cannot host the bot" 1 \
    "Claudify installs require a Linux server with systemd."
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  check "OS: ${PRETTY_NAME:-unknown}" 0
fi

check "Running as user: $USER (uid $(id -u))" 0

# ─── Dependencies ─────────────────────────────────────────────────────────
section "Dependencies"
if command -v node >/dev/null 2>&1; then
  check "node $(node --version)" 0
else
  check "node is missing" 1 "Install Node.js 20+ (via NodeSource or apt)"
fi

if command -v npm >/dev/null 2>&1; then
  check "npm $(npm --version)" 0
else
  check "npm is missing" 1 "Install npm (usually bundled with node)"
fi

if command -v bun >/dev/null 2>&1; then
  check "bun $(bun --version)" 0
else
  check "bun is missing (required by the Telegram plugin)" 1 \
    "curl -fsSL https://bun.sh/install | bash"
fi

if command -v jq >/dev/null 2>&1; then
  check "jq present" 0
else
  check "jq is missing" 2 "sudo apt install -y jq  (optional but recommended)"
fi

if command -v claude >/dev/null 2>&1; then
  check "claude $(claude --version 2>/dev/null | head -1)" 0
else
  check "claude CLI is missing" 1 "npm install -g @anthropic-ai/claude-code"
fi

if command -v /usr/bin/script >/dev/null 2>&1 || [[ -x /usr/bin/script ]]; then
  check "/usr/bin/script (util-linux)" 0
else
  check "/usr/bin/script missing" 1 "sudo apt install -y util-linux"
fi

# ─── Claudify layout ──────────────────────────────────────────────────────
section "Claudify layout  ($CLAUDIFY_ROOT)"
if [[ -d "$CLAUDIFY_ROOT" ]]; then
  check "root directory exists" 0
else
  check "root directory missing" 1 "Run install.sh — no Claudify install was found"
  # If the root is missing, most further checks will cascade — bail now
  echo
  c_red "Doctor aborting: no Claudify install detected."
  exit 1
fi

if [[ -d "$CLAUDIFY_WORKSPACE" ]]; then
  check "workspace/ dir exists" 0
else
  check "workspace/ missing" 1 "Re-run install.sh to recreate"
fi

if [[ -s "$CREDS_FILE" ]]; then
  perms=$(stat -c '%a' "$CREDS_FILE")
  if [[ "$perms" == "600" ]]; then
    check "credentials.env present (mode 600)" 0
  else
    check "credentials.env has wide permissions (mode $perms)" 2 \
      "chmod 600 $CREDS_FILE"
  fi
else
  check "credentials.env missing" 1 \
    "Re-run install.sh — OAuth token was never persisted"
fi

if [[ -s "$CLAUDIFY_TELEGRAM/.env" ]]; then
  perms=$(stat -c '%a' "$CLAUDIFY_TELEGRAM/.env")
  if [[ "$perms" == "600" ]]; then
    check "telegram/.env present (mode 600)" 0
  else
    check "telegram/.env has wide permissions (mode $perms)" 2 \
      "chmod 600 $CLAUDIFY_TELEGRAM/.env"
  fi
else
  check "telegram/.env missing (bot token)" 1 "Re-run install.sh"
fi

if [[ -s "$CLAUDIFY_TELEGRAM/access.json" ]]; then
  if jq -e 'has("allowFrom")' "$CLAUDIFY_TELEGRAM/access.json" >/dev/null 2>&1; then
    n=$(jq '.allowFrom | length' "$CLAUDIFY_TELEGRAM/access.json")
    check "access.json valid ($n allowlisted users)" 0
  else
    check "access.json missing 'allowFrom' key" 1 "Re-run install.sh"
  fi
else
  check "access.json missing" 1 "Re-run install.sh"
fi

# ─── Claude Code state ────────────────────────────────────────────────────
section "Claude Code state  ($HOME/.claude.json)"
if [[ -s "$HOME/.claude.json" ]]; then
  if jq -e '.hasCompletedOnboarding == true' "$HOME/.claude.json" >/dev/null 2>&1; then
    check "onboarding seeded (hasCompletedOnboarding: true)" 0
  else
    check "onboarding not seeded — service will hang at theme prompt" 1 \
      "Re-run install.sh (the seed_claude_state step fixes this)"
  fi

  if jq -e --arg d "$CLAUDIFY_WORKSPACE" \
       '.projects[$d].hasTrustDialogAccepted == true' \
       "$HOME/.claude.json" >/dev/null 2>&1; then
    check "workspace trust set for $CLAUDIFY_WORKSPACE" 0
  else
    check "workspace trust NOT set — service will hang at trust prompt" 1 \
      "Re-run install.sh"
  fi
else
  check "~/.claude.json missing" 1 "Re-run install.sh to seed Claude's user-wide state"
fi

if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -q "telegram.*claude-plugins-official"; then
    check "telegram plugin installed" 0
  else
    check "telegram plugin NOT installed" 1 \
      "claude plugin install telegram@claude-plugins-official"
  fi

  if claude auth status 2>&1 | grep -qE '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
    # Pull subscription type if available
    sub=$(claude auth status 2>&1 | grep -oE '"subscriptionType":[[:space:]]*"[^"]+"' | cut -d'"' -f4)
    check "Claude authenticated${sub:+ (subscription: $sub)}" 0
  else
    check "Claude NOT authenticated — API calls will 401" 1 \
      "Make sure $CREDS_FILE has CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-…" \
      "Re-run claude setup-token if the token is missing"
  fi
fi

# ─── Systemd service ──────────────────────────────────────────────────────
section "Systemd service  (claude-telegram.service, user scope)"
linger=$(loginctl show-user "$USER" 2>/dev/null | grep '^Linger=' | cut -d= -f2)
if [[ "$linger" == "yes" ]]; then
  check "linger enabled for $USER" 0
else
  check "linger is disabled — service dies on SSH logout" 1 \
    "sudo loginctl enable-linger $USER"
fi

if [[ -f "$SERVICE_UNIT" ]]; then
  check "unit file present ($SERVICE_UNIT)" 0

  # Sanity-check a few key lines in the unit
  if grep -q "^EnvironmentFile=-%h/.claudify/credentials.env" "$SERVICE_UNIT"; then
    check "unit points at ~/.claudify/credentials.env" 0
  else
    check "unit EnvironmentFile is not ~/.claudify/credentials.env" 2 \
      "You may be on an older layout — re-run install.sh"
  fi
  if grep -q "^Environment=TELEGRAM_STATE_DIR=%h/.claudify/telegram" "$SERVICE_UNIT"; then
    check "unit sets TELEGRAM_STATE_DIR to ~/.claudify/telegram" 0
  else
    check "unit missing TELEGRAM_STATE_DIR" 2 \
      "Re-run install.sh to update the service unit"
  fi
else
  check "unit file missing" 1 "Re-run install.sh"
fi

# daemon-reload isn't strictly required here, but status queries below need
# the user bus to be reachable
if systemctl --user is-enabled claude-telegram >/dev/null 2>&1; then
  check "service enabled (starts on boot)" 0
else
  check "service not enabled" 2 "systemctl --user enable claude-telegram"
fi

if systemctl --user is-active --quiet claude-telegram; then
  started=$(systemctl --user show claude-telegram --property=ActiveEnterTimestamp --value)
  check "service is active (since: $started)" 0

  svc_pid=$(systemctl --user show claude-telegram --property=MainPID --value)
  # Look for bun among descendants
  if [[ -n "$svc_pid" && "$svc_pid" != "0" ]] \
     && pstree -p "$svc_pid" 2>/dev/null | grep -q 'bun'; then
    check "bun MCP subprocess is running (plugin active)" 0
  else
    check "bun subprocess not found — plugin likely failed to start" 1 \
      "Check: journalctl --user -u claude-telegram -n 50 --no-pager" \
      "Most common cause: ~/.bun/bin not on systemd PATH"
  fi
else
  check "service is NOT running" 1 \
    "systemctl --user status claude-telegram" \
    "journalctl --user -u claude-telegram -n 50 --no-pager"
fi

# ─── Telegram reachability ────────────────────────────────────────────────
section "Telegram"
if [[ -s "$CLAUDIFY_TELEGRAM/.env" ]]; then
  # shellcheck disable=SC1091
  TELEGRAM_BOT_TOKEN="$(grep '^TELEGRAM_BOT_TOKEN=' "$CLAUDIFY_TELEGRAM/.env" | cut -d= -f2-)"

  if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
    bot_info=$(curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
    if echo "$bot_info" | grep -q '"ok":true'; then
      username=$(echo "$bot_info" | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4)
      check "bot token valid (@${username:-?})" 0
    else
      check "Telegram rejected the bot token" 1 \
        "Revoke via /revoke in @BotFather, issue a new token, re-run install"
    fi

    # getWebhookInfo — webhook would block polling
    webhook=$(curl -s --max-time 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo")
    if echo "$webhook" | grep -q '"url":""'; then
      check "no webhook set (correct — we use polling)" 0
    else
      check "webhook is set — blocks polling" 1 \
        "DELETE via: curl https://api.telegram.org/bot\$TOKEN/deleteWebhook"
    fi

    # getUpdates: if our service is polling, this request will 409.
    updates=$(curl -s --max-time 5 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?timeout=1")
    if echo "$updates" | grep -q '"error_code":409'; then
      check "service is actively polling (409 from getUpdates as expected)" 0
    elif echo "$updates" | grep -q '"ok":true'; then
      check "no one is polling Telegram — service isn't connected" 1 \
        "The service may be up but claude didn't spawn the plugin" \
        "journalctl --user -u claude-telegram -n 100 --no-pager"
    else
      check "Telegram getUpdates returned unexpected response" 2 \
        "Response: $(echo "$updates" | head -c 200)"
    fi
  else
    check "bot token is empty in telegram/.env" 1 "Re-run install.sh"
  fi
else
  check "telegram/.env missing — can't test" 1 "Re-run install.sh"
fi

# ─── Summary ──────────────────────────────────────────────────────────────
echo
total=$((PASS + WARN + FAIL))
if (( FAIL == 0 && WARN == 0 )); then
  c_green "╭────────────────────────────────────────────────────────────╮"
  c_green "│                 All $total checks passed.                      │"
  c_green "╰────────────────────────────────────────────────────────────╯"
  echo
  echo "  Your bot should be fully operational. Send it a Telegram message."
  echo
  exit 0
elif (( FAIL == 0 )); then
  c_yellow "╭────────────────────────────────────────────────────────────╮"
  c_yellow "│           $PASS passed, $WARN warnings, 0 failures.                │"
  c_yellow "╰────────────────────────────────────────────────────────────╯"
  echo
  echo "  Bot should work, but the warnings above are worth addressing."
  echo
  exit 0
else
  c_red "╭────────────────────────────────────────────────────────────╮"
  c_red "│      $PASS passed, $WARN warnings, $FAIL failure(s) — fix above.       │"
  c_red "╰────────────────────────────────────────────────────────────╯"
  echo
  echo "  Fix each ✗ above (hints are printed inline) and re-run doctor."
  echo "  Full reinstall (scrubs ALL state):"
  echo "      bash ~/test/autoinstall.sh"
  echo
  exit 1
fi
