---
name: espalier
description: Execute the Espalier development pipeline for a requirement
---

# Espalier Pipeline Runner

## When to Use
- "Implement this requirement using Espalier"
- "Run the full pipeline for this feature"
- "/espalier <requirement description>"

## Instructions

You are the pipeline orchestrator. For the given requirement, drive it through
all 10 stages defined in `espalier/pipeline.md`.

### Before Starting

1. Read `espalier/pipeline.md` for stage definitions
2. Check for existing state: look in `espalier/changes/` for a matching
   requirement (matching = the kebab-tail rule in Session Resumption below)
   - If found, read `pipeline-state.md` and RESUME from the current stage
   - If not found, create a new directory and start from Stage 1 — an
     unrelated in-flight change is surfaced, never silently resumed

### Flag Parsing

The invocation may carry flags BEFORE the requirement. Scan tokens from the start:
while a token looks like `--flag`, consume it; stop at the first token that does
not — everything from there on is the requirement text (so a `--word` inside the
requirement itself is never mistaken for a flag).

| Flag | Effect |
|------|--------|
| `--no-grill` | Set `GRILL_DISABLED=yes` — Stage 1 skips the requirement grill. |
| `--resume` | Recognized no-op. Resumption is already automatic (see Session Resumption); accept and drop the token. |

An unrecognized leading `--token` is NOT absorbed into the requirement — warn the
user (`unrecognized flag: --token; ignoring`) and drop it. Only the flags above are
recognized.

### Stage 0 Pre-Flight (drift + conventions + doctor)

Run this BEFORE Stage 1. Source the drift helpers:

```bash
. espalier/hooks/drift-helpers.sh
```

Gather all three signals BEFORE prompting:
1. **STALE** — `stale_files()` lists flagged files; `tier_counts()` buckets them
   into fresh / aging / stale / critical / expired. Beside it, information
   only: `contract_drift_lines` summed over `espalier/rules/*.md` (awk, no
   scout) — when the total N is above 0 the pre-flight line gains
   ` · drift=N` (lines carrying a SHA, date, PR number, shell command, or
   history phrase — the rules Writing Contract; `/espalier-doctor` reports
   them per file, `/espalier-prune` refreshes under its Removed-rules
   ledger). Never a prompt on its own.
2. **CONV** — `conv_fold` (in `drift-helpers.sh`) folds the legacy
   `espalier/.conventions.tsv` AND any `espalier/conventions/*.tsv` per-key
   files into `key<TAB>diverges_count<TAB>status` lines; every key with status
   `diverges` and `diverges_count` >= 3 is a promotion candidate. Do not parse
   the files yourself — the helper owns width tolerance, cross-source
   observation dedupe, and status precedence.
3. **DOCTOR** — `doctor_due()`. Skip if `/espalier-doctor` is not installed.

If all three are empty/false → no prompt, proceed to Stage 1. If only fresh
(<14d) stale docs and no conv/doctor signal → treat as empty.

**Critical/expired stale row present** (`tier_counts` shows critical or
expired > 0) → issue ONE blocking `AskUserQuestion` NOW, default
**"Handle now"** — the drift sidecar is per-clone, so a critical/expired row
here is YOUR OWN flag (the prune escape-hatch case):

```
Pre-flight found:
  - {N} stale doc(s): {tier breakdown}
  - {M} convention(s) over the promotion threshold
  - doctor scan due ({cadence})
Options:
  1. Handle now — run /espalier-prune + review conventions, then resume
  2. Proceed    — continue to Stage 1 with current docs
  3. Abort
```

