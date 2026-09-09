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
> the orchestrator at Stage Execution entry. Substitute them when running the snippet.

```bash
STATE="espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"
BASE_REF=$(grep '^Base-Ref:' "$STATE" | tail -1 | awk '{print $2}')
# Every commit of the change, oldest first; a missing Base-Ref (a pre-v0.25
# change resumed here) falls back to HEAD alone.
if [ -n "$BASE_REF" ]; then SHAS=$(git rev-list --reverse "${BASE_REF}..HEAD"); else SHAS=$(git rev-parse HEAD); fi

# Ensure section exists
if ! grep -q "^## Commits" "$STATE"; then
  cat >> "$STATE" << EOF

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
EOF
fi

[ -f espalier/hooks/lookup-helpers.sh ] && . espalier/hooks/lookup-helpers.sh
for SHA in $SHAS; do
  FILES=$(git diff-tree --no-commit-id --name-only -r "$SHA" | tr '\n' ',' | sed 's/,$//')
  # Idempotency: skip if this stage+SHA pair already recorded
  grep -qE "^\| 7 \| ${SHA} " "$STATE" || echo "| 7 | $SHA | $FILES |" >> "$STATE"
  # Self-heal reverse-lookup cache (silently no-op if helpers absent)
  type _cache_append >/dev/null 2>&1 && _cache_append "$SHA" "${TYPE}/${SLUG}" "original"
done
```

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
. espalier/hooks/drift-helpers.sh
STALE=$(stale_files)
PATCHES="espalier/changes/${TYPE}/${SLUG}/doc-patches.md"

if [ -z "$STALE" ]; then
  echo "Stage 8.5: no drift."
else
  {
    echo ""
    echo "## Stage 8.5 Doc Drift (notify-only)"
    echo "| File | Tier | Reason |"
    echo "|------|------|--------|"
    printf '%s\n' "$STALE" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      tier=$(classify_tier "$f")
      reason=$(awk -F'\t' -v x="$f" '$1==x {print $4; exit}' espalier/.drift-state.tsv)
      echo "| $f | $tier | $reason |"
    done
  } >> "$PATCHES"
  N=$(printf '%s\n' "$STALE" | grep -c .)
  echo "Stage 8.5: $N stale doc(s) — run /espalier-prune to refresh. (Not blocking; pipeline continues.)"
fi
```

`doc-patches.md` is a per-change artifact created on demand under
`espalier/changes/{type}/{slug}/` — like `ci-result.md`. Stage 8.5 touches no
rule/wiki/spec file, so it cannot dirty a project-level doc. Advance to Stage 9
regardless of the result. In-pipeline auto-apply is a v2 item — refresh stays a
deliberate `/espalier-prune`.
