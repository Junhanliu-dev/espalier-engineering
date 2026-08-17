# Deferred Items

Things consciously punted from v0.2.0. Each has a documented rationale; revisit when the trigger condition (noted in each entry) materializes.

## Items deferred from v0.21.0

- **Fold interface-test writing into Stage 3; merge Stage 5/6 into the review panel.** The largest remaining per-run spawn saving (~2 cold starts + one fixpoint loop), but it restructures the stage contract: the security abuse-test contract only exists after Stage 4's panel passes, so test writing would split into interface-tests-with-code (Stage 3) and contract-driven abuse tests (post-panel). Design sketch in `docs/pipeline-speed-plan.md` → Deferred.
  - **Trigger to revisit**: `espalier-stats.sh` field data showing most runs pass Stage 4 in 1 round (i.e., remaining cost is spawn count, not round count).

## Items deferred (acceptable as-is for v0.2.0)

- **`harness-fix.md` "Before Starting" step 1** references `harness/pipeline.md` even though fix lane has its own stage overview (7 stages: 0–7, no Stage 2). Slightly redundant but not wrong — pipeline.md is the canonical Stage 3-7 contract.
  - **Trigger to revisit**: if users report confusion between fix-lane stages and full pipeline stages.

- **`_prompt_user_for_merge_decision`** in `lookup-helpers.sh` is a stub. The real prompt fires via the orchestrator's `AskUserQuestion` tool. The stub prints help text + does nothing in non-interactive mode. Comment in the helper clarifies.
  - **Trigger to revisit**: if a non-Claude consumer ever sources `lookup-helpers.sh` standalone.

- **`docs/plan.md` is committed at repo root** (~93KB / ~2270 lines). Currently linked from README. Could move under `docs/internal/` later if external readers find it noisy.
  - **Trigger to revisit**: if README signal/noise becomes a complaint.

## Items deferred from v0.11.0

- **Commit-index `_cache_append` non-atomicity + rebuild/append race** (`lookup-helpers.sh`, `rebuild-commit-index.sh`) — concurrent append vs rebuild can lose a row; needs a lock or temp-file swap.
- **Empty `OUT_SLUG[@]` expansion under bash 3.2 + `set -u`** (`lookup-helpers.sh` ~70-73) — an all-filtered dedupe would trip `unbound variable` on old bash.
- **`parse-drift-blocks.py` argv/IO error handling** — a missing/unreadable record path currently tracebacks instead of degrading.
- **Apostrophes in repo paths break bootstrap's `run "cp '…'"` quoting** — a path containing `'` splits the eval'd command.
- **Multi-line gate function bodies joined by newlines instead of `&&` fail open by convention** — needs an init-time validator that rejects a body whose steps don't propagate failure.
- **`eval/`-suite fixture for wrapper matching** — the deterministic test-hooks.sh wrapper matrix shipped in v0.11.0 (A6); only the LLM-judged eval variant is deferred.
- **test-bootstrap gaps** — spaces-in-path, `--force` re-run settings.json dedup assertion, invalid-JSON settings path, husky branch.

## Algorithm complexity upgrades (`_dedupe_entries_preserve_primary`)

Current implementation in `skills/harness-engineering/hook-templates/lookup-helpers.sh` is **Option A** (C-style nested loops, cached array accesses, ~30% faster than the original `seq`-based version). O(N²) worst case, ~25 ops at the Stage 0 fan-out cap of 5. Per-call cost well under 1ms.

Two upgrade paths exist if the fan-out cap is ever raised meaningfully:

### Option B — Two-pass O(N) with concat-string seen-set (bash 3.2 compatible)

True O(N) for typical inputs via string-glob `case` membership checks. Pays off only when cap > ~20.

```bash
_dedupe_entries_preserve_primary() {
  local -a OUT_SLUG=() OUT_SHA=() OUT_ROLE=() OUT_LOOKUP=()
  local i n=${#ENTRIES_SLUG[@]}
  local PRIMARY_SLUGS="|" SEEN_SLUGS="|"
  local slug role

  # Pass 1: collect slugs that have a primary entry
  for ((i = 0; i < n; i++)); do
    if [ "${ENTRIES_ROLE[$i]}" = "primary" ]; then
      PRIMARY_SLUGS="${PRIMARY_SLUGS}${ENTRIES_SLUG[$i]}|"
    fi
  done

  # Pass 2: keep at most one entry per slug, preferring primary
  for ((i = 0; i < n; i++)); do
    slug="${ENTRIES_SLUG[$i]}"
    role="${ENTRIES_ROLE[$i]}"

    case "$PRIMARY_SLUGS" in
      *"|${slug}|"*) [ "$role" != "primary" ] && continue ;;
    esac

    case "$SEEN_SLUGS" in
      *"|${slug}|"*) continue ;;
    esac

    SEEN_SLUGS="${SEEN_SLUGS}${slug}|"
    OUT_SLUG+=("$slug")
    OUT_SHA+=("${ENTRIES_SHA[$i]}")
    OUT_ROLE+=("$role")
    OUT_LOOKUP+=("${ENTRIES_LOOKUP[$i]}")
  done

  ENTRIES_SLUG=("${OUT_SLUG[@]}")
  ENTRIES_SHA=("${OUT_SHA[@]}")
  ENTRIES_ROLE=("${OUT_ROLE[@]}")
  ENTRIES_LOOKUP=("${OUT_LOOKUP[@]}")
}
```

- **Trade-off**: more lines, slight conceptual complexity. Substring search via `case` glob is implementation-fast (Boyer-Moore-like) for short slugs, so worst-case O(N²) is rarely hit.
- **Trigger to apply**: cap raised above ~20 entries, OR profiling shows dedupe cost > 5ms.

### Option C — Associative arrays (bash 4+)

Cleanest code, true O(1) per slug, but **breaks macOS default bash 3.2**. Would require shebang change to `#!/usr/bin/env bash` AND a documented runtime prerequisite.

