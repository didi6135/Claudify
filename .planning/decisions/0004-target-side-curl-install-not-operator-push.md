# ADR 0004: Target-side curl install, not operator-side SSH push

**Status:** Accepted
**Date:** 2026-04-19

## Context

There are two common shapes for installing a self-hosted tool on a
remote server:

1. **Operator-side push** — the user runs a CLI on their laptop that
   SSHes to the target server and configures it from outside.
   (Examples: Ansible, Capistrano, custom shell scripts that wrap `ssh`.)
2. **Target-side install** — the user SSHes to their server first, then
   runs an install script locally. (Examples: Bun, Tailscale, k3s,
   OpenCode, Deno.)

Our original design (`deploy.sh`, removed before shipping — see commit
history if you want to read it) was operator-side push. We pivoted because
the user wanted the familiar Bun / OpenCode UX.

## Decision

Claudify is **target-side install only**. The user SSHes to their server,
then runs:

```bash
curl -fsSL https://claudify.sh/install | bash
```

There is no operator-side CLI. There is no SSH-from-laptop wrapper. The
install script runs locally on the target and only on the target.

## Consequences

- **Good:**
  - Familiar UX — every developer recognizes `curl ... | bash`
  - Drastically simpler script: no SSH heredoc, no remote PTY tricks for
    sudo, no key management, no host-key pinning
  - One operating system to support (Linux on the server) instead of
    three (Linux + macOS + Windows on the operator's laptop)
  - The script is auditable line-by-line before the user pipes it
  - No operator-side state to leak, lose, or sync

- **Bad:**
  - No native "manage many servers from one laptop" mode. Power users
    who want that can wrap our install with their own SSH:
    `ssh user@host 'curl -fsSL https://claudify.sh/install | bash'`.
    Acceptable.
  - The install script must handle the curl-pipe-bash stdin quirk:
    when piped, `read` doesn't work because stdin is the script itself.
    We read prompts from `/dev/tty` instead.

- **Ugly:**
  - We will hear from someone who wants the operator-CLI mode. We say no
    by default and revisit only if it becomes a frequent ask.

## Alternatives considered

- **SSH-from-laptop wrapper** — Rejected. Higher complexity, more state
  to manage, OS-portability tax for a feature most users won't use.
- **npm-installable CLI** — Rejected. Heavier than a curl one-liner;
  forces npm on the operator. Also adds a Node dependency on the
  operator side, which we don't otherwise need.
- **Docker image + `docker run` one-liner** — Rejected for the same
  reasons as ADR 0002 (Docker as service supervisor): heavyweight,
  introduces another layer between user and bot.
- **Both modes** — Rejected. Doubles the surface area and the doc
  burden. If we ship both, neither stays polished.
