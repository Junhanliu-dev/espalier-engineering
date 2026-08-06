---
name: espalier-grill
description: Internal pipeline stage — invoked by /espalier and /espalier-fix Stage 1 (and by /espalier-map for decision tickets) with a mode and reqs_path; not for direct user invocation. Stress-test a requirement (spec), a bug diagnosis, or an open decision before coding — adaptive sequential interrogation that surfaces ambiguity, false premises, missing edge cases, and collisions with the project's own rules/wiki conventions
---

# Espalier Grill

## Purpose

Interrogate the Stage 1 input before any code is written. A vague requirement or an
unconfirmed diagnosis that passes Stage 1 is trusted by every later stage — and no
later gate audits it. Grill is that audit: it converts an under-specified input into
one a coding agent can execute without guessing.

Grill also closes the one blind spot a bare reading of the input cannot: a requirement
that will violate a convention the project already encoded in `espalier/rules/` or
re-implement something `espalier/wiki/` already documents. That collision is known to
the repo but unknown to the requester — Step 1.5 cross-references the input against the
project map and turns it into a question before any code is written.

Grill is invoked BY Stage 1 of `/espalier` and `/espalier-fix`, and by
`/espalier-map` when resolving a grilling ticket. It is not a slash command and
is never called directly by the user.

## Inputs (passed by the invoking stage)

| Input | Values |
|-------|--------|
| `mode` | `spec` (from `/espalier`) — interrogates the requirement |
| | `diagnosis` (from `/espalier-fix`) — interrogates the bug's root cause |
| | `decision` (from `/espalier-map`) — settles an open decision ticket |
| `input_text` | the requirement, bug description, or ticket question (+ map context) |
| `reqs_path` | path to the change's `requirements.md` (spec/diagnosis) or the ticket file (decision) |

### Decision-mode deltas (`mode=decision`)

A decision ticket inverts grill's usual input: the QUESTION arrives sharp (the
map already stated it precisely — that is what made it a ticket), and the
ambiguity lives in the answer space. Everything below applies with these deltas:

- **Step 1 (tiering):** skip the signal count — a decision ticket is never
  `skip`-crisp (an already-settled question would not be a ticket). Default
  tier `light` (≤ 3 questions); the user's read of the stakes bumps to `full`.
- **Step 1.5:** runs unchanged, against the CANDIDATE ANSWERS: before locking
  a decision, cross-check the leading candidates against `espalier/rules/` and
  `espalier/wiki/` — a candidate that collides with an encoded convention is
  surfaced as a citation-carrying question before it can win. Empty rules/wiki
  (greenfield Pass 1) → skip silently, per the existing contract.
- **Step 2:** the divergent-interpretations technique becomes divergent
  CANDIDATES: privately list 3–5 concrete, divergent answers to the ticket,
  ask the question that eliminates the most. Sequential, HITL — never answer
  the ticket yourself.
- **Step 3:** resolved decisions land in the ticket file's `## Resolution` —
  the answer, its rationale, citations from Step 1.5 — plus a one-line gist
  the caller appends to the map's Decisions-so-far. A non-answer records the
  conservative default in `## Resolution` marked `(default — revisit)`.
- **Verdict:** `GRILLED` or `SKIPPED: non-interactive` only.

## Process

Run Steps 0–3 in order (Step 1.5 sits between Step 1 and Step 2).

### Step 0 — Environment check

Decide whether a human can answer a grill question. Do NOT use a bare `[ -t 0 ]`
TTY test — inside Claude Code stdin has no TTY even when a user is right there,
so that test would skip the grill in normal interactive use (the bug this
closes). Use the explicit-signal helper instead:

```bash
. espalier/hooks/drift-helpers.sh
interactivity_mode        # -> "interactive" | "unattended"
```

Only an EXPLICIT unattended signal (`CI`, `ESPALIER_UNATTENDED`, `ESPALIER_LOOP`,
`ESPALIER_HEADLESS`) returns `unattended` — then do NOT grill (a question would
hang an unattended pipeline); return the verdict `SKIPPED: non-interactive`.
Otherwise you are interactive: grill normally. The real authority is the
orchestrator — if it can call `AskUserQuestion`, it is interactive regardless;
this check only governs the auto-skip for genuinely headless runs.

### Step 1 — Score ambiguity, choose depth

Do not judge ambiguity by feel. Count concrete ambiguity **signals** in `input_text`:

| Signal | Example |
|--------|---------|
| Undefined / overloaded term | "archive the order" — soft-delete? export? |
| Unstated actor or system | "send a notification" — to whom, over what channel? |
| Missing failure / error behaviour | nothing said about what happens when it fails |
| Hidden quantifier | "fast", "some", "large", "soon" — unmeasured |
| Unscoped edge case | the input describes only the happy path |
| (diagnosis) Unconfirmed cause | the cause is asserted, not evidenced |
| (diagnosis) Weak reproduction | "sometimes fails" — no exact, repeatable steps |
| Rule collision | the requirement's approach contradicts an `espalier/rules/` convention |
| Wiki duplication | the requirement re-implements a capability `espalier/wiki/` documents |
| Unstated ripple | the requirement touches a documented critical-path / data-model with unstated downstream |

