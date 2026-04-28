# Phase 3 — Task index

Each file in this directory is a self-contained, executable task spec
for one piece of Phase 3 work. The phase overview lives in
[`../phase-3-lifecycle.md`](../phase-3-lifecycle.md). The architectural
reasoning behind every decision lives in [`../../../docs/architecture.md`](../../../docs/architecture.md).

**Rule:** before starting any task, read its file end-to-end. Each one
specifies *exactly* which files change, what each step is, and how to
verify done.

## Status board

| Task | Title | Status | Estimated | Depends on | Blocks |
|---|---|---|---|---|---|
| 3.4.1 | [Repo skeleton](3.4.1-skeleton.md) | ⏳ next | ~30 min | — | all of 3.4 |
| 3.4.2 | [Split lib/steps.sh](3.4.2-split-steps.md) | ⏳ pending | ~1 hr | 3.4.1 | 3.4.3 |
| 3.4.3 | [Engine abstraction](3.4.3-engine-abstraction.md) | ⏳ pending | ~1.5 hr | 3.4.2 | 3.4.5 |
| 3.4.4 | [Manifest files](3.4.4-manifest.md) | ⏳ pending | ~1 hr | 3.4.2 | 3.4.5 |
| 3.4.5 | [Multi-instance layout](3.4.5-multi-instance.md) | ⏳ pending | ~1.5 hr | 3.4.3, 3.4.4 | 3.4.6, 3.4.7 |
| 3.4.6 | [Personal command wrapper](3.4.6-personal-cmd.md) | ⏳ pending | ~45 min | 3.4.5 | 3.4.8 |
| 3.4.7 | [Migration logic](3.4.7-migration.md) | ⏳ pending | ~30 min | 3.4.5 | 3.4.8 |
| 3.4.8 | [Docs sync after refactor](3.4.8-docs-sync.md) | ⏳ pending | ~30 min | 3.4.6, 3.4.7 | 3.5 |
| 3.5 | [backup.sh + restore.sh (TS)](3.5-backup-restore.md) | ⏳ pending | ~3-4 hrs | 3.4.8 | 3.6 |
| 3.6 | [Security hardening pass](3.6-security.md) | ⏳ pending | ~1-2 hrs | 3.5 | — |

**Total estimated effort:** ~12-15 hours across multiple sessions.

## Task file template

Every task file follows the same shape so a reader can scan in 10 seconds:

```markdown
# Task X.Y.Z — Title

**Status:** pending / in-progress / done
**Estimated effort:** N hours
**Depends on:** prior tasks
**Blocks:** later tasks

## Goal
One-sentence success state.

## Why
Why this task exists now. Link to architecture.md / ADR.

## Scope
### Files to create
### Files to modify
### Files to delete

## Steps
Ordered, atomic actions.

## Acceptance criteria
Verifiable checkboxes.

## Test plan
How to verify it works (Station11 round-trip, syntax checks, etc.).

## Out of scope
What we deliberately don't touch in this task.

## Notes / risks
```

When a task is done: status flipped to `✅ done` + completion date in
the header, plus `## Outcome` appended at the bottom (1-2 paragraphs
on what was delivered, any deviations, follow-up work spawned).
