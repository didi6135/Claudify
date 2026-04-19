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

# ─── Inputs ────────────────────────────────────────────────────────────────
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
# Permissive grep until we observe real `claude auth status` output during
# the first end-to-end install (Phase 1 task 1.B.10). Tighten then.
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
