---
name: Bug report
about: Report a problem with /espalier-init, /espalier, /espalier-fix, /espalier-migrate, or any shipped script
title: "bug: "
labels: bug
assignees: ''
---

## Environment

- Espalier version: <!-- from `.claude-plugin/plugin.json` or `/plugin list` -->
- Install method: <!-- marketplace, manual clone, project-scoped symlink -->
- OS + version: <!-- e.g. macOS 14.5, Ubuntu 22.04 -->
- Shell: <!-- output of `/bin/bash --version` -->
- Claude Code version: <!-- from `claude --version` -->

## What command / skill did you run?

<!-- e.g. /espalier-init, /espalier feat: add auth, bash scripts/migrate-v0.3-to-v0.4.sh -->

## Expected behavior

<!-- What should have happened? -->

## Actual behavior

<!-- What actually happened? Include full error output. -->

```
<paste error / stack trace / hook output here>
```

## Reproduction steps

1. <!-- step 1 -->
2. <!-- step 2 -->
3. <!-- ... -->

## State at time of failure

<!-- If applicable, paste output of: -->

```bash
ls -la espalier/ harness/ .claude/ 2>/dev/null
cat .claude/settings.json 2>/dev/null | head -30
cat espalier/.merge-hook-decision 2>/dev/null || cat harness/.merge-hook-decision 2>/dev/null
```

## Additional context

<!-- Workarounds tried? Frequency? First-time-only or persistent? -->
