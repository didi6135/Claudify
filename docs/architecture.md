# Architecture

How Claudify is built, organized, and extended. This is the doc a
contributor reads first. When you change anything structural, update
this doc in the **same commit** (per `CLAUDE.md` rule 2).

---

## 1. Core invariants

Five truths that don't change — every design decision flows from these.

1. **Claudify is a *harness*, not an *engine*.** The harness does
   install / update / lifecycle / extension management. The *engine*
   is whatever generates the AI responses. Today's engine is Claude
   Code; the architecture is built so other engines can plug in.
2. **One curl command on the target server is the install UX.** No
   operator-side CLI, no SSH-from-laptop. Anyone with a Linux server
   should be able to `bash <(curl …)` and reach a running assistant
   in under 3 minutes. (See ADR 0004.)
3. **All Claudify state lives under `~/.claudify/`.** Uninstall is
   `rm -rf ~/.claudify` plus disabling the systemd unit. We do not
   scatter state across `/etc`, `/opt`, or other home directories.
4. **Per-instance isolation by default.** Every install is an
   *instance* — name, state dir, systemd unit, OAuth token are all
   per-instance. One server can host multiple instances side-by-side
   without interference.
5. **Extensions are first-class, named, and discoverable.** Channels
   (Telegram, Discord, …), MCPs (Gmail, Drive, …), skills (custom
   commands), and hooks (event handlers) each have their own
   directory, lifecycle, and manifest entry.

## 2. Layering

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1 — Bootstrap (bash)                                 │
│    install.sh, update.sh, uninstall.sh, doctor.sh,          │
│    backup.sh, restore.sh, build.sh                          │
│  Runs on a bare Linux server. Only needs bash + coreutils.  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Layer 2 — Engine runtime (provided by the engine adapter)  │
│    Today: Claude Code CLI                                   │
│    The engine handles the actual AI interaction loop:       │
│    receives messages from channels, calls MCP tools,        │
│    writes responses back. We don't reinvent this.           │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Layer 3 — Lifecycle tools (TypeScript via Bun)             │
│    backup, restore, future complex tooling.                 │
│    Bash for bootstrap is non-negotiable; everything that    │
│    runs *after* install can assume Bun exists, so we use TS │
│    for anything beyond ~200 lines of bash. (ADR 0005.)      │
└─────────────────────────────────────────────────────────────┘
```

## 3. Folder architecture

### 3a. Repo layout (the source code)

```
claudify/
├── README.md   CHANGELOG.md   CLAUDE.md   LICENSE
│
├── install.sh           # one-command install (curl|bash entry point)
├── update.sh            # in-place refresh (preserves state)
├── uninstall.sh         # clean removal of one instance
├── doctor.sh            # health diagnostic
├── backup.sh            # bash shim → src/backup.ts via bun
├── restore.sh           # bash shim → src/restore.ts via bun
├── build.sh             # produces dist/install.sh from lib/+install.sh
│
├── lib/                 # shared bash modules (sourced by entrypoints)
│   ├── ui.sh            # colors, step/ok/warn/fail, banners
│   ├── prompts.sh       # TTY detection + ask family
│   ├── validate.sh      # input validators (regex, blocklist)
│   ├── args.sh          # CLI flag parsing
│   ├── preflight.sh     # OS / deps / linger checks
│   ├── manifest.sh      # read / write claudify.json + instances.json
│   ├── onboarding.sh    # intro + walkthroughs + collect_inputs
│   ├── configs.sh       # per-channel config writes
│   ├── service.sh       # systemd unit generation + lifecycle
│   ├── oauth.sh         # engine-agnostic OAuth orchestration
│   ├── personal-cmd.sh  # ~/.local/bin/<name> wrapper generation
│   └── engines/
│       └── claude-code.sh   # the only engine adapter today
│
├── src/                 # TypeScript (run via Bun)
│   ├── backup.ts        # entrypoint — tar instance state
│   ├── restore.ts       # entrypoint — untar to fresh server
│   ├── lib/
│   │   ├── log.ts       # colored output (TS twin of bash ui.sh)
│   │   ├── state.ts     # read/write per-instance dirs
│   │   ├── manifest.ts  # TS-side manifest helpers
│   │   └── systemd.ts   # systemctl --user wrappers
│   ├── tsconfig.json
│   └── package.json
│
├── dist/                # built artifacts (committed for curl)
│   ├── install.sh       # concatenation of lib/+install.sh
│   └── (future: bundled TS for backup/restore)
│
├── docs/                # user-facing documentation
│   ├── architecture.md   ← THIS FILE
│   ├── prerequisites.md
│   ├── troubleshooting.md
│   └── faq.md
│
├── tests/               # test suites
│   ├── bash/            # bats-core integration tests
│   └── ts/              # bun test for src/
│
└── .planning/           # internal — never read by users
    ├── PROJECT.md   ROADMAP.md   conventions.md
    ├── upstream-wishlist.md   who-am-i.md
    ├── LOCAL*                       (gitignored — secrets ok here)
    ├── decisions/                   ADRs
    └── phases/                      phase docs
