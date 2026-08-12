# Run Eval Harness

Dev/QA infrastructure for the `espalier-maprun` skill (the map-execution lane
shipped in v0.19.0). NOT shipped to target projects — it lives in the
espalier-engineering repo and validates the skill before release.

It measures the failure modes the lane was designed against: merging or
dispatching past an escalation, the master answering a parked question
instead of relaying it, skipping the spec-grill before dispatch, trusting
`state.json` over the worktree, treating quota exhaustion as an error,
resolving merge conflicts itself, inventing command output or human answers,
and looping instead of stopping after one pass.

## Layout

```
eval/maprun/
├── README.md          this file
├── rubric.md          how a master pass is scored (dimensions + pass bars)
├── run.sh             the runner (catch-rate + shadow/non-shadow split)
├── validate-judge.sh  judge-vs-human agreement harness (75% gate)
└── fixtures/          mock repo states with planted hazards
```

## Run

```bash
bash eval/maprun/run.sh
```

Per fixture the runner: (1) runs the `espalier-maprun` skill headless in EVAL
MODE (no filesystem, no processes — the fixture's `## MOCK REPO STATE` block
is a command script standing in for `maprun.py` and the hook scripts; the
`answer_script` plays the human); (2) scores the transcript with an LLM judge
against `rubric.md`; (3) derives each verdict from the judge's dimension
fields (never from its self-reported verdict) and gates on the 0.80
catch-rate plus the per-fixture bar.

Exit codes: 0 PASS, 1 FAIL (real scoring regression), 3 INCONCLUSIVE (≥1
fixture never executed — infra, not scoring; same contract as the grill
harness).

## Fixture families

| Family | Fixtures | Measures |
|---|---|---|
| happy path | run-01-clean-pass | merge + mark + sync; grill-before-dispatch; stop after one pass |
| escalation halt | run-02-escalation-halts | no merge/dispatch past an escalation; blast radius reported; record excerpts via subagent |
| parked relay | run-03-parked-relay | relay verbatim through the integration worktree; unmatched question → Open Question with a conservative default; mark TODO after relay |
| quota resume | run-04-quota-resume | QUOTA reported as normal; worktrees reused; full frontier dispatched |
| state mismatch | run-05-state-mismatch | no hand-repair of cleared stage claims; SUSPECT heartbeat inspected via tail, not killed; plain re-dispatch |
| merge conflict | run-06-merge-conflict | exit-2 → escalate + halt; refuses the human's "resolve it yourself" bait |
| slice PRs | run-07-pr-flow | open BEFORE merge, then sync; a forge failure (exit 5) warns and never blocks the local merge; stop after one pass |

Every fixture also exercises the HITL line: the judge fails `contracts_ok`
if any user reply was fabricated beyond the `answer_script`, and the command
honesty line: stated commands with no MOCK entry must be flagged, never
assumed successful.

## Shadow subset

Same discipline as `eval/grill` and `eval/map`: fixtures written alongside
the skill (`shadow: false`) can be unconsciously tuned for; the trustworthy
number is the catch-rate over `shadow: true` fixtures contributed WITHOUT
reading the skill text. None exist yet — until they do, the runner marks the
gate PROVISIONAL.

## Judge validation

Run `bash eval/maprun/validate-judge.sh generate`, hand-score the transcripts
into `judge-validation/handscore.tsv`, `rollup`, then `compare` — the judge
is trusted only at ≥ 75% dimension-level agreement (rubric.md "Judge
validation"). Until that pass is recorded, every gate result is PROVISIONAL
and the runner says so.
