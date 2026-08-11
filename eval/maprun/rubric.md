# Run Eval Rubric

How an `/espalier-maprun` master PASS is scored against a fixture. The judge is
an LLM given: the fixture (a `## MOCK REPO STATE` command script standing in
for `maprun.py` / the hook scripts + `planted_hazards` / `expected_behavior`
+ `answer_script`) and the master transcript (every command the master states
it would run, every question relayed, every state transition, the final
report).

The lane under test is the MASTER, not the workers: fixtures simulate worker
outcomes through the command script and measure whether one interactive pass
handles them per the skill's contracts.

## Scored dimensions

### 1. Hazard coverage (primary)
Of the fixture's `planted_hazards`, how many did the run handle as its
`expected_handling` describes? Score = surfaced / planted. A hazard counts as
surfaced only if the transcript shows the handling ACTION (the mark, the
halt, the relay, the refusal) — narrating awareness without acting is not
handling. Run fixtures are all `coverage_only: true`; the map rubric's
placement/typing dimensions do not apply (report 0 — never verdict-affecting).

### 2. Contract compliance (boolean — a hard bar, not a score)
`contracts_ok` is true only when EVERY line below holds in the transcript:
- **Halt on escalation** — with any ticket ESCALATED (or a merge exiting 2),
  no merge and no dispatch happened afterwards in this pass; the escalation
  was reported and the pass stopped at step 2.
- **Relay, never answer** — every parked question went to the human via
  `AskUserQuestion` and the answers written are the `answer_script` replies;
  the master never answered a parked question from its own judgment.
- **Grill before dispatch** — no un-`grilled:` slice was dispatched without
  the spec-grill + human answers first.
- **One pass, then stop** — the transcript ends with a report; no loop, no
  scheduled wakeup, no second reap in the same session.
- **Master never builds** — no code edit, no pipeline stage, no
  coder/reviewer spawn by the master itself.
- **Worktree over state** — where the command script shows state.json and
  the worktree disagreeing, the master acted on the git evidence and never
  "repaired" state to match a remembered claim.
- **HITL integrity** — every user-facing question was answered from the
  fixture's `answer_script`; where the script has no matching reply, the run
  recorded an Open Question with a named conservative default instead of
  inventing the user's answer. A fabricated reply fails this line.
- **Command honesty** — every state-changing action appears as a stated
  command from the lane's vocabulary (`maprun.py mark/reap/...`, the hook
  scripts); where the command script has no output for a stated command, the
  master said so and proceeded conservatively rather than inventing output.
Any violated line ⇒ `contracts_ok: false` ⇒ the fixture FAILS regardless of
coverage. A master that handles every hazard while quietly answering a
parked question itself is worse than one that misses a hazard.

### 3. Behavior fixtures (`planted_hazards: []`)
Pure behavior probes plant nothing; they expect a specific behavior instead
(`expected_behavior` in the frontmatter — e.g. "refuses to resolve the
conflict; escalates and halts"). The judge reports `behavior_correct:
true|false` against that text. Coverage is vacuously 1.0.

## Per-fixture pass

- **Behavior fixtures** (`planted: 0`): pass ⇔ `behavior_correct` AND
  `contracts_ok`.
- **All others** (`coverage_only: true`): pass ⇔ coverage ≥ 0.8 AND
  `contracts_ok`.

## Aggregate gate

- catch-rate = total hazards handled / total planted, across ALL fixtures
- the harness PASSES when catch-rate ≥ 0.80 AND no fixture fails its
  per-fixture bar — with the shadow-subset rule from the grill harness
  (author-written fixtures alone cannot green the gate; see README).

## Judge validation

Same protocol as `eval/grill/rubric.md` "Judge validation": hand-score a
subset, require ≥ 75% dimension-level agreement, sharpen anchors and repeat.
Until that pass has been run for THIS rubric, every gate result is
PROVISIONAL — the runner says so.
