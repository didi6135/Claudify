#!/usr/bin/env bats
#
# manifest.bats — covers the lib/manifest.sh helpers in isolation.
# Each test runs in a fresh temp HOME so it doesn't touch the dev
# machine's real ~/.claudify.

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export CLAUDIFY_ROOT="$TEST_HOME/.claudify"
  export CLAUDIFY_ENGINE="claude-code"
  export SCRIPT_VERSION="0.1.0-test"
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  # Source manifest.sh in a sub-shell-friendly way: we need jq + the
  # functions, nothing else. manifest.sh references CLAUDIFY_ROOT via
  # the env var (set above), so layout.sh isn't strictly needed.
  # shellcheck disable=SC1090
  . "$REPO_ROOT/lib/manifest.sh"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ─── manifest_init_registry ───────────────────────────────────────────────
@test "manifest_init_registry creates instances.json with version=1 + empty instances" {
  manifest_init_registry
  [[ -s "$CLAUDIFY_ROOT/instances.json" ]]
  run jq -r '.version' "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "1" ]]
  run jq -r '.instances | length' "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "0" ]]
}

@test "manifest_init_registry is idempotent (existing file untouched)" {
  manifest_init_registry
  # Mark the file so we can detect a clobber
  jq '.instances.preserved = {marker: true}' "$CLAUDIFY_ROOT/instances.json" \
     > "$CLAUDIFY_ROOT/instances.json.t" \
    && mv "$CLAUDIFY_ROOT/instances.json.t" "$CLAUDIFY_ROOT/instances.json"

  manifest_init_registry  # second call must NOT clobber
  run jq -r '.instances.preserved.marker' "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "true" ]]
}

# ─── manifest_register_instance ───────────────────────────────────────────
@test "manifest_register_instance default adds an entry with engine + service + personal_cmd" {
  manifest_register_instance default
  run jq -r '.instances.default.engine'         "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "claude-code" ]]
  run jq -r '.instances.default.service'        "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "claude-telegram" ]]
  run jq -r '.instances.default.personal_cmd'   "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "default" ]]
  # created_at must be a non-empty ISO-8601-ish string
  run jq -r '.instances.default.created_at'     "$CLAUDIFY_ROOT/instances.json"
  [[ -n "$output" && "$output" != "null" ]]
}

@test "manifest_register_instance preserves created_at on re-register" {
  manifest_register_instance default
  first_created="$(jq -r '.instances.default.created_at' "$CLAUDIFY_ROOT/instances.json")"
  sleep 1
  manifest_register_instance default
  second_created="$(jq -r '.instances.default.created_at' "$CLAUDIFY_ROOT/instances.json")"
  [[ "$first_created" == "$second_created" ]]
}

@test "manifest_unregister_instance removes the entry" {
  manifest_register_instance default
  manifest_register_instance other
  manifest_unregister_instance default
  run jq -r '.instances | keys | join(",")' "$CLAUDIFY_ROOT/instances.json"
  [[ "$output" == "other" ]]
}

@test "manifest_list_instances echoes one name per line" {
  manifest_register_instance alpha
  manifest_register_instance beta
  result="$(manifest_list_instances | sort | tr '\n' ' ')"
  [[ "$result" == "alpha beta " ]]
}

# ─── per-instance manifest ────────────────────────────────────────────────
@test "manifest_init_instance creates claudify.json with required shape" {
  manifest_init_instance default
  local f="$CLAUDIFY_ROOT/claudify.json"
  [[ -s "$f" ]]
  run jq -r '.version'           "$f"; [[ "$output" == "1" ]]
  run jq -r '.name'              "$f"; [[ "$output" == "default" ]]
  run jq -r '.engine'            "$f"; [[ "$output" == "claude-code" ]]
  run jq -r '.claudify_version'  "$f"; [[ "$output" == "0.1.0-test" ]]
  run jq -r '.channels | length' "$f"; [[ "$output" == "0" ]]
  run jq -r '.mcps | length'     "$f"; [[ "$output" == "0" ]]
}

@test "manifest_set_channel telegram adds an enabled entry" {
  manifest_init_instance default
  manifest_set_channel default telegram "0.0.6"
  local f="$CLAUDIFY_ROOT/claudify.json"
  run jq -r '.channels.telegram.enabled' "$f"; [[ "$output" == "true" ]]
  run jq -r '.channels.telegram.version' "$f"; [[ "$output" == "0.0.6" ]]
  run jq -r '.channels.telegram.installed_at' "$f"
  [[ -n "$output" && "$output" != "null" ]]
}

@test "manifest_set_channel auto-creates per-instance manifest if missing" {
  manifest_set_channel default telegram ""
  local f="$CLAUDIFY_ROOT/claudify.json"
  [[ -s "$f" ]]
  run jq -r '.channels.telegram.enabled' "$f"
  [[ "$output" == "true" ]]
}

# ─── atomic write ─────────────────────────────────────────────────────────
@test "manifest_atomic_write leaves no .tmp on success" {
  manifest_init_registry
  manifest_register_instance default
  ! [[ -e "$CLAUDIFY_ROOT/instances.json.tmp" ]]
}

@test "manifest_atomic_write produces a valid JSON file" {
  manifest_atomic_write "$CLAUDIFY_ROOT/x.json" '{"a": 1}'
  run jq -r '.a' "$CLAUDIFY_ROOT/x.json"
  [[ "$output" == "1" ]]
}
