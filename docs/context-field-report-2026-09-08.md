# Portal context analysis — where espalier agents' tokens actually go (2026-09-08)

Source: 565 subagent transcripts (coder 192, reviewer 143, scout 132, security 84) and 45 orchestrator
sessions under `~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au/`, 2026-08-09 → 2026-09-08,
plus `portal.quota.com.au/espalier/` (68 change records, 292 espalier commits) and the v0.24 templates.
Scripts: `mine_transcripts.py`, `mine2.py`, `mine3.py`, `mine4.py` (this scratchpad). "total_in" = sum of the
context sent on every API call (cache reads included) — the quantity that scales cost and latency.

## 1. Spend map

| Agent | spawns | calls (med) | first-turn ctx | peak ctx | total_in / spawn | sum |
|---|---:|---:|---:|---:|---:|---:|
| harness-coder | 192 | 38 | 74k | 196k | 6.2M | 1,710M |
| harness-reviewer | 143 | 21 | 74k | 172k | 2.7M | 449M |
| scout | 132 | 11 | 52k | 88k | 0.8M | 214M |
| harness-security | 84 | 13 | 72k | 152k | 1.5M | 192M |
| orchestrator session | 45 | ~120 | 94k (Aug) / 146k (Sep) | 329k (max 734k) | 27.6M | 1,733M |

Total ≈ 4.4B input tokens processed; coder spawns alone are 39 %.

### What each token-turn is made of

| Component | coder | reviewer | security | orchestrator |
|---|---:|---:|---:|---:|
| first-turn baseline × calls (system + user-global + rules + agent body) | 41 % | 54 % | 56 % | 39 % |
| tool results (code, diffs, artifacts, bash output) | 24 % | 22 % | 22 % | 13 % |
| own output (reasoning + Write/Edit/Bash payloads) | 12 % | 5 % | 6 % | 25 % |
| user-side text (prompts, task-notifications, hook injections) | 1 % | 1 % | 1 % | 9 % |
| per-change artifacts only (pack + requirements + coding-report + records) | 3.5 % | 5.8 % | 5.6 % | <1 % |

### The baseline is mostly not espalier

A bare session in `espalier-engineering` (no project CLAUDE.md, no espalier rules, same Claude Code 2.1.263 and
model) starts at **72k tokens**. A portal harness spawn in September starts at **91k**. So ≈ 70k of every
subagent turn is the user-global harness (`~/.claude/CLAUDE.md` + 15 rule files = 28.6 KB, ~130 listed skills,
~50 listed agents, MCP server instructions, hook output) and ≈ 20k is espalier (rules 75 KB ≈ 21k, agent body
24 KB ≈ 6.5k). Weekly medians for harness spawns: 61k (wk32) → 74k → 91k → 103k (wk35, rules at 139 KB) → 91k
(wk36, after the 2026-09-07 compress `eea0a620`). Rules growth explains ≈ 30k of the August rise; the rest is
the global harness and version drift.

### The tail: long coder spawns

- 49 % of coder spawns peak above 200k; 16 % above 300k; 5 % above 400k (max 448k, 141–193 calls).
- 51 % of all coder tokens are processed on turns whose context already exceeds 200k; 78 % above 150k.
- Top 20 % of spawns = 49 % of coder spend. Stage 5 test-writing spawns cost the same as Stage 3
  (7.4M vs 7.2M median); fix rounds 5.0M.
- Reviewer: 49 % of spend at ctx > 150k; security 34 %.
- Coder context at first source edit ≈ 160k regardless of pack (baseline + discovery reads).

### The context pack works (v0.21)

| coder cohort | n | first edit at turn | calls | total_in |
|---|---:|---:|---:|---:|
| read the pack | 95 | 13 | 33 | 5.4M |
| no pack (pre-v0.21 or fix lane) | 97 | 18 | 45 | 7.2M |

Adoption is 100 % since September.

### Orchestrator

- First-turn 117–178k in September: ≈ 72k global + rules 21k + `/espalier` skill 56 KB (≈ 15k) + `pipeline.md`
  23 KB + `agent.md` 7 KB. Every one of the 50–390 calls in a session re-reads that.
