# Grill Blind-Spot Pass — rules/ + wiki/ Convention Cross-Check

> Follow-on to [`grill-integration-plan.md`](./grill-integration-plan.md). Adds a
> proactive blind-spot pass to the existing `espalier-grill` skill. Target: v0.12.0.

## 1. Goal

Grill today interrogates the Stage 1 input for **ambiguity in the requirement text**
and verifies stated premises against **raw code** (`espalier-grill.md` Step 2:
"Answer from the codebase first", "Verify premises"). It never consults the two
artifacts `/espalier-init` uniquely builds: `espalier/rules/` (the encoded
conventions) and `espalier/wiki/` (the map of the system).

Consequence: when a requirement, as written, will **violate a documented convention**
or **re-implement a capability the wiki already documents**, nothing catches it until
the Stage 4 reviewer — which costs a full rework round. The reviewer flags exactly
these convention violations; grill is positioned one stage earlier and holds the same
evidence, but doesn't look.

This is the repo's own thesis applied earlier: surface the unwritten-rule collision
*before* code is written, not after. It closes the one class of unknown that Espalier
is uniquely equipped to surface — a **known-known to the repo** (it's written in
`rules/`/`wiki/`) that is an **unknown-unknown to the user**.

## 2. Scope

**In:**
- New **Step 1.5 — blind-spot pass** in `espalier-grill.md`, running in both modes
  (`spec` and `diagnosis`), between Step 1 (score) and Step 2 (grill loop).
- Cross-check the requirement against `espalier/rules/*.md` and `espalier/wiki/*.md`;
  detect three collision classes (§4.2).
- Verify each candidate collision against code before raising it (anti-stale).
- Feed confirmed collisions into the existing Step 2 question loop as the sharpest
  discriminating questions; write resolutions back to `requirements.md`.
- Eval: new `collision-*` fixture class with mock `espalier/` context + a new rubric
  dimension (collision coverage) gated as go/no-go.
- Forward-only v0.11 → v0.12 migration (overwrites the grill skill template only).

**Out (deferred / explicitly not this):**
- Brainstorming / generating new design alternatives — this pass surfaces collisions
  with **existing documented conventions only**. Zero collisions → it adds nothing and
  stays silent. (The divergent-exploration axis is a deliberate non-goal for Espalier.)
- Changing the Stage 4 reviewer — overlap with it is intentional redundancy.
- Glossary / ADR — still deferred per `grill-integration-plan.md` §11.

## 3. Locked decisions this must respect (from grill-integration-plan §3)

| Existing invariant | How this preserves it |
|---|---|
| Grill = one skill, single methodology, two modes | Step 1.5 runs in both modes; no new skill |
| Depth is grill's **output**, not user input | Collision → tier floor is grill's own judgment (§4.4) |
| `--no-grill` / grill-off == **current behavior** | Pass is inside grill; `--no-grill` skips it too |
| Non-breaking | **Extended invariant: zero-collision == current behavior.** Silent when nothing collides |
| Read budget caps (T5) | Curated docs get a separate budget; code-verify draws the existing ≤8 (§4.3) |
| Eval harness is the un-gameable gate (§9) | New rubric dimension gates release (§5) |

## 4. Architecture

### 4.1 Placement

New **Step 1.5** in `espalier-grill.md`, after Step 1 (score ambiguity, choose depth)
and before Step 2 (grill loop). It can raise the tier and it seeds Step 2's questions,
so it must run between them.

### 4.2 The cross-check

Read the curated map — these are the artifacts the pass exists to consult, not source
code:

- `espalier/rules/*.md` — `coding-standards`, `engineering-structure`,
  `development-process`, `production-standards`, `security-standards`.
- `espalier/wiki/*.md` — `architecture`, `data-models`, `critical-paths`,
  `external-services`.

