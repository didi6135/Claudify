# tests/bash/ — bats-core integration tests

One `.bats` file per entrypoint. Each test runs the entrypoint inside
an isolated environment (typically a Docker container that simulates
a fresh server) so it doesn't pollute the dev machine.

## Convention

| File | Covers |
|---|---|
| `canary.bats` | sanity check — always passes |
| `<entrypoint>.bats` | one file per top-level script |

Each `.bats` covers the happy path plus 1–2 failure modes per
`docs/architecture.md §8`.

## Running

```bash
bats tests/bash/canary.bats   # one file
bats tests/bash/              # all files
bash test.sh                  # via the repo entry script
```

Missing `bats` is warn-skipped by `test.sh`, not failed.

Install bats locally: `apt install bats` (Debian/Ubuntu) or see
[bats-core docs](https://bats-core.readthedocs.io).
