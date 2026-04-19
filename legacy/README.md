# legacy/

Files preserved for historical reference. **Not maintained.** Don't run them.

## What's here

### `deploy.sh`
The original installer, written in the **operator-side SSH push** model:
the user ran `deploy.sh` on their laptop and it SSHed to a remote server
to install everything from outside.

This was retired on 2026-04-19 in favor of the standard self-hosted-tool
install pattern (`curl ... | bash` run on the target server itself).
See [ADR 0004](../.planning/decisions/0004-target-side-curl-install-not-operator-push.md)
for the full rationale.

The new installer is `install.sh` at the project root.

## Why keep this around?

- Reference for the bash patterns we used (heredocs, color helpers,
  prompt loops) when extracting them into `lib/` modules
- History — someone reading the repo can see how we got here
- Sanity check when implementing the new flow ("does the new install do
  X that the old one did?")

## When to delete

When `install.sh` reaches feature parity *and* a real user has run a
clean install end-to-end without consulting `deploy.sh`. Until then,
this stays.