Detect three collision classes (added as new signal rows in Step 1's table):

| New signal | Means | Example |
|---|---|---|
| **Rule collision** | the requirement's implied approach contradicts a `rules/` convention | req "throw on invalid input" vs `coding-standards.md` "errors are `Result<T>`" |
| **Wiki duplication** | the requirement re-implements a capability `wiki/` documents | req "add a Stripe call" vs `external-services.md` already wrapping payments |
| **Unstated ripple** | the requirement touches a `wiki/` critical-path / data-model whose documented downstream is not in the requirement | req "add a field to Order" vs `critical-paths.md` showing Order flows to 3 consumers |

### 4.3 Verify before asserting (anti-stale)

`rules/`/`wiki/` can be stale — the repo already ships drift detection for exactly
this. Before raising a collision, confirm the cited convention still holds in code
(drawing from Step 2's existing ≤8 **code**-read budget). If the doc contradicts
current code, do **not** raise a false collision: emit the same drift signal
`/espalier-doctor` and the post-merge hook use, and skip. This mirrors `/espalier-ask`'s
"verify every doc claim against the actual code before answering."

Budget rule: reading the curated `rules/`/`wiki/` docs does **not** count against the
≤8 source-code budget (they are small, pre-digested, and are what the pass is for).
Scope wiki reads to the requirement's surface; skim rules always. Code-verification of
a candidate collision spends from the ≤8.

### 4.4 Feed the loop; floor the tier

- **Feed, don't replace.** Each confirmed collision becomes a Step 2 question — the
  sharpest kind, because it carries a concrete fork with a citation:
  > "Requirement implies X. `rules/coding-standards.md#error-handling` says this repo
  > returns `Result<T>` — reconcile to `Result<T>`, or is `throw` intended here (and
  > why)?"
  This slots straight into the existing ICLR "candidate-solutions → most discriminating
  question" mechanism (grill-integration-plan §13); the rule/wiki simply seeds a
  candidate the user didn't know existed. Always cite the exact
  `rules/<file>#section` or `wiki/<file>#section`.
- **Tier teeth (the one change with force).** A confirmed collision floors the tier at
  `light`. A `skip`-scored requirement (0–1 signals) that nonetheless collides with a
  documented convention must not skip — the collision is exactly the hidden-default
  grill exists to catch. `skip` + ≥1 confirmed collision → bump to `light`, loop for
  those collisions only. (Same shape as the existing user-driven tier bump; here the
  bump source is the cross-check.)

### 4.5 Write-back (Step 3 extension)

Resolved collisions land in `requirements.md` like any grilled decision:

| Collision resolved to | Lands as |
|---|---|
| follow the convention | `## Acceptance Criteria` line naming it ("errors returned as `Result<T>` per coding-standards") |
| reuse existing capability | `## Scope Definition` out-line ("reuse existing `PaymentClient`; do not add a new Stripe wrapper") |
| intentional deviation | `## Acceptance Criteria` line + one line of *why* the convention is overridden |
| unresolved (non-answer / unattended) | `## Open Questions` with the cited path + a conservative default |

Add a short `## Convention Notes` block citing each `rules/`/`wiki/` path consulted, so
the audit trail shows the cross-check ran even when it found nothing.

### 4.6 Verdict

Unchanged set (`GRILLED` / `SKIPPED: crisp` / `SKIPPED: non-interactive` /
`SKIPPED: --no-grill`). One refinement: `SKIPPED: crisp` now additionally requires
**zero confirmed collisions** — a crisp-but-colliding requirement returns `GRILLED`.

## 5. Eval (the go/no-go gate)

- **Fixture frontmatter** — add `planted_collisions:`, each entry
  `{doc: rules/coding-standards.md#error-handling, kind: rule-collision, resolves_to: "..."}`.
- **New fixture class `collision-*`** — e.g. `collision-01-throw-vs-result`,
  `collision-02-duplicate-payment-client`, `collision-03-order-field-ripple`. Each ships
  a mock `espalier/rules/` + `espalier/wiki/` context so the pass has something to read.
  **This is the real build cost** — the harness (`eval/grill/run.sh`) must mount the
  per-fixture curated context.
- **New rubric dimension — collision coverage:** of `planted_collisions`, how many did
  grill surface *with a correct citation*. Plus a **false-collision penalty**: raising a
  collision that isn't real (e.g. off a stale doc it should have drift-flagged) scores
  negative. Gate release on a collision-coverage threshold, same as the existing
  catch-rate gate (grill-integration-plan §9).
- **Anti-stale fixture** — one fixture whose mock wiki is deliberately stale vs its mock
  code; expected outcome is a **drift flag, not a raised collision**.
- **Regression guard** — the existing `light-*` / `full-*` / `skip-*` / `shadow-*`
  fixtures carry no `planted_collisions`, so they must score identically to today
  (proves the pass is silent on zero collision).

### 5.1 Measurement caveat (found while building the eval)

The collision fixtures **inline** their `rules/`/`wiki/` as a `## MOCK CONTEXT` block,
because the eval runs the skill through `claude -p` with no `espalier/` directory on disk.
An A/B on `collision-01` showed the **old** skill (no Step 1.5) *also* surfaced the
collision — because inlining hands the model the map and a capable model reasons over
context it is given, step or no step. So these fixtures **under-measure** Step 1.5's real
value; they prove the *new* behaviour is systematic (verify-before-raise, tier-floor,
citation, `## Convention Notes`), not that the old skill fails.

The true production gap is structural and is verified independently: the pre-change grill
skill references neither `espalier/rules/` nor `espalier/wiki/` (grep), so in a real
initialised project it never loads the conventions unprompted — Step 1.5 is what makes it
read them at all. A faithful A/B would use a real on-disk `espalier/` fixture project and
let each skill decide whether to read it; that is deferred (it needs a cwd-based harness
mode). Until then, the collision fixtures are a capability + regression check, not a clean
causal isolation of Step 1.5.

## 6. File inventory

**New:**
- `eval/grill/fixtures/collision-0{1,2,3}-*.md` + their mock `espalier/` context dirs.
- Anti-stale fixture + its mock context.

**Modified:**
- `skills/espalier-init/templates/skills/espalier-grill.md` — Step 1 signal table (3 new
  rows), new Step 1.5, Step 3 write-back + `## Convention Notes`, verdict note,
  anti-pattern list ("NEVER raise a collision without verifying it against code";
  "NEVER brainstorm new designs — existing conventions only").
- `eval/grill/run.sh` — mount per-fixture `rules/`/`wiki/` context.
- `eval/grill/rubric.md` — collision-coverage dimension + false-collision penalty.
- `docs/grill-integration-plan.md` §11 — record this as landed.

## 7. Migration

Forward-only v0.11 → v0.12 splice that overwrites
`espalier/skills/espalier-grill/SKILL.md` in existing installs (via `/espalier-migrate`).
Strictly non-breaking: the pass is silent when there are no collisions and fully skipped
under `--no-grill`, preserving the §3 "grill-off == current behavior" invariant
(extended to "zero-collision == current behavior"). No new files land in installs; the
`rules/`/`wiki/` it reads already exist from init.

## 8. Risks & mitigations

| Risk | Sev | Mitigation |
|---|---|---|
| False collisions from stale docs | HIGH | Verify against code before raising; drift-flag instead of raising (§4.3) |
| Read-budget blowout (9 docs + code verify) | MED | Curated docs on a separate budget; relevance-scoped wiki reads; code-verify capped by the existing ≤8 |
| Latency creep on every grill | MED | Curated docs are small/pre-digested; escalates to code reads only when a candidate collision is found |
| Goodhart — tier floor inflates grill rate | MED | Floor only on **code-confirmed** collisions; false-collision penalty in eval guards it |
| Scope creep into brainstorming | MED | Explicit scope guard: existing conventions only, silent on zero collision (§2 Out, §4 anti-patterns) |

## 9. Relationship to the Stage 4 reviewer

This pulls a slice of the reviewer's convention-check forward to Stage 1. The reviewer
still runs (defense in depth — the repo already values idempotent redundancy). The
difference: a collision caught at Stage 1 costs one **question** instead of a full
**rework round**. That is the "conventions on the first try, not the fifth" thesis
applied to the requirement itself.

## 10. Effort

Small–medium. The grill skill edit is ~30 lines. The real cost is the eval fixtures with
mock `rules/`/`wiki/` context, the harness mount, and the rubric dimension — roughly the
Phase A + Phase A2 shape of the original plan, scaled down (no new pipeline wiring; grill
is already invoked at Stage 1).

## 11. Success criteria — met (benchmark 2026-07-13)

Full `run.sh` over all 24 fixtures (20 existing + 4 new), new skill, `CLAUDE_RETRIES=4`:

```
catch-rate (all):        1.00  (gate >= 0.80)     [baseline 0.98]
catch-rate (shadow):     1.00  (trustworthy)      [baseline 0.97]
catch-rate (non-shadow): 1.00
fixture failures: 0     infra failures: 0     RESULT: PASS (exit 0)
```

- **Collision coverage** — `collision-01/02/03` each 1.00, PASS. New capability works.
- **Anti-stale** — `collision-04` stayed `skip` (coverage n/a), PASS: grill flagged the
  stale doc and raised no false collision. The depth-cal gate would have failed a
  false positive, so this is enforced, not incidental.
- **No regression** — every existing fixture PASS at coverage 1.00; none dropped. The four
  previously-red fixtures went green *because* of the issue-3/4 fixes, not the skill:
  `shadow-light-04` 0.75→1.00 (merge), `full-01`/`full-03`/`light-02` cleared via
  `coverage_only`. `RESULT` flipped FAIL→PASS because issues 1–4 are fixed.
- **Honest attribution** — the shadow gain (0.97→1.00) is a real fixture-bug fix
  (`shadow-light-04`), not gaming. The collision fixtures are non-shadow (author-written)
  — the weaker signal by run.sh's own discipline; a shadow collision fixture is future
  work. And per §5.1 the inlined-context fixtures under-measure the true (structural) gap.
