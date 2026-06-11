# Greenfield Eval Harness

Dev/QA infrastructure for the greenfield flow (`skills/espalier-init/
references/greenfield.md` + `/espalier-new`). NOT shipped to target
projects. Mitigates the v0.7 pre-mortem risks (`docs/greenfield-v2-plan.md`
§10): adaptive grill over-asking, wrong track routing, scaffolding without
confirmation, secrets in written files.

## Layout

```
eval/greenfield/
├── README.md             this file
├── rubric.md             how an interview run is scored
├── run.sh                interview-behavior runner (LLM judge)
├── scaffold-asserts.sh   scripted live scaffold checks per core track (no LLM)
└── fixtures/             interview scenarios with persona answer scripts
```

## Run

```bash
bash eval/greenfield/run.sh                    # interview behavior (LLM judge)
bash eval/greenfield/scaffold-asserts.sh all   # live scaffolds (network + toolchains)
bash eval/greenfield/scaffold-asserts.sh frontend backend   # subset
```

`run.sh` plays each fixture's `answer_script` as the simulated user against
the greenfield flow in EVAL MODE (dry-run — commands are described, never
executed), then LLM-judges the transcript against `rubric.md`. Exits
non-zero below the gate.

`scaffold-asserts.sh` actually scaffolds each requested core track in a
temp dir (the track file's §3 happy path with defaults), runs its §7
verification gate, and asserts: expected files exist, no secret-shaped
strings in any written file. Requires network + per-track toolchains
(npm/uv/flutter); skips tracks whose toolchain is missing, reporting SKIP.

## Fixture format

```yaml
---
fixture_id: vague-01-just-an-app
entry: espalier-new | init-gate
expected_track: <track or "n/a">
expected_max_rounds: <int>        # AskUserQuestion calls before proposal
expected_behaviors:               # judge checks each appeared
  - ...
forbidden_behaviors:              # judge checks each did NOT appear
  - ...
answer_script:
  - asks_about: <topic>
    reply: <text>
shadow: false
---
<the user's opening request, verbatim>
```

## Discipline

- Same rules as `eval/grill/`: grow toward 20+ fixtures, keep ~1/3
  `shadow: true` (authored from real sessions, not by the flow's author —
  the current seed set is all `shadow: false` and is NOT a valid shadow
  set), validate the judge against hand scores before trusting it.
- Run on every edit to `greenfield.md` or any `greenfield/*.md` track file.
- `scaffold-asserts.sh` is the regression net for scaffolder drift — when
  an ecosystem moves (a flag renamed, a template changed), this is what
  catches it. Run it before every release.
