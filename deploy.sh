#!/usr/bin/env bash
# claude-telegram-deploy: Bootstrap Claude Code + Telegram bot on a remote Linux server as a systemd user service.
# Usage: ./deploy.sh   (prompts for everything)
# Or pre-fill via env: SSH_HOST=... SSH_PORT=... SSH_USER=... SSH_KEY=... BOT_TOKEN=... TG_USER_ID=... WORKSPACE=... ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
c_cyan()  { printf '\033[36m%s\033[0m\n' "$*"; }
c_bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

step() { echo; c_cyan "━━━ $* ━━━"; }
ok()   { c_green "  ✓ $*"; }
warn() { c_yellow "  ⚠ $*"; }
fail() { c_red   "  ✗ $*"; exit 1; }

ask() {
  # ask "Prompt" "default" "VAR_NAME"
  local prompt="$1" default="${2:-}" varname="$3"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: $current (from env)"
    return
  fi
  local input
  if [[ -n "$default" ]]; then
    read -r -p "  $prompt [$default]: " input
    input="${input:-$default}"
  else
    read -r -p "  $prompt: " input
  fi
  printf -v "$varname" '%s' "$input"
}

ask_secret() {
  local prompt="$1" varname="$2"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: (set from env)"
    return
  fi
  local input
  read -r -s -p "  $prompt: " input
  echo
  printf -v "$varname" '%s' "$input"
}

# ──────────────────────────── Collect inputs ────────────────────────────

c_bold "╭────────────────────────────────────────────────────────────╮"
c_bold "│      Claude Code + Telegram Bot — Server Deploy Kit        │"
c_bold "╰────────────────────────────────────────────────────────────╯"

step "1/6  Connection details"
ask "SSH host (IP or hostname)" "" SSH_HOST
ask "SSH port"                  "22" SSH_PORT
ask "SSH user"                  "" SSH_USER
ask "SSH private key path"      "$HOME/.ssh/id_rsa" SSH_KEY

[[ -f "$SSH_KEY" ]] || fail "SSH key not found: $SSH_KEY"

step "2/6  Deployment details"
ask "Workspace folder name (goes under ~/workspace/)" "claude-bot" WORKSPACE

step "3/6  Telegram bot"
ask_secret "Telegram bot token (from @BotFather)" BOT_TOKEN
[[ -n "$BOT_TOKEN" ]] || fail "Bot token required"
ask        "Allowed Telegram user ID (from @userinfobot)" "" TG_USER_ID
[[ -n "$TG_USER_ID" ]] || fail "User ID required"

