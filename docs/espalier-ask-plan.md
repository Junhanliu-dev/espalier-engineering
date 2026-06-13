# /espalier-ask — Read-Only Q&A Lane

**Status:** draft for review (rev 3 — post second deep review)
**Target version:** v0.7.0 (minor — new skill, no breaking changes)

## Motivation

Users ask "how does X work", "where is Y", "why is Z built this way" — these
never enter the pipeline today, and plain Claude answers them by exploring the
codebase from scratch every time. Meanwhile every Espalier install carries a
wiki (`architecture.md`, `data-models.md`, `critical-paths.md`,
`external-services.md`), rules, and a `changes/` history that already hold
most of these answers, cheaper and with decision rationale code can't provide.

A Q&A lane makes that doc investment pay a second time, and produces two
free byproducts:

1. **Opportunistic drift detection** — answering a question forces verifying a
   wiki claim against code; a mismatch is exactly what `/espalier-doctor`
   scans for periodically, caught here at zero extra cost.
2. **Wiki-gap signal** — a question the docs can't answer (but code can) is
   the best evidence for what the wiki should cover next.

## What it is NOT

- Not a pipeline lane. No `pipeline-state.md`, no stages, no gates, no human
  checkpoints, no `changes/` folder created.
- Strictly read-only on Espalier artifacts: never edits wiki/rules/specs.
  Only appends to two sidecar files (drift state + gap log).
- Not a replacement for `/espalier-doctor` (periodic, systematic) or
  `/espalier-prune` (the only thing that refreshes docs).

## Skill Design

### Invocation

```
/espalier-ask <question>
```

The frontmatter `description` must carry trigger phrases so plain questions
route to the skill without the slash — e.g. "how does X work", "where is Y
handled", "why is Z built this way", "what changed recently in X". The
frontmatter `name:` MUST be `espalier-ask` (validation check 11 enforces
dir-name/frontmatter-name parity).

### Answer procedure (inside SKILL.md)

1. **Classify** the question: `where` (location), `how` (behavior/flow),
   `why` (rationale/history), `what-changed` (recent history).

2. **Docs-first search**, ordered by question type:

   | Type | Primary sources | Secondary |
   |------|----------------|-----------|
   | where | `wiki/critical-paths.md`, `wiki/architecture.md`, `rules/engineering-structure.md` (file placement/layer layout) | codebase search |
   | how | `wiki/architecture.md`, `wiki/data-models.md`, `wiki/external-services.md`, `rules/coding-standards.md` (discovery scouts 1.3 coding-patterns + 1.6 unwritten-rules feed this file — there is NO separate `rules/coding-patterns.md`), layer specs in `skills/espalier-coding/specs/` | code read |
   | why | `changes/*/requirements.md`, `changes/*/review-record.md`, `rules/*` | git log |
   | what-changed | `changes/` (date-prefixed dirs sort chronologically), `.commit-index.tsv` | git log |

   `.commit-index.tsv` is gitignored and lazily built — it may not exist.
   The skill must not fail on absence: fall back to
   `espalier/hooks/rebuild-commit-index.sh` (if present) or plain `git log`.

3. **Verify before asserting** — docs are the map, code is the truth. Any
   behavior/location claim taken from a doc MUST be confirmed by reading the
   cited file before it goes in the answer. Never answer behavior questions
   from wiki alone.

4. **Fallback** — docs silent or insufficient → normal codebase exploration
   (Grep/Glob/Read). Answer from code.

5. **Answer with sources** — every claim cites doc path and/or `file:line`.

Degrade gracefully: missing wiki files, missing `changes/`, or no
`espalier/` dir at all → skip the absent sources (and all sidecar writes if
`espalier/` is gone), answer from code, never crash.

### Byproduct writes (append-only, notify-only)

- **Drift found** (doc contradicted code in step 3) — exact call:

  ```bash
  . espalier/hooks/drift-helpers.sh
  mark_stale "espalier/wiki/<file>.md" "$(git rev-parse HEAD)" "ask-verify: <one-line mismatch>"
  ```

  Same sidecar (`.drift-state.tsv`) the post-edit detector and doctor write
  to. The path argument must be repo-root-relative (`mark_stale` guards
  `[ -f "$_DS_ROOT/$file" ]`). `mark_stale` upserts: re-flagging a doc the
  doctor already flagged overwrites the reason but preserves write-once
  `stale_first_seen` — acceptable. Surface one line in the answer:
  "wiki/architecture.md is stale here — flagged; refresh with /espalier-prune".
  Never edits the doc itself.

