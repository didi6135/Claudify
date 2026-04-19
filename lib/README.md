# lib/ — bash modules sourced by install.sh

Reusable bash helpers, each focused on one concern. Sourced by `install.sh`
(and later by `doctor.sh`, `update.sh`, etc.) via `source lib/<name>.sh`.

## Rules

- Each file = one focused concern (e.g. `colors.sh`, `prompts.sh`, `validate.sh`).
- Files in `lib/` define functions only; they do not run code on source.
- Every non-trivial function gets a one-line docstring above it
  explaining *why*, not *what*.
- Functions use `local` for every variable and quote every expansion.
- No business logic here — that lives in the top-level scripts (`install.sh`,
  etc.). `lib/` is for reusable helpers.

## Naming

`snake_case.sh` filenames. Function names are `snake_case` and prefixed
when ambiguous (e.g. `prompt_secret`, not just `secret`).

## Currently empty

Modules will be extracted from `install.sh` as it grows. Expected first
extractions when `install.sh` exceeds ~300 lines:
- `colors.sh` — `c_red`, `c_green`, `step`, `ok`, `warn`, `fail`
- `prompts.sh` — `ask`, `ask_secret`, `ask_validated`, TTY detection
- `validate.sh` — input format checks for tokens, IDs, paths
- `preflight.sh` — OS detection, prerequisite checks, linger detection
