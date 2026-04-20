#!/usr/bin/env bash
# claudify install.sh — bootstrap Claude Code + Telegram on this Linux server
#
# THIS FILE IS GENERATED. Do not edit directly.
# Source:  https://github.com/didi6135/Claudify
# Edit:    install.sh + lib/*.sh in the source repo, then run `bash build.sh`
# Built:   2026-04-20T14:04:16Z
#
# Usage (on a target Linux server):
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash -s -- --dry-run

set -euo pipefail

SCRIPT_VERSION="0.1.0-dev"

# ─── from lib/ui.sh ─────────────────────────────────────────────────
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

# ─── from lib/args.sh ─────────────────────────────────────────────────
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

# ─── from lib/prompts.sh ─────────────────────────────────────────────────
# lib/prompts.sh — interactive prompts that survive `curl | bash`
#
# The challenge: when `bash install.sh` is fed via `curl … | bash`, stdin is
# the script content, not the keyboard, so plain `read` can't reach the user.
# We re-route prompts through /dev/tty when piped.
#
# Exposes:
#   detect_tty                                          — sets TTY_DEV
#   ask          <prompt> <default> <varname>           — visible input
#   ask_secret   <prompt> <varname>                     — hidden input
#   ask_validated <prompt> <default> <var> <fn> <hint>  — loop until valid
#   ask_secret_validated <prompt> <var> <fn> <hint>     — same, hidden

TTY_DEV=""

detect_tty() {
  if [[ -t 0 ]]; then
    TTY_DEV=/dev/stdin
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    TTY_DEV=/dev/tty
  fi
}

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

# Pause the flow until the user hits ENTER. Any typed input is discarded.
# This is a pacing pause, not a prompt for a value — so it does NOT go
# through ask()'s env-var-prefill logic. Using ask() here caused bugs
# when the throwaway var name collided with bash's special $_ variable.
wait_enter() {
  local prompt="${1:-Press ENTER to continue}"
  [[ -z "$TTY_DEV" ]] && return 0
  local _input
  read -r -p "  $prompt: " _input < "$TTY_DEV" || true
}

# ─── from lib/validate.sh ─────────────────────────────────────────────────
# lib/validate.sh — input format validators
#
# Pure functions: take a string, return 0 if valid, non-zero otherwise.
# No I/O, no side effects. Used by the *_validated prompt helpers.

validate_bot_token() { [[ "$1" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; }
validate_user_id()   { [[ "$1" =~ ^[0-9]+$ ]]; }
validate_workspace() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

# ─── from lib/preflight.sh ─────────────────────────────────────────────────
# lib/preflight.sh — checks run before any install action
#
# Each function fails (or warns) loudly with actionable instructions.
# Order matters: OS first, then prereq commands, then linger (which may
# need sudo and changes server state if the user agrees).
#
# Exposes:
#   preflight_os
#   preflight_prereqs
#   preflight_linger

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

# Offer to install a missing apt package; prompt confirmation, then sudo.
offer_apt_install() {
  local pkg="$1" desc="${2:-$1}"
  warn "$desc is missing"
  echo "    Will install via: sudo apt install -y $pkg"
  echo "    (You'll be prompted for your sudo password if not already cached.)"
  local yn
  ask "Install $pkg now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without $desc"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] sudo apt install -y $pkg"
    return 0
  fi
  sudo apt install -y "$pkg" >/dev/null || fail "Failed to install $pkg"
  ok "$pkg installed"
}

# Install Node.js v22 via NodeSource. We don't use distro packages because
# they're often too old for current Claude Code.
install_node() {
  warn "Node.js is not installed (required by Claude Code)"
  echo "    Will install Node.js v22 from NodeSource (official Node repo)."
  echo "    This runs:"
  echo "        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
  echo "        sudo apt install -y nodejs"
  echo "    You'll be prompted for your sudo password."
  local yn
  ask "Install Node.js v22 now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without Node.js"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] add NodeSource repo + apt install -y nodejs"
    return 0
  fi

  echo "  ↓ Adding NodeSource repository…"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1 \
    || fail "NodeSource setup failed"
  echo "  ↓ Installing nodejs…"
  sudo apt install -y nodejs >/dev/null 2>&1 || fail "apt install nodejs failed"
  ok "Node.js $(node --version) installed"
}

