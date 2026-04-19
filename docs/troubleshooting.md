# Troubleshooting

When the bot isn't responding or the install failed, start here.

## First step — always

Run the doctor:

```bash
bash <(curl -fsSL https://claudify.sh/doctor)
```

(Or, if you cloned the repo: `./doctor.sh`.)

It checks each component and tells you exactly what's broken and what
to do about it.

---

## Common issues

### The bot doesn't reply on Telegram

1. Check the service is running:
   ```bash
   systemctl --user status claude-telegram
   ```
2. Check the logs for errors:
   ```bash
   journalctl --user -u claude-telegram -n 50 --no-pager
   ```
3. Confirm your Telegram user ID is in the allowlist:
   ```bash
   cat ~/.claude/channels/telegram/access.json
   ```
   Your numeric ID (from @userinfobot) must appear in `allowFrom`.

### "linger is not enabled"

The installer needs `loginctl enable-linger` to be on for your user.
Run once on the server:

```bash
sudo loginctl enable-linger $USER
```

Then re-run the installer.

### Service starts but dies after a few seconds

Almost always Claude auth has expired or never completed. Re-run
`claude setup-token` in your shell, then:

```bash
systemctl --user restart claude-telegram
```

### "claude: command not found" inside the service

The service `PATH` may be missing where `claude` lives. Check:

```bash
which claude
systemctl --user show claude-telegram | grep PATH
```

The first path should be inside the second. If not, re-run the installer.

### `journalctl --user` says "No journal files were found"

Linger isn't enabled — see above.

### I revoked my bot token / want to use a different one

Edit `~/.claude/channels/telegram/.env`, change the value, then:

```bash
systemctl --user restart claude-telegram
```

### Two bots fighting over the same token

Telegram only allows one bot polling a token at a time. If you see
errors about "terminated by other getUpdates request," another instance
is running somewhere — your laptop, another server, or a stale process.
Stop the other one or revoke and re-issue the token via @BotFather.

---

## Still stuck?

Open an issue with:
- The output of `claudify doctor`
- The last 50 lines of `journalctl --user -u claude-telegram`
- The contents of `/tmp/claudify-install-*.log`
