# Phase 4 — Capabilities

**Status:** ⏳ planned (kicks off after Phase 3 closes)
**Goal:** Move from *"Claudify exists and is healthy"* (Phase 3) to
*"Claudify is genuinely useful for personal-assistant work"*. The
codebase is in long-term shape after 3.x; Phase 4 is about turning
the bot into something the operator reaches for daily.

This is informed by `docs/skills.md`, the openclaw / clawhub
research notes, the Anthropic skill-engineering blog post, and the
canonical memory plan in [`.planning/research/memory.md`](../research/memory.md)
— that's the source of truth for the *why* behind every memory task
in this phase. Read it before starting any 4.x work.

---

## End-state target

After Phase 4:

```
# A real first-skill exists, ships with Claudify
operator → "remind me to call Dani Thursday"
bot      → ✓ saved to reminders.db, will ping Thursday 09:00

# Persona memory works across skills
operator → "summarize my week" (weekly-recap skill)
bot      → reads persona.db (knows operator timezone, working hours,
            language preference), uses them to format output

# DM pairing replaces hand-edit of access.json
new_user → /start (sends to bot)
bot      → "Pairing code: 1234. Ask the operator to approve."
operator → /approve 1234
bot      → "✓ user added to allowlist"

# Skill marketplace discovery works
operator → claude plugin install reminders@claudify-skills
         → skill drops under skills/reminders/
         → first-run prompt for any config.json setup
         → ready to use
```

---

## Tasks (planned, ordered by dependency)

> **Memory is the central thread of Phase 4.** Tasks 4.0a → 4.4 are
> the memory rollout per [`.planning/research/memory.md`](../research/memory.md).
> They land in the order below — 4.0a/b ship the substrate before
> anything depends on it. 4.2 (DM pairing) and 4.3 (reminders) are
> parallelisable once the substrate is up.

### 4.0a — `claudify-memory` MCP server (~3 hr)

**Goal:** A working MCP server in `src/mcp/memory/` that exposes the
9 tools defined in `.planning/research/memory.md` Part C (`memory.list`,
`memory.read`, `memory.write`, `memory.append`, `memory.delete`,
`memory.search`, `memory.recent`, `persona.get`, `persona.set`).
Backed by the file substrate (`data/_memories/*`) + SQLite stores
(`data/_persona/persona.db`, `data/_conversations/messages.db`). All
SQLite opens in WAL mode. All writes recorded to `data/_audit/writes.log`.

**Scope:**
- `src/mcp/memory/index.ts` — entrypoint, MCP boilerplate, tool registration (~80 lines)
- `src/mcp/memory/files.ts` — 5 file-op tools confined to `/memories/` with path-traversal protection (~120 lines)
- `src/mcp/memory/search.ts` — FTS5 wrappers + `memory.recent` (~100 lines)
- `src/mcp/memory/persona.ts` — `persona.get` + gated `persona.set` (~80 lines)
- `src/mcp/memory/audit.ts` — append-only audit log helper (~40 lines)
- `src/mcp/memory/db.ts` — SQLite open helpers, schema migrations, WAL mode (~60 lines)
- `tests/ts/mcp-memory.test.ts` — Bun tests with real SQLite + tmp filesystem (~150 lines)
- `src/package.json` — pin MCP SDK + `@types/bun` versions
- `build.sh` — bundle the MCP into `dist/` (or build separately as part of install)

**Acceptance:**
- All 9 tools callable via the MCP test harness
- `memory.write /memories/test.md "..."` then `memory.read /memories/test.md` round-trips
- Path traversal attempts (`../../etc/passwd`) refused
- `memory.search` finds messages matching FTS5 queries
- `persona.set` is rejected if not called from a sanctioned caller (gated by manifest declaration)
- `_audit/writes.log` has one line per write
- Tests green via `bash test.sh`
- Killing the MCP process and restarting is safe (no DB corruption)

**Engine-agnostic:** by construction. The MCP server doesn't know
which model is on the other side.