preflight_prereqs() {
  # Things every Linux server should have — fail if missing (we won't fight
  # broken base systems).
  for cmd in script curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fail "'$cmd' not found. Install util-linux + curl and re-run."
    fi
  done

  # Node.js — install via NodeSource if missing.
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    install_node
  fi
  ok "Node.js $(node --version), npm $(npm --version)"

  # jq — handy for idempotent JSON merges. Offer to install.
  if ! command -v jq >/dev/null 2>&1; then
    offer_apt_install "jq"
  else
    ok "jq present"
  fi

  # Bun — required by the telegram plugin's MCP server (see its .mcp.json:
  # command "bun" run start). Without it the plugin silently fails to spawn
  # and claude --channels runs but never polls Telegram.
  if ! command -v bun >/dev/null 2>&1; then
    install_bun
  fi
  # Ensure PATH has bun for the rest of this script run
  export PATH="$HOME/.bun/bin:$PATH"
  ok "bun $(bun --version 2>/dev/null || echo '?')"
}

# Install Bun via its official one-liner. User-level install under ~/.bun,
# no sudo needed. The telegram MCP server depends on this.
install_bun() {
  warn "Bun is not installed (required by the Telegram plugin's MCP server)"
  echo "    Will install Bun via its official one-liner:"
  echo "        curl -fsSL https://bun.sh/install | bash"
  echo "    Installs under ~/.bun (no sudo needed)."
  local yn
  ask "Install Bun now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without Bun (Telegram plugin requirement)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] curl -fsSL https://bun.sh/install | bash"
    return 0
  fi

  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 \
    || fail "Bun install failed"
  export PATH="$HOME/.bun/bin:$PATH"
  command -v bun >/dev/null 2>&1 || fail "Bun installed but not on PATH — check ~/.bun/bin"
  ok "Bun $(bun --version) installed"
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

# ─── from lib/steps.sh ─────────────────────────────────────────────────
# lib/steps.sh — the install steps themselves
#
# Each public function here is one step in the install flow. main() in
# install.sh calls them in order. Steps are idempotent: re-running on a
# configured server is safe and skips work that's already done.
#
# Exposes:
#   collect_inputs              — prompts for BOT_TOKEN / TG_USER_ID / WORKSPACE
#   install_claude              — installs Claude Code CLI to ~/.npm-global
#   install_telegram_plugin     — adds marketplace + plugin
#   write_configs               — .env + access.json (idempotent)
#   write_service               — systemd user unit + enable
#   oauth_setup                 — runs `claude setup-token` if not authed
#   start_service               — restart + verify the unit stays up
#   final_summary               — congratulatory output + useful commands

NPM_PREFIX="$HOME/.npm-global"

# ─── Welcome ──────────────────────────────────────────────────────────────
intro() {
  echo
  echo "  Welcome to Claudify."
  echo
  echo "  This installer will:"
  echo "    1. Verify and install missing system dependencies (Node.js, jq)"
  echo "    2. Walk you through creating a Telegram bot if you don't have one"
  echo "    3. Install Claude Code and the official Telegram channel plugin"
  echo "    4. Configure and start your bot as a systemd service"
  echo "    5. Pause once for Claude OAuth — log in with your subscription"
  echo
  echo "  Estimated time: 3–5 minutes (most of it is the npm install)."
  echo
  if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
    wait_enter "Press ENTER to continue, or Ctrl-C to abort"
  fi
}

# ─── Telegram setup walkthroughs ──────────────────────────────────────────
guide_botfather() {
  echo
  c_cyan "  ━ How to create a Telegram bot ━"
  echo
  echo "  Open Telegram and chat with BotFather:"
  echo "      https://t.me/BotFather"
  echo
  echo "  Then:"
  echo "      1. Send: /newbot"
  echo "      2. Pick a display name (any text — e.g. \"My Claude Assistant\")"
  echo "      3. Pick a username ending in 'bot' (e.g. \"my_claude_assistant_bot\")"
  echo "      4. BotFather replies with a token. Copy it. Looks like:"
  echo "          1234567890:ABCdef-GhIjKlMnOpQrStUvWxYz_12345"
  echo
  wait_enter "Press ENTER when you have your token"
}

guide_userinfobot() {
  echo
  c_cyan "  ━ How to find your Telegram user ID ━"
  echo
  echo "  Only your user ID will be allowed to talk to the bot — nobody else."
  echo
  echo "  Open Telegram and chat with userinfobot:"
  echo "      https://t.me/userinfobot"
  echo
  echo "  Then:"
  echo "      1. Send: /start"
  echo "      2. Copy the 'Id:' number — digits only (e.g. 7104012252)"
  echo
  wait_enter "Press ENTER when you have your user ID"
}

# ─── Inputs ────────────────────────────────────────────────────────────────
collect_inputs() {
  step "Telegram bot setup"

  # Bot token — show walkthrough only if not pre-filled via env.
  if [[ -z "${BOT_TOKEN:-}" ]]; then
    guide_botfather
  fi
  ask_secret_validated \
    "Paste your Telegram bot token" \
    BOT_TOKEN validate_bot_token \
    "Format: digits, colon, then characters (e.g. 1234567890:ABC-...)"
  ok "bot token format valid"

  # User ID — same pattern.
  if [[ -z "${TG_USER_ID:-}" ]]; then
    guide_userinfobot
  fi
  ask_validated \
    "Paste your Telegram user ID (numeric)" \
    "" TG_USER_ID validate_user_id \
    "Must be all digits."

  # Workspace — usually default is fine, no walkthrough.
  echo
  ask_validated \
    "Workspace folder name" \
    "claude-bot" WORKSPACE validate_workspace \
    "Letters, digits, dot, underscore, hyphen only — no spaces."
}

# ─── Claude Code ──────────────────────────────────────────────────────────
# Set up a user-local npm prefix so global installs don't need sudo.
setup_npm_prefix() {
  run "mkdir -p '$NPM_PREFIX'"
  if [[ "$DRY_RUN" -ne 1 ]]; then
    npm config set prefix "$NPM_PREFIX" >/dev/null
  fi
  export PATH="$NPM_PREFIX/bin:$PATH"

  local rc="$HOME/.bashrc"
  if [[ -f "$rc" ]] && ! grep -q "$NPM_PREFIX/bin" "$rc"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  [DRY] append PATH export to $rc"
    else
      echo "export PATH=\"$NPM_PREFIX/bin:\$PATH\"" >> "$rc"
      ok "added $NPM_PREFIX/bin to PATH in ~/.bashrc"
    fi
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
  ok_done "claude installed: $(claude --version 2>/dev/null | head -1)"
}

# ─── Telegram plugin ──────────────────────────────────────────────────────
install_telegram_plugin() {
  step "Install Telegram plugin"

  if claude plugin marketplace list 2>/dev/null | grep -q "claude-plugins-official"; then
    ok "marketplace already registered"
  else
    echo "  ↓ Adding official marketplace…"
    run "claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1"
    ok_done "marketplace registered"
  fi

  if claude plugin list 2>/dev/null | grep -q "telegram.*claude-plugins-official"; then
    ok "telegram plugin already installed"
  else
    echo "  ↓ Installing telegram plugin…"
    run "claude plugin install telegram@claude-plugins-official >/dev/null 2>&1"
    ok_done "telegram plugin installed"
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
# Load CLAUDE_CODE_OAUTH_TOKEN from here. Leading '-' makes it optional
# so the unit can be written before oauth_setup runs.
EnvironmentFile=-%h/.claude/credentials.env
Environment=PATH=%h/.bun/bin:%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
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
# `claude auth status` emits JSON like:
#   {"loggedIn": true, "authMethod": "claude.ai", ...}
# We match the exact JSON field rather than guessing at phrasing.
# Verified against Claude Code v2.1.114 on 2026-04-20.
claude_is_authed() {
  claude auth status 2>&1 | grep -qE '"loggedIn"[[:space:]]*:[[:space:]]*true'
}

# `claude setup-token` does NOT persist credentials. It generates a
# long-lived OAuth token, prints it to the terminal, and expects the
# operator to set CLAUDE_CODE_OAUTH_TOKEN in the environment of whoever
# runs `claude`. For a systemd-supervised bot that means loading the
# token from an EnvironmentFile on the unit. Store it here:
CREDS_FILE="$HOME/.claude/credentials.env"

oauth_setup() {
  step "Authenticate Claude (one-time)"

  # Already authed? Either from a prior install or from CLAUDE_CODE_OAUTH_TOKEN
  # already in the environment. Don't re-run setup-token.
  if [[ -s "$CREDS_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; . "$CREDS_FILE"; set +a
  fi
  if claude_is_authed; then
    ok "Claude is already authenticated"
    return 0
  fi

  c_yellow "  Claude needs a one-time OAuth login."
  echo "    A URL will appear below. Open it in a browser, log in to your"
  echo "    Claude subscription, and paste the resulting code back here."
  echo "    Claudify will then save the long-lived token for the systemd service."
  echo

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] would run: claude setup-token"
    echo "  [DRY] would write $CREDS_FILE"
    return 0
  fi

  # Run setup-token. Its output is already being tee'd to LOG_FILE by
  # ui.sh's setup_logging, so the long-lived token ends up captured there.
  if [[ -n "$TTY_DEV" ]]; then
    claude setup-token < "$TTY_DEV" || fail "claude setup-token failed"
  else
    claude setup-token || fail "claude setup-token failed"
  fi

  # Parse the sk-ant-oat01-... token out of the log we just appended to.
  local token
  token=$(grep -oE 'sk-ant-oat01-[A-Za-z0-9_-]+' "$LOG_FILE" | tail -1)
  if [[ -z "$token" ]]; then
    warn "Couldn't parse a long-lived token from setup-token output."
    echo "    Look for 'sk-ant-oat01-...' in $LOG_FILE and save it manually:"
    echo "        echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' > $CREDS_FILE"
    echo "        chmod 600 $CREDS_FILE"
    fail "Auth setup incomplete"
  fi

  # Persist for systemd (via EnvironmentFile on the unit) and export for
  # this shell so claude_is_authed can verify.
  mkdir -p "$(dirname "$CREDS_FILE")"
  umask 077
  printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$token" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  export CLAUDE_CODE_OAUTH_TOKEN="$token"
  ok "OAuth token saved to $CREDS_FILE (mode 600)"

  if claude_is_authed; then
    ok "Claude authenticated"
  else
    warn "Token saved but 'claude auth status' still reports not-logged-in:"
    claude auth status 2>&1 | sed 's/^/    /'
    fail "Unexpected — check $LOG_FILE"
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
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    c_yellow "╭────────────────────────────────────────────────────────────╮"
    banner_line "DRY-RUN complete  —  no changes were made" "\033[33m"
    c_yellow "╰────────────────────────────────────────────────────────────╯"
    echo
    echo "  Re-run without --dry-run to actually install:"
    echo "      bash install.sh"
    echo
    echo "  Dry-run log: $LOG_FILE"
    echo
    return
  fi

  c_green "╭────────────────────────────────────────────────────────────╮"
  banner_line "Claudify  —  install complete" "\033[32m"
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

# ─── main ────────────────────────────────────────────────────────
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
