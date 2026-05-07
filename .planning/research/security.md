# Security audit + hardening plan

**Status:** ✅ approved 2026-05-07 — execution lands as Phase 3.6 after Phase 3.4 closes
**Owner:** project owner
**Sources:** systemd.exec(5), systemd-analyze security, Anthropic Claude Code IAM docs, hardening guides
**See also:** [docs/architecture.md §11](../../docs/architecture.md), [phase-3-tasks/3.6-security.md](../phases/phase-3-tasks/3.6-security.md)

This document captures (a) the threat model Claudify defends against,
(b) what we have today, (c) the gaps, and (d) the concrete plan to
close them. Phase 3.6 task specs are the *how*; this doc is the
*why*.

---

## Part A — Threat model

Hardening is wasted if it defends against threats that don't apply.
What follows is the realistic threat list for a single-user
personal-PA running on the operator's own Linux server, accessed only
via Telegram.

### What we DO defend against

| # | Threat | Likelihood | Impact | Tier |
|---|---|---|---|---|
| 1 | **Prompt injection** via Telegram from an allowlisted user (account theft, social engineering, or just a confusing forwarded message) | Medium | High — bot has `bypassPermissions`, can run shell, edit files | Critical |
| 2 | **Malicious or buggy skill / MCP / plugin** writes outside its data dir, leaks secrets, or runs destructive ops | Medium (when skill ecosystem grows) | High | Critical |
| 3 | **Bot token / OAuth token leak** via process listing, logs, or filesystem permission gap | Low | High — full account takeover | Important |
| 4 | **Local user on the same machine reading the bot's data** | Very low (single-user server) | Medium | Defense-in-depth |
| 5 | **Random Telegram users spamming the bot** | Low (we have allowlist) | DoS only | Already handled |
| 6 | **Local privilege escalation from bot process to root** | Very low (user-mode service, no SUID) | Total | Defense-in-depth |

### What we do NOT defend against

These are out of scope by design — pretending to defend against them
would be theatre.

- **Multi-user scenarios.** Claudify is single-user by design. If you
  share the server, you share the bot.
- **Server compromise via unrelated paths.** Stolen SSH key, kernel
  CVE, etc. — that's OS hardening, not bot hardening.
- **Network attacks against Anthropic / Telegram themselves.**
- **Side-channel attacks on the host.** Spectre, rowhammer, etc.
- **Adversaries with physical access** to the server.

The hardening priorities therefore are **#1, #2, #3** — limit what
the bot process *can do at the OS level* so that a compromised
conversation, a buggy skill, or a leaked token has bounded blast
radius.

---

## Part B — Current state

### ✅ What's solid

- **Outbound-only network model.** Bot polls Telegram + calls
  Anthropic. No listener, no port to attack. Structurally safer than
  any service that opens a socket.
- **User-mode systemd service**, not system. The bot has zero
  capabilities, can't `mount`, can't bind low ports, can't read
  `/etc/shadow`. Inherits user's UID and that's it.
- **Minimal sudo footprint.** Exactly one sudo call, at install time,
  for `loginctl enable-linger`. After install, the bot never touches
  sudo.