**Only non-critical signals** → do NOT prompt here (this wait was the cost):
print ONE line (`pre-flight: {N} stale, {M} promotion candidate(s), doctor
{due|not due} — deferred to the approval gate`), append the same summary to
`espalier/.drift-report.md` with a `deferred-to-approval-gate ({ts})` marker
line (an interrupted run leaves an inspectable trace, and the signals
re-surface at the next invocation's pre-flight anyway — the sidecar is never
cleared by deferral), and continue to Stage 1. The Requirements Approval
Gate carries the maintenance question (its step 3b) — still BEFORE Stage 3,
so a promotion decided there governs this run's coder. The weekly
gardener rota (see /espalier-prune's Multi-Developer Discipline) remains
the default owner of non-critical maintenance either way.

**Unattended runs (never prompt here):** when `interactivity_mode` (in
`drift-helpers.sh`) returns `unattended`, do NOT issue the pre-flight
question. Write the three-signal summary to `espalier/.drift-report.md`,
print ONE line (`pre-flight: {N} stale, {M} promotion candidate(s), doctor
{due|not due} — recorded to espalier/.drift-report.md`), and continue to
Stage 1. Never prune, never promote, never run a doctor scan unattended.

### Convention Promotion

When the Stage 0 pre-flight reports a `pattern_key` with >= 3 deduped
`diverges` observations (from `conv_fold`) and the user picks "Handle now",
fetch the evidence rows with `conv_observations "$PATTERN_KEY"` (rows, not
counts — it folds the legacy file and the per-key files and dedupes across
both), run the race guard below, and surface the candidate with
`AskUserQuestion`:

```
Convention "{pattern_key}" has diverged in {N} changes:
  {change_slug : location, one per row}
Options:
  1. Promote   — bless the new pattern in the rule file, deprecate the old.
  2. Reject    — the new pattern is wrong; code should conform to the rule.
  3. Exception — sanction it under the rule's "## Exceptions" (a carve-out,
                 not a new default).
  4. Wait      — leave the rows; re-prompt at the next occurrence.
```

- **Promote** — the orchestrator edits the rule file DIRECTLY (not
  `/espalier-prune`: prune re-runs a scout, which re-derives the rule from a
  code base that is now a MIX of old + new and cannot make the decision). Then
  flip those rows' status `diverges` → `promoted`.
- **Reject** — flip those rows → `rejected`. The threshold counts only
  `diverges`, so a rejected pattern stops counting.
- **Exception** — append under the rule's "## Exceptions"; flip rows → `exception`.
- **Wait** — leave rows `diverges`.

Flip a row's status by editing the KEY'S FILE —
`espalier/conventions/k-$(conv_slug "$KEY").tsv` — change the 5th tab field
(`status`) of every matching row IN PLACE. That is safe here: the file is
small, single-concern, and ordinary 3-way merged; a concurrent same-key
decision on another branch surfaces as a visible git conflict in that ~5-line
file, which IS the race detection. **Never write the legacy
`espalier/.conventions.tsv`** — v0.17+ writers treat it as read-only. For a
pre-conversion key whose rows live only in the legacy file, record the
decision as ONE status row appended to the key's file (same columns; use the
deciding change's slug and the rule file as the location) — the legacy rows
stay untouched and `conv_fold`'s precedence rule (a key-file status beats any
legacy status) retires the candidacy. The edit is committed by the same
Stage 0 → Stage 7 run (the orchestrator stages `espalier/conventions/` at
Stage 7). `coupled_with` candidates are surfaced together — promote/reject
them as a set.

**Branch lane (multi-dev).** Deciding a promotion on your FEATURE BRANCH is
fine — make the rule edit + status flip their own isolated commit
(`docs: promote convention {pattern_key}`), never folded into a feature
commit, so it can be reviewed, cherry-picked, or reverted independently.
CODEOWNERS routes the rules-touching PR to the rule owner at merge either way
(advisory until "Require review from Code Owners" branch protection is on).

**Race guard (courtesy pre-check — run before the promotion prompt).** A
teammate may have already decided this key on the canonical branch:

```bash
. espalier/hooks/drift-helpers.sh   # for conv_slug
R=$(grep '^canonical-remote:' espalier/.espalier-config | awk '{print $2}')
B=$(grep '^canonical-branch:' espalier/.espalier-config | awk '{print $2}')
if git fetch --quiet "$R" "$B" 2>/dev/null; then
  DECIDED=no
  # Per-key file first — a single-file read via the same conv_slug the
  # writer uses; the legacy scan is only the pre-conversion fallback.
  git show "FETCH_HEAD:espalier/conventions/k-$(conv_slug "$KEY").tsv" 2>/dev/null \
    | awk -F'\t' -v k="$KEY" '(NF==5||NF==6) && $3==k && $5!="diverges" {found=1} END{exit !found}' \
    && DECIDED=yes
  if [ "$DECIDED" = no ]; then
    git show "FETCH_HEAD:espalier/.conventions.tsv" 2>/dev/null \
      | awk -F'\t' -v k="$KEY" '(NF==5||NF==6) && $3==k && $5!="diverges" {found=1} END{exit !found}' \
      && DECIDED=yes
  fi
  [ "$DECIDED" = yes ] && SKIP_PROMPT=yes   # surface the existing canon decision instead of prompting
else
  echo "WARN: cannot fetch $R/$B — race guard skipped"   # do NOT read a stale tracking ref
fi
```

