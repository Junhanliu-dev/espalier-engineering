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
   into fresh / aging / stale / critical / expired.
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
so a promotion decided there governs this run's coder. The weekly gardener
rota (see /espalier-prune's Multi-Developer Discipline) remains the default
owner of non-critical maintenance either way.

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
   "Resuming {requirement} from Stage {N}", continue from that stage (do NOT
   restart from 1).
3. Non-matching in-flight state files do NOT block a new requirement. Start
   the new change normally and surface ONE line: "Note: {N} other in-flight
   change(s): {slugs} — resume each with /espalier <its requirement>." (The
   push gate independently warns when several changes are in flight;
   finishing one before starting the next is the safe default.)
4. Invoked with no requirement text at all (bare `/espalier`, or `--resume`
   alone) → resume the single in-flight change; if several are in flight,
   list them and ask which one via `AskUserQuestion`.
5. Before creating a new folder, also scan
   `espalier/changes/feat/*/pipeline-state.md` for `Status: FILED` skeletons
   (root-cause feats filed by a fix lane's PARTIAL_FIX exit, or slices filed
   by a cleared `/espalier-map` handoff); if the new requirement's kebab tail
   OR its text mentions the skeleton's slug stem, ADOPT the skeleton folder
   instead of creating a new one (set its `- Status: IN_PROGRESS` and start
   from Stage 1 with its inherited `caused_by` / `filed_from_partial_fix` /
   `charted_from` + `tickets` frontmatter). A map-filed skeleton's
   requirements.md arrives part-grilled — its decided criteria carry ticket
   citations; Stage 1's grill covers only what the slice adds.

### Stage Execution Protocol

For each stage:
1. **Announce:** "## Stage N: {name}"
2. **Update state:** Write current stage to pipeline-state.md. Stage History
   timestamps use `date -u +%Y-%m-%dT%H:%M:%SZ` (full seconds — the stats
   duration report floors minute-only legacy rows). Bookkeeping steps with no
   agent in flight may batch into one bash invocation (state write + record
   append + context read) — same file effects, fewer round-trips.
3. **Load context:** Read the skill/agent file specified for this stage
4. **Execute:** Perform work or delegate to sub-agent
5. **Verify gate:** Check the quality gate
6. **Record:** Append result to pipeline-state.md
7. **Decision:**
   - PASS → advance to next stage (EXCEPT the Stage 2 → Stage 3 transition: the
     **Requirements Approval Gate** below must pass first — a Stage 2 PASS alone
     does NOT authorize coding)
   - FAIL → follow rollback path
   - HUMAN → pause and ask user (use AskUserQuestion tool)

### Requirements Approval Gate (BLOCKING — before Stage 3 Coding)

MANDATORY. Must NOT be skipped on a PASS. Stages 1 (requirements written +
grilled) and 2 (requirements review) finish WITHOUT writing any code. Do NOT
chain Stage 1 → 2 → 3 automatically — that is the bug this gate closes. After
Stage 2's gate passes (no P0/P1 reqs findings), HALT and get explicit user
sign-off on `requirements.md` before Stage 3.

1. Present a concise summary of the final `requirements.md`: the one-line goal,
   the acceptance criteria, and anything the Stage 1 grill resolved or marked
   out-of-scope.
2. Ask with `AskUserQuestion`:

   ```
   Requirements are written and reviewed. Nothing has been coded yet.
   Approve to start Stage 3 (Coding)?

   Options:
     1. Approve — proceed to coding.
     2. Edit    — tell me what to change; I revise requirements.md and re-ask.
     3. Abort   — stop here; leave requirements.md as a draft (Status: ABORTED).
   ```

