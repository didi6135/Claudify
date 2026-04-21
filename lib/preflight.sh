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
  if [[ "${NON_INTERACTIVE:-0}" -ne 1 ]]; then
    local yn
    ask "Install $pkg now? [Y/n]" "Y" yn
    [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without $desc"
  fi

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
  if [[ "${NON_INTERACTIVE:-0}" -ne 1 ]]; then
    local yn
    ask "Install Node.js v22 now? [Y/n]" "Y" yn
    [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without Node.js"
  fi

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

  # Bun — required by the telegram plugin's MCP server (see its .mcp.json:
  # command "bun" run start). Without it the plugin silently fails to spawn
  # and claude --channels runs but never polls Telegram.
  if ! command -v bun >/dev/null 2>&1; then
    install_bun
  fi
  # Ensure PATH has bun for the rest of this script run
  export PATH="$HOME/.bun/bin:$PATH"
  ok "bun $(bun --version 2>/dev/null || echo '?')"
}

# Install Bun via its official one-liner. User-level install under ~/.bun,
# no sudo needed. The telegram MCP server depends on this.
install_bun() {
  warn "Bun is not installed (required by the Telegram plugin's MCP server)"
  echo "    Will install Bun via its official one-liner:"
  echo "        curl -fsSL https://bun.sh/install | bash"
  echo "    Installs under ~/.bun (no sudo needed)."
  if [[ "${NON_INTERACTIVE:-0}" -ne 1 ]]; then
    local yn
    ask "Install Bun now? [Y/n]" "Y" yn
    [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without Bun (Telegram plugin requirement)"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [DRY] curl -fsSL https://bun.sh/install | bash"
    return 0
  fi

  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 \
    || fail "Bun install failed"
  export PATH="$HOME/.bun/bin:$PATH"
  command -v bun >/dev/null 2>&1 || fail "Bun installed but not on PATH — check ~/.bun/bin"
  ok "Bun $(bun --version) installed"
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

  if [[ "${NON_INTERACTIVE:-0}" -ne 1 ]]; then
    local yn
    ask "Continue and enable linger now? [Y/n]" "Y" yn
    [[ "$yn" =~ ^[Nn] ]] && fail "Cannot proceed without linger"
  else
    echo "  (non-interactive: running sudo loginctl enable-linger)"
  fi

  sudo loginctl enable-linger "$USER" || fail "Failed to enable linger"
  ok "linger enabled"
}