The last three are not in `input_text` — they surface only by cross-referencing the
project's own map, which **Step 1.5** does. A collision confirmed there counts as a
signal and floors the tier at `light` (Step 1.5). Count the text signals now; let
Step 1.5 add any collision signals before you commit to a tier.

Map the count to a depth tier:

| Signals | Tier | Action |
|---------|------|--------|
| 0–1 | `skip` | Confirm understanding in one line. Return `SKIPPED: crisp`. Steps 2–3 do not run. |
| 2–4 | `light` | Ask ≤ 3 questions. |
| 5+ | `full` | Ask ≤ 7 questions. |

Tier anchors (calibrate against these):
- `skip` — "feat: bump the copyright year to 2026"
- `light` — "feat: add a CSV export button to the reports page"
- `full` — "make the dashboard faster and handle errors better"

State the chosen tier to the user in one line ("Well-specified — confirming, not
grilling") so a misjudgment is visible and they can correct it. If the user pushes
back on the tier ("this is more involved than that" / "don't bother grilling"), adopt
their tier and proceed — their read of the requirement's stakes overrides the signal
count. A `skip`→`light`/`full` bump runs Step 2; a bump down to `skip` returns
`SKIPPED: crisp`.

### Step 1.5 — Blind-spot pass (convention cross-check)

Runs in both modes, after Step 1, before Step 2. Its job is the collision the requester
could not have flagged — a rule they don't know exists, a capability the wiki already
documents. These are known to the repo but unknown to the requester, and no text-signal
count in Step 1 can catch them. This is the one class of unknown the project's own map
can surface and a bare reading of `input_text` cannot.

Read the project map — NOT source code:
- `espalier/rules/*.md` — the encoded conventions.
- `espalier/wiki/*.md` — architecture, data-models, critical-paths, external-services.

**If neither directory exists or both are empty, skip this step silently** — there is
nothing to cross-check (e.g. a repo not yet initialised by `/espalier-init`). No signal,
no tier change, no output. (This keeps grill's behaviour identical to before on any
input that has no map to collide with.)

Scan for three collision classes (the last three rows of Step 1's signal table):

| Class | You are looking for |
|-------|---------------------|
| Rule collision | the requirement's implied approach contradicts a `rules/` convention (e.g. `throw` where coding-standards mandates `Result<T>`) |
| Wiki duplication | the requirement re-implements a capability `wiki/` already documents (e.g. a new HTTP client where `external-services.md` documents one) |
| Unstated ripple | the requirement touches a `wiki/` critical-path or data-model whose documented downstream is not in the requirement (e.g. "add a field to Order" when `critical-paths.md` shows Order feeding three consumers) |

Reading `rules/`/`wiki/` does NOT count against Step 2's ≤ 8 code-read budget — they are
the curated map, and consulting them is the whole point. Scope wiki reads to the
requirement's surface; skim rules.

**Verify before you raise it.** A doc can be stale. Before treating a collision as real,
confirm the cited convention still holds in the current code (this DOES draw from the
≤ 8 code-read budget). If the doc contradicts the code, do not raise a false collision —
flag the doc as drifted instead, with the same helper `/espalier-ask` uses:

```bash
. espalier/hooks/drift-helpers.sh
mark_stale "espalier/<rules|wiki>/<file>.md" "$(git rev-parse HEAD)" "grill-verify: <one-line mismatch>"
```

Then move on — a stale doc is not a collision.

**What a confirmed collision does:**
- **Becomes a Step 2 question** — the sharpest kind, because it carries a concrete fork
  and a citation: *"Requirement implies X; `rules/coding-standards.md#error-handling`
  says this repo returns `Result<T>` — reconcile to `Result<T>`, or is `throw` intended
  here (and why)?"* Always cite the exact `rules/<file>#section` or `wiki/<file>#section`.
- **Floors the tier at `light`.** A `skip`-scored requirement (0–1 text signals) that
  nonetheless collides must not skip — the collision is exactly the hidden default grill
  exists to catch. `skip` + ≥ 1 confirmed collision → run Step 2 for the collisions alone.

**Scope guard.** Surface collisions with conventions that already exist in `rules/`/`wiki/`
only. Never propose new designs, generate alternatives, or brainstorm — that is not
grill's job, and it would fight the point of encoding conventions. Zero collisions → add
nothing and stay silent.

### Step 2 — Grill loop (tiers `light` and `full`)

Ask questions **sequentially** — one question, wait for the answer, let the answer
shape the next. Never batch.

**Before each question**, privately list 3–5 concrete, *divergent* ways the input
could still be built (`spec`) or explained (`diagnosis`). Ask the question whose
answer **eliminates the most of them**. This produces a sharp, non-obvious question
instead of a generic one.

> Example. "add export" → interpretations: {CSV of the current page, sync · CSV of
> the full dataset, async job · XLSX · JSON endpoint}. The discriminating question is
> "CSV of the current page, or the full dataset as an async job?" — not the generic
> "what format do you want?".

Rules for the loop:
- **Answer from the codebase first.** If a question is answerable by reading the code
  (does helper X exist? what does the current cancel flow do?), read it — do not ask
  the user. Budget: ≤ 8 file reads per session; if you would exceed it, ask instead.
- **Verify premises.** When the input assumes current behaviour ("extend the existing
  X", "the bug is in Y"), check the code and surface any contradiction immediately.
- **By mode** — `spec`: probe scope (in / out), false premises, edge cases, vague
  terms. `diagnosis`: probe the root cause (symptom vs. cause?), the reproduction,
  and whether the stated "expected behaviour" is actually correct.
- **Cover every counted signal.** Each ambiguity signal you counted in Step 1 must end
  either resolved by an answer or consciously ruled out of scope. Stop-early (below)
  applies only to questions *beyond* the counted signals — never leave a signal you
  counted unaddressed, because that is exactly the ambiguity grill exists to catch.
- **Handle a non-answer.** If the user replies "I don't know" / defers, do not silently
  drop the point: record it under `## Open Questions` in `requirements.md`, pick the
  safest default, and name that default. An invisible unresolved signal defeats the audit.
- **Stop early.** Stop the moment the next question's answer would not change the
  implementation — even before the tier cap (but after every counted signal is covered).

### Step 3 — Write the resolved input back

Write every resolved decision into `requirements.md` inline, as it is resolved — not
batched at the end:

| Mode | Where |
|------|-------|
| `spec` | concrete `## Acceptance Criteria` entries + explicit `## Scope Definition` in / out lines |
| `diagnosis` | populate `## Root Cause`; sharpen `## Reproduction` into exact, repeatable steps |

A **resolved collision** (Step 1.5) lands the same way, carrying its citation:

| Collision resolved to | Lands as |
|-----------------------|----------|
| follow the convention | a `## Acceptance Criteria` line naming it ("errors returned as `Result<T>` per `rules/coding-standards.md`") |
| reuse the existing capability | a `## Scope Definition` out-line ("reuse the documented `PaymentClient`; do not add a new HTTP client") |
| intentional deviation | a `## Acceptance Criteria` line + one line of *why* the convention is overridden |
| unresolved (non-answer / unattended) | an `## Open Questions` entry with the cited path + a conservative default |

When Step 1.5 ran, add a short `## Convention Notes` block to `requirements.md` listing
each `rules/`/`wiki/` path consulted and the collision verdict (raised / cleared / doc
flagged stale) — so the audit trail shows the cross-check ran even when it found nothing.

Every grilled decision must land as a verifiable line. Never leave a resolution only
in the conversation.

**Coverage guard (before returning `GRILLED`).** Re-read the Step 1 signal list. Every
signal you counted must now appear in `requirements.md` as a resolved criterion, a
scope-out line, or an `## Open Questions` entry. A counted signal with no written trace
is a coverage miss — ask it now (within the tier cap) or record it under
`## Open Questions` in requirements.md with a chosen conservative default and one
line of why (the same convention as the user-non-answer rule above) — the record
option is allowed ONLY when the tier's question cap is exhausted; never exceed
the cap. Then return.

## Verdict

Return ONE verdict to the invoking stage — it records this in `pipeline-state.md`:

| Verdict | When |
|---------|------|
| `GRILLED` | grill ran (`light` or `full`); `requirements.md` (or the decision ticket) updated |
| `SKIPPED: crisp` | spec/diagnosis only — tier was `skip`, input already well-specified, **and** Step 1.5 confirmed zero collisions. A crisp input that collides with a rule/wiki convention returns `GRILLED`, not this. Decision mode never returns it. |
| `SKIPPED: non-interactive` | unattended run (Step 0's interactivity_mode check) |
| `SKIPPED: --no-grill` | spec/diagnosis only — the invoking stage passed the opt-out flag |

## Anti-Patterns

- NEVER ask a question the codebase already answers.
- NEVER re-ask something already answered or inferable from a prior answer.
- NEVER ask a generic question ("what about edge cases?") — name the specific case.
- NEVER exceed the tier's question cap, or grill past the point where answers stop
  changing the implementation.
- NEVER leave a resolved decision only in the chat — it must be written to
  `requirements.md`.
- NEVER batch questions — sequential only.
- NEVER raise a collision (Step 1.5) without first verifying the cited `rules/`/`wiki/`
  claim against the current code — a stale doc gets `mark_stale`, not a question.
- NEVER brainstorm new designs or generate alternatives in Step 1.5 — it surfaces
  collisions with conventions that already exist in `rules/`/`wiki/`, nothing more.
