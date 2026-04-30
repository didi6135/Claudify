# lib/oauth.sh — Claude OAuth setup + token persistence for systemd
#
# `claude setup-token` prints a long-lived OAuth token to the terminal
# but does NOT persist it. The bot service needs it via an
# EnvironmentFile, so this module captures the token while running
# setup-token, parses it, and writes it to $CREDS_FILE with chmod 600.
#
# Why we wrap `claude setup-token` in script(1):
#   ui.sh's setup_logging does `exec > >(tee -a $LOG_FILE)`, which
#   makes stdout a pipe — not a TTY. Claude Code's TUI then thinks
#   it's running headless and falls back to a degraded render that
#   re-prints the entire splash screen on every spinner tick (looks
#   like dozens of stacked "Welcome to Claude Code" banners).
#   `script -qfec CMD CAPTURE` gives the child a real PTY and copies
#   every byte to CAPTURE; pinning stdin/stdout to $TTY_DEV bypasses
#   the tee so the user sees a live, in-place TUI render.
#
# Constants `CREDS_FILE`, `TTY_DEV` come from lib/claude.sh and
# lib/prompts.sh. `claude_is_authed` lives in lib/claude.sh.
#
# Exposes:
#   oauth_setup    — idempotent: skip if already authed, else run setup-token + persist

# Run `claude setup-token` in a real PTY (`script`), with output
# *also* copied to $1 so _persist_oauth_token can grep the long-lived
# token out of it. Stdin/stdout pinned to the real terminal.
_run_setup_token() {
  local capture="$1"

  if [[ -z "$TTY_DEV" ]]; then
    fail "OAuth requires an interactive terminal — no TTY detected.
     Re-run install.sh from a real terminal session, not a non-interactive pipe."
  fi

  if ! command -v script >/dev/null 2>&1; then
    fail "OAuth requires /usr/bin/script (util-linux). Install with: apt install bsdmainutils util-linux"
  fi

  script -qfec "claude setup-token" "$capture" \
    < "$TTY_DEV" > "$TTY_DEV" 2>&1 \
    || fail "claude setup-token failed"
}

# Parse the long-lived sk-ant-oat01-… token out of the capture file
# and write it to $CREDS_FILE so systemd can pick it up via
# EnvironmentFile.
_persist_oauth_token() {
  local capture="$1"

  local token
  token=$(grep -oE 'sk-ant-oat01-[A-Za-z0-9_-]+' "$capture" | tail -1)
  if [[ -z "$token" ]]; then
    warn "Couldn't parse a long-lived token from setup-token output."
    echo "    Look in $capture for 'sk-ant-oat01-...' and save it manually:"
    echo "        echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' > $CREDS_FILE"
    echo "        chmod 600 $CREDS_FILE"
    fail "Auth setup incomplete"
  fi

  mkdir -p "$(dirname "$CREDS_FILE")"
  umask 077
  printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$token" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  export CLAUDE_CODE_OAUTH_TOKEN="$token"
  ok "OAuth token saved to $CREDS_FILE (mode 600)"
}

oauth_setup() {
  step "Authenticate Claude (one-time)"

  # Preserve-state (update.sh path): if credentials.env exists we
  # trust the operator's current token even if claude auth status
  # disagrees. They'd fix it via a fresh install, not via update.
  if [[ "${PRESERVE_STATE:-0}" -eq 1 && -s "$CREDS_FILE" ]]; then
    ok "credentials.env present (preserved; not re-exchanging OAuth)"
    return 0
  fi

  # Already authed? Either from a prior install or from
  # CLAUDE_CODE_OAUTH_TOKEN already in the environment.
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

  # Capture file holds setup-token's full output (incl. the long-lived
  # token). chmod 600 immediately, shred when done — never leave it on
  # disk.
  local capture
  capture="$(mktemp -t claudify-oauth-XXXXXX)"
  chmod 600 "$capture"

  _run_setup_token   "$capture"
  _persist_oauth_token "$capture"

  shred -u "$capture" 2>/dev/null || rm -f "$capture"

  if claude_is_authed; then
    ok "Claude authenticated"
  else
    warn "Token saved but 'claude auth status' still reports not-logged-in:"
    claude auth status 2>&1 | sed 's/^/    /'
    fail "Unexpected — check $LOG_FILE"
  fi
}
