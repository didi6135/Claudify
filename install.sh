#!/usr/bin/env bash
# claudify install.sh — bootstrap Claude Code + Telegram on this Linux server
#
# Usage:
#   curl -fsSL https://claudify.sh/install | bash
#   bash install.sh
#   bash install.sh --dry-run
#   BOT_TOKEN=... TG_USER_ID=... WORKSPACE=... bash install.sh
#
# Dependencies on this server:
#   - bash, coreutils, util-linux (provides /usr/bin/script), curl
#   - node >= 20 + npm
#   - sudo (used ONCE for `loginctl enable-linger`)
#
# See also:
#   - .planning/phases/phase-1-bootstrap.md  (build plan)
#   - docs/architecture.md                   (what this installs)
#   - docs/troubleshooting.md                (when something breaks)

set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────
SCRIPT_VERSION="0.1.0-dev"
LOG_FILE="/tmp/claudify-install-$(date +%Y%m%d-%H%M%S).log"
NPM_PREFIX="$HOME/.npm-global"
TTY_DEV=""    # set by detect_tty()
DRY_RUN=0
RESET_CONFIG=0

# ─── Output helpers ───────────────────────────────────────────────────────
c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
c_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

step() { echo; c_cyan "━━━ $* ━━━"; }
ok()   { c_green "  ✓ $*"; }
warn() { c_yellow "  ⚠ $*"; }
fail() { c_red   "  ✗ $*"; exit 1; }

# Tee everything to a log file from the very first line
exec > >(tee -a "$LOG_FILE") 2>&1

# ─── Args & help ──────────────────────────────────────────────────────────
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

# ─── TTY detection (handles `curl | bash` case) ───────────────────────────
# When piped from curl, stdin is the script content, so `read` can't
# reach the keyboard. We re-route prompts through /dev/tty in that case.
detect_tty() {
  if [[ -t 0 ]]; then
    TTY_DEV=/dev/stdin
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    TTY_DEV=/dev/tty
  fi
}

# ─── Prompt helpers ───────────────────────────────────────────────────────
ask() {
  local prompt="$1" default="${2:-}" varname="$3"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: $current (from env)"
    return
  fi
  [[ -z "$TTY_DEV" ]] && fail "No TTY; set $varname via env var when running non-interactively"
  local input
  if [[ -n "$default" ]]; then
    read -r -p "  $prompt [$default]: " input < "$TTY_DEV"
    input="${input:-$default}"
  else
    read -r -p "  $prompt: " input < "$TTY_DEV"
  fi
  printf -v "$varname" '%s' "$input"
}

ask_secret() {
  local prompt="$1" varname="$2"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: (from env)"
    return
  fi
  [[ -z "$TTY_DEV" ]] && fail "No TTY; set $varname via env var when running non-interactively"
  local input
  read -r -s -p "  $prompt: " input < "$TTY_DEV"
  echo
  printf -v "$varname" '%s' "$input"
}

ask_validated() {
  local prompt="$1" default="$2" varname="$3" validator="$4" hint="$5"
  while true; do
    ask "$prompt" "$default" "$varname"
    if "$validator" "${!varname}"; then return 0; fi
    warn "$hint"
    unset "$varname"
  done
}

ask_secret_validated() {
  local prompt="$1" varname="$2" validator="$3" hint="$4"
  while true; do
    ask_secret "$prompt" "$varname"
    if "$validator" "${!varname}"; then return 0; fi
    warn "$hint"
    unset "$varname"
  done
}

# ─── Validators ───────────────────────────────────────────────────────────
validate_bot_token() { [[ "$1" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; }
validate_user_id()   { [[ "$1" =~ ^[0-9]+$ ]]; }
validate_workspace() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

# ─── Run helper (honors --dry-run) ────────────────────────────────────────
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] $*"
  else
    eval "$@"
  fi
}

# ─── Preflight ────────────────────────────────────────────────────────────
preflight_os() {
  step "Preflight"
  [[ "$(uname -s)" == "Linux" ]] || fail "Not Linux. Claudify installs the bot on a Linux server."
  ok "Linux ($(uname -m))"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian) ok "${PRETTY_NAME:-$NAME $VERSION_ID} (supported)" ;;
      *)             warn "${PRETTY_NAME:-${ID:-unknown}} (not formally tested; may work)" ;;
    esac
  fi
}