3. In the SAME `AskUserQuestion` call, add a second question collecting the
   Stage 7 push authorization — so a run whose gates all pass later doesn't
   stall waiting for a human who has walked away:

   ```
   When Stage 7 (push) is reached and every gate passes, push to:
     1. {current branch} → {default remote}   (pre-authorize)
     2. Somewhere else — specify
     3. Ask me again at Stage 7
   ```

   Record the choice as `- Push-Target: {branch → remote | ASK}` in
   pipeline-state.md. Stage 7 then pushes a pre-authorized target without
   re-prompting — the programmatic gates (clean tree, branch convention,
   pre-push hook, certificate) still apply in full; only the redundant wait
   is removed. `ASK` or a missing line → prompt at Stage 7 as before. This
   pre-authorization NEVER extends to Stage 10 — delivery acceptance stays a
   human act.

3b. If Stage 0 recorded a `deferred-to-approval-gate` pre-flight summary,
   add a THIRD question to the SAME `AskUserQuestion` call:

   ```
   Pre-flight noted: {N} stale doc(s) ({tiers}), {M} convention promotion
   candidate(s), doctor {due|not due}.
     1. Handle after this change (default — gardener rota covers it)
     2. Pause & handle now — run /espalier-prune + convention decisions,
        then continue to Stage 3
     3. Ignore this run
   ```

   "Pause & handle now" runs the SAME mechanics as the Stage 0 prompt's
   "Handle now" (Convention Promotion's race guard, per-key status flip,
   isolated `docs:` commit) — relocated, not altered, and still before any
   code is written.

3c. ONLY when the discovered `## Deploy & Verification` section of
   `espalier/rules/development-process.md` is configured (it does NOT read
   "No deploy configuration discovered"), add a deploy question to the same
   call:

   ```
   When Stage 9 (deploy verify) is reached and CI is green, deploy with the
   discovered command to:
     1. {discovered target/environment}   (pre-authorize)
     2. Somewhere else — specify
     3. Ask me again at Stage 9
   ```

   Record `- Deploy-Target: {target | ASK}` in pipeline-state.md. Stage 9
   honors it (see pipeline.md Stage 9): a pre-authorized target deploys and
   health-checks without re-prompting; `ASK`/missing prompts at Stage 9 as
   today. The health-check gate, its rollback path, and the Stage 10 human
   acceptance are untouched — like the push pre-auth, this removes only the
   redundant wait, and it NEVER extends to Stage 10.

4. Advance to Stage 3 ONLY on **Approve**. On **Edit**, revise `requirements.md`
   per the feedback, re-run the Stage 2 gate, and re-present this gate. On
   **Abort**, write Status: ABORTED to pipeline-state.md and stop.

**Non-interactive exception:** auto-approve ONLY when the run is EXPLICITLY
unattended — `interactivity_mode` (in `drift-helpers.sh`) returns `unattended`,
i.e. one of `CI` / `ESPALIER_UNATTENDED` / `ESPALIER_LOOP` / `ESPALIER_HEADLESS`
is set. Do NOT key this off a bash TTY test: stdin has no TTY inside Claude Code
even when the user is present, so a TTY check would silently auto-approve every
interactive run — defeating the gate. If you (the orchestrator) can call
`AskUserQuestion`, you ARE interactive and MUST prompt. Only on a genuinely
headless run, record `requirements auto-approved (non-interactive)` in the Stage
History and proceed.

Record the outcome in pipeline-state.md Stage History (e.g.
`| 2 | PASSED | … | Requirements approved by user |`).

### Stage 3 Entry: Context Pack (assemble once — every spawn reuses it)

Immediately after the Requirements Approval Gate passes, write
`espalier/changes/{type}/{slug}/context-pack.md` (overwrite if resuming a
pre-Stage-3 crash; never rewrite it mid-loop — re-spawn rounds reuse it):

```markdown
# Context Pack: {slug}
- Requirement: espalier/changes/{type}/{slug}/requirements.md
- Layers touched: {layer list, from the task decomposition}
- Layer specs: espalier/skills/espalier-coding/specs/{layer}.md  (one line per touched layer)
- Rules: espalier/rules/coding-standards.md · engineering-structure.md · security-standards.md · production-standards.md
- Reference files: {1-2 existing files per touched layer that exemplify its conventions}
- Build: {build command} · Lint: {lint command} · Tests: {test command}
```

