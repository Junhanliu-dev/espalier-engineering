# Finding the unknowns — plan v1 (implemented as v0.27.0)

Status: **implemented as v0.27.0** on `feat/v0.26-turn-economy` (2026-09-14),
the commit after v0.26.0. Source article: Thariq (@trq212), "A Field Guide to
Fable: Finding Your Unknowns" (2026-07-03). Owner rules unchanged: the
quality invariant (`docs/pipeline-speed-plan-v4.md` §1), no hard budgets, every
lever with "why quality holds".

## 1. The article in one paragraph

The map (prompt, skills, context) is not the territory (the codebase, its real
constraints). The gap is *unknowns* — known/unknown × known/unknown — and with
Fable the quality of the work is bottlenecked by how well the user clarifies
them. Planning ahead is not enough: unknowns surface before, during and after
implementation. Techniques: **pre** — blind-spot pass, brainstorm/prototype,
interview (one question at a time, prioritising answers that change the
architecture), references (source code as the model), implementation plans
that lead with the decisions most likely to change; **during** —
`implementation-notes.md` with a Deviations section ("pick the conservative
option, log it, keep going"); **post** — explainer/pitch, quiz before merge.
Plus: give the model your starting point (experience, where you are in your
thinking). Warning both ways: too specific and the model follows instructions
when a pivot is right; too vague and it guesses from industry defaults.

## 2. Gap analysis against v0.26.0 (verified by reading the templates)

| Article technique | v0.26.0 | Verdict |
|---|---|---|
| Interview | grill Step 2: sequential, discriminating question from 3–5 private divergent builds, answer-from-codebase first, non-answer → Open Questions default, coverage guard, written back inline | **strong** — stricter than the article |
| Blind-spot pass (repo side) | grill Step 1.5: rules/wiki collisions, verified before raised, floors tier | **strong** |
| Blind-spot pass (user side: "teach me my unknown unknowns") | none; grill treats the user as an intent oracle only; no starting-point intake | **missing** |
| References (repo side) | pack `- Reference files:`, coding-spec `## Example`, coder step 4 | strong |
| References (user-named model) | no contract slot | **missing** |
| Brainstorm / prototype | map lane `prototype` / `research` tickets; single-session lane has none; Step 1.5 forbids brainstorming; the 3–5 candidates stay private | partial |
| Plan led by likely-to-change decisions | gate summary = goal + AC + grill resolutions; fixed template order | partial |
| Deviations during implementation | coder: `## Staleness Encountered` (doc vs code), `Notes` (blast radius, not built); no rule for territory-contradicts-contract; `grep deviat\|ambigu\|guess harness-coder.md` = 0 | **missing — the central tension** |
| Explainer / pitch | Completion: file/test/round counts; Stage 10: files, tests, verdicts | missing |
| Quiz | none | missing |
| HTML artifacts | none — git-tracked markdown audit chain by design | not a defect |

**The tension.** Espalier front-loads every unknown into Stage 1, then freezes
the contract; the coder builds to it and the panel checks against it. When the
territory contradicts a criterion at Stage 3 the coder could only comply
(build the wrong thing correctly) or hand off. The article's central claim —
"planning ahead isn't always enough" — is exactly where v0.26 was weakest.
And the article's warning about over-specific instructions applies to the
*task* spec (requirements.md), not the process spec: a prescriptive procedure
is fine; a frozen contract with no sanctioned exit is not.

## 3. Design principle: discover everywhere, resolve only at gates

Agents discover unknowns before, during and after implementation. Only humans
resolve them, at gates that already exist (approval gate, Stage 3 exit gate,
Stage 4 PASS, Stage 10). That is Espalier's own HITL rule — grill "never answer
your own questions", map "never close a prototype ticket on your own choice" —
applied to Stages 3–10. The contract stays frozen: the coder never edits
requirements.md. Every new mechanism reuses an existing pattern (report
section, sentinel line, gate question, panel verification, unattended
exception) and every new note is *verified by the panel*, never trusted.

Why quality holds: nothing auto-resolves, nothing skips a gate, every
deviation is reviewed at P1/P0 discipline, and the unattended path takes the
conservative option and records the question — it never hangs and never
widens scope.

## 4. What shipped (v0.27.0)

**Pre (Stage 1).** Grill: `familiarity: low` input (from the requester's words
only) → one more signal, floors `light`; Step 1.6 requester brief (≤ 7 cited
lines from rules / wiki / layer specs, explains, never proposes); candidates
shown at `full` tier; undecided APPROACH → `## Open Questions` `approach:` +
one `/espalier-map` line, never a grill brainstorm. Requirements: `## References`
(contract set; `req_shape_check`); step 5 passes familiarity.

**Gate (Stage 2).** Summary order: Technical Considerations' data-model /
interface / user-facing lines + every Open Questions default (ratified here)
→ goal + criteria → scope / References / grill resolutions. Pack: `- References:`.

**During (Stage 3) — the tension fix.** Coder "Territory vs Contract:
Deviations": Open-Questions default → apply + log; conservative option →
take + log; neither → `## Blocked` + `- BLOCKED-ON-REQUIREMENT:` sentinel.
`### Deviations` block carried forward; `You Must NOT` edit requirements.md.
Orchestrator (both lanes, `pipeline.md`): sentinel after HANDOFF → archive
`blocked-{n}`, `| 3 | BLOCKED {n} |`, ONE `AskUserQuestion` (conservative
option default → `open_question_append` ratified / change the criterion / abort;
unattended → default, `(default — revisit)`), continuation with `RESOLUTION:`.
Reviewer "Deviation Review" (step 9; `[deviation]` P1 for unlogged or
non-conservative; never resolves). Auditor step 5: relaxed control on a
sensitive field = P0. Panel prompts carry `DEVIATIONS:`.

**Stage 4 PASS.** `deviations_list` printed under the PASS line;
`deviations: {n}` in the PASSED row.

**Post (Stage 10).** `delivery_brief` → `delivery-brief.md` (assembled, never
authored); quiz offer (interactive, default no). Completion → deviations to
`requirements-notes.md` `## Settled for next time` + charted digest.

**Plumbing.** Helpers `_md_section`, `deviations_list`, `open_question_append`,
`delivery_brief`; stats `deviations:` row; check 69 `unknowns-channel`
(59/64/69); migration #37 (12 pure copies + anchored coder / reviewer /
security edits); migrate skill entry 37 + `NEEDS_V0270_PATCH` + floor;
Test 37 (+ Tests 35/36 chain #37); T24; evals `coder-09`, `rule-deviation-10`.

## 5. What the evals taught (2026-09-14)

The first draft defined conservative as "the narrower behaviour, the stricter
check, the smaller surface". Both new fixtures FAILED on it: the coder chose
`isTerminal` (CLOSED **or** CANCELLED) for a criterion that named CLOSED only
and argued "stricter", and the reviewer accepted the same argument ("rejects
more and writes less"). Both were following the rule as written — the rule was
wrong: "stricter" is a *scope* decision when it adds a product rule the human
never made. Rewritten as: conservative = the option that builds the LEAST the
contract did not name (behaviour inside the criterion's words, no new
dependency, no shared file reshaped), with "stricter" winning only on a
control on a sensitive field; test — would the human, reading the criterion,
be surprised? Re-run: coder-09 PASS (local `status === 'CLOSED'` check, one
Deviations entry), rule-deviation-10 PASS (`[deviation]` P1 naming the local
check). Suites: bootstrap 363/363, hooks 209/209.

## 6. Rejected / deferred

- Auto-resolving a BLOCKED criterion from the coder's own judgement — never;
  the human resolves, the unattended default is conservative and recorded.
- Brainstorming in the single-session lane — stays in the map lane; grill
  shows candidates, does not generate designs.
- Inferring `familiarity` from git history — words only (deferred-items).
- A scoring quiz that gates acceptance — the quiz is the human's check on
  themselves (deferred-items).
- HTML artifacts — the audit chain is the artifact.
