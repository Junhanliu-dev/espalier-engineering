# Pipeline Speed Plan v2 (v0.22.0)

> **Status:** IMPLEMENTED on branch `feat/v0.22-pipeline-speed`
> (2026-08-18) — all eight tracks, migration #30, migrate-skill chain,
> version bumps, changelog; suites green (bootstrap 270/270, hooks
> 159/159). Remaining before release: eval re-runs (§12.3), manual smoke
> (§12.4), merge + tag.
> Revised after a two-agent fresh-eyes review (an adversarial contract
> check + an independent opportunity scout): Track B redesigned around
> quarantine-on-FAIL, dispatch-sequencing races removed, fix-lane Stage 5
> machinery restored, Track A parsing hardened, and Tracks F–H added.
> Grilled with the owner 2026-08-18 — every §15 question resolved (see
> §15): one v0.22.0 release carrying all eight tracks; speculation ON by
> default in both lanes. Owner's field profile: interactive feats,
> fix-lane bugs, AND maprun headless batches are all real usage — every
> track retained, F/G conditional per repo (CI/deploy vary), and Track
> A's unattended-correct classification is load-bearing, not a nicety.
> **Owner:** Zayhan
> **Target version:** espalier v0.22.0
> **Estimated effort:** ~9–12h (two to three focused sessions).
> **Scope:** `/espalier` (full lane) and `/espalier-fix` wall-clock + token
> cost, including the pre-push hook and the CI wait.
> **Constraint (same as v0.21):** reduce wall-clock and token cost
> **without impacting code quality**. Every change is a dispatch-order,
> read-scope, or wait-scheduling change; the quality machinery — separate
> coder/reviewer/security agents, fresh panel round after every fix,
> per-round `VERDICT:` sentinels, programmatic build/lint gates, round
> caps, the `Reviewed-Diff` certificate, both human gates, the pre-push
> hook's independent re-verification — stays contract-equal to v0.21.

---

## 0. Goals & Non-Goals

### Goals
1. Remove the last big serial agent block: Stage 5 test writing currently
   waits for the Stage 4 panel even though most of its work does not
   depend on the panel's verdict (Track B).
2. Extend the v0.21 delta-scope contract to Stage 6 re-review rounds — the
   one review loop v0.21 missed (Track C).
3. Cut human round-trips: the non-critical pre-flight prompt folds into
   the approval gate (Track D), and Stage 9's mid-run deploy-parameter
   stall gets the same pre-authorization treatment Stage 7's push got in
   v0.21 (Track F).
