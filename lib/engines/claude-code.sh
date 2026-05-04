# lib/engines/claude-code.sh — Claude Code engine adapter
#
# Implements the engine contract from `lib/engines/README.md`. Today
# this is the only adapter; future adapters (Gemini CLI, OpenAI Codex,
# etc.) ship as additional `lib/engines/<id>.sh` files implementing
# the same contract.
#
# All Claude-Code-specific knowledge lives here:
#   - npm-installable binary `@anthropic-ai/claude-code`
#   - `claude auth status` JSON probe
#   - `claude setup-token` interactive OAuth + sk-ant-oat01-… token
#   - `claude plugin marketplace add ...` + `claude plugin install ...`
#   - `~/.claude.json` first-run-state seeding (onboarding + trust)
#   - `~/.claude/settings.json` permission-allow seeding
#   - `claude --permission-mode bypassPermissions --channels plugin:...`
#     systemd ExecStart — wrapped in /usr/bin/script for a real PTY
#
# Layout constants (CLAUDIFY_ROOT etc.) come from lib/layout.sh.
# UI/IO helpers (step, ok, warn, fail, run, ok_done) come from lib/ui.sh
# and lib/args.sh. TTY_DEV comes from lib/prompts.sh. LOG_FILE comes
# from lib/ui.sh.
#
# Exposes (the engine contract):
#   engine_install                  — npm install -g @anthropic-ai/claude-code
#   engine_seed_state <wsdir>       — pre-accept Claude TUI onboarding + tools
#   engine_install_channel_plugin <name>  — register marketplace + install plugin
#   engine_auth_check               — 0 if authed, non-zero otherwise
#   engine_auth_setup               — interactive OAuth flow + token persistence
#   engine_run_args                 — echo full ExecStart command for systemd
#   engine_status                   — echo JSON status object
#   engine_uninstall                — no-op (engine binary shared across instances)

# ─── Constants (engine-specific) ──────────────────────────────────────────
# user-local npm prefix so `npm install -g` doesn't need sudo
NPM_PREFIX="$HOME/.npm-global"

# Where Claude Code's plugin marketplace lives — this is the only one
# we register today. New marketplaces → add a new helper, don't change
# this constant.
CLAUDE_PLUGIN_MARKETPLACE="anthropics/claude-plugins-official"

# Env-var name Claude Code reads to skip OAuth on each invocation.
# Per-engine — never surface as a generic name.
CLAUDE_OAUTH_ENV_VAR="CLAUDE_CODE_OAUTH_TOKEN"

