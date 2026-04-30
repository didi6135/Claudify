# lib/oauth.sh — Claude OAuth setup + token persistence for systemd
#
# `claude setup-token` prints a long-lived OAuth token to the terminal
# but does NOT persist it. The bot service needs it via an
# EnvironmentFile, so this module captures the token from the install
# log (which ui.sh's setup_logging is tee-ing) and writes it to
# $CREDS_FILE with chmod 600.
#
# Constants `CREDS_FILE`, `LOG_FILE`, `TTY_DEV` come from lib/claude.sh
# and lib/ui.sh / lib/prompts.sh respectively. `claude_is_authed` lives
# in lib/claude.sh.
#
# Exposes:
#   oauth_setup    — idempotent: skip if already authed, else run setup-token + persist

# Run claude setup-token interactively. Output is being tee'd to
# LOG_FILE by ui.sh's setup_logging — that's how we recover the token
# afterwards.
_run_setup_token() {
  if [[ -n "$TTY_DEV" ]]; then
    claude setup-token < "$TTY_DEV" || fail "claude setup-token failed"
  else
    claude setup-token || fail "claude setup-token failed"
  fi
}

# Parse the long-lived sk-ant-oat01-… token out of LOG_FILE and write
# it to $CREDS_FILE so systemd can pick it up via EnvironmentFile.
_persist_oauth_token() {
  local token
  token=$(grep -oE 'sk-ant-oat01-[A-Za-z0-9_-]+' "$LOG_FILE" | tail -1)
  if [[ -z "$token" ]]; then
    warn "Couldn't parse a long-lived token from setup-token output."
    echo "    Look for 'sk-ant-oat01-...' in $LOG_FILE and save it manually:"
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

  _run_setup_token
  _persist_oauth_token

  if claude_is_authed; then
    ok "Claude authenticated"
  else
    warn "Token saved but 'claude auth status' still reports not-logged-in:"
    claude auth status 2>&1 | sed 's/^/    /'
    fail "Unexpected — check $LOG_FILE"
  fi
}
