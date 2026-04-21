# ADR 0005: Keep upstream Telegram plugin; extend Claudify in the Intelligence layer (bash bootstrap, TS beyond)

**Status:** Accepted
**Date:** 2026-04-21

## Context

Two related questions surfaced late in Phase 1 that deserved a single
recorded decision rather than being solved ad-hoc for each follow-up:

1. **Do we fork the Telegram channel plugin?** The operator wanted a
   3-button permission UI ("Deny / Allow once / Allow forever"). The
   upstream plugin only ships "Allow / Deny". Forking would give us
   control, at the cost of diverging from actively-maintained upstream.

2. **Do we rewrite install.sh in TypeScript?** Complex state management
   (OAuth persistence, onboarding seeding, permission merges) has been
   painful in bash. TypeScript would be more readable and testable.

The underlying question is the same: **where does Claudify add value,
and where do we defer to others?**

## Decision

Claudify has two layers. We own the second; we defer on the first.

### Transport layer — use upstream, don't fork

- The Telegram plugin is a pipe: it moves messages between Telegram and
  Claude Code over MCP. We use `plugin:telegram@claude-plugins-official`
  and accept its UI constraints.
- UX gripes (3-button UI, multi-bot, webhook support, etc.) are filed
  upstream via [.planning/upstream-wishlist.md](../upstream-wishlist.md).
- We revisit forking only when 5+ concrete items accumulate in the
  wishlist that upstream won't accept. At that point we have a clear
  business case for the fork tax.

### Intelligence layer — build in Claude Code's native extension points

This is where nearly everything the operator thinks of as "long-term
features" actually lives:

| Feature | Native Claude Code point |
|---|---|
| Persona / preferences / memory | `~/.claude/CLAUDE.md`, auto-memory |
| Custom commands (`/allow`, `/backup`…) | Claude Code skills |
| Audit log of every tool call | Claude Code hooks |
| Cost tracking | Claude Code's own accounting + hooks |
| Per-tool/per-pattern approvals | `settings.json` permissions.allow |
| Multi-channel orchestration | `--channels` with multiple plugin args |

### Language — bash for the bootstrap, TypeScript for the rest

- **`install.sh` stays in bash.** It runs via `curl ... | bash` on a
  fresh server where TypeScript/Bun may not yet exist. See ADR 0001.
- **Everything that runs after install** (`doctor.sh`, `update.sh`,
  `backup.sh`, `uninstall.sh`, future custom skills) can assume `bun`
  is already installed (the plugin requires it). Those scripts should
  be written in **TypeScript run via Bun** when they exceed ~200 lines
  of bash or when they develop real state-management needs.
- `doctor.sh` is currently ~250 lines of bash — acceptable for now.
  The next lifecycle script (`update.sh` in Phase 3) is the first
  candidate for TypeScript.

## Consequences

- **Good:**
  - No fork tax on the transport layer. Upstream improvements flow to us.
  - Most "Claudify features" become skills + hooks + `CLAUDE.md` content,
    not new code — fast to add, easy to customize per operator.
  - Clear language split: anyone reading `install.sh` sees bash; anyone
    reading future tooling sees TypeScript. No "is this file TS or bash?"
    confusion.

- **Bad:**
  - We're gated on upstream for UX wins we might want fast (like the
    3-button approval UI). Mitigation: file a clear feature request,
    and in the meantime use `--permission-mode bypassPermissions` or
    patterned allow-lists as workarounds.
  - TypeScript-via-Bun is another runtime to install. Already required
    for the plugin, so no marginal cost — but it ties us to the plugin
    even more tightly. Acceptable given ADR 0002's systemd+linger choice.

- **Ugly:**
  - If upstream goes unmaintained, we inherit a fork anyway. We accept
    this risk because the plugin is small enough (~40KB server.ts) that
    a reluctant fork is tractable.

## Alternatives considered

- **Fork the Telegram plugin now.** Rejected. We haven't accumulated
  enough concrete gripes to justify the maintenance tax. One "I wish
  the UI had three buttons" isn't enough.
- **Rewrite install.sh in TypeScript.** Rejected. Breaks the "read
  the script before piping to bash" property that makes curl-pipe-bash
  trustworthy. Node/Bun isn't on a fresh server.
- **Pure bash for everything.** Rejected for anything beyond the
  bootstrap. We've already felt the pain (OAuth parsing, JSON merges,
  ANSI log filtering). TypeScript is the right tool as the logic grows.
- **Build Claudify-owned channel(s) from scratch.** Rejected. Same
  reasoning as "don't fork now": no concrete proof that we'd do it
  meaningfully better than the maintained upstream.
