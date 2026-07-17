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

## Before Writing Code
The canonical pre-coding sequence (identify layer → read spec → find 1-2
reference files → follow the template exactly → climb the Solution Selection
Ladder) lives in `espalier/agents/harness-coder.md` ("Before Writing ANY
Code") — follow it from there; it is deliberately not restated here so the two
files cannot drift. This skill adds the project-specific parts: the Layer
Specs map and the Implementation Checklist above.

## Solution Selection (keep it lean)
Best convention-compliant solution wins: conventions first, correctness within
them, brevity only breaks ties. Reuse what the project already has (reference
files, `espalier/wiki/`) before writing new code; where conventions are silent
on the mechanism, prefer stdlib → native platform feature → already-installed
dependency; NEVER add a new dependency without a `requirements.md` line naming
it. Build nothing the requirement didn't ask for. The full ladder lives in
`espalier/agents/harness-coder.md` — it is the coder's rule, and the reviewer
checks against it (advisory, plus the new-dependency gate).
