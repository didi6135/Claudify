# Prerequisites

Everything you need before running the Claudify installer.

## On the target server

- **A Linux server with systemd.** Tested on Ubuntu 24.04 LTS. Debian
  12+, Fedora 39+, and other systemd distros should work but aren't
  formally tested yet.
- **Node.js 20 or newer**, with `npm`. Check with `node --version`.
- **`util-linux`** (provides `/usr/bin/script`). Almost always
  preinstalled.
- **`curl`** to fetch the installer.
- **`sudo` access** for the user who will own the bot. Used **once**,
  during first install, to enable `loginctl linger`. Never again.
- **Open outbound HTTPS** to `npm`, `github.com`, and `api.telegram.org`.

## In your accounts

- **A Claude subscription** (Pro or Max). The installer pauses once for
  you to complete OAuth via `claude setup-token`.
- **A Telegram bot token**, created with [@BotFather](https://t.me/BotFather):
  1. `/newbot` → pick a name and a username ending in `bot`
  2. Copy the token BotFather gives you (`1234567890:ABC-...`)
- **Your numeric Telegram user ID**, from [@userinfobot](https://t.me/userinfobot):
  send any message and it replies with your ID.

## What you do NOT need

- A domain name
- A reverse proxy (nginx, Caddy)
- A database
- Docker
- Anything on your laptop other than an SSH client (the installer runs
  on the server, not on your laptop)