# ─── Private helpers ──────────────────────────────────────────────────────
_npm_prefix_setup() {
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

# Merge headless-friendly fields into ~/.claude.json so the systemd
# unit doesn't sit forever at the theme + workspace-trust prompts.
# Keys verified against Claude Code v2.1.116:
#   hasCompletedOnboarding                          (top-level, user-wide)
#   projects[<abs-path>].hasTrustDialogAccepted     (per-workspace)
#   projects[<abs-path>].hasCompletedProjectOnboarding
_seed_claude_json() {
  local config="$HOME/.claude.json"
  local wsdir="$1"
  local existing='{}'
  [[ -s "$config" ]] && existing=$(cat "$config")

  printf '%s' "$existing" | jq --arg dir "$wsdir" '
    .hasCompletedOnboarding = true
    | .bypassPermissionsModeAccepted = true
    | .projects = (.projects // {})
    | .projects[$dir] = ((.projects[$dir] // {}) + {
        hasTrustDialogAccepted: true,
        hasCompletedProjectOnboarding: true,
        allowedTools: (.projects[$dir].allowedTools // [])
      })
  ' > "$config.tmp" && mv "$config.tmp" "$config"

  ok "seeded ~/.claude.json (onboarding + trust for $wsdir)"
}

# Auto-allow the telegram plugin's tools so the bot doesn't prompt the
# operator (via Telegram!) to approve every reply/react/edit.
_seed_settings_json() {
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$settings")"
  local existing='{}'
  [[ -s "$settings" ]] && existing=$(cat "$settings")

  printf '%s' "$existing" | jq '
    .permissions = (.permissions // {})
    | .permissions.allow = (
        ((.permissions.allow // []) + [
          "mcp__plugin_telegram_telegram__reply",
          "mcp__plugin_telegram_telegram__react",
          "mcp__plugin_telegram_telegram__edit_message",
          "mcp__plugin_telegram_telegram__download_attachment"
        ]) | unique
      )
  ' > "$settings.tmp" && mv "$settings.tmp" "$settings"

  ok "auto-allowed telegram plugin tools in ~/.claude/settings.json"
}

# Run `claude setup-token` in a real PTY (`script(1)`) so its TUI
# renders cleanly. Captures all output to $1 so the long-lived token
# can be parsed out afterwards. Stdin/stdout pinned to the real
# terminal to bypass setup_logging's tee pipe — otherwise the TUI
# detects no-TTY-on-stdout and renders a degraded "redraw splash on
# every spinner tick" mode.
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
    echo "        echo '${CLAUDE_OAUTH_ENV_VAR}=<token>' > $CREDS_FILE"
    echo "        chmod 600 $CREDS_FILE"
    fail "Auth setup incomplete"
  fi

  mkdir -p "$(dirname "$CREDS_FILE")"
  umask 077
  printf '%s=%s\n' "$CLAUDE_OAUTH_ENV_VAR" "$token" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  export "${CLAUDE_OAUTH_ENV_VAR}=${token}"
  ok "OAuth token saved to $CREDS_FILE (mode 600)"
}

# ─── Contract: engine_install ─────────────────────────────────────────────
engine_install() {
  step "Install Claude Code"
  _npm_prefix_setup

  if command -v claude >/dev/null 2>&1; then
    ok "claude already installed: $(claude --version 2>/dev/null | head -1)"
    return 0
  fi

  echo "  ↓ npm install -g @anthropic-ai/claude-code"
  run "npm install -g @anthropic-ai/claude-code >/dev/null 2>&1"
  ok_done "claude installed: $(claude --version 2>/dev/null | head -1)"
}

# ─── Contract: engine_seed_state <wsdir> ──────────────────────────────────
# Engines that don't need any first-run state seeding can implement
# this as a no-op `return 0`.
engine_seed_state() {
  step "Seed Claude Code first-run state"

  local wsdir="${1:-$CLAUDIFY_WORKSPACE}"
  mkdir -p "$wsdir"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] merge hasCompletedOnboarding + trust($wsdir) into ~/.claude.json"
    echo "  [DRY] merge permissions.allow for telegram plugin tools into ~/.claude/settings.json"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required for seeding ~/.claude.json but was not found"
  fi

  _seed_claude_json "$wsdir"
  _seed_settings_json
}

# ─── Contract: engine_install_channel_plugin <name> ───────────────────────
# Today: marketplace + plugin from claude-plugins-official.
# An engine that has no plugin model can implement this as no-op.
engine_install_channel_plugin() {
  local plugin="${1:-telegram}"
  step "Install $plugin plugin"

  if claude plugin marketplace list 2>/dev/null | grep -q "$CLAUDE_PLUGIN_MARKETPLACE"; then
    ok "marketplace already registered"
  else
    echo "  ↓ Adding official marketplace…"
    run "claude plugin marketplace add $CLAUDE_PLUGIN_MARKETPLACE >/dev/null 2>&1"
    ok_done "marketplace registered"
  fi

  if claude plugin list 2>/dev/null | grep -q "${plugin}.*claude-plugins-official"; then
    ok "$plugin plugin already installed"
  else
    echo "  ↓ Installing $plugin plugin…"
    run "claude plugin install ${plugin}@claude-plugins-official >/dev/null 2>&1"
    ok_done "$plugin plugin installed"
  fi
}

# ─── Contract: engine_auth_check ──────────────────────────────────────────
# `claude auth status` emits JSON like {"loggedIn": true, ...}. Match
# the exact JSON field rather than guessing at phrasing.
# Verified against Claude Code v2.1.114 on 2026-04-20.
engine_auth_check() {
  claude auth status 2>&1 | grep -qE '"loggedIn"[[:space:]]*:[[:space:]]*true'
}

# ─── Contract: engine_auth_setup ──────────────────────────────────────────
# Interactive flow + token persistence. Caller (lib/oauth.sh) handles
# "is auth needed?" / "preserve-state skip" / final-verification logic;
# this function only knows how to drive `claude setup-token` and write
# the result.
#
# In dry-run, prints what *would* happen and returns success.
engine_auth_setup() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] would run: claude setup-token"
    echo "  [DRY] would write $CREDS_FILE"
    return 0
  fi

  local capture
  capture="$(mktemp -t claudify-oauth-XXXXXX)"
  chmod 600 "$capture"

  _run_setup_token   "$capture"
  _persist_oauth_token "$capture"

  shred -u "$capture" 2>/dev/null || rm -f "$capture"
}

# ─── Contract: engine_run_args ────────────────────────────────────────────
# Echo the full ExecStart command for the systemd unit. Each engine
# decides whether it needs script(1) wrapping (Claude Code's TUI
# does — without a real PTY the channel plugin never spawns).
#
# Today's wiring: Telegram via plugin:telegram@claude-plugins-official.
# 3.4.4 (manifest) will pass channel/plugin set as args.
engine_run_args() {
  printf '%s' '/usr/bin/script -qfec "claude --permission-mode bypassPermissions --channels plugin:telegram@claude-plugins-official" /dev/null'
}

# ─── Contract: engine_status ──────────────────────────────────────────────
engine_status() {
  local version="" authed=false
  if command -v claude >/dev/null 2>&1; then
    version="$(claude --version 2>/dev/null | head -1)"
    if engine_auth_check; then
      authed=true
    fi
  fi
  jq -n --arg engine "claude-code" --arg version "$version" --argjson authed "$authed" '
    {engine: $engine, version: $version, authenticated: $authed}
  '
}

# ─── Contract: engine_uninstall ───────────────────────────────────────────
# No-op for Claude Code: the binary lives at ~/.npm-global/bin/claude
# and is shared across all Claudify instances on this host. Per-bot
# state under $CLAUDIFY_ROOT is removed by uninstall.sh's `rm -rf`,
# not by us. Returning 0 means "engine has nothing claudify-specific
# to clean up beyond what's already under $CLAUDIFY_ROOT".
engine_uninstall() {
  return 0
}