- **Secrets via `EnvironmentFile=` not `Environment=`.** The unit
  text references the path; values aren't part of the unit. `systemctl
  cat` doesn't print tokens. They only appear in `/proc/<pid>/environ`
  (readable to same user / root only) — the standard pattern.
- **chmod 600** on `credentials.env`, `telegram/.env`, partial-state
  file. Owner-only.
- **OAuth token capture is well-designed.** `script(1)` capture file
  is `mktemp` + chmod 600, shredded after parsing. The install log
  bypasses tee via `< $TTY_DEV > $TTY_DEV` so the token never lands
  in `/tmp/claudify-install-*.log`.
- **Allowlist** at the channel layer. Random spam stops at the
  Telegram plugin before reaching Claude.

### ⚠️ What's missing

1. **The systemd unit has zero hardening directives.** No
   `NoNewPrivileges`, no `ProtectHome`, no `RestrictAddressFamilies`,
   no resource limits. A current `systemd-analyze --user security`
   run would likely return an exposure score of ~9.6 ("UNSAFE /
   EXPOSED") out of 10. Industry-standard target for a hardened
   service is 1.x–2.x.
2. **`access.json` is mode 644.** Contains user IDs (slightly
   sensitive). 600 is correct.
3. **`/tmp/claudify-install-*.log` is mode 644.** Doesn't contain
   tokens (verified) but does contain detailed install context.
   600 is correct.
4. **`bypassPermissions` is hardcoded with no docs.** Operator
   should know exactly what it means: anyone who can make Claude
   take actions can take actions.
5. **No process resource limits.** A runaway skill could fork-bomb
   or exhaust memory.
6. **No filesystem write-restriction.** A prompt-injected
   `rm -rf ~/.ssh` succeeds today.
7. **doctor.sh has no security checks.** No drift detection — six
   months from now we wouldn't know if hardening got reverted.

---

## Part C — The 10 items

Numbered + tier'd for the Phase 3.6 task specs. Each item maps to a
sub-task.

### Critical (biggest gap, biggest win)

#### 1. Tier-1 systemd hardening directives — *always safe*

These directives have **zero behavior risk** for our use case.
They drop powers the bot doesn't need.

```ini
# Privilege restrictions
NoNewPrivileges=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true

# Filesystem isolation
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectKernelLogs=true
ProtectClock=true
ProtectHostname=true

# Namespace restrictions
RestrictNamespaces=true