### 4.0b — Adapter wires the MCP via `engine_memory_setup` (~30 min)

**Goal:** When `install.sh` runs, the active engine adapter's
`engine_memory_setup` registers the freshly-built MCP with the
engine. After this task, `claude mcp list` (or the equivalent on a
future engine) shows `claudify-memory`.

**Scope:**
- Replace the no-op stub from 3.4.5.2 in `lib/engines/claude-code.sh`
  with a real implementation:
  ```bash
  engine_memory_setup() {
    step "Register memory MCP"
    local mcp_path="$CLAUDIFY_INSTANCE_DIR/bin/claudify-memory.js"
    run "mkdir -p $(dirname "$mcp_path")"
    run "cp $LIB_DIR/../src/mcp/memory/dist/index.js $mcp_path"
    run "claude mcp add claudify-memory bun run $mcp_path \
      --env CLAUDIFY_INSTANCE_DIR=$CLAUDIFY_INSTANCE_DIR"
    ok "memory MCP registered"
  }
  ```
- Wire `install.sh main()` to call `engine_memory_setup` after
  `engine_install_channel_plugin` and before `oauth_setup`.

**Acceptance:**
- After install, `claude mcp list` includes `claudify-memory`
- Service start spawns the MCP as a child of `claude`; `pgrep -laf claudify-memory` shows it
- doctor.sh adds a check: MCP responds to `tools/list` within 2 seconds
- Killing the MCP doesn't crash claude — bot continues serving non-memory queries

**Engine-agnostic:** the call site (`install.sh`) is unchanged for
future engines; only the body of `engine_memory_setup` differs per
adapter.

### 4.1 — `persona.db` + `lib/persona.sh` + auto-render via `engine_apply_persona` (~1 hr)

**Goal:** A shared `persona.db` exists at
`~/.claudify/instances/<n>/data/_persona/persona.db` with a `facts`
table. Bootstrapped from operator answers in onboarding (name, timezone,
language, working hours). On every persona update, the rendered
markdown block is pushed into the engine's surface via
`engine_apply_persona`.

**Scope:**
- `lib/persona.sh` with `persona_init` (creates DB + bootstraps from collect_inputs answers), `persona_set <key> <value> [--sensitive]`, `persona_get <key>`, `persona_list`, `persona_render` (returns the markdown block to inject).
- Schema per `.planning/research/memory.md` Part C:
  ```sql
  CREATE TABLE facts (
    key TEXT PRIMARY KEY, value TEXT NOT NULL,
    source TEXT, sensitive BOOLEAN DEFAULT 0,
    updated_at TEXT NOT NULL
  );
  ```
- `install.sh` calls `persona_init` and then `engine_apply_persona "$(persona_render)"` after the substrate is ready.
- `persona_set` calls `engine_apply_persona "$(persona_render)"` after every successful write so the block in `CLAUDE.md` stays current.

**Acceptance:**
- After install, `persona.db` has at minimum: `name`, `timezone`, `language`, `working_hours`
- `workspace/CLAUDE.md` has a marker-bracketed `## Who I am` block at the top with those facts
- Calling `persona_set` updates both DB + CLAUDE.md block
- Operator content below the block is preserved across `persona_set` calls
- The MCP `persona.get <key>` (from 4.0a) returns the same values
- doctor.sh validates persona.db schema + checks every fact has a non-null value

### 4.1.1 — `default remember <fact>` operator command (~30 min)

**Goal:** Operator can save persona facts with a single command,
deliberately and explicitly (anti-creep alternative to mem0's
auto-extract).

**Scope:**
- A built-in skill or `lib/cmd-remember.sh` invoked as
  `default remember "<key>" "<value>"` or natural language:
  `default remember "I prefer Friday meetings before noon"` →
  parses into key/value via Claude (or a simple heuristic).
- Calls `persona_set` from 4.1.
- Replies on Telegram with `✓ remembered: <key> = <value>`.

