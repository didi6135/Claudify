# Claude Code + Telegram Bot — Server Deploy Kit

One command to deploy Claude Code as an always-on Telegram bot on a remote Linux server.

## What it does

1. Connects to your server over SSH
2. Installs Bun + Claude Code if missing
3. Installs the official `telegram` plugin
4. Writes your bot token + allowlist
5. Creates a `systemd --user` service that runs 24/7 with auto-restart
6. Pauses once so you can run `claude setup-token` (interactive OAuth)
7. Starts the service and verifies it's listening

## Prerequisites

### On your machine (the "operator")
- `bash` — any of: macOS Terminal, Linux, WSL, Git Bash on Windows
- `ssh`

### On the target server
- Linux with `systemd` (Ubuntu / Debian / Fedora / etc.)
- `node` + `npm` already installed (the script doesn't install Node itself)
- Lingering enabled for the user (`loginctl enable-linger <user>` — requires sudo one-time; script attempts it)
- SSH access with a key

### You also need
- A Telegram bot token from [@BotFather](https://t.me/BotFather)
- Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)
- A Claude subscription (Pro or Max) for the interactive `setup-token` step

## Usage

### One-shot, interactive

```bash
cd ~/Desktop/claude-telegram-deploy
./deploy.sh
```

The script prompts for everything it needs.

### Pre-filled via environment variables

```bash
SSH_HOST=1.2.3.4 \
SSH_PORT=22 \
SSH_USER=ubuntu \
SSH_KEY=~/.ssh/id_rsa \
WORKSPACE=claude-bot \
BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" \
TG_USER_ID=123456789 \
./deploy.sh
```

Any variable you don't set is prompted interactively.

## After deployment

The bot runs as `claude-telegram.service` under the user's systemd instance.

```bash
# Status
systemctl --user status claude-telegram

# Live logs
journalctl --user -u claude-telegram -f

# Stop / start / restart
systemctl --user stop claude-telegram
systemctl --user start claude-telegram
systemctl --user restart claude-telegram
```

## Gotchas

- **Only one bot per token.** If you run a bot with the same token on another machine (e.g. your laptop), they'll fight over polling. Stop one before using the other.
- **Token revocation.** If your token leaks, `/revoke` in BotFather and re-run the deploy.
- **Auth expires.** Claude auth tokens have limits — if the service fails months later, re-run `claude setup-token` on the server.
- **Single-bot design.** This kit assumes one bot per server. For multiple bots, set a distinct `TELEGRAM_STATE_DIR` per service — not implemented yet.
