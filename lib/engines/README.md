# lib/engines/ — engine adapters

Each file in this folder is **one engine adapter**. An engine is the
underlying CLI/runtime that actually talks to an LLM (today: Claude
Code). Claudify's entrypoints (`install.sh`, `update.sh`, etc.) call
into these adapters through a fixed 6-function contract — they never
reference `claude` or any specific binary directly.

See `docs/architecture.md §6` for the full rationale and ADR 0005 for
the criteria that gate adding a new adapter.

## The contract

Every `lib/engines/<engine-id>.sh` must define **6 functions**:

| Function | What it does |
|---|---|
| `engine_install` | Install / update the engine binary on the host |
| `engine_auth_check` | Returns 0 if currently authenticated |
| `engine_auth_setup` | Run interactive auth flow; persist credentials |
| `engine_run_args` | Echo the argv vector for systemd `ExecStart` |
| `engine_status` | Return JSON describing engine version + auth state |
| `engine_uninstall` | Remove engine state from `~/.claudify/instances/<name>/` (does NOT remove the engine binary itself) |

## Naming

- File: `lib/engines/<engine-id>.sh` (lowercase, kebab-case)
- Engine ID: matches the file stem (`claude-code`, `gemini-cli`, …)

## Rules

- Adapters are sourced by the orchestrator only. They define functions
  and constants — no top-level work, no I/O on source.
- Adapters do not source each other.
- All 6 functions must be defined even if one is a no-op (return 0).
- The header comment lists `Exposes:` with the 6 function names.

## Current adapters

_None yet._ The first adapter (`claude-code.sh`) lands in task 3.4.3.
