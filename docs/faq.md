# FAQ

### What does Claudify cost me?

Your **Claude subscription** (Pro or Max) and your **Linux server**.
Claudify itself is free and has no hosted component.

### Can I run more than one bot on the same server?

Not in v1. The installer assumes one Telegram bot per server. Future
multi-bot support is on the Phase 4 roadmap.

### Can I run Claudify on Windows or macOS?

The bot runs on a **Linux server**. You can SSH to it from Windows or
macOS — or anywhere with `ssh`. There is no Windows/Mac install path
because the bot needs `systemd`.

### Does Claudify need a public IP or a domain?

No. The bot polls Telegram outbound; nothing inbound is exposed.

### What happens to my data?

Everything stays on your server. Claudify writes to `~/.claude/` on your
machine. There is no Claudify-side telemetry, no analytics, no phone-home.

### How do I update Claudify?

Re-run the install one-liner. The installer is idempotent — it preserves
your configuration and updates only what changed. (A dedicated
`update.sh` is on the Phase 3 roadmap.)

### Can I use my Anthropic API key instead of my subscription?

No, by design. See [ADR 0003](../.planning/decisions/0003-oauth-not-apikey.md).

### How do I uninstall Claudify?

Until `uninstall.sh` ships in Phase 3, manual:

```bash
systemctl --user stop claude-telegram
systemctl --user disable claude-telegram
rm ~/.config/systemd/user/claude-telegram.service
rm -rf ~/.claude/channels/telegram
# (Leave ~/.claude/ alone if you want to keep memories/auth for other Claude Code use)
```

To revoke the bot token, message [@BotFather](https://t.me/BotFather)
and use `/revoke`.

### Who is Claudify for?

You, primarily — if you have a Claude subscription and a Linux server
and want a personal assistant reachable from your phone. It's not built
for teams, customers, or shared deployments.

### Why is it called "Claudify"?

Short, verb-shaped, easy to say in Hebrew and English, suggests
"turn this thing into a Claude." Reads naturally as
*"I claudified my VPS in two minutes."*

### Does Claudify work with other Claude tools?

It uses the official Claude Code CLI under the hood, so anything Claude
Code does — code editing, MCP servers, plugins — is available to your
bot. Claudify just sets it up and supervises it.
