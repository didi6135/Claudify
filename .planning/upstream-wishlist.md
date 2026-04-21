# Upstream wishlist

Running log of features we want from the upstream Telegram channel
plugin ([`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official)).

Rationale for keeping this list separately rather than forking is in
[decisions/0005-upstream-plugin-bash-ts-layering.md](decisions/0005-upstream-plugin-bash-ts-layering.md).
If this list grows past ~5 concrete items upstream declines to accept,
that triggers the fork conversation.

Each entry: **what we want**, **why**, **urgency (hi/med/lo)**,
**upstream issue link once filed**.

---

## Active

### 1. Three-button permission UI (Deny / Allow once / Allow forever)

- **What:** When Claude Code wants to use a tool, the plugin currently
  posts a Telegram message with two inline-keyboard buttons: *Allow*
  (one-time) and *Deny*. Add a third: *Allow forever*. On press, the
  plugin writes the tool name (or a pattern) into `permissions.allow`
  in `~/.claude/settings.json` so future uses of that same tool don't
  prompt again.
- **Why:** For personal bots, per-message-per-tool approval is
  unworkable UX — three or four prompts per user message adds up fast.
  Operators end up disabling permissions entirely with
  `--permission-mode bypassPermissions`, which is blunt.
- **Urgency:** medium. We've routed around this with bypass mode; fine
  for now but limits granular safety.
- **Upstream issue:** *(not yet filed)*

---

## Backlog (lower priority, not filed upstream yet)

### 2. Webhook support as an alternative to polling

- **What:** Optional config to receive updates via Telegram webhook
  instead of long-poll `getUpdates`.
- **Why:** Lower resource use on servers that have a public HTTPS
  endpoint; simpler scaling for multi-bot.
- **Urgency:** low. Polling works fine for personal bots.

### 3. Multi-bot support in one plugin process

- **What:** Run multiple bot tokens from a single plugin instance,
  routing per-token to distinct Claude sessions.
- **Why:** Currently one plugin per bot (hence `TELEGRAM_STATE_DIR`
  parallel installs). For ~10+ bots that gets wasteful.
- **Urgency:** low. Personal-assistant-first project; not a priority.

---

## Closed / not pursued

*(none yet)*