**Acceptance:**
- `default remember "preferred_meeting_time" "Friday morning"` persists to persona.db
- Auto-render updates CLAUDE.md
- Replied to via Telegram
- Bonus: natural-language input parses correctly via the engine

### 4.2 — DM pairing flow (~1 hr)

**Goal:** Adding a new allowed user becomes:
1. New user sends any message to the bot
2. Bot replies with a 4-digit pairing code, doesn't process the message
3. Operator (already in allowlist) sends `/approve 1234`
4. Bot adds the new user's ID to `access.json`, replies "added"

**Scope:**
- `lib/access.sh` (or extend the existing access.json handling) with `pairing_create`, `pairing_approve`, `pairing_revoke`
- New built-in skill `dm-pairing` that triggers when an unknown sender messages
- `access.json` already has a `"pending": {}` slot — wire it up

**Acceptance:**
- New user → pairing-code reply within 1 polling cycle
- `/approve <code>` from existing allowlisted user → addition lands in `access.json`, persists across restarts
- `/approve` from a non-allowlisted user is ignored (no privilege escalation)
- Failed pairing (wrong code, expired) replies with a helpful error

**Memory tie-in:** none directly; runs in parallel with 4.1.

### 4.3 — First real skill: `reminders` (~2 hr)

**Goal:** The first useful skill ships with Claudify. Uses
everything: data dir, persona, gotchas, progressive disclosure. Acts
as the **canonical reference** for skill authors.

**Scope:**
- `skills/reminders/SKILL.md` — written per `docs/skills.md` template
- `skills/reminders/scripts/add.sh`, `list.sh`, `mark-done.sh`
- `data/reminders/reminders.db` — schema:
  `reminders(id, text, due_at, created_at, notified)`
- A simple cron-like systemd timer that checks for due reminders every minute and sends them via Telegram

**Acceptance:**
- Operator says *"remind me to call Dani Thursday at 3pm"* → reminder saved
- Operator says *"what reminders do I have?"* → list returned
- At Thursday 3pm, bot proactively sends the reminder via Telegram
- Skill folder is < 500 lines `SKILL.md`, has Gotchas section, uses `${CLAUDIFY_SKILL_DATA}`

**Memory tie-in:** uses Tier 2 SQLite directly via the skill's data dir.

### 4.4 — Conversation log + FTS5 + `<private>` filter (~1 hr)

**Goal:** Every message exchanged via Telegram (or any future channel)
gets logged to `data/_conversations/messages.db`. The MCP's
`memory.search` and `memory.recent` tools (from 4.0a) query against
this DB. `<private>...</private>` spans are stripped before insert.

