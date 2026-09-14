# Pipeline Speed Plan v4 (v0.26.0) — Turn Economy

**Status (2026-09-14):** implemented as v0.26.0 on `feat/v0.26-turn-economy` — every track below (A–F) shipped; §8 applied outside espalier the same day. Draft r1 text follows unchanged; the expected effects in §10 stay estimates until `espalier-stats.sh` shows the field numbers.

**Constraint (unchanged since v0.21):** reduce the wall-clock of an
`/espalier` run and an `/espalier-fix` run **without touching the quality of
the code or its readability**. Separate coder / reviewer / security agents,
a fresh two-agent panel after every fix, per-round `VERDICT:` sentinels,
programmatic gates the orchestrator runs itself (a coder's "build: pass"
stays a claim), round caps, the `Reviewed-Diff` certificate, the
Requirements Approval Gate and Stage 10 acceptance all keep their contract.
The v0.25 owner rules bind too: no hard budget of any kind, no lever that
removes an input an agent uses, every lever carries a "why quality holds"
paragraph, every number is a design expectation until an eval or field
run proves it.

**What is different about v4:** v0.21–v0.23 took the stage machinery off
the serial chain (concurrent panel, delta rounds, the Stage 3/5 fold,
pre-authorized push). v0.25 managed context. The field data measured for
this plan (`docs/pipeline-field-report-2026-09-14.md`) says the remaining
minutes are **turns and spawns, not context and not gates**: a coder spawn
is 37 model turns at ~15s each (70% of its wall), model latency does not
grow with context size in the 50–300k range, the mechanical gates are
seconds, and the largest serial tail left on a sensitive change is a whole
extra coder spawn (the contract phase) that in 7 of 7 recent runs mostly
re-verified tests that already existed. So v4 spends turns and spawns:
fewer verification turns inside a coder, no contract-phase coder when the
contract is already covered, no bash the orchestrator retypes, and no
blocking question whose answer changes nothing.

---

## 0. Field evidence (what the data says)

Numbers from `docs/pipeline-field-report-2026-09-14.md` (48 changes since
2026-08-18 across portal.quota and portal.cne; portal.quota transcripts;
the v0.25 era on portal.quota is 3 feats + 4 fixes + 1 refactor, so every
v0.25-only number is thin and is hedged below).

### 0.1 A feature run, minute by minute

The one complete v0.25 feat (`cfd69823`, 3 serial sub-tasks, one fix
round, a 13-field contract; 148 min end to end):

| bucket | min | share |
|---|---:|---:|
| coder spawns (3 sub-tasks + fix round + contract coder) | 86 | 58% |
| panel rounds (544s + 317s) + contract delta review (313s) | 19.5 | 13% |
| orchestrator (Stage 1 reads + requirements ≈ 8, gates ≈ 8, Stage 7–10 ≈ 8, rest) | 31 | 21% |
| human asks (grill, approval, boundaries, delivery) | 11 | 7% |

Medians over all feats since 2026-08-18: Stage 3 1611s, Stage 4 936s
(all rounds), Stage 1 385s incl. grill asks, contract phase 357s +
review 252s. Fix lane: Stage 3 660s, Stage 4 605s, Stage 7 199s, Stage
5/6 skipped on 13 of 21.

### 0.2 Inside a coder spawn (v0.25, n=20)

- wall med 627s; 37 assistant turns; **15s per turn**; 70% of wall is
  model + harness with no tool pending; 18% is build/test/lint waits
  (380 calls, 6.1s avg); 10% is Edit latency (295 calls, 4.3s avg — the
  9 user-global Edit hooks in `~/.claude/settings.json`; espalier's two
  hooks measure 0.03s + 0.06s).
- **Model latency is flat across context**: 5.6s (50–100k) → 8.6s
  (150–200k) → 6.9s (250–300k) per message; ≈ 2.3–3.1s per 100 output
  tokens in every bucket. Turn count sets coder wall, not context size.
