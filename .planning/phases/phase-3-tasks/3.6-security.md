# Task 3.6 — Security hardening pass (umbrella)

**Status:** ⏳ pending
**Estimated effort:** ~2.75 hr (across 6 sub-tasks)
**Depends on:** 3.5 (everything in scope must already be implemented)
**Blocks:** Phase 3 closure
**Research:** [`.planning/research/security.md`](../../research/security.md) — threat model, audit, decisions

## Goal

Two arms, ship in parallel:

- **Arm A — systemd hardening** (sub-tasks 3.6.1–3.6.6 below). Take
  the unit from a `systemd-analyze` exposure score of ~9.6
  ("UNSAFE") to ≤3.0 ("MOSTLY OK"). Closes the biggest mechanical
  gap.
- **Arm B — broad code-level audit** (the 9-section checklist at the
  bottom of this file, run alongside the sub-tasks). Verifies that
  every claim in `docs/architecture.md §11` is actually true in
  code. Catches things that aren't directly systemd: supply chain,
  network HTTPS-only, multi-instance isolation, etc.

After Phase 3 closes, no one is going to come back to do this — so
it has to land now, before skills (Phase 4) ship and start running
under whatever shape the unit ends up with.

## Why

`CLAUDE.md` rule 6: *"Security-by-default per change."* Each prior
task should have respected this, but no one has done a comprehensive
sweep across the whole codebase. This task is that sweep. Plus,
prompt injection through Telegram means `bypassPermissions` has real
blast radius — systemd hardening is what bounds it.

See [`.planning/research/security.md`](../../research/security.md) for the
full audit, threat model, and reasoning behind every directive.

## Sub-tasks (Arm A — systemd hardening)

| # | Task | Effort | Tier |
|---|---|---|---|
| 1 | [3.6.1 — Tier-1 hardening (always-safe)](3.6.1-tier1-hardening.md) | 30 min | Critical |
| 2 | [3.6.2 — Filesystem write-restriction](3.6.2-fs-write-restriction.md) | 45 min | Critical |
| 3 | [3.6.3 — Address families + syscall filter](3.6.3-syscall-and-network.md) | 30 min | Critical |
| 4 | [3.6.4 — Tighten file permissions](3.6.4-file-permissions.md) | 15 min | Important |
| 5 | [3.6.5 — doctor.sh security section](3.6.5-doctor-security-section.md) | 30 min | Important |
| 6 | [3.6.6 — Security documentation](3.6.6-security-docs.md) | 15 min | Documentation |

Each sub-task is a separate commit + Station11 round-trip. Tier
order is the suggested ship order — Tier-1 first (zero risk), then
Tier-2 (filesystem), then Tier-3 (syscall filter, needs more
testing). Permissions + doctor + docs can land alongside.

## Arm B — broader audit checklist

These items are run alongside the sub-tasks. Many will already be
covered by the sub-task work; the checklist exists so nothing slips.

### 1. Secrets at rest

- [ ] Every file under `~/.claudify/instances/<name>/` containing a secret is chmod 600
- [ ] `~/.claudify/instances/<name>/credentials.env` 600
- [ ] `~/.claudify/instances/<name>/channels/*/.env` 600
- [ ] `~/.claudify/instances/<name>/mcps/*/oauth.json` 600 (when MCPs land in Phase 4)
- [ ] `access.json` 600 (covered by 3.6.4)
- [ ] systemd unit file 644 (NOT secret — references EnvironmentFile)
- [ ] `~/.local/bin/<name>` wrapper 755 (executable, no secrets inside)
- [ ] `/tmp/claudify-install-*.log` 600 (covered by 3.6.4)

### 2. Secrets in transit / process surface

- [ ] No `Environment=` line with a secret in any systemd unit (must use `EnvironmentFile=`)
- [ ] No `claude` / `bun` / npm / curl call where a secret is passed as a positional argument
- [ ] No `echo` / `printf` of a secret to stdout/stderr without redaction
- [ ] sed-redact pattern applied to install/update/doctor log files before user-facing display
- [ ] `claudify-install-*.log` files don't contain raw secrets

### 3. Input validation

- [ ] `BOT_TOKEN` regex enforced at every entry point (env + prompt)
- [ ] `TG_USER_ID` regex enforced
- [ ] Instance name regex + blocklist enforced
- [ ] No `eval` on operator input anywhere — `grep -rn 'eval' lib/ src/ install.sh update.sh uninstall.sh doctor.sh backup.sh restore.sh build.sh test.sh`
- [ ] Every `$var` expansion in bash is double-quoted

### 4. Path traversal / symlink attacks

