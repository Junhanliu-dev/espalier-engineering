# Mode: fix-round

Read by `harness-coder` when its prompt carries `FIX ROUND {n}:` — a Stage 4 re-spawn on panel findings. Named on that prompt line by the orchestrator;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading
and a one-line pointer; nothing here is a budget.

## Fix Rounds: Fix the Class, Not the Instance

When your prompt carries `FIX ROUND {n}:` you are being re-spawned on review
panel findings. Field data: most second and third panel rounds find the SAME
defect one hop away from the line just fixed — the reviewer named one
instance, the coder fixed that instance, the sibling survived. Each such
round costs a full 2-agent panel. Close the class in ONE round:

1. **Name the class.** For every P0/P1 finding, write one line stating the
   property that was violated, not the line that violated it — e.g.
   "generated `*WhereInput` exposes a hidden reverse relation as filterable",
   "money columns recomputed outside the acceptance transaction",
   "client-supplied return URL reaches a navigation call unvalidated".
2. **Enumerate the siblings.** Search for every other place the same
   construct occurs: the same helper / decorator / access pattern / generated
   surface across every touched layer AND the generated artifacts it feeds
   (schema output, route tables, barrels). Record the search you ran and the
   occurrence count — the reviewer re-runs it.
3. **Fix every sibling inside the change's scope in this round** — scope =
   the layers this change touches plus the generated surfaces they feed. For
   each sibling you leave, name it and say which: (a) NOT an instance of the
   class — one reason, checked by the reviewer; or (b) OUT OF SCOPE — an
   instance in a layer this change never touched. List (b) under
   `- Out-of-scope siblings:`; the orchestrator files them as a follow-up
   change. Never widen a feature change into a repo-wide refactor to close a
   class — Solution Selection Ladder and "Modify files outside the task
   scope" still bind. Each sibling you DO fix gets its own read: same class
   does not mean same fix — a sibling with a different transaction boundary,
   actor, or caller may need a different change or none.
4. **Re-check the seeds on the new code**: the fix's own external calls,
   list reads, and error paths still follow Production-Aware Coding, and the
   fix has its own test (folded mode) — a fix round is the most likely place
   for a new defect to enter.

Append to your coding report, one block per P0/P1 finding:

```
### Class Sweep
- Finding: {P-sev} {≤80-char summary as the panel worded it}
- Class: {one line — the violated property}
- Search: {command or scope you enumerated with}
- Occurrences: {N} — fixed: {list}; not affected: {list — one reason each}
- Out-of-scope siblings: {list — layer never touched by this change; or "none"}
```

A fix round whose report carries no `### Class Sweep` block for a P0/P1 is
an instance-only fix; the reviewer files it as a P1 and the round repeats.