(FETCH_HEAD, not `$R/$B` — a source-only fetch doesn't update the tracking
ref, and a fetch failure must SKIP the check rather than consult stale state.
The width guard keeps a malformed row from vacuously satisfying
`$5!="diverges"`.) The guard is a courtesy, not the race defense — two
same-key decisions on different branches surface as an ordinary git conflict
at merge, which is the structural detection.

### Session Resumption

On every invocation, check:
```
find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md
```

Resumption is scoped to THIS invocation's requirement — never hijack an
unrelated in-flight change into the new request:

1. Derive the invocation's `{kebab}` (State File Format below) and compare it
   against each state file's folder tail — the part after the `YYYY-MM-DD-`
   prefix — the same tail match the fix lane's collision check uses.
2. Resume is status-driven, not stage-driven: Resume any change whose
   `- Status:` is `IN_PROGRESS`, at whatever stage its `Current Stage:`
   records — including a crash mid-Stage-7/8/9/10. Statuses `COMPLETE`,
   `ABORTED`, `ABORTED_LATE`, `ESCALATED`, `ESCALATED_LATE` are terminal —
   never resumed. `PARTIAL_FIX` keeps its existing prompt ('Resume / extend'
   offer — see the fix lane's collision table). `FILED` skeletons are not
   resumed here; they are adopted by the FILED-skeleton scan (step 5 below).
   On a tail-matching `IN_PROGRESS` state file: read stage + history, announce
   "Resuming {requirement} from Stage {N}", append
   `| {N} | RESUMED | {ts} | fresh session |` to Stage History (the row that
   closes the gap — `espalier-stats.sh` books the time before it as human
   wait, never agent work), and continue from that stage (do NOT restart
   from 1).
3. Non-matching in-flight state files do NOT block a new requirement. Start
   the new change normally and surface ONE line: "Note: {N} other in-flight
   change(s): {slugs} — resume each with /espalier <its requirement>." (The
   push gate independently warns when several changes are in flight;
   finishing one before starting the next is the safe default.)
4. Invoked with no requirement text at all (bare `/espalier`, or `--resume`
   alone) → resume the single in-flight change; if several are in flight,
   list them and ask which one via `AskUserQuestion`.
5. Before creating a new folder, also scan
   `espalier/changes/feat/*/pipeline-state.md` AND
   `espalier/changes/refactor/*/pipeline-state.md` for `Status: FILED`
   skeletons (root-cause feats filed by a fix lane's PARTIAL_FIX exit,
   slices filed by a cleared `/espalier-map` handoff — a retirement map's
   slices carry `simplify_from` as well — or cuts filed by
   `/espalier-simplify` under `refactor/`); if the new requirement's kebab
   tail OR its text mentions the skeleton's slug stem, ADOPT the skeleton
   folder instead of creating a new one (set its `- Status: IN_PROGRESS` and
   start from Stage 1 with its inherited `caused_by` /
   `filed_from_partial_fix` / `charted_from` + `tickets` / `simplify_from` +
   `survey_commit` frontmatter). A map-filed skeleton's requirements.md
   arrives part-grilled — its decided criteria carry ticket citations;
   Stage 1's grill covers only what the slice adds. A simplify-filed
   skeleton arrives with its proof record and `## Retired Surface` list —
   the grill covers only what the record leaves open (accepting the stated
   consequence IS the product question; expect it to be asked).
   **Digest fold (adoption-time):** when the adopted skeleton's frontmatter
   names `charted_from: maps/{map-slug}` and
   `espalier/maps/{map-slug}/findings/` contains files, append to the
   adopted requirements.md a section titled
   `## Known failure patterns (from sibling slices)`
   holding the newest 12 P0/P1 finding lines (filename
   date order, newest files first; skip if the section already exists).
   Facts, never instructions: reviewers treat these as known hot spots —
   MORE scrutiny on those axes, never less; no check is ever skipped
   because of a digest line.

### Stage Execution Protocol

For each stage:
1. **Announce:** "## Stage N: {name}"
2. **Update state:** Write current stage to pipeline-state.md. Stage History
   timestamps use `date -u +%Y-%m-%dT%H:%M:%SZ` (full seconds — the stats
   duration report floors minute-only legacy rows). Bookkeeping steps with no
   agent in flight may batch into one bash invocation (state write + record
   append + context read) — same file effects, fewer round-trips.
