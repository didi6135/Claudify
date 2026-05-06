# Memory MCP — research, design decisions, and execution plan

**Status:** ✅ approved 2026-05-06 — execution begins after Phase 3 closes
**Owner:** project owner
**Reviewed prior art:** Anthropic memory tool, Letta (MemGPT), mem0, LangGraph memory, claude-mem, openclaw / clawhub
**See also:** [docs/skills.md](../../docs/skills.md), [docs/architecture.md §4-§6](../../docs/architecture.md), [phase-4-capabilities.md](../phases/phase-4-capabilities.md)

This document captures (a) the research that shaped Claudify's memory
architecture, (b) the decisions taken, and (c) the execution plan
across Phase 3.4.5.x and Phase 4. It is the single source of truth
for the *why* behind memory; task specs cover the *how*.

---

## Part A — Research summary

### Prior art surveyed

| Source | Approach | License | Stars | What we learn |
|---|---|---|---|---|
| **Anthropic memory tool** ([docs](https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool)) | File-based memory dir `/memories`, host-side storage, 6 commands. Pairs with context editing + compaction. | — | (built-in) | The host owns storage. The tool contract is just file ops. **Just-in-time retrieval** is the recommended pattern. |
| **Letta** (MemGPT successor) | OS-style hierarchy: core (in-context blocks) + recall (search) + archival (vector). LLM has tools to read/write each. | Apache 2.0 | 22.5k | Memory blocks with labels (human, persona) is a clean abstraction. |
| **mem0** | Fact extraction via LLM at write-time. Multi-level scope (user/session/agent). Hybrid retrieval (semantic + BM25 + entity). | Apache 2.0 | 54.9k | Auto-extract is *creepy* in a personal-PA context — explicit is better. |
| **LangGraph memory** | Thread-scoped checkpointer (short-term) + cross-thread BaseStore (long-term) with namespaces. | MIT | (LangChain) | Explicit warning: *"don't write memory in the hot path"*. Avoid monolithic profiles. |
| **claude-mem** | Lifecycle-hook capture → SQLite + FTS5 + Chroma vectors + daemon → context injection on next session. | AGPL | 72k | Validates SQLite + FTS5 path. Daemon + AGPL + auto-inject too heavy for our model. |
| **openclaw / ClawHub** | Local-first multi-channel runtime, vector DB plugins, gateway/agent/channel split. | various | — | Pairing-based DM auth, per-skill data dirs. Full system is a *competitor*, not a component. |

### Memory taxonomy that matters

Adapted from cognitive science via LangGraph:

| Type | What it holds | How long | Where for Claudify |
|---|---|---|---|
| **Working** | Current turn context | seconds-minutes | LLM context window — already handled by Claude Code |
| **Semantic** | Facts about the user/world | months-years | `data/_persona/persona.db` |
| **Episodic** | Specific events/conversations | indefinite | `data/_conversations/messages.db` (FTS5) |
| **Procedural** | How-to-do-things rules | indefinite | `workspace/CLAUDE.md` + `skills/<id>/SKILL.md` — already handled |

### Two ways an agent gets memory into context

1. **Proactive injection** ("hot path", what claude-mem does) — pre-search & inject. Simple but rigid; LangGraph explicitly warns against it.
2. **Tool-driven access** (Anthropic memory tool, Letta, mem0 native) — model decides when to query. Far more flexible at small extra latency cost.

**Decision:** Tool-driven primary. Proactive only for the small persona-summary slice that's always relevant.

### Storage primitives — ranked by complexity

| Primitive | Use it for | Verdict |
|---|---|---|
| Markdown / text files | Persona facts, freeform notes | ✅ Tier 1 |
| JSON files | Tiny structured config | 🟡 ok but SQLite is barely heavier |
| SQLite (no FTS) | Per-skill tabular data | ✅ Tier 2 default |
| **SQLite + FTS5** | Conversation log, message search | ✅ The sweet spot |
| Vector DB (Chroma/LanceDB) | Semantic similarity | ⛔ Defer — opt-in plugin only |
| Graph DB | Entity-relationship | ⛔ Never (single-user PA) |

The case against vectors at our scale: 365 days × 50 msg/day = 18k rows/year. SQLite + FTS5 handles this in sub-millisecond queries. Embedding models add cost + complexity for queries that exact + keyword match would solve.

### Anthropic's "memory tool" insight

From their docs: *"This is the key primitive for **just-in-time
context retrieval**: rather than loading all relevant information
upfront, agents store what they learn in memory and pull it back on
demand."*

The Anthropic tool is **client-side** — the host owns storage. They
specify the protocol (`view`, `create`, `str_replace`, `insert`,
`delete`, `rename`). We could implement their contract directly.

