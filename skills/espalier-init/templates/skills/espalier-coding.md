---
name: espalier-coding
description: Implementation skill with per-layer specs for this project
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
1. Identify which layer(s) this change touches
2. Read the relevant spec file(s) from specs/
3. Find 1-2 existing files in that layer as reference
4. Follow the template structure exactly
5. Climb the Solution Selection Ladder (below) before choosing the change's shape

## Solution Selection (keep it lean)
Best convention-compliant solution wins: conventions first, correctness within
them, brevity only breaks ties. Reuse what the project already has (reference
files, `espalier/wiki/`) before writing new code; where conventions are silent
on the mechanism, prefer stdlib → native platform feature → already-installed
dependency; NEVER add a new dependency without a `requirements.md` line naming
it. Build nothing the requirement didn't ask for. The full ladder lives in
`espalier/agents/harness-coder.md` — it is the coder's rule, and the reviewer
checks against it (advisory, plus the new-dependency gate).
