# Pipeline Speed Plan v3 (v0.23.0) — Round Economy

**Constraint (unchanged from v0.21/v0.22):** reduce the wall-clock and token
cost of an `/espalier` feature run and an `/espalier-fix` run **without
impacting the quality of the code**. The quality machinery — separate
coder/reviewer/security agents, fresh panel round after every fix, per-round
`VERDICT:` sentinels, programmatic gates, round caps, the `Reviewed-Diff`
certificate, both human checkpoints — keeps its contract. Every track below
is either a dispatch restructuring whose review coverage is provably equal
(one place it is strictly stronger — see §2.4 last bullet), or an additive
context change that reduces *rounds*, never *scrutiny*.

**What is different about v3:** v0.21 and v0.22 were designed against a
modeled cost profile. v3 is designed against **field data** — a real v0.22.1
install (`portal.quota.com.au`, 42 changes: 35 feat / 4 fix / 3 refactor,
one BUILT map with 14 charted slices, heavy maprun usage) measured on
2026-08-24 via Track A (`espalier-stats.sh`) plus per-change Stage History
analysis.

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
→ Stage 3 exit gate: build+lint (+ fix-lane regression verification
   + scope detectors) — every coder return
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
  2. **fix lane:** the regression verification (fixed-tree scoped run +
     `Base-Ref` worktree run) — relocated here from the post-test-spawn
     slot. It RE-RUNS on every coder return (a fix round can rewrite the
     regression test); the `- REGRESSION_VERIFIED:` line in
     coding-report.md is re-appended per run and readers take the LAST
     line (`grep … | tail -1`, the sentinel pattern). Skip the worktree
     half when neither the regression test files nor `Base-Ref` changed
     since the last verified run (both are recorded facts). Net effect:
     the panel sees `REGRESSION_VERIFIED` **before round 1** — strictly
     earlier than today's Stage-6-only visibility, same
     `true|false|skipped` semantics;
  3. **scope detectors** (fix lane; relocated, not new): the Stage 3
     reactive escalation gate now counts **non-test files only** toward
     its `>5 files / >2 layers` thresholds — the fold moves test files
     into the Stage 3 diff, and counting them would trip the gate on
     work that was previously Stage 5's. Test scope keeps its OWN signal:
     the coder's `TEST_SCOPE_INFLATION` block (unchanged wording, now in
     coding-report.md) is grepped HERE on every return, firing the same
     late-escalation prompt. Neither signal is weakened; they are
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
  `Current Stage:` as an integer (≥ 7 to push), and `espalier-stats.sh`
  buckets durations by stage number. The fold keeps the numbers and
  re-points their meaning; it never removes a row:
  - Stage 3 rows = code+tests coding (as today).
  - Stage 4 rows = the panel loop (as today).
  - Stage 5 row = the contract phase when the contract is non-empty;
    otherwise ONE row `| 5 | SKIPPED | {ts} | folded: no contract |`.
  - Stage 6 row = the contract delta review when Stage 5 ran; otherwise
    `| 6 | SKIPPED | {ts} | folded: reviewed at Stage 4 |`.
  `Current Stage:` stays monotonic 3→4→5→6→7, so the push gate, resume
  logic, and stats lanes work unmodified. Stats gains one note line so
  post-fold Stage 4 durations are read as code+tests reviews when
  compared against pre-fold data.
- **Contract phase (sensitive changes only).** Unchanged detection
  (`grep -q '^## Security-Sensitive Fields'` after the final panel PASS).
  One test-coder spawn (the existing CONTRACT PHASE entry point) writes
  the contracted abuse tests; then ONE delta-scoped reviewer spawn
  verifies tamper→rejected→store-unchanged coverage for every contracted
  field (its existing Stage-6 abuse-coverage section, delta scope = the
  contract tests + security-record.md). Non-sensitive happy path: no
  post-panel spawns at all.
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
  the panel per §2.1). Default stays 3.

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
restore/reconcile, its crash-recovery rules — ~100 lines per lane skill
plus agent-template exclusion lines). Keeping all three modes would grow
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
  the same tests inside a warm context that just wrote the code. At
  Δ≈150–240s the net is **≈ 0 to −240s wall-clock** (field Stage-6 tail
  median 235s says the realized tail is at the small end of the model).
- So the honest claim, matching `docs/deferred-items.md`'s framing: the
  fold's prize is **tokens and turns** — 2 cold-start context loads
  (agent file + rules + specs + pack, per spawn), one fixpoint loop's
  bookkeeping round-trips, and the Stage 4→5→6 handoff protocol — with
  wall-clock neutral-to-positive, never negative on the happy path.
  Sensitive changes keep the contract spawn + delta review they have
  today (net −1 spawn). Multi-round changes lose the quarantine/restore
  machinery cost entirely.

### 2.6 Files

