# lib/layout.sh — Claudify on-disk layout constants
#
# Everything Claudify owns lives under a single root so uninstall is
# `rm -rf $CLAUDIFY_ROOT`. Each engine's user-wide state (~/.claude,
# ~/.claude.json for Claude Code) stays where it is — it belongs to
# the engine, not Claudify.
#
# These paths are layout-specific, not engine-specific — they don't
# change when a different engine adapter is in use. Engine-specific
# paths (like NPM_PREFIX for engines that npm-install) live in the
# engine adapter under lib/engines/.
#
# 3.4.5 (multi-instance) will introduce
# `~/.claudify/instances/<name>/...` nesting; this file becomes the
# single source of truth for the new paths.
#
# Exposes:
#   CLAUDIFY_ROOT       — ~/.claudify (top-level Claudify dir)
#   CLAUDIFY_WORKSPACE  — ~/.claudify/workspace (engine WorkingDirectory)
#   CLAUDIFY_TELEGRAM   — ~/.claudify/telegram (channel state dir)
#   CREDS_FILE          — ~/.claudify/credentials.env (chmod 600 OAuth)

CLAUDIFY_ROOT="$HOME/.claudify"
CLAUDIFY_WORKSPACE="$CLAUDIFY_ROOT/workspace"
CLAUDIFY_TELEGRAM="$CLAUDIFY_ROOT/telegram"
CREDS_FILE="$CLAUDIFY_ROOT/credentials.env"