- Zero compactions in 45 sessions; sessions run whole pipelines to 300–730k context.
- Own output is 25 %: Bash gate scripts 3.5 MB (4,934 calls), Agent prompts 1.9 MB, Write 0.8 MB, Edit 0.7 MB,
  AskUserQuestion 0.6 MB across 45 sessions. Prose is only 18 KB per session.
- Subagent final messages arrive as task-notifications: median 3.6 KB (scouts 7.6 KB) — small.
- The orchestrator reads records correctly by sentinel (`grep '^VERDICT:'`): coding-report read once,
  security-record 3×, review-record 7× in 45 sessions.

### Things that are NOT levers (measured)

- Test output: `silent: "passed-only"` already; median 0.7 KB, p90 4.4 KB per run.
- Spawn prompts: 3–4 KB; 88/195 coder prompts paste the requirement, still ≤ 12 KB.
- Hook injections into subagents: 0 bytes. System-reminders: 0.
- Wiki: not read by pipeline agents (coder 0.1 reads/spawn, reviewer 0); read by scouts (doctor/prune) and grill.
- Explicit re-reads of `espalier/rules/*` after the reword: 2 in 23 post-compress spawns.

### Pure waste, small

- 17 % of coder and 21 % of reviewer spawns re-Read their own agent file (24–25 KB, already the system prompt)
  because the spawn prompt says "Read espalier/agents/harness-X.md for your full instructions".
- Duplicate reads of the same file inside one spawn: 13–17 KB per harness spawn.
- Agents page persisted oversized tool outputs back in with `sed -n 1,400p …/tool-results/…` (up to 28 KB a chunk).
- Template growth per release (source of truth, bytes): coder agent 12.3k (v0.13) → 23.6k (v0.24); reviewer
  14.4k → 25.2k; `/espalier` skill 29k → 56k; fix skill 51k → 63k; pipeline.md 13.7k → 22.7k.

### Quality signal

Only 24 Stage-4 panel rounds could be joined to the coder spawn that preceded them; no usable correlation between
coder peak context and P0/P1 findings can be drawn from this data. The r2 field note stands: three runs on the
compressed rules kept normal round counts.

## 2. Implications, ranked by measured leverage

1. **Per-turn baseline (41–57 % of every agent's spend, 39 % of the orchestrator's).** Any KB removed from the
   always-loaded set pays on every call of every agent. ≈ 70k of it is the user's global harness, not espalier;
   ≈ 20k is espalier rules + agent body.
2. **Spawn length.** Half of coder tokens are spent above 200k context, where attention is weakest and each
   turn costs the most. The pipeline principle "one task per context window" exists in `agent.md` but nothing
   enforces it; Stage 5 test spawns are as long as Stage 3 spawns.
3. **Orchestrator session shape.** 115–150k baseline × 100–400 calls, no stage-boundary reset, although
   `pipeline-state.md` RESUME already supports one.
4. **Artifact diet (r3).** Right in direction, but it moves 3.5–6 % of harness spend (r3's own model: 40 % of
   artifact bytes ≈ 2 % of total). Its value is attention (a 177 KB report handed to two panel agents) and
   stopping the growth engines (append-only report, requirements as design doc, CLAUDE.md rewrites).
5. **Discovery cost inside a spawn** is already addressed by the pack (−25 %); the remaining ≈ 85k of reads
   before the first edit are code and tests the coder genuinely needs.

## 3. Ways to improve (quality-neutral first)

### A. Cut the per-turn baseline

- **User-global (outside espalier, largest single lever):** trim `~/.claude/rules/*` (28.6 KB, 15 files;
  several describe stores that are empty or tools not used in the pipeline), prune the skill and agent listings,
  and disable MCP servers not needed for coding sessions. A halving is ≈ −35k per call ≈ −15 to −20 % of all
  portal spend with zero effect on espalier gates.
