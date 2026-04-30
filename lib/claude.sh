# lib/claude.sh — Claude Code engine + Telegram plugin install + auth probe
#
# This module owns everything that talks to the `claude` CLI directly:
# installing it, installing its plugin, seeding its first-run state,
# checking whether it's authenticated. In 3.4.3 these get split between
# a real engine adapter under lib/engines/claude-code.sh and engine-
# agnostic glue. For now it's all here so 3.4.2 stays a pure split.
#
# Also defines the Claudify-layout constants that everything else
# references. They live here because the layout exists *because* of
# the engine — `~/.claudify/credentials.env` holds Claude OAuth, the
# workspace is the engine's CWD, etc. 3.4.3 will reshuffle.
#
# Exposes:
#   constants:
#     NPM_PREFIX            — user-local npm prefix (avoids sudo for -g installs)
#     CLAUDIFY_ROOT         — ~/.claudify
#     CLAUDIFY_WORKSPACE    — ~/.claudify/workspace (claude WorkingDirectory)
#     CLAUDIFY_TELEGRAM     — ~/.claudify/telegram (channel state dir)
#     CREDS_FILE            — ~/.claudify/credentials.env (chmod 600 OAuth)
#   functions:
#     setup_npm_prefix      — point npm at NPM_PREFIX, persist PATH in ~/.bashrc
#     install_claude        — npm install -g @anthropic-ai/claude-code (idempotent)
#     install_telegram_plugin — register marketplace + install plugin (idempotent)
#     seed_claude_state     — pre-accept onboarding/trust + auto-allow plugin tools
#     claude_is_authed      — 0 if `claude auth status` says loggedIn:true

# ─── Constants ────────────────────────────────────────────────────────────
NPM_PREFIX="$HOME/.npm-global"

# Everything Claudify owns lives under a single root so uninstall is
# `rm -rf $CLAUDIFY_ROOT`. Claude Code's own user-wide state
# (~/.claude, ~/.claude.json) stays where it is — it belongs to Claude.
CLAUDIFY_ROOT="$HOME/.claudify"
CLAUDIFY_WORKSPACE="$CLAUDIFY_ROOT/workspace"
CLAUDIFY_TELEGRAM="$CLAUDIFY_ROOT/telegram"
CREDS_FILE="$CLAUDIFY_ROOT/credentials.env"

# ─── npm prefix ───────────────────────────────────────────────────────────
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

# ─── Claude Code ──────────────────────────────────────────────────────────
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

# ─── Claude Code first-run state ──────────────────────────────────────────
# On first launch, Claude Code's TUI asks about theme + workspace trust.
# A systemd-spawned service has no one to answer those prompts, so it
# sits forever and the channel plugin never spawns. We pre-seed the
# state it would have written after a successful manual onboarding.
#
# Keys verified against Claude Code v2.1.116 binary strings:
#   hasCompletedOnboarding                          (top-level, user-wide)
#   projects[<abs-path>].hasTrustDialogAccepted     (per-workspace trust)
#   projects[<abs-path>].hasCompletedProjectOnboarding
_seed_claude_json() {
  local config="$HOME/.claude.json"
  local wsdir="$1"

  # Merge with any existing content so we don't clobber fields claude
  # may have already written (userID, firstStartTime, migration flags).
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

# Auto-allow the telegram plugin's tools. Without this the bot prompts
# the user (via Telegram) to approve every reply/react/edit. Owner
# already trusts their own bot.
_seed_settings_json() {
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$settings")"

  local existing_s='{}'
  [[ -s "$settings" ]] && existing_s=$(cat "$settings")

  printf '%s' "$existing_s" | jq '
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

seed_claude_state() {
  step "Seed Claude Code first-run state"

  local wsdir="$CLAUDIFY_WORKSPACE"
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

# ─── Auth probe ───────────────────────────────────────────────────────────
# `claude auth status` emits JSON like:
#   {"loggedIn": true, "authMethod": "claude.ai", ...}
# We match the exact JSON field rather than guessing at phrasing.
# Verified against Claude Code v2.1.114 on 2026-04-20.
claude_is_authed() {
  claude auth status 2>&1 | grep -qE '"loggedIn"[[:space:]]*:[[:space:]]*true'
}
