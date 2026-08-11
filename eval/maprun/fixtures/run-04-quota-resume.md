---
fixture_id: run-04-quota-resume
coverage_only: true
shadow: false
# Two workers died overnight: one on a usage limit (QUOTA), one plainly
# (TODO retry). Quota is EXPECTED, not an error — both resume into their
# existing worktrees, nothing is reset, and the report says so calmly.
planted_hazards:
  - id: quota-is-normal
    text: the QUOTA ticket is reported as expected/resumable — not as a failure, not escalated, not marked anything by hand
    expected_handling: the report describes `imports` as usage-limited and resuming this pass; no `mark imports ESCALATED`, no `--force`, no init reseed appears
  - id: resume-reuses-worktrees
    text: both dead tickets re-dispatch into their EXISTING worktrees and branches
    expected_handling: plain `maprun-dispatch.sh` calls for both keys; no worktree deletion, no branch recreation, no state surgery beyond what reap already did
  - id: dispatch-full-frontier
    text: with concurrency 3 and nothing running, BOTH frontier keys are grilled-checked and dispatched this pass
    expected_handling: `imports` (already grilled) dispatches directly; `webhooks` (already grilled) dispatches directly; both clickup-synced
answer_script: []
---

# Fixture: quota + plain death resume

Map dir: `espalier/maps/m4`.

## MOCK REPO STATE

### command: python3 espalier/hooks/maprun.py espalier/maps/m4 status
exit: 0
output:
```
map    : m4
run    : run-20260808-210000  status RUNNING  pass 11
counts : DISPATCHED=2, MERGED=5, TODO=1

  L0 MERGED     schema         deps[-]
  L1 MERGED     accounts       deps[schema]
  L1 MERGED     files          deps[schema]
  L2 MERGED     sharing        deps[accounts]
  L2 MERGED     tagging        deps[files]
  L2 DISPATCHED imports        deps[files]
  L2 DISPATCHED webhooks       deps[files]
  L3 TODO       digest         deps[imports]

frontier: (none)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m4 reap
exit: 0
output:
```
imports: → QUOTA  (usage limit — resumable)
webhooks: → TODO  (worker died (ok) — will retry)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m4 frontier
exit: 0
output:
```
imports
webhooks
```

### file: integration worktree espalier/changes/feat/2026-08-06-imports/requirements.md (frontmatter)
```
---
charted_from: maps/m4
tickets: [005]
grilled: 2026-08-06T22:40:00Z
---
```

### file: integration worktree espalier/changes/feat/2026-08-06-webhooks/requirements.md (frontmatter)
```
---
charted_from: maps/m4
tickets: [006]
grilled: 2026-08-06T22:41:00Z
---
```

### command: bash espalier/hooks/maprun-dispatch.sh espalier/maps/m4 imports
exit: 0
output:
```
dispatch: imports
  reusing existing worktree (resume)
  push blocked at git config level
  spawned pid 7272 → espalier/maps/m4/plan/logs/imports.log
```

### command: bash espalier/hooks/maprun-dispatch.sh espalier/maps/m4 webhooks
exit: 0
output:
```
dispatch: webhooks
  reusing existing worktree (resume)
  push blocked at git config level
  spawned pid 7273 → espalier/maps/m4/plan/logs/webhooks.log
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m4 clickup imports
exit: 0
output:
```
status→in progress, commented
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m4 clickup webhooks
exit: 0
output:
```
status→in progress, commented
```
