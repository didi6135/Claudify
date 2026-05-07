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
| 3.4.1 | [Repo skeleton](3.4.1-skeleton.md) | ✅ done 2026-04-28 | ~30 min | — | all of 3.4 |
| 3.4.2 | [Split lib/steps.sh](3.4.2-split-steps.md) | ✅ done 2026-04-30 | ~1 hr | 3.4.1 | 3.4.3 |
| 3.4.2.1 | [Resume interrupted install](3.4.2.1-resume-install.md) | ✅ done 2026-05-04 | ~30 min | 3.4.2 | — |
| 3.4.3 | [Engine abstraction](3.4.3-engine-abstraction.md) | ✅ done 2026-05-04 | ~1.5 hr | 3.4.2 | 3.4.5 |
| 3.4.4 | [Manifest files](3.4.4-manifest.md) | ✅ done 2026-05-04 | ~1 hr | 3.4.2 | 3.4.5 |
| 3.4.5 | [Multi-instance layout](3.4.5-multi-instance.md) | ⏳ next | ~1.5 hr | 3.4.3, 3.4.4 | 3.4.5.1, 3.4.6, 3.4.7 |
| 3.4.5.1 | [Skill data dir + lib/memory.sh](3.4.5.1-skill-data-dir.md) | ⏳ pending | ~45 min | 3.4.5 | 3.4.5.2, Phase 4 |
| 3.4.5.2 | [Engine contract: memory_setup + apply_persona](3.4.5.2-engine-memory-contract.md) | ⏳ pending | ~30 min | 3.4.3 | Phase 4 (memory) |
| 3.4.6 | [Personal command wrapper](3.4.6-personal-cmd.md) | ⏳ pending | ~45 min | 3.4.5 | 3.4.8 |
| 3.4.7 | [Migration logic](3.4.7-migration.md) | ⏳ pending | ~30 min | 3.4.5 | 3.4.8 |
| 3.4.8 | [Docs sync after refactor](3.4.8-docs-sync.md) | ⏳ pending | ~30 min | 3.4.6, 3.4.7 | 3.5 |
| 3.5 | [backup.sh + restore.sh (TS)](3.5-backup-restore.md) | ⏳ pending | ~3-4 hrs | 3.4.8 | 3.6 |
| 3.6 | [Security hardening pass — umbrella](3.6-security.md) | ⏳ pending | ~2.75 hrs | 3.5 | — |
| 3.6.1 | [Tier-1 hardening (always-safe)](3.6.1-tier1-hardening.md) | ⏳ pending | ~30 min | 3.5 | 3.6.2 |
| 3.6.2 | [Filesystem write-restriction](3.6.2-fs-write-restriction.md) | ⏳ pending | ~45 min | 3.6.1 | 3.6.3 |
| 3.6.3 | [Address families + syscall filter](3.6.3-syscall-and-network.md) | ⏳ pending | ~30 min | 3.6.2 | — |
| 3.6.4 | [Tighten file permissions](3.6.4-file-permissions.md) | ⏳ pending | ~15 min | 3.5 | — |
| 3.6.5 | [doctor.sh security section](3.6.5-doctor-security-section.md) | ⏳ pending | ~30 min | 3.6.1, 3.6.2, 3.6.4 | — |
| 3.6.6 | [Security docs](3.6.6-security-docs.md) | ⏳ pending | ~15 min | 3.6.1, 3.6.2 | — |

**Total estimated effort:** ~12-15 hours across multiple sessions.

> **Inserted decimal tasks** (e.g. 3.4.2.1) are small, self-contained
> work that surfaces between numbered tasks. Used when a real UX gap
> shows up mid-phase and waiting for the next planned task would
> compound the friction. They get the same spec template as the
> numbered tasks.

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
