# tests/ — test suites

Two suites, one per language. Both run from `bash test.sh` at the
repo root.

| Suite | Path | Runner | Covers |
|---|---|---|---|
| Bash | `tests/bash/` | [bats-core](https://github.com/bats-core/bats-core) | shell entrypoints (`install.sh`, `update.sh`, `doctor.sh`, …) |
| TypeScript | `tests/ts/` | `bun test` | modules under `src/lib/` |

## Running

```bash
bash test.sh                # runs both suites; skips a suite if its runner is missing
bats tests/bash/            # bash only
cd src && bun test ../tests/ts/   # TS only
```

`test.sh` exits non-zero if any suite fails. Missing runners are
warn-skipped (not failed) so a partial dev environment doesn't block
a contributor — CI will install both runners and run everything.

## Why two suites

`docs/architecture.md §8` explains the split: bash code gets
integration tests under bats (since most bash logic is hard to
unit-test), TypeScript code gets unit tests via `bun test`.

## Adding a test

- Bash: drop `<name>.bats` under `tests/bash/`.
- TS: drop `<name>.test.ts` under `tests/ts/`.

Each new entrypoint or module ships with a test in the same commit.