```bash
_dedupe_entries_preserve_primary() {
  local -A best_idx
  local -a OUT_SLUG=() OUT_SHA=() OUT_ROLE=() OUT_LOOKUP=()
  local i slug role current

  for ((i = 0; i < ${#ENTRIES_SLUG[@]}; i++)); do
    slug="${ENTRIES_SLUG[$i]}"
    role="${ENTRIES_ROLE[$i]}"
    current="${best_idx[$slug]}"

    if [ -z "$current" ] || \
       { [ "$role" = "primary" ] && [ "${ENTRIES_ROLE[$current]}" = "call_path" ]; }; then
      best_idx[$slug]="$i"
    fi
  done

  for ((i = 0; i < ${#ENTRIES_SLUG[@]}; i++)); do
    slug="${ENTRIES_SLUG[$i]}"
    if [ "${best_idx[$slug]}" = "$i" ]; then
      OUT_SLUG+=("$slug")
      OUT_SHA+=("${ENTRIES_SHA[$i]}")
      OUT_ROLE+=("${ENTRIES_ROLE[$i]}")
      OUT_LOOKUP+=("${ENTRIES_LOOKUP[$i]}")
    fi
  done

  ENTRIES_SLUG=("${OUT_SLUG[@]}")
  ENTRIES_SHA=("${OUT_SHA[@]}")
  ENTRIES_ROLE=("${OUT_ROLE[@]}")
  ENTRIES_LOOKUP=("${OUT_LOOKUP[@]}")
}
```

- **Trigger to apply**: macOS default bash 3.2 support is dropped repo-wide (also affects `post-merge-backlink.sh` and others currently kept 3.2-compatible).

### Performance ladder summary

| | Current (A) | B (concat-set) | C (assoc-array) |
|---|---|---|---|
| Code clarity | baseline | -1 | +2 |
| Performance at cap=5 | baseline | +0.5ms | +0.5ms |
| Performance at N=100 | baseline | 50× faster | 100× faster |
| Bash 3.2 compat | ✓ | ✓ | ✗ |
| Risk to apply | n/a | low | medium (macOS) |