- 22 Bash calls per spawn, 18 of them build/test/lint by keyword. The
  transcripts show the shape: after each editing burst the coder runs
  `vitest`, host `tsc`, container `tsc`, `prettier --check` as **separate
  turns**, sometimes hunting for the tool first (which `prettier`, an
  `@esbuild` install) — 3–6 turns per verification cycle, 2–4 cycles per
  spawn.
- Reads are what they should be: pack, requirements, specs, reference
  files, the tests beside them. Not a lever.

### 0.3 The panel

Round wall is the reviewer (v0.25 med 241s, max 540s); security finishes
~35% earlier. Every round-1 FAIL in 48 changes came from the reviewer,
never security. 6 of 24 feats and 2 of 21 fixes needed a second round;
5 more rounds were the user choosing to fix P2/P3 advisories after a
PASS. Rounds are already the exception the v0.23 class sweep aimed for.

### 0.4 The contract phase is a second coder spawn that mostly verifies

On the changes that carry a security contract (folded era on portal.quota
since 2026-08-30: 6 of 16 changes; the rest wrote two SKIPPED rows), the
folded flow is: panel PASS → contract coder spawn (953s in `cfd69823`,
2995s once) → exit gate → delta-review spawn (~313s) → Stage 7. In 7 of 7
folded-era contract phases on portal.quota the auditor's contract already
carried per-field coverage marks (`status: SATISFIED by path:lines`,
"PROVEN", "already covered") — an improvised field convention — and in 2
of 7 the coder wrote no test at all. The coder's Security-Aware Coding
section already has it classify every client-supplied sensitive value and
record the control; nothing asks it to write the tamper → rejected →
store-unchanged test for those values at Stage 3, so the contract coder
re-discovers the change from a cold start to add one leg.

### 0.5 Orchestrator time

- Agent-return → next-spawn gap: coder→panel med 91s (exit gate + rows),
  coder→coder 58s, panel→contract coder 58s; 6–8 transitions per feat →
  6–10 min. The exit gate itself: 19s med, 80s p75 on portal.quota.
- Since 2026-08-25 the portal orchestrator retyped ≈ 620 KB of bash:
  the fix lane's regression verification (45 calls × 1.2 KB), the Stage 7
  commit table (57 × 1.6 KB), the certificate (89 × 1.4 KB), the drift
  parse (35 × 1.2 KB), the Stage 8.5 table (24 × 1.6 KB), by-hand
  build/lint (98 × 0.7 KB). At the measured output rate that is 2–3
  minutes of pure typing per session — and every retype is a chance to
  mis-anchor a grep (the v0.22 certificate find).
- `exit_gate` runs the FULL suites on portal.quota (65–108s each) because
  a two-workspace `run_tests` body is not scopable; a scoped run is ~5s.

### 0.6 Human waits

12–15% of session time is a pending `AskUserQuestion`. Two of those per
run are the v0.25 stage-boundary offers (after approval, after the Stage
4 PASS): 2 of 69 changes took one; measured cost 0–3 min when the human is
present, unbounded when not (the offer stalls Stages 5–10 that push
pre-authorization was meant to let run).

---

## 1. Goals & Non-Goals

### Goals

- Remove the contract-phase coder spawn on the path where the contract is
  already covered, and make that path the common one — with the Stage 6
  enforcement (every contracted field has a passing tamper → rejected →
  store-unchanged test, a gap is a P0) byte-for-byte unchanged.
- Cut verification turns inside a coder spawn by giving it the gate's own
  one-call verifier instead of a hunt for commands, without removing any
  check it runs today.
- Move every bash block the orchestrator retypes into a tested helper.
- Remove the two blocking boundary questions from the happy path while
  keeping the fresh-session option.
- Scope the exit gate's test run on multi-workspace and `uv`/`poetry`
  repos the way it is already scoped on single-command repos.

### Non-Goals

- Any change to what the reviewer or security agent reads, any budget,
  any cap on findings or turns, any model tiering (deferred, unchanged
  trigger).
- Skipping or weakening the orchestrator's exit gate or the pre-push hook
  because a coder reported green (claim-vs-gate stands).
- Speculative dispatch of any post-panel spawn (decided against in
  v0.23; the panel-PASS → contract order stays).
