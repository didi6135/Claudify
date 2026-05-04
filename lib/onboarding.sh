# lib/onboarding.sh — welcome banner + Telegram walkthroughs + input collection
#
# The user-facing first half of the install: explains what's about to
# happen, walks the operator through creating a Telegram bot if they
# don't have one, and collects BOT_TOKEN / TG_USER_ID / WORKSPACE.
#
# Constants `CLAUDIFY_TELEGRAM` etc. are defined in lib/claude.sh and
# referenced here at call time (not source time), so source order
# between the two doesn't matter for correctness.
#
# Resume-from-Ctrl-C: as soon as the user finishes pasting inputs in
# `_collect_inputs_fresh`, we drop them in `~/.claudify/.install-partial`
# (chmod 600). On any re-run, `_load_partial_state` silently sources
# that file before prompting, so an interrupted install picks up
# without re-pasting. The file is removed on successful finish (in
# `final_summary`) and on `--reset-config`.
#
# Exposes:
#   intro                 — welcome message, ENTER to continue
#   guide_botfather       — printed walkthrough for creating a Telegram bot
#   guide_userinfobot     — printed walkthrough for finding a Telegram user ID
#   collect_inputs        — prompts (or reuses, in --preserve-state) the 3 inputs
#   PARTIAL_STATE_FILE    — path of the resume file (consumed by service.sh
#                           on success and by args.sh on --reset-config)

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
  echo "  Safe to Ctrl-C at any point — re-running picks up where you stopped."
  echo
  if [[ "${DRY_RUN:-0}" -ne 1 && "${NON_INTERACTIVE:-0}" -ne 1 ]]; then
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

# ─── Resume-from-Ctrl-C state ────────────────────────────────────────────
# The file lives at the well-known path under $CLAUDIFY_ROOT (defined
# in lib/claude.sh; resolved at call time). Holds the bot token, so
# chmod 600 from the moment it exists.
PARTIAL_STATE_FILE_NAME=".install-partial"

_partial_state_path() {
  printf '%s/%s' "$CLAUDIFY_ROOT" "$PARTIAL_STATE_FILE_NAME"
}

# Write whatever the operator just pasted to disk so a Ctrl-C between
# now and `write_configs` doesn't waste their input. Caller is
# `_collect_inputs_fresh` after every prompt has succeeded.
_write_partial_state() {
  local f
  f="$(_partial_state_path)"
  mkdir -p "$CLAUDIFY_ROOT"
  umask 077
  {
    printf 'BOT_TOKEN=%s\n'  "$BOT_TOKEN"
    printf 'TG_USER_ID=%s\n' "$TG_USER_ID"
    printf 'WORKSPACE=%s\n'  "$WORKSPACE"
  } > "$f"
  chmod 600 "$f"
}

# If a prior interrupted run left a partial-state file, source it
# silently and announce one green line. Returns 0 if it loaded a full
# set (caller can skip prompting), 1 otherwise.
#
# Skipped intentionally:
#   - DRY_RUN=1     (don't read state during a preview)
#   - PRESERVE_STATE=1  (update flow has its own source-of-truth)
_load_partial_state() {
  [[ "${DRY_RUN:-0}"        -eq 1 ]] && return 1
  [[ "${PRESERVE_STATE:-0}" -eq 1 ]] && return 1

  local f
  f="$(_partial_state_path)"
  [[ -s "$f" ]] || return 1

  # Only resume if the operator hasn't pre-filled any of the three
  # via env vars — env wins, and partial file then gets refreshed at
  # the end of _collect_inputs_fresh anyway.
  [[ -n "${BOT_TOKEN:-}"  ]] && return 1
  [[ -n "${TG_USER_ID:-}" ]] && return 1
  [[ -n "${WORKSPACE:-}"  ]] && return 1

  # shellcheck disable=SC1090
  set -a; . "$f"; set +a

  if [[ -z "$BOT_TOKEN" || -z "$TG_USER_ID" || -z "$WORKSPACE" ]]; then
    # Corrupt or partial — pretend we didn't see it.
    return 1
  fi

  ok "resumed from previous attempt — using saved BOT_TOKEN, TG_USER_ID, WORKSPACE"
  return 0
}

# Called by args.sh when --reset-config is set, and by service.sh's
# final_summary on the success path. Idempotent.
clear_partial_state() {
  rm -f "$(_partial_state_path)" 2>/dev/null || true
}

# ─── Inputs ────────────────────────────────────────────────────────────────
# In --preserve-state mode (update.sh hot path), pull existing values
# from ~/.claudify so the operator doesn't have to retype them. Fail
# loudly if --preserve-state is set but no install exists to preserve.
_collect_inputs_preserved() {
  if [[ -z "${BOT_TOKEN:-}" && -s "$CLAUDIFY_TELEGRAM/.env" ]]; then
    BOT_TOKEN="$(grep '^TELEGRAM_BOT_TOKEN=' "$CLAUDIFY_TELEGRAM/.env" | cut -d= -f2-)"
    export BOT_TOKEN
  fi
  if [[ -z "${TG_USER_ID:-}" && -s "$CLAUDIFY_TELEGRAM/access.json" ]]; then
    TG_USER_ID="$(jq -r '.allowFrom[0] // empty' "$CLAUDIFY_TELEGRAM/access.json" 2>/dev/null || true)"
    export TG_USER_ID
  fi
  WORKSPACE="${WORKSPACE:-claude-bot}"
  export WORKSPACE

  if [[ -z "$BOT_TOKEN" || -z "$TG_USER_ID" ]]; then
    fail "--preserve-state but no existing config found in $CLAUDIFY_TELEGRAM.
     For a first-time install, omit --preserve-state and run install.sh normally."
  fi
  ok "BOT_TOKEN reused from $CLAUDIFY_TELEGRAM/.env"
  ok "TG_USER_ID reused from $CLAUDIFY_TELEGRAM/access.json ($TG_USER_ID)"
  ok "WORKSPACE = $WORKSPACE"
}

# Fresh install: prompt for whichever inputs aren't pre-filled via env.
# Each prompt skips its walkthrough if the value is already in the env.
_collect_inputs_fresh() {
  if [[ -z "${BOT_TOKEN:-}" ]]; then
    guide_botfather
  fi
  ask_secret_validated \
    "Paste your Telegram bot token" \
    BOT_TOKEN validate_bot_token \
    "Format: digits, colon, then characters (e.g. 1234567890:ABC-...)"
  ok "bot token format valid"

  if [[ -z "${TG_USER_ID:-}" ]]; then
    guide_userinfobot
  fi
  ask_validated \
    "Paste your Telegram user ID (numeric)" \
    "" TG_USER_ID validate_user_id \
    "Must be all digits."

  echo
  ask_validated \
    "Workspace folder name" \
    "claude-bot" WORKSPACE validate_workspace \
    "Letters, digits, dot, underscore, hyphen only — no spaces."

  # Persist immediately so a Ctrl-C between here and write_configs
  # doesn't lose what the operator just typed.
  _write_partial_state
}

collect_inputs() {
  step "Configuration"

  if [[ "${PRESERVE_STATE:-0}" -eq 1 ]]; then
    _collect_inputs_preserved
    return 0
  fi

  if _load_partial_state; then
    return 0
  fi

  _collect_inputs_fresh
}
