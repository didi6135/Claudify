# ADR 0001: Bash as the implementation language

**Status:** Accepted
**Date:** 2026-04-19

## Context

Claudify needs an installer that runs on a target Linux server and
configures it to host a Claude+Telegram assistant. The installer touches
the filesystem, package manager, systemd, and prompts the user
interactively. We must pick a language for this tool before writing it.

The tool runs in `curl ... | bash` mode, which means the language must
be either present by default on every Linux server, or installable
trivially before our script runs. There is no opportunity for an "install
the runtime first" step — that would defeat the one-command UX.

## Decision

Use **bash** as the implementation language for `install.sh`, `doctor.sh`,
and any future top-level scripts.

## Consequences

- **Good:**
  - Available on every Linux server out of the box; no chicken-and-egg
  - Transparent — users can read the script before piping it to bash
  - The standard for self-hosted-tool installers (Bun, Tailscale, k3s,
    OpenCode all use bash). Familiar UX.
  - No build step, no compile step, no packaging
  - Easy to source from `lib/` modules as the project grows

- **Bad:**
  - No type safety; classes of bugs we wouldn't have in a typed language
  - Hard to unit-test; we'll lean on integration tests against a real server
  - Verbose for complex data manipulation; we offload JSON to `jq`
  - Quoting is famously error-prone; we mitigate with `set -euo pipefail`,
    shellcheck in CI, and code review

- **Ugly:**
  - As Claudify grows, bash will hurt. We accept this and will revisit
    in Phase 5 if the install logic exceeds ~1500 lines or develops real
    state-management needs (write a new ADR if so).

## Alternatives considered

- **Node.js / TypeScript** — Rejected. Requires installing Node before the
  installer can run. We *do* require Node on the server (Claude Code itself
  needs it), but bootstrapping the installer in Node creates a worse UX
  (`npm install -g claudify` is heavier than a curl one-liner).
- **Python** — Rejected. Not always present (especially on minimal Ubuntu
  Server images), and the Python 2/3 split still bites occasionally.
- **Go** — Rejected. Would require a build pipeline and per-arch binaries.
  Loses the "read the script before running it" property that makes
  curl-pipe-bash trustworthy.
- **Pure POSIX `sh`** — Rejected. We'd lose `[[ ]]`, arrays, and `read -p`
  with little gain; every modern Linux ships bash.