**Scope:**
- `data/_conversations/messages.db` per the schema in `.planning/research/memory.md` Part C, including the `messages_fts` FTS5 virtual table
- `lib/conversation-hook.sh` — opens the DB in WAL mode, strips `<private>` spans, inserts inbound + outbound rows
- Hook registration in the engine adapter (Claude Code's `PostToolUse` hook for Telegram send/receive)
- Privacy: explicit operator opt-out via `<no-log>...</no-log>` wrapping a single message

**Acceptance:**
- Inbound + outbound messages land in messages.db within seconds of arrival
- `<private>my PIN is 1234</private>` never appears in the DB
- Skills can `memory_assert_read messages.db` and query
- `memory.search "dani invoice"` (via the MCP) returns relevant rows
- doctor.sh validates the schema + FTS5 mirror integrity

### 4.5 — Skill marketplace discovery + install UX (~1.5 hr)

**Goal:** `claudify skill install <name>` resolves a skill from a
configured marketplace (start with one: a curated `claudify-skills`
GitHub org) and lays it under `skills/<id>/`, runs `config.json`
prompt if needed, registers in the manifest.

**Scope:**
- `bin/claudify-skill` (or extend the personal command from 3.4.6 with a `skill` subcommand)
- Pulls from `https://github.com/claudify-skills/<id>` by default
- Validates the skill structure (SKILL.md present, no top-level scripts that try to write outside `data/`)
- Updates manifest entry under `skills[]`

**Acceptance:**
- `default skill install reminders` works end-to-end on a fresh Station11
- Bad skill (missing SKILL.md / writes outside data dir) refuses to install with a clear error
- Manifest registers the install with version

### 4.6 — Skill template / `claudify skill new` (~1 hr)

**Goal:** Bootstrapping a new skill is one command. Generated skill
matches `docs/skills.md` template exactly.

**Scope:**
- `default skill new <id>` creates `skills/<id>/SKILL.md` from template + empty `scripts/`, `references/`, `assets/` dirs
- Frontmatter pre-filled with id + version 0.1.0
- Body has `## When to use`, `## Procedure`, `## Gotchas`, `## Files in this skill` placeholders ready to fill

**Acceptance:**
- `default skill new my-skill` produces a working skeleton
- Skeleton passes the manifest validation gate from 4.5

---

## Acceptance criteria for Phase 4

Phase 4 is **done** when:

- [ ] `claudify-memory` MCP is registered with the engine and serves all 9 tools (4.0a + 4.0b)
- [ ] persona.db exists with operator's name + timezone + language + working hours; `engine_apply_persona` keeps `CLAUDE.md` in sync (4.1)
- [ ] `default remember <fact>` writes to persona.db + auto-rerenders (4.1.1)
- [ ] DM pairing replaces hand-edit of access.json for adding users (4.2)
- [ ] `reminders` skill ships and fires reminders proactively via Telegram (4.3)
- [ ] Conversation log captures inbound + outbound messages, FTS5-queryable, `<private>` spans stripped (4.4)
- [ ] `default skill install` and `default skill new` work end-to-end (4.5 + 4.6)
- [ ] Every shipped skill has a Gotchas section, uses progressive disclosure, and writes to `${CLAUDIFY_SKILL_DATA}`
- [ ] `docs/skills.md` is referenced in onboarding + the personal-command help text — operators know where to learn the conventions
- [ ] If a hypothetical Gemini adapter were dropped in: only `lib/engines/gemini-cli.sh` would need new memory code; substrate + MCP server unchanged (the engine-agnostic invariant)

---

## Out of scope for Phase 4

- Voice integration (Phase 5+)
- Multi-channel beyond Telegram (Discord/WhatsApp) — already on the architecture roadmap, not a Phase 4 priority
- Live Canvas / A2UI — out of vision
- Vector / semantic memory (LanceDB / Chroma) — Phase 5+ trigger condition (operator hits FTS5 limits in real use)
- Compression / summarisation of old conversation rows — Phase 5+, only if row volume + token cost makes recap-style queries impractical
- Hosted SaaS path — out of vision (per PROJECT.md non-goals)
- Federation across machines — single-user PA doesn't need it
- Auto-extraction of facts from messages (mem0 style) — operator-explicit `default remember` is the path

---

## Notes

- **Memory rollout order is load-bearing.** 4.0a → 4.0b → 4.1 → 4.1.1 → 4.4 must land in that order; each builds on the previous.
- **4.2 (DM pairing) and 4.3 (reminders) are parallelisable** with the memory rollout once 4.0b lands. They use the substrate but don't block it.
- **Task 4.5 (marketplace discovery) is the natural moment to publish a curated `claudify-skills` GitHub org.** Pre-4.5 skills live in the Claudify repo itself (`/skills/`). Post-4.5, third-party skills become installable.
- **The skill template that 4.6 generates** should be a literal copy of `docs/skills.md` §5, with the placeholders ready to fill.
- **The MCP server is bundled into `dist/`** during build so curl-installs ship it without operators needing to clone the repo. `build.sh` runs `bun build src/mcp/memory/index.ts --outfile dist/mcp/memory/index.js` and the engine adapter copies it into the per-instance `bin/` dir at install time.
