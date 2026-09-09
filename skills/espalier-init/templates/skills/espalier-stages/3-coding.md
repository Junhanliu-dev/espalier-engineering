# /espalier — Stage 3 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 3
> starts (coding — requirements approved). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 3 Entry: Context Pack (assemble once — every spawn reuses it)

In the SAME orchestrator turn that presents the Requirements Approval Gate
prompt — the pack is paths/facts only and approval-independent, so
assembling it while the human reads the gate saves one turn — write
`espalier/changes/{type}/{slug}/context-pack.md` (overwrite if resuming a
pre-Stage-3 crash; never rewrite it mid-loop — re-spawn rounds reuse it).
On **Edit** that changes the layer set, re-derive the pack before
re-asking; on **Abort** the pack is dead weight in the aborted change dir —
harmless:

```markdown
# Context Pack: {slug}
- Requirement: espalier/changes/{type}/{slug}/requirements.md
- Layers touched: {layer list, from the task decomposition}
- Layer specs: espalier/skills/espalier-coding/specs/{layer}.md  (one line per touched layer)
- Rules: espalier/rules/coding-standards.md · engineering-structure.md · security-standards.md · production-standards.md
- Reference files: {1-2 existing files per touched layer that exemplify its conventions}
- Facts established: {verified facts a spawn must not re-derive, one per line, each with `path:line` — or "none"}
- Grep-only: {`grep_only_files` output — path (size), one per line; or "none"} — searched, never Read; grep for the symbol
- Scoped docs: {`scoped_docs <reference files>` output — nearest last; or "none"} — workspace docs on the path from each reference file up to the repo root (root instruction file excluded — always loaded). Grep each for the files you touch; Read the matching sections (offset/limit). A claim there is a trap, an invariant, a deliberate stub, or a rejected alternative: verify it against the code before relying on it, as with the pack.
- Build: {build command} · Lint: {lint command} · Tests: {test command}
```

Fill the two new lines from the helpers (`. espalier/hooks/drift-helpers.sh`):
`grep_only_files` lists every tracked file matching `grep-only-paths:` in
`espalier/.espalier-config` with its size — patterns and sizes, no threshold;
`scoped_docs {reference files}` walks up from each reference file collecting
`CLAUDE.md` / `AGENTS.md`, nearest last, root excluded, de-duplicated. Empty
output → `none`. On Codex / Copilot the `- Scoped docs:` line is the only path
by which a workspace doc reaches a coder.

**Requirement shape (information only).** Before the first coder spawn,
print `req_shape_check "espalier/changes/{type}/{slug}"` — every
`requirements.md` heading outside the contract set (espalier-requirements
→ "Contract and notes"), each with `→ requirements-notes.md`. No size, no
refusal: the human approved this text at the gate; the line is for the next
Stage 2, not this Stage 3.

Derive the layer list and reference files ONCE (from the requirement +
`engineering-structure.md` + a quick glob of the touched layers) — this is
exactly the discovery the coder, both panel agents, and the test spawns
would otherwise EACH repeat from scratch. The pack lists PATHS AND FACTS
only — never conclusions, never verdicts, never "this part is fine": every
agent still reads the named files itself and trusts the current code over
the pack. Add the `CONTEXT PACK:` line to EVERY Stage 3-6 spawn prompt (the
prompt templates below carry it). A spawn that finds no pack (resumed old
change, fix lane before its pack step) falls back to its own discovery —
the pack is an accelerator, never a gate.

### Parallel Sub-Tasks (Stage 3)

Size each sub-task as one coder's bounded work — one seam: a schema list
with its hooks and tests; one screen with its hook and its GraphQL
documents; one resolver with its abuse tests. The test of a good size is
that a coder starting fresh finishes it with its instructions still at
full strength. When unsure, split: a second spawn costs one context-pack
read; a spawn that runs past its attention costs a review round. Test
writing splits the same way at Stage 3 — one spawn per test-file group.
The contract phase stays one spawn; a contract too large for one spawn
hands off (harness-coder.md → Handoff). Splitting changes DISPATCH only:
the panel still reviews the COMBINED diff once.

