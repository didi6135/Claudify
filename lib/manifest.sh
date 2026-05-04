# lib/manifest.sh — registry + per-instance manifest read/write helpers
#
# Two JSON files are the single source of truth for "what's installed":
#   ~/.claudify/instances.json   — top-level registry of all instances
#   ~/.claudify/<per-instance>   — per-instance manifest
#
# Today (pre-3.4.5) "per-instance" lives at the root of $CLAUDIFY_ROOT
# because there's only one instance. 3.4.5 will move it under
# `instances/<name>/claudify.json` as part of the multi-instance
# layout migration. Path resolution is centralised in
# `_instance_manifest_path` so 3.4.5 is a one-line update.
#
# All writes go through `manifest_atomic_write`: write `.tmp` then mv.
# mv is atomic on POSIX, so a Ctrl-C or power loss never leaves a
# half-written manifest. The worst case is "the .tmp lingers", which
# is harmless on the next run.
#
# Layout constant CLAUDIFY_ROOT comes from lib/layout.sh.
# Engine ID (CLAUDIFY_ENGINE) comes from lib/engine.sh.
# SCRIPT_VERSION comes from install.sh.
#
# Exposes:
#   manifest_init_registry           — create instances.json if missing
#   manifest_register_instance <n>   — add/update an instance's registry entry
#   manifest_unregister_instance <n> — remove an entry
#   manifest_list_instances          — echo each instance name on its own line
#   manifest_get_instance <n>        — print one registry entry as JSON
#   manifest_init_instance <n>       — create per-instance manifest if missing
#   manifest_set_channel <n> <ch> [v] — add/update a channel entry
#   manifest_set_mcp <n> <mcp> [v]   — add/update an MCP entry
#   manifest_read_field <n> <jq>     — read one field via jq -r
#   manifest_atomic_write <f> <body> — internal helper, exposed for tests

MANIFEST_VERSION=1

_registry_path() {
  printf '%s/instances.json' "$CLAUDIFY_ROOT"
}

_instance_manifest_path() {
  local name="${1:-default}"
  # TODO(3.4.5): once multi-instance layout lands, this becomes
  #   printf '%s/instances/%s/claudify.json' "$CLAUDIFY_ROOT" "$name"
  if [[ "$name" == "default" ]]; then
    printf '%s/claudify.json' "$CLAUDIFY_ROOT"
  else
    printf '%s/claudify-%s.json' "$CLAUDIFY_ROOT" "$name"
  fi
}

# Atomic file write. $1 = target path, $2 = new contents (a string).
# Creates parent dir if needed, writes to "${1}.tmp", then mv. Inherits
# permissions of the existing file if any.
manifest_atomic_write() {
  local target="$1" contents="$2"
  local tmp="${target}.tmp"
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$contents" > "$tmp"
  mv "$tmp" "$target"
}

manifest_init_registry() {
  local f
  f="$(_registry_path)"
  [[ -s "$f" ]] && return 0
  manifest_atomic_write "$f" "$(jq -n --argjson v "$MANIFEST_VERSION" '{
    version: $v,
    instances: {}
  }')"
}

manifest_register_instance() {
  local name="${1:-default}"
  local engine="${CLAUDIFY_ENGINE:-claude-code}"
  # Service name today is hardcoded; 3.4.5 introduces claudify-<name>.
  local service_unit="claude-telegram"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  manifest_init_registry
  local f
  f="$(_registry_path)"

  local merged
  merged="$(jq --arg name "$name" \
              --arg engine "$engine" \
              --arg service "$service_unit" \
              --arg pcmd "$name" \
              --arg now "$now" '
    .instances[$name] = ((.instances[$name] // {created_at: $now}) + {
      engine: $engine,
      service: $service,
      personal_cmd: $pcmd
    })' "$f")"

  manifest_atomic_write "$f" "$merged"
}

manifest_unregister_instance() {
  local name="${1:?manifest_unregister_instance: name required}"
  local f
  f="$(_registry_path)"
  [[ -s "$f" ]] || return 0
  local merged
  merged="$(jq --arg name "$name" 'del(.instances[$name])' "$f")"
  manifest_atomic_write "$f" "$merged"
}

manifest_list_instances() {
  local f
  f="$(_registry_path)"
  [[ -s "$f" ]] || return 0
  jq -r '.instances | keys[]' "$f"
}

manifest_get_instance() {
  local name="${1:?manifest_get_instance: name required}"
  local f
  f="$(_registry_path)"
  [[ -s "$f" ]] || { echo "null"; return 0; }
  jq --arg name "$name" '.instances[$name] // null' "$f"
}

manifest_init_instance() {
  local name="${1:-default}"
  local engine="${CLAUDIFY_ENGINE:-claude-code}"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local engine_version=""
  if command -v claude >/dev/null 2>&1; then
    engine_version="$(claude --version 2>/dev/null | head -1)"
  fi

  local f
  f="$(_instance_manifest_path "$name")"

  if [[ -s "$f" ]]; then
    # Refresh version fields on re-install; leave channels/mcps/skills/hooks alone.
    local merged
    merged="$(jq --arg cv "${SCRIPT_VERSION:-unknown}" \
                 --arg ev "$engine_version" '
      .claudify_version = $cv
      | .engine_version = $ev' "$f")"
    manifest_atomic_write "$f" "$merged"
    return 0
  fi

  local fresh
  fresh="$(jq -n --argjson v "$MANIFEST_VERSION" \
                 --arg name "$name" \
                 --arg now "$now" \
                 --arg cv "${SCRIPT_VERSION:-unknown}" \
                 --arg engine "$engine" \
                 --arg ev "$engine_version" '
    {
      version: $v,
      name: $name,
      created_at: $now,
      claudify_version: $cv,
      engine: $engine,
      engine_version: $ev,
      channels: {},
      mcps: {},
      skills: [],
      hooks: []
    }')"
  manifest_atomic_write "$f" "$fresh"
}

manifest_set_channel() {
  local name="${1:?manifest_set_channel: instance name required}"
  local channel="${2:?manifest_set_channel: channel name required}"
  local version="${3:-}"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local f
  f="$(_instance_manifest_path "$name")"
  [[ -s "$f" ]] || manifest_init_instance "$name"

  local merged
  merged="$(jq --arg ch "$channel" \
              --arg ver "$version" \
              --arg now "$now" '
    .channels[$ch] = ((.channels[$ch] // {installed_at: $now}) + {
      enabled: true,
      version: $ver
    })' "$f")"
  manifest_atomic_write "$f" "$merged"
}

manifest_set_mcp() {
  local name="${1:?manifest_set_mcp: instance name required}"
  local mcp="${2:?manifest_set_mcp: mcp name required}"
  local version="${3:-}"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local f
  f="$(_instance_manifest_path "$name")"
  [[ -s "$f" ]] || manifest_init_instance "$name"

  local merged
  merged="$(jq --arg m "$mcp" --arg ver "$version" --arg now "$now" '
    .mcps[$m] = ((.mcps[$m] // {installed_at: $now}) + {
      enabled: true,
      version: $ver
    })' "$f")"
  manifest_atomic_write "$f" "$merged"
}

manifest_read_field() {
  local name="${1:?manifest_read_field: instance name required}"
  local jq_path="${2:?manifest_read_field: jq path required}"
  local f
  f="$(_instance_manifest_path "$name")"
  [[ -s "$f" ]] || return 1
  jq -r "$jq_path" "$f"
}