Derive the layer list and reference files ONCE (from the requirement +
`engineering-structure.md` + a quick glob of the touched layers) — this is
exactly the discovery the coder, both panel agents, and the test spawns
would otherwise EACH repeat from scratch. The pack lists PATHS AND FACTS
only — never conclusions, never verdicts, never "this part is fine": every
agent still reads the named files itself and trusts the current code over
the pack. Add the `CONTEXT PACK:` line to EVERY Stage 3-6 spawn prompt (the
prompt templates below carry it). A spawn that finds no pack (resumed old
change, fix lane before its pack step) falls back to its own discovery —
the pack is an accelerator, never a gate.

### Parallel Sub-Tasks (Stage 3)

When the task decomposition yields several sub-tasks, compare their planned
file sets. Sub-tasks are PARALLEL-SAFE only when the sets are pairwise
disjoint — counting any shared module both would edit (barrel files, route
tables, migration indexes, shared fixtures are overlap). Dispatch
parallel-safe sub-tasks as concurrent `harness-coder` spawns in ONE message,
with two extra lines in each prompt:

- `REPORT TARGET: espalier/changes/{type}/{slug}/coding-report.part-{n}.md`
  — parts, never `coding-report.md` directly.
- `PARALLEL DISPATCH: do NOT run the build / test / dependency-install
  commands — other coders share this working tree and concurrent runs
  corrupt each other. Write code only; the orchestrator runs the exit gate
  on the combined result.` (The coders' self-run build is a convenience
  check, not a gate — the orchestrator's Stage 3 exit gate is, and it still
  runs.)