- **Rules budget (r2 §2, carried to v0.26):** 75 KB → ≈ 50 KB under the 12 KB/file contract: ≈ −7k per call.
- **Agent bodies as system prompts:** coder 24 KB and reviewer 25 KB are loaded every call. Keep the gate
  rubric and hard constraints in the body; move procedure prose the agent reads anyway from the phase skill
  (`espalier-coding/SKILL.md`, `espalier-review/SKILL.md`) out of the body. Target ≈ 12 KB each (v0.19 size)
  ≈ −3k per call. Every rubric line that a gate greps stays.
- **Stop the self re-read:** spawn line → "Your instructions are already loaded from
  `espalier/agents/harness-X.md` (auto-loaded on Claude Code; read it only if absent)". Removes 6–7k resident
  tokens in one spawn of five.

### B. Bound spawn length (coder first)

- **Decomposition size rule at Stage 3 entry:** a sub-task is ≤ N planned files / one layer pair; Stage 5
  test-writing split per test file group. The orchestrator already dispatches parallel sub-tasks and
  concatenates reports, so the machinery exists; only the size criterion is missing.
- **Checkpoint-and-return:** coder body gains a turn budget ("after ~40 tool calls, or when the task is not
  finishable in ~10 more, write the coding report with a `## Handoff` block — done, remaining, next file —
  and return"); the orchestrator re-spawns a fresh coder with the handoff, the same path fix rounds use.
  Fresh context restores instruction adherence; total_in per task drops because the second half no longer
  re-reads 200k+ every turn.
- **Stage 5 first:** test spawns are the cleanest split (one spawn per test file group) and are 29 % of
  coder spend.

### C. Reshape the orchestrator session

- **Stage-boundary reset:** after Stage 2 approval and after Stage 4 PASS, the skill prints "state saved —
  `/clear` then `/espalier` resumes at Stage N" and stops. Peak drops from ≈ 330k to ≈ 150k; the Stage 7–10
  procedure then runs on a fresh context, where the field failures have been.
- **Skill as router:** `/espalier` SKILL.md 56 KB → ≈ 15 KB router + per-stage procedure files read at stage
  entry (Stages 7–10 never load in a maprun worker). r2 Track C (pipeline.md = contract, ≈ 9 KB) on top.
- **Shorter gate scripts:** the Bash payloads are 47 % of the orchestrator's own resident output; ship the
  build/lint/test gate as one helper in `espalier/hooks/` and call it, instead of restating the script each stage.

### D. Keep r3, re-labelled

Ship the artifact diet as attention hygiene, not as the context release: current-spawn report + `coding-log/`,
requirements contract + notes, security-contract extract, advisory cap, edit-the-claim docs clause. Its measured
context effect is ≈ 2–3 % of total spend; its quality effect (smaller, current inputs to the panel) is the
argument. The `Grep-only:` pack line is cheap and covers the 497 KB generated `graphql.ts`.

### E. Hygiene lines (one-liners)

- Agents: "grep the persisted tool-result file; never page it back with sed".
- Agents: "do not re-Read a file you already have in context unless it changed".
- Orchestrator: keep `git diff` for the panel scoped to the round's changed files (already computed as
  CHANGED SINCE LAST REVIEW).

## 4. Proof plan that fits the existing evals

Same A/B discipline as v0.23: pin the model, run `eval/coder`, `eval/review`, `eval/security` on (a) current
templates, (b) trimmed agent bodies + router skill, (c) plus the checkpoint rule; pass = planted-defect catch
unchanged, FP ≤ baseline. Field smoke = one feat + one fix on the portal with `espalier-stats.sh` gaining a
context row (first-turn ctx, peak, calls per spawn) so the number is tracked per run instead of mined from
transcripts.

## 5. Housekeeping found on the way

- `docs/context-diet-plan.md` (r3) and `docs/context-diet-model.py` are no longer on disk in
  `espalier-engineering` (only `docs/__pycache__/context-diet-model.cpython-314.pyc` remains, 15:54). Not
  gitignored, no stash, no worktree. Both recovered from the previous session's transcript:
  `context-diet-plan.r3.md` and `model-py-heredoc.sh` in this scratchpad.
- `espalier/.migrations-skipped` on the portal: the v0.23.0 coding fold was never ported into the customised
  `espalier-coding/SKILL.md`.
