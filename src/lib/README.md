# src/lib/ — TypeScript modules

Pure TypeScript modules consumed by future entrypoints (`backup.ts`,
`restore.ts`). Run via [Bun](https://bun.sh) — no transpile step,
strict mode, ESM only.

See `docs/architecture.md §3a` for where this fits in the repo layout
and `§8` for the test strategy.

## Rules

- ESM only (`"type": "module"`).
- Strict TypeScript (`tsconfig.json` extends `--strict`).
- One concern per file. ≤300 lines per file, ≤50 lines per function.
- No top-level side effects on import.
- Tests live under `tests/ts/`, not co-located.

## Current modules

_None yet._ Phase 3.5 introduces the first real modules
(`state.ts`, `manifest.ts`).