- Forcing parallel sub-task dispatch: overlap and dependency (the
  portal's frontend codegen reads the backend schema) decide it, as now.
- Splitting `espalier-fix.md` for speed: §0.2 shows latency does not
  track context, so the deferred router split keeps its v0.25 trigger.

---

## 2. Track A — Contract coverage first (both lanes)

### 2.1 Change

Three edits, one routing rule:

1. **Coder, Stage 3 TESTS duty.** `harness-coder.md` → Security-Aware
   Coding already ends "Record each sensitive field you handled and the
   control you applied". Add: for each such field, write its abuse test
   now — the same shape the contract will name (tamper the value → assert
   rejected → assert the store unchanged; the recipe in
   `espalier-security/SKILL.md`), listed under `- Test files:`. The
   spawn-prompt TESTS lines in both lanes gain one clause: "…and the
   abuse test for every client-supplied sensitive value you classified;
   the Stage 4 auditor's contract may still name more." The exclusion
   "everything EXCEPT contracted abuse tests" becomes "the contract may
   add fields; it never removes the duty".
2. **Auditor, contract entry.** `harness-security.md` → Abuse-Test
   Contract: each entry gains one line, `covered_by: {path:line of the
   test that tampers, asserts rejection, asserts the store unchanged} |
   none`. The auditor already reads the test files in the diff (secrets /
   live-endpoint / fixture scope); this line is where a test it saw
   proves an entry. It is a **routing fact, never a verdict**: the delta
   review still proves every entry itself. `contract_extract` copies the
   line unchanged.
3. **Orchestrator, Stage 5.** `stages/5-6-contract.md` (and the fix
   lane's Stage 5/6 section, which points at it): after `contract_extract`,
   `contract_gaps DIR` (new helper) prints the entries whose `covered_by`
   is `none` or missing.
   - **No gaps** → skip the coder: write `| 5 | PASSED | {ts} | folded:
     contract covered at Stage 3 ({n} entries) |` and spawn the Stage 6
     delta review exactly as today. Zero post-panel coder spawns.
   - **Gaps** → the CONTRACT PHASE coder spawn as today, its prompt
     naming only the gap entries ("write the abuse test for each entry
     listed under GAPS; the others are covered — do not rewrite them"),
     then the exit gate, then the delta review.
   - The delta review is unchanged: every contracted field, tamper →
     rejected → store unchanged, a gap is a P0 back to the contract
     phase (which then always spawns the coder). A wrong `covered_by`
     costs one delta-review FAIL and lands on today's path; a missing one
     costs today's coder spawn.

### 2.2 Why quality holds (and where it rises)

- The enforcement point does not move: Stage 6's per-field proof is the
  gate, as in v0.23; §9 of the v3 plan ("the abuse-coverage check cannot
  run in the round-1 panel") still holds — the check runs where the
  contract exists.
- The auditor's `covered_by` line cannot pass anything: it only decides
  whether a coder is spawned before the reviewer looks. Its failure modes
  both degrade to the current flow.
- The abuse tests written at Stage 3 are reviewed by the round-1 panel as
  ordinary test files (assertions meaningful, not tautological) — one
  more reading than a contract-phase test gets today (it is read only by
  the delta reviewer).
- The coder writes the abuse test while the sensitive field and its
  control are in front of it, instead of a cold spawn reconstructing the
  change 20 minutes later. Field notes already show the contract coder
  spending its time locating coverage ("1 of 2 entries already fully
  covered", "5 already covered", "join leg covered by existing suite").

### 2.3 Expected effect (design expectation)

- Covered path: −(contract coder + its exit gate) ≈ **−10 to −18 min** per
  contracted feat on portal.quota (953s and 1430s medians in §0.1/§0.4;
  the 50-min case gone). The delta review (~5 min) stays.
- Gap path: unchanged wall (the coder writes fewer tests, but the spawn's
  fixed cost dominates).
- Stage 3 grows by the abuse tests' edits — a few turns per sensitive
  field, inside a spawn that already has the field in view.
- Fix lane: same shape on the fixes that carry a contract (2 of the 7
  folded-era contract phases were fixes).

### 2.4 Files

| File | Change |
|---|---|
| `templates/agents/harness-coder.md` | Security-Aware Coding: abuse test per classified field; TESTS duty wording; Contract entry point: GAPS list |
| `templates/agents/harness-security.md` | contract entry `covered_by:` line + the routing-fact sentence |
| `templates/skills/espalier-stages/3-coding.md`, `espalier-fix.md` Stage 3 | TESTS prompt clause |
| `templates/skills/espalier-stages/5-6-contract.md`, `espalier-fix.md` Stage 5/6, `pipeline.md` Stage 5 | `contract_gaps` routing, the new PASSED row wording |
| `templates/agents/modes/stage6-abuse-coverage.md` | one sentence: a `covered_by` line is a claim to verify, never evidence |
| `hook-templates/drift-helpers.sh` | `contract_gaps DIR` (awk over security-contract.md; prints entries lacking `covered_by:` with a path) |
| `templates/skills/espalier-testing.md`, `espalier-security.md` | the Stage 3 duty sentence |
| `hook-templates/espalier-stats.sh` | contract phases split: covered-at-Stage-3 vs coder-spawned (the number that tells whether A works) |

---

## 3. Track B — One-call verification for the coder

### 3.1 Change

`exit_gate DIR [test files…]` already runs the installed gate's
`run_build` / `run_lint` bodies as two concurrent jobs and the discovered
test command scoped to the files given. Let the coder use it:

- `harness-coder.md` → You Must NOT "Skip the build/lint check" gains its
  procedure: **verify in one call** — `. espalier/hooks/drift-helpers.sh
  && exit_gate espalier/changes/{type}/{slug} {your test files}` — the
  same commands the orchestrator's gate will run, build and lint
  concurrent, tests scoped to the files you name, per-job logs on
  failure. One turn per verification cycle instead of a runner, a
  type-check and a formatter in separate turns; never hunt for a command
  the pack already names. Exit `2`/`3` (customised or placeholder gate)
  → run the pack's Build / Lint / Tests lines yourself, in one bash call.
  Under `PARALLEL DISPATCH` nothing changes: no build, no tests, no gate.
- The context pack's `- Build: … · Lint: … · Tests: …` line gains the
  helper call as its first item so the coder sees the one-liner before
  the raw commands.

### 3.2 Why quality holds

The coder runs the same three checks, sourced from the one place they are
defined (`pre-push-gate.sh`), instead of an approximation of them
(host-side `tsc` where the gate builds inside the container; a
`prettier` the repo does not configure). The orchestrator's exit gate
still runs after the return — it is the gate; this only makes the
coder's own check the same shape, so fewer returns come back red.

### 3.3 Expected effect (design expectation)

Verification turns per spawn from ~18 Bash calls to ~4–8: at 15s per
turn, **−2 to −3 min per coder spawn** (≈ 20–30% of a 627s median spawn),
times 1.3 spawns + fix rounds + contract coders per change. Exit-gate
reds from command mismatch (1 hand-gated red in the v0.25 sample) fall.

### 3.4 Files

`templates/agents/harness-coder.md`; `stages/3-coding.md` pack format;
`espalier-fix.md` pack paragraph; `templates/skills/espalier-coding.md`
("Before Writing Code" pointer sentence).

---

## 4. Track C — Session-boundary preference at the approval gate

### 4.1 Change

The two stage-boundary offers (after approval; after the Stage 4 PASS —
serial mode after Stage 6) become ONE question asked inside the
Requirements Approval Gate's `AskUserQuestion` call, next to the push
target:

```
Session boundaries (state is on disk at each; nothing depends on this):
  1. Continue here at both (default)
  2. Stop after approval for a fresh session
  3. Stop after the Stage 4 PASS for a fresh session
  4. Stop at both
```

Recorded as `- Session-Boundary: none | after-2 | after-4 | both` in
pipeline-state.md. At each boundary the orchestrator reads the line
instead of asking: `after-2`/`both` → write `Current Stage: 3`, print the
two commands, stop (as today's option 2); otherwise continue. Unattended
runs skip the question, as they skip the offers today. When the gate call
already carries four questions (approve + push + pre-flight 3b + deploy
3c), ask this one right after — the rare case keeps today's shape.

### 4.2 Why quality holds

The v0.25 text itself: "Nothing depends on the answer: the state is
already on disk and Session Resumption is unchanged." The mechanism (a
fresh session running Stages 3–10 with the stage file at the top of its
context) is kept; only the moment the human is asked moves to a turn
where they are already answering.

### 4.3 Expected effect

−2 blocking asks per feat and per fix. Measured 0–3 min each when the
human is at the keyboard; the real saving is the run that no longer
stalls at the Stage 4 PASS when they are not (push was pre-authorized for
exactly that case).

### 4.4 Files

`stages/1-2-requirements.md` (gate step 3d; step 5 becomes a read),
`stages/4-panel.md` step 5, `stages/5-6-contract.md` serial Stage 6 PASS,
`espalier-fix.md` gate + Stage 4 step 4, `pipeline.md` Stage 2 line,
`espalier-stats.sh` (RESUMED rows unchanged; add the preference mix).

---

## 5. Track D — Helpers for what the orchestrator retypes

### 5.1 Change

Move the six blocks in §0.5 into `drift-helpers.sh` (or
`lookup-helpers.sh` where they already source it), each replacing a
verbatim block in a skill with a one-line call; the block's text moves
into the helper unchanged in effect:

| helper | replaces | lane |
|---|---|---|
| `regression_verify DIR "REG_RUN" file…` | the fix lane's Stage 3 exit-gate regression block (handoff guard, harness-error classifier, fixed-tree run, Base-Ref worktree run, `REGRESSION_VERIFIED` + `_SCOPE` lines, cache) | fix |
| `record_commits TYPE SLUG` | Stage 7 Commit Recording (`## Commits` table, `_cache_append`) | both |
| `certificate_write DIR` | `git add -A` + `Reviewed-Diff` line (anchored overwrite) | both |
| `drift_index TYPE SLUG` | Stage 4 Post-Review parse + `mark_stale` + `convention_drift*` lines | both |
| `stage85_drift TYPE SLUG` | the Stage 8.5 notify table | feat |
| `backlink_all SLUG` | 7.2 (reads the `caused_by` YAML itself — the one part the orchestrator still parses by hand) | fix |

The skills keep a one-paragraph description of what each helper does and
its exit codes, as `exit_gate` has today; the bash bodies leave the
templates. `test-hooks.sh` gains a section per helper (the regression
verifier: true / false-on-fixed / false-on-prefix / skipped-harness-error
/ cached / handoff-guard; the certificate: anchored overwrite of a
prose-quoted `Reviewed-Diff:`; commit recording: idempotent rows,
missing Base-Ref fallback).

### 5.2 Why quality holds (and rises)

Byte-identical file effects by construction (the tests assert them); the
grep anchors the v0.22 field find fixed are now in one tested place
instead of retyped from a template into every session. The orchestrator
emits ~1.2–1.6 KB less per call; the skills shrink by the same lines
(context is the by-product).

### 5.3 Expected effect

≈ 620 KB of typed bash per 26 sessions → one-liners: **−2 to −3 min per
session** of output plus the failed-retype rework it removes (the "exit
gate by hand", "certificate recomputed" rows in the v0.25 sample).

---

## 6. Track E — exit gate: scope more shapes, start tests when build is green

### 6.1 Change (`drift-helpers.sh` only)

1. `_gate_scoped_cmd`: accept a multi-line `run_tests` body whose every
   line is `(cd WS && CMD) || return 1` (or `cd WS && CMD`, one per
   line): scope each line to the listed test files under `WS/`, drop a
   workspace with no listed files, keep the `|| return 1` chain. Any
   other multi-line shape → full suite, as now. Add runner rows for
   `uv run pytest`, `poetry run pytest`, `pnpm exec vitest run`,
   `npx vitest run` inside a `cd`.
2. `exit_gate`: `wait "$pid_b"` → if green, run the scoped tests → then
   `wait "$pid_l"`. Output lines print in the same order (build, lint,
   tests) after all three finish; exit codes and messages unchanged.

### 6.2 Why quality holds

Scoping rule unchanged ("scoped to the report's listed test files where
the runner supports path filtering, full suite where it does not") —
this widens "where it does" to the monorepo and `uv` shapes the field
repos actually have; the pre-push hook still runs every suite. Lint has
no ordering dependency on tests (both read the tree the build just
compiled); the gate's verdict is the same conjunction.

### 6.3 Expected effect

portal.quota: two full suites (65–108s each) → two ~5s scoped runs on
every coder return: **−1 to −3 min per return** (exit gate p75 80s →
~25s). Lint overlap: seconds on portal (no lint), up to the lint's length
on `ocv-dashboard` / `z-memo-palace`.

---

## 7. Track F — pre-push hook: build ∥ lint by default

`gate_build_section` and `gate_lint_section` run serially unless
`hook-parallel-gates: yes`. v0.25's `exit_gate` already runs build and
lint concurrently by default on every coder return, so the pipeline has
accepted that pair as independent; the hook can do the same without the
opt-in, keeping tests after a green build. `hook-parallel-gates: yes`
keeps meaning the three-way overlap the human confirmed at init (the
v0.22 decision "discovery proposes, human confirms" stays for tests).
Effect: −lint time per push; nothing on portal.quota (no lint), the
frontend `npm run lint` on `ocv-dashboard`. `test-hooks.sh` T5 gains the
default-concurrent assertion (both failures still print, build first).

The stats nudge for the three-way opt-in stays; on portal.quota the
discovered build and test commands are plausibly independent
(vitest does not read the build output) — an owner call, not a template
one.

---

## 8. Outside espalier (owner's harness) — recorded, not shipped

- **Edit hook latency is 10% of coder wall** (4.3s per Edit, 64s per
  spawn): the user-global `typescript-preflight` (80s timeout),
  `compiler-in-the-loop` (60s) and `post-tool-use-tracker` (240s) hooks
  fire on every harness Edit. The exit gate already type-checks the
  result; a harness subagent gains nothing from a per-edit compile. Scoping
  those hooks to non-harness sessions (a matcher on the agent type, or a
  `CLAUDE_AGENT_TYPE` guard inside the hook) is the single largest
  per-spawn saving on the table and needs no espalier change.
- **API 403 (`oauth_org_not_allowed`) killed a reviewer** and cost 54 min
  until the re-spawn: the completion check re-spawns once, but only when
  the orchestrator's next turn runs. Not a template item.

---

## 9. Considered and rejected

- **Scoping the exit gate's BUILD to touched workspaces.** The portal's
  frontend codegen reads the backend schema: a backend-only change can
  break the frontend build. The build stays whole-tree.
- **Running tests concurrently with the build by default.** Compiled
  stacks need the build output; only the init-time confirmation
  (`hook-parallel-gates`) knows. Track F keeps that line.
- **Skipping the orchestrator's exit gate when the coder's own
  `exit_gate` call was green.** Claim-vs-gate: the coder's call is a
  convenience, the orchestrator's is the gate (same reasoning that keeps
  the pre-push hook re-verifying a certificate-matching tree).
- **Spawning the contract coder speculatively on the round-1 security
  record.** Decided against in v0.23 (round economy) and it breaks "a
  fix is never the last action before the gate". Track A removes the
  spawn instead of moving it.
- **Letting the security agent's `covered_by` line satisfy Stage 6.**
  Never — it is a routing fact; the delta review proves every field.
- **Dropping the boundary offers.** The fresh-session mechanism is the
  v0.25 context lever; Track C keeps it and moves the question.
- **Splitting `espalier-fix.md` for speed.** Latency is flat across
  context (§0.2); the split keeps its context-report trigger.
- **Parallel sub-tasks by default.** Overlap and dependency decide; the
  field serial choices were dependency-driven (codegen).
- **Warm reviewers, skipping security on non-intersecting rounds,
  general grill batching, pre-authorizing Stage 10.** All stay rejected
  (v0.21/v0.22 decisions).
- **A turn cap or a verification-call cap on the coder.** No budgets;
  Track B gives the coder a better tool, not a limit.

---

## 10. Expected effect summary (design expectations, per run, portal.quota shape)

| track | feat (contracted, 1 spawn, 1 round) | fix (no contract) |
|---|---|---|
| A contract coverage first | −10 to −18 min (covered path; ~40% of folded-era changes carry a contract) | same when a contract exists |
| B one-call verification | −2 to −3 min per coder spawn | same |
| C boundary preference | −2 asks (0–3 min present; unbounded absent) | same |
| D helpers | −2 to −3 min per session | larger share (regression block ×2–4 per fix) |
| E scoped gate | −1 to −3 min per coder return | same |
| F hook build ∥ lint | ~0 on portal; lint length elsewhere | same |
| owner hooks (§8) | −1 min per coder spawn | same |

On the `cfd69823` shape (148 min) the sum of A–E is roughly 25–35 min;
on a fix with no contract, 5–8 min of a ~25-min run. Both are estimates
to be measured with `espalier-stats.sh` stage durations and the
transcript scripts in this session's scratchpad after one release in the
field — not claims.

---

## 11. Proof, tests, migration (surfaces)

- **Evals:** `eval/coder` (Stage 3 abuse tests present for classified
  fields; no regression on the seed set), `eval/security` (contract
  entries carry `covered_by`, catch rate and FP gate unchanged —
  baseline A/B under the same model first, per the v0.22 lesson),
  `eval/review` (delta review still files the P0 on a `covered_by` line
  that lies — a new fixture).
- **`test-hooks.sh`:** Track D helpers (one section each), Track E
  scoping shapes (two-workspace body, `uv run pytest`, lint-overlap
  ordering), Track F default-concurrent hook sections.
- **`test-bootstrap.sh`:** marker checks for the new template lines
  (checks 67+, totals `N_CLAUDE/N_CODEX/N_ALL` +1 each), Test 36 for
  migration #36 (apply / no-op / customised-skip on a real v0.25.1
  install from `git show v0.25.1:`).
- **Migration #36** `scripts/migrate-v0.25.1-to-v0.26.0.sh`: pure copies
  for helpers, stage files, modes; `swap_block` for the agent and skill
  paragraphs; probes on markers that survive future rewrites (the
  v0.22.1 chain lesson); `/espalier-migrate` Step 1 supersession floor
  entry for v0.26.0 plus the four machinery surfaces (detection, probe,
  Step 3/6 lists, header).
- **Docs:** CHANGELOG 0.26.0, README command table unchanged,
  `docs/usage-cost.md` (stats line), `deferred-items.md` (parallel
  contract-phase dispatch trigger re-worded for the gap path).

---

## 12. Open questions (owner) — resolved 2026-09-14

1. `covered_by` is emitted by the security auditor (routing fact; the delta
   review proves every entry).
2. The boundary preference is one question inside the approval-gate call
   (`- Session-Boundary:`); both boundaries read it.
3. The coder's `exit_gate` call writes nothing under `espalier/` (confirmed:
   the helper reads the report for its file list and writes only its temp
   dir).
4. The user-global Edit hooks are guarded off for `harness-*` subagents
   (`~/.claude/hooks/skip-for-harness.sh`, keyed on the hook input's
   `agent_type`).

### As asked

1. Track A's `covered_by` line: emitted by the security auditor (reads
   tests it already has in scope; free wall-clock since the reviewer is
   the long pole) — or should the coder's report list "abuse tests by
   field" and the auditor only confirm? Plan takes the auditor: its
   contract is the source of truth for the field list.
2. Track C: fold the boundary question into the gate call (plan) or drop
   the Stage 4 offer entirely and keep only the post-approval one?
3. Track B: should the coder's `exit_gate` call also archive nothing and
   never write under `espalier/`? (It does not today — the helper reads
   the report only for the file list; confirmed.)
4. §8: are the user-global Edit hooks meant to run inside harness
   spawns? If not, scoping them is a one-line settings change.
