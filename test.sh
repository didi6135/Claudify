#!/usr/bin/env bash
# test.sh — repo-root entry for both test suites.
#
# Bash suite: bats-core, files under tests/bash/*.bats
# TS  suite: bun test, files under tests/ts/*.test.ts
#
# Each suite is warn-skipped if its runner isn't installed (so a
# partial dev environment doesn't block contributors). Suite failures
# are real failures and propagate.
#
# Exit codes:
#   0  — all present suites passed
#   1  — at least one suite failed
#
# Usage:
#   bash test.sh               # both suites
#   bash test.sh --bash        # bash only
#   bash test.sh --ts          # TS only
#   bash test.sh --strict      # treat missing runners as failures (CI)

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- options ---------------------------------------------------------
RUN_BASH=1
RUN_TS=1
STRICT=0

for arg in "$@"; do
  case "$arg" in
    --bash)   RUN_TS=0 ;;
    --ts)     RUN_BASH=0 ;;
    --strict) STRICT=1 ;;
    -h|--help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "test.sh: unknown arg: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

# --- output helpers --------------------------------------------------
if [ -t 1 ]; then
  c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_rst=$'\033[0m'
else
  c_red=""; c_grn=""; c_yel=""; c_rst=""
fi

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '%s✓%s %s\n' "$c_grn" "$c_rst" "$1"; }
warn() { printf '%s!%s %s\n' "$c_yel" "$c_rst" "$1"; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_rst" "$1"; }

# --- runners ---------------------------------------------------------
fails=0

run_bash_suite() {
  step "bash suite (bats)"
  if ! command -v bats >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      err "bats not installed — failing under --strict"
      return 1
    fi
    warn "bats not installed — skipping bash suite (install: apt install bats)"
    return 0
  fi

  local count
  count=$(find "$REPO_ROOT/tests/bash" -maxdepth 1 -name '*.bats' 2>/dev/null | wc -l)
  if [ "$count" -eq 0 ]; then
    warn "no .bats files under tests/bash/ — skipping"
    return 0
  fi

  if bats "$REPO_ROOT/tests/bash/"; then
    ok "bash suite passed ($count file(s))"
    return 0
  else
    err "bash suite failed"
    return 1
  fi
}

run_ts_suite() {
  step "ts suite (bun test)"
  if ! command -v bun >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      err "bun not installed — failing under --strict"
      return 1
    fi
    warn "bun not installed — skipping ts suite (install: curl -fsSL https://bun.sh/install | bash)"
    return 0
  fi

  local count
  count=$(find "$REPO_ROOT/tests/ts" -maxdepth 1 -name '*.test.ts' 2>/dev/null | wc -l)
  if [ "$count" -eq 0 ]; then
    warn "no .test.ts files under tests/ts/ — skipping"
    return 0
  fi

  # bun test resolves imports relative to cwd; run from src/ where tsconfig lives
  if (cd "$REPO_ROOT/src" && bun test "$REPO_ROOT/tests/ts/"); then
    ok "ts suite passed ($count file(s))"
    return 0
  else
    err "ts suite failed"
    return 1
  fi
}

# --- run -------------------------------------------------------------
[ "$RUN_BASH" -eq 1 ] && { run_bash_suite || fails=$((fails + 1)); }
[ "$RUN_TS"   -eq 1 ] && { run_ts_suite   || fails=$((fails + 1)); }

step "summary"
if [ "$fails" -eq 0 ]; then
  ok "all run suites passed"
  exit 0
else
  err "$fails suite(s) failed"
  exit 1
fi
