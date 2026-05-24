# Grill Integration Plan — espalier-engineering

**Status:** Draft v2 — pre-mortem mitigations applied
**Target version:** v0.6.0 (current: v0.5.5)
**Type:** Feature, non-breaking

## 1. Goal

Add requirement/diagnosis **grilling** to Stage 1 of both espalier pipelines. Grilling is a relentless sequential interrogation that stress-tests a requirement (feat) or a diagnosis (fix) *before any code is written* — methodology adapted from the `grill-with-docs` skill (Matt Pocock's skills repo).

Espalier already hardens code-pattern conformance, but its weakest stage is Stage 1: `espalier-requirements` is a form-filler whose only quality mechanism is one passive line ("Ask clarifying questions if acceptance criteria are ambiguous"). Every later stage trusts the Stage 1 spec; no gate audits it. The Stage 1 gate is a *count* check (≥ 2 acceptance criteria). Grill is the missing audit of the pipeline's root of trust.

## 2. Scope

**In:**
- New `espalier-grill` skill — single methodology, two modes.
- Stage 1 wiring in `/espalier` (feat) and `/espalier-fix`.
- `--no-grill` per-run escape-hatch flag on both pipelines.
- `## Root Cause` field added to the fix-lane `requirements.md` template.
- Adaptive depth (skip / light / full — chosen by grill, not the user).
- A golden-set **eval harness** for the grill skill (QA + value test — see §6 Phase A2).
- v0.5 → v0.6 migration.

**Out (deferred — see §11):**
- Domain glossary / `wiki/glossary.md` — separate future minor.
- ADRs.
- Pluggable toggle, `.grill-mode` dotfile, Phase 0 question — explicitly rejected (see §3).

## 3. Locked decisions (from scoping discussion — do not relitigate without cause)

| Decision | Rationale |
|---|---|
| Absorb grill as **methodology**, not a drop-in skill | grill-with-docs uses different file conventions; a standalone install would duplicate Stage 2 reqs-review and not wire into the pipeline |
| **Unbundle** — grill now, glossary later, ADR deferred | grill is highest ROI / lowest cost; glossary carries the full release tax and modest payoff |
| Grill = its **own skill** `espalier-grill` | single source of truth; both Stage 1s invoke it; avoids duplicating the methodology across two templates |
| **Fixed + adaptive**, NOT a pluggable toggle | grill-need is determinable by grill itself — unlike the 3 existing toggles (merge strategy, agent tools, doctor cadence), which encode irreducible user facts espalier cannot determine |
| Depth = grill's **output**, not user input | grill assesses ambiguity per-case → skip/light/full. Per-case judgment beats a blunt global switch |
| One flag: **`--no-grill`**, per-run, ephemeral | escape hatch only. No dotfile, no Phase 0 question (YAGNI — adding a toggle later is non-breaking; removing one breaks users) |
| feat-grill ≠ fix-grill **target** | feat interrogates the SPEC (scope / false premises / edge cases); fix interrogates the DIAGNOSIS (root cause / repro / expected-behaviour). Same method |
| `--no-grill` / grill-off == **current behavior** | feature ships strictly non-breaking |

## 4. Architecture

### 4.1 The `espalier-grill` skill

`espalier/skills/espalier-grill/SKILL.md` — phase-loaded (NOT a slash command; invoked by Stage 1 of each pipeline). Pure-copied by bootstrap because the methodology is project-agnostic. ~115 lines as built, following espalier's skill house style (H1, Purpose, Output Format, numbered Process, Anti-Patterns).

Skill sections:

- **Mode select** — `spec` (called by `/espalier`) | `diagnosis` (called by `/espalier-fix`).

- **Step 0 — Environment check.** If the session is non-interactive (no TTY — `[ -t 0 ]` is false), skip grilling and log `grill skipped: non-interactive` to `pipeline-state.md`. Prevents an unattended pipeline from hanging on an unanswerable question.

- **Step 1 — Ambiguity scoring → adaptive depth.** Do NOT "judge ambiguity" abstractly — count concrete ambiguity *signals* in the input: undefined / overloaded terms; unstated actors or systems; missing failure / error behaviour; hidden quantifiers ("fast", "some", "large"); unscoped edge cases. Map the count to a depth tier, each anchored with a labelled example in the skill:
  - 0–1 signals → `skip` (one confirmation at most)
  - 2–4 → `light` (≤ 3 questions)
  - 5+ → `full` (≤ N questions)
  State the chosen tier out loud to the user ("Well-specified — one confirmation only") so a misjudgment is visible and correctable.

- **Step 2 — The grill loop.** Before each question, silently sample 3–5 concrete *divergent interpretations* the input still permits, then ask the question whose answer best **discriminates** between them. (Reasoning over candidate solutions, not over questions, is what produces sharp non-obvious questions.) Sequential — one question, wait, the next builds on the answer. Explore the codebase to self-answer before asking the user, within a read budget (≤ M files). Stop the moment remaining ambiguity would not change the implementation.

- **Step 3 — Output.** Write resolved decisions into `requirements.md` (spec mode: acceptance criteria + scope; diagnosis mode: `## Root Cause` + `## Reproduction`). Closed verdict vocabulary: `GRILLED` | `SKIPPED (<reason>)`.

- **Anti-Patterns.** Never ask what the code already answers. Never re-ask an answered or inferable point. Never exceed the tier's question cap. Never grill past the point where answers stop changing the implementation.

### 4.2 Invocation flow

```
/espalier feat: <req>            → Stage 1 → espalier-grill (mode=spec)
/espalier --no-grill feat: <req> → Stage 1 → skip grill, plain requirements analysis
/espalier-fix <bug>              → Stage 1 → espalier-grill (mode=diagnosis)
/espalier-fix --no-grill <bug>   → Stage 1 → skip grill
```

`--no-grill` is a hard override — it short-circuits before the Step 1 adaptive assessment.

## 5. File inventory

### New
| File | Purpose |
|---|---|
| `skills/espalier-init/templates/skills/espalier-grill.md` | grill skill template → emitted to `espalier/skills/espalier-grill/SKILL.md` |
| `eval/grill/fixtures/*.md` | 20–30 golden requirement fixtures with planted ambiguities (QA harness — see Phase A2) |
| `eval/grill/rubric.md` | LLM-judge scoring rubric |
| `eval/grill/run.sh` | eval runner (dev/QA only — not shipped to target projects) |
| `scripts/migrate-v0.5-to-v0.6.sh` | migration for existing installs |
| `docs/migrating-v0.5-to-v0.6.md` | migration doc |

### Modified
| File | Change |
|---|---|
| `templates/skills/espalier-requirements.md` | Stage 1 (feat): invoke espalier-grill unless `--no-grill`; replace the passive clarifying-question line |
| `templates/skills/espalier-fix.md` | Stage 1: invoke grill (diagnosis mode); add `## Root Cause` to the reqs template; add `--no-grill` to the flag `case` block |
| `templates/skills/espalier.md` | NEW flag-parse step — known-flag **whitelist** `{--no-grill, --resume}`; `--resume` recognised as a no-op (resume is automatic); unknown `--token` → warn, never absorbed into requirement text; Stage 1 conditional |
| `templates/pipeline.md` | Stage 1 definition references grill |
| `scripts/bootstrap-espalier.sh` | Stage 2 `mkdir espalier/skills/espalier-grill`; Stage 3 pure-copy list += `espalier-grill`; Stage 5 symlink list += `espalier-grill`; check #2 (`skills-load`) extended to include `espalier-grill` |
| `skills/espalier-init/SKILL.md` | output-structure section + Phase 3 description mention espalier-grill |
| `skills/espalier-migrate/SKILL.md` | register v0.5→v0.6 in the auto-detect migration chain |
| `CHANGELOG.md`, `.claude-plugin/plugin.json`, `README.md` | v0.6.0 release |

## 6. Implementation phases

| Phase | Work | Depends on |
|---|---|---|
| **A — Build the skill** | Write `espalier-grill.md` per the §4.1 design: solution-space question reasoning, signal-count depth rubric with anchored examples, per-tier question caps, codebase read budget, TTY check, anti-patterns | — |
| **A2 — Eval harness** | Build `eval/grill/`: 20–30 golden requirement fixtures with planted ambiguities spanning the three depth tiers; an LLM-judge rubric scoring non-obviousness / discrimination / progression / depth-calibration; a runner. Validate the judge against hand labels (target 75–90% agreement). Keep a shadow subset unseen by the skill author. Wire as a regression gate on `espalier-grill.md` edits | A |
| **B — Wire Stage 1** | espalier-requirements.md; espalier-fix.md (+ Root Cause field + flag case); espalier.md (+ whitelist flag parser + Stage 1 conditional); pipeline.md | A |
| **C — Bootstrap + init** | bootstrap-espalier.sh (mkdir, pure-copy list, validation #29); espalier-init/SKILL.md | A |
| **D — Migration** | migrate-v0.5-to-v0.6.sh; migrating doc; register in espalier-migrate | A, B, C |
| **E — Release** | CHANGELOG, version bump, README; run test-bootstrap.sh + validation + the grill eval harness | A–D |

Order: **A → (A2 ∥ B ∥ C) → D → E.**

## 7. Migration (existing installs)

`migrate-v0.5-to-v0.6.sh` steps:
1. Create `espalier/skills/espalier-grill/` and copy `SKILL.md`.
2. **Backup-on-diff:** before overwriting any pure-copied pipeline skill, diff it against the known v0.5 template. If it differs (user customisation), copy it to `<file>.pre-v0.6.bak` and list every backup in the migration summary.
3. Re-copy the pure-copied pipeline skills carrying grill wiring: `espalier.md`, `espalier-fix.md`, `espalier-requirements.md`, `pipeline.md`.
4. Symlink `.claude/skills/espalier-grill` (bootstrap Stage 5 globs new skill dirs; migration mirrors that).
5. Announce: "v0.6 adds Stage 1 grilling (adaptive, on by default). Per-run opt-out: `--no-grill`."

No mode/decision prompt — the fixed+adaptive design removed the migration-default question entirely.

**Cross-platform constraint:** the migration script must use BSD-compatible `sed -E` and bash 3.2 syntax. Prior espalier migrate scripts hit exactly this — extended regex without `-E` throws `RE error` on macOS BSD sed.

## 8. Risks & mitigations (post-premortem)

| Risk | Residual severity | Mitigation |
|---|---|---|
| Adaptive depth mis-calibrates (under/over-grills) | Low–Med | Signal-count rubric + anchored examples (§4.1 Step 1); tier stated aloud so the user can correct it; eval harness catches regressions |
| Grill asks shallow / obvious questions | Low–Med | Solution-space reasoning — sample divergent interpretations, ask the discriminating question (§4.1 Step 2); eval rubric scores non-obviousness |
| `--resume` invocation mangled by the new flag parser | Low | Whitelist parser `{--no-grill, --resume}`; `--resume` = recognised no-op; unknown `--token` warns instead of being absorbed |
| Non-interactive `/espalier` hangs on a grill question | Low | TTY check (§4.1 Step 0) auto-skips grill in non-interactive sessions |
| Migration overwrites a user-customised pipeline skill | Low | Backup-on-diff step (§7 step 2) |
| Goodhart's law — `req=n` becomes a gamed target | Low | `req=n` is a monitoring signal only, never a hard gate; the golden-set eval is the un-gameable check |
| Eval-harness LLM judge is unreliable | Low–Med | Validate the judge against hand labels (≥ 75% agreement) before trusting it; keep a shadow fixture set |
| Sequential grill conflicts with espalier's batched execution | Low | Contained to Stage 1 (already interactive + human checkpoint); adaptive skip keeps easy cases fast |

## 9. Success criteria

Mechanical:
- `espalier-grill` registers cleanly (folder name == `name:` frontmatter).
- Fresh `/espalier-init` emits `espalier-grill`; bootstrap check #2 (`skills-load`, now including `espalier-grill`) passes.
- `/espalier feat: <vague>` triggers grilling; `/espalier --no-grill feat: <vague>` skips it.
- `/espalier feat: <crisp>` adaptive-skips — no questions asked.
- `/espalier-fix` output contains a populated `## Root Cause` section.
- A v0.5 install + `migrate-v0.5-to-v0.6.sh` → `espalier-grill` present and wired.
- `test-bootstrap.sh` passes.

Outcome (the value test):
- The eval harness shows grill surfaces ≥ 80% of planted ambiguities across the golden fixtures.
- The eval LLM-judge is validated at ≥ 75% agreement with hand labels.
- On a sample of post-grill changes, the `Review Rounds: req=` counter (already recorded in `pipeline-state.md`) trends below the retroactive pre-grill baseline. Monitoring signal — not a hard gate.

## 10. Effort

Medium-plus. The core skill is small; the eval harness adds roughly one extra day (deliberate — it is the mitigation for the two HIGH pre-mortem findings); the remainder is the release tax (migration script + doc + CHANGELOG + validation check), comparable to v0.5 doc-drift.

## 11. Out of scope / future

- **Domain glossary** (`wiki/glossary.md` + a discovery scout) — a separate future minor (v0.7+). Real value, but it carries the full release tax; ship it after grill has proven out.
- **ADRs** — deferred; revisit if users ask.
- **Tier-2 toggle** (`.grill-mode` dotfile) — add ONLY if real usage shows routine `--no-grill` use.

## 12. Status / next step

Pre-mortem complete (§13). **Phases A, A2, B, C complete** — grill skill + eval harness built; Stage 1 grill wired into `espalier-requirements`, `espalier-fix`, `espalier.md`, `pipeline.md`; bootstrap wires the new skill (mkdir + pure-copy + Stage 5 symlink + check #2). `espalier-fix` gained the `## Root Cause` field and `--no-grill` flag; `espalier.md` gained a leading-flag whitelist parser (`--no-grill`, `--resume`). Next: **Phase D** (migration v0.5→v0.6).

## 13. Risk Mitigations (Pre-Mortem)

**Run:** 2026-05-22 · deep mode · 5 tigers, 1 elephant. Outcome: all addressed (user chose "Apply all + full eval harness"). Mitigation research: 1 scout (espalier internals) + 2 oracle (external).

| Finding | Sev | Mitigation | Landed in |
|---|---|---|---|
| T1 — no value test | HIGH | Reuse existing `req=n` / `Total Rollbacks` counters; retroactive baseline; golden-set eval harness | §6 Phase A2, §9 |
| E1 — grill skill quality (elephant) | HIGH | Solution-space question reasoning; signal-count depth rubric with anchors; LLM-judge QA rubric | §4.1, §6 Phase A & A2 |
| T2 — `--resume` mangled | MED | Known-flag whitelist parser; warn on unknown `--token` | §5, §6 Phase B |
| T3 — migration backup gap | MED | Explicit backup-on-diff step in the procedure | §7 step 2 |
| T4 — non-interactive hang | MED | TTY check → auto-skip | §4.1 Step 0 |
| T5 — unbounded codebase exploration | MED | Per-tier question caps + read budget | §4.1 Steps 1–2 |
| Goodhart on `req=n` (surfaced during research) | — | `req=n` monitoring-only, never a gate; eval harness is the un-gameable check | §8, §9 |

**Key research source:** "Active Task Disambiguation with LLMs" (ICLR 2025) — sharp, non-obvious questions come from reasoning over candidate *solutions* and picking the most discriminating question, not from reasoning over questions directly. This is the core technique behind §4.1 Step 2.

## 14. Reversibility / kill switch

Grill can be backed out at every stage; the cost rises the later it is removed.

| Stage | Reversible | Mechanism |
|---|---|---|
| Pre-wiring (Phases A–C, before release) | Fully, zero cost | git — revert the branch |
| Phase A2 eval gate | Fully | a catch-rate below the §9 threshold blocks release. A2 sits before E specifically as this go/no-go |
| After release, per run | Yes | `--no-grill` bypasses grill for that invocation |
| After release, full removal from the plugin | Mostly — see below | lazy removal |

**Graceful degradation.** Because grill-off equals current behaviour (§3), a grill that performs badly is dead weight, not a breakage — it never corrupts artifacts or blocks the pipeline. A poor grill can sit disabled-in-practice (users default to `--no-grill`) while a fix or removal is prepared.

**Lazy removal (the kill switch).** espalier's migration system is forward-only — there is no down-migration pattern, so fully deleting grill from already-migrated installs is awkward. Instead, a later version makes grill **inert**: change `espalier-grill` Step 1 to always return `skip`. One line, no down-migration, existing installs unaffected — the skill file remains but does nothing. The only lasting trace is the `## Root Cause` field in fix-lane `requirements.md` files already committed under v0.6; that is harmless leftover data.