4. Land the instrumentation the v0.21 plan called for ("measure before
   tuning") so the deferred stage-fold decision — and every future speed
   decision — is made on field data, not guesses (Track A).
5. Give the Stage 8 CI wait a protocol so orchestrators stop burning a
   model round-trip per poll (Track G).
6. Cut the pre-push hook's wall-clock without weakening any of its checks
   (Track H).
7. Micro-parallelize and batch the orchestrator's own bash where steps are
   independent (Track E).

### Non-Goals
- No change to any gate condition, verdict vocabulary, sentinel format,
  round cap, certificate, or escalation path.
- No change to grill semantics (full-tier stays sequential; light-tier
  batching stays as shipped).
- No model tiering in this release (see Deferred — needs eval evidence).
- No touch to `/espalier-init` discovery, `/espalier-map`, or
  `/espalier-maprun` orchestration beyond what the shared run-lane
  templates carry into workers automatically (Track H adds one init-time
  decision, gated off by default).
- The Stage 3/5 **fold** (tests into the coder, Stage 5/6 into the panel)
  stays deferred — Track B's overlap variant takes most of its wall-clock
  win without restructuring the stage contract; the fold's trigger
  condition becomes measurable via Track A.

---

## 1. Where the time goes after v0.21

A happy-path `/espalier` feature run serializes:

```
grill Q&A → approval gate → coder → build+lint → ┌ reviewer ┐ → drift bash
  (human)      (human)                            └ security ┘
→ test-coder → test-reviewer → push hook (build+lint+FULL test suite)
→ push → CI wait (polled) → [deploy confirm (human)] → Stage 10 (human)
```

v0.21 removed repeated discovery (context pack), whole-diff re-reads
(Stage 4 delta rounds, security delta mode), the Stage 7 stall (push
pre-auth), and light-tier grill round-trips. What remains:

- **5 sub-agent cold starts occupying 4 serial slots** on the happy path
  (the panel pair is already concurrent). Per `docs/usage-cost.md`, runs
  typically pass review in 1 round — so the remaining agent cost is spawn
  *serialization*, not round count.
- **Two to four human round-trips** (grill, approval, Stage 10; plus the
  pre-flight prompt whenever any signal exists; plus Stage 9's deploy
  confirm in deploy-configured repos — sitting right after the CI wait,
  where the human has most likely walked away).
- **The pre-push hook runs build → lint → the FULL test suite strictly
  serially on every gated push** (`pre-push-gate.sh` gate sections), plus
  a network-bound dependency audit (45s cap) on every push — a cost the
  v0.21 analysis never counted.
- **The CI wait has no protocol.** `pipeline.md` Stage 8 says only
  "Running CI command or reading CI output" — an orchestrator on remote
  CI polls, and each poll is a full model round-trip.
- **One shipped optimization that doesn't reach Stage 6:** both Stage 6
  prompt templates pass `ROUND: {n}` but never the
  `CHANGED SINCE LAST REVIEW:` line, so every test-review round ≥ 2
  silently re-reviews all tests. The reviewer's delta contract only
  activates "when handed the set" (`harness-reviewer.md` → Re-review
  Rounds).
- **No timing data.** Stage History rows already carry ISO timestamps, but
  `espalier-stats.sh` reports only round counts.

---

## 2. Track A — Stage-duration instrumentation (`espalier-stats.sh`)

**Goal:** turn the timestamps the pipeline already records into a per-stage
wall-clock report, split human-wait vs agent-work. Ship this first; it is
the decision gate for Track B's follow-ups and the recorded trigger for the
deferred fold (`docs/deferred-items.md`).

### 2.1 Design

New section `## Stage durations` in `espalier-stats.sh`:

1. For each `pipeline-state.md`, extract table rows FROM THE
   `## Stage History` SECTION ONLY — awk section-bounded, the same
   pattern the script's Maps section already uses. The same file carries
   other tables (`## Commits` rows are `| 7 | {SHA} | {files} |`,
   `## Follow-up Fixes`, `## Root Cause Addressed By`) whose rows must
   never reach the duration parser.
2. Duration attributed to a row = next row's timestamp − this row's
   timestamp (the span that ended when the next row was written). Last row
   gets no duration.
3. Bucket by stage number and aggregate with the existing `_stat_dist`
   helper (min/median/mean/max), per lane.
4. Classify spans as **human-wait** vs **agent-work** by the row that
   CLOSES them — a gate row is written AFTER the human answers, so the
   wait lives in the span that ends at that row (classifying by the
   opening row would report human-wait ≈ 0 on every run). A span whose
   closing row's notes match the human-gate markers
   (`Requirements approved`, `approved by user`, `delivery`, grill
   verdict rows) is a human span — EXCEPT any note containing
   `non-interactive` or `auto-` (`auto-approved`, `auto-accepted`), which
   is an unattended run's marker and classifies as agent/other, never
   human (headless fleets and `/espalier-maprun` workers write exactly
   those strings with zero human wait behind them; miscounting them would
   skew the very data the §11 fold trigger keys on). A span closed by a
   Stage 3–6 `PASSED`/`ROUND` row is an agent span; everything else is
   `other`. The split is approximate (a Stage 1 span mixes grill Q&A with
   drafting) — the buckets answer "where did the hour go", not billing.
   Print the three totals per lane.
5. Timestamp math via `python3` (already a pipeline dependency —
   `parse-drift-blocks.py`). Degrade granularity: `python3` absent → the
   whole section prints `stage durations: unavailable`; a single row
   whose timestamp doesn't parse SKIPS THAT ROW (both spans it bounds)
   and increments a printed `skipped_rows=N` counter — one foreign or
   hand-edited row must never poison the whole report. Tolerate both
   minute-resolution (`2025-01-15T10:05`) and full-second timestamps;
   minute-only diffs are floored, not errored.

### 2.2 Template tightening (optional, same release)

`_template`/skill examples show minute-resolution timestamps. Mandate
`date -u +%Y-%m-%dT%H:%M:%SZ` in the Stage Execution Protocol wording so
new rows carry seconds. Old rows keep working (tolerance above).

### 2.3 Quality argument

Read-only reporting; touches no gate. Pure addition.

### 2.4 Files
| File | Change |
|------|--------|
| `skills/espalier-init/hook-templates/espalier-stats.sh` | New `## Stage durations` section |
| `skills/espalier-init/templates/skills/espalier.md` | One-line timestamp-format note in Stage Execution Protocol |
| `skills/espalier-init/templates/skills/espalier-fix.md` | Same note in Stage State Protocol |

---

## 3. Track B — Take Stage 5 off the serial chain (speculative overlap, quarantine-on-FAIL)

**Goal:** on the typical 1-round run, hide the test-writing duration behind
the Stage 4 panel round it currently waits for — without ever letting a
speculative artifact touch a gate, a certificate, or a review verdict.

### 3.1 Why the dependency is weaker than the stage order implies

Stage 5's only true dependencies on Stage 4 are:

- **(a) the abuse-test contract** — `harness-security` emits
  `## Security-Sensitive Fields` only when it returns; AND
- **(b) stable code** — a panel FAIL means the code the tests target will
  change.

For (a): most changes have **no sensitive surface** — the security agent
self-noops by design (`harness-security.md` → Scope Gate) and emits no
contract, so there is nothing to wait for. For (b): the quarantine rule
below takes speculative tests OUT of the tree the moment a fix round
starts, so unstable code never collides with them.

### 3.2 New dispatch shape (both lanes)

**Round-1 Stage 4 dispatch becomes a 3-agent message:** `harness-reviewer`
+ `harness-security` + `harness-coder` in testing mode. The panel prompts
gain ONE line (an installed contract, not a hope — see 3.4):

```
SPECULATIVE TESTS IN FLIGHT: a test-writing agent runs concurrently with
you. New/changed TEST files not listed in coding-report.md are its
work-in-progress — exclude them from your review scope and your verdict;
they are reviewed at Stage 6.
```

The test-coder's prompt deltas, per lane:

```
SPECULATIVE DISPATCH: a review panel is running concurrently on this code.
- {full lane:} Write the interface tests and failure-mode tests for the
  coding-report changes NOW.
  {fix lane:} Write NOW: (1) the regression test that reproduces the
  original bug, (2) the original-feature test from the caused_by change's
  acceptance criteria, (3) failure-mode tests for any NEW external-call
  path — i.e. every fix-lane Stage 5 requirement EXCEPT the contracted
  abuse tests.
- Do NOT read security-record.md this pass — it may be mid-write; the
  contracted abuse tests are a separate phase after the panel returns.
- REPORT TARGET: espalier/changes/{type}/{slug}/coding-report.part-test.md
  — never append to coding-report.md directly (the panel is reading it).
  List EVERY file you create under "Files created" — the orchestrator's
  quarantine/discard mechanics operate on that list.
- Run ONLY scoped invocations of the test files you write; no whole-tree
  builds, no dependency installs.
```

The part-file report reuses the proven `coding-report.part-{n}.md`
mechanics from v0.21's parallel sub-task dispatch.

**Wall-clock shape (honest math).** The templates use blocking parallel
dispatch — all results in a message return together — so round-1 time
becomes max(reviewer, security, test-coder), and the round-1 verdict
waits for the slowest of the three. Happy path: max(panel, tests)
replaces panel + tests — always ≤. A 2-round change with quarantine:
old = P1 + fix + P2 + T; new = max(P1, T) + fix + P2 + R (R = the
restore-and-reconcile delta spawn, normally ≪ T) — a clear win while
test writing ≤ panel-time, near-wash at worst (≈ R − P1) when test
writing dominates. `speculative-tests: off` is the lever for repos
living in that worst case; Track A's data shows which regime a repo is
in.

**Sequencing protocol after the joint dispatch resolves (races are the
failure mode here — this ordering is mandatory):**

**Step 1 — orchestrator-local bash, ONE invocation, no agent in flight:**
1. Run the Stage 5 escalation detector against the PART file
   (`grep -q '^- TEST_SCOPE_INFLATION: true' coding-report.part-test.md`)
   — the fix lane's late-escalation gate must see the signal wherever the
   report landed, and it fires on BOTH the PASS and FAIL paths below (the
   signal describes the fix's testability, which survives any discard).
2. Read both panel sentinels (the unchanged gate read).
3. **On PASS:** append the part file to `coding-report.md`, then delete
   the part file (a crash between append and delete must not re-append on
   resume — the append is guarded by a content-presence grep, same
   idempotency style as the Stage 7 commit rows). Run the Stage 4
   post-review drift/convention parse (BEFORE any Stage 6 spawn — the
   existing contract, since Stage 6 overwrites review-record.md). Fix
   lane: run the Base-Ref regression verification now (see 3.3).
4. **On FAIL/p0/p1>0:** QUARANTINE the speculative tests — move every
   file listed in the part file's "Files created" to
   `espalier/changes/{type}/{slug}/.speculative-tests/` (paths preserved
   relative to root) and leave the part file beside them. The source
   tree is now exactly what the coder left it — the pre-round build/lint
   gate, the round-2 panel, and the coder re-spawn see NO speculative
   artifact. This kills the wedge where stale tests referencing round-1
   symbols break the whole-tree build/lint gate before every panel round
   (build failures don't increment `max-code-rounds`, so that wedge
   would have been uncapped).
5. **On ESCALATION_REQUIRED:** quarantine as in step 4, then the
   escalation protocol unchanged — plus one line in the escalation
   summary naming the quarantined files so the human decides with full
   information.

**Step 2 — post-final-PASS test completion (one spawn, alone in its
message):**
- Happy path (no fix round), empty contract → nothing to spawn; Stage 5
  is already complete. Serial test cost ≈ zero.
- Happy path, non-empty contract → one `CONTRACT PHASE:` test-coder
  re-spawn (abuse tests only, appends to coding-report.md normally).
- Any fix round occurred → one re-spawn that RESTORES the quarantined
  files (the orchestrator moves them back first, then spawns), reconciles
  them against "code changed since your tests: {files}", AND carries the
  `CONTRACT PHASE:` block when the contract is non-empty — one spawn,
  never two. Fix lane: the Base-Ref regression verification runs AFTER
  this spawn returns (see 3.3).

**Step 3 — Stage 6 dispatch, alone in its message.** Never in the same
message as any bash that writes coding-report.md or review-record.md.

**Hard rule the protocol encodes:** never issue a bash call that writes a
record file in the same message as an agent spawn that reads or writes
that same file — one message means concurrent execution. The Step-1 bash
runs with zero agents in flight; Steps 2 and 3 are single-spawn messages.

**Contract detection (deterministic):** after a PASS round,
`grep -q '^## Security-Sensitive Fields' <security-record.md>` decides
empty vs non-empty — the same grep-a-heading style as the gate reads.

**Round accounting (unchanged):** the speculative write, the
restore/reconcile re-spawn, and the contract phase are all Stage 5
actions — none increments `max-test-rounds`, which counts Stage 6 verdict
loops only, exactly as today. `max-code-rounds` semantics are untouched.

**State bookkeeping & crash recovery:** `Current Stage:` stays 4 during
the joint dispatch (it IS the Stage 4 round); the Stage 5 row is written
at Step-1 append / Step-2 spawn. On a resume into Stage 4:
- an orphan `coding-report.part-test.md` (tree or quarantine dir) → DELETE
  the part file AND every file its "Files created" list names, wherever
  they sit — the post-panel flow re-derives tests from scratch. The
  report alone is never the only thing discarded: the FILES are what
  `git add -A` at the certificate would otherwise sweep, unlisted and
  unreviewed, into the fingerprint.
- speculative files WITHOUT a part file (crash mid-write, nothing to
  enumerate from) → the orchestrator cannot reliably tell them from the
  coder's work, so it must not guess-delete: surface ONE line to the
  human — "possible orphan speculative tests: {untracked files matching
  the project's test layout that coding-report.md does not list} — review
  or delete before continuing" — and wait. Fail toward human eyes, never
  toward silent certification (the same bias the regression verifier
  documents). On an UNATTENDED run this prompt cannot fire and must not
  hang a headless worker: set `- Status: ESCALATED`, record the candidate
  list in a Stage History row
  (`| 4 | ESCALATED | {ts} | orphan speculative files need human review: {list} |`),
  and stop the lane — never guess-delete, never continue past artifacts
  the orchestrator cannot enumerate. (A maprun worker ending ESCALATED is
  a normal, master-surfaced outcome, not a hang.)
- a `.speculative-tests/` quarantine dir on a change being resumed →
  same rule as the part file: delete it (its part file sits beside it, so
  enumeration is exact).

**Stage 6 entry condition (unchanged in substance):** panel PASS + test
report landed in coding-report.md + contract coverage written (when a
contract exists) + regression verification recorded (fix lane). Only the
*ordering* that produced those artifacts changed.

### 3.3 Fix-lane regression verification scheduling

One uniform rule: the Base-Ref verification runs **after the LAST
test-writing spawn has returned, with the test files in their final
in-tree locations, and never in the same message as any test-writing
spawn** — a verification that runs mid-rewrite or against pre-reconcile
tests would record a `REGRESSION_VERIFIED` line that does not describe
the current tree. Concretely: happy path → it runs inside Step 1 (the
joint dispatch has fully resolved; the speculative tests ARE final);
contract-phase-only path → after the contract spawn (the contract spawn
does not touch the regression test, but the rule stays uniform rather
than clever); any-fix-round path → after the Step-2 restore/reconcile
spawn returns. The two-step-serial structure *inside* the verification
(fixed-tree run validates the invocation before the Base-Ref conclusion)
is untouched, and it is not parallelized (shared runner caches).

### 3.4 Why quality is unaffected

- Every gate reads the same records with the same sentinels; the Stage 6
  reviewer still enforces contract coverage, regression meaningfulness,
  and failure-mode coverage on the final artifacts.
- The panel's exclusion of in-flight test files is an INSTALLED contract:
  the one-line prompt addition (3.2) plus a matching one-liner in
  `harness-reviewer.md`/`harness-security.md` — not an unstated
  assumption. It narrows nothing that was ever Stage 4's scope: tests
  are reviewed at Stage 6, exactly as today. The reviewer's
  suspicion-expansion license over the CHANGE's files is untouched.
- Quarantine means no gate, panel round, or coder re-spawn after round 1
  ever executes against a tree containing speculative artifacts — the
  FAIL path is byte-identical to today's serial flow from the coder
  re-spawn onward.
- The quarantine dir lives under `espalier/changes/…`, which the
  certificate diff EXCLUDES (`':(exclude)espalier/'`), so quarantined
  tests can never leak into a `Reviewed-Diff` fingerprint. On the happy
  path the Stage 4 certificate may hash the in-tree speculative tests;
  harmless — Stage 6's fingerprint (the one the push gate compares)
  always supersedes it after test review, exactly as today's test-add
  flow.
- The unlisted-file hole is closed from both ends: the part report MUST
  list every created file (prompt contract), discard/quarantine operate
  on that list, and the no-list crash window fails toward a human prompt,
  never toward `git add -A` sweeping unreviewed files into a certificate.
- Reviewers execute nothing; the test-coder is the only executor during
  the joint dispatch (scoped runs only) — the shared-tree discipline from
  v0.21's parallel dispatch carries over, and `post-edit-wrapper.sh`'s
  per-edit layer check is read-only, so concurrent instances are safe.
- The fix lane's escalation machinery is preserved relocated, not
  dropped: the TEST_SCOPE_INFLATION detector greps the PART file at
  Step 1 on every path, before any append or quarantine.
- Round caps, escalation paths, and both human gates unchanged.

### 3.5 Config escape hatch

`speculative-tests: off` in `espalier/.espalier-config` restores the
serial Stage 5 dispatch verbatim (default: on, both lanes). Same read
pattern as the round-cap keys. This is the rollback lever if field data
(Track A) shows a repo living in the tests-dominate regime.

### 3.6 Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/skills/espalier.md` | Stage 4 dispatch (3-agent round 1 + panel prompt line), Stage 5 rewrite (sequencing protocol, phases), Stage 6 entry note |
| `skills/espalier-init/templates/skills/espalier-fix.md` | Same for the fix lane + lane-specific speculative test set + detector-on-part-file + verification scheduling |
| `skills/espalier-init/templates/pipeline.md` | Stage 5 trigger line ("dispatched with the round-1 panel; completed after panel PASS") |
| `skills/espalier-init/templates/agents/harness-coder.md` | Testing-mode note: SPECULATIVE / CONTRACT PHASE prompt contract + "list every created file" |
| `skills/espalier-init/templates/agents/harness-reviewer.md` | One line: prompt-marked in-flight speculative test files are outside this round's scope and verdict |
| `skills/espalier-init/templates/agents/harness-security.md` | Same one line |

---

## 4. Track C — Stage 6 delta scope (close the v0.21 gap)

**Goal:** re-review rounds ≥ 2 at Stage 6 get the same delta-scope contract
Stage 4 shipped in v0.21.

### 4.1 Change

Both Stage 6 prompt templates gain, on round ≥ 2:

```
{On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {the test files the Stage 5
fix re-spawn touched, from the latest coding-report.md}. Re-review in delta
scope per your "Re-review Rounds" section.
```

No agent-file change needed: `harness-reviewer.md` → "Re-review Rounds"
already defines the floor (changed files + prior findings + direct
dependents, expandable on suspicion) and activates it when handed the set.
`pipeline.md` Stage 6 gets the same one-line note Stage 4 carries.

### 4.2 Why quality is unaffected

Identical argument to the shipped Stage 4 change: every test file was
reviewed fresh in the round it last changed; the scope is a floor, not a
ceiling; the whole-change verdict rule and the sentinel contract are
untouched; the Stage 6 fingerprint still covers the full tree at PASS.

### 4.3 Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/skills/espalier.md` | Stage 6 prompt: delta line on round ≥ 2 |
| `skills/espalier-init/templates/skills/espalier-fix.md` | Stage 6 prompt: same |
| `skills/espalier-init/templates/pipeline.md` | Stage 6 section: delta-scope note |

---

## 5. Track D — Fold the non-critical pre-flight prompt into the approval gate

**Goal:** one fewer human round-trip on runs where Stage 0 pre-flight finds
signals. The decision is deferred within the run, never removed — and on a
run that dies before its approval gate, it is deferred to the NEXT run's
pre-flight (the drift sidecar persists), which the plan states as the
accepted semantics rather than pretending nothing moved.

### 5.1 Change (both lanes)

Stage 0 pre-flight still gathers all three signals (STALE / CONV /
DOCTOR). New dispatch of the *prompt*:

- **Any critical/expired stale row** → today's behavior exactly: immediate
  blocking `AskUserQuestion`, default "Handle now" (the per-clone
  escape-hatch case).
- **Only non-critical signals** → do NOT prompt here. Print the one-line
  summary and RECORD it to `espalier/.drift-report.md` with a
  `deferred-to-approval-gate ({ts})` marker line — the same surface
  unattended runs already write, now carrying the interactive deferral
  too, so an interrupted run leaves an inspectable trace. Continue to
  Stage 1. At the **Requirements Approval Gate**, append a third question
  to the existing `AskUserQuestion` call (approve / push-target / — new —
  maintenance):

  ```
  Pre-flight noted: {N} stale doc(s) ({tiers}), {M} convention promotion
  candidate(s), doctor {due|not due}.
    1. Handle after this change (default — gardener rota covers it)
    2. Pause & handle now — run /espalier-prune + convention decisions,
       then continue to Stage 3
    3. Ignore this run
  ```

- **No signals** → nothing, as today.
- **Unattended** → unchanged (never prompts; writes `.drift-report.md`).
- **Run never reaches the approval gate** (crash, Abort, fix-lane
  escalation migration): the deferred question is dropped FOR THAT RUN —
  the signals re-surface at the next invocation's pre-flight unchanged,
  because the sidecar state was never cleared. A delay, not a loss.

Convention promotions decided via "Pause & handle now" run the same
mechanics (race guard, per-key status flip, isolated `docs:` commit) —
relocated, not altered. Deciding at the approval gate is still **before
Stage 3**, so a promoted rule governs the coder that run.

### 5.2 Why quality is unaffected

The current prompt's default is already "Proceed", so the default path's
semantics are identical. One trade-off is real and ACCEPTED, not claimed
away: for non-critical signals, "handle now" moves from pre-grill to
post-grill — a user who would have refreshed stale docs before Stage 1
now grills against the stale docs. This is survivable by design: grill
verifies every cited convention against the CURRENT code before raising
it and `mark_stale`s a doc that disagrees, so a stale doc degrades to a
flagged doc, never into a wrong requirement. Critical/expired rows — the
case where doc rot is bad enough to matter — keep today's immediate
blocking prompt with "Handle now" as its default.

### 5.3 Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/skills/espalier.md` | Stage 0 pre-flight dispatch rules + `.drift-report.md` deferral record + approval-gate third question |
| `skills/espalier-init/templates/skills/espalier-fix.md` | Same (its approval gate is the diagnosis gate) |

---

## 6. Track E — Orchestrator micro-parallelism & bash batching

1. **Build + lint concurrently** at the Stage 3 exit gate and every
   pre-panel re-run: the two discovered commands are independent — run
   them as two background jobs (`$BUILD & $LINT & wait` with per-pid
   `wait`s to capture both rcs, each job's output redirected to its own
   temp file so a failure's log isn't interleaved); both must still
   exit 0, failure handling unchanged. Escape: NO new config field — the
   orchestrator keeps them serial when the discovered commands plainly
   depend on each other (e.g. a typecheck that consumes build output), a
   judgment it makes from the commands it already read at discovery.
2. **Batch the orchestrator's own bookkeeping into single bash
   invocations** — Track B's Step-1 protocol is the model. The rule that
   makes this safe: batch orchestrator-LOCAL steps together freely
   (they run in one serial script), but NEVER bundle a bash that writes a
   record file into the same message as an agent spawn that reads or
   writes that file (one message = concurrent execution). The old idea of
   "riding the next dispatch" is superseded by this rule — it bundled
   the part-file append with the contract spawn (both touching
   coding-report.md) and the drift parse with the Stage 6 spawn (which
   overwrites review-record.md the parse is reading); both are exactly
   the races the rule forbids.
3. **Stage 7 bookkeeping in one script:** the fix lane's per-entry
   back-link contract ("runs ONCE PER ENTRY as its own bash invocation")
   exists only so `exit 0` early-outs are safe; wrap the entry body in a
   function whose early-outs are `return 0` and run ALL Stage 7
   bookkeeping — convention staging (7.0), own-commit recording (7.1),
   every back-link entry (7.2), the partial-fix reverse-link — in ONE
   bash invocation per lane. Saves up to ~5 orchestrator turns per fix
   with byte-identical file effects.
4. **Stage-transition batching (protocol line):** the Stage Execution
   Protocol's "update state" write, "load context" read, and previous
   stage's "record" append may ride one message when no agent is in
   flight — same file effects, fewer turns.

Explicitly NOT doing: parallelizing the fix lane's fixed-tree vs Base-Ref
regression runs — shared `node_modules`/test-cache state makes concurrent
runner invocations unsafe on some stacks, and the step-1-validates-step-2
ordering is a deliberate part of the check's honesty.

### Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/skills/espalier.md` | Stage 3 exit-gate wording; batching rule + protocol line |
| `skills/espalier-init/templates/skills/espalier-fix.md` | Same + Stage 7 single-script bookkeeping (function-wrapped back-link loop) |
| `skills/espalier-init/templates/pipeline.md` | Stage 3 gate wording |

---

## 7. Track F — Stage 9 deploy pre-authorization (mirror of the shipped Push-Target pattern)

**Goal:** remove the one remaining mid-run human stall pre-authorization
can legitimately remove. `pipeline.md` Stage 9's "confirm deploy
parameters (human checkpoint)" sits AFTER the CI wait — the point in the
run where the human has most likely walked away; the v0.21 push pre-auth
exists for exactly this stall shape one stage earlier.

### 7.1 Change

At the Requirements Approval Gate, ONLY when the discovered
`## Deploy & Verification` section is configured (i.e. it does not read
"No deploy configuration discovered"), add a deploy question to the same
`AskUserQuestion` call:

```
When Stage 9 (deploy verify) is reached and CI is green, deploy with the
discovered command to:
  1. {discovered target/environment}   (pre-authorize)
  2. Somewhere else — specify
  3. Ask me again at Stage 9
```

Record `- Deploy-Target: {target | ASK}` in pipeline-state.md. Stage 9
with a pre-authorized target runs the discovered deploy + health check
without re-prompting; `ASK`/missing → prompt exactly as today. No-deploy
repos see no new question (the SKIPPED path is untouched).

**Unattended posture (decided — closes a pre-existing gap):** an
unattended run with a pre-authorized target proceeds (deploy + health
check — that is what pre-auth is for); unattended with `ASK`/missing
records `| 9 | SKIPPED | {ts} | deploy needs-human (unattended) |` and
continues. An unauthorized target is NEVER auto-deployed. Today's
templates specify no unattended behavior for a configured Stage 9 at
all; this rule replaces improvisation with the conservative default.

### 7.2 Why quality is unaffected

The programmatic health-check gate (HTTP 2xx / exit 0) and its
rollback-on-failure path are untouched; a failed health check still stops
the lane before Stage 10. Stage 10's human acceptance is unchanged — the
existing "pre-authorization NEVER extends to Stage 10" line applies to
this question verbatim. This removes a redundant wait, not a decision:
the human makes the same parameters decision, at a moment they are
already present.

### 7.3 Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/skills/espalier.md` | Approval-gate deploy question (conditional) |
| `skills/espalier-init/templates/pipeline.md` | Stage 9: honor `Deploy-Target:` pre-auth; `ASK`/missing → prompt as today |

---

## 8. Track G — Stage 8 CI wait protocol (+ Stage 8.5 fold)

**Goal:** stop paying a model round-trip per CI poll. No wait strategy
exists in the templates today, so orchestrators improvise short polls.

### 8.1 Change

One instruction block in `pipeline.md` Stage 8 (and the espalier skill):

- Prefer the CI provider's BLOCKING watch inside a single bash call
  (`gh run watch <run-id> --exit-status` or equivalent), not a poll loop
  across messages.
- The Bash tool caps a call at ~10 minutes — for longer CI, chunk the
  wait: a single bash `until`-loop per call with a generous internal
  interval and a ~9-minute per-call budget, repeated. Turns become
  ceil(CI / 9min), not CI / poll-interval.
- Issue the Stage 8.5 doc-drift bash in the SAME message as the first
  watch call: 8.5 reads only `.drift-state.tsv` and appends only to the
  change's `doc-patches.md` — CI-independent, notify-only, and no agent
  or other bash touches that file concurrently, so the Track E batching
  rule permits it.

### 8.2 Why quality is unaffected

The gate still reads the same final `ci_status` / `total_tests` /
`lint_errors` values; only the waiting shape changes. Stage 8.5 is
notify-only by contract and blocks nothing.

### 8.3 Files
| File | Change |
|------|--------|
| `skills/espalier-init/templates/pipeline.md` | Stage 8: wait protocol block |
| `skills/espalier-init/templates/skills/espalier.md` | Stage 8.5: "may ride the first watch message" note |

---

## 9. Track H — Pre-push hook wall-clock (parallel gates opt-in + audit cache)

The hook is the deterministic backstop — every check stays, every check
still blocks. Two cost cuts inside it:

### 9.1 Parallel gate sections (opt-in, default serial)

`pre-push-gate.sh` runs `gate_build_section` → `gate_lint_section` →
`gate_tests_section` strictly serially: every gated push costs
sum(build, lint, tests). When `espalier/.espalier-config` carries
`hook-parallel-gates: yes`, run the three substituted commands as
background jobs (per-pid `wait`, per-job temp-file output, any nonzero rc
still exits 2 with that job's output). The key's write flow (decided):
discovery PROPOSES — when it judges the three commands mutually
independent (most test runners self-build; a stack whose tests consume a
prebuilt artifact is never proposed) — and an option on an EXISTING
init-time question confirms; no answer → serial. Dependent-toolchain
repos see no new prompt at all. Existing installs migrate with the key
absent → serial, byte-equivalent behavior. A static hook cannot judge
toolchain ordering at runtime; init time (plus the human) can.

**Implementation caveat:** migrations re-splice SPANS of this file (the
`run_tests` comment documents the v0.9.2 precedent) — the parallel branch
must preserve the existing section anchor comments so future span-based
patches keep landing.

### 9.2 Dependency-audit cache

The WARN-only, network-bound audit (45s timeout) runs on EVERY push —
even `PIPELINE_TRACKED=no` pushes. Cache the result in a gitignored
`espalier/.dep-audit-cache` keyed on the lockfile hash, with a TTL
(default 7 days): re-run only on lockfile change or TTL expiry, print the
cached warning otherwise. A new dependency changes the lockfile and
forces a fresh audit; the TTL bounds staleness for newly published
advisories. The audit never blocked a push, so caching weakens no gate.

### 9.3 Why quality is unaffected

All three gate sections still run on every push and still exit 2 on any
failure — 9.1 changes overlap, never presence or ordering relative to the
push. 9.2 caches an advisory that is non-blocking by explicit design
("never blocks the push").

### 9.4 Files
| File | Change |
|------|--------|
| `skills/espalier-init/hook-templates/pre-push-gate.sh` | Guarded parallel branch (anchor-preserving) + audit cache |
| `skills/espalier-init/SKILL.md` (init) | Write `hook-parallel-gates:` only on discovery-verified independence |
| target `.gitignore` (init/migration) | `espalier/.dep-audit-cache` entry |

---

## 10. Considered and rejected

- **Warm/persistent reviewers across rounds** (reuse one reviewer
  conversation instead of fresh spawns). Rejected: the stateless
  fresh-eyes spawn is the review's integrity mechanism ("You NEVER wrote
  this code — you are seeing it fresh"); a warm reviewer anchors on its
  own prior verdict. Delta scope already bounds the re-read cost.
- **Skip the security agent on non-intersecting rounds.** Stays rejected
  (v0.21 decision; do not re-litigate): a fix can introduce a new
  client-data read into a previously non-sensitive file. Delta MODE keeps
  the invariant at nearly the same saving.
- **General grill batching.** Stays rejected for `full` tier and decision
  mode: the eval rubric's Progression dimension scores question chaining
  as quality.
- **Pre-authorizing Stage 10 acceptance at the approval gate.** Forbidden
  by design — delivery acceptance stays a human act. (Track F's Stage 9
  question is parameters-confirmation pre-auth with all programmatic
  gates intact — a different act; the Stage 10 line stays verbatim.)
- **Skipping the pre-push hook's build/tests when the certificate
  matches.** Rejected: the hook's value is INDEPENDENT re-verification —
  the same claim-vs-gate philosophy that keeps the orchestrator's
  build/lint re-run. Track H overlaps its sections; it never skips one.
- **Trimming fix-lane Stage 0.4 linked-context reads.** Already bounded
  by the existing >8K-tokens summarization rule; nothing worth the churn.
- **Parallelizing the regression verification's two runs.** See Track E.

## 11. Deferred

- **The Stage 3/5 fold** (interface tests into Stage 3; Stage 5/6 into
  the panel; ~2 fewer cold starts + one fewer loop). Still the largest
  *token* saving, but Track B captures most of the *wall-clock* saving
  without restructuring the stage contract. New trigger: Track A field
  data showing (a) most runs pass Stage 4 in 1 round AND (b) spawn
  cold-start time still dominates agent-phase wall-clock after Track B.
  Update `docs/deferred-items.md` accordingly.
- **Model tiering per seat** (e.g. test-coder on a faster model). Only
  with eval evidence: run `eval/coder` (and `eval/review` / `eval/security`
  for those seats) under the candidate model and require parity before
  proposing. Note the headless-model lesson: workers/eval must pin
  `--model` explicitly.

---

## 12. Test plan

1. **Bootstrap suite** (currently 257/257): add Test 30 — v0.22 marker
   assertions (speculative-dispatch + quarantine blocks in both lane
   skills, panel in-flight line, Stage 6 delta line, pre-flight fold
   text, deploy pre-auth question, CI wait block, stats section, hook
   parallel branch + cache) + migration apply / no-op / customized-skip
   triplet, following the Test 28/29 pattern. Remember the v0.21.1
   lesson: dash-leading grep anchors need `grep -qF --`.
2. **Hooks suite** (currently 146/146): stats tests — fixture
   `pipeline-state.md` files with known timestamps → expected duration
   lines; a foreign `## Commits`-style row → not parsed; one corrupt
   timestamp → that row skipped, `skipped_rows=1`, section still prints;
   unattended `auto-approved` note → not counted human; `python3`
   absent → `unavailable`; empty install → `none`. Pre-push tests: both
   gate modes (serial default and `hook-parallel-gates: yes`) with each
   command failing in turn → exit 2 with that command's output; audit
   cache hit / lockfile-change miss / TTL expiry.
3. **Eval suites:** re-run `eval/coder`, `eval/review`, `eval/security`,
   and `eval/maprun` fixtures (the lane templates changed; grill and map
   fixtures are untouched by this release). Per the eval-baseline lesson,
   if any fixture regresses, first re-baseline the OLD templates under
   today's model before attributing to the change.
4. **Manual smoke (behavioral, not marker-grep):** one `/espalier feat:`
   and one `/espalier-fix` run on a scratch repo covering: 1-round PASS
   with empty contract (fast path — Stage 5 serial cost ≈ 0); a forced
   Stage 4 FAIL round (quarantine → clean build/lint → restore/reconcile
   spawn); a sensitive change (contract phase); a forced **Stage 6
   round ≥ 2** (Track C's delta line actually passed and delta-scoped);
   a **crash resumed into Stage 4** (part-file + listed files discarded;
   no-list orphan → the human-surfacing line, not silent deletion);
   `speculative-tests: off` (serial path equivalent to v0.21); a
   pre-flight-signal run (maintenance question rides the approval gate);
   one **unattended** (`ESPALIER_UNATTENDED=1`) fix-lane run end-to-end;
   and, in a deploy-configured fixture, Stage 9 honoring a pre-authorized
   `Deploy-Target:` — plus the unattended Stage 9 pair: pre-authorized →
   deploys and health-checks; `ASK` → the `SKIPPED — deploy needs-human`
   row, no deploy attempted.

## 13. Rollout

1. Implement Tracks A → C → E → G → D → F → H → B (smallest/independent
   first; B last — it touches the most template text and depends on E's
   batching rule being written).
2. `scripts/migrate-v0.21.1-to-v0.22.0.sh` (migration #30): copy the
   changed PURE-COPY surfaces with backup-on-diff
   (`<file>.pre-v0.22.bak`) — both lane skills, `pipeline.md`,
   `espalier-stats.sh` — following the #28 pattern. SUBSTITUTION
   templates get targeted, anchor-based patches instead (the #29
   coder-patch pattern), never wholesale copies: `harness-coder.md`,
   `harness-reviewer.md`, `harness-security.md` (all carry
   `{project_name}`), and `pre-push-gate.sh` (carries the three
   substituted commands; patch by section anchors, preserving the
   span-splice markers earlier migrations rely on). No blanket
   `chmod +x` on synced files (tar preserves modes; the release gate
   rejects flipped template modes).
3. **Migrate-skill checklist (the gap that recurred twice — run ALL of
   it):** bump `NEEDS_*` detection + the final up-to-date check + the
   Step 2 probe filename + the Step 3/6 lists + the frontmatter
   description line + the numbered entry (#30) + the chain paragraph +
   the "Up to TWENTY-x" header + `plugin.json` + `marketplace.json`
   (2 version fields).
4. CHANGELOG + `docs/deferred-items.md` trigger update + this doc gains a
   "Shipped" section mirroring `docs/pipeline-speed-plan.md`'s shape.
5. Suites + evals green → tag v0.22.0, GitHub release.

## 14. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|------------|--------|------------|
| 1 | Speculative work wasted on FAIL rounds | Medium | Low (tokens, not quality) | Quarantine preserves the work for the restore/reconcile spawn; bounded by `max-code-rounds`; Track A measures; `speculative-tests: off` |
| 2 | Round-1 verdict waits for the slowest of 3 agents | Medium | Low-Medium (wall-clock only) | Honest math in §3.2; happy path strictly wins; `speculative-tests: off`; Track A shows the regime |
| 3 | Stale speculative tests break the pre-round whole-tree build/lint (uncapped wedge — build failures don't count rounds) | Was HIGH | Eliminated by design | Quarantine-on-FAIL (§3.2 Step 1.4): the tree the gate/panel/coder see after round 1 carries zero speculative artifacts |
| 4 | Speculative test FILES survive discard unlisted and get swept into the certificate by `git add -A` unreviewed | Low | High if unhandled | Part report must list every created file; discard deletes report + listed files; quarantine dir sits under `espalier/` (fingerprint-excluded); no-list crash → human-surfacing line interactively, `ESCALATED` on unattended runs — never silent proceed, never a hang (§3.2 crash recovery) |
| 5 | Same-file races from bundling bookkeeping bash with spawns | Was HIGH (in draft 1) | Eliminated by design | §3.2 sequencing protocol + §6.2 hard rule: Step-1 bash runs with zero agents in flight; Steps 2/3 are single-spawn messages |
| 6 | Panel behavior change from unexplained in-flight test files (suspicion-expansion license → phantom-scope FAIL/escalation) | Medium | Medium | Installed contract, not a hope: panel prompt line + one-liners in both reviewer/security agent files (§3.2, §3.6) |
| 7 | Fix-lane Stage 5 machinery silently dropped (scope-inflation detector, regression/original-feature tests) | Was MED | Eliminated by design | Lane-aware speculative prompt (§3.2); detector greps the PART file at Step 1 on every path |
| 8 | `REGRESSION_VERIFIED` describes the wrong tree (run mid-rewrite / pre-reconcile) | Medium | High if unhandled | Uniform rule (§3.3): verification runs after the LAST test-writing spawn, never in the same message as one |
| 9 | Escalation leaves speculative files around | Low | Low | Quarantined under the change dir + named in the escalation summary |
| 10 | Stats skew: unattended `auto-*` rows counted as human; foreign table rows parsed; one bad row poisons the report | Medium | Medium (it gates the fold decision) | §2.1: `non-interactive`/`auto-` exclusion; Stage-History-section-bounded parsing; per-row skip with `skipped_rows=N` |
| 11 | Minute-resolution legacy timestamps → zero-length durations | Certain (legacy rows) | Low | Tolerated by design; new rows carry seconds |
| 12 | Build/lint concurrency breaks ordered toolchains | Low | Medium | Orchestrator keeps serial on plainly-dependent commands (§6) — judgment from discovered commands, no new field |
| 13 | Init misjudges command independence for `hook-parallel-gates` | Low | Medium (flaky pushes) | Default serial; discovery proposes + human confirms at init (§9.1, decided); both modes smoke-tested (§12.2); trivially removable key |
| 14 | Audit cache hides a fresh advisory | Medium | Low | WARN-only check by design; lockfile-hash key + 7-day TTL bounds staleness |
| 15 | Deploy pre-auth removes a human look at deploy parameters | Low | Medium | Same decision, made earlier by the same human; health-check gate + rollback + Stage 10 acceptance unchanged; `ASK` remains available and is the default when unanswered; unattended posture decided in §7.1 (never auto-deploy an unauthorized target) |
| 16 | CI watch exceeds the ~10-min bash cap | Certain on long CI | Low | Chunked watch calls (~9 min budget each) — §8.1 |
| 17 | Pre-flight fold delays doc refresh / promotion past grill's rules read; interrupted runs defer the question to the next run | Medium | Low | Accepted trade-offs stated in §5; grill verifies citations against code + `mark_stale`; sidecar persistence guarantees resurfacing; critical/expired keeps the immediate prompt |
| 18 | Migration misses a machinery surface again | Medium | Medium | Checklist in §13.3; Test 30 asserts the markers; four substituted files patched by anchor, never copied (§13.2) |

## 15. Decisions (resolved with the owner, 2026-08-18)

All former open questions are settled; none block implementation.

1. **`speculative-tests` default** — **ON, both lanes** (owner decision).
   Same key, same off-switch per repo.
2. **Contract-phase prompt shape** — same testing-mode prompt + a
   `CONTRACT PHASE:` marker line; `harness-coder.md` documents one
   testing-mode contract with two entry points (speculative,
   contract/restore). (Adopted recommendation.)
3. **Track A machine-readable output** — no TSV in v0.22; markdown only,
   matching the script's read-only report philosophy. Revisit if someone
   actually graphs it. (Adopted recommendation.)
4. **`hook-parallel-gates` write flow** — discovery PROPOSES, the human
   CONFIRMS via an option on an existing init-time question; no answer →
   serial; dependent-toolchain repos are never asked (owner decision;
   encoded in §9.1).
5. **Audit-cache TTL** — 7 days, overridable via `dep-audit-ttl-days:`
   in `.espalier-config`. (Adopted default.)
6. **Stage 9 unattended posture** — pre-authorized target → deploy +
   health check; `ASK`/missing → `SKIPPED — deploy needs-human` row and
   continue; an unauthorized target is never auto-deployed (owner
   decision; encoded in §7.1, closing a pre-existing unspecified-behavior
   gap).
7. **Release shape** — ONE v0.22.0 carrying all eight tracks; one
   migrate-skill checklist run covers everything (owner decision).
8. **Field profile driving priorities** — interactive full-lane feats,
   fix-lane bugs, and maprun headless batches are ALL real usage for this
   owner; CI/deploy presence varies by repo. Consequences: every track
   retained; F/G stay conditional (they self-noop where unconfigured);
   Track A's unattended-marker correctness (§2.1) and the unattended
   crash-recovery posture (§3.2) are load-bearing requirements, not edge
   polish (owner statement, this grill).