| File | Change |
|---|---|
| `templates/skills/espalier.md` | Stage 3 prompt + exit-gate protocol; 2-agent Stage 4 dispatch; §2.1 stage-row rules; contract phase + delta review + FAIL routing replace the Stage 4→5 handoff and Stage 6 sections; `test-mode` read + legacy-key table; speculative machinery deleted (two-mode shape) |
| `templates/skills/espalier-fix.md` | Same, plus regression verification + scope detectors into the Stage 3 exit gate; escalation-gate non-test-file counting |
| `templates/pipeline.md` | Stage 3/5/6 descriptions; round-cap meanings; SKIPPED-row semantics |
| `templates/agents/harness-coder.md` | Testing duty in the main task contract; speculative entry point retired (contract entry point stays); Test Scope Signal wording re-addressed to Stage 3 |
| `templates/agents/harness-reviewer.md` | Stage-6 interface/tautology/failure-mode checklist folded into the Stage 4 review process; abuse-coverage section re-scoped to the contract delta review; delta contract gains contract-tests scope |
| `templates/agents/harness-security.md` | Speculative exclusion line dropped; one-line test-file scope stance |
| `hook-templates/espalier-stats.sh` | Stage 4 post-fold note line; grill-tier split (Track D') |

---

## 3. Track B' — Recurring-findings digest (map feedback loop)

**Data:** charted slices median 2 code rounds vs 0 uncharted; one defect
family recurred across ≥3 sibling slices, costing a ~900s panel round each
time it was rediscovered.

### 3.1 Change

1. **At change Completion** (both lanes), when the change's
   `requirements.md` has `charted_from: maps/{map-slug}`: extract each
   Stage History ROUND row's finding one-liner and write them to a
   **per-change file** —
   `espalier/maps/{map-slug}/findings/{type}-{change-slug}.md` — one
   writer per file, created once at Completion, never appended by anyone
   else. NOT a shared section in `map.md`: maprun runs up to N workers in
   parallel worktrees, and concurrent appends to one file would surface
   as add/add churn at every integration merge. One-file-per-writer is
   the repo's established answer (the per-key convention files); reuse
   it. Bash-only, rides the same Completion commit as the Spawned-Changes
   row update.
2. **At slice adoption** (the FILED-skeleton adoption step in both the
   full lane and maprun's worker dispatch): fold every file under
   `espalier/maps/{map-slug}/findings/` (cap: newest 12 rows, P0/P1
   only) into the adopted slice's `requirements.md` under
   `## Known failure patterns (from sibling slices)`. Adoption-time
   folding — not handoff-time — is what makes the loop work: at handoff
   no slice has run yet, so the digest is necessarily empty then; each
   later slice picks up everything its predecessors recorded. Honest
   limit: maprun slices dispatched in the same parallel wave cannot see
   each other's findings — the digest helps wave N+1 learn from wave N,
   and helps sequential `/espalier` slice runs fully.
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

`templates/skills/espalier-map.md` (findings/ dir in the storage layout),
`templates/skills/espalier.md` + `espalier-fix.md` (Completion write;
adoption-time fold), `templates/skills/espalier-maprun.md` (worker
dispatch folds the digest into the worktree's requirements).

---

## 4. Track C' — Adoption nudge for `hook-parallel-gates`

**Change:** two report-only surfaces, no auto-write (the v0.22 decision —
discovery proposes, human confirms — stands):

1. `espalier-stats.sh`: one footer line when the key is absent and the
   `## Commits` tables show ≥ 3 gated pushes:
   `hook-parallel-gates not set — if build/lint/tests are independent, opting in saves ~40% per gated push (see docs).`
2. `espalier-doctor`: same check as a WARN-level row, with the init-time
   independence caveat text.

Migration #32's notes mention the opt-in for existing installs. Zero
behavior change; serial stays the default.

---

## 5. Track D' — Slice crispness: instrument, then gate

**Data caveat (§0.2):** `GRILLED=14/14, crisp=0` proves charted slices are
never crisp, but the recorded verdict does not split `light` from `full`,
so the depth of the problem is unmeasured. Two steps, in order:

1. **Instrument (this release):** the grill verdict recorded into
   pipeline-state.md becomes `GRILLED (light)` / `GRILLED (full)` (the
   skill already knows its tier; one word in the existing verdict line —
   the stats grep gains the split, old rows still count as GRILLED).
2. **Gate (this release, principled independent of the split):** the map
   CLEARED → FILED handoff scores each slice's drafted requirement with
   the grill's own Step-1 signal count. A slice that would score `full`
   tier is NOT filed — the map is not actually clear there; file the
   missing grilling/decision tickets instead and keep the map ACTIVE.
   Slices scoring `skip`/`light` file as today (`light` is fine — Stage
   1's grill is cheap at that tier and slices legitimately add detail).

**Why quality is unaffected:** a strictness increase on the map lane's own
"cleared" claim, using the grill's existing deterministic scoring. It
moves grill work from N slice sessions back into the map (paid once),
which is the map lane's stated purpose.

**Files:** `templates/skills/espalier-grill.md` (tier in verdict),
`templates/skills/espalier-map.md` (handoff gate),
`hook-templates/espalier-stats.sh` (tier split).

---

## 6. Test plan

0. **Prerequisite:** security-eval judge recalibration per
   `eval/security/KNOWN-ISSUES.md` (deferred v0.22 item; v0.23 touches
   security-adjacent template text, which is the recorded trigger).
   Re-validate `judge-validation/`, re-key shadow-03, THEN baseline the
   v0.22.1 templates under the current model before any A/B attribution.
1. **Bootstrap suite** (276/276 at v0.22.1): Test 31 — fold markers
   (Stage 3 test duty in both lane skills + coder template; 2-agent
   Stage 4 dispatch; SKIPPED-row rules; contract FAIL-routing text;
   `test-mode` + legacy-key table; digest write/fold blocks; crispness
   gate; tier-recording line; stats/doctor nudge lines) + migration #32
   apply / no-op / customized-skip triplet. **Test 30 must be revised in
   the same commit** — it asserts the speculative markers the two-mode
   shape deletes; its assertions move to "absent in folded templates".
   Dash-leading grep anchors need `grep -qF --`. Migration probes must
   anchor on text that survives future rewrites (the #29 lesson):
   structural markers (`test-mode`, `## Known failure patterns`), not
   prose.
2. **Hooks suite** (160/160): stats — tier split counts; post-fold
   Stage 4 note; nudge line present/absent per config and per gated-push
   count; digest — one file per change, adoption fold caps at 12 rows
   P0/P1, second Completion run does not duplicate.
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
   charted slice adopting a non-empty digest; a handoff where one foggy
   slice is refused by the crispness gate; one unattended fix-lane run
   end-to-end.
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
4. CHANGELOG + `docs/deferred-items.md` (fold entry closes; model-tiering
   entry stays with its eval-parity trigger) + this doc gains a Shipped
   section.
5. Suites + evals green → tag v0.23.0, GitHub release.

## 8. Track E' — Context pack before the approval gate (micro)

Assemble `context-pack.md` in the same orchestrator turn that issues the
Requirements Approval Gate prompt (it is paths/facts only and
approval-independent). On **Edit**, re-derive the pack before re-asking
when the edit changed the layer set. On **Abort**, the pack is dead weight
in an aborted change dir — harmless. Saves one orchestrator turn per run;
the pack remains an accelerator, never a gate.

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

## 10. Deferred (carried / new)

- **Model tiering per seat** — unchanged trigger: eval parity under the
  candidate model, `--model` pinned everywhere headless.
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
| 3 | Round-1 reviewer overloaded (code + tests in one verdict) | Medium | Medium | The Stage-6 checklist is additive lines, not a second diff — the reviewer already re-reads the code at Stage 6 today to judge the tests; eval/review combined fixture measures it; findings would surface as round-2 escapes in Track A field data |
| 4 | Stage-number semantics drift breaks integer consumers | Low | High if unhandled | §2.1 stage-row rules: numbers retained, SKIPPED rows written, `Current Stage` monotonic; bootstrap Test 31 asserts the row text; push-gate + stats unmodified |
| 5 | Fix-lane escalation thresholds mis-count folded test files | Certain if unhandled | Medium | §2.1 detectors: thresholds count non-test files; `TEST_SCOPE_INFLATION` keeps its own detector at the exit gate |
| 6 | Contract-phase FAIL loops bypass security on code fixes | Pre-existing | Medium | §2.1 routing sends code-touching fixes to a full panel round — strictly better than v0.22 |
| 7 | Digest biases the panel toward known families (tunnel vision) | Low | Medium | Digest wording = "additional hot spots, not a checklist ceiling"; scope-floor rule unchanged |
| 8 | Digest write/fold races under parallel maprun workers | Low | Low | One writer per findings file; fold is read-only at adoption; same-wave blindness documented as a limit, not a bug |
| 9 | Crispness gate stalls legitimate handoffs | Low | Low | Refusal files concrete grilling tickets — forward motion; map stays ACTIVE; `light` passes |
| 10 | Migration #32 misses a machinery surface (3rd recurrence) | Medium | Medium | §7.3 checklist + Test 31 markers + Test 30 revision + anchor-patched substituted files |
| 11 | Security-eval FP gate fails and gets misattributed to the fold | High (known broken at baseline) | Medium | §6 step 0 prerequisite + baseline A/B before any attribution |
| 12 | Track A data incomparable across the fold boundary | Certain (semantics change) | Low | Stage numbers + SKIPPED rows keep lanes parseable; stats note line marks the boundary; compare within-era |

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
3. **Digest fold cap: newest 12 rows, P0/P1 only** (2026-08-25).
   Enough to carry a recurring defect family (the field repo's
   access-control family was mixed P0/P1) at ~10-15 lines per adopted
   slice; a cap keeps late slices in a big map from inheriting an
   ever-growing table and bounds the tunnel-vision surface. Encoded in
   §3.1 step 2.
4. **Crispness gate refuses would-be-`full` slices only** (2026-08-25).
   `light`/`skip` slices file as today — `light` is ≤3 cheap questions,
   legitimately Stage 1's job; no warn-noise added at handoff. Encoded
   in §5 step 2.