When the task decomposition yields several sub-tasks, compare their planned
file sets. Sub-tasks are PARALLEL-SAFE only when the sets are pairwise
disjoint — counting any shared module both would edit (barrel files, route
tables, migration indexes, shared fixtures are overlap — and each
sub-task's planned TEST files count too: shared test fixtures, helpers, or
suite barrel files are overlap). Dispatch
parallel-safe sub-tasks as concurrent `harness-coder` spawns in ONE message,
with two extra lines in each prompt:

- `REPORT TARGET: espalier/changes/{type}/{slug}/coding-report.part-{n}.md`
  — parts, never `coding-report.md` directly.
- `PARALLEL DISPATCH: do NOT run the build / test / dependency-install
  commands — other coders share this working tree and concurrent runs
  corrupt each other. Write code only; the orchestrator runs the exit gate
  on the combined result.` (The coders' self-run build is a convenience
  check, not a gate — the orchestrator's Stage 3 exit gate is, and it still
  runs.)

After ALL return, check each part for the handoff sentinel first
(`grep -q '^- HANDOFF: true' coding-report.part-{n}.md`): a part that
carries it is archived (`report_archive` with the part's path as DIR is not
the shape — move it by hand to `coding-log/NN-handoff-{n}-part{k}.md`) and
continued by a fresh coder on the SAME part target with the `CONTINUATION:`
line (Stage 3 exit gate, below) BEFORE concatenation; the combined report
never carries the sentinel. Then concatenate the parts into
`coding-report.md` in sub-task order — KEEP the part files until the Stage 3
exit gate passes — and run the
exit gate ONCE on the combined tree. A failure attributable to one sub-task
re-spawns only that coder, again targeting ITS `coding-report.part-{n}.md`
(never `coding-report.md` — an overwrite there would erase the other
sub-tasks' reports that Stages 4-6 read); re-concatenate after the fix.
Unclear attribution → re-run the failing sub-tasks serially (serial
re-spawns may run the build themselves again). Only after the exit gate
passes, delete the part files. Any overlap or uncertainty → serial dispatch,
exactly as before. Parallelism changes DISPATCH only — the Stage 4 panel
always reviews the COMBINED diff, and the review/gate contract is untouched.

### Sub-Agent Delegation

Stages 3-6 use sub-agents for separation of concerns:

**Stage 3 (Coding):**
```
Agent tool:
  prompt: |
    You are the harness-coder.
    Your instructions are espalier/agents/harness-coder.md (auto-loaded as
    your system prompt on Claude Code; read it only if it is not already in
    your context).

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first; it names the layers/specs/rules/reference files (paths and facts
    only — verify against current code).
    REQUIREMENT: {paste requirement from Stage 1 output}
    TASK: {specific sub-task from decomposition}
    {On a continuation after a handoff add:}
    CONTINUATION: espalier/changes/{type}/{slug}/coding-log/NN-handoff-{n}.md
    — read its ## Handoff first; its Facts are verified (cite them, do not
    re-derive), its Remaining is your task list.
    TESTS: alongside the code, write the interface tests and failure-mode
    tests for this change per espalier/skills/espalier-testing/SKILL.md —
    everything EXCEPT contracted abuse tests (that contract does not exist
    yet; it comes from the Stage 4 security audit). List the test files in
    their own "Test files" subsection of the coding report.
    {On a change whose requirements.md carries simplify_from: add:}
    SIMPLIFICATION CHANGE: read espalier/agents/modes/simplification.md
    first (its harness-coder section) — requirements.md is a cut filed by
    /espalier-simplify; apply "Simplification Changes: Retire the Whole
    Obligation" and report a "### Retired Surface" block.

    When done, write your coding report to:
    espalier/changes/{type}/{slug}/coding-report.md
```

(With `test-mode: serial`, drop the TESTS lines — tests are written after
the final panel PASS instead; see the Stage 5/6 section.)

**Stage 3 exit gate (PROGRAMMATIC — after EVERY coder return, before any
panel spawn).** Order matters — sentinel first, gate second, so a handoff
report is archived before anything overwrites or appends to it:

1. **Sentinel.** `grep -q '^- HANDOFF: true' espalier/changes/{type}/{slug}/coding-report.md`
   (after a parallel wave: each `coding-report.part-{n}.md`). Present → the
   coder handed off at a clean point (harness-coder.md → Handoff).
2. **Archive** (sentinel present). `. espalier/hooks/drift-helpers.sh &&
   report_archive "espalier/changes/{type}/{slug}" "handoff-{n}"` moves the
   report to `coding-log/NN-handoff-{n}.md` ({n} counts this change's
   handoffs); append `| 3 | HANDOFF {n} | {ts} | {remaining item count};
   next: {file} |` to Stage History.
3. **Gate.** `exit_gate "espalier/changes/{type}/{slug}"` (drift-helpers.sh)
   runs the discovered build and lint as two concurrent jobs, then — folded
   mode — the discovered test command scoped to the coding report's listed
   test files where the runner supports path filtering (full suite where it
   does not; the old Stage 5 "tests pass" gate, moved earlier — the panel
   must never review tests nobody has executed), and prints one line per
   job plus the log path of any failure. The commands have one source: the
   `run_build` / `run_lint` / `run_tests` bodies init substituted into
   `espalier/hooks/pre-push-gate.sh`. Exit codes: `0` green; `1` a job
   failed — red; `2` a `run_*` function is missing or unparseable in a
   customised gate; `3` the greenfield placeholder gate. Only `1` is red.
   On `2` or `3` run the gate by hand exactly as before: build + lint as
   two concurrent background jobs in ONE bash call (`$BUILD & $LINT &`,
   per-pid `wait`s, each job's output to its own temp file) — UNLESS the
   discovered commands plainly depend on each other, then serial — then the
   scoped test run; concurrency changes the wait, never the gate. The
   coder's self-reported "Build status: pass" is a claim, not the gate. On
   red, archive the current report (`report_archive … "exit-gate-fix"`) and
   re-spawn the coder with the failing job's log — do NOT spawn the review
   panel on unbuildable or failing code (a wasted panel round), and do NOT
   count it as a P0 round.
4. **Continuation** (sentinel present). Green or red, the next spawn is a
   fresh `harness-coder` with the SAME prompt (same REPORT TARGET for a
   part) plus the `CONTINUATION:` line naming
   `coding-log/NN-handoff-{n}.md` — and, when the gate was red, the failing
   log, exactly as a red gate re-spawns a coder. The panel is spawned only
   on a report without the sentinel. Unattended runs (maprun workers) need
   no human for any of this.

`report_archive DIR LABEL` runs before EVERY coder spawn after the first,
so `coding-report.md` is always the CURRENT spawn's report and every prior
spawn's report is one file in `coding-log/` (read only when named). Labels
name the spawn that wrote the archived report: `stage3` (`stage3-part{k}`
for a wave's parts), `handoff-{n}` (`handoff-{n}-part{k}`), `round{n}-fix`
(the FIX ROUND {n} report), `exit-gate-fix`, `contract-phase`. A no-op when
no report exists.

**`test-mode` (read once at Stage 3 entry — word-key pattern, NOT the round
caps' integer grep):**

```bash
TEST_MODE=$(grep '^test-mode:' espalier/.espalier-config 2>/dev/null | awk '{print $2}')
if [ -z "$TEST_MODE" ]; then
  LEG=$(grep '^speculative-tests:' espalier/.espalier-config 2>/dev/null | awk '{print $2}')
  [ "$LEG" = "off" ] && TEST_MODE=serial || TEST_MODE=folded
fi
case "$TEST_MODE" in folded|serial) ;; *) echo "WARN: unknown test-mode '$TEST_MODE' — using folded" >&2; TEST_MODE=folded ;; esac
```

`folded` (default): tests ride the Stage 3 coder and the panel reviews
code+tests together. `serial`: tests are written AFTER the final panel
PASS and reviewed at Stage 6 — the pre-v0.22 flow, kept as the
conservative fallback. The legacy `speculative-tests` key maps through the
table above; `.espalier-config` is user-owned and never auto-rewritten.
