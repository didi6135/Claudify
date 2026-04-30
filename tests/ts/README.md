# tests/ts/ — bun test suite

Unit + integration tests for the TypeScript modules under `src/lib/`.

## Convention

| File | Covers |
|---|---|
| `canary.test.ts` | sanity check — always passes |
| `<module>.test.ts` | one file per `src/lib/<module>.ts` |

## Running

```bash
cd src && bun test ../tests/ts/        # all
cd src && bun test ../tests/ts/canary  # one file by stem
bash test.sh                            # via the repo entry script
```

Missing `bun` is warn-skipped by `test.sh`, not failed.

Install Bun locally: `curl -fsSL https://bun.sh/install | bash`.
