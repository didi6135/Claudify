# ADR 0003: Authenticate Claude via OAuth (subscription), not API key

**Status:** Accepted
**Date:** 2026-04-19

## Context

Claude Code supports two authentication paths:
1. **OAuth via `claude setup-token`** — uses the user's Claude Pro/Max
   subscription. Requires a one-time interactive browser login on first
   use. Pricing is the user's flat subscription fee.
2. **`ANTHROPIC_API_KEY` env var** — uses the Anthropic API directly.
   No interactive step. Pricing is per-token, billed against an API key.

Either would technically work for Claudify. We must pick one as the
default — and likely the only — auth path.

The product's tagline is: *"A personal assistant powered by your own
Claude Code subscription."* The user explicitly stated they only use the
subscription model.

## Decision

Use **OAuth via `claude setup-token`** as the only auth path. Do not
build any API-key flow.

The installer pauses once during first setup with clear instructions for
the operator to run `claude setup-token` and complete the browser login.
On all subsequent installer runs, the existing OAuth session is
detected and the pause is skipped.

## Consequences

- **Good:**
  - Matches the product framing: the user owns their Claude subscription,
    Claudify is just a wrapper
  - No risk of an exposed API key burning through a budget
  - Flat-cost mental model — the user's subscription bill is the
    only Claude charge
  - One fewer secret to manage, rotate, and protect

- **Bad:**
  - First install requires a browser interaction. Cannot be fully
    headless on first run. ~1–2 minutes of unavoidable user time.
  - CI testing of the full install flow can't easily simulate the OAuth
    step. We work around this by testing everything *except* the auth
    pause in CI, and relying on a real human run for the full path.

- **Ugly:**
  - If Claude Code changes the OAuth flow shape, our installer's
    "pause and resume" logic might break. Mitigated by parsing the
    real `claude auth status` output (Phase 1 task 1.B.10) and failing
    loudly if the format changes.

## Alternatives considered

- **`ANTHROPIC_API_KEY` only** — Rejected. Conflicts with the product
  vision. Forces users to manage API billing separately from their
  subscription.
- **Both, user picks** — Rejected. Doubles the surface area, doubles
  the doc burden, and the choice is rarely meaningful — most users
  already have one or the other. We can revisit if a clear use case
  emerges.
