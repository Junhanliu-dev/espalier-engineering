---
name: Feature request
about: Suggest a new capability, scout, skill template, or workflow
title: "feat: "
labels: enhancement
assignees: ''
---

## Problem / motivation

<!-- What problem does this solve? What's the current friction? -->

## Proposed change

<!-- What would the new behavior look like? -->

## Where it lives

<!-- Which part of the system does this touch? -->

- [ ] `/espalier-init` Phase 0/1/2/3 (discovery, writes, bootstrap)
- [ ] `/espalier` (full pipeline orchestrator)
- [ ] `/espalier-fix` (bug-fix lane)
- [ ] `/espalier-migrate` (migration shim)
- [ ] Child skill template (`espalier-coding` / `-review` / `-testing` / `-requirements`)
- [ ] Hook template (`pre-push-gate.sh`, `post-merge-backlink.sh`, etc.)
- [ ] Sub-agent (`harness-coder` / `harness-reviewer`)
- [ ] Discovery scout (Phase 1)
- [ ] Validation check (`bootstrap-espalier.sh` Stage 11)
- [ ] Documentation / README / migration guide
- [ ] Other: <!-- specify -->

## Acceptance criteria

<!-- What would "done" look like? List concrete, verifiable conditions. -->

- [ ] When <action>, then <expected result>
- [ ] <boundary condition> is handled by <behavior>

## Alternatives considered

<!-- What else did you consider? Why is the proposed approach better? -->

## Compatibility impact

<!-- Breaking change? Migration needed? Backward-compat concerns? -->

- [ ] Pure additive (no impact on existing installs)
- [ ] Additive + migration shim provided
- [ ] Breaking change — requires major version bump
