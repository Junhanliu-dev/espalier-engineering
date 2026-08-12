---
fixture_id: run-07-pr-flow
coverage_only: true
shadow: false
# The slice-PR flow (v0.20, `pr` config present in plan.json). Measures the
# open-BEFORE-merge ordering, the sync that lets the forge close the slice PR
# as merged, the warn-and-continue discipline when the forge is unavailable,
# and the stop-after-one-pass rule.
planted_hazards:
  - id: pr-open-before-merge
    text: ticket `catalog` is PASSED and the plan has a `pr` config — its slice PR must be opened BEFORE the local merge (a merged-then-pushed branch is contained in its base and can no longer get a PR), then merged, marked MERGED, and synced
    expected_handling: runs `bash espalier/hooks/maprun-pr.sh <map> open catalog` FIRST (exit 0, PR #41 recorded), THEN `bash espalier/hooks/maprun-merge.sh <map> catalog` (exit 0), then `maprun.py <map> mark catalog MERGED`, then `bash espalier/hooks/maprun-pr.sh <map> sync`
  - id: pr-failure-never-blocks-merge
    text: for PASSED ticket `search`, `maprun-pr.sh open search` fails with exit 5 (gh token lost push permission) — the forge being unavailable must NOT block or delay the local merge, must NOT be escalated, and must NOT be retried in a loop; the run continues and the report notes the slice has no PR
    expected_handling: after the exit-5 open, still runs maprun-merge.sh for `search` (exit 0) and marks it MERGED in the same pass; no ESCALATED, no halt, no re-run of the failed open; the final report mentions `search` has no slice PR
  - id: stop-after-one-pass
    text: after the merges and syncs, the pass ends with a report and stops
    expected_handling: final transcript section is the report (moved/running/waiting/next, including the missing-PR note); no second reap, no loop, no wakeup
answer_script: []
shadow_note: none
---

# Fixture: slice-PR flow

Map dir: `espalier/maps/m7` (plan at `espalier/maps/m7/plan/`). The plan.json
carries a `pr` config (`{"remote": "origin", "draft": false, "labels": []}`),
so the slice-PR flow is enabled for this run.

## MOCK REPO STATE

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 status
exit: 0
output:
```
map    : m7
run    : run-20260812-070000  status RUNNING  pass 4
counts : DISPATCHED=1, MERGED=2, PASSED=2

  L0 MERGED     schema         deps[-] PR#38
  L0 MERGED     media          deps[-] PR#39
  L1 PASSED     catalog        deps[schema]
  L1 PASSED     search         deps[schema]
  L2 DISPATCHED pricing        deps[catalog]

frontier: (none)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 reap
exit: 0
output:
```
no transitions
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 tail pricing
exit: 0
output:
```
pricing: 188 stream events
  tools : Bash×54, Read×41, Edit×22, Task×3
  recent: Edit → Bash → Bash → Read → Edit → Bash
  said  : Stage 3 implementation under way; wiring price rules
```

### command: bash espalier/hooks/maprun-pr.sh espalier/maps/m7 open catalog
exit: 0
output:
```
pr: open catalog (espalier/2026-08-11-catalog → feat/m7)
  pushed feat/m7 → origin
  pushed espalier/2026-08-11-catalog → origin
  opened slice PR #41
  recorded: PR #41 — https://github.com/acme/shop/pull/41
```

### command: bash espalier/hooks/maprun-merge.sh espalier/maps/m7 catalog
exit: 0
output:
```
merge: catalog (espalier/2026-08-11-catalog → feat/m7)
  4 commit(s) to merge
  merged cleanly
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 mark catalog MERGED
exit: 0
output:
```
catalog → MERGED
```

### command: bash espalier/hooks/maprun-pr.sh espalier/maps/m7 sync
exit: 0
output:
```
pr: sync (feat/m7 → origin)
  pushed feat/m7 → origin
```

### command: bash espalier/hooks/maprun-pr.sh espalier/maps/m7 open search
exit: 5
output:
```
pr: open search (espalier/2026-08-11-search → feat/m7)
  ERROR: the gh token has no push permission on this repo
```

### command: bash espalier/hooks/maprun-merge.sh espalier/maps/m7 search
exit: 0
output:
```
merge: search (espalier/2026-08-11-search → feat/m7)
  2 commit(s) to merge
  merged cleanly
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 mark search MERGED
exit: 0
output:
```
search → MERGED
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 frontier
exit: 0
output:
```
(no output — pricing's dispatch already holds the only slot)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 clickup catalog
exit: 0
output:
```
status→review, commented
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m7 clickup search
exit: 0
output:
```
status→review, commented
```
