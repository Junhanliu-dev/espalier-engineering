# /espalier — Stage 7–10 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 7–10
> starts (push, CI, doc drift, deploy, delivery). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 7: The Split — Code Branch, Espalier Branch

Stage 7 ends in TWO pull requests: the code branch carries every path outside
`espalier/`, a sibling branch carries all of `espalier/**`, and both are based
on the canonical branch. Everything below runs through
`espalier/hooks/espalier-pr.sh`, which holds the two invariants that make the
split safe. Read them once — they are not style:

- **The checkout never switches branches.** `espalier/` is live working state
  through Stage 10 (ci-result, doc-patches, the delivery brief and
  Completion's close are all still to come). Checking out the espalier branch takes those
  files out of the tree and the push gate then finds no in-flight change at
  all. The espalier branch is a PROJECTION, built in a temporary worktree and
  synced one-way. `espalier-pr.sh` refuses to run from it.
- **Both branches are pushed by refspec, from the code branch.**
  `pre-push-gate.sh` fingerprints the source diff against the CURRENT checkout;
  on an espalier-only branch that diff is empty, so the fingerprint is the
  empty-blob hash and can never match the certificate. `espalier-pr.sh push`
  pushes `<branch>:<branch>` with HEAD still on the code branch, so the gate
  checks what it was written to check. Never push the espalier branch by hand
  from a worktree, and never edit the gate.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug, set by
> the orchestrator at Stage Execution entry.

**1. Commit what the coder left.** The coder committed its units as it went
(harness-coder.md → Commit Discipline), so the only code that can still be
uncommitted is what its report flags (`- Commits: none — {reason}`, or a
parallel wave's parts). Commit it on the code branch, one commit per part /
unit, with the message the report carries (`- Commit:` line, or the coder's
subject) — the orchestrator names it from the report, it does not invent
scope. Never `git add -A`, never one "everything" commit, and never squash or
rebase the coder's commits (squash-merge is the pull request's policy and the
post-merge hook maps it back).

Commit it with an explicit pathspec — `git commit -- {paths}` — never a bare
`git commit`. `certificate_write` runs `git add -A`, so `espalier/` is already
staged by the time you get here and a bare commit absorbs it; a rollback that
re-enters Stage 3 puts a coder commit in exactly that position. `push` refuses
a code branch carrying `espalier/` paths, so getting this wrong stops the stage
instead of shipping a code PR full of pipeline records.

Do not stage `espalier/conventions/` here either — the projection in step 4
picks up what it is given under `espalier/`, tracked or new, and `git add`
honours `.gitignore` so the per-clone sidecars stay out.

**2. The doc sweep.** Spawn `harness-reviewer` with `WIKI SWEEP:` on the prompt
line; the procedure is `espalier/agents/modes/wiki-sweep.md`. It reads this
change's diff (`Base-Ref..HEAD`, `espalier/` excluded) against
`espalier/wiki/*.md` and `espalier/rules/*.md` and asks one question per doc:
does this diff make anything written here false? It re-derives nothing — that
is `/espalier-prune` — and it never deletes; a section the diff appears to
retire goes to `doc-patches.md` under `### Proposed Removals`.

Skip the spawn entirely when the diff touches no source file (tests only, docs
only, config only) and record `| 7 | SWEEP-SKIPPED | {ts} | no source files |`
in the Stage History.

The sweep appends its `### Wiki Sweep` verdicts and `### Proposed Removals` to
the change's `doc-patches.md`, edits the files in place, and stops. Committing
is step 4's job, one class per commit, so each is separately revertable on the
espalier PR. `delivery_brief` reads that block back for the Stage 10 brief's
`## Doc Refresh` (and `### Proposed Removals` for `## Proposed Doc Removals`),
so a sweep that records nothing leaves the human approving the change unaware
a doc moved.

**3. Record.** Before anything is projected, write the records Stage 7 owes:
the `## Commits` table (Stage 7 Commit Recording, below) and, when this feat
was filed from a partial fix, the reverse-link into that fix's state file
(Stage 7 Reverse-link, below). Order is the point: a record written after the
projection sits in this checkout and reaches no pull request.

```bash
. espalier/hooks/drift-helpers.sh && record_commits "$TYPE" "$SLUG"
# + the PARTIAL_FIX reverse-link write, when requirements.md carries
#   filed_from_partial_fix: (the first block of Stage 7 Reverse-link, below)
```

**4. Project and push.** One `project` call per commit class — records first,
then each class the sweep patched — then push both branches:

```bash
espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" project \
  "chore(espalier): $SLUG — pipeline records"
# the files the latest `### Wiki Sweep` block marked PATCH, one class per commit:
espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" project-sweep wiki
espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" project-sweep rules
# when step 3 wrote a PARTIAL_FIX reverse-link (see that section for the guard):
#   espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" project "chore(espalier): close the root-cause chain for ${FILED_FROM}" \
#     "espalier/changes/${FILED_FROM}/pipeline-state.md"
espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" push
```

`project` is a no-op when nothing changed, and `project-sweep` exits quietly
when the sweep patched nothing in that class, so an unpatched class costs a
line of output and nothing else.

Each call names WHAT it may commit and nothing else can enter — the default is
this change's own records plus `espalier/conventions/`, and `project-sweep`
names exactly the files its block marked PATCH, never the whole directory.
That scoping is not tidiness: the working tree can also hold another in-flight
change's records, migration `.bak` backups, and unrelated local edits under
`espalier/` — including in `wiki/` and `rules/` — and a whole-tree projection
would put all of them in THIS change's pull request.

`project` refuses a wiki or rule file that was deleted or lost more lines than
it gained — the sweep's never-delete rule, enforced rather than trusted. On
that refusal, restore the text, record the removal under `### Proposed
Removals`, and re-run the call.

**5. Open both PRs.**

```bash
espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" open
```

Both target the canonical branch — they are SIBLINGS, not a stack. GitHub
closes a child PR when its base branch is deleted rather than retargeting it,
and that close cannot be undone (the base of a closed PR cannot be changed and
it cannot be reopened without its base), so a stack would lose the espalier PR
of every change in any repo with `deleteBranchOnMerge`. Ordering is advisory
and lives in the espalier PR's body. `open` records both in the state file's
`## Pull Requests` table, then projects and pushes that table itself (`sync`)
so it reaches the espalier PR. It is idempotent — a re-run finds the open PRs
(or a merged one still at this branch's tip) instead of opening new ones.

**Re-entering Stage 7** (a Stage 8 rollback through Stage 3): run the same
steps again. The sweep appends a fresh `### Wiki Sweep` block and
`project-sweep` reads only the latest one; `record_commits` appends only the
new commits; `project`, `push` and `open` are idempotent. New commits go onto
the open PRs — never force-push, never open a second pair.

With no `gh`, or a `gh` with no usable account, `open` exits 5 with a warning
and the run continues: the branches are pushed and a human opens the PRs. The
pipeline NEVER blocks on the forge.

`open` finishes with a CI scan (`espalier-pr.sh {type} {slug} ci-scan`, also
runnable on its own). The espalier PR's diff is `espalier/**` and nothing else,
which breaks `pull_request` path filters in two opposite directions, so the
scan reports rather than prescribes:

- A workflow whose `paths:` excludes `espalier/` never runs on that PR. Fine on
  its own — a **deadlock** if any of its checks are required by branch
  protection, because a required check that never runs blocks the PR forever.
- A workflow with no path filter runs the full suite against a diff with no
  code in it. Mergeable, but it doubles CI per change.

The fix for one is the cause of the other, so the scan names which workflows
are in which bucket and the required checks it can read, and edits nothing.
Never blocking: a scan failure is reported and the run continues.

The Stage 7 gate is otherwise unchanged (branch convention, pre-push hook,
certificate) with one amendment: the working tree is clean OUTSIDE `espalier/`.
`espalier/` is expected dirty here — that is the projection's source.

### Stage 7 Commit Recording

Runs at step 3 — after step 1 has committed every code unit, so
`Base-Ref..HEAD` is final, and BEFORE the projection, so the table rides the
espalier PR. Record EVERY commit of the change — `Base-Ref..HEAD`, oldest
first, one row each — in the state file's Commits table (the fix lane's reverse
lookup blames a line to ONE commit, so every commit must resolve to this
change). A table written after the projection would merge without it.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug, set by
> the orchestrator at Stage Execution entry.

```bash
. espalier/hooks/drift-helpers.sh && record_commits "$TYPE" "$SLUG"
```

`record_commits` lists the change's commits (`git rev-list --reverse
Base-Ref..HEAD`; HEAD alone when no Base-Ref was recorded — a pre-v0.25
change resumed here), creates the `## Commits` table when absent, appends
one `| 7 | {sha} | {files} |` row per commit not already recorded, and
self-heals the reverse-lookup cache through `_cache_append` when
`lookup-helpers.sh` is installed. It prints the rows it added.

This commit-record is read at fix-time by `/espalier-fix` Stage 0 reverse lookup,
and used by the post-merge hook for squash-merge mapping.

Under the split it records the CODE branch's commits only, and that is on
purpose. The table's readers blame a source line to one commit, so code-only
rows make the `post-merge-backlink.sh` file-overlap match sharper than it was
when the records commit's `espalier/` paths sat in the same range. The espalier
branch's own commits are deliberately NOT recorded here: its squash carries
only `espalier/` paths, `_fuzzy_scan` finds no source-file overlap, and the
hook exits without writing — no row, rather than a wrong one. The espalier PR
is tracked by number in `## Pull Requests` instead.

### Stage 7 Reverse-link to PARTIAL_FIX (when applicable)

If this feat's `requirements.md` frontmatter has `filed_from_partial_fix: fix/{slug}`
(meaning it was filed as the root-cause for a partial fix), write back to the partial
fix's pipeline-state.md so the audit chain closes:

> Variables in scope: `TYPE` and `SLUG` are the active change's identifiers.

```bash
REQS="espalier/changes/${TYPE}/${SLUG}/requirements.md"
FILED_FROM=$(grep '^filed_from_partial_fix:' "$REQS" 2>/dev/null | awk '{print $2}')

if [ -n "$FILED_FROM" ]; then
  PARTIAL_STATE="espalier/changes/${FILED_FROM}/pipeline-state.md"
  if [ -f "$PARTIAL_STATE" ]; then
    # Update Root Cause Status line
    if [ "$(uname)" = "Darwin" ]; then
      sed -i '' 's|^- Root Cause Status:.*$|- Root Cause Status: COMPLETE (verified '"$(date -u +%Y-%m-%d)"')|' "$PARTIAL_STATE"
    else
      sed -i    's|^- Root Cause Status:.*$|- Root Cause Status: COMPLETE (verified '"$(date -u +%Y-%m-%d)"')|' "$PARTIAL_STATE"
    fi

    if ! grep -q "^## Root Cause Addressed By" "$PARTIAL_STATE"; then
      cat >> "$PARTIAL_STATE" << EOF

## Root Cause Addressed By
| Feat | Status | Date |
|------|--------|------|
EOF
    fi
    echo "| feat/${SLUG} | COMPLETE | $(date -u +%Y-%m-%d) |" >> "$PARTIAL_STATE"
  fi
fi
```

Runs at step 3, before the projection. This writes into ANOTHER change's
records, so — exactly as the fix lane's back-link — it must be projected or it
reaches no pull request. This feat caused the row, so the row rides THIS
change's espalier PR, and only when that file already exists on the espalier
branch (a partial fix still in flight has never merged; projecting it here
would add its whole state file and collide with its own PR). Run this at step
4, between the sweep projections and `push`:

```bash
ESP_BRANCH="${TYPE}/${SLUG}-espalier"
# `project` creates the branch on first use, so after the records projection it
# exists; testing an unset ref would read `:path` — the INDEX, where
# certificate_write's `git add -A` has staged everything — and always pass.
if [ -n "$FILED_FROM" ] && git cat-file -e "${ESP_BRANCH}:espalier/changes/${FILED_FROM}/pipeline-state.md" 2>/dev/null; then
  espalier/hooks/espalier-pr.sh "$TYPE" "$SLUG" project \
    "chore(espalier): close the root-cause chain for ${FILED_FROM}" \
    "espalier/changes/${FILED_FROM}/pipeline-state.md"
fi
```

### Stage 8.5 — Doc Drift Check (notify-only)

Runs as a sub-step between Stage 8 (CI verify) and Stage 9 (deploy). It edits no
doc, prompts nothing, blocks nothing — it only surfaces drift this run may have
caused. Because it is CI-independent (reads `.drift-state.tsv`, writes only
this change's `doc-patches.md`), it MAY ride the same message as Stage 8's
first CI watch call instead of waiting for CI to finish — see pipeline.md
Stage 8's wait protocol.

> "8.5" is a label, not a numeric stage. Do NOT write `Current Stage: 8.5` to
> pipeline-state.md — it would break `pre-push-gate.sh`'s integer stage parse.
> Record Stage 8.5 only in the Stage History notes.

```bash
. espalier/hooks/drift-helpers.sh && stage85_drift "$TYPE" "$SLUG"
```

`stage85_drift` reads `.drift-state.tsv`; with no flagged doc it prints
`Stage 8.5: no drift.`, otherwise it appends a `## Stage 8.5 Doc Drift
(notify-only)` table (file, tier, reason) to the change's `doc-patches.md`
and prints `Stage 8.5: {N} stale doc(s) — run /espalier-prune to refresh.
(Not blocking; pipeline continues.)`.

`doc-patches.md` is a per-change artifact created on demand under
`espalier/changes/{type}/{slug}/` — like `ci-result.md`. Advance to Stage 9
regardless of the result; refresh stays a deliberate `/espalier-prune`.

### Stage 10: Delivery Brief (assembled, never authored)

Before the Stage 10 checkpoint, write the brief the human reads instead of
a file list:

```bash
. espalier/hooks/drift-helpers.sh && delivery_brief "$TYPE" "$SLUG"
```

`delivery_brief` assembles `espalier/changes/{type}/{slug}/delivery-brief.md`
from what the change already recorded — the Requirement Summary and
acceptance criteria, `## References` and `## Open Questions` (the decisions
ratified at the gate and at any Stage 3 BLOCKED), the coding report's
`### Deviations` and `- Notes:` (what was deliberately not built), the
review and security verdict lines, the ROUND / HANDOFF / BLOCKED rows of the
Stage History, the `## Commits` rows, and the CI / deploy results when
present — sections copied, nothing paraphrased, nothing judged; a section
with no source is one `none` line. It prints the path and one count line
(`delivery brief: {n} deviations, {m} rounds, {k} commits`).

Present the brief at the Stage 10 checkpoint (`AskUserQuestion`: Approve /
Request Changes, as pipeline.md) — the reviewer of this change starts with
the same unknowns the requester had; the brief carries what settled them.
When the run is interactive, add ONE more question to the SAME call, first
option default:

```
Before you accept: quiz you on this change (five questions from the
brief — what changed, what deviated, what was left undone)?
  1. No — accept on the brief (default)
  2. Yes — ask me; I accept only after the answers
```

Option 2: ask the five questions ONE at a time from the brief's content
only (never from memory of the run), then re-present the Approve /
Request Changes choice. The quiz changes nothing in the change; it is the
human's check on their own understanding before a merge. Skipped on an
unattended run exactly as the checkpoint is.