After ALL return, concatenate the parts into `coding-report.md` in sub-task
order — KEEP the part files until the Stage 3 exit gate passes — and run the
exit gate ONCE on the combined tree. A failure attributable to one sub-task
re-spawns only that coder, again targeting ITS `coding-report.part-{n}.md`
(never `coding-report.md` — an overwrite there would erase the other
sub-tasks' reports that Stages 4-6 read); re-concatenate after the fix.
Unclear attribution → re-run the failing sub-tasks serially (serial
re-spawns may run the build themselves again). Only after the exit gate
passes, delete the part files. Any overlap or uncertainty → serial dispatch,
exactly as before. Parallelism changes DISPATCH only — the Stage 4 panel
always reviews the COMBINED diff, and the review/gate contract is untouched.

### Sub-Agent Delegation

Stages 3-6 use sub-agents for separation of concerns:

**Stage 3 (Coding):**
```
Agent tool:
  prompt: |
    You are the harness-coder.
    Read espalier/agents/harness-coder.md for your full instructions.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first; it names the layers/specs/rules/reference files (paths and facts
    only — verify against current code).
    REQUIREMENT: {paste requirement from Stage 1 output}
    TASK: {specific sub-task from decomposition}

    When done, write your coding report to:
    espalier/changes/{type}/{slug}/coding-report.md
```

**Stage 3 exit gate (PROGRAMMATIC — run before every panel spawn):** after the
coder returns (first pass AND every P0-fix re-spawn), re-run the discovered
build + lint commands yourself (they are in `espalier/rules/development-process.md`
/ the pre-push gate's substituted commands). Both must exit 0. Run them as two
concurrent background jobs in ONE bash call (`$BUILD & $LINT &` with per-pid
`wait`s to capture both exit codes, each job's output to its own temp file so
a failure's log isn't interleaved) — UNLESS the discovered commands plainly
depend on each other (e.g. a typecheck that consumes build output), in which
case keep them serial. Concurrency changes the wait, never the gate: both
still must exit 0. The coder's
self-reported "Build status: pass" is a claim, not the gate. On failure,
re-spawn the coder with the build/lint output — do NOT spawn the review panel
on unbuildable code (a wasted panel round), and do NOT count it as a P0 round.

**Stage 4 (Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer.
    Read espalier/agents/harness-reviewer.md for your full instructions.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the code you read).
    WHAT TO REVIEW: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what the coder did. Then read the actual files listed there.
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {fix's files from the
    latest coding-report.md}. Re-review in delta scope per your "Re-review
    Rounds" section.

    Write (OVERWRITE) your review to:
    espalier/changes/{type}/{slug}/review-record.md
    End the file with your VERDICT sentinel line.
```

**Stage 4 (Security Audit — runs as a panel with the review above):**
```
Agent tool:
  prompt: |
    You are the harness-security auditor.
    Read espalier/agents/harness-security.md for your full instructions.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the code you read).
    WHAT TO AUDIT: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what changed, then trace the touched endpoints. Assume the client is hostile.
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {fix's files from the
    latest coding-report.md}. If your own prior round was clean, run delta
    mode per your "Re-review Rounds" section.

    Write (OVERWRITE) your audit to:
    espalier/changes/{type}/{slug}/security-record.md
    End the file with your VERDICT sentinel line.
```

Stage 4 is a **review panel**: `harness-reviewer` (correctness / conventions /
production readiness, → review-record.md) and `harness-security` (trust boundary,
→ security-record.md) both run on the CURRENT diff. BOTH records are OVERWRITTEN
each round and end with a machine-greppable `VERDICT:` sentinel. Run this
procedure every round — it IS the gate, not a description. Do not advance to
Stage 5 by any other path:

1. **Baseline.** Note whether EACH of `review-record.md` and `security-record.md`
   exists, and its size/mtime. Spawn BOTH agents in ONE message (concurrent).
   On a re-review round, include the `CHANGED SINCE LAST REVIEW:` line in both
   prompts — the agents then review in delta scope (their "Re-review Rounds"
   sections; required reads = fix files + prior findings + direct dependents,
   expandable on any suspicion; security runs delta mode when its own prior
   round was clean). Both agents still return fresh current-round sentinels
   and still own the whole-change verdict.
2. **Completion check — BOTH files.** After both return, confirm EACH record was
   written THIS round: it exists, differs from its baseline, and its last
   `VERDICT:` line carries `round={n}` for the current round. A record that is
   missing, unchanged, or lacks a current-round sentinel means THAT agent did not
   complete — re-spawn that agent (once; a second failure → escalate to human).
   Never treat a missing or stale record as a pass.
3. **Gate read (deterministic).** From EACH record:
   `V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
   - `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT
     advance and do NOT re-spawn: snapshot the sentinel, then run the escalation
     protocol (fix lane: the late-escalation prompt; full lane: escalate to the
     human with the agent's Escalation Reason block). An `ESCALATION_REQUIRED`
     with `p0=0` is still an escalation.
   - Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
     with the combined findings and loop (counter + `max-code-rounds` cap
     unchanged).
   - Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
     `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.
4. **On a non-PASS round (verdict `FAIL`, or p0/p1 > 0) →** snapshot both
   sentinel lines into pipeline-state.md Stage History
   (`| 4 | ROUND {n} FAIL | {ts} | reviewer: FAIL p0=2 p1=0; security: PASS p0=0 p1=0 |`).
   Check the cap BEFORE re-spawning: if the counter already equals
   `max-code-rounds` (default 3, read from `espalier/.espalier-config` via
   `grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'`; fall
   back to 3 if the file or key is unset), escalate to the human immediately —
   the coder is NOT re-spawned and no further panel round runs. Before stopping,
   set `- Status: ESCALATED` and add a Stage History row
   `| 4 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
   Otherwise re-spawn `harness-coder` with the combined findings (a Stage 3
   action — its programmatic build/lint gate applies), increment the shared
   round counter, and return to step 1. After snapshotting a ROUND row, also
   update the `Review Rounds:` numerators in pipeline-state.md — a resumed
   session recounts rounds from this line plus the ROUND rows, never from
   memory.
5. **Only when both last sentinels are PASS/PASS_WITH_FIXES with p0=0 p1=0 on
   the current code →** snapshot the two sentinel lines into Stage History
   (`| 4 | PASSED | … |`), write the `Reviewed-Diff` certificate, THEN run the
   "Stage 4 Post-Review" drift processing below. The exit gate requires BOTH
   clean — never one agent's pass alone. A security P0/P1 shares the correctness
   `max-code-rounds` round counter.

**Stage 5 (Testing):**
```
Agent tool:
  prompt: |
    You are the harness-coder in testing mode.
    Read espalier/agents/harness-coder.md AND espalier/skills/espalier-testing/SKILL.md.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — verify against current code).
    WHAT TO TEST: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what was implemented. Write tests for those changes.

    ALSO read espalier/changes/{type}/{slug}/security-record.md (if present) — for
    EVERY field in its `## Security-Sensitive Fields` contract, write the negative
    abuse test it names (tamper the value → assert rejected → assert store unchanged). A
    contracted field with no such test will be blocked at Stage 6.

    Append test report to: espalier/changes/{type}/{slug}/coding-report.md
