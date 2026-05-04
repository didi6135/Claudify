# lib/service.sh — systemd user unit + service start + final summary
#
# Writes the user-mode systemd unit, enables it, restarts it, and
# verifies it stays up. Also owns the final-summary banner.
#
# The ExecStart command line comes from `engine_run_args` (engine
# adapter — 3.4.3). Today's only adapter is Claude Code, which wraps
# the run in /usr/bin/script for a real PTY.
#
# The unit name is `claude-telegram.service` today. 3.4.5 (multi-
# instance) renames it to `claudify-<instance>.service` with a
# migration step. Don't rename here.
#
# Constants `CLAUDIFY_WORKSPACE` come from lib/layout.sh.
#
# Exposes:
#   write_service    — write + enable user systemd unit (idempotent)
#   start_service    — restart + verify it stayed up after 3 s
#   final_summary    — congratulatory output + useful commands

# ─── systemd user service ─────────────────────────────────────────────────
write_service() {
  step "Install systemd service"

  local svc_dir="$HOME/.config/systemd/user"
  local svc_path="$svc_dir/claude-telegram.service"
  run "mkdir -p '$svc_dir'"
  run "mkdir -p '$CLAUDIFY_WORKSPACE'"

  # Engine decides the ExecStart line — Claude Code wraps in script(1)
  # for a real PTY; future engines may do something else.
  local execstart
  execstart="$(engine_run_args)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] write $svc_path"
  else
    cat > "$svc_path" <<SVC
[Unit]
Description=Claudify — Telegram bot ($WORKSPACE)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# All per-bot state lives under ~/.claudify (self-contained; rm -rf to uninstall).
# Leading '-' on EnvironmentFile makes it optional so the unit can be
# written before oauth_setup populates credentials.env.
EnvironmentFile=-%h/.claudify/credentials.env
Environment=PATH=%h/.bun/bin:%h/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=%h
Environment=TERM=xterm-256color
Environment=TELEGRAM_STATE_DIR=%h/.claudify/telegram
WorkingDirectory=%h/.claudify/workspace
ExecStart=$execstart
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

  # Install finished cleanly — drop the resume crumbs.
  clear_partial_state

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
