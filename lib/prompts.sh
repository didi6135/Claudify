# lib/prompts.sh — interactive prompts that survive `curl | bash`
#
# The challenge: when `bash install.sh` is fed via `curl … | bash`, stdin is
# the script content, not the keyboard, so plain `read` can't reach the user.
# We re-route prompts through /dev/tty when piped.
#
# Exposes:
#   detect_tty                                          — sets TTY_DEV
#   ask          <prompt> <default> <varname>           — visible input
#   ask_secret   <prompt> <varname>                     — hidden input
#   ask_validated <prompt> <default> <var> <fn> <hint>  — loop until valid
#   ask_secret_validated <prompt> <var> <fn> <hint>     — same, hidden
#   ask_yn       <prompt> <default-y-or-n>              — returns 0 (yes) / 1 (no)
#   wait_enter   [<prompt>]                             — pause until ENTER

TTY_DEV=""

detect_tty() {
  if [[ -t 0 ]]; then
    TTY_DEV=/dev/stdin
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    TTY_DEV=/dev/tty
  fi
}

ask() {
  local prompt="$1" default="${2:-}" varname="$3"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: $current (from env)"
    return
  fi
  [[ -z "$TTY_DEV" ]] && fail "No TTY; set $varname via env var when running non-interactively"
  local input
  if [[ -n "$default" ]]; then
    read -r -p "  $prompt [$default]: " input < "$TTY_DEV"
    input="${input:-$default}"
  else
    read -r -p "  $prompt: " input < "$TTY_DEV"
  fi
  printf -v "$varname" '%s' "$input"
}

ask_secret() {
  local prompt="$1" varname="$2"
  local current="${!varname:-}"
  if [[ -n "$current" ]]; then
    echo "  $prompt: (from env)"
    return
  fi
  [[ -z "$TTY_DEV" ]] && fail "No TTY; set $varname via env var when running non-interactively"
  local input
  read -r -s -p "  $prompt: " input < "$TTY_DEV"
  echo
  printf -v "$varname" '%s' "$input"
}

ask_validated() {
  local prompt="$1" default="$2" varname="$3" validator="$4" hint="$5"
  while true; do
    ask "$prompt" "$default" "$varname"
    if "$validator" "${!varname}"; then return 0; fi
    warn "$hint"
    unset "$varname"
  done
}

ask_secret_validated() {
  local prompt="$1" varname="$2" validator="$3" hint="$4"
  while true; do
    ask_secret "$prompt" "$varname"
    if "$validator" "${!varname}"; then return 0; fi
    warn "$hint"
    unset "$varname"
  done
}

# Yes/no prompt. Returns 0 for yes, 1 for no.
#   default = "y" → empty input means yes
#   default = "n" → empty input means no
#
# When there's no TTY (curl | bash through a non-interactive pipe),
# falls back to whatever the default would be without asking.
ask_yn() {
  local prompt="$1" default="${2:-y}"
  local hint="[Y/n]"
  [[ "$default" =~ ^[Nn]$ ]] && hint="[y/N]"

  if [[ -z "$TTY_DEV" ]]; then
    [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
  fi

  local input
  read -r -p "  $prompt $hint " input < "$TTY_DEV"
  input="${input:-$default}"
  [[ "$input" =~ ^[Yy] ]]
}

# Pause the flow until the user hits ENTER. Any typed input is discarded.
# This is a pacing pause, not a prompt for a value — so it does NOT go
# through ask()'s env-var-prefill logic. Using ask() here caused bugs
# when the throwaway var name collided with bash's special $_ variable.
wait_enter() {
  local prompt="${1:-Press ENTER to continue}"
  [[ -z "$TTY_DEV" ]] && return 0
  local _input
  read -r -p "  $prompt: " _input < "$TTY_DEV" || true
}
