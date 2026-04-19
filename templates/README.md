# templates/ — config files rendered at install time

Files in this folder are **templates**: they contain `${VARIABLE}`
placeholders that the installer fills in with real values (workspace
name, user ID, bot token, etc.) using `envsubst` before writing them to
the target locations on the server.

## Naming

Templates use a `.tpl` suffix (e.g. `claude-telegram.service.tpl`)
to make rendering explicit. The installer strips the suffix when
writing the rendered file.

## Current files

The two files presently in this folder (`access.json` and
`claude-telegram.service`) are concrete examples from the original
`deploy.sh` flow. They will be converted to `.tpl` form during Phase 1
task 1.B.8 (systemd service) and 1.B.7 (config writes).

Once converted, expected templates are:

- `claude-telegram.service.tpl` — systemd user unit, references
  `${WORKSPACE}` and standard `%h`-expanded paths
- `access.json.tpl` — Telegram channel allowlist, references
  `${TG_USER_ID}`
- `env.tpl` — `TELEGRAM_BOT_TOKEN=${BOT_TOKEN}`, written with `chmod 600`

## Not for ad-hoc rendering

These templates are rendered only by the installer's known code path.
Don't add files here that aren't consumed by the install flow.