But: that's Claude-coupled. A Gemini engine adapter wouldn't have
that tool. We need something cross-engine.

---

## Part B — The engine-agnostic constraint

**Hard rule from the project owner:**
> *"It's important that our tool stays flexible to swap in another
> model in the future. We need to think about this all the time."*

What that excludes:
- Claude-specific tool surfaces (e.g. `memory_20250818`) as the *primary* memory interface
- `~/.claude/...` references in core Claudify code (only inside `lib/engines/claude-code.sh`)
- Any "the model is Claude" assumption outside the engine adapter

What that demands:
- Storage substrate is universal (files + SQLite — no model-specific format)
- Model-facing surface lives behind an `engine_*` contract function so each adapter can wire its model's tool format
- A protocol layer that other vendors also speak

**Conclusion: MCP is the answer.** It's a tools protocol designed for
exactly this — separating storage substrate from any one model's tool
format. Anthropic invented it; Gemini CLI ships it; Codex shims
exist; Llama wrappers (Ollama, llama.cpp) are converging.

---

## Part C — The plan

### Architecture in one picture

```
┌──────────── Telegram channel plugin ────────────┐
│  inbound msg → claude → outbound reply          │
└────────────────────┬────────────────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │  claude (engine) process tree   │
    │                                 │
    │  ├── telegram-plugin MCP        │
    │  └── claudify-memory MCP        │  ← THE NEW THING
    │      (TypeScript / Bun, stdio)  │
    └────────────────┬────────────────┘
                     │ reads/writes
                     ▼
  ~/.claudify/instances/<name>/data/
  ├── _memories/                      ← Tier 1: file-based memory
  │   ├── preferences.md
  │   ├── pending-tasks.md
  │   └── …
  ├── _persona/persona.db             ← Tier 0: facts (auto-rendered)
  ├── _conversations/messages.db      ← Tier 2: log + FTS5
  ├── _audit/writes.log               ← every memory write recorded
  └── <skill-id>/…                    ← per-skill data (3.4.5.1)
```

### Three tiers of memory

| Tier | Tech | Always loaded? | Used for |
|---|---|---|---|
| **0 — Persona summary** | `persona.db` rendered to engine-specific surface (`CLAUDE.md` for Claude) via `engine_apply_persona` | Yes — every session | Compact set of "facts about you" the model always needs |
| **1 — File-based memory** | `data/_memories/*.md` (or any file), accessed via `claudify-memory` MCP | On demand | Freeform notes, project crumbs, session bridges |
| **2 — Structured / queryable** | `data/<skill_id>/<name>.db` (SQLite + FTS5 where useful) | On demand | Conversation log, reminders, calendar, expense items |
| **3 — Vector / semantic** | Optional plugin (Chroma/LanceDB) | If installed | Semantic recall when FTS5 isn't enough — Phase 5+ trigger |

### The MCP server — `claudify-memory`

Implemented in TypeScript under `src/mcp/memory/`, runs under Bun
(already a Claudify dependency). Speaks JSON-RPC over stdio with the
host CLI. Exposes 9 tools:

| Tool | Purpose | Backed by |
|---|---|---|
| `memory.list` | List files in `/memories/` | filesystem |
| `memory.read` | Read a memory file | filesystem |
| `memory.write` | Create/overwrite a file | filesystem + audit log |
| `memory.append` | Append (good for journals/logs) | filesystem + audit log |
| `memory.delete` | Delete a file | filesystem + audit log |
| `memory.search` | FTS5 over `messages.db` | SQLite |
| `memory.recent` | Last N messages on a channel | SQLite |
| `persona.get` | Read a persona fact by key | SQLite |
| `persona.set` | Write a persona fact (gated) | SQLite + audit log |

All file ops confined to `/memories/` (path traversal protection).
All SQLite opens use WAL mode + parameterized queries. Every write
appends to `_audit/writes.log`.

### Schemas

#### `_persona/persona.db`
```sql
CREATE TABLE facts (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  source      TEXT,              -- "manual", "remember-skill", etc
  sensitive   BOOLEAN DEFAULT 0, -- if 1, never echoed back unprompted
  updated_at  TEXT NOT NULL      -- ISO-8601
);
```

Bootstrapped at install with: name, timezone, language, working
hours, communication style — pulled from operator answers in
onboarding.

#### `_conversations/messages.db`
```sql
CREATE TABLE messages (
  id          INTEGER PRIMARY KEY,
  channel     TEXT NOT NULL,         -- "telegram", future others
  direction   TEXT NOT NULL,         -- "in" | "out"
  sender_id   TEXT,
  body        TEXT NOT NULL,
  ts          TEXT NOT NULL,         -- ISO-8601
  thread_id   TEXT
);
CREATE VIRTUAL TABLE messages_fts USING fts5(
  body, content='messages', content_rowid='id'
);
```

