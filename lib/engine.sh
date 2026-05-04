# lib/engine.sh — pick the engine adapter and source it
#
# The orchestrator and all step modules call abstract `engine_*`
# functions; they never reference a specific binary like `claude`.
# This file picks the right adapter and pulls it into scope.
#
# Engine selection:
#   - Default: claude-code
#   - Override: CLAUDIFY_ENGINE=<id> bash install.sh
#
# Adapters live at `lib/engines/<id>.sh` and implement the contract
# documented in `lib/engines/README.md` (see also docs/architecture.md
# §6 and ADR 0005).
#
# In `dist/install.sh`, build.sh has already concatenated the adapter
# into the single file, so the runtime source below is a no-op
# (functions already defined).
#
# Exposes:
#   CLAUDIFY_ENGINE      — engine ID (matches `lib/engines/<id>.sh`)
#   engine_id            — echo the current engine ID

CLAUDIFY_ENGINE="${CLAUDIFY_ENGINE:-claude-code}"

engine_id() {
  printf '%s' "$CLAUDIFY_ENGINE"
}

# In dev mode (sourced from install.sh), pull the adapter into scope.
# In dist mode (sourced from the built one-file install.sh), the
# adapter functions are already defined inline, so this is a no-op.
if ! declare -f engine_install >/dev/null 2>&1; then
  _adapter="${LIB_DIR:-${SCRIPT_DIR:-.}/lib}/engines/${CLAUDIFY_ENGINE}.sh"
  if [[ ! -f "$_adapter" ]]; then
    fail "engine adapter not found: $_adapter
     Available: $(ls "${LIB_DIR:-./lib}/engines"/*.sh 2>/dev/null | xargs -rn1 basename | sed 's/\.sh$//' | tr '\n' ' ')"
  fi
  # shellcheck disable=SC1090
  . "$_adapter"
  unset _adapter
fi