preflight_prereqs() {
  local missing=()
  for cmd in node npm script curl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if (( ${#missing[@]} )); then
    c_red "  ✗ missing required commands: ${missing[*]}"
    echo
    echo "  Install them and re-run. On Ubuntu/Debian:"
    echo "      sudo apt update && sudo apt install -y nodejs npm util-linux curl"
    exit 1
  fi
  ok "node $(node --version), npm $(npm --version)"

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is missing — needed to safely merge access.json. Install with:"
    echo "      sudo apt install -y jq"
  else
    ok "jq present"
  fi
}

preflight_linger() {
  if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    ok "linger already enabled for $USER"
    return 0
  fi

  warn "linger is disabled for $USER"
  echo "    Without linger, the bot would die when you log out of SSH."
  echo "    Enabling it requires one-time sudo. You'll be prompted for"
  echo "    your password right here."
  echo

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] sudo loginctl enable-linger $USER"
    return 0
  fi

  local yn
  ask "Continue and enable linger now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without linger"

  sudo loginctl enable-linger "$USER" || fail "Failed to enable linger"
  ok "linger enabled"
}

# ─── Inputs ───────────────────────────────────────────────────────────────
collect_inputs() {
  step "Configuration"
  ask_secret_validated \
    "Telegram bot token (from @BotFather)" \
    BOT_TOKEN validate_bot_token \
    "Format: digits, colon, then characters (e.g. 1234567890:ABC-...)"
  ok "bot token format valid"

  ask_validated \
    "Your Telegram user ID (numeric, from @userinfobot)" \
    "" TG_USER_ID validate_user_id \
    "Must be all digits."

  ask_validated \
    "Workspace folder name" \
    "claude-bot" WORKSPACE validate_workspace \
    "Letters, digits, dot, underscore, hyphen only — no spaces."
}

# ─── Claude Code install ──────────────────────────────────────────────────
# Set up a user-local npm prefix so global installs don't need sudo.
setup_npm_prefix() {
  run "mkdir -p '$NPM_PREFIX'"
  if [[ "$DRY_RUN" -ne 1 ]]; then
    npm config set prefix "$NPM_PREFIX" >/dev/null
  fi
  export PATH="$NPM_PREFIX/bin:$PATH"

  # Persist for future shells if not already there
  local rc="$HOME/.bashrc"
  if [[ -f "$rc" ]] && ! grep -q "$NPM_PREFIX/bin" "$rc"; then
    if [[ "$DRY_RUN" -ne 1 ]]; then
      echo "export PATH=\"$NPM_PREFIX/bin:\$PATH\"" >> "$rc"
    fi
    ok "added $NPM_PREFIX/bin to PATH in ~/.bashrc"
  fi
}

install_claude() {
  step "Install Claude Code"
  setup_npm_prefix

  if command -v claude >/dev/null 2>&1; then
    ok "claude already installed: $(claude --version 2>/dev/null | head -1)"
    return 0
  fi

  echo "  ↓ npm install -g @anthropic-ai/claude-code"
  run "npm install -g @anthropic-ai/claude-code >/dev/null 2>&1"
  ok "claude installed: $(claude --version 2>/dev/null | head -1)"
}

# ─── Telegram plugin ──────────────────────────────────────────────────────
install_telegram_plugin() {
  step "Install Telegram plugin"

  if claude plugin marketplace list 2>/dev/null | grep -q "claude-plugins-official"; then
    ok "marketplace already registered"
  else
    echo "  ↓ Adding official marketplace…"
    run "claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1"
    ok "marketplace registered"
  fi

  if claude plugin list 2>/dev/null | grep -q "telegram.*claude-plugins-official"; then
    ok "telegram plugin already installed"
  else
    echo "  ↓ Installing telegram plugin…"
    run "claude plugin install telegram@claude-plugins-official >/dev/null 2>&1"
    ok "telegram plugin installed"
  fi
}

# ─── Config files (idempotent) ────────────────────────────────────────────
write_configs() {
  step "Write configuration"

  local channels_dir="$HOME/.claude/channels/telegram"
  run "mkdir -p '$channels_dir'"

  # .env (bot token)
  local env_file="$channels_dir/.env"
  if [[ -s "$env_file" && "$RESET_CONFIG" -ne 1 ]]; then
    ok "bot token already configured (use --reset-config to overwrite)"
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  [DRY] write $env_file (chmod 600)"
    else
      printf 'TELEGRAM_BOT_TOKEN=%s\n' "$BOT_TOKEN" > "$env_file"
      chmod 600 "$env_file"
      ok "bot token written"
    fi
  fi

  # access.json (allowlist) — preserve existing, merge new ID
  local access="$channels_dir/access.json"
  if [[ -s "$access" && "$RESET_CONFIG" -ne 1 ]]; then
    if command -v jq >/dev/null 2>&1; then
      if jq -e --arg id "$TG_USER_ID" '.allowFrom // [] | index($id)' "$access" >/dev/null 2>&1; then
        ok "allowlist already contains $TG_USER_ID (preserved)"
      else
        if [[ "$DRY_RUN" -eq 1 ]]; then
          echo "  [DRY] jq merge $TG_USER_ID into existing $access"
        else
          local tmp; tmp="$(mktemp)"
          jq --arg id "$TG_USER_ID" \
             '.allowFrom = ((.allowFrom // []) + [$id] | unique)' \
             "$access" > "$tmp"
          mv "$tmp" "$access"
          ok "added $TG_USER_ID to existing allowlist"
        fi
      fi
    else
      warn "access.json exists but jq is missing — skipping merge."
      echo "    Install jq and re-run, or pass --reset-config to overwrite."
    fi
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  [DRY] write $access"
    else
      cat > "$access" <<JSON
{
  "dmPolicy": "allowlist",
  "allowFrom": ["$TG_USER_ID"],
  "groups": {},
  "pending": {}
}
JSON
      ok "allowlist written (user $TG_USER_ID)"
    fi
  fi
}

# ─── systemd user service ─────────────────────────────────────────────────
write_service() {
  step "Install systemd service"

  local svc_dir="$HOME/.config/systemd/user"
  local svc_path="$svc_dir/claude-telegram.service"
  run "mkdir -p '$svc_dir'"
  run "mkdir -p '$HOME/workspace/$WORKSPACE'"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] write $svc_path"
  else
    cat > "$svc_path" <<SVC
[Unit]
Description=Claude Code with Telegram channel ($WORKSPACE)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=%h
Environment=TERM=xterm-256color
WorkingDirectory=%h/workspace/$WORKSPACE
ExecStart=/usr/bin/script -qfec "claude --channels plugin:telegram@claude-plugins-official" /dev/null
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SVC
    ok "service unit written"
  fi

  if [[ "$DRY_RUN" -ne 1 ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    systemctl --user daemon-reload
    systemctl --user enable claude-telegram.service >/dev/null 2>&1
    ok "service enabled"
  fi
}

# ─── Claude OAuth ─────────────────────────────────────────────────────────
# We can't observe Claude's exact `auth status` output until we run it
# against a live install, so we accept several phrasings. Phase 1.B.10
# tightens this once we see real output.
claude_is_authed() {
  claude auth status 2>&1 | grep -qiE '(logged.in|authenticated|active|ok)'
}

oauth_setup() {
  step "Authenticate Claude (one-time)"

  if claude_is_authed; then
    ok "Claude is already authenticated"
    return 0
  fi

  c_yellow "  Claude needs a one-time browser login."
  echo "    A URL will appear below. Open it in any browser, log in to your"
  echo "    Claude subscription, and the script will continue automatically."
  echo

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] would run: claude setup-token"
    return 0
  fi

  # Run setup-token with the user's TTY so the OAuth UI works
  if [[ -n "$TTY_DEV" ]]; then
    claude setup-token < "$TTY_DEV" || fail "claude setup-token failed"
  else
    claude setup-token || fail "claude setup-token failed"
  fi

  if claude_is_authed; then
    ok "Claude authenticated"
  else
    warn "Auth not detected after setup-token. Output:"
    claude auth status 2>&1 | sed 's/^/    /'
    fail "Re-run install or 'claude setup-token' manually"
  fi
}

# ─── Start service + verify ───────────────────────────────────────────────
start_service() {
  step "Start service"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] systemctl --user restart claude-telegram"
    return 0
  fi

  systemctl --user restart claude-telegram.service
  sleep 3

  if systemctl --user is-active --quiet claude-telegram.service; then
    ok "service is running"
  else
    warn "service failed to start. Last 20 log lines:"
    journalctl --user -u claude-telegram -n 20 --no-pager | sed 's/^/    /'
    fail "Service did not stay up. Check logs above."
  fi
}

# ─── Final summary ────────────────────────────────────────────────────────
final_summary() {
  echo
  c_green "╭────────────────────────────────────────────────────────────╮"
  c_green "│              Claudify  —  install complete                 │"
  c_green "╰────────────────────────────────────────────────────────────╯"
  echo
  echo "  Send a message to your bot on Telegram to test."
  echo
  echo "  Useful commands:"
  echo "    Status:   systemctl --user status claude-telegram"
  echo "    Logs:     journalctl --user -u claude-telegram -f"
  echo "    Stop:     systemctl --user stop claude-telegram"
  echo "    Restart:  systemctl --user restart claude-telegram"
  echo
  echo "  Install log: $LOG_FILE"
  echo
}

# ─── Main ─────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  detect_tty

  c_bold "╭────────────────────────────────────────────────────────────╮"
  printf '\033[1m│        Claudify install.sh  (v%-22s)        │\033[0m\n' "$SCRIPT_VERSION"
  c_bold "╰────────────────────────────────────────────────────────────╯"

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
