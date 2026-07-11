---
name: espalier-ask
description: Answer a question about this codebase ("how does X work", "where is Y handled", "why is Z built this way", "what changed recently in X") read-only — from the espalier/ wiki, rules, and change history first, verified against code, falling back to codebase exploration. Never edits an artifact.
---

# Espalier Ask

A read-only question-answering lane. It answers "how / where / why / what-changed"
questions about the project by reading the Espalier docs FIRST (wiki, rules,
change history), verifying every doc claim against the actual code, and only
then falling back to a from-scratch codebase search.

It is NOT a pipeline. No stages, no gates, no human checkpoints, no
`changes/` folder, no `pipeline-state.md`. It never edits a wiki/rule/spec
file. Its only writes are append-only sidecar rows (drift flag + gap log),
described below.

## When to Use

- "/espalier-ask <question>"
- "How does <feature> work?" / "Where is <thing> handled?"
- "Why is <thing> built this way?" / "What changed recently in <area>?"

Do NOT use for:
- Implementing anything → `/espalier <requirement>` (feat/refactor) or
  `/espalier-fix <bug>`.
- Refreshing a stale doc → `/espalier-prune <path>` (the only thing that edits docs).
- A systematic drift scan → `/espalier-doctor`.

## Trigger

```
/espalier-ask <question>
```

No flags. Everything after `/espalier-ask` is the question text. Code
fallback is always on; sidecar writes are always on.

## Answer Procedure

### 1. Classify the question

| Type | Looks like |
|------|------------|
| `where` | "where is X", "which file handles Y" |
| `how` | "how does X work", "what's the flow for Y" |
| `why` | "why is X built this way", "why did we choose Y" |
| `what-changed` | "what changed in X recently", "when did Y land" |

A question may be more than one type — gather from every matching row.

### 2. Search the docs first

Read the primary sources for the question type before touching the codebase.
The wiki is `espalier/wiki/`; rules are `espalier/rules/`; history is
`espalier/changes/`.

| Type | Primary sources (read these first) | Secondary |
|------|-----------------------------------|-----------|
| where | `wiki/critical-paths.md`, `wiki/architecture.md`, `rules/engineering-structure.md` (file placement / layer layout) | codebase search |
| how | `wiki/architecture.md`, `wiki/data-models.md`, `wiki/external-services.md`, `rules/coding-standards.md` (conventions + invariants), layer specs in `skills/espalier-coding/specs/` | code read |
| why | `espalier/changes/*/*/requirements.md`, `espalier/changes/*/*/review-record.md`, `rules/*` | `git log` |
| what-changed | `changes/` (folders are `YYYY-MM-DD-<slug>` — sort to get chronology), `espalier/.commit-index.tsv` | `git log` |

`espalier/.commit-index.tsv` is gitignored and lazily built — it may not
exist. Do NOT fail on its absence: fall back to
`espalier/hooks/rebuild-commit-index.sh` (if present) or plain `git log`.

### 3. Verify before asserting

Docs are the map, code is the truth. Any behavior or location claim taken
from a doc MUST be confirmed by reading the cited file before it goes in the
answer. Never answer a behavior question from the wiki alone — the wiki can
be stale.

### 4. Fall back to code

If the docs are silent or insufficient, do a normal codebase search
(Grep/Glob/Read) and answer from the code.

### 5. Answer with sources

Every claim cites a doc path and/or a `file:line`. Make clear which part of
the answer came from a doc (verified) versus read directly from code.

### Degrade gracefully

Missing wiki files, missing `changes/`, or no `espalier/` directory at all →
skip the absent sources, answer from code, never crash. If there is no
`espalier/` directory, also skip ALL Byproduct Writes (the section below —
there is nowhere to write them).

## Byproduct Writes (append-only, notify-only)

These are the only writes this skill performs. Both are bash-3.2 safe and
TSV-sanitized. Skip both entirely when there is no `espalier/` directory.

### Drift found — a doc contradicted the code (step 3)

Flag the doc in the same sidecar the post-edit detector and `/espalier-doctor`
use. Do not edit the doc.

```bash
. espalier/hooks/drift-helpers.sh
mark_stale "espalier/wiki/<file>.md" "$(git rev-parse HEAD)" "ask-verify: <one-line mismatch>"
```

- The path argument is repo-root-relative — `mark_stale` guards on
  `[ -f "$_DS_ROOT/$file" ]` and silently no-ops if the path is wrong.
- `mark_stale` upserts: if the doctor already flagged this doc, the reason is
  overwritten but the write-once `stale_first_seen` is preserved. Acceptable.

Then surface ONE line in the answer:

> wiki/architecture.md looks stale here (doc says X, code does Y) — flagged;
> refresh with `/espalier-prune espalier/wiki/architecture.md`.

### Gap found — the docs had no coverage, you answered from code

Append one row to `espalier/.ask-gaps.tsv`:

```bash
# date<TAB>question<TAB>answered_from<TAB>suggested_doc — sanitize every field.
_sanitize() { printf '%s' "$1" | tr -d '\t\n\r'; }
printf '%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(_sanitize "<the question>")" \
  "$(_sanitize "<files/dirs the answer came from>")" \
  "$(_sanitize "<which wiki/rule file SHOULD cover this>")" \
  >> espalier/.ask-gaps.tsv
```

No dedup — the same question asked twice writes two rows, on purpose. Repeat
count is the demand signal a future `/espalier-prune` integration ranks by.

`espalier/.ask-gaps.tsv` is git-TRACKED (a doc backlog that should travel with
the repo, unlike the per-clone drift sidecars). A row written mid-pipeline
dirties the working tree, and pipeline Stage 7 gates on a clean tree — so when
you write a gap row, surface:

> wiki had no coverage for this — logged to `espalier/.ask-gaps.tsv`; commit it
> with your next change.

## What This Skill Does NOT Do

- Never edits a wiki, rule, spec, or any Espalier doc — refresh is
  `/espalier-prune` only.
- Never opens a `changes/` folder or writes `pipeline-state.md` — it is not a
  pipeline lane.
- Never blocks — it has no gates. The drift flag and gap log are notify-only.
- Does not replace `/espalier-doctor` (a systematic periodic scan); this only
  catches drift opportunistically, on a doc it happened to read for an answer.