```

### 3b. Runtime layout (the server, after install)

```
~/.claudify/
├── instances.json                        # registry of all instances
└── instances/
    ├── default/                          # first install lands here
    │   ├── claudify.json                 # this instance's manifest
    │   ├── credentials.env               # engine OAuth (chmod 600)
    │   ├── workspace/                    # engine's working directory
    │   │   └── CLAUDE.md                 # persona / operator preferences
    │   ├── channels/<name>/              # one dir per enabled channel
    │   │   ├── .env                      # channel secrets (chmod 600)
    │   │   └── access.json               # allowlist / policy
    │   ├── mcps/<name>/                  # one dir per enabled MCP
    │   │   └── oauth.json                # MCP-specific creds (chmod 600)
    │   ├── skills/<name>/                # operator-installed skills
    │   │   └── SKILL.md                  # Claude-readable skill definition
    │   ├── hooks/                        # hook configs (audit, cost, etc.)
    │   └── logs/                         # install / runtime logs (per-instance)
    └── business/                         # second instance, if any
        └── (same shape as default)
```

User-facing personal command lives at `~/.local/bin/<name>` (see 3f).

### 3c. State Claudify reads but doesn't own

| Path | Owned by | Claudify behavior |
|---|---|---|
| `~/.claude/` | Claude Code (engine) | Read-only by Claudify; never deleted on uninstall |
| `~/.claude.json` | Claude Code (engine) | Modified to add per-workspace trust + onboarding flags |
| `~/.config/systemd/user/claudify-<name>.service` | systemd | Created by us, removed on uninstall — not under `~/.claudify/` because systemd requires this exact path |
| `~/.bun/`, `~/.npm-global/` | The runtimes themselves | Installed by us; left in place on uninstall (operator may use them elsewhere) |

**Rule of thumb:** anything not under `~/.claudify/` is *touched but not owned*. Uninstall removes the systemd unit only.

### 3d. Personal command per instance (named CLI)

Each instance gets a friendly command named after the instance. If the
operator names their instance `david`:

```bash
$ david doctor       # → wraps doctor.sh --name david
$ david update       # → update.sh --name david
$ david uninstall    # → uninstall.sh --name david
$ david status       # → systemctl --user status claudify-david
$ david logs         # → journalctl --user -u claudify-david -f
$ david restart      # → systemctl --user restart claudify-david
$ david stop         # / start
$ david              # → usage hint
```

The command is a generated wrapper script at `~/.local/bin/<name>`,
created during install, removed during uninstall. `~/.local/bin` is
appended to `PATH` in `~/.bashrc` / `~/.zshrc` if not already present.

**Validation on the instance name** (`lib/validate.sh`):
- Must match `^[a-z][a-z0-9_-]{1,30}$` (lowercase, starts with letter, 2–31 chars)
- Must not collide with common Unix commands (blocklist of `ls`, `cd`, `rm`, `cp`, `mv`, `cat`, `grep`, `find`, `git`, `npm`, `bun`, `node`, `claude`, `claudify`, `docker`, `systemctl`, etc.)
- Must not match an existing instance on this server

If validation fails, install aborts before touching state.

### 3e. Naming conventions

| Token | Pattern | Example |
|---|---|---|
| Instance name | `^[a-z][a-z0-9_-]{1,30}$` (post-blocklist) | `david`, `business`, `default` |
| Channel name | matches the plugin name | `telegram`, `discord`, `whatsapp` |
| MCP name | matches the plugin name | `gmail`, `calendar`, `drive` |
| systemd service | `claudify-<instance>.service` | `claudify-david.service` |
| Engine adapter | `lib/engines/<engine-id>.sh` | `lib/engines/claude-code.sh` |
| Personal command | matches instance name | `david` |

### 3f. Migration map — current state → target architecture

| Area | Today | Target | Action |
|---|---|---|---|
| `~/.claudify/` (single-instance) | flat — claudify.json at root | `instances/default/` nesting | Migration in install.sh — auto-detect old layout, move into `instances/default/` |
| systemd unit name | `claude-telegram.service` | `claudify-<instance>.service` | Renamed during migration; old unit removed |
| `lib/steps.sh` (~430 lines) | one big file | split into `onboarding.sh`, `configs.sh`, `service.sh`, `oauth.sh`, `manifest.sh` | Split as part of Phase 3.4 |
| `lib/engines/` | doesn't exist | one adapter, `claude-code.sh` | Created in 3.4; engine-specific code moves there |
| `src/` (TypeScript) | doesn't exist | structure for backup/restore | Skeleton in 3.4; populated in 3.5 |
| `tests/` | doesn't exist | bash + TS test dirs | Skeleton in 3.4 |
| `templates/access.json`, `templates/claude-telegram.service` | unused | deleted | Removed in 3.4 |
| Personal command wrapper | doesn't exist | `~/.local/bin/<name>` | Created in 3.4 |
| Manifest files | doesn't exist | `instances.json` + per-instance `claudify.json` | Created in 3.4 |

## 4. The 4 extension types

Every "thing the operator can add" maps to exactly one of these.

### 4a. Channels (how users reach the bot)

**State:** `~/.claudify/instances/<name>/channels/<channel>/`
**Examples:** Telegram (today), Discord, WhatsApp Business, email, SMS, web chat
**Mechanism:** Claude Code `--channels plugin:<name>@<marketplace>` flag in the systemd `ExecStart`
**Lifecycle:** Adding a channel ⇒ install its plugin via `claude plugin install`, write per-channel state to `channels/<name>/`, restart service. Uninstalling ⇒ reverse.

### 4b. MCPs (tools Claude can call)

**State:** `~/.claudify/instances/<name>/mcps/<mcp>/`
**Examples:** Gmail, Calendar, Drive, Outlook, Notion, Shopify, iCount (IL accounting)
**Mechanism:** `claude plugin install <name>@<source>` — MCP servers are spawned as subprocesses by claude-code on session start
**Lifecycle:** Install plugin → seed credentials (OAuth flow per MCP) → claude-code picks them up automatically

### 4c. Skills (custom commands)

**State:** `~/.claudify/instances/<name>/skills/<skill>/SKILL.md` + supporting files
**Examples:** `/draft-email`, `/schedule-meeting`, `/summarize`, `/customer-reply`
**Mechanism:** Claude Code auto-discovers skills under specific paths and exposes them as slash-commands; we point CC at our skills dir
**Lifecycle:** Drop a folder, claude-code picks it up next session. No service restart needed.

### 4d. Hooks (event-driven)

**State:** Configured in `~/.claude/settings.json` `hooks:` array; supporting files under `~/.claudify/instances/<name>/hooks/`
**Examples:** Audit log, cost tracker, profanity filter, dead-man switch
**Mechanism:** Claude Code's native hooks system fires on tool-use / message events
**Lifecycle:** settings-driven; we manage entries in `settings.json` per instance

## 5. The manifest

Two manifest files. Both are JSON. Both are read every time an
entrypoint runs.

### 5a. `~/.claudify/instances.json` — the registry

```json
{
  "version": 1,
  "instances": {
    "default": {
      "created_at": "2026-04-26T10:00:00Z",
      "engine": "claude-code",
      "service": "claudify-default",
      "personal_cmd": "default"
    },
    "business": {
      "created_at": "2026-04-26T15:00:00Z",
      "engine": "claude-code",
      "service": "claudify-business",
      "personal_cmd": "business"
    }
  }
}
```

`doctor.sh` (no `--name`) iterates this list and reports per-instance.
`update.sh` without `--name` defaults to all. `uninstall.sh` requires
explicit `--name <one>` or `--all`.

### 5b. `~/.claudify/instances/<name>/claudify.json` — the per-instance manifest

```json
{
  "version": 1,
  "name": "default",
  "created_at": "2026-04-26T10:00:00Z",
  "claudify_version": "0.1.0",
  "engine": "claude-code",
  "engine_version": "2.1.119",
  "channels": {
    "telegram": { "installed_at": "...", "enabled": true, "version": "0.0.6" }
  },
  "mcps": {},
  "skills": [],
  "hooks": []
}
```

`backup.sh` reads this to know what to bundle. `doctor.sh` reads it
to know what to check. `update.sh` reads it to know what's enabled.

## 6. Engine abstraction

Today there's one engine. The architecture supports more.

### The engine contract

Every engine adapter under `lib/engines/<id>.sh` implements **6
functions** with a fixed interface:

| Function | What it does |
|---|---|
| `engine_install` | Install / update the engine binary on the host |
| `engine_auth_check` | Returns 0 if currently authenticated |
| `engine_auth_setup` | Run interactive auth flow; persist credentials |
| `engine_run_args` | Echo the argv vector for `ExecStart` (channels, plugins, mode flags) |
| `engine_status` | Return JSON describing engine version + auth state |
| `engine_uninstall` | Remove engine-specific state from `~/.claudify/instances/<name>/` (does NOT remove the engine binary itself — operator-wide) |

`install.sh` and friends call these abstract functions. They never
reference `claude` or `claude-code` directly.

### Today's adapter: `lib/engines/claude-code.sh`

Wraps Claude Code CLI: `npm install -g @anthropic-ai/claude-code`,
`claude setup-token` capture, `claude --channels <plugin> --permission-mode bypassPermissions` for run args.

### When we'd add another adapter

Triggered explicitly — see ADR 0005 for the full criteria. Adding a
new engine means: write a new file under `lib/engines/`, implement
the 6 functions, update `install.sh --engine=<id>` to accept the new
ID. No other code changes.

## 7. Entrypoint responsibilities

| Script | What it does | What it doesn't |
|---|---|---|
| `install.sh` | Create / update an instance: preflight, deps, claude-code install, plugin install, configs, systemd unit, OAuth, persona, personal cmd, manifest entries | Doesn't read existing state for an unrelated instance; doesn't touch other instances |
| `update.sh` | In-place refresh of one instance — preserves all secrets and operator edits | Doesn't change instance name; doesn't add or remove extensions |
| `uninstall.sh` | Remove one named instance: stop service, rm unit, rm `~/.claudify/instances/<name>/`, rm personal command | Doesn't touch other instances; doesn't remove `~/.claude/`, Bun, npm-global |
| `doctor.sh` | Health-check one or all instances | Read-only — doesn't try to fix things |
| `backup.sh` | Tar one instance's state into `claudify-<name>-<host>-<ts>.tar.gz` | Doesn't include engine binaries or `~/.claude/` |
| `restore.sh` | Inverse of backup. Untar onto a fresh server, register instance | Doesn't merge with an existing instance of the same name (refuses) |

## 8. Test strategy

### Bash entrypoints
- **`tests/bash/`** — bats-core integration tests
- One test per entrypoint covering happy path + 1–2 failure modes
- Run inside an Ubuntu Docker container that simulates a fresh server (so we don't pollute the dev machine)
- `bash test.sh` at repo root runs the full bash suite

### TypeScript code (`src/`)
- **`tests/ts/`** — `bun test`
- Unit tests for `state.ts`, `manifest.ts`, etc. (pure-function-shaped)
- Integration tests for backup/restore round-trip
- `bun test` from `src/` runs the TS suite

### Live verification (manual)
- After a meaningful change: round-trip on Station11 — install → bot replies → doctor 28/28 → update → uninstall
- Capture summary in the PR / commit message
- Don't merge to `main` without this for changes that touch the install path

## 9. Extending Claudify (the contributor's hello-world)

### Add a new channel

1. Confirm the plugin exists at `claude-plugins-official` (or another marketplace)
2. Add a function to `lib/engines/<engine>.sh` that knows how to install it: `engine_channel_<name>_install <instance-dir>`
3. Add a step to `lib/onboarding.sh` that prompts for that channel's secrets (or detects them from env)
4. Add validation in `lib/validate.sh` for the new secret format
5. Add a doctor check for that channel in `doctor.sh`
6. Update README and CHANGELOG

### Add a new MCP

1. Find or build the MCP plugin
2. Add OAuth flow to `lib/engines/<engine>.sh` (or generic OAuth helper)
3. Test with `claude plugin install <mcp>` then make sure claude-code spawns it on next session
4. Update README / CHANGELOG

### Add a new skill

1. Drop a folder under `~/.claudify/instances/<name>/skills/<skill>/`
2. Include `SKILL.md` describing what it does
3. Optionally include scripts the skill references
4. Restart the service (or just send the bot a message — claude-code re-discovers skills on session)

### Add a new hook

1. Append an entry to `settings.json.hooks` for the right event (e.g., `pre_tool_use`)
2. Implement the hook script under `~/.claudify/instances/<name>/hooks/<hook>/`
3. Restart the service

## 10. Migration roadmap

### What's done (commits land at)
- Phase 1 + 2 (install, doctor, modular lib, public repo)
- Phase 3.1 (uninstall.sh)
- Phase 3.2 (update.sh + `--preserve-state`)
- Phase 3.3 (CLAUDE.md persona seed)

### What this architecture doc adds (Phase 3.4)
- Multi-instance layout (`instances/<name>/` nesting)
- Personal command per instance (`~/.local/bin/<name>`)
- Migration logic (single → multi)
- Manifest files (registry + per-instance)
- Engine abstraction layer (`lib/engines/claude-code.sh`)
- `lib/steps.sh` split into 5 focused modules
- `src/` skeleton for TypeScript
- `tests/` skeleton with one canary test per side
- Cleanup of unused `templates/*.{service,json}`

### Phase 3.5
- `backup.sh` + `restore.sh` (TypeScript via Bun)
- Round-trip tested

### Beyond Phase 3
- Phase 4 — Capabilities: Gmail / Calendar / Drive MCPs; Discord channel; richer skills library
- Phase 5 — Security & observability: cost ceiling, audit log, health endpoint, signed releases
- Phase 6+ — Multi-engine (Gemini / OpenAI) only when the trigger conditions in ADR 0005 hit

## 11. Security model

This section lists what we protect, how, and what we don't protect.

### 11a. Secrets

| Secret | Location | Protection |
|---|---|---|
| Bot token | `~/.claudify/instances/<name>/channels/telegram/.env` | chmod 600 |
| Engine OAuth | `~/.claudify/instances/<name>/credentials.env` | chmod 600 |
| MCP OAuth | `~/.claudify/instances/<name>/mcps/<mcp>/oauth.json` | chmod 600 |
| User allowlist | `…/channels/<ch>/access.json` | chmod 644 (not secret — IDs only) |

Universal rules:
- **Sed-redact** all secrets in any output we surface to the operator (`sk-ant-oat01-*`, bot tokens)
- **`EnvironmentFile=` only** in systemd units — `Environment=<key>=<value>` puts secrets in `ps`
- **Never pass secrets as argv** — `ps aux` is world-readable on most systems
- **`.gitignore`** locks out `.planning/LOCAL*` so accidentally-filled-in operator templates never commit

### 11b. Process isolation

- Service runs as the user, **never root**. Linger is the only sudo touch, and it's interactive at install time, not in the running service.
- `WorkingDirectory=%h/.claudify/instances/<name>/workspace`
- `PATH` in the unit is fixed, not inherited (`%h/.bun/bin:%h/.npm-global/bin:` + standard paths)
- No `CapabilityBoundingSet` granted

### 11c. Network

- **Outbound only.** Telegram long-poll + Anthropic API. Nothing inbound.
- HTTPS everywhere; no `--insecure` curl flags anywhere in our code
- No webhook endpoints — would require opening a port
- Cert verification is the system default; we never override

### 11d. Tool permissions

- Service runs with `--permission-mode bypassPermissions` by default
  → Claude can call any tool without prompting (see ADR 0005)
- Mitigated by **the channel allowlist** — only the configured user IDs can reach Claude. Compromise that account → full access.
- `permissions.allow` in `~/.claude/settings.json` redundantly auto-allows the four telegram plugin tools as a defense-in-depth fallback

### 11e. Input validation

- All operator inputs validated at install:
  - `BOT_TOKEN`: `^[0-9]+:[A-Za-z0-9_-]+$`
  - `TG_USER_ID`: `^[0-9]+$`
  - Instance name: `^[a-z][a-z0-9_-]{1,30}$` + blocklist
- Every variable expansion in bash is quoted (`"$var"`, `"${arr[@]}"`)
- No `eval` on operator input anywhere
- Path values anchored to `$CLAUDIFY_ROOT/instances/<name>/` — no traversal

### 11f. Supply chain

- `install.sh` fetched via `https://` only (curl exits non-zero on cert errors by default; we don't override)
- `dist/install.sh` is committed and reviewable line-by-line before piping to bash
- Dependencies (Bun, Claude Code, telegram plugin) installed from official sources
- **Phase 5 will add:** signed commits, signed releases, checksum verification on the install one-liner

### 11g. Multi-instance isolation

- Each instance has separate credentials, OAuth tokens, allowlists
- File permissions (chmod 600) prevent cross-instance reads even under the same user
- Separate systemd units → no shared process, no shared cwd
- Logs are per-instance directories

### 11h. Threat model — explicit list

**Protected against:**
- ✅ Random Telegram users messaging the bot (allowlist enforces)
- ✅ Eavesdropping in transit (HTTPS)
- ✅ Secrets in `ps` listings (EnvironmentFile, not Environment)
- ✅ Cross-instance leak (file perms + service boundaries)
- ✅ Accidental token-in-git (`.gitignore` for `LOCAL*`)
- ✅ Privilege escalation by the bot (runs as user, not root)

**NOT protected against (documented limits):**
- ❌ Compromise of the server-user account → full access
- ❌ Compromise of the operator's Telegram account → bot follows orders
- ❌ Cost runaway from a malicious / buggy prompt loop (no ceiling — Phase 5)
- ❌ Prompt injection from forwarded messages (CLAUDE.md persona advises Claude to refuse, but this is guidance, not enforcement)
- ❌ Insider with shell access on the server (any user with `sudo -u <bot-user>` can read state)
- ❌ Anthropic API compromise (out of our control)

### 11i. Operator action items

If you run Claudify in a context that needs harder boundaries than the
above:
1. Run on a dedicated VPS for this bot (no other users)
2. Use a low-permission Anthropic API key with a budget cap (Phase 5 will manage this)
3. Audit `~/.claudify/instances/<name>/logs/` regularly
4. Rotate bot token and Claude OAuth periodically
5. Disable bypassPermissions in `lib/engines/claude-code.sh`'s `engine_run_args` and accept the per-message-per-tool prompts (Phase 5 will offer a finer middle ground)

---

*This doc is the canonical "how Claudify is built" reference.
Contributors: change Claudify, change this doc — same commit. The
ADRs under `.planning/decisions/` capture *why* particular choices
were made; this doc captures *what* the system is right now.*
