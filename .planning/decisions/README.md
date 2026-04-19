# Architecture Decision Records (ADRs)

Short docs that capture the *why* behind a non-obvious architectural choice.
Each is 1–2 pages, immutable once accepted. If a decision is later reversed,
write a new ADR that supersedes the old one — don't edit the original.

## When to write an ADR

Write one when the choice:
- Is hard to reverse later (changing it later costs work)
- Is surprising to a new reader (they'd ask "why this and not X?")
- Excludes a real alternative someone might propose
- Locks the project into a constraint

Don't write one for naming, small refactors, bug fixes, or formatting.

## Naming

`NNNN-kebab-case-title.md` where `NNNN` is the next free 4-digit number.

Examples:
- `0001-bash-as-implementation-language.md`
- `0007-switch-from-systemd-to-docker.md`

## Template

```markdown
# ADR NNNN: <Decision title>

**Status:** Proposed | Accepted | Superseded by ADR-NNNN
**Date:** YYYY-MM-DD

## Context
What is the problem we are facing? What forces are at play? Keep it short —
two or three short paragraphs.

## Decision
What did we decide to do? State it as a clear, single choice.

## Consequences
- **Good:** what this gets us
- **Bad:** what this costs us
- **Ugly:** what we're explicitly accepting as a tradeoff

## Alternatives considered
- **<Alternative 1>** — one sentence on why we rejected it
- **<Alternative 2>** — one sentence on why we rejected it
```

## Lifecycle

- **Proposed** — written, under discussion, not yet implemented
- **Accepted** — agreed and in effect
- **Superseded by ADR-NNNN** — replaced by a newer decision; old ADR
  stays in place for history
