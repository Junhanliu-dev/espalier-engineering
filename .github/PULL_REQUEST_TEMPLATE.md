## Summary

<!-- One sentence: what does this PR do? -->

## Why

<!-- What problem does it solve? Link issue if applicable: closes #N -->

## Changes

<!-- Bulleted list of concrete changes. Group by file or component if many. -->

-
-
-

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking, additive)
- [ ] Breaking change (fix or feature that changes existing skill/script behavior)
- [ ] Docs only
- [ ] Refactor / cleanup (no behavior change)

## Test plan

- [ ] `bash scripts/test-bootstrap.sh --verbose` passes 33/33
- [ ] All shell scripts pass `bash -n` under `/bin/bash` (macOS 3.2.57)
- [ ] If migration scripts changed: dry-run + apply tested against synthetic v0.3 fixture under both `/bin/bash` and homebrew bash
- [ ] If skill templates changed: spawned a test project, ran `/espalier-init`, verified output structure
- [ ] CHANGELOG.md updated under the next version heading
- [ ] Tested on macOS / Linux: <!-- specify which -->

## Compatibility

- [ ] Pure additive — no impact on existing installs
- [ ] Additive — backward-compat fallback retained for v0.3 / v0.2 installs
- [ ] Breaking — migration shim added at `scripts/migrate-v0.4-to-v0.5.sh` (or equivalent)

## Screenshots / output

<!-- If applicable: paste relevant terminal output or before/after state. -->

```
<paste>
```

## Reviewer notes

<!-- Anything specific to call out? Tricky logic? Known limitations? -->
