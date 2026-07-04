---
name: espalier-doctor
description: Periodically re-scout the codebase to catch Espalier-artifact drift that file-diff detection misses — silent refactors and pre-clone drift
---

# Espalier Doctor

A periodic deep check. Catches what the post-merge file-diff detector and the
reviewer cannot: silent refactors that change no file structure, and drift that
landed before this clone existed (the drift sidecar is per-clone).

The doctor only FLAGS — it writes sidecar rows and a report, it never edits a
doc. Refresh is always `/espalier-prune`.

## When to Use

- "/espalier-doctor" — run a drift scan now
- Surfaced by the Stage 0 pre-flight when `doctor_due()` is true
- A non-blocking reminder at `git push` time when a scan is overdue

## Trigger

```
/espalier-doctor [--quick | --full | --since <sha>]
```

| Mode | Scope | Cost |
|------|-------|------|
| `--quick` (default) | re-scout architecture, CI, data-models, critical-paths, external-services | ~3 min |
| `--full` | every embedded scout (also coding-patterns, unwritten-rules, per-layer specs) | ~8 min |
| `--since <sha>` | only re-scout layers with files touched since `<sha>` | varies |

## What It Does

```bash
. espalier/hooks/drift-helpers.sh
```

For each artifact in scope (see Scout Mapping):

1. Spawn the matching scout (prompts in `espalier/.scout-prompts.md`) against the CURRENT codebase.
2. Two-way diff the scout's proposed content vs the current artifact file.
3. If MATERIALLY different, flag it:
   ```bash
   mark_stale "<artifact>" "$(git rev-parse HEAD)" "doctor: scout drift"
   ```
   If the scout confirms the artifact is current AND it carries a stale row
   from an earlier false positive, retire that row:
   ```bash
   clear_stale "<artifact>"
   ```

On completion, stamp the run and write a report:

```bash
doctor_stamp "$(git rev-parse HEAD)"
```

`doctor_stamp` records the run in the gitignored `espalier/.doctor-last-run`, so
`doctor_due()` resets. Write a timestamped human summary to the gitignored
`espalier/.drift-report.md`: artifacts scanned, flagged, confirmed-current.

The doctor never edits an artifact. To apply a refresh, run `/espalier-prune`.

## Cadence

The cadence is chosen at `/espalier-init` (Phase 0 Q3) and stored in the tracked
`espalier/.doctor-cadence` (one line, e.g. `cadence: weekly`):

| `cadence:` | `doctor_due()` fires |
|-----------|----------------------|
| `every-change` | every Stage 0 pre-flight |
| `weekly` | first activity after 7 days |
| `monthly` | first activity after 30 days |
| `manual` | never automatically — only an explicit `/espalier-doctor` |

`doctor_due()` (in `drift-helpers.sh`) compares the tracked cadence against the
gitignored `espalier/.doctor-last-run` stamp. It is activity-gated — an idle
repo never triggers a scan (no commits = no drift). It is checked at the
`/espalier` and `/espalier-fix` Stage 0 pre-flights and as a non-blocking
reminder in `pre-push-gate.sh`. To change the cadence, edit `.doctor-cadence`
directly — bootstrap writes it once and never auto-rewrites it.

## Scout Mapping

| Artifact | Scout | In `--quick`? |
|----------|-------|---------------|
| `rules/engineering-structure.md` + `wiki/architecture.md` | 1.2 | yes |
| `rules/development-process.md` | 1.5 | yes |
| `wiki/data-models.md` | 1.8 | yes |
| `wiki/critical-paths.md` | 1.9 | yes |
| `wiki/external-services.md` | 1.10 | yes |
| `rules/coding-standards.md` | 1.3 + 1.6 (merge before diff) | `--full` only |
| `rules/security-standards.md` | 1.11 — discovered sections only (see espalier-prune's fixed-vs-discovered note) | `--full` only |
| `rules/production-standards.md` | 1.3 + 1.10 + 1.8 — `{discovered}` cells only (merge before diff) | `--full` only |
| `skills/espalier-coding/specs/{layer}.md` | per-layer spec scout | `--full` only |

## Embedded Scout Prompts

The scout prompts live in ONE shipped file — `espalier/.scout-prompts.md` (copied
into this project at init). Read it and spawn the scout(s) mapped to each artifact
in scope (Scout Mapping above); run each as an Agent/Task scout against the current
codebase. `/espalier-prune` reads the same file, so the two can never drift apart.

For an artifact with two scouts (`coding-standards.md` ← 1.3 + 1.6), spawn both
and merge before the two-way diff.

## What This Skill Does NOT Do

- Does not edit any artifact — it only flags (`mark_stale`) and reports.
- Does not refresh — that is `/espalier-prune`.
- Does not run on an idle repo — `doctor_due()` is activity-gated.
