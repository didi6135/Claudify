# lib/engines/ — engine adapters

Each file in this folder is **one engine adapter**. An engine is the
underlying CLI/runtime that actually talks to an LLM (today: Claude
Code). Claudify's entrypoints (`install.sh`, `update.sh`, etc.) call
into these adapters through a fixed contract — they never reference
`claude` or any specific binary directly.

See `docs/architecture.md §6` for the full rationale and ADR 0005 for
the criteria that gate adding a new adapter.

## The contract

Every `lib/engines/<engine-id>.sh` must define **8 functions**:

| Function | Args | What it does |
|---|---|---|
| `engine_install` | — | Install / update the engine binary on the host. Idempotent — skip if already present. |
| `engine_seed_state` | `<workspace-dir>` | Pre-accept any first-run prompts (e.g. theme, workspace trust) so a systemd-spawned service doesn't sit forever waiting for user input. No-op for engines that don't have such prompts. |
| `engine_install_channel_plugin` | `<plugin-name>` | Install the named channel plugin (today: `telegram`). No-op for engines that don't have a plugin model. |
| `engine_auth_check` | — | Returns 0 if currently authenticated, non-zero otherwise. |
| `engine_auth_setup` | — | Run the interactive auth flow and persist credentials to `$CREDS_FILE`. Caller (lib/oauth.sh) handles the user-facing intro and post-verification. |
| `engine_run_args` | — | Echo the full `ExecStart=` line for the systemd unit. Each engine decides whether it needs `script(1)` wrapping (Claude Code does — its TUI requires a real PTY). |
| `engine_status` | — | Echo a JSON object: `{"engine": "...", "version": "...", "authenticated": true/false}`. |
| `engine_uninstall` | — | Remove engine-specific state from `~/.claudify/`. Does NOT remove the engine binary itself — that's host-wide and may be in use elsewhere. |

Adapters may define private helper functions (prefix with `_`); the
public API is exactly these 8.

## Naming

- File: `lib/engines/<engine-id>.sh` (lowercase, kebab-case)
- Engine ID: matches the file stem (`claude-code`, `gemini-cli`, …)
- Selected at runtime via `CLAUDIFY_ENGINE=<id>` env var (default
  `claude-code`); `lib/engine.sh` handles dispatch.

## Rules

- Adapters define functions and constants. **No top-level work, no
  I/O on source.**
- Adapters do not source each other or other lib modules.
- All 8 contract functions must be defined even if some are no-ops
  (`return 0`).
- The header comment lists `Exposes:` with the 8 function names plus
  any engine-specific public constants.
- Engine-specific env-var names (e.g. `CLAUDE_CODE_OAUTH_TOKEN`) stay
  internal to the adapter — never surfaced as generic
  `ENGINE_TOKEN`-style names. Each adapter manages its own token
  storage convention.

## Current adapters

| File | Engine | Notes |
|---|---|---|
| [`claude-code.sh`](claude-code.sh) | Claude Code | Today's only adapter. npm-installable; needs `script(1)` PTY wrap; channel plugins via `claude-plugins-official` marketplace. |

When we add a second engine: drop a new file here implementing the
8-function contract, and that's it — the rest of the codebase is
already engine-agnostic. ADR 0005 documents the trigger conditions
for actually adding one.
