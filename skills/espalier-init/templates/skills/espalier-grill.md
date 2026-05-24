---
name: espalier-grill
description: Stress-test a requirement (spec) or a bug diagnosis before coding — adaptive sequential interrogation that surfaces ambiguity, false premises, and missing edge cases at Stage 1
---

# Espalier Grill

## Purpose

Interrogate the Stage 1 input before any code is written. A vague requirement or an
unconfirmed diagnosis that passes Stage 1 is trusted by every later stage — and no
later gate audits it. Grill is that audit: it converts an under-specified input into
one a coding agent can execute without guessing.

Grill is invoked BY Stage 1 of `/espalier` and `/espalier-fix`. It is not a slash
command and is never called directly by the user.

## Inputs (passed by the invoking stage)

| Input | Values |
|-------|--------|
| `mode` | `spec` (from `/espalier`) — interrogates the requirement |
| | `diagnosis` (from `/espalier-fix`) — interrogates the bug's root cause |
| `input_text` | the requirement or bug description |
| `reqs_path` | path to the change's `requirements.md` |

## Process

Run Steps 0–3 in order.

### Step 0 — Environment check

```bash
[ -t 0 ] || echo "non-interactive"
```

If the session is non-interactive (no TTY), do NOT grill — a grill question would
hang an unattended pipeline. Return the verdict `SKIPPED: non-interactive`.

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
grilling") so a misjudgment is visible and they can correct it.

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
- **Stop early.** Stop the moment the next question's answer would not change the
  implementation — even before the tier cap.

### Step 3 — Write the resolved input back

Write every resolved decision into `requirements.md` inline, as it is resolved — not
batched at the end:

| Mode | Where |
|------|-------|
| `spec` | concrete `## Acceptance Criteria` entries + explicit `## Scope Definition` in / out lines |
| `diagnosis` | populate `## Root Cause`; sharpen `## Reproduction` into exact, repeatable steps |

Every grilled decision must land as a verifiable line. Never leave a resolution only
in the conversation.

## Verdict

Return ONE verdict to the invoking stage — it records this in `pipeline-state.md`:

| Verdict | When |
|---------|------|
| `GRILLED` | grill ran (`light` or `full`); `requirements.md` updated |
| `SKIPPED: crisp` | tier was `skip` — input already well-specified |
| `SKIPPED: non-interactive` | no TTY (Step 0) |
| `SKIPPED: --no-grill` | the invoking stage passed the opt-out flag |

## Anti-Patterns

- NEVER ask a question the codebase already answers.
- NEVER re-ask something already answered or inferable from a prior answer.
- NEVER ask a generic question ("what about edge cases?") — name the specific case.
- NEVER exceed the tier's question cap, or grill past the point where answers stop
  changing the implementation.
- NEVER leave a resolved decision only in the chat — it must be written to
  `requirements.md`.
- NEVER batch questions — sequential only.