`<private>...</private>` spans stripped from `body` before insert.

#### `_audit/writes.log`
Append-only NDJSON. One line per write.
```json
{"ts":"2026-05-06T11:23:00Z","tool":"memory.write","path":"/memories/x.md","bytes":1234,"caller":"engine"}
```

### Engine contract: 8 → 10 functions

| New function | Args | Purpose | Claude Code adapter does |
|---|---|---|---|
| `engine_memory_setup` | — | Make our MCP visible to the engine. Idempotent. | `claude mcp add claudify-memory bun "$dist_path"` |
| `engine_apply_persona` | `<rendered-text>` | Make persona text part of every model session | Writes to `${CLAUDIFY_INSTANCE_DIR}/workspace/CLAUDE.md` (preserving operator additions below a marker) |

A future Gemini adapter implements both differently — but
`install.sh`, `lib/persona.sh` and other call sites don't change.

### What we explicitly defer

- **Vector / semantic memory** — opt-in skill in Phase 5+. Trigger: operator complains FTS5 missed something they remember saying.
- **Compression / summarization** — Phase 5+. Trigger: row volume + token cost makes recap-style queries impractical.
- **Web UI** — never. Out of scope.
- **Daemon process / network listener** — never. Violates clean-uninstall invariant. The MCP subprocess is a child of claude, not a daemon — `ps aux` shows it under claude's tree, not as its own service.
- **Auto-extract from messages (mem0 style)** — never automatically. Operator-explicit `default remember <fact>` is the path.

### Privacy patterns adopted

- **`<private>...</private>` tag convention** — operator wraps anything they don't want in the conversation log. Stripped before insert into `messages.db`. Filtering is in-bounds for skills that read the log.
- **`sensitive` column on persona facts** — flagged facts are stored but never echoed back unprompted (model has to be specifically asked).
- **Per-skill data dir at chmod 700** — accident-prevention, not malicious-actor defence (operator trusts own bot).
- **Operator-triggered prune** — `default memory prune --older-than <N>d` exists; never runs automatically.
- **No fact auto-extraction** — explicit `default remember` only. Anti-creep alternative to mem0.

### Failure modes + fallbacks

| Failure | What happens | Recovery |
|---|---|---|
| MCP fails to start (Bun missing, build broken) | Bot still works for non-memory queries. Doctor flags MCP unhealthy. | Re-run `update.sh`; or `systemctl --user restart claude-telegram` |
| MCP throws on a tool call | Model gets error response, retries or skips. | Automatic, plus tests catch in CI |
| MCP returns wrong data (silent corruption) | Worst case — model misremembers | Audit log + `default memory verify` (Phase 5) |
| MCP spec changes | Pin SDK version; CI catches before deploy | Bounded adapter rewrite; data preserved |
| SQLite corruption | WAL mode protects against process kill | `PRAGMA integrity_check` in doctor; `default backup` (Phase 5) |
| Our own bug | Localised | Same as any code — test + fix |

**The substrate safety net:** all data is in plain files + SQLite at
known paths. If the MCP is dead or removed, operator can `cat`,
`sqlite3`, or `vi` directly against the data dir. There is no
scenario where memory is locked behind a process the operator can't
bypass.

---

## Part D — Decisions baked into this plan

After research and discussion, these are the decisions. Future
contributors must respect them or open an ADR to change them.

1. **MCP-first architecture** — cross-engine, TypeScript MCP server. Backed by per-instance file + SQLite substrate.
2. **9 tools** — 5 file ops + 2 search + 2 persona. Bound to grow with skills' needs but starts small.
3. **`<private>` tag convention** — operator-controlled privacy in the conversation log.
4. **Operator-explicit `default remember`** — no auto-extract from messages. Surprises are creepy in a personal PA.
5. **No vector search, no daemon, no web UI** — substrate is files + SQLite. Period.
6. **Audit log on every write** — operator can always see what was persisted.
7. **Phase 3 stays MCP-free** — Phase 3 ships only the substrate + contract additions. The MCP server itself is Phase 4 work. This keeps Phase 3 commits engine-agnostic and small.
8. **Vector / summarization deferred** — opt-in plugins in Phase 5+ with documented trigger conditions.
9. **Engine-agnostic rule promoted to CLAUDE.md** — explicit, not implicit. Future tasks can't drift back into Claude-coupling without breaking the rule out loud.

---

## Part E — Execution: 7 tasks across 2 phases

### Phase 3 (substrate + contract — MCP-free)