- [ ] All paths are absolute (`$HOME` / `$CLAUDIFY_ROOT`-anchored)
- [ ] `mv`, `rm -rf`, `tar -x` operate only inside `~/.claudify/`, `~/.config/systemd/user/`, or explicit user-supplied dirs
- [ ] `restore.sh` validates the tarball doesn't contain `..` segments before extracting
- [ ] MCP `/memories/*` operations confined to `data/_memories/` (covered by Phase 4.0a)

### 5. Privilege

- [ ] No `sudo` calls during normal operation (install, update, uninstall, doctor, backup, restore)
- [ ] `sudo` only at install for `loginctl enable-linger` — interactive, not automated
- [ ] No `setuid` or `setgid` shenanigans
- [ ] Service unit doesn't grant capabilities; runs as the user (covered by 3.6.1)

### 6. Network

- [ ] All curl calls use `https://`
- [ ] No `--insecure` flag
- [ ] No `-k` flag
- [ ] We don't override `CURL_CA_BUNDLE` or similar
- [ ] No outbound to non-HTTPS endpoints anywhere in the stack
- [ ] systemd unit blocks non-IP socket families (covered by 3.6.3)

### 7. Supply chain

- [ ] `dist/install.sh` committed and identical to a fresh `bash build.sh` output (run it; check `git diff`)
- [ ] Bun installed from the official one-liner only (`https://bun.sh/install`)
- [ ] Claude Code installed from `@anthropic-ai/claude-code` only
- [ ] No vendored binaries / blobs in the repo

### 8. Multi-instance isolation

- [ ] Two instances don't read each other's secrets even when same user (file perms)
- [ ] Two instances' `bun` subprocesses don't share TELEGRAM_STATE_DIR
- [ ] Test: install instance `alpha` and `beta`; run `lsof | grep claudify` — should see both unit's processes operating only inside their own paths

### 9. Error handling

- [ ] Every `|| true` in shell has a comment explaining why
- [ ] Every `try/catch` in TS has a meaningful error message
- [ ] No silent swallowing of failures from `chmod`, `mv`, `mkdir -p`

## Acceptance criteria for the whole 3.6 umbrella

- [ ] All 6 sub-tasks shipped (their own acceptance criteria met)
- [ ] `systemd-analyze --user security claudify-default.service` ≤ 3.0
- [ ] Arm B checklist all ✅ or marked "deferred to Phase 5" with reason
- [ ] `tests/bash/security.bats` covers at least 5 audit items and passes
- [ ] README has a Security section accessible from the TOC (3.6.6)
- [ ] `docs/architecture.md §11` status updated; links to `.planning/research/security.md`
- [ ] CHANGELOG `### Security` entry in Unreleased summarising what was audited and tightened

## Test plan

- **Local:** `grep -rn 'eval' lib/ src/ *.sh` — empty (or each match annotated as safe)
- **Local:** bats security tests pass
- **Local:** `bash build.sh` is a no-op against the committed `dist/install.sh` (supply-chain check)
- **Station11:** `find ~/.claudify -type f -exec stat -c '%a %n' {} \; | grep -v '^[67]00\|^644'` — empty
- **Station11:** `systemctl --user cat claudify-default | grep -E '^Environment='` — only non-secret env vars
- **Station11:** `journalctl --user -u claudify-default | grep -oE 'sk-ant-oat01-[A-Za-z0-9_-]+' | head` — empty
- **Station11:** `systemd-analyze --user security claudify-default` reports the target score

## Out of scope (deferred to Phase 5)

- Cost ceiling enforcement
- Audit log of bot *actions* (we have an audit log of memory writes; bot actions through tools is a bigger feature)
- Signed releases / commits
- Encrypted-at-rest secrets via age/sops
- Per-skill resource limits (we cap the unit; per-skill is finer-grained)
- Penetration testing by an external party

## Notes / risks

- **Order matters within Arm A.** Tier-1 first (zero compatibility risk), then Tier-2 (filesystem write-restriction — needs path verification on Station11), then Tier-3 (syscall filter — needs full round-trip testing because some Bun/Node syscalls aren't in `@system-service`). Each ships separately so a Tier-3 break is reversible without losing Tier-1+2.
- **`bypassPermissions` stays.** It's the right call for an unattended bot. The fix for its risk is upstream isolation (this task), not turning permissions back on (which would break the bot). 3.6.6 documents the trade-off explicitly.
- **README's Security section is user-facing** — keep it readable, not a wall of text. The detailed threat model lives in `.planning/research/security.md`; README's job is plain English.
- **`MemoryDenyWriteExecute` and `ProtectSystem=strict` are explicitly excluded** — JIT compatibility + npm-global symlinks. Both documented in the relevant sub-tasks as "do not enable."
- **Some checklist items require Station11** (file-perm `find`, journalctl grep). Plan a 15-minute Station11 session as part of this umbrella.