```

**Stage 6 (Test Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer reviewing tests.
    Read espalier/agents/harness-reviewer.md for your instructions.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the tests you read).
    WHAT TO REVIEW: The test files created in Stage 5.
    Read espalier/changes/{type}/{slug}/coding-report.md for the list.
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {the test files the
    Stage 5 fix re-spawn touched, from the latest coding-report.md}.
    Re-review in delta scope per your "Re-review Rounds" section.

    Check: Are tests meaningful? Do they cover edge cases?
    Do they match project testing patterns in espalier/skills/espalier-testing/SKILL.md?
    Security coverage: does EVERY field in espalier/changes/{type}/{slug}/security-record.md's
    `## Security-Sensitive Fields` contract have a passing abuse test
    (tamper → rejected → store unchanged)? A missing one is a P0 → back to Stage 5.
    Failure-mode coverage: does every NEW external-call path have a
    dependency-failure test (per espalier/rules/production-standards.md)?
    A missing one is a P1.

    Write (OVERWRITE) your review to: espalier/changes/{type}/{slug}/review-record.md
    End the file with your VERDICT sentinel line.
```

Stage 6 uses the same record semantics as Stage 4: freshness-check
review-record.md against its baseline, snapshot each round's sentinel into
Stage History. (Stage 4's final record is overwritten here — its verdicts live
in Stage History and the certificate.)

**Gate read (deterministic).** From EACH record:
`V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
- `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT advance
  and do NOT re-spawn: snapshot the sentinel, then run the escalation protocol
  (fix lane: the late-escalation prompt; full lane: escalate to the human with
  the agent's Escalation Reason block). An `ESCALATION_REQUIRED` with `p0=0` is
  still an escalation.
- Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
  with the combined findings and loop (counter + `max-test-rounds` cap
  unchanged).
- Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
  `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.

Stage 6's loop cap is `max-test-rounds`. Check the cap BEFORE re-spawning: if
the counter already equals `max-test-rounds`, escalate to the human
immediately — the coder is NOT re-spawned and no further panel round runs.
Before stopping, set `- Status: ESCALATED` and add a Stage History row
`| 6 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
Otherwise re-spawn, increment the counter, and loop. After snapshotting a
ROUND row, also update the `Review Rounds:` numerators in pipeline-state.md —
a resumed session recounts rounds from this line plus the ROUND rows, never
from memory.

### Stage 4 Post-Review: Drift & Convention Index

After Stage 4 PASSES (step 5 above — BOTH panel agents returned zero P0 and the
certificate is written), parse `review-record.md` for Convention Drift blocks (see
`harness-reviewer.md`) and flag the affected rule files. Do NOT run this on a P0
round: a malformed-drift P0 written back mid-loop would contaminate the next
round's P0 count.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug.

```bash
. espalier/hooks/drift-helpers.sh
REV="espalier/changes/${TYPE}/${SLUG}/review-record.md"
[ -f "$REV" ] || exit 0
SHA=$(git rev-parse HEAD)

python3 espalier/hooks/parse-drift-blocks.py "$REV" \
| while IFS=$'\t' read -r KIND RULE_FILE COUPLED; do
  case "$KIND" in
    DRIFT)
      mark_stale "$RULE_FILE" "$SHA" "convention drift flagged in ${TYPE}/${SLUG} review"
      LINE="convention_drift: $RULE_FILE"
      [ -n "$COUPLED" ] && LINE="$LINE (coupled_with: $COUPLED)"
      echo "$LINE" >> "espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"
      ;;
    MALFORMED)
      echo "convention_drift_malformed: $RULE_FILE (reviewer bundled blocks — drift NOT indexed)" \
        >> "espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"
      ;;
  esac
