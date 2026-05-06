# How I (Claude) work on Claudify

This file is read at the start of every Claude Code session in this
repo. It's the contract between the owner and me. When we disagree
during a session, these rules win — but the owner can amend this file
any time and I re-read it next session.

**Not to be confused with:**
- `~/.claude/CLAUDE.md` — user-wide Claude Code preferences (if any)
- `~/.claudify/workspace/CLAUDE.md` — the bot's persona on the server

This file is the **Claudify-repo contract**, not either of those.

---

## Process — how we collaborate

- **Propose before doing anything destructive.** `rm -rf`, `git push --force`, `git reset --hard`, anything that touches Station11 or other live systems, anything that changes many files at once. Propose, wait for explicit "go".
- **One task at a time.** Don't parallelize unless the owner asks. Each task gets a round-trip test on Station11 before the next starts.
- **Keep messages short.** Owner reads on phone / in the IDE. 5 lines > 30.
- **Match the owner's language.** Hebrew when they write Hebrew; English for technical content. Don't switch unilaterally.
- **Finish what I start before moving on.** No "95% done, moving to next" — either it's done (✅ DONE + date in the phase doc) or I fix it now.

## Architecture — non-negotiable invariants

These come before the code-quality rules. Breaking one of these
requires opening an ADR + getting explicit owner approval, not just a
PR review.

1. **Engine-agnostic core.** The codebase must support swapping in a
   different LLM CLI (Gemini, Codex, local Llama, future engines)
   without touching anything outside `lib/engines/<id>.sh`. No
   references to `claude` (the binary), `~/.claude/`, `CLAUDE.md`-as-
   a-system-prompt-file, Claude-specific tool names like
   `memory_20250818`, or any other Claude-coupled assumption may
   appear in `install.sh`, `lib/*.sh` (except inside `lib/engines/`),
   `src/`, or `tests/`. If a new feature has an engine-specific
   surface, it lives behind a function in the engine contract; the
   adapter implements per-engine, the rest of the codebase calls the
   abstract function. **The substrate (paths, file formats, SQL
   schemas) is universal; the model-facing surface is per-adapter.**
2. **Clean uninstall.** `uninstall.sh` must leave the system as if
   Claudify never ran (modulo what's deliberately preserved per
   3.1's spec). No daemons that survive uninstall; no env-var
   pollution; no orphaned PATH entries; no files under `/etc` or
   `/var`. Every file Claudify writes lives under `~/.claudify/`.
3. **Substrate independence.** Memory, persona, and conversation
   data live in plain files + SQLite at known paths under
   `~/.claudify/`. The operator must always be able to inspect /
   edit / back up the data with standard tools (`cat`, `sqlite3`,
   `vi`) — even if every Claudify process is dead. Any wrapper
   layer (MCP, future skills) is glue, not a gate.
4. **Single-user trust model.** Claudify is a personal assistant
   for one operator. We don't build malicious-skill defences, we
   don't run sandboxed per-skill processes, we don't build
   permission systems. Skills the operator installs are trusted —
   isolation is for accident prevention, not adversaries.

## Code quality — 11 rules

1. **Line limits.** Bash: ≤300 lines per file. Functions: ≤50 lines. TypeScript: ≤300/file, 50/function. When a file crosses, split it.
2. **New feature ⇒ full docs in the same commit.** User-facing → README; structural → phase doc; architectural → new ADR; always → one line in `CHANGELOG.md`.
3. **Bug fixes logged in `CHANGELOG.md`.** Keep a Changelog format (`### Fixed` section under `## [Unreleased]`).
4. **Consistent style** per `.planning/conventions.md`. Before pushing: `bash -n` every touched shell file, `shellcheck` if available.
5. **Delete dead code in the same commit.** No `.bak`, no commented-out blocks, no stale `legacy/` folders. If it's unused, it's gone.
6. **Security-by-default walkthrough per change.** Every new code I write, I mentally check:
   - Inputs validated (regex/length/type)?
   - Secrets absent from logs, env listings, `ps` output?
   - File permissions right (600 on secrets, 644 on configs)?
   - Any `eval`/`source` on untrusted input? (never)
   - Shell quoting: every expansion quoted?
   - Least privilege in the systemd unit?
7. **Tests per feature.** Bash = smoke test + round-trip on Station11, captured as a checklist in the phase doc. TypeScript = Bun's built-in test runner, real units. No test = no ship.
8. **Idempotency required.** Every script I ship is safe to re-run. Install, update, doctor, backup, restore, uninstall — running twice is a no-op or produces the same end state.
9. **No silent failures.** Every `|| true` needs a comment explaining why the failure is OK. Otherwise: `fail "specific reason — try X next"` with a concrete hint.
10. **Environment hygiene on uninstall.** Anything the installer adds to `~/.bashrc`, `~/.zshrc`, PATH, env vars, etc. — uninstall removes it. No orphaned state.
11. **Versioning discipline.** `SCRIPT_VERSION` in `install.sh` bumps for every meaningful user-visible change, and lands in `CHANGELOG.md` on the same commit.

## Security rules

- **Scrub every command output** that might contain secrets. Pipe tokens through `sed` to redact `sk-ant-oat01-…` and bot tokens before showing the owner or pasting into chat history.
- **Flag leaked secrets loudly.** If the owner pastes a token into chat, immediately tell them to revoke.
- **Never commit** anything under `.planning/LOCAL*` (gitignored; may hold real tokens).
- **Auto-allow tool scope** stays narrow: only the 4 telegram plugin tools (`reply`, `react`, `edit_message`, `download_attachment`). Don't widen without a new ADR.
- **No `bash <(curl …)`** without first explaining what the script does.

## Before-I-ship checklist

Before I say "pushed":

- [ ] `bash -n` passes on every touched shell file
- [ ] `shellcheck` run; only `# shellcheck disable=…` with a *reason* comment
- [ ] If `lib/` or `install.sh` changed → `bash build.sh` ran, `dist/install.sh` is current
- [ ] Phase doc / README / `CHANGELOG.md` updated in the **same commit** as the code
- [ ] Round-trip test on Station11 (where applicable) — captured in chat
- [ ] `doctor.sh` still reports 28/28 green (for changes touching install path)

## Things I never do without asking

- Rename files, restructure folders
- Add a runtime dependency (apt package, npm module, bun package, external tool)
- Create a new top-level file (skill, hook, workflow, CI job)
- Modify `.git/` contents directly
- Force-push anything
- Change `main` from a PR-style merge pattern to direct commits (if we adopt one)
- Commit `.planning/LOCAL*` or anything containing secrets
- Install Claude plugins beyond `telegram@claude-plugins-official`
- Touch state outside the repo + Station11 (e.g. the operator's laptop `~/.claude/`)

---

*Owner amends this file freely. I re-read it at the start of every
session and adjust my behavior accordingly.*
