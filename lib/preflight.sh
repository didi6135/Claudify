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

# Offer to install a missing apt package; prompt confirmation, then sudo.
offer_apt_install() {
  local pkg="$1" desc="${2:-$1}"
  warn "$desc is missing"
  echo "    Will install via: sudo apt install -y $pkg"
  echo "    (You'll be prompted for your sudo password if not already cached.)"
  local yn
  ask "Install $pkg now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without $desc"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] sudo apt install -y $pkg"
    return 0
  fi
  sudo apt install -y "$pkg" >/dev/null || fail "Failed to install $pkg"
  ok "$pkg installed"
}

# Install Node.js v22 via NodeSource. We don't use distro packages because
# they're often too old for current Claude Code.
install_node() {
  warn "Node.js is not installed (required by Claude Code)"
  echo "    Will install Node.js v22 from NodeSource (official Node repo)."
  echo "    This runs:"
  echo "        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
  echo "        sudo apt install -y nodejs"
  echo "    You'll be prompted for your sudo password."
  local yn
  ask "Install Node.js v22 now? [Y/n]" "Y" yn
  [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without Node.js"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] add NodeSource repo + apt install -y nodejs"
    return 0
  fi

  echo "  ↓ Adding NodeSource repository…"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1 \
    || fail "NodeSource setup failed"
  echo "  ↓ Installing nodejs…"
  sudo apt install -y nodejs >/dev/null 2>&1 || fail "apt install nodejs failed"
  ok "Node.js $(node --version) installed"
}

preflight_prereqs() {
  # Things every Linux server should have — fail if missing (we won't fight
  # broken base systems).
  for cmd in script curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      fail "'$cmd' not found. Install util-linux + curl and re-run."
    fi
  done

  # Node.js — install via NodeSource if missing.
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    install_node
  fi
  ok "Node.js $(node --version), npm $(npm --version)"

  # jq — handy for idempotent JSON merges. Offer to install.
  if ! command -v jq >/dev/null 2>&1; then
    offer_apt_install "jq"
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
