# lib/oauth.sh — engine-agnostic OAuth orchestration
#
# Owns the user-facing flow: "is auth needed? / show what's about to
# happen / preserve-state skip / verify after". Hands off to the
# active engine's `engine_auth_setup` for the actual interactive
# token-capture work — *that's* where engine-specific knowledge lives
# (which CLI to invoke, how to parse the captured token, which env
# var name persists into systemd's EnvironmentFile, etc.).
#
# 3.4.3 split this in two: this file is the orchestrator; the engine
# adapter at lib/engines/<id>.sh does the actual auth.
#
# Layout constants (CREDS_FILE) come from lib/layout.sh.
# `engine_auth_check` and `engine_auth_setup` come from the active
# engine adapter, sourced via lib/engine.sh.
#
# Exposes:
#   oauth_setup    — idempotent: skip if authed, else run engine_auth_setup + verify

oauth_setup() {
  step "Authenticate $(engine_id) (one-time)"

  # Preserve-state (update.sh path): if credentials.env exists we
  # trust the operator's current token even if the engine disagrees.
  # They'd fix it via a fresh install, not via update.
  if [[ "${PRESERVE_STATE:-0}" -eq 1 && -s "$CREDS_FILE" ]]; then
    ok "credentials.env present (preserved; not re-exchanging OAuth)"
    return 0
  fi

  # Already authed? Either from a prior install or from the engine's
  # OAuth env var already in the environment.
  if [[ -s "$CREDS_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; . "$CREDS_FILE"; set +a
  fi
  if engine_auth_check; then
    ok "$(engine_id) is already authenticated"
    return 0
  fi

  c_yellow "  $(engine_id) needs a one-time OAuth login."
  echo "    A URL will appear below. Open it in a browser, log in to your"
  echo "    Claude subscription, and paste the resulting code back here."
  echo "    Claudify will then save the long-lived token for the systemd service."
  echo

  engine_auth_setup

  # Dry-run: engine_auth_setup printed what *would* happen, no real
  # auth, no verify needed.
  [[ "$DRY_RUN" -eq 1 ]] && return 0

  if engine_auth_check; then
    ok "$(engine_id) authenticated"
  else
    warn "Token saved but auth status still reports not-logged-in:"
    fail "Unexpected — check $LOG_FILE"
  fi
}
