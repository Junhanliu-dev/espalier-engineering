# Map Eval Rubric

How an `/espalier-map` run is scored against a fixture. The judge is an LLM
given: the fixture (idea or mock map + `planted_decisions` /
`planted_collisions` / `expected_behavior` + `answer_script`) and the map
transcript (destination, tickets created or resolved, fog section, and every
stated action).

Two fixture families share one scoring shape:
- **chart fixtures** (`mode: chart`) — a loose idea in; a charted map out.
- **work fixtures** (`mode: work`) — a `## MOCK MAP` block in; one resolved
  ticket out.

## Scored dimensions

### 1. Coverage (primary)
Of the fixture's `planted_decisions`, how many did the run actually surface —
as a ticket OR as a Not-yet-specified fog line? Score = surfaced / planted.
A planted decision counts as surfaced only if a created ticket's Question, or
a fog line, would force that decision to be made before building. For work
fixtures the planted set is what the resolved ticket should surface
(follow-up tickets, graduated fog, resolution content) — same fraction.

### 2. Placement calibration (0–2)
Wayfinder's fog test: *can the question be stated precisely now?* Sharp →
ticket; not yet phrasable → fog. Each planted decision carries
`expected_placement: ticket|fog`.
- 2 — every surfaced decision landed where expected
- 1 — exactly one misplaced (fog pre-sliced into a ticket, or a sharp
  question left as fog)
- 0 — more than one misplaced

Score 0 when the fixture plants nothing this dimension can measure: behavior
fixtures (`planted_decisions: []`) and collision-only fixtures (planted
collisions carry no `expected_placement`). Same convention for dimension 3
(`expected_type`). Never verdict-affecting — those fixture families don't
gate placement/typing.

### 3. Type calibration (0–2)
Each `expected_placement: ticket` decision carries an `expected_type`
(`grilling|research|prototype|task`).
- 2 — every surfaced ticket typed as expected
- 1 — exactly one mistyped
- 0 — more than one mistyped, or ANY ticket that reads as an implementation
  step ("build the X") — the mis-type the upstream skill warns about hardest.

### 4. Contract compliance (boolean — a hard bar, not a score)
`contracts_ok` is true only when EVERY line below holds in the transcript:
- **Plan, don't do** — no file write, scaffold command, or code outside
  `espalier/maps/` was performed or claimed; a tempted build was deflected to
  a `task` ticket + approval window, or into the handoff.
- **Destination first** (chart) — the destination was named and confirmed
  before any ticket was created.
- **One ticket per session** (work) — exactly one non-research ticket
  resolved, then the session stopped.
- **HITL integrity** — every user-facing question was answered from the
  fixture's `answer_script`; where the script has no matching reply, the run
  recorded an Open Question with a named conservative default instead of
  inventing the user's answer. A fabricated reply fails this line.
- **Cap respected** — open tickets never exceeded `max-open-tickets`
  (fixtures state the cap; default 9).
Any violated line ⇒ `contracts_ok: false` ⇒ the fixture FAILS regardless of
coverage. An agent that surfaces everything while quietly building is worse
than one that misses a decision.

### 5. Behavior fixtures (`planted_decisions: []`)
No-fog exits, cap stops, and pure guard probes plant nothing; they expect a
specific behavior instead (`expected_behavior` in the frontmatter — e.g.
"refuses to chart; routes to /espalier", "stops at the cap and offers
narrow/split/raise"). The judge reports `behavior_correct: true|false`
against that text. Coverage is vacuously 1.0; placement/type are 0 by
definition and not gated.

### 6. Collision coverage (fixtures with `planted_collisions` only)
Decision-mode Step 1.5: of the planted rule/wiki collisions, how many were
surfaced **with the correct citation** before the decision locked? Same
counting rule as the grill rubric's dimension 6 — each planted collision is
one `planted`, each surfaced-with-citation one `surfaced`; the
false-collision penalty applies (deduct one surfaced-credit per invented
collision). Collision fixtures are `coverage_only: true` by nature.

## Per-fixture pass

- **Behavior fixtures** (`planted: 0`): pass ⇔ `behavior_correct` AND
  `contracts_ok`.
- **Coverage-only fixtures** (`coverage_only: true`): pass ⇔ coverage ≥ 0.8
  AND `contracts_ok`.
- **All others**: pass ⇔ coverage ≥ 0.8 AND placement ≥ 1 AND typing ≥ 1 AND
  `contracts_ok`.

## Aggregate gate

- catch-rate = total decisions surfaced / total planted, across ALL fixtures
  (collisions fold in exactly like decisions)
- the harness PASSES when catch-rate ≥ 0.80 AND no fixture fails its
  per-fixture bar — with the shadow-subset rule from the grill harness
  (author-written fixtures alone cannot green the gate; see README).

## Judge validation

Same protocol as `eval/grill/rubric.md` "Judge validation": hand-score a
subset, require ≥ 75% dimension-level agreement, sharpen anchors and repeat.
Until that pass has been run for THIS rubric, every gate result is
PROVISIONAL — the runner says so.
