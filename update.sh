#!/usr/bin/env bash
# update.sh — refresh Claudify to the latest main branch, in place.
#
# Usage (on the target server):
#   bash <(curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/update.sh)
#   bash update.sh
#
# What it does:
#   Fetches the latest dist/install.sh from main and runs it with
#   --preserve-state --non-interactive. That means:
#     • BOT_TOKEN (~/.claudify/telegram/.env)       — preserved
#     • TG_USER_ID allowlist (access.json)          — preserved
#     • CLAUDE_CODE_OAUTH_TOKEN (credentials.env)   — preserved
#     • systemd unit file                            — rewritten (so unit
#                                                      changes land)
#     • ~/.claude.json onboarding + trust seed       — reseeded (idempotent)
#     • claude plugin + bun                          — updated if available
#     • service                                      — restarted
#
# Typically takes 10-20s on a healthy install. No OAuth prompts, no
# questions.
#
# If your install doesn't exist yet, this script will fail and tell
# you to run install.sh instead.

set -euo pipefail

# Refuse to run if no Claudify state exists — update implies there's
# something to update.
if [[ ! -d "$HOME/.claudify" ]] || [[ ! -s "$HOME/.claudify/telegram/.env" ]]; then
  echo "No Claudify install found at ~/.claudify."
  echo
  echo "This script updates an existing install. For a first-time install, run:"
  echo
  echo "    curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash"
  echo
  exit 1
fi

curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh \
  | bash -s -- --preserve-state
