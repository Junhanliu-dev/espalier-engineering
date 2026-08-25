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
| `--full` | every shipped scout prompt (also coding-patterns, unwritten-rules, per-layer specs) | ~8 min |
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
`doctor_due()` resets for THIS clone. When the scan runs in the weekly
maintenance lane, ALSO write the tracked shared stamp at session end —
`doctor_stamp_shared` under Multi-Developer Discipline below (clean/dirty
semantics; the end-of-session restamp rule applies). Write a timestamped human
summary to the gitignored `espalier/.drift-report.md`: artifacts scanned,
flagged, confirmed-current.

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

## Multi-Developer Discipline

On a multi-developer repo the doctor is a **scheduled singleton, not a
concurrent free-for-all**: run it as part of the weekly maintenance flow on
the canonical branch (`canonical-branch` in `espalier/.espalier-config`),
via the temporary-worktree flow described in `/espalier-prune`'s
Multi-Developer Discipline section — one scan per interval, one maintenance
PR carrying the scan's prune refreshes. Prune and promotion have their own
lanes (see that section's per-mechanism table); the doctor's lane is the
weekly maintenance PR only — a scan result stranded on a feature branch
helps nobody until merge.

**The shared stamp (tracked `espalier/.doctor-stamp`).** The doctor is the
stamp's ONLY writer. At the END of the maintenance session, write it and
commit it as its own commit in the weekly maintenance PR:

```bash
. espalier/hooks/drift-helpers.sh
N=$(stale_files | grep -c . || true)
if [ "$N" -eq 0 ]; then
  doctor_stamp_shared "$(git rev-parse HEAD)" clean
else
  doctor_stamp_shared "$(git rev-parse HEAD)" "dirty:$N"
fi
git add espalier/.doctor-stamp
git commit -m "docs: espalier doctor stamp ($( [ "$N" -eq 0 ] && echo clean || echo "dirty:$N" ))"
```

Semantics `doctor_due()` enforces team-wide: only a `clean` stamp satisfies
everyone; a `dirty:<N>` stamp satisfies ONLY this clone (via the local stamp
the doctor keeps writing) — a shared stamp must never mean "scan complete"
while the findings sit unrefreshed. **End-of-session rule:** the stamp records
the state at the end of the maintenance session, not the first scan — if the
same session's prune cleared every finding, RE-RUN the doctor (fast on a
now-clean tree) so the PR carries a `clean` stamp; otherwise a `dirty:N`
stamp whose findings were already fixed in the same PR would keep
`doctor_due()` firing team-wide forever. The file is ONE line, whole-file
last-writer-wins — never append, never union-merge it (no `.gitattributes`
entry may ever be added for it). Two doctors in one interval is a rota
failure; if their stamps conflict, the resolution is one line vs one line:
**keep the newer line** (or either `clean`).

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

## Scout Prompts (shipped file)

Read the prompts from `espalier/.scout-prompts.md` — they are NOT embedded here. The file is copied into this project at init. Spawn the scout(s)
mapped to each artifact in scope (Scout Mapping above); run each as an
Agent/Task scout against the current codebase. `/espalier-prune` reads the same
file, so the two can never drift apart.

For an artifact with two scouts (`coding-standards.md` ← 1.3 + 1.6), spawn both
and merge before the two-way diff.

## Config Advisories (report-only)

While writing the report, check one shipped-but-unused opt-in and, when it
applies, add ONE plain advisory line (the doctor has no severity levels and
this adds none):

- `hook-parallel-gates` absent from `espalier/.espalier-config` AND ≥ 3
  Stage-7 push rows recorded
  (`grep -hcE '^\| 7 \| ' espalier/changes/*/*/pipeline-state.md` summed) →
  report: `hook-parallel-gates not set — if build/lint/tests are
  independent, opting in saves ~40% per gated push (see docs). Opt in only
  when the three discovered commands are truly independent (the init-time
  question's caveat).`

Report-only: never write the key — discovery proposes, the human confirms.

## What This Skill Does NOT Do

- Does not edit any artifact — it only flags (`mark_stale`) and reports.
- Does not refresh — that is `/espalier-prune`.
- Does not run on an idle repo — `doctor_due()` is activity-gated.