| # | Task | Effort | Files |
|---|---|---|---|
| 1 | **3.4.5.1** Skill data dir + `lib/memory.sh` | 45 min | `lib/memory.sh`, manifest schema, `install.sh` |
| 2 | **3.4.5.2** Engine contract: `engine_memory_setup` + `engine_apply_persona` (no-ops at first) | 30 min | `lib/engines/claude-code.sh`, `lib/engines/README.md` |

Phase 3 closes after 3.4.8 docs sync. The substrate is in place; nothing
yet calls the new contract functions actively.

### Phase 4 (memory becomes real)

| # | Task | Effort | Files |
|---|---|---|---|
| 3 | **4.0a** `claudify-memory` MCP server | 3 hr | `src/mcp/memory/*.ts`, `tests/ts/mcp-memory.test.ts`, `src/package.json`, `build.sh` |
| 4 | **4.0b** Adapter wires the MCP via `engine_memory_setup` | 30 min | `lib/engines/claude-code.sh` |
| 5 | **4.1** `persona.db` substrate + `lib/persona.sh` + auto-render via `engine_apply_persona` | 1 hr | `lib/persona.sh`, `install.sh`, schema migration |
| 6 | **4.1.1** `default remember <fact>` operator command | 30 min | new `default-remember` skill or built-in |
| 7 | **4.4** Conversation log + FTS5 + `<private>` filter + post-tool-use hook | 1 hr | `lib/conversation-hook.sh`, hook registration in adapter |

**Total new code estimate:** ~960 lines + ~230 lines tests, ~7.5 hours of focused work across 7 commits, each with its own Station11 round-trip.

### Order + dependencies

```
3.4.5  multi-instance layout (already pending)
3.4.5.1  skill data dir + lib/memory.sh
3.4.5.2  engine contract + 2 new functions (no-ops at first)
3.4.6  personal command wrapper (already on roadmap)
3.4.7  migration logic (already on roadmap)
3.4.8  docs sync (already on roadmap)
── Phase 3 closes ──
4.0a  MCP server                          ← memory work begins
4.0b  adapter wires the MCP
4.1   persona substrate + auto-render
4.1.1  default remember
4.2   DM pairing (already on roadmap, parallelizable with 4.1)
4.3   reminders skill (already on roadmap, parallelizable)
4.4   conversation log + private filter
── Phase 4 closes ──
```

The MCP work doesn't block anything in Phase 3. Phase 3 ships
completely engine-agnostic infrastructure (paths, manifest, commands,
migration). Phase 4 layers memory on top.

---

## Part F — Success criteria for the memory work

After all 7 tasks ship:

- [ ] `~/.claudify/instances/<name>/data/` is the canonical memory substrate; survives `update.sh`
- [ ] `claudify-memory` MCP server is registered with the active engine; visible in `claude mcp list`
- [ ] Bot can recall persona facts via `persona.get` (operator types *"what's my timezone?"* → bot reads → answers)
- [ ] Bot can search conversation history via `memory.search` (operator types *"what did Dani say last week?"* → bot searches → answers, citing messages)
- [ ] `<private>...</private>` spans never appear in `messages.db`
- [ ] `default remember <fact>` persists to `persona.db` and re-renders into `CLAUDE.md` via `engine_apply_persona`
- [ ] doctor reports the MCP healthy + every DB passing `PRAGMA integrity_check`
- [ ] Killing the MCP process leaves the bot still working for non-memory queries (graceful degradation)
- [ ] Operator can `sqlite3 ~/.claudify/.../persona.db "SELECT * FROM facts"` and see exactly what's stored
- [ ] If we swap in a hypothetical Gemini adapter tomorrow: only `lib/engines/gemini-cli.sh` needs new memory code; substrate + MCP server unchanged

---

## Appendix — The "won't change my mind" cases

What WOULD make us pivot:

- **MCP gets deprecated by Anthropic AND no successor emerges** — the protocol layer would need replacement, but the substrate (files + SQLite) keeps all data. Cost: ~100 lines of new transport code in the MCP server.
- **Operator hits FTS5 limits in real use** — add the optional vector plugin in Phase 5. Doesn't change Tier 0/1/2, just adds Tier 3.
- **Multi-user / multi-tenant becomes a goal** — would require rethinking per-instance isolation. Not on the roadmap.
- **Anthropic's `memory_20250818` becomes the dominant cross-vendor format** — we'd add it as a *supplementary* tool registration in the Claude adapter. Substrate doesn't change.

What WOULDN'T:
- A new Claude model
- A faster Claude model
- Claude Code CLI minor bumps
- Skill ecosystem growth
- Operator wanting more skills installed
