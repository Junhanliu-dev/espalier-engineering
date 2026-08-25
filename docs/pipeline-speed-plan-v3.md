# Pipeline Speed Plan v3 (v0.23.0) — Round Economy

**Constraint (unchanged from v0.21/v0.22):** reduce the wall-clock and token
cost of an `/espalier` feature run and an `/espalier-fix` run **without
impacting the quality of the code**. The quality machinery — separate
coder/reviewer/security agents, fresh panel round after every fix, per-round
`VERDICT:` sentinels, programmatic gates, round caps, the `Reviewed-Diff`
certificate, both human checkpoints — keeps its contract. Every track below
is either a dispatch restructuring whose review coverage is provably equal
(one place it is strictly stronger — see §2.4), or an additive
context change that reduces *rounds*, never *scrutiny*.

**What is different about v3:** v0.21 and v0.22 were designed against a
modeled cost profile. v3 is designed against **field data** — a real v0.22.1
install (`portal.quota.com.au`, 42 changes: 35 feat / 4 fix / 3 refactor,
one BUILT map with 14 charted slices, heavy maprun usage) measured on
2026-08-24 via Track A (`espalier-stats.sh`) plus per-change Stage History
analysis.

**Revision r2 (2026-08-25):** a claim-by-claim code review of this plan
found three blockers (§3.1's source data did not exist; the digest never
fired for maprun slices; risk #3's premise was factually wrong), several
design gaps, and about a dozen unlisted edit surfaces. This revision folds
the fixes in; the change list is §14.

---

## 0. Field evidence (what the data says)

### 0.1 The v0.22 deferred-fold trigger is now satisfied

`docs/deferred-items.md` gated the Stage 3/5 fold on two conditions:

> (a) most runs pass Stage 4 in 1 round AND (b) spawn cold-start time still
> dominates agent-phase wall-clock AFTER the v0.22 overlap shipped.

Measured:

- **(a) SATISFIED.** Post-v0.22 changes (created ≥ 2026-08-19): **8 of 11
  passed Stage 4 with zero FAIL rounds (73%)**; 2 more with one round.
  (Pre-v0.22 changes on the same repo: only 5/19 zero-round — the overall
  `code rounds median=1, mean=1.17` hides the improvement.) Test rounds:
  median **0**.
- **(b) MEASURED, concentrated exactly where the fold cuts.** Post-v0.22
  stage-transition medians: coder→panel-verdict 622s; panel→Stage-5 row
  **0s** (the speculative overlap works in the field — verified live,
  including a correct quarantine-on-FAIL on 2026-08-21); the remaining
  serial agent tail is the **Stage 6 test-review spawn, ~235s median**,
  plus its (rare) fixpoint loop. That tail is the last stage-machinery
  wall-clock item on the happy path — and the per-run cold starts it
  represents are the token cost the fold was always chiefly about.

### 0.2 Rounds are where the remaining minutes are

A Stage 4 FAIL round costs ~900s median (fix-round coder + fresh panel).
The field FAIL-round notes cluster hard in ONE defect family: access-control
on list slices (`access.filter.update` missing, field over-disclosure, role
widening) — found independently by reviewer AND security across at least
three sibling slices of the same map (`job-lists`, `money-lists`,
`tradie-credentials-licence-portfolio`).

- **Charted (map-spawned) feats: code rounds median 2.** Uncharted feats:
  median 0. The map's slices keep re-paying for the same lesson.
- Grill verdicts on charted feats: **GRILLED=14 of 14, crisp=0.** Caveat:
  the recorded verdict does not distinguish `light` from `full` tier
  (`GRILLED` covers both), so this shows slices are never *crisp*, not
  that they grill deep — Track D' therefore starts by instrumenting the
  tier before tightening anything (§5).

### 0.3 Shipped speed work that sits unused

`hook-parallel-gates` (measured −42% on gated pushes in the v0.22
benchmark) is **not opted in** on the field repo, whose discovered commands
(backend + frontend `npm run build`, `npm test`) are plausibly independent.
The opt-in exists but nothing ever suggests it after init.

---

## 1. Goals & Non-Goals

### Goals

1. Remove the last stage-machinery spawns on the happy path (the
   speculative test-coder seat + the Stage 6 test-review spawn) by folding
   interface and failure-mode test writing into Stage 3 — **the Stage 3/5
   fold**, now evidence-backed (Track A'). Primarily a **token /
   cold-start / round-trip** saving; wall-clock is modestly positive
   (honest math in §2.5).
2. Reduce FAIL rounds on map-charted slices by feeding sibling-slice
   review findings forward (Track B') and by instrumenting-then-hardening
   slice crispness at map handoff (Track D').
3. Convert shipped-but-unused wins into used ones: a report-only adoption
   nudge for `hook-parallel-gates` (Track C').
4. Micro: assemble the context pack before the approval-gate prompt fires
   (Track E').

### Non-Goals

- No weakening of any gate, sentinel, cap, certificate, or human
  checkpoint. Stage 10 acceptance stays a human act.
- No re-litigation of the v0.21/v0.22 rejected list (warm reviewers,
  security-agent skipping, full-tier grill batching, certificate-skip of
  the push hook). Those rejections are quality invariants.
- No model tiering in this release — still gated on eval parity evidence
  (stays in Deferred).
- The security-eval judge recalibration (deferred from v0.22) is a
  **prerequisite task, not a track** — see §6 Test plan. v0.23 touches
  review/security-adjacent template text, so the judge-collapse rule must
  be recalibrated and `judge-validation/` re-validated FIRST, per
  `eval/security/KNOWN-ISSUES.md`.

---

## 2. Track A' — The Stage 3/5 fold (tests ride the coder; panel reviews code+tests together)

### 2.1 New shape (both lanes)

**Today (v0.22):**

```
coder → build+lint → ┌ reviewer          ┐
                     │ security          │ → Step-1 append → [contract spawn]
                     └ spec. test-coder  ┘   → Stage 6 test-review → push
```

**v0.23 (`test-mode: folded`):**

```
coder (code + interface/failure-mode tests)
→ Stage 3 exit gate: build+lint+changed-scope tests (+ fix-lane
   regression verification + scope detectors) — every coder return
→ ┌ reviewer (code AND tests) ┐  → panel PASS → certificate
  └ security                  ┘
→ [sensitive only: contract spawn → delta test-review → cert refresh]
→ push
```

- **Stage 3.** The coder prompt (both lanes) adds: write the interface
  tests and failure-mode tests for the change alongside the code, per
  `espalier/skills/espalier-testing/SKILL.md` — everything the speculative
  Stage 5 pass writes today EXCEPT the contracted abuse tests (the
  contract does not exist until the security agent's first clean pass).
  `harness-coder.md` already carries the testing-mode contract
  (`### Speculative & Contract entry points`); the fold makes the
  interface-test half a Stage 3 duty and retires the speculative entry
  point (the contract entry point stays). The coding report lists test
  files in their own subsection — the escalation detectors below key off
  that split.
- **Stage 3 exit gate** (every coder return, first pass and every fix
  re-spawn), one bash protocol:
  1. build + lint as concurrent jobs (unchanged);
  2. **test execution (new gate duty — the fold moves it here).**
     Today Stage 5's own gate requires "tests pass" before any review;
     without this step the first execution would slide to the push
     hook's full-suite run — the most expensive failure point, and the
     panel would be reviewing tests nobody has ever run. Run the
     discovered test command on every coder return, scoped to the
     coder's listed test files where the runner supports path filtering
     (full suite where it does not — that is exactly what the Stage 5
     gate paid today, moved earlier, not added). A failing run goes
     straight back to the coder WITHOUT spawning the panel, like a
     failing build;
  3. **fix lane:** the regression verification (fixed-tree scoped run +
     `Base-Ref` worktree run) — relocated here from the post-test-spawn
     slot. It RE-RUNS on every coder return (a fix round can rewrite the
     regression test); the `- REGRESSION_VERIFIED:` line in
     coding-report.md is re-appended per run and readers take the LAST
     line (`grep … | tail -1`, the sentinel pattern). Skip the worktree
     half when neither the regression test files nor `Base-Ref` changed
     since the last verified run — recorded facts, made concrete:
     `Base-Ref` is already a state line, and each verified run appends
     `- REGRESSION_VERIFIED_SCOPE: {hash of the sorted regression-test
     paths + blob SHAs}` beside the sentinel; unchanged hash + unchanged
     `Base-Ref` = skip. Net effect:
     the panel sees `REGRESSION_VERIFIED` **before round 1** — strictly
     earlier than today's Stage-6-only visibility, same
     `true|false|skipped` semantics;
  4. **scope detectors** (fix lane; relocated, not new): the Stage 3
     reactive escalation gate now counts **non-test files only** toward
     its `>5 files / >2 layers` thresholds — the fold moves test files
     into the Stage 3 diff, and counting them would trip the gate on
     work that was previously Stage 5's. Test scope keeps its OWN signal:
     the coder's `TEST_SCOPE_INFLATION` block (re-worded, not unchanged:
     its trigger text currently says "under `/espalier-fix` Stage 5" and
     lands in the speculative part file under the default mode — both
     references die with the fold; the block becomes a Stage 3 duty
     written in coding-report.md) is grepped HERE on every return,
     firing the same late-escalation prompt. Neither signal is weakened; they are
     re-addressed to where the work now happens.
- **Stage 4 panel = 2 agents again** (reviewer + security; the
  speculative third seat and its "tests in flight" exclusion lines
  retire). The reviewer's scope explicitly includes the tests: the
  test-review checklist it runs at Stage 6 today — assertions meaningful
  and not tautological, changed-interface coverage, the failure-mode P1
  rule, `REGRESSION_VERIFIED: false` = P0 (fix lane) — becomes a
  mandatory section of the Stage 4 review. **Exception: the
  `## Security Abuse-Test Coverage` check CANNOT run in round 1** — the
  contract it verifies is emitted by the security agent in this same
  round. That check moves whole to the contract delta review (below),
  where the contract exists. The security agent's scope note: test files
  are in scope for secrets/live-endpoint/fixture-data leakage, and are
  otherwise not findings surface — this is strictly more security
  coverage than today, where no security agent ever reads a test file.
- **Stage numbering and state (load-bearing — the integer contract).**
  Stage numbers are an interface: `pre-push-gate.sh` parses
  `Current Stage:` as an integer (≥ 7 to push), `espalier-stats.sh`
  buckets durations by stage number, and maprun parses it twice more —
  `maprun-dispatch.sh:357/379` (leg boundaries, no-progress detection)
  and `maprun.py:399`. The fold keeps the numbers and
  re-points their meaning; it never removes a row:
  - Stage 3 rows = code+tests coding (as today).
  - Stage 4 rows = the panel loop (as today).
  - Stage 5 row = the contract phase when the contract is non-empty;
    otherwise ONE row `| 5 | SKIPPED | {ts} | folded: no contract |`.
  - Stage 6 row = the contract delta review when Stage 5 ran; otherwise
    `| 6 | SKIPPED | {ts} | folded: reviewed at Stage 4 |`.
  `Current Stage:` stays monotonic 3→4→5→6→7, so the push gate, resume
  logic, and stats lanes work unmodified. The maprun worker contract's
  boundary text ("STAGES 1 THROUGH 6 ONLY. Stop after Stage 6 (test
  review) passes", `maprun-dispatch.sh:240/264/365`) is re-worded to
  "stop once the Stage 6 row is written (SKIPPED or delta-review PASS)"
  — headless workers must not stall hunting for a test-review spawn
  that no longer exists. Stats gains one note line so
  post-fold Stage 4 durations are read as code+tests reviews when
  compared against pre-fold data.
- **Contract phase (sensitive changes only).** Unchanged detection
  (`grep -q '^## Security-Sensitive Fields'` after the final panel PASS).
  One test-coder spawn (the existing CONTRACT PHASE entry point) writes
  the contracted abuse tests; the Stage 3 exit gate re-runs (the
  contract tests must build and PASS before anyone reviews them); then
  ONE delta-scoped reviewer spawn verifies
  tamper→rejected→store-unchanged coverage for every contracted field
  (its existing Stage-6 abuse-coverage section, delta scope = the
  contract tests + security-record.md). Write the delta review's gate
  read as single-record wording — today's Stage 6 gate-read text is
  stale two-agent boilerplate ("From EACH record… either agent",
  `espalier.md:696/707`) and must not be copied forward. Non-sensitive
  happy path: no post-panel spawns at all.
- **Contract-phase FAIL routing (closes a pre-existing gap).** When the
  delta review fails:
  - fix touches **only test files** → contract loop: re-spawn the coder
    in contract mode, delta review again, under `max-test-rounds`.
  - fix must touch **any non-test file** (an abuse test failed because
    the CODE is vulnerable) → that is a security-relevant code change:
    route back to a **full Stage 4 panel round** under `max-code-rounds`
    (then contract phase re-verifies). Today's Stage 6 loop re-spawns the
    coder and re-reviews with the *reviewer only* — a code fix at the
    test stage never re-meets the security agent until the fingerprint at
    push. The fold's routing puts security eyes back on exactly the code
    changes most likely to need them. This is the one place v3 is
    strictly stronger than v0.22, not merely equal.
- **Certificate.** Written at the final panel PASS (covers code+tests);
  on a sensitive change, refreshed after the contract delta-review PASS
  (same `git add -A` + fingerprint command). The push gate is unchanged.
  Honest scope note: the full-lane skill currently only NAMES the
  certificate — the literal command and the `Base-Ref` anchor live in
  pipeline.md and the fix lane (espalier.md has zero `Base-Ref`
  occurrences and no Stage-6 refresh step) — so the fold writes the
  command into espalier.md for the first time; keep the three files
  textually identical.
- **Parallel sub-tasks (feat lane).** Disjointness now includes each
  sub-task's planned TEST files; shared test fixtures, helpers, or suite
  barrel files are overlap → serial. One added line in the existing
  Parallel Sub-Tasks rule.
- **Crash recovery (simpler than v0.22 — specify, don't inherit).** The
  fold has no part-files and no quarantine dir; tests are ordinary
  tracked files listed in coding-report.md. Resume rules: a resume into
  Stage 4 re-runs the exit gate then the panel (unchanged); a resume into
  Stage 5/6 with a certificate that no longer matches the tree means the
  contract spawn wrote tests before the crash — re-run contract
  detection, re-spawn the delta review, refresh the certificate. The
  v0.22 quarantine/orphan machinery is deleted with the mode that needed
  it (see §2.3).

### 2.2 Round accounting

- Code+test findings share ONE loop under `max-code-rounds` (they are one
  diff now). A FAIL round re-spawns the coder with combined findings;
  tests loop as ordinary files in the diff — **the quarantine machinery
  retires with the speculative dispatch** (risks #3/#4 of the v0.22
  register dissolve structurally: there is no unreviewed parallel
  work-in-progress to protect).
- `max-test-rounds` survives with a narrower meaning: the contract
  delta-review loop only (test-only fixes; code-touching fixes route to
  the panel per §2.1). Default stays 3. A code-touching contract fix
  that routes to the panel obeys the normal cap-before-respawn check:
  if `max-code-rounds` is already exhausted from the earlier panel
  loop, escalate immediately — no second counter, no cap reset. While
  re-scoping the key, print its literal read command once per lane
  skill (today it is only cross-referenced, never shown).

### 2.3 Config: one mode key, two modes (recommended)

```
# test-mode: folded | serial   (absent = folded)
```

- `folded` (default) — this track.
- `serial` — the v0.21 dispatch (write tests after the panel PASSES,
  review at Stage 6), kept as the simple conservative fallback. It is
  today's `speculative-tests: off` path, already maintained verbatim.

**DECIDED (owner, 2026-08-25): two modes — `speculative` is retired.**
The speculative dispatch exists to hide test-writing wall-clock behind
the panel; folded supersedes that saving and deletes the machinery
speculative needs (part-file protocol, quarantine-on-FAIL,
restore/reconcile, its crash-recovery rules — measured: 114 lines in
espalier.md + 75 in espalier-fix.md, which shares the handoff by
reference — plus agent-template exclusion lines in BOTH the reviewer and
security templates). Keeping all three modes would grow
the two largest templates; keeping two SHRINKS them net. A repo that
distrusts the fold wants the simple path, and `serial` is it — serial
has MORE author-checker separation than speculative (tests written after
review settles, no overlap, no reconcile), so no quality preference maps
to the retired mode; see §13.1 for the full quality argument.

**No config rewrite.** `.espalier-config` is user-owned ("never
auto-rewritten" — and migration #30 deliberately wrote no keys). The
orchestrator honors the legacy key when the new one is absent, the
`ESPALIER_CACHE_THRESHOLD_MS`/`HARNESS_CACHE_THRESHOLD_MS` precedent:

| Keys present | Behavior |
|---|---|
| `test-mode:` set | It wins (`folded` / `serial`) |
| only `speculative-tests: off` | `serial` |
| only `speculative-tests: on` / absent | `folded` (the successor default) |

Read with the word-key pattern (`grep '^test-mode:' … | awk '{print $2}'`,
like `hook-parallel-gates`), NOT the integer grep the round caps use.

### 2.4 Why quality is unaffected

- **Same reviewers, same checks, same sentinels.** Every check the Stage 6
  reviewer runs today is still run by the same agent role reading the same
  skill files — one round earlier for interface/failure-mode/tautology
  checks (with the code in view), and at the contract delta review for
  abuse coverage (where the contract exists). The whole-change verdict
  rule, freshness check, cap-before-respawn, and escalation protocol are
  copied, not altered.
- **The independence that matters is preserved.** The reviewer and
  security agents still never wrote the code OR the tests they judge. What
  the fold removes is only the *separate cold start* for the test author —
  the test author was already the same `harness-coder` role.
- **Tautology risk (coder certifies its own code with its own tests) is
  today's risk too** — the speculative test-coder already writes tests for
  code it just read uncritically. The defense is unchanged and now fires
  in round 1: the reviewer's tautology/meaningfulness checklist plus the
  mechanical `REGRESSION_VERIFIED` result (fix lane), which the panel now
  sees before its first verdict instead of at Stage 6.
- **Round-1 reviewer load is a real increase — the honest trade.**
  Today's Stage 6 review is TESTS ONLY ("your verdict comes from the
  tests you read", `espalier.md:670-672` — the reviewer never re-reads
  the source there). Folding makes one review carry code AND tests:
  more work per round-1 spawn, offset by the checks being strictly
  better-informed — the tautology/meaningfulness judgment finally runs
  with the code in view instead of code-blind. The eval/review combined
  fixture (§6.3) is the release gate for this trade, not a nice-to-have.
- **The abuse-test contract keeps its independent author-checker split:**
  security names the fields, the coder writes the tests, the reviewer
  delta-verifies coverage. Unchanged from v0.22.
- **Scope-escalation machinery is re-addressed, not dropped:** the fix
  lane's Stage 3 file/layer thresholds count non-test files (so folding
  tests in cannot trip them spuriously), and `TEST_SCOPE_INFLATION`
  keeps its own detector at the Stage 3 exit gate (§2.1).
- **One strict improvement:** contract-phase code fixes re-meet the
  security agent (§2.1 routing) — today they get reviewer-only
  re-review.
- **Escape hatch:** `test-mode: serial` restores the fully serial
  pre-v0.22 contract per repo.

### 2.5 Cost removed (honest math)

The fold trades an inline test-writing extension of the coder run for two
cold starts and a loop. Using the v0.22 benchmark's parameter set
(reviewer 300 / security 240 / test-coder 360 / test-review 180, feat):

- v0.22 happy path, non-sensitive:
  `coder 480 + max(300,240,360)=360 + Stage6 180 ≈ 1020s` agent-serial.
- folded: `coder 480+Δ + max(300,240)=300 ≈ 780s + Δ`, where Δ = writing
  the same tests inside a warm context that just wrote the code. Net =
  `240 − Δ`: at Δ≈150–240s that is **≈ 0 to −90s wall-clock** (−240s
  would require Δ=0; field Stage-6 tail median 235s says the realized
  tail sits at the small end of the model). Test execution moves from
  the Stage 5 gate to the Stage 3 exit gate — the same runs, earlier,
  adding nothing to this math.
- So the honest claim, matching `docs/deferred-items.md`'s framing: the
  fold's prize is **tokens and turns** — 2 cold-start context loads
  (agent file + rules + specs + pack, per spawn), one fixpoint loop's
  bookkeeping round-trips, and the Stage 4→5→6 handoff protocol — with
  wall-clock neutral-to-positive, never negative on the happy path.
  Sensitive changes keep the contract spawn + delta review they have
  today (net −1 spawn). Multi-round changes lose the quarantine/restore
  machinery cost entirely.

### 2.6 Files

All paths under `skills/espalier-init/` (full house-style paths — v2
convention; r2 normalizes v3's earlier bare-`templates/` shorthand):

| File | Change |
|---|---|
| `templates/skills/espalier.md` | Stage 3 prompt + exit-gate protocol (now incl. test execution); 2-agent Stage 4 dispatch; §2.1 stage-row rules; contract phase + delta review + FAIL routing replace the Stage 4→5 handoff and Stage 6 sections; certificate command + `Base-Ref` written into this file for the first time (§2.1 note); `test-mode` read + legacy-key table; `max-test-rounds` literal read printed once; speculative machinery deleted (two-mode shape); "Stage 4 Post-Review: Drift & Convention Index" ordering rule ("must finish BEFORE any Stage 6 spawn") re-verified against the delta-review spawn |
| `templates/skills/espalier-fix.md` | Same, plus regression verification (+ `REGRESSION_VERIFIED_SCOPE` record) + scope detectors into the Stage 3 exit gate; escalation-gate non-test-file counting; `## Escalation Gates` appendix headers (`### Stage 5 Gate (test scope)` / `### Stage 6 Gate (reviewer)`) re-labeled |
| `templates/pipeline.md` | Stage 3/5/6 descriptions; round-cap meanings; SKIPPED-row semantics; Stage 8 rollback rows re-pointed (`total_tests == 0 → Stage 5` becomes Stage 3 under folded); Stage 3 context-pack timing note (Track E') |
| `templates/agents/harness-coder.md` | Testing duty in the main task contract; speculative entry point retired (contract entry point stays — incl. dropping its "reconcile the restored speculative tests" line, `:246`); Test Scope Signal wording re-addressed to Stage 3 |
| `templates/agents/harness-reviewer.md` | Its own `SPECULATIVE TESTS IN FLIGHT:` exclusion line (`:34`) dropped; Stage-6 interface/tautology/failure-mode checklist folded into the Stage 4 review process; abuse-coverage section re-scoped to the contract delta review; delta contract gains contract-tests scope |
| `templates/agents/harness-security.md` | Speculative exclusion line dropped; one-line test-file scope stance |
| `templates/rules/production-standards.md` | "## Failure-Mode Tests (Stage 5 duty)" heading + "Stage 5 writes… P1 at Stage 6" re-pointed (Stage 3 duty; panel-round P1) — always-loaded rule file |
| `templates/rules/security-standards.md` | "Stage 5 writes them and Stage 6 blocks" re-pointed to contract phase + delta review |
| `templates/skills/espalier-coding.md` | Frontmatter "Stage 5 (testing mode)", "How This Skill Applies by Stage" section, "Fix rounds — Stage 4/6 re-spawns" re-pointed |
| `templates/skills/espalier-testing.md` | Two "Enforced at Stage 6" lines re-pointed (round-1 panel; contract delta review) |
| `hook-templates/maprun-dispatch.sh` | Worker-contract boundary text fold-aware (§2.1); worker findings-write duty (Track B') |
| `references/wiring.md` | Review-Rounds `test=0/{max-test-rounds}` denominator meaning + "Stage 2/4/6 gates" cap description |
| `hook-templates/pre-push-gate.sh` | User-facing messages "(Stage 4 code / Stage 6 test)" + "Complete code review and tests" re-worded (§7.2 already anchor-patches this file) |
| `hook-templates/espalier-stats.sh` | Stage 4 post-fold note line; grill-tier split (Track D'); adoption-nudge section (Track C') |

---

## 3. Track B' — Recurring-findings digest (map feedback loop)

**Data:** charted slices median 2 code rounds vs 0 uncharted; one defect
family recurred across ≥3 sibling slices, costing a ~900s panel round each
time it was rediscovered.

### 3.1 Change

0. **Make the source data exist (prerequisite — today it does not).**
   Stage History ROUND rows carry sentinel counts only
   (`| 4 | ROUND {n} FAIL | {ts} | reviewer: FAIL p0=2 p1=0; … |`); the
   finding text lives in review-record.md / security-record.md, which
   are OVERWRITTEN every round by design — at Completion there is
   nothing to extract. So the digest's source is written at the only
   moment it exists: the existing non-PASS round snapshot (both lane
   skills + pipeline.md) additionally appends, to the same row's notes,
   one finding line per failing agent — `{sev} {≤80-char summary}`
   (e.g. `P1 access.filter.update missing on job-lists update`). The
   notes column is free-form, so the stats parser (keyed on the leading
   stage integer) is unaffected. Side benefit: Track A field analysis
   stops needing manual record archaeology.
1. **Digest write**, when the change's `requirements.md` has
   `charted_from: maps/{map-slug}`: copy the Stage History finding
   lines (step 0) to a **per-change file** —
   `espalier/maps/{map-slug}/findings/{YYYY-MM-DD}-{type}-{change-slug}.md`
   (date prefix: lexical sort == chronological, the maps-dir
   convention — git preserves no mtimes, so "newest" must live in the
   name). One writer per file, written once, never appended by anyone
   else. Two triggers, one per lane shape:
   - **full lane:** at change Completion, riding the Completion
     commit — whose `git add` scope widens to include
     `espalier/maps/{map-slug}/` (today it stages only the change dir,
     and even the Spawned-Changes row update sits outside it; the
     widened scope carries both).
   - **maprun:** workers never reach Completion (hard stop at Stage 6),
     so the worker writes the findings file as its LAST act before
     writing the PASSED sentinel — the file rides the ticket branch and
     merges into the integration branch like any other one-writer file;
     later-dispatched workers branch off integration and inherit it
     before adoption.
   NOT a shared section in `map.md`: maprun runs up to N workers in
   parallel worktrees, and concurrent appends to one file would surface
   as add/add churn at every integration merge. One-file-per-writer is
   the repo's established answer twice over (the per-key convention
   files, and the map's own `tickets/` layout); reuse it. Bash-only.
2. **At slice adoption** (the FILED-skeleton adoption step — one shared
   mechanism: maprun workers run the same scan): fold every file under
   `espalier/maps/{map-slug}/findings/` (cap: newest 12 finding lines
   by filename date order, P0/P1 only — severity is in each line per
   step 0) into the adopted slice's `requirements.md` under
   `## Known failure patterns (from sibling slices)`. Adoption-time
   folding — not handoff-time — is what makes the loop work: at handoff
   no slice has run yet, so the digest is necessarily empty then; each
   later slice picks up everything its predecessors recorded. Honest
   limit: slices in flight concurrently cannot see each other's
   findings — the digest helps later-dispatched slices (maprun refills
   from the frontier as slots free; "waves" are a gloss, not a
   mechanism) and helps sequential `/espalier` slice runs fully.
3. The digest is **facts** (findings that actually fired, with slugs),
   never instructions to skip checks — the same contract as the context
   pack. Reviewer/security read it as "known hot spots": MORE scrutiny on
   those axes, not less; the scope-floor rule is unchanged.

### 3.2 Why quality is unaffected

Purely additive context. No gate, scope, or verdict rule changes. The
mechanism mirrors the existing convention-observation index (the
orchestrator aggregates what isolated fresh agents cannot see across
spawns) — applied to review findings within one map. A finding family that
keeps appearing is ALSO convention-promotion fuel through the existing
index; the digest does not replace that path.

### 3.3 Files

All under `skills/espalier-init/`:
`templates/skills/espalier-map.md` (findings/ dir in the storage
layout), `templates/skills/espalier.md` + `templates/skills/espalier-fix.md`
(round-snapshot finding lines; Completion write with widened commit
scope; adoption-time fold — note the fix lane has ZERO `charted_from`
logic today, so this is net-new there, not an extension),
`templates/pipeline.md` (ROUND-row notes format),
`templates/skills/espalier-maprun.md` (worker contract: findings write
before PASSED; dispatch folds the digest into the worktree's
requirements), `hook-templates/maprun-dispatch.sh` (the worker-contract
heredoc carries both duties).

---

## 4. Track C' — Adoption nudge for `hook-parallel-gates`

**Change:** two report-only surfaces, no auto-write (the v0.22 decision —
discovery proposes, human confirms — stands). Neither surface exists yet
— both are NEW logic, not one-liners (review find):

1. `espalier-stats.sh`: a new trailing advisory section — the script has
   no footer today and reads/writes no `## Commits` tables (header:
   "Writes NOTHING"); precedent for a conditional advisory is the
   convention-divergence note at its tail. Counting: no gated-push
   counter exists — the proxy is `| 7 |` rows in the `## Commits` tables
   across `espalier/changes/*/*/pipeline-state.md` (one row per Stage 7
   push; idempotent per SHA). When `hook-parallel-gates` is absent from
   `.espalier-config` AND that count ≥ 3:
   `hook-parallel-gates not set — if build/lint/tests are independent, opting in saves ~40% per gated push (see docs).`
2. `espalier-doctor`: same check as a plain advisory line in the report
   (doctor has no leveled INFO/WARN row vocabulary — its terms are
   FLAGS / mark_stale; this deliberately introduces no new level), with
   the init-time independence caveat text.

Migration #32's notes mention the opt-in for existing installs. Zero
behavior change; serial stays the default.

---

## 5. Track D' — Slice crispness: instrument, then gate

**Data caveat (§0.2):** `GRILLED=14/14, crisp=0` proves charted slices are
never crisp, but the recorded verdict does not split `light` from `full`,
so the depth of the problem is unmeasured. Two steps, in order:

1. **Instrument (this release):** the grill verdict recorded into
   pipeline-state.md becomes `GRILLED (light)` / `GRILLED (full)`. The
   skill knows its tier from Step 1 — but there is no single "existing
   verdict line" to touch: the write is split across the grill's return
   and TWO recording contracts (`espalier-requirements.md:58` spec lane,
   `espalier-fix.md:600` diagnosis lane); all three gain the tier word.
   The stats grep gains the split; its bare `GRILLED` substring match
   means old rows still count as GRILLED unchanged.
2. **Gate (this release, principled independent of the split):** the
   handoff scores each slice's drafted requirement with the grill's own
   Step-1 signal count — via a new **score-only entry point** in
   espalier-grill.md (Step 1 alone against a requirements draft, no
   questions asked; the existing three modes all run the full flow).
   Sequencing change the current handoff forces: today
   `status: CLEARED` is set as handoff step 1, BEFORE slices are even
   drafted — the gate reorders the handoff to draft-and-score first and
   flip CLEARED LAST. A slice that would score `full` tier is NOT
   filed — the map is not actually clear there; file the missing
   grilling/decision tickets instead and leave `status: IN_PROGRESS`
   (the status enum is `IN_PROGRESS | CLEARED | BUILT | ABANDONED` —
   there is no ACTIVE). Slices scoring `skip`/`light` file as today
   (`light` is fine — Stage 1's grill is cheap at that tier and slices
   legitimately add detail).

**Why quality is unaffected:** a strictness increase on the map lane's own
"cleared" claim, using the grill's existing deterministic scoring. It
moves grill work from N slice sessions back into the map (paid once),
which is the map lane's stated purpose.

**Files** (all under `skills/espalier-init/`):
`templates/skills/espalier-grill.md` (tier in verdict; new score-only
entry point), `templates/skills/espalier-map.md` (handoff reorder —
CLEARED flips last — + gate), `templates/skills/espalier-requirements.md`
+ `templates/skills/espalier-fix.md` (the two verdict-recording
contracts that actually land `GRILLED (tier)` in pipeline-state.md),
`hook-templates/espalier-stats.sh` (tier split).

---

## 6. Test plan

0. **Prerequisite:** security-eval judge recalibration per
   `eval/security/KNOWN-ISSUES.md` (deferred v0.22 item; v0.23 touches
   security-adjacent template text, which is the recorded trigger).
   Re-validate `judge-validation/`, re-key shadow-03, THEN baseline the
   v0.22.1 templates under the current model before any A/B attribution.
1. **Bootstrap suite** (276/276 at v0.22.1): Test 31 — fold markers
   (Stage 3 test duty in both lane skills + coder template; exit-gate
   test-execution line; 2-agent Stage 4 dispatch; SKIPPED-row rules;
   contract FAIL-routing text; certificate command present in
   espalier.md; `test-mode` + legacy-key table — one case per table
   row; round-snapshot finding-line format; date-prefixed findings
   filenames; worker findings-write line in the dispatch heredoc;
   digest write/fold blocks; crispness gate + CLEARED-last handoff
   order; grill score-only mode; tier-recording line in BOTH recording
   contracts; stats/doctor nudge lines; maprun boundary re-wording) +
   migration #32 apply / no-op / customized-skip triplet. **Test 30
   must be revised in the same commit** — it asserts the speculative
   markers the two-mode shape deletes; the break-set is enumerable:
   30a, 30b's speculative clause, 30d, 30i, and 30k's five speculative
   clauses (30c/e/f/g/h/l assert unrelated v0.22.0 features and
   survive); the broken assertions move to "absent in folded
   templates".
   Dash-leading grep anchors need `grep -qF --`. Migration probes must
   anchor on text that survives future rewrites (the #29 lesson):
   structural markers (`test-mode`, `## Known failure patterns`), not
   prose.
2. **Hooks suite** (160/160): stats — tier split counts; post-fold
   Stage 4 note; nudge line present/absent per config and per
   Stage-7-row count (the `| 7 |` Commits-row proxy); digest — one file
   per change, date-prefixed name, adoption fold caps at newest 12
   finding lines P0/P1, second write does not duplicate.
3. **Eval suites — new fixtures, not only re-runs:** `eval/coder` gains a
   folded-task fixture (code+tests in one task; judge scores test
   presence/quality alongside code); `eval/review` gains a combined
   code+tests review fixture (the reviewer's most-changed duty);
   `eval/security` re-runs after step 0; `eval/maprun` re-runs. Per the
   eval-baseline lesson: any regression → re-baseline OLD templates under
   today's model first.
4. **Manual live smoke** (the v0.22 recipe: real headless runs,
   `ESPALIER_UNATTENDED=1`, `ANTHROPIC_MODEL` pinned — never bare
   `claude -p` under a fable default): one feat + one fix covering:
   1-round non-sensitive (zero post-panel spawns; Stage 5/6 SKIPPED rows
   present; push gate passes on them); sensitive (contract + delta
   review + cert refresh); a forced Stage 4 FAIL (tests loop as ordinary
   diff; no quarantine dir appears); a forced contract-phase FAIL that
   touches code (routes to a FULL panel round — the §2.1 gap-closer);
   fix-lane regression verification re-running on a round-2 coder return
   with last-line-wins read; `test-mode: serial` equivalence to v0.21; a
   maprun worker writing its findings file before the PASSED sentinel;
   a charted slice adopting a non-empty digest; a handoff where one
   foggy slice is refused by the crispness gate (map stays
   IN_PROGRESS); one unattended fix-lane run end-to-end.
5. **Benchmark doc** (house style, like
   `docs/pipeline-speed-benchmark-v0.22.md`): measure the deterministic
   mechanisms (exit-gate protocol, digest fold) for real; model the
   agent-phase composition with §2.5's Δ made explicit; re-derive from
   Track A field data after release.

## 7. Rollout

1. Implement order: C' → E' → D' → B' → A' (smallest/independent first;
   the fold last — it touches the most template text).
2. `scripts/migrate-v0.22.1-to-v0.23.0.sh` (migration #32): pure-copy
   surfaces with backup-on-diff; the four substituted files
   (`harness-*.md`, `pre-push-gate.sh`) patched by section anchors, never
   wholesale. **No `.espalier-config` writes** (legacy-key honor makes
   the mapping runtime behavior, not a migration edit). No blanket
   `chmod +x` (tar preserves modes; the release gate rejects flipped
   template modes).
3. **Full migrate-skill checklist** (the twice-recurred gap): `NEEDS_*`
   detection + up-to-date check + Step 2 probe filename + Step 3/6 lists
   + frontmatter description + numbered entry (#32) + chain paragraph +
   count header + `plugin.json` + `marketplace.json` (2 version fields).
4. **Hygiene fixes riding the release** (found in this plan's review;
   all pre-existing, none fold-caused):
   - `pre-push-gate.sh:85` — anchor the `Current Stage:` read
     (`grep -E '^(- )?Current Stage:'`), the same fix the v0.22 field
     bug forced on the certificate lines; add a hooks-suite case;
   - `pre-push-gate.sh:319/:368` — `TEST_COUNT` takes the FIRST numeric
     match in test output; take the LAST (summary) match, in both the
     serial and parallel copies (they are kept in lockstep manually);
   - `espalier-stats.sh:66` — status distribution truncates multi-word
     labels (`$2` of `uniq -c`); dormant, fix while touching the file;
   - `index.html` — stale at v0.15.0 (nav pill + timeline, 7 releases
     behind): either add it to this checklist permanently or drop the
     version pill — owner's call at release time.
5. CHANGELOG + `docs/deferred-items.md` (fold entry closes;
   model-tiering entry is ADDED with its eval-parity trigger — review
   found it was never actually recorded there, only in the speed-plan
   docs) + this doc gains a Shipped section.
6. Suites + evals green → tag v0.23.0, GitHub release.

## 8. Track E' — Context pack before the approval gate (micro)

Assemble `context-pack.md` in the same orchestrator turn that issues the
Requirements Approval Gate prompt (it is paths/facts only and
approval-independent). On **Edit**, re-derive the pack before re-asking
when the edit changed the layer set. On **Abort**, the pack is dead weight
in an aborted change dir — harmless. Saves one orchestrator turn per run;
the pack remains an accelerator, never a gate.

**Files** (all under `skills/espalier-init/`):
`templates/skills/espalier.md` + `templates/skills/espalier-fix.md`
(pack assembly moves into the gate turn),
`templates/pipeline.md` (the Stage 3 "Context pack (first entry only)"
timing note).

## 9. Considered and rejected

- **Keeping `speculative` as a third `test-mode`.** DECIDED against
  (owner, 2026-08-25 — §13.1): folded supersedes its saving; three modes
  grow the two largest templates where two modes shrink them; `serial`
  is the conservative fallback a distrustful repo actually wants.
- **Retiring `max-test-rounds` entirely.** Rejected: the contract
  delta-review still needs its own cap; reusing `max-code-rounds` would
  let a contract loop eat code-round budget and vice versa.
- **Auto-writing `hook-parallel-gates: yes` when commands look
  independent.** Rejected (stands from v0.22): discovery proposes, the
  human confirms — a flaky parallel push gate is worse than a slow one.
- **Digest as instructions ("always add access.filter.update").**
  Rejected: rules belong in the rules files via the convention-promotion
  flow; the digest carries *observed findings*, and repeated families
  surface as promotion candidates through the existing index.
- **Digest as a shared `map.md` section.** Rejected for merge mechanics:
  parallel maprun workers appending one file guarantees integration
  conflicts; per-change files make conflicts structurally impossible
  (§3.1).
- **Blocking the map handoff on ANY grill signal.** Rejected: `light`
  slices are fine — Stage 1's grill exists and is cheap at that tier; the
  gate refuses only would-be-`full` slices.
- **Running the abuse-coverage check in the round-1 panel.** Impossible
  by construction — the contract is written by the security agent in that
  same round; the check runs where the contract exists (the delta
  review). Noted so nobody "optimizes" it forward later.
- **Extracting the digest from review-record.md at Completion.**
  Impossible: the records are overwritten every round by design, and
  ROUND rows carry only sentinel counts — at Completion the finding
  text no longer exists anywhere. Hence §3.1 step 0 captures it at the
  round snapshot, the only moment it exists.

## 10. Deferred (carried / new)

- **Model tiering per seat** — unchanged trigger: eval parity under the
  candidate model, `--model` pinned everywhere headless. (Housekeeping,
  §7.5: this entry exists only in the speed-plan docs today — ADD it to
  `docs/deferred-items.md`, where the plan previously claimed it
  lived.)
- **maprun Spawned-Changes COMPLETE flip** — pre-existing gap surfaced
  by the B' review: workers stop at Stage 6 and the master never
  updates map.md at merge, so Spawned-Changes rows stay stale for
  maprun-built maps. Natural home: the master's merge step. Take it in
  v0.23 only if it rides B' cheaply; otherwise it stays here.
- **Template size diet** (orchestrator skills at 50–60KB; agent files
  12–19KB read per spawn) — Track A' already deletes the speculative
  machinery (~100 lines/lane); go further only with token accounting
  showing it matters, and only with a loading contract for cold-path
  sections (crash recovery, escalation) that must bind at the moment
  they are needed.
- **Digest cross-map scope** (feeding findings between maps) — revisit if
  a second map on the same repo re-pays the first map's lessons.
- **Base-Ref verification cache across changes** — the per-round skip
  (§2.1) covers the hot path; a persistent cache is not worth state.

## 11. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|------------|--------|------------|
| 1 | Folded coder writes weaker tests than a dedicated pass | Medium | Medium | Same skill files; reviewer's test checklist mandatory in round 1; `REGRESSION_VERIFIED` mechanical and earlier; NEW eval/coder folded fixture gates the release; `test-mode: serial` escape |
| 2 | Longer coder runs hit context limits on big feats | Low-Med | Medium | Parallel sub-task decomposition splits big feats (now test-file-aware); fix lane small by routing rule; per-repo escape |
| 3 | Round-1 reviewer overloaded (code + tests in one verdict) | Medium | Medium | REAL increase (r2 correction — today's Stage 6 reviews tests ONLY; the reviewer never re-reads code there). Offset: checks run better-informed (code in view vs today's code-blind test review); the eval/review combined fixture GATES the release; escapes show as round-2 rates in Track A field data |
| 4 | Stage-number semantics drift breaks integer consumers | Low | High if unhandled | §2.1 stage-row rules: numbers retained, SKIPPED rows written, `Current Stage` monotonic; bootstrap Test 31 asserts the row text; push-gate + stats unmodified; maprun's parses (`maprun-dispatch.sh:357/379`, `maprun.py:399`) + its worker boundary re-wording covered by §2.1 + Test 31 |
| 5 | Fix-lane escalation thresholds mis-count folded test files | Certain if unhandled | Medium | §2.1 detectors: thresholds count non-test files; `TEST_SCOPE_INFLATION` keeps its own detector at the exit gate |
| 6 | Contract-phase FAIL loops bypass security on code fixes | Pre-existing | Medium | §2.1 routing sends code-touching fixes to a full panel round — strictly better than v0.22 |
| 7 | Digest biases the panel toward known families (tunnel vision) | Low | Medium | Digest wording = "additional hot spots, not a checklist ceiling"; scope-floor rule unchanged |
| 8 | Digest write/fold races under parallel maprun workers | Low | Low | One writer per findings file (the worker's own change slug); the write rides the ticket branch and merges like any one-writer file; fold is read-only at adoption; concurrent-slice blindness documented as a limit, not a bug |
| 9 | Crispness gate stalls legitimate handoffs | Low | Low | Refusal files concrete grilling tickets — forward motion; map stays ACTIVE; `light` passes |
| 10 | Migration #32 misses a machinery surface (3rd recurrence) | Medium | Medium | §7.3 checklist + Test 31 markers + Test 30 revision + anchor-patched substituted files |
| 11 | Security-eval FP gate fails and gets misattributed to the fold | High (known broken at baseline) | Medium | §6 step 0 prerequisite + baseline A/B before any attribution |
| 12 | Track A data incomparable across the fold boundary | Certain (semantics change) | Low | Stage numbers + SKIPPED rows keep lanes parseable; stats note line marks the boundary; compare within-era |
| 13 | Round-snapshot finding lines bloat pipeline-state.md or leak verbose findings | Low | Low | One line per failing agent per round, ≤80 chars, sev prefix; Test 31 asserts the format |
| 14 | Exit-gate test runs slow Stage 3 on big suites | Medium | Low-Med | Scope to the coder's listed test files where the runner supports path filtering; the full-suite fallback is what Stage 5's gate paid today anyway — moved earlier, not added |

## 12. Open questions (owner)

None — all resolved; see §13.

## 13. Decisions (resolved with the owner)

1. **`test-mode` is two modes: `folded` | `serial`; `speculative`
   retired** (2026-08-25). Quality basis: per-run output quality is
   identical under either shape for any repo on `folded` or `serial`;
   speculative occupies no point on the quality frontier (serial
   dominates it on author-checker separation, folded on speed + the
   contract-FAIL security routing). Run-execution quality favors two
   modes: fewer dispatch protocols = less orchestrator mode-mixing,
   denser test/eval coverage per kept path, and one fewer protocol
   variant for every future migration to patch consistently (the
   missed-surface bug already recurred twice with fewer surfaces).
   Encoded in §2.3; legacy-key mapping unchanged
   (`speculative-tests: on`/absent → `folded`, `off` → `serial`).
2. **`folded` rolls out to BOTH lanes in v0.23.0** (2026-08-25). One
   migration (#32), lanes stay protocol-symmetric, and the feat lane —
   where the field volume and token spend sit (35/42 changes on the
   field repo) — gets the saving immediately. The risk a fix-lane-first
   phasing would have covered is covered instead by the release gates
   and the escape hatch: the new eval/coder folded fixture and
   eval/review combined fixture gate the release BEFORE field exposure,
   and `test-mode: serial` is a per-repo instant rollback. Two-release
   phasing was rejected for its costs: two migrations, a release of
   lane-asymmetric protocol text (its own bug surface — the lanes share
   dispatch wording today), and thin fix-lane field volume to learn
   from (4-5 runs vs 35).
3. **Digest fold cap: newest 12 finding lines, P0/P1 only** (2026-08-25).
   Enough to carry a recurring defect family (the field repo's
   access-control family was mixed P0/P1) at ~10-15 lines per adopted
   slice; a cap keeps late slices in a big map from inheriting an
   ever-growing table and bounds the tunnel-vision surface. Encoded in
   §3.1 step 2.
4. **Crispness gate refuses would-be-`full` slices only** (2026-08-25).
   `light`/`skip` slices file as today — `light` is ≤3 cheap questions,
   legitimately Stage 1's job; no warn-noise added at handoff. Encoded
   in §5 step 2.

## 14. Revision history

- **r2 (2026-08-25)** — fixes from the claim-by-claim code review of r1:
  - §3.1 gains step 0 (round-snapshot finding lines — the digest's
    source data did not exist: ROUND rows carry counts only and the
    records are overwritten each round) and a maprun write trigger
    (workers never reach Completion, so the worker writes findings
    before its PASSED sentinel); findings filenames date-prefixed (no
    mtime to sort by); Completion commit scope widened.
  - §2.1 exit gate gains test execution (Stage 5's "tests pass" gate
    must not slide to the push hook) + `REGRESSION_VERIFIED_SCOPE`
    recording for the skip condition; contract phase re-runs the gate
    and gets single-record gate-read wording; certificate noted as
    net-new text for espalier.md; maprun worker boundary re-worded;
    maprun's two stage-integer parses added to the interface list.
  - §2.4 + risk #3 re-based on the verified fact that today's Stage 6
    reviews tests only (the "reviewer already re-reads the code"
    premise was wrong); the eval/review combined fixture is now a
    release gate.
  - §4 re-specced against real surfaces (stats has no footer, reads no
    Commits tables, counts nothing; doctor has no WARN level) — the
    `| 7 |` Commits-row proxy defined.
  - §5 fixed to IN_PROGRESS (no ACTIVE status exists), handoff
    reordered CLEARED-last, grill score-only entry point added, and the
    two verdict-recording contracts (espalier-requirements.md,
    espalier-fix.md) added to Files.
  - §2.5 net corrected to ≈0…−90s (was overstated as 0…−240s); §2.3
    line counts measured (114 + 75).
  - §2.6 files table grew 7 surfaces (production/security rules,
    espalier-coding, espalier-testing, maprun-dispatch, wiring.md,
    pre-push-gate message text) and normalized to full house-style
    paths; Track E' gained a Files list.
  - §2.2: contract-fix cap interplay stated (no second counter);
    `TEST_SCOPE_INFLATION` wording honestly marked as re-worded.
  - §6: Test 30 break-set enumerated (30a, 30b¹, 30d, 30i, 30k⁵);
    Test 31 marker list extended; smoke adds the maprun findings-write
    case.
  - §7 gains hygiene fixes (unanchored `Current Stage:` grep,
    `TEST_COUNT` first-match parse, stats `$2` truncation, index.html
    staleness); §10 gains the deferred-items housekeeping note and the
    maprun Spawned-Changes flip; §9 gains the Completion-extraction
    rejection; risks 13-14 added.
- **r1 (2026-08-24)** — initial plan from field data.
