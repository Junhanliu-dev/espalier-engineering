# Migrating from v0.12.0 to v0.13.0 (Convention-Bounded Minimalism)

## TL;DR

```bash
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

Or run the script directly:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.12.0-to-v0.13.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.12.0-to-v0.13.0.sh --yes
```

## What v0.13.0 changes — and why

AI coders over-build: a 200-line date-picker component, correctly placed in
the right layer with the right naming and timeouts, passed every Espalier gate
in v0.12 — no stage ever asked whether `<input type="date">` would have done.
Espalier enforced *fit* (conventions, layers, production seeds) but had no
notion of *size*.

v0.13.0 adds convention-bounded minimalism — the idea adapted from
[ponytail](https://github.com/DietrichGebert/ponytail) (MIT), re-grounded in
Espalier's model. The governing rule everywhere:

> **Conventions first, correctness within them, brevity only breaks ties.**

"Short is always best" is explicitly NOT the rule: a construct your rules or
layer specs mandate is never over-build, even when a shorter form exists.

**The coder** (`espalier/agents/harness-coder.md`) gains a Solution Selection
Ladder it climbs before choosing a change's shape: speculative extra → don't
build it; the project already has it (reference files, `espalier/wiki/`) →
reuse it; a convention names the mechanism → use THAT, even when stdlib would
be shorter; conventions silent → stdlib, then native platform, then an
already-installed dependency; only then the leanest convention-compliant
implementation that is correct on the edge cases. A NEW dependency always
requires a `requirements.md` line naming it. Deliberate simplifications land
in coding-report.md Notes so the reviewer confirms rather than re-derives them.

**The reviewer** (`espalier/agents/harness-reviewer.md`) gains a Minimalism
Review — advisory by construction: `delete:` / `stdlib:` / `native:` /
`yagni:` findings are capped at **P2/P3**, so they ride along in
review-record.md without ever re-opening the Stage 4 fixpoint loop or touching
the sentinel's `p0=`/`p1=` counts. ONE exception may block at P1: a new
dependency covering what stdlib, a native feature, or an installed dependency
already provides — the objectively checkable mirror image of the existing
"hand-rolls what the discovered wrapper covers" P1. Findings are invalid
against anything your rules/specs mandate; "the convention itself is
over-built" routes to a Convention Observation (the human promotion path),
never a blocking finding.

**Two hardening fixes ride along:** the sentinel contract now binds `p1=` to
the P1 row count exactly as `p0=` always was, and the reviewer's restated P1
checklist regains the "unbounded fan-out (N calls in a loop) on a request
path" bullet that had drifted from `production-standards.md`.

## What the migration touches

All four files are per-project (placeholder-substituted or scout-filled at
init), so the migration is **surgical** — anchored section inserts and line
replacements, never a template overwrite. Section bodies are extracted from
the installed plugin's v0.13.0 templates at runtime, so the script cannot
drift from the templates it installs.

| File | Change |
|---|---|
| `espalier/agents/harness-coder.md` | + `## Solution Selection Ladder`, + ladder step in the pre-code checklist |
| `espalier/agents/harness-reviewer.md` | + `## Minimalism Review`, + process step, + Summary line, `p1=` binding, + fan-out P1 bullet, + Must-NOT bullet, full `espalier-security` citation path |
| `espalier/skills/espalier-coding/SKILL.md` | Before-Writing steps → pointer at the canonical harness-coder sequence (de-duplicated), + `## Solution Selection (keep it lean)` |
| `espalier/skills/espalier-review/SKILL.md` | + plan-review pass condition (zero P0/P1), + Leanness checklist item, panel description names the Minimalism review |

Every file is backed up to `<file>.pre-v0.13.bak` before its first patch. The
script is idempotent — re-running on a migrated install exits 0 without
touching anything.

**Not migrated (cosmetic, fresh-install only):** the richer frontmatter
descriptions on the three renamed files — they carry per-project substitutions
the script cannot re-derive. Functional parity is complete without them.

## Pipeline semantics: what does NOT change

- Gate math is untouched: Stage 4/6 still advance only on
  PASS/PASS_WITH_FIXES with `p0=0 p1=0`; round caps and escalation are
  unchanged. Minimalism P2/P3 notes cannot trigger a fix round.
- Verdict vocabulary, record files, sentinel format: unchanged.
- A customised install: the anchored patches skip any block whose anchor text
  you have rewritten (each logs "no-op if custom" or simply leaves your text
  alone); the verification block reports exactly which markers landed.

## Verification

The release was gated on both eval suites (green after every template edit):
coder 4/4 (including a new overbuild-trap fixture), review 8/8 with
catch-rate 1.00 and zero false positives — including a planted
new-dependency P1 and a clean fixture guarding against minimalism severity
inflation. Quality scoring of all four artifacts (independent scorer agents,
darwin rubric): see [`docs/quality-report-v0.13.0.md`](./quality-report-v0.13.0.md).
