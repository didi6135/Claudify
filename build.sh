#!/usr/bin/env bash
# build.sh — produce dist/install.sh from the modular sources in lib/
#
# The local install.sh sources lib/*.sh at runtime. That works when the
# repo is checked out, but not when the script is fetched via
# `curl … | bash` (lib/ files aren't reachable). build.sh concatenates
# everything into a single self-contained file under dist/ that we can
# serve from a public URL in Phase 2.
#
# Usage:
#   bash build.sh
#
# Output:
#   dist/install.sh    (single-file, executable)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
OUT_DIR="$SCRIPT_DIR/dist"
OUT="$OUT_DIR/install.sh"

# Order must match the source order in install.sh.
# Engine adapters under lib/engines/ are concatenated *before*
# lib/engine.sh so the adapter's functions exist by the time the
# dispatcher's "if not declared, source it" check runs (it's a no-op
# in dist mode because functions are already defined).
MODULES=(
  ui.sh
  args.sh
  prompts.sh
  validate.sh
  preflight.sh
  layout.sh
  engines/claude-code.sh
  engine.sh
  onboarding.sh
  configs.sh
  service.sh
  oauth.sh
)

# Pull SCRIPT_VERSION out of install.sh so dist matches.
SCRIPT_VERSION="$(grep -m1 '^SCRIPT_VERSION=' "$SCRIPT_DIR/install.sh" | cut -d'"' -f2)"

mkdir -p "$OUT_DIR"

{
  cat <<HEADER
#!/usr/bin/env bash
# claudify install.sh — bootstrap Claude Code + Telegram on this Linux server
#
# THIS FILE IS GENERATED. Do not edit directly.
# Source:  https://github.com/didi6135/Claudify
# Edit:    install.sh + lib/*.sh in the source repo, then run \`bash build.sh\`
# Built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# Usage (on a target Linux server):
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/didi6135/Claudify/main/dist/install.sh | bash -s -- --dry-run

set -euo pipefail

SCRIPT_VERSION="$SCRIPT_VERSION"
HEADER

  for m in "${MODULES[@]}"; do
    echo
    echo "# ─── from lib/$m ─────────────────────────────────────────────────"
    # Strip module-internal blank-line padding at start, keep the rest.
    awk 'BEGIN{started=0} /^./{started=1} started{print}' "$LIB_DIR/$m"
  done

  echo
  echo "# ─── main ────────────────────────────────────────────────────────"
  # Take the main() function and the trailing call from install.sh
  awk '/^main\(\)/,/^main "\$@"$/' "$SCRIPT_DIR/install.sh"
} > "$OUT"

chmod +x "$OUT"

LINES="$(wc -l < "$OUT" | tr -d ' ')"
echo "Built $OUT ($LINES lines)"
