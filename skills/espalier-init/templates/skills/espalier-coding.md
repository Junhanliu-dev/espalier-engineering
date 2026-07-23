---
name: espalier-coding
description: >-
  How {project} implements features — the per-layer spec map, the
  project-specific implementation checklist, and the lean solution-selection
  rule. Load BEFORE writing any code in {project}; used by harness-coder at
  Stage 3 (implementation), Stage 5 (testing mode), and on fix rounds.
  Triggers: "implement", "add feature", "write code", "which layer does this
  go in", "layer spec".
---

# Coding Skill

## How This Project Adds Features
{describe the actual pattern for adding new functionality}
{e.g., "Create a route file, add handler, create service, write repository query"}

## Layer Specs
{for each discovered layer, reference its spec file}
- Read `espalier/skills/espalier-coding/specs/{layer-a}.md` when working in {layer A}
- Read `espalier/skills/espalier-coding/specs/{layer-b}.md` when working in {layer B}

## Implementation Checklist
- [ ] {project-specific step 1}
- [ ] {project-specific step 2}
- [ ] ...
{e.g., "- [ ] Route registered in the route index", "- [ ] Service returns the
project's Result type — never throws across the layer boundary", "- [ ] New
list query is bounded (limit / pagination)"}

## Before Writing Code
The canonical pre-coding sequence (identify layer → read spec → find 1-2
reference files → follow the template exactly → climb the Solution Selection
Ladder) lives in `espalier/agents/harness-coder.md` ("Before Writing ANY
Code") — follow it from there; it is deliberately not restated here so the two
files cannot drift. This skill adds the project-specific parts: the Layer
Specs map and the Implementation Checklist above.

## How This Skill Applies by Stage

The layer map above is stage-agnostic; which parts carry the weight changes
with the context the pipeline loaded this skill in:

- **Stage 3 — implementation.** The whole skill applies: the layer spec for
  every layer touched, the full Implementation Checklist, the Solution
  Selection Ladder before choosing the change's shape.
- **Stage 5 — testing mode.** Layer specs still govern WHERE tests live and
  what naming/structure they follow; the ladder applies to test code too —
  reuse the project's existing test helpers, fixtures, and factories before
  writing new ones, and a new test-only dependency is still a NEW dependency
  (needs its `requirements.md` line). The test recipes themselves (abuse
  tests, failure-mode tests) are canonical in
  `espalier/agents/harness-coder.md` and
  `espalier/skills/espalier-security/SKILL.md`, not here.
- **Fix rounds — Stage 4/6 re-spawns.** Scope is the findings, nothing else:
  re-read only the spec(s) for the layers the fix touches, make the smallest
  convention-compliant change that clears the finding, and never "improve"
  adjacent code the finding didn't name. The checklist applies to what the
  fix DID touch; record the delta in coding-report.md.

## Solution Selection (keep it lean)
Best convention-compliant solution wins: conventions first, correctness within
them, clarity then brevity break ties. Reuse what the project already has
(reference files, `espalier/wiki/`) before writing new code; where conventions
are silent on the mechanism, prefer stdlib → native platform feature →
already-installed dependency; NEVER add a new dependency without a
`requirements.md` line naming it. Build nothing the requirement didn't ask
for. The full ladder lives in `espalier/agents/harness-coder.md` — it is the
coder's rule, and the reviewer checks against it (advisory, plus the
new-dependency and cryptic-public-name gates).