- **Gap found** (docs had no coverage; answered from code): append a row to
  `espalier/.ask-gaps.tsv` —
  `date<TAB>question<TAB>answered_from<TAB>suggested_doc`. Surface one line:
  "wiki had no coverage for this — logged as gap".

  No dedup: the same question asked twice writes two rows, deliberately —
  repeat count is the demand signal the deferred prune follow-up will rank by.

  **`.ask-gaps.tsv` is git-TRACKED** (decided at review) — it is a doc
  backlog, not clone state, so it travels with the repo and the whole team +
  future prune integration see accumulated gaps. This intentionally differs
  from the five drift sidecars (all gitignored, per-clone). Do NOT add it to
  the Stage 10 gitignore list.

  Tracked-file consequence: a gap row written mid-pipeline dirties the
  working tree, and pipeline Stage 7 gates on `git status` clean
  (`pipeline.md` Stage 7). Not a blocker — when a gap row is written, the
  skill's surfaced line must add "commit it with your next change", e.g.
  "wiki had no coverage for this — logged to espalier/.ask-gaps.tsv; commit
  it with your next change".

Both sidecars are TSV, sanitized with the same `tr -d '\t\n\r'` discipline as
`drift-helpers.sh`, bash-3.2 safe.

### Flags

None. Everything after `/espalier-ask` is the question text — no flag parsing.
Code fallback always on; drift/gap sidecar writes always on.

## Deliverables

### 1. New template (pure-copy)

`skills/espalier-init/templates/skills/espalier-ask.md`
— the SKILL.md per the design above. Frontmatter: `name: espalier-ask`,
description with the trigger phrases listed under Invocation.

### 2. `scripts/bootstrap-espalier.sh` — five edits

| Where | Edit |
|-------|------|
| Stage 2 (mkdir, ~line 238) | add `run "mkdir -p espalier/skills/espalier-ask"` |
| Stage 3 (cp) | add `run "cp '$PLUGIN_DIR/templates/skills/espalier-ask.md' espalier/skills/espalier-ask/SKILL.md"` |
| Stage 5 (symlinks, ~line 311) | add `espalier-ask` to the `for s in …` skill list |
| Stage 7 (CLAUDE.md heredoc, ~line 356-372) | add line: `**For questions** ("how does X work", "where is Y"), use \`/espalier-ask <question>\` — read-only, answers from espalier/ docs first.` |
| Stage 11 (validation) | new `run_check 29 "espalier-ask-skill" 'test -f .claude/skills/espalier-ask/SKILL.md'`; extend the `skills-load` ls list (check 2) |

**Validation count bump is NOT one line.** The total `28` is hardcoded in
~7 places and the deterministic-output cat globs must cover the new index:

- `:644` stage banner "validation (28 checks — R6)"
- `:662` / `:666` run_check echo `[$n/28]`
- `:674` / `:694` check 25's `[25/28]` lines
- `:751` / `:754` summary `$failed/28` + `28/28 passed`
- cat globs: `cat "$tmpdir"/2[0-4]` … `cat "$tmpdir"/2[6-8]` → extend to
  `2[6-9]` so check 29's result is emitted

All become 29. (Line numbers as of v0.6.0 — re-locate at implementation.)

Note: `.ask-gaps.tsv` is created lazily by the skill on first gap (like
`.conventions.tsv`); bootstrap does not pre-create it, and Stage 10
gitignore is NOT touched (file is tracked — see above).

### 3. `skills/espalier-init/SKILL.md` — two edits

- Tree diagram (~line 67-71): add
  `espalier-ask/SKILL.md  # read-only Q&A lane (slash: /espalier-ask)`
- Phase 3 description (~line 285): add `espalier-ask` to the pure-copy
  template list.

(The Phase 4 completion block lists no commands — verified, no edit there.)

### 3b. `skills/espalier-init/templates/agent.md` — one row

The agent.md lane table (lines 19-25) enumerates lanes (`Via /espalier`,
`Via /espalier-fix`). Add a row:

```
| Ask | espalier/skills/espalier-ask/ | Read-only Q&A over espalier/ docs | Via /espalier-ask |
```

`espalier/agent.md` is LLM-substituted per project, so existing installs
can't get this via `cp` — the migration sed-inserts the row after the Fix
row (precedent: the v0.5.3 patch migration already sed-appends to the
LLM-substituted `harness-coder.md`). Warn-only if the table was customized
beyond recognition.

### 4. `scripts/test-bootstrap.sh`

Add asserts following the espalier-prune/doctor pattern (~lines 142-150):

- `espalier-ask skill copied` — `[ -f '$TMP/espalier/skills/espalier-ask/SKILL.md' ]`
- `.claude/skills/espalier-ask link` — `[ -L '$TMP/.claude/skills/espalier-ask' ]`

Plus whatever the 28→29 validation bump touches in its expectations.

### 5. Migration: `scripts/migrate-v0.6-to-v0.7.sh`

Follow `migrate-v0.5-to-v0.6.sh` structure, with these specifics:

- **Preflight chain:** error if pre-v0.4 (`harness/` no `espalier/`); error if
  no `espalier/`; error if `.merge-hook-decision` missing; error if pre-v0.6
  (`espalier/skills/espalier-grill/SKILL.md` absent → run v0.5→v0.6 first).
- **Already-v0.7 detector:** `espalier/skills/espalier-ask/SKILL.md` present
  → "nothing to do", exit 0.
- **Plugin sanity check:** `$PLUGIN_INIT/templates/skills/espalier-ask.md`
  must exist, else "plugin is pre-v0.7, update first".
