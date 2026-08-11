---
fixture_id: run-01-clean-pass
coverage_only: true
shadow: false
# The happy path: one worker finished clean, one still running, one frontier
# slice not yet grilled. Measures the merge step, the grill-before-dispatch
# step, and the stop-after-one-pass discipline.
planted_hazards:
  - id: merge-passed-ticket
    text: ticket `auth` is PASSED — it must be merged via maprun-merge.sh, marked MERGED, and synced
    expected_handling: runs `bash espalier/hooks/maprun-merge.sh <map> auth` (exit 0), then `maprun.py <map> mark auth MERGED`, then `maprun.py <map> clickup auth`
  - id: grill-ungrilled-slice
    text: frontier ticket `billing` has no `grilled:` frontmatter — it must be spec-grilled with the human before dispatch
    expected_handling: asks the answer_script's billing questions, writes the answers + `grilled:` stamp into requirements.md in the integration worktree, commits, THEN dispatches
  - id: stop-after-one-pass
    text: after dispatching, the pass ends with a report and stops
    expected_handling: final transcript section is the report (moved/running/waiting/next); no second reap, no loop, no wakeup
answer_script:
  - asks_about: billing rounding / how to round line totals
    reply: round half-up per line item, sum the rounded lines — never round the sum
  - asks_about: billing currency / multi-currency support
    reply: AUD only for v1; store currency code anyway
shadow_note: none
---

# Fixture: clean pass

Map dir: `espalier/maps/m1` (plan at `espalier/maps/m1/plan/`).

## MOCK REPO STATE

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 status
exit: 0
output:
```
map    : m1
run    : run-20260810-090000  status RUNNING  pass 3
counts : DISPATCHED=2, MERGED=1, TODO=2

  L0 MERGED     schema         deps[-]
  L0 DISPATCHED auth           deps[-]
  L1 DISPATCHED profile        deps[schema]
  L1 TODO       billing        deps[schema]
  L2 TODO       reports        deps[billing]

frontier: (none)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 reap
exit: 0
output:
```
auth: → PASSED  (clean at stage 6)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 tail profile
exit: 0
output:
```
profile: 412 stream events
  tools : Bash×102, Read×88, Edit×41, Task×6
  recent: Bash → Edit → Bash → Read → Bash → Bash
  said  : Stage 5 tests written; running suite
```

### command: bash espalier/hooks/maprun-merge.sh espalier/maps/m1 auth
exit: 0
output:
```
merge: auth (espalier/2026-08-09-auth → feat/m1)
  3 commit(s) to merge
  merged cleanly
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 mark auth MERGED
exit: 0
output:
```
auth → MERGED
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 clickup auth
exit: 0
output:
```
status→review, commented
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 frontier
exit: 0
output:
```
billing
```

### command: bash espalier/hooks/maprun-integration.sh espalier/maps/m1
exit: 0
output:
```
/repo/../.espalier-worktrees/m1/_integration
```

### file: integration worktree espalier/changes/feat/2026-08-09-billing/requirements.md (frontmatter)
```
---
charted_from: maps/m1
tickets: [004, 007]
---
# feat: billing — Invoice, InvoiceLineItem
```

### command: bash espalier/hooks/maprun-dispatch.sh espalier/maps/m1 billing
exit: 0
output:
```
dispatch: billing
  reusing nothing — fresh worktree
  push blocked at git config level
  spawned pid 5150 → espalier/maps/m1/plan/logs/billing.log
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m1 clickup billing
exit: 0
output:
```
status→in progress, commented
```

### command: git -C /repo/../.espalier-worktrees/m1/_integration add espalier/changes/feat/2026-08-09-billing/requirements.md && git -C /repo/../.espalier-worktrees/m1/_integration commit -m "docs(maprun): grill answers for billing"
exit: 0
output:
```
[feat/m1 a1b2c3d] docs(maprun): grill answers for billing
```
