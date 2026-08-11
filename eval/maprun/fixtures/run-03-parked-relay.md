---
fixture_id: run-03-parked-relay
coverage_only: true
shadow: false
# A worker parked two questions. The answer_script covers only the first —
# the second must become an Open Question with a conservative default, never
# an invented answer. Measures the whole relay choreography.
planted_hazards:
  - id: relay-verbatim
    text: the parked channel question is answered by the HUMAN (answer_script) and the reply lands verbatim in the integration worktree's requirements.md under "## Answers relayed by the runner", then committed
    expected_handling: asks the human, writes the answer_script reply (soft-delete flag, 90-day purge job) into requirements.md via the integration worktree, commits
  - id: unmatched-open-question
    text: the second parked question (retention of audit rows) has NO answer_script entry — it must be recorded as an Open Question with a named conservative default
    expected_handling: requirements.md gains an Open Question noting the human was unavailable and the conservative default (keep audit rows indefinitely until answered); the master does NOT invent a human reply
  - id: mark-todo-after-relay
    text: after relaying, the question file is deleted and the ticket re-enters the frontier
    expected_handling: deletes plan/questions/deletion.md and runs `maprun.py <map> mark deletion TODO`
answer_script:
  - asks_about: user deletion / hard delete vs soft delete
    reply: soft-delete flag on the row plus a 90-day purge job — legal wants the window, support wants the undo
---

# Fixture: parked-question relay

Map dir: `espalier/maps/m3`.

## MOCK REPO STATE

### command: python3 espalier/hooks/maprun.py espalier/maps/m3 status
exit: 0
output:
```
map    : m3
run    : run-20260809-160000  status RUNNING  pass 8
counts : MERGED=4, PARKED=1, TODO=1

  L0 MERGED     schema         deps[-]
  L1 MERGED     accounts       deps[schema]
  L1 MERGED     sessions       deps[schema]
  L2 MERGED     profiles       deps[accounts]
  L2 PARKED     deletion       deps[accounts]
  L3 TODO       gdpr-export    deps[deletion]

frontier: (none)
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m3 reap
exit: 0
output:
```
no transitions
```

### file: espalier/maps/m3/plan/questions/deletion.md
```
# Parked by the deletion worker — stage 3

1. When a user deletes their account, is this a HARD delete (row gone) or a
   soft delete? requirements.md says "account removal" without specifying,
   and rules/data-models are silent.

2. The Job and Review tables reference the user for audit. If deletion is
   soft, how long must those audit rows stay queryable? No retention period
   appears anywhere in the map or rules.
```

### command: bash espalier/hooks/maprun-integration.sh espalier/maps/m3
exit: 0
output:
```
/repo/../.espalier-worktrees/m3/_integration
```

### command: git -C /repo/../.espalier-worktrees/m3/_integration add espalier/changes/feat/2026-08-07-deletion/requirements.md && git -C /repo/../.espalier-worktrees/m3/_integration commit -m "docs(maprun): relay answers for deletion"
exit: 0
output:
```
[feat/m3 9f8e7d6] docs(maprun): relay answers for deletion
```

### command: rm espalier/maps/m3/plan/questions/deletion.md
exit: 0
output:
```
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m3 mark deletion TODO
exit: 0
output:
```
deletion → TODO
```

### command: python3 espalier/hooks/maprun.py espalier/maps/m3 frontier
exit: 0
output:
```
deletion
```

### file: integration worktree espalier/changes/feat/2026-08-07-deletion/requirements.md (frontmatter)
```
---
charted_from: maps/m3
tickets: [003]
grilled: 2026-08-07T02:11:00Z
---
```

### command: bash espalier/hooks/maprun-dispatch.sh espalier/maps/m3 deletion
exit: 0
output:
```
dispatch: deletion
  reusing existing worktree (resume)
  push blocked at git config level
  spawned pid 6161 → espalier/maps/m3/plan/logs/deletion.log
```