done
```

A `MALFORMED` line means the reviewer bundled unrelated drifts into one block.
Stage 4 has already PASSED when this parse runs, so there is no later round to
fix it in this change — do NOT write a fake P0 into review-record.md (it would
contaminate the Stage 6 gate read). Instead the malformed block is recorded in
pipeline-state.md and surfaced to the user in ONE line ("a Convention Drift
block was malformed and not indexed — the underlying drift will resurface via
the post-merge detector or the next review that sees it"). `coupled_with`
blocks resurface together at the next Stage 0 pre-flight (promote-together /
reject-together / split).

**Convention Observations → the convention index.** The reviewer also emits
lower-bar Convention Observations (see `harness-reviewer.md`) — one per
divergence, with NO aggregation key. The orchestrator assigns the key: a fresh
isolated reviewer cannot (three reviews of one pattern would coin three keys and
the count would never reach the threshold). For each Observation in
`review-record.md`:

1. Read existing keys: `. espalier/hooks/drift-helpers.sh && conv_fold | cut -f1`
   (folds the legacy file AND the per-key files — never parse them yourself).
2. Map the Observation's `description` to an existing `pattern_key`, or mint a
   new kebab-case key.
3. Append the row:

```bash
. espalier/hooks/drift-helpers.sh
append_convention "${TYPE}/${SLUG}" "$PATTERN_KEY" "$LOCATION"
```

`append_convention` sanitizes every field and de-dupes on
(change_slug, pattern_key, location), so re-running Stage 4 never inflates the
count. Convention state is tracked and row-append-only — columns
`date · change_slug · pattern_key · location · status` (+ optional 6th
`coupled_with`); `status` ∈ `diverges | promoted | rejected | exception`. When a
`pattern_key` reaches 3 deduped `diverges` observations (per `conv_fold`) it is
a promotion candidate, surfaced at the next Stage 0 pre-flight (see Convention
Promotion).

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

### Stage 7 Commit Recording

After `git push` at Stage 7 succeeds, capture the commit SHA + files changed and
append to the state file's Commits table.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug, set by
> the orchestrator at Stage Execution entry. Substitute them when running the snippet.

```bash
SHA=$(git rev-parse HEAD)
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | tr '\n' ',' | sed 's/,$//')
STATE="espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"

# Ensure section exists
if ! grep -q "^## Commits" "$STATE"; then
  cat >> "$STATE" << EOF

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
EOF
fi

# Idempotency: skip if this stage+SHA pair already recorded
if ! grep -qE "^\| 7 \| ${SHA} " "$STATE"; then
  echo "| 7 | $SHA | $FILES |" >> "$STATE"
fi

# Self-heal reverse-lookup cache (silently no-op if helpers absent)
[ -f espalier/hooks/lookup-helpers.sh ] && {
  . espalier/hooks/lookup-helpers.sh
  _cache_append "$SHA" "${TYPE}/${SLUG}" "original"
}
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

### Completion

When Stage 10 passes:
- Update pipeline-state.md with final status: COMPLETE
- Commit the espalier bookkeeping (`git add espalier/changes/{type}/{slug}
  && git commit -m 'chore(espalier): close {slug}'`) so the next change starts
  from a clean tree.
- Summarize: files changed, tests added, review findings addressed
- Report total rounds and rollbacks
- **Map-charted changes:** if this change's `requirements.md` frontmatter has
  `charted_from: maps/{map-slug}` — update that map's Spawned Changes row to
  COMPLETE. If EVERY row in the table is now COMPLETE, OFFER (AskUserQuestion
  — never auto-flip) setting the map's `status: CLEARED → BUILT`. On an
  unattended run, skip the offer and leave one line in the summary instead.
