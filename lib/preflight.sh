# lib/preflight.sh — checks run before any install action
#
# Each function fails (or warns) loudly with actionable instructions.
# Order matters: OS first, then prereq commands, then linger (which may
# need sudo and changes server state if the user agrees).
#
# Exposes:
#   preflight_os
#   preflight_prereqs
#   preflight_linger

preflight_os() {
  step "Preflight"
  [[ "$(uname -s)" == "Linux" ]] || fail "Not Linux. Claudify installs the bot on a Linux server."
  ok "Linux ($(uname -m))"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian) ok "${PRETTY_NAME:-$NAME $VERSION_ID} (supported)" ;;
      *)             warn "${PRETTY_NAME:-${ID:-unknown}} (not formally tested; may work)" ;;
    esac
  fi
}

preflight_prereqs() {
  local missing=()
  for cmd in node npm script curl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if (( ${#missing[@]} )); then
    c_red "  ✗ missing required commands: ${missing[*]}"
    echo
    echo "  Install them and re-run. On Ubuntu/Debian:"
    echo "      sudo apt update && sudo apt install -y nodejs npm util-linux curl"
    exit 1
  fi
  ok "node $(node --version), npm $(npm --version)"

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is missing — needed to safely merge access.json. Install with:"
    echo "      sudo apt install -y jq"
  else
    ok "jq present"
  fi
}

preflight_linger() {
  if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    ok "linger already enabled for $USER"
    return 0
  fi

  warn "linger is disabled for $USER"
  echo "    Without linger, the bot would die when you log out of SSH."
  echo "    Enabling it requires one-time sudo. You'll be prompted for"
  echo "    your password right here."
  echo

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] sudo loginctl enable-linger $USER"
    return 0
  fi

  local yn
  ask "Continue and enable linger now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without linger"

  sudo loginctl enable-linger "$USER" || fail "Failed to enable linger"
  ok "linger enabled"
}