3. **Load context:** read this stage's PROCEDURE file now — it is the most
   recent thing in your context when the stage starts — then the skill /
   agent file `espalier/pipeline.md` names for the stage:

   | Stage | Procedure: read `espalier/skills/espalier/stages/{file}` now, then run it |
   |-------|------------------------------------------------------------------------|
   | 1–2 | `stages/1-2-requirements.md` — Stage 1/2 loads, the Requirements Approval Gate (BLOCKING) with the push / deploy pre-authorization and the stage-boundary offer |
   | 3 | `stages/3-coding.md` — Stage 3 Entry: Context Pack, sub-task sizing and parallel dispatch, the coder spawn, the Stage 3 exit gate (the `- HANDOFF: true` sentinel → archive → `exit_gate` → continuation), the `test-mode` read |
   | 4 | `stages/4-panel.md` — the two-agent panel prompts and procedure (round ≥ 2 prompts carry `CHANGED SINCE LAST REVIEW:`; gate read: Advance ONLY when EVERY record's last sentinel is PASS/PASS_WITH_FIXES with p0=0 p1=0), the `FIX ROUND {n}:` re-spawn, the PASS write + certificate + stage-boundary offer, post-review drift and convention index |
   | 5–6 | `stages/5-6-contract.md` — Stage 5/6 (folded): the contract phase and delta review / test writing and test review (serial), the certificate, crash recovery |
   | 7–10 | `stages/7-10-delivery.md` — convention-index staging, commit recording, the PARTIAL_FIX reverse-link, the Stage 8.5 doc-drift check |

   This file ROUTES; the stage files carry the procedure verbatim and
   `espalier/pipeline.md` is the contract (trigger / load / gate / output /
   limit per stage). A maprun worker (stages 1–6) never loads
   `7-10-delivery.md`. Re-read a stage file only when the stage starts —
   never re-Read one already in your context.
4. **Execute:** Perform work or delegate to sub-agent
5. **Verify gate:** Check the quality gate
6. **Record:** Append result to pipeline-state.md
7. **Decision:**
   - PASS → advance to next stage (EXCEPT the Stage 2 → Stage 3 transition: the
     **Requirements Approval Gate** (`stages/1-2-requirements.md`) must pass
     first — a Stage 2 PASS alone does NOT authorize coding)
   - FAIL → follow rollback path
   - HUMAN → pause and ask user (use AskUserQuestion tool)

**Sequencing (HARD RULE, both modes):** never issue a bash that writes
coding-report.md or review-record.md in the same message as an agent spawn
that reads or writes that file. Bookkeeping bash runs with zero agents in
flight; every spawn above is alone in its message.

### State File Format

Parse `{type}` from the requirement prefix:
- `feat: <text>` → type = `feat`
- `fix: <text>` → type = `fix`
- `refactor: <text>` → type = `refactor`
- `docs: <text>` → type = `docs`
- Anything else → type = `feat` (default)

`fix:` on the FULL pipeline is for large fixes — >5 files, multiple layers, or
schema changes (the espalier-fix skill's own "Do NOT use for" list routes those
here). A typical single-bug fix belongs in `/espalier-fix`, which adds Stage 0
causal linking; when a `fix:` requirement looks that small, say so in one line
and suggest the fix lane before proceeding.

The same routing runs upward: a `feat:` that is really an EPIC — several
distinct features bundled, explicit multi-session scope, or a requirement so
foggy Stage 1's grill would blow its `full` tier without converging — belongs
in `/espalier-map` (multi-session planning; it hands back FILED slices this
lane then runs one at a time). Say so in one line and suggest the map lane
before proceeding. The split is session count, not project size: whatever
fits one session stays here.

Then derive `{kebab}` from the remainder of the requirement (kebab-case, max 80
chars — same truncation rule as the fix lane, so collision tail-matching agrees
across lanes; strip slashes).

**Date-prefix the slug** so change folders sort chronologically in a directory
listing:

```bash
DATE="$(date -u +%Y-%m-%d)"   # ISO date, UTC — lexical sort == chronological sort
SLUG="${DATE}-${kebab}"       # e.g. 2026-06-02-add-login-rate-limit
```

`{slug}` = `{YYYY-MM-DD}-{kebab}` everywhere below. The ISO date MUST be a
*prefix* (not a suffix) — only a leading `YYYY-MM-DD` makes lexical sort equal
chronological sort. Session Resumption (above) globs `pipeline-state.md` by path
and reads Status, so the date prefix never breaks resume. Reverse-lookup derives
its slug from the folder basename, so the dated slug flows through unchanged.

Create `espalier/changes/{type}/{slug}/pipeline-state.md`:

```markdown
# Pipeline State: {requirement title}

## Status
- Current Stage: {N}
- Started: {ISO timestamp}
- Last Updated: {ISO timestamp}
- Total Rollbacks: {count}
- Review Rounds: req={n}/{max-req-rounds}, code={n}/{max-code-rounds}, test={n}/{max-test-rounds}

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 1 | PASSED | 2025-01-15T10:00 | Requirements accepted |
| 2 | PASSED | 2025-01-15T10:05 | 1 round, no P0s |
| 3 | IN_PROGRESS | 2025-01-15T10:10 | |
```

When instantiating this from `_template`, substitute the Review-Rounds
denominators (`{max-req-rounds}`, `{max-code-rounds}`, `{max-test-rounds}`) from
`espalier/.espalier-config` — same read as the Stage 4 gate:
`grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'` (fall
back to 3 per key if the file or key is missing) — alongside the `{requirement}`
/ `{timestamp}` substitution. The denominators are the escalation limits as displayed.

### Rollback Protocol

When a gate fails:
1. Identify failure type from gate output
2. Look up rollback target in pipeline.md
3. Update pipeline-state.md (increment rollback counter, record failure)
4. If total rollbacks > `max-rollbacks` (default 3, read from
   `espalier/.espalier-config` via
   `grep '^max-rollbacks:' espalier/.espalier-config | grep -oE '[0-9]+'`; fall
   back to 3 if unset): STOP and ask human
5. Otherwise: announce rollback target and re-execute from that stage

### Human Checkpoints

At stages marked with human checkpoint in pipeline.md:
- Present a concise summary of what was done
- Use AskUserQuestion tool with options: Approve / Request Changes / Skip
- "Skip" only allowed for stages 9-10
- "Request Changes" triggers rollback with human's feedback as context

Stage-boundary resume offers — after Stage 2 approval and after the Stage 4
PASS (serial mode: after the Stage 6 PASS) — are `Continue here` /
`Continue in a fresh session`, asked once, first option default, never on an
unattended run. Nothing depends on the answer: the state is already on
disk and Session Resumption is unchanged; a fresh session runs Stages 7–10
with the change's state and the stage's procedure at the top of its context.

### Completion

When Stage 10 passes:
- Update pipeline-state.md with final status: COMPLETE
- **Map-charted changes** (requirements.md frontmatter has
  `charted_from: maps/{map-slug}`), BEFORE the bookkeeping commit:
  1. **Findings digest:** if Stage History recorded `ROUND {n} FAIL` rows,
     write their bracketed finding lines (one per line, P-severity prefix
     kept) to
     `espalier/maps/{map-slug}/findings/{YYYY-MM-DD}-{type}-{kebab}.md` —
     this change's own date/type/kebab; skip if the file already exists.
     One writer per file: merge-safe by construction.
  2. Update that map's Spawned Changes row to COMPLETE. If EVERY row is now
     COMPLETE, OFFER (AskUserQuestion — never auto-flip) setting the map's
     `status: CLEARED → BUILT`. On an unattended run, skip the offer and
     leave one line in the summary instead.
- **Simplification changes** (requirements.md frontmatter has
  `simplify_from:`), BEFORE the bookkeeping commit — flag the docs that
  still describe the retired surface (the post-merge detector keys off
  paths, so a doc naming a deleted function by name would otherwise stay
  green): for every identifier under requirements.md `## Retired Surface`,
  `grep -rlwF --` it (whole word; skip entries shorter than 4 characters
  — `id`, `run` — they would flag every doc) across `espalier/wiki/*.md`,
  `espalier/rules/*.md`, and `espalier/skills/espalier-coding/specs/*.md`
  (skip `wiki/simplify-survey.md` and `wiki/security-audit.md` —
  regenerated pages), and for each hit:
  `. espalier/hooks/drift-helpers.sh && mark_stale "<doc>" "$(git rev-parse HEAD)" "simplify: <name> retired in refactor/{slug}"`.
  Surface ONE line — `{N} doc(s) describe retired surface — flagged; refresh
  with /espalier-prune --all-stale (your own flags: prune's feature-branch
  escape hatch applies)` — and, when other `simplify_from` changes have
  completed since this one's `survey_commit`, add `run /espalier-doctor
  --since {survey_commit}`. Notify-only: never edit a doc here.
- Commit the espalier bookkeeping — a charted change stages its map dir in
  the SAME commit, so the digest + Spawned-Changes update ride with it:
  `git add espalier/changes/{type}/{slug}` (+ `git add espalier/maps/{map-slug}`
  when charted) `&& git commit -m 'chore(espalier): close {slug}'` — the
  next change starts from a clean tree.
- Summarize: files changed, tests added, review findings addressed
- Report total rounds and rollbacks