SSH_CMD=(ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_USER@$SSH_HOST")

echo
c_bold "About to deploy:"
echo "  → ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
echo "  → Workspace: ~/workspace/${WORKSPACE}"
echo "  → Allowlist: Telegram user ${TG_USER_ID}"
echo
read -r -p "Proceed? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ──────────────────────────── Test connection ───────────────────────────

step "4/6  Preflight"
"${SSH_CMD[@]}" 'echo connected; uname -s; which node npm curl 2>&1' \
  || fail "SSH connection failed"
ok "SSH reachable"

# ──────────────────────────── Remote install ────────────────────────────

step "5/6  Installing stack on remote server"

# Build remote bootstrap script
REMOTE_SCRIPT=$(cat <<REMOTE_EOF
set -euo pipefail
export PATH="\$HOME/.bun/bin:\$HOME/.npm-global/bin:\$PATH"

# Node.js
command -v node >/dev/null 2>&1 || { echo "FAIL: node.js not installed on server. Install manually first."; exit 1; }
echo "  ✓ node \$(node --version)"

# Bun
if ! command -v bun >/dev/null 2>&1; then
  echo "  ↓ Installing Bun…"
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1
fi
export PATH="\$HOME/.bun/bin:\$PATH"
echo "  ✓ bun \$(bun --version)"

# Claude Code
if ! command -v claude >/dev/null 2>&1; then
  echo "  ↓ Installing Claude Code…"
  npm install -g @anthropic-ai/claude-code >/dev/null 2>&1
fi
echo "  ✓ claude \$(claude --version 2>/dev/null | head -1)"

# Workspace dir
mkdir -p "\$HOME/workspace/${WORKSPACE}"
echo "  ✓ workspace at ~/workspace/${WORKSPACE}"

# Marketplace + plugin
if ! claude plugin marketplace list 2>/dev/null | grep -q claude-plugins-official; then
  echo "  ↓ Adding official marketplace…"
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1
fi
echo "  ✓ marketplace registered"

if ! claude plugin list 2>/dev/null | grep -q "telegram.*claude-plugins-official"; then
  echo "  ↓ Installing telegram plugin…"
  claude plugin install telegram@claude-plugins-official >/dev/null 2>&1
fi
echo "  ✓ telegram plugin installed"

# Token + allowlist
mkdir -p "\$HOME/.claude/channels/telegram"
echo "TELEGRAM_BOT_TOKEN=${BOT_TOKEN}" > "\$HOME/.claude/channels/telegram/.env"
chmod 600 "\$HOME/.claude/channels/telegram/.env"
echo "  ✓ bot token written"

cat > "\$HOME/.claude/channels/telegram/access.json" <<ACCESS
{
  "dmPolicy": "allowlist",
  "allowFrom": ["${TG_USER_ID}"],
  "groups": {},
  "pending": {}
}
ACCESS
echo "  ✓ allowlist set (user ${TG_USER_ID})"

# Systemd service
mkdir -p "\$HOME/.config/systemd/user"
cat > "\$HOME/.config/systemd/user/claude-telegram.service" <<SVC
[Unit]
Description=Claude Code with Telegram channel (${WORKSPACE})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=%h/.bun/bin:%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=%h
Environment=TERM=xterm-256color
WorkingDirectory=%h/workspace/${WORKSPACE}
ExecStart=/usr/bin/script -qfec "claude --channels plugin:telegram@claude-plugins-official" /dev/null
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SVC
echo "  ✓ systemd service written"

REMOTE_EOF
)

"${SSH_CMD[@]}" "bash -s" <<< "$REMOTE_SCRIPT" || fail "Remote install failed"
ok "Remote install complete"

# ───────────────────── Interactive auth pause ───────────────────────────

step "6/6  Authenticate Claude Code on server (manual step)"
c_yellow "  Claude Code auth requires a one-time interactive login."
echo
echo "  Open a NEW terminal, SSH into the server, and run:"
echo
c_bold  "      ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST"
c_bold  "      claude setup-token"
echo
echo "  Follow the browser prompts. When you see the 'authenticated' message,"
echo "  return here and press ENTER."
echo
read -r -p "  [ENTER when done, or 'skip' if already authenticated]: " skip

# Verify auth
"${SSH_CMD[@]}" 'bash -lc "PATH=\$HOME/.npm-global/bin:\$PATH; claude auth status 2>&1 | head -3"' \
  | grep -q '"loggedIn": true' || warn "Auth not detected — service will fail to start. Re-run setup-token."

# Start service
"${SSH_CMD[@]}" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); loginctl enable-linger 2>/dev/null || true; systemctl --user daemon-reload; systemctl --user enable claude-telegram.service; systemctl --user restart claude-telegram.service; sleep 3; systemctl --user status claude-telegram.service --no-pager | head -10' \
  || fail "Failed to start service"

echo
c_green "╭────────────────────────────────────────────────────────────╮"
c_green "│                  DEPLOYMENT COMPLETE                       │"
c_green "╰────────────────────────────────────────────────────────────╯"
echo
echo "  Send a message to your bot on Telegram to test."
echo
echo "  Useful remote commands:"
echo "    Status:  ssh ... 'systemctl --user status claude-telegram'"
echo "    Logs:    ssh ... 'journalctl --user -u claude-telegram -f'"
echo "    Stop:    ssh ... 'systemctl --user stop claude-telegram'"
echo "    Restart: ssh ... 'systemctl --user restart claude-telegram'"
echo