- **Backup-on-diff is REQUIRED, not optional.** `bootstrap --force` Stage 3
  unconditionally re-copies ALL pure-copy files (pipeline.md + every
  pipeline-skill SKILL.md), clobbering user customizations even for files
  unchanged in v0.7. Run `backup_if_differs` (same helper as the v0.6
  script) over the full pure-copy set — pipeline.md, espalier, espalier-fix,
  espalier-requirements, espalier-grill, espalier-prune, espalier-doctor —
  with suffix `.pre-v0.7.bak`.
- **CLAUDE.md patch:** bootstrap Stage 7 is append-once (skips when
  `## Espalier` exists), so migrated installs never receive the new
  `/espalier-ask` line from the heredoc. The migration inserts it directly:
  if CLAUDE.md has `## Espalier` and no `/espalier-ask` mention, sed-insert
  the question line after the `**For bug fixes**` line (use the existing
  `sed_inplace` BSD/GNU helper pattern). Skip silently if user removed the
  section.
- **agent.md patch:** same treatment — if `espalier/agent.md` has the lane
  table's Fix row and no `/espalier-ask` mention, sed-insert the Ask row
  after it (see 3b). Warn-only on no-match.
- Run `bootstrap-espalier.sh --force` with cached `--merge-decision` /
  `--doctor-cadence` (read from sidecars, as v0.6 script does).
- Verify: SKILL.md exists, symlink valid, CLAUDE.md line present (warn-only).
- `--dry-run` + `--yes` + `--plugin-dir=` flags, idempotent, same as v0.6.

### 6. `skills/espalier-migrate/SKILL.md`

- Extend the Step 1 auto-detect chain with the v0.6 → v0.7 step (detection:
  `espalier/skills/espalier-grill/SKILL.md` exists,
  `espalier/skills/espalier-ask/SKILL.md` absent) and the "which ones apply"
  combination matrix (a v0.5.3+ install now needs grill then ask; etc.).
- Update the frontmatter `description` migration list. NOTE pre-existing
  bug found at review: the description still ends at "the v0.5.3
  coder-agent patch" — it never gained v0.5→v0.6 even though the body did.
  Fix both versions while there.

### 7. Eval harness: `eval/ask/`

Model on `eval/grill/` (fixtures/, rubric.md, run.sh, README.md) — the v0.6
precedent for judgment-heavy skills. Fixture buckets:

- **classify** — questions with expected type (where/how/why/what-changed),
  including ambiguous ones.
- **docs-first** — fixture repo state where the answer IS in wiki/changes;
  pass = answer cites the doc + verifies against code, no full codebase
  crawl.
- **drift** — wiki deliberately contradicts code; pass = answer trusts code,
  calls `mark_stale` with `ask-verify:` reason, surfaces the prune line.
- **gap** — docs silent; pass = answers from code, appends well-formed
  `.ask-gaps.tsv` row, surfaces the commit line.
- **no-install** — no espalier/ dir; pass = degrades to plain code answer,
  no sidecar writes, no crash.

### 8. Release collateral (at ship time)

- `CHANGELOG.md` 0.7.0 entry (format per 0.6.0: bold-file bullets + closing
  non-breaking note).
- **README.md — more than a callout** (verified against current README):
  top callout (~line 11), structure-tree skills line (~line 36), a new
  `### /espalier-ask <question>` command section beside `/espalier-fix`
  (~line 65), maintenance paragraph mention (~line 73, gap-log sentence),
  token-cost table row (~line 218-220, weight: LIGHT), version history
  line (~line 253).
- `index.html` — command list + version callout (same as v0.6.0 commit).
- **`.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json`** —
  version bumps 0.6.0 → 0.7.0 (both files; missed by rev 2).
- **`docs/migrating-v0.6-to-v0.7.md`** — every prior migration ships a doc
  (`docs/migrating-v0.5-to-v0.6.md` etc.); CHANGELOG links it.
- No new wiki file, no rule changes, no hook changes, no sub-agent changes.

## Deferred (explicitly out of v1)

- **Gap log in Stage 0 pre-flight** — surfacing accumulated `.ask-gaps.tsv`
  rows alongside STALE/CONV/DOCTOR in the `/espalier` pre-flight prompt.
  Natural follow-up, but pre-flight already aggregates three signals; adding a
  fourth deserves its own look after gap data exists.
- **`/espalier-prune` consuming the gap log** — letting prune offer "write the
  missing wiki section" from gaps, ranked by repeat count. Depends on the
  same data.
- **Answer caching** — storing Q&A pairs for reuse. Unclear value, real
  staleness risk; skip.

## Effort

Moderate. One new template (~150 lines), five bootstrap edits (the
validation 28→29 bump fans out to ~9 lines), two espalier-init SKILL.md doc
edits + one agent.md template row, two test-bootstrap asserts, one migration
script cloned from the v0.6 pattern plus CLAUDE.md/agent.md sed-inserts, an
eval/ask harness (five fixture buckets), and the README/CHANGELOG/manifest/
migration-doc collateral. No hooks, no rules, no wiki changes, no sub-agent
changes.
