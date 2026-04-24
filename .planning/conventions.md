# Project conventions

> Rules for how we write code and docs in Claudify. Keep this short.
> If a rule isn't here, default to clarity over cleverness.

---

## Bash files

### Header
Every executable bash file starts with:

```bash
#!/usr/bin/env bash
# <one-line purpose>
#
# Usage:
#   <invocation example>
#
# Dependencies:
#   - <external commands this file needs>
#
# See also:
#   - <related ADR or doc, if any>

set -euo pipefail
```

### Style
- `snake_case` for variables and functions
- `kebab-case` for script filenames (`install.sh`, `enable-linger.sh`)
- `UPPER_SNAKE` for env vars and constants
- Functions before main flow; main flow at the bottom
- No global side-effects above the main flow (define, don't run)
- Quote every variable expansion (`"$var"`, `"${arr[@]}"`)
- Prefer `[[ ... ]]` over `[ ... ]`
- `local` every variable inside a function

### Error handling
- `set -euo pipefail` is mandatory
- Use the `fail` helper from `lib/colors.sh` (or equivalent) — it prints red + exits non-zero
- Catch expected failures explicitly with `||` — never with bare `2>/dev/null` that hides real errors
- On error, tell the user *what to do next*, not just *what failed*

### Logging style
- `step "<title>"` — major section header
- `ok "<msg>"` — success line (green check)
- `warn "<msg>"` — non-fatal issue (yellow)
- `fail "<msg>"` — fatal, exits 1 (red)
- Plain `echo` for verbose detail under a step
- Never log secrets — even in dry-run mode, replace token-like values with `***`

### Comments
- Default to **no comments**
- One-line docstring above non-trivial functions: explain *why*, not *what*
- Don't reference the current task or fix in comments — that goes in commit messages

---

## Documentation

### Three audiences, three folders
- `README.md` (root) — the user installing Claudify for the first time
- `docs/` — the user troubleshooting or wanting to understand
- `.planning/` — us (the maintainers)

### Rules
- Every folder has a `README.md` explaining what belongs there
- Every script has a header comment
- Every architectural choice that's non-obvious gets an ADR
- User-facing docs use second person ("you") and active voice
- Internal docs can be terser

---

## ADRs (Architecture Decision Records)

Live in `.planning/decisions/`. Format: `NNNN-kebab-case-title.md` where
`NNNN` is the next available 4-digit number. See
[decisions/README.md](decisions/README.md) for the template.

A decision is ADR-worthy when:
- It's hard to reverse later
- It's surprising to a new reader
- It excludes a real alternative someone might propose
- It locks us into a constraint

Bug fixes, naming choices, and small refactors are **not** ADR-worthy.

---

## Adding a Phase task

1. Open `.planning/phases/phase-N-<name>.md`
2. Add a numbered task under the right sub-phase, following the existing
   format: bold title, problem, action, (discovered-on if applicable)
3. If the task is large or surprising, add an ADR for the approach
4. Update the phase's acceptance criteria if the task changes what
   "done" looks like

---

## Commit messages

Single-line subject (≤ 72 chars), imperative mood. Body explains *why*,
not *what* (the diff already shows what). For multi-change commits,
bullet the body.

```
short subject in imperative mood

- bullet for each meaningful change
- another bullet
- another bullet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Size limits

Files and functions have soft caps. When a file crosses, split it.

- **Bash files:** ≤ **300 lines**.
  - Current offender: `lib/steps.sh` (~430 lines). Due for split into
    `lib/steps/{seed,oauth,configs,service}.sh` after Phase 3 closes.
- **TypeScript files:** ≤ **300 lines**.
- **Functions (any language):** ≤ **50 lines**.
- **Line length:** soft 100 chars, hard 120.

Rationale: when you can't hold a file in your head, readers either
skim-read and miss bugs, or bail and ignore the file. 300 lines
keeps things scannable without forcing premature fragmentation.

## Shellcheck before push

Every bash file I touch goes through:

1. `bash -n <file>` — syntax parse
2. `shellcheck <file>` — lint for common bash mistakes

`shellcheck` is allowed to be missing locally (it's an apt package;
we don't hard-require it yet), but if it IS installed, I run it.
Disables need a reason comment:

```bash
# shellcheck disable=SC2034  # intentional: passed to jq via export
local _=ignored
```

Phase 5 (security + observability) will wire this into a pre-commit
hook or CI check.

## Dead-code deletion

When a feature is removed or a file becomes unused, the deletion
lands in the **same commit** as the change that obsoleted it. No
orphaned files, no commented-out blocks, no `.bak` suffixes, no
`legacy/` folders squatting at the repo root. Git history holds the
old code if we ever need it; the working tree stays clean.

## Things we explicitly don't do

- Comments that restate the code
- Wrapper functions for trivial commands
- Backwards-compatibility shims for code that hasn't shipped
- Speculative abstractions for hypothetical future cases
- Catch-all error handlers that hide real failures
- Premature optimization

---

## Modular bash + single-file distribution

`install.sh` is the user-facing entry point. It exists in two forms:

1. **Source form** (in this repo): a thin orchestrator that
   `source`s files under `lib/`. Easy to read, edit, and test in
   isolation.
2. **Distributed form** (`dist/install.sh`, gitignored): a single
   self-contained file produced by `bash build.sh`. This is what gets
   served to users via `curl … | bash`, because curl can only fetch one
   file.

Rules:
- Modules under `lib/` **define functions and constants only** —
  no top-level work, no I/O on source. The orchestrator decides when
  to invoke setup steps (e.g. `setup_logging` is a function, not a
  side-effect-on-source).
- Modules don't `source` each other; only the orchestrator (`install.sh`)
  sources lib files, in dependency order.
- Modules don't have their own shebang or `set -euo pipefail`. Those
  belong on the orchestrator.
- Every module has a header comment listing its purpose and what it
  exposes (`Exposes: foo, bar, baz`).
- Run `bash build.sh` whenever you change anything under `lib/` or
  `install.sh`. The output `dist/install.sh` must pass `bash -n`.