# Resource limits (DoS / runaway-skill mitigation)
MemoryMax=1G
TasksMax=200
LimitNPROC=200
```

| Directive | Plain meaning |
|---|---|
| `NoNewPrivileges` | Bot can never gain power. Setuid binaries can't escalate. |
| `PrivateTmp` | Bot's `/tmp/` is private; can't see/be seen by other processes. |
| `ProtectKernel*` | Bot can't modify kernel state, load modules, change clock. |
| `ProtectControlGroups` | Bot can't reach into Linux's process-grouping. |
| `RestrictNamespaces` | Bot can't create container-style sandboxes (where attackers hide). |
| `RestrictSUIDSGID` | Bot can't create files marked "run as someone else." |
| `RestrictRealtime` | Bot can't grab CPU priority and freeze the server. |
| `LockPersonality` | Bot can't pretend to be a different OS to fool a program. |
| `MemoryMax`/`TasksMax`/`LimitNPROC` | Caps memory + thread count + processes. Buggy skill = bounded damage. |

**Lands as:** [3.6.1](../phases/phase-3-tasks/3.6.1-tier1-hardening.md). ~30 min.

#### 2. Tier-2 filesystem write-restriction

```ini
ProtectHome=read-only
ReadWritePaths=%h/.claudify %h/.claude %h/.npm-global %h/.bun
```

Bot can read $HOME but can only **write** to those four explicit
paths. Stops `rm -rf ~/.ssh` cold; stops a skill from `>>` -ing into
`~/.bashrc`.

**Risk:** any path the bot legitimately needs to write that isn't
on the list will silently fail. Needs careful review of:
- `~/.claudify` ✓ (state)
- `~/.claude/` ✓ (Claude Code settings)
- `~/.npm-global/` ✓ (claude binary)
- `~/.bun/` ✓ (Bun runtime)
- `~/.bashrc` — we currently `>>` PATH lines into this. Either add
  to the list or move the PATH wiring elsewhere (preferred:
  `~/.profile` or a one-shot drop-in).

This is the **single biggest security win** in the whole plan.

**Lands as:** [3.6.2](../phases/phase-3-tasks/3.6.2-fs-write-restriction.md). ~45 min.

#### 3. Tier-3 address families + syscall filter

```ini
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
```

`AF_UNIX` for MCP stdio between claude and its subprocesses.
`AF_INET`/`INET6` for HTTPS to Telegram + Anthropic. Everything else
(raw packets, netlink, weird socket families) — banned.

`@system-service` is systemd's pre-curated allowlist of syscalls for
normal daemons. Blocks `kexec`, `bpf`, `swapon`, `userfaultfd`, and
~250 other unusual calls.

**Risk:** higher compatibility risk than Tier 1 — needs Station11
testing because Bun + Node + claude all link against system
libraries that may use unusual syscalls.

**Lands as:** [3.6.3](../phases/phase-3-tasks/3.6.3-syscall-and-network.md). ~30 min.

### Important (defense in depth)

#### 4. Tighten file permissions

- `access.json` → chmod 600 (was 644)
- `/tmp/claudify-install-*.log` → chmod 600 + `umask 077` before creation

Both files contain "operationally sensitive" data even if not
secret-secret. On a multi-user server, 644 leaks the allowlist + the
install topology to any logged-in user. Cheap to fix; defense in
depth.

**Lands as:** [3.6.4](../phases/phase-3-tasks/3.6.4-file-permissions.md). ~15 min.

#### 5. doctor.sh security section

A new "Security" section in `doctor.sh` that verifies hardening
hasn't drifted. Each check fails loud with a fix hint:

- All chmod-600 files actually are 600
- Systemd unit contains the Tier-1 directives (regex check)
- `systemd-analyze --user security` returns a score below threshold
  (default: ≤ 3.0)
- `~/.claudify/credentials.env` owned by the operator
- No tokens visible in `ps -eo cmd | grep claude`

**Lands as:** [3.6.5](../phases/phase-3-tasks/3.6.5-doctor-security-section.md). ~30 min.

### Documentation

#### 6. Document `bypassPermissions` explicitly

- Comment in `lib/engines/claude-code.sh::engine_run_args` explaining
  why the flag is there (headless service, no operator at the
  terminal to approve every tool call).
- Section in `docs/architecture.md §11` listing what this implies
  for the threat model.
- README "Security" section explaining the trust model in plain
  English: *"the bot has the same access you have. Hardening limits
  where it can write and which network connections it can make. If
  someone gets through the allowlist, they can ask the bot to take
  actions within those limits — but not outside."*

**Lands as:** [3.6.6](../phases/phase-3-tasks/3.6.6-security-docs.md). ~15 min.

### Out of scope for now

#### 7. Per-skill resource limits — Phase 5+

Each skill gets its own memory cap, file-write cap, etc. Useful when
skills are real and operator wants per-skill blast-radius. Today no
skills exist, so unnecessary.

---

## Part D — Estimated `systemd-analyze security` score

Based on hardening guides and our current unit:

| Score (0=safe, 10=exposed) | Configuration |
|---|---|
| ~9.6 ("UNSAFE / EXPOSED") | Today's unit — no hardening |
| ~5.0 ("OK") | After Tier 1 (always-safe + resource limits) |
| ~3.0 ("MOSTLY OK") | After Tier 2 (filesystem write-restriction) |
| ~2.0 ("OK") | After Tier 3 (address families + syscall filter) |

Industry-respected daemons (sshd hardened, nginx hardened) sit
around 2-3. Hitting 2.0 for a personal-PA is achievable and
worthwhile.

The acceptance test for 3.6.5 (doctor security section) enforces
**≤ 3.0** as the floor — once we ship 3.6.1 + 3.6.2, drift would
trigger a doctor failure.

---

## Part E — Decisions baked into this plan

After research and discussion, these are the decisions. Future
contributors must respect them or open an ADR to change them.

1. **Hardening lands as Phase 3.6** — *after* Phase 3.4 closes
   (multi-instance paths must be stable; ReadWritePaths references
   them) and *before* Phase 4 starts (skills must run under a
   hardened unit; otherwise we'd retroactively add restrictions
   that break installed skills).

2. **Tier-1 first, Tier-2 second, Tier-3 third.** Each is a separate
   commit + Station11 round-trip. We don't bundle — if Tier-3
   breaks something, we want a clean revert that keeps Tier-1+2.

3. **Acceptance criterion is `systemd-analyze` score, not a
   directive checklist.** The score is what matters. The directive
   list may evolve as systemd ships new ones.

4. **`bypassPermissions` stays.** It's the right call for an
   unattended bot. The fix for its risk is upstream isolation, not
   turning permissions back on (which would break the bot). The
   *fix* is documenting it loudly so operators know what they're
   running.

5. **Per-skill resource limits deferred to Phase 5+.** Premature
   today; valuable when skills are real and there's actual data
   about which skills misbehave.

6. **No `MemoryDenyWriteExecute`.** Bun and Node use JIT —
   `MDWE=true` would crash the bot at startup. Documented as a
   "do not enable" in the relevant task spec.

7. **No `ProtectSystem=strict`.** Possibly blocks `/usr` symlinks
   for the npm-global claude binary. Tier-1 covers most of the
   benefit without the risk. Revisit only if a hardening guide
   identifies it as low-risk for our shape.

---

## Part F — Execution: 6 sub-tasks (Phase 3.6)

| # | Task | Effort | Tier |
|---|---|---|---|
| 1 | [3.6.1 — Tier-1 hardening](../phases/phase-3-tasks/3.6.1-tier1-hardening.md) | 30 min | Critical |
| 2 | [3.6.2 — Filesystem write-restriction](../phases/phase-3-tasks/3.6.2-fs-write-restriction.md) | 45 min | Critical |
| 3 | [3.6.3 — Address families + syscall filter](../phases/phase-3-tasks/3.6.3-syscall-and-network.md) | 30 min | Critical |
| 4 | [3.6.4 — Tighten file permissions](../phases/phase-3-tasks/3.6.4-file-permissions.md) | 15 min | Important |
| 5 | [3.6.5 — doctor security section](../phases/phase-3-tasks/3.6.5-doctor-security-section.md) | 30 min | Important |
| 6 | [3.6.6 — Security documentation](../phases/phase-3-tasks/3.6.6-security-docs.md) | 15 min | Documentation |

**Total:** ~2.75 hr across 6 commits, each with a Station11
round-trip and a `systemd-analyze` score check.

---

## Part G — Success criteria

After all 6 tasks ship:

- [ ] `systemd-analyze --user security claudify-default.service`
      returns a score ≤ 3.0
- [ ] All Tier-1 directives present in the unit (`grep -c
      'NoNewPrivileges\|PrivateTmp\|Protect.*=' ...service` ≥ 10)
- [ ] `ProtectHome=read-only` + `ReadWritePaths=%h/.claudify`
      present and the bot still works end-to-end on Station11
- [ ] `RestrictAddressFamilies=` + `SystemCallFilter=` present and
      the bot still polls Telegram + calls Anthropic
- [ ] `access.json` and the install log are both mode 600
- [ ] `doctor.sh` has a "Security" section that checks all of the
      above and fails if any drift
- [ ] README has a "Security" section that explains the trust model
      in plain English
- [ ] `docs/architecture.md §11` documents `bypassPermissions` +
      links to this research doc

---

## Appendix — What WOULD make us pivot

What WOULD change this plan:

- **Real-world incident** where a skill or message did real damage
  → revisit per-skill isolation (Phase 5 → bring forward) or
  per-action approval flows
- **bun-on-MDWE compatibility** ships → enable `MemoryDenyWriteExecute`
- **Multi-tenant becomes a goal** → fundamental rethink (probably
  doesn't happen — it's against the project's vision)
- **systemd-analyze score targets shift** in the wider community —
  if 1.0 becomes the new "OK", we tighten more

What WOULDN'T:
- A new Claude model
- A faster Claude Code CLI
- Bot popularity changes (even with ten skills installed, the
  hardening shape is the same)
- Adding multi-channel (Discord/WhatsApp) — same network shape,
  same hardening
