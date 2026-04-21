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

# ─── Claude Code first-run state ──────────────────────────────────────────
# On first launch, Claude Code's TUI asks about theme + workspace trust.
# A systemd-spawned service has no one to answer those prompts, so it
# sits forever and the channel plugin never spawns. We pre-seed the
# state it would have written after a successful manual onboarding.
#
# Keys verified against Claude Code v2.1.116 binary strings:
#   hasCompletedOnboarding                    (top-level, user-wide)
#   projects[<abs-path>].hasTrustDialogAccepted  (per-workspace trust)
#   projects[<abs-path>].hasCompletedProjectOnboarding
seed_claude_state() {
  step "Seed Claude Code first-run state"

  local config="$HOME/.claude.json"
  local wsdir="$HOME/workspace/$WORKSPACE"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] merge hasCompletedOnboarding + trust($wsdir) into $config"
    return 0
  fi

  # Merge with any existing content so we don't clobber fields claude
  # may have already written (userID, firstStartTime, migration flags).
  local existing='{}'
  [[ -s "$config" ]] && existing=$(cat "$config")

  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required for seeding ~/.claude.json but was not found"
  fi

  printf '%s' "$existing" | jq --arg dir "$wsdir" '
    .hasCompletedOnboarding = true
    | .projects = (.projects // {})
    | .projects[$dir] = ((.projects[$dir] // {}) + {
        hasTrustDialogAccepted: true,
        hasCompletedProjectOnboarding: true,
        allowedTools: (.projects[$dir].allowedTools // [])
      })
  ' > "$config.tmp" && mv "$config.tmp" "$config"

  ok "seeded ~/.claude.json (onboarding + trust for $wsdir)"
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
