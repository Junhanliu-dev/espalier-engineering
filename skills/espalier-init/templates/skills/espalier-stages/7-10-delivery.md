# /espalier — Stage 7–10 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 7–10
> starts (push, CI, doc drift, deploy, delivery). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 7: Stage the Convention Index

If this run appended an observation (Stage 4) or flipped a status
(Convention Promotion), stage the per-key files into the Stage 7 commit
alongside `espalier/changes/{type}/{slug}/*`:

```bash
[ -d espalier/conventions ] && git add espalier/conventions/
```

The per-key files are tracked; staging them here keeps the working tree
clean for the Stage 7 gate and never leaves an automation-written file
uncommitted. (The legacy `espalier/.conventions.tsv` is read-only to this
plugin version — it is never written, so there is nothing of it to stage.)

### Stage 7: What Is Still Uncommitted

The coder committed its units as it went (harness-coder.md → Commit
Discipline), so by Stage 7 the working tree holds at most two kinds of
uncommitted paths. Handle each by path — never `git add -A`, never one
"everything" commit, and never squash or rebase the coder's commits (the
pipeline pushes them as made; squash-merge is the pull request's policy and
the post-merge hook maps it back):

1. Code the coder left uncommitted (its report says `- Commits: none —
   {reason}`, or a parallel wave's parts were never committed): commit it
   as one commit per part / unit with the message the report carries
   (`- Commit:` line, or the coder's subject for the unit) — the
   orchestrator names it from the report, it does not invent scope.
2. The change's records (`espalier/changes/{type}/{slug}/`, plus
   `espalier/conventions/` when this run wrote there — staged above):
   one `chore(espalier): {slug} — pipeline records` commit. Completion adds
   its own `chore(espalier): close {slug}` afterwards.

Then push. The Stage 7 gate (clean tree, branch convention, pre-push hook,
certificate) is unchanged.

### Stage 7 Commit Recording

After `git push` at Stage 7 succeeds, record EVERY commit of the change —
`Base-Ref..HEAD`, oldest first, one row each — in the state file's Commits
table (the fix lane's reverse lookup blames a line to ONE commit, so every
commit must resolve to this change).

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
