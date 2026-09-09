# Quality-First Context Plan (v0.25.0 + v0.25.1) — Fresh, Bounded, Current

> **Constraint (same as v0.21 / v0.23 / v0.24):** every gate, every agent
> rubric, every verdict sentinel, every round cap, and every escalation path
> is contract-equal to v0.24.0. **This release sets no hard budget of any
> kind** — no size cap on a file, no turn cap on a spawn, no refusal on
> size, no numeric cap on findings. The pre-existing escalation caps
> (`max-req-rounds` / `max-code-rounds` / `max-test-rounds` / `max-rollbacks`,
> default 3) are not context budgets — they stop loops — and stay (owner,
> 2026-09-09). So do the pre-existing bounds on interaction and fan-out
> shape — grill question tiers, auditor and scout batch counts, the
> simplify lead cut (§1) — which bound how many questions a human is asked
> or how work is split, never what one agent reads or writes. Every
> mechanism below is one of three
> things: a protocol an agent follows, a default the orchestrator applies,
> or a number the human sees. Smaller context is the expected by-product,
> never the goal; the goal is that every agent works with its instructions
> at full strength on current inputs. Goal order (owner, 2026-09-09):
> context under control, with coding quality kept maximal — where the two
> conflict, quality wins and the context lever is dropped (§10 lists the
> ones dropped for that reason).

Status: **IMPLEMENTED in the working tree — v0.25.0 INCLUDING the former
v0.25.1 scope** (2026-09-09, r4.8: B.2 router + `stages/`, B.3 pipeline
contract, D.8 mode files, check 66 all ship in v0.25.0 at the owner's
direction — "add deferred item into this one"; migration #35 carries them,
there is no #36). Uncommitted, awaiting the owner's branch / commit / eval
run / portal migration — §9 steps 2–6. Implementation notes in §15 r4.7 /
r4.8.
Previously: **draft r4.6** (2026-09-09), owner review pending. r4 is the fourth
revision of the v0.25 context plan: r1/r2 (rules diet) and r3 (artifact
diet) were `docs/context-diet-plan.md`; that file is no longer on disk (r3
text is in the 2026-09-08 05:42Z session transcript; the r2/r3 designs this
plan keeps are restated here in full, so nothing depends on it). r4 reframes
after the owner's direction — *keep the highest coding quality; context
reduction is a bonus; no hard budgets* — and after the first measurement of
where tokens actually go (§0), which re-ranks the fixes. r4.1 (same day)
adds what the transcripts say about on-demand disclosure (§0.9) and the two
protocol lines that close it (Track D.5, D.6). r4.2 (2026-09-09) applies
the fresh-eyes review: three protocol collisions in Track A, the template's
own `≤ 5 files` cap, real anchors and a command source for Track B, and the
release split (§9, §14). r4.3 (2026-09-09) applies the second review:
single-source gate commands, the grill's read cap reworded, archive call
sites, the remaining anchors. The plan spans v0.25.0 (Tracks A, C, D, E, F,
B.1, B.4) and v0.25.1 (B.2, B.3). r4.4 (2026-09-09) applies the third
review: every read-budget reference in the grill and map skills reworded,
the pre-existing interaction and fan-out bounds classified and kept,
`exit_gate` hardened (brace depth, `bash -n`, exit codes, greenfield), F.1's
count corrected. r4.5 (2026-09-09): the grill's code reads are unlimited
(owner) — A.5 rewritten. r4.6 (2026-09-09) fills the context-goal gaps:
expected-effect model (§0.10), mode files for the agent bodies (D.8,
v0.25.1), report-only rows for the platform's doc injection and the
workspace docs (F.4), the A.5 ↔ B.1 link, Appendix A as a checklist, and
the quality invariant stated where levers are dropped (§4, §10).

## 0. Field evidence (transcripts, not file sizes)

Source: every subagent transcript the portal produced,
`~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au/*/subagents/*.jsonl`
(565 spawns: coder 192, reviewer 143, scout 132, security 84) and the 45
orchestrator sessions that spawned them, 2026-08-09 → 2026-09-08, plus the
portal's `espalier/` (68 change records, 292 espalier commits) and the v0.24.0
templates. "total" below is the context sent on every API call, summed —
the quantity that scales cost, latency, and how far from its instructions
an agent is working. The mining script ships with this release (§3, Track F).

### 0.1 Spend map

| Agent | spawns | calls (median) | first-turn ctx | peak ctx | total / spawn | sum |
|---|---:|---:|---:|---:|---:|---:|
| harness-coder | 192 | 38 | 74k | 196k | 6.2M | 1,710M |
| harness-reviewer | 143 | 21 | 74k | 172k | 2.7M | 449M |
| scout | 132 | 11 | 52k | 88k | 0.8M | 214M |
| harness-security | 84 | 13 | 72k | 152k | 1.5M | 192M |
| orchestrator session | 45 | ~120 | 94k (Aug) / 146k (Sep) | 329k (max 734k) | 27.6M | 1,733M |

### 0.2 What a token-turn is made of

| Component | coder | reviewer | security | orchestrator |
|---|---:|---:|---:|---:|
| first-turn baseline × calls (system + user-global + rules + agent body) | 41 % | 54 % | 56 % | 39 % |
| tool results (code, diffs, artifacts, bash output) | 24 % | 22 % | 22 % | 13 % |
| own output (reasoning + Write / Edit / Bash payloads) | 12 % | 5 % | 6 % | 25 % |
| user-side text (prompts, task-notifications, hook injections) | 1 % | 1 % | 1 % | 9 % |
| of which per-change artifacts (pack + requirements + report + records) | 3.5 % | 5.8 % | 5.6 % | <1 % |

### 0.3 The baseline is mostly not espalier

A bare session in `espalier-engineering` (no project `CLAUDE.md`, no
espalier rules, same Claude Code 2.1.263 and model) starts at **72k**. A
portal harness spawn in September starts at **91k**. So ≈ 70k of every
subagent turn is the owner's global harness — `~/.claude/CLAUDE.md` plus 15
rule files (28.6 KB), ~130 listed skills, ~50 listed agents, MCP server
instructions, hook output — and ≈ 20k is espalier: rules 75 KB (≈ 21k) and
the agent body (24 KB ≈ 6.5k). Weekly medians for harness spawns: 61k (wk32)
→ 74k → 91k → 103k (wk35, rules at 139 KB) → 91k (wk36, after the owner's
2026-09-07 compress `eea0a620`). Rules growth explains ≈ 30k of the August
rise; the rest is the global harness and Claude Code version drift. The
global part is outside this plugin (Appendix A). Attachment payloads
measured per spawn: skill listing 34 KB, agent listing 11 KB, MCP
instructions 3.7 KB, user + project instruction files 110 KB (178 KB before
the compress).

### 0.4 Long spawns

- 49 % of coder spawns peak above 200k; 16 % above 300k; 5 % above 400k
  (max 448k at 141–193 calls).
- 51 % of all coder tokens are processed on turns whose context already
  exceeds 200k; 78 % above 150k. Reviewer: 49 % of its spend above 150k.
- The top 20 % of coder spawns are 49 % of coder spend. Stage 5 test-writing
  spawns cost what Stage 3 spawns cost (7.4M vs 7.2M median); fix rounds 5.0M.
- A coder's context at its first source edit is ≈ 160k with or without a
  pack: the baseline plus the code and tests it genuinely needs.

`agent.md` says "Decompose into tasks that fit one context window each" and
"NEVER exceed context — break the task smaller"; nothing in the machinery
gives the coder a way to act on it once inside a spawn.

### 0.5 The context pack works (v0.21)

| coder cohort | n | first edit at turn | calls | total / spawn |
|---|---:|---:|---:|---:|
| read the pack | 95 | 13 | 33 | 5.4M |
| no pack (pre-v0.21 or fix lane before its pack step) | 97 | 18 | 45 | 7.2M |

Adoption is 100 % since September.

### 0.6 The orchestrator

- First turn 117–178k in September: ≈ 72k global + rules 21k + the
  `/espalier` skill (56 KB ≈ 15k) + `pipeline.md` (22.7 KB) + `agent.md`.
  Every one of the 50–390 calls in a session re-reads all of it.
- Zero compactions in 45 sessions; whole pipelines run to 300–730k context,
  so Stages 7–10 run on the fullest context the session ever has.
- Own output is 25 %: Bash gate scripts 3.5 MB (4,934 calls), Agent prompts
  1.9 MB, Write 0.8 MB, Edit 0.7 MB across 45 sessions; prose only 18 KB a
  session. The exit-gate bash is retyped every stage.
- Subagent final messages arrive as task-notifications: median 3.6 KB. The
  orchestrator reads records by sentinel (`grep '^VERDICT:'`), as designed.

### 0.7 Not levers (measured) and pure waste

- Test output is already quiet (`silent: "passed-only"`): median 0.7 KB a
  run. Spawn prompts 3–4 KB. Hook injections into subagents: 0 bytes.
  The wiki is never read by pipeline agents (scouts and the grill read it).
- 17 % of coder and 21 % of reviewer spawns re-Read their own agent file
  (24–25 KB, already their system prompt) because the spawn prompt says
  "Read espalier/agents/harness-X.md for your full instructions".
- Duplicate reads of the same file inside one spawn: 13–17 KB a harness
  spawn. Agents page persisted oversized tool outputs back in with
  `sed -n 1,400p …/tool-results/…` (28 KB a chunk).
- Explicit re-reads of `espalier/rules/*` after the portal's reword line:
  2 in 23 spawns — the reword works.
- Template growth per release (bytes): coder agent 12.3k (v0.13) → 23.6k
  (v0.24); reviewer 14.4k → 25.2k; `/espalier` skill 29k → 56k; fix skill
  51k → 63k; `pipeline.md` 13.7k → 22.7k.

### 0.8 What the evidence does and does not say about quality

- Only 24 Stage-4 panel rounds could be joined to the coder spawn that
  preceded them; no correlation between coder peak context and P0/P1
  findings can be claimed from this data.
- Three portal runs on the 48 % smaller rules kept their round counts
  (r2 field note, PRs #182 / #183 / #193).
- Everything else in this plan rests on design reasoning that is stated
  next to each fix (§3) and tested in §7, not on a measured quality delta.
  The plan therefore ships measurement (Track F) so the next revision has
  one.

### 0.9 On-demand disclosure: skipped or silent (r4.1)

Espalier discloses progressively by design: `agent.md`'s Config Index says
what loads when; the coder reads the coding skill and only the touched
layer's spec (`harness-coder.md:22 ff.`); the pack is paths and facts; the
wiki is on demand; scoped workspace docs ride Claude Code's nested memory.
The transcripts show the always-on layer loaded whole and the on-demand
layer followed inconsistently — share of spawns that opened the file:

| file | coder Aug | coder Sep | reviewer Aug | reviewer Sep | security Aug | security Sep |
|---|---:|---:|---:|---:|---:|---:|
| `espalier-coding/SKILL.md` | 26 % | 54 % | 2 % | 0 % | 0 % | 0 % |
| `specs/{layer}.md` | 19 % | 46 % | 22 % | 40 % | 0 % | 0 % |
| `espalier-review/SKILL.md` | — | — | 37 % | 83 % | — | — |
| `espalier-security/SKILL.md` | 2 % | 6 % | 0 % | 0 % | 58 % | 71 % |
| `espalier-testing/SKILL.md` | 31 % | 64 % | 23 % | 10 % | 1 % | 0 % |
| any scoped `CLAUDE.md`, explicit Read | 19 % | 70 % | 15 % | 63 % | 1 % | 23 % |

Scoped workspace docs by auto-load (`nested_memory` attachment) in harness
spawns that Read a `frontend/` or `backend/` file:

| Claude Code | spawns | got nested memory |
|---|---:|---:|
| 2.1.227 – 2.1.258 (Aug 9 – Sep 1) | 260 | 0 |
| 2.1.259 – 2.1.263 (Sep 2 →) | 10 | 10 |

The docs say a subdirectory `CLAUDE.md` loads when a file in that directory
is Read and that custom subagents load `CLAUDE.md` like the main
conversation (`code.claude.com/docs/en/memory`, `debug-your-config`); in the
field that held only from 2.1.259. When it fires it injects the whole chain —
54 KB median, 137 KB max per spawn — and a Read of `domains/x/CLAUDE.md`
itself pulls `frontend/CLAUDE.md` (observed 2026-09-07). On Codex and
Copilot nothing reads a `CLAUDE.md` at all; the plugin templates never
mention scoped docs, and the bootstrap's AGENTS.md / copilot-instructions
do not point at them.

The docs are live inputs on both sides of the panel: 26 portal review /
security records cite a `CLAUDE.md`, 15 finding rows reference one, and 25
coding reports name a `CLAUDE.md` claim under Staleness. Coders already cite
a spec spontaneously in 11 of 47 reports (`specs/backend-schemas.md` 12×).
No measured link between an unread spec and a later finding exists
(per-round records are overwritten; the 24-round join is too thin); the
case for D.5 / D.6 is mechanism plus this gap, and §7 gains the fixtures
that can test it.

### 0.10 Expected effect of the plan (model — expectations, never budgets)

A linear-growth model of each spawn (first-turn context, last-turn context,
calls) reproduces 88 % of measured coder spend and 94 % of reviewer spend;
the numbers below come from re-running it with each track's change applied
to the 565 spawns and 45 sessions. The handoff is judgment, not a count —
"~40 calls" is the sensitivity point, not a rule. Offers are modelled as
taken and prune as run.

| Track | Change modelled | Coder spend | Orchestrator spend | Quality |
|---|---|---:|---:|---|
| A handoff | long spawns split; modelled at ~40 calls (~60: −13 %, ~30: −27 %) | −22 % (124 extra spawns / 192) | — | + instructions fresh per seam |
| B.1 resume offer | reset after Stage 2 and Stage 4 | — | −37 % (one reset: −28 %) | + Stages 7–10 on fresh context |
| B.2 / B.3 router + contract (v0.25.1) | 15–20k fewer resident tokens per call | — | −12 – 15 % | + procedure at point of use |
| C current inputs | current report, contract files | −2 – 3 % | small | + panel attention |
| D load-once, D.5 / D.6 | self-read gone; spec and doc sections read | −1 – 2 %, then + one spec read | — | + |
| D.8 mode files (v0.25.1) | mode-only sections leave the always-on body | −2 – 3 % | — | + mode text read when it applies |
| E rules contract (prune, voluntary) | 75 → ~50 KB always-on | −5 % | −3 % | neutral; ledger-protected |
| reviewer / security | short spawns; handoff irrelevant | 0 – 1 % | — | — |

Sum, offers taken and prune run: coder ≈ −28 % now, ≈ −31 % with v0.25.1;
orchestrator ≈ −40 % now, ≈ −50 % with v0.25.1. Outside the plugin, halving
the owner's global harness is a further ≈ −20 % on every agent (Appendix A).
Nothing in the table removes an input an agent uses; §4 says which levers
were dropped to keep it that way.

## 1. Goals & Non-Goals

### Goals (quality mechanisms; context is the by-product)

1. **Instructions at full strength.** A coder works on bounded work and
   hands off cleanly when the work is not bounded — a fresh spawn with the
   handoff, never a 400k-token spawn.
2. **Current inputs.** The panel judges this change from this spawn's
   report, the contract sections of the requirement, and the security
   contract — never from history it must skip past.
3. **Procedure near the point of use.** The orchestrator is offered a fresh
   session at the boundaries where its state is already on disk (B.1,
   v0.25.0) and reads a stage's procedure when the stage starts (B.2,
   v0.25.1).
4. **Load once, read what is pointed at.** Nothing an agent needs is
   removed; nothing it already has is loaded a second time; an on-demand
   read the pipeline depends on leaves a visible trace (r4.1).
5. **Measured, not assumed.** Spawn shape lands in `espalier-stats.sh`; a
   transcript report ships as a dev script; the A/B evals run before the tag.

### Non-Goals

- **No hard budget anywhere** — restated because r1/r2 had one
  (`rule-budget-kb`, prune refusal at 1.5×) and r3 had two (`req_size_check`
  8 KB, advisory cap of three). All four are gone; §10 records why. The
  templates' pre-existing bounds on what an agent READS go the same way
  (A.5: the four `≤ 8` code-read references). Pre-existing bounds on
  interaction and fan-out shape stay, disclosed: grill question tiers
  (`espalier-grill.md:44, 122–123, 198` — `light` ≤ 3, `full` ≤ 7
  questions), audit dispatch (`espalier-audit.md:77–78` — ≤ 8 surface files
  per auditor, at most 4 batches), simplify dispatch and lead cut
  (`espalier-simplify.md:113, 416` — at most 4 batches; 12 leads in full,
  the rest one line each). Owner, 2026-09-09 (§14).
- No path-scoping of `security-standards.md` / `production-standards.md`
  (a rubric must not depend on which file an agent happened to Read).
- No LLM summarisation at load time; no per-agent rule exclusion.
- No renames: `coding-report.md` has 60+ consumers, `- REGRESSION_VERIFIED:`
  is appended by bash in the fix lane, `## Security-Sensitive Fields` is
  grepped in nine places. Files are split by ADDING a sibling.
- No automatic rewriting of any install's rules by the migration.
- The owner's global `~/.claude` harness (Appendix A) and model tiering
  (deferred, unchanged).

## 2. Design principles

- **Fresh.** A fresh spawn per bounded task; a fresh session offered at a
  stage boundary whose state is on disk.
- **Bounded.** Sub-tasks sized at decomposition; a handoff protocol inside
  the spawn for what decomposition missed. Both are judgment, neither is a
  number.
- **Current.** State file + log directory for everything that grows by
  append; contract file + notes file for everything that grows by prose.
- **Load once.** What is in the system prompt or auto-loaded is not Read;
  what was Read is not Read again unless it changed.
- **Protocol, not cap.** A cap makes an agent drop content to fit; a
  protocol makes it finish or hand off. The doctor and prune show sizes as
  information; nothing refuses on size.
- **Nothing renamed.** Every sentinel, block, path, and grep stays.

## 3. The tracks

### Track A — Bounded coder work (`harness-coder.md`, `espalier.md`, `espalier-fix.md`, `espalier-requirements.md`)

**A.1 Sizing at decomposition** (`espalier-requirements.md` §5 "Task
Decomposition", line 39 — the paragraph REPLACES line 45, `Rule: Each
sub-task should touch ≤ 5 files. If more, decompose further.`, the one
numeric sizing rule in the templates; `espalier.md` "Parallel Sub-Tasks
(Stage 3)", line 391 — a new paragraph before the parallel-safety rule):

```
Size each sub-task as one coder's bounded work — one seam: a schema list
with its hooks and tests; one screen with its hook and its GraphQL
documents; one resolver with its abuse tests. The test of a good size is
that a coder starting fresh finishes it with its instructions still at
full strength. When unsure, split: a second spawn costs one context-pack
read; a spawn that runs past its attention costs a review round. Test
writing splits the same way at Stage 3 — one spawn per test-file group.
The contract phase stays one spawn; a contract too large for one spawn
hands off (Handoff protocol). Splitting changes DISPATCH only: the panel
still reviews the COMBINED diff once.
```

(r4.2's per-family contract-phase dispatch is dropped: `espalier.md:657`
runs ONE test-coder spawn and no part-file or archive mechanism exists for
it — §10, §11.)

**A.2 The handoff protocol** (new section in `harness-coder.md`, inserted
before `## Editing Discipline` at line 295):

```
## Handoff: Finish Bounded, Hand Off Clean

You are one spawn among several the orchestrator can run. Your task should
fit one spawn; when it does not, hand off instead of pushing on with your
instructions far behind you. Signs it does not fit: the remaining work is
another whole seam (a second layer, a second screen, a second family of
tests); the TASK list still has items that do not depend on what you just
finished; you are about to start re-deriving facts you established early.

Hand off only at a clean point:
1. Finish the file you are in. Never hand off mid-edit.
2. Run the build (and lint where it exists). If it does not pass here,
   continue to the next clean point where it does — a handoff is never an
   excuse for a red tree. Tests you wrote pass, or are listed as red with
   the reason. Under PARALLEL DISPATCH (your prompt carries it) you never
   run the build: the clean point is every touched file syntactically
   complete, and the orchestrator gates the combined tree.
3. Write your report fresh (overwrite) — coding-report.md, or the REPORT
   TARGET part file your prompt names — with everything done so far, then
   a `## Handoff` block:
   - Done: {files, one line each — what it now does}
   - Remaining: {ordered; per file; the hard part named with what you tried}
   - Facts: {verified facts the next coder must not re-derive — each with
     `path:line`, exactly like the context pack's "Facts established"; a
     fact without a citation is not a fact}
   - Next: {the first file the next coder should open, and why}
4. End the report with the sentinel line `- HANDOFF: true`. The
   orchestrator reads it before any gate or append touches the file; in the
   fix lane the regression step is skipped on a report that carries it.

Never hand off to avoid a hard part — name it under Remaining with what
you tried. Never hand off with an unrun build outside PARALLEL DISPATCH.
The next coder reads your
Handoff first; the panel reviews the combined diff once, exactly as if
one coder had written it.
```

**A.3 Orchestrator handling** (`espalier.md` "Stage 3 exit gate", line
456; `espalier-fix.md` "Stage 3: Coding", line 655, and its regression
exit gate at 916–1005; the detector mirrors the existing
`TEST_SCOPE_INFLATION: true` grep, `espalier-fix.md:730`). Order matters —
sentinel first, gate second, so the handoff report is archived before
anything overwrites or appends to it:

1. **Sentinel.** After EVERY coder return, `grep -q '^- HANDOFF: true'` on
   the file the coder wrote — `coding-report.md`, or each
   `coding-report.part-{n}.md` after a parallel wave.
2. **Archive.** When present: `report_archive "{dir}" "handoff-{n}"`
   (part files: `handoff-{n}-part{k}`) moves it to `coding-log/`; append a
   Stage History row `| 3 | HANDOFF {n} | {ts} | {remaining item count};
   next: {file} |`.
3. **Gate.** Run the exit gate exactly as today (build + lint concurrent,
   scoped tests). Green or red, the next spawn is the same: a fresh
   `harness-coder` with the SAME prompt (same REPORT TARGET for a part)
   plus `CONTINUATION: espalier/changes/{type}/{slug}/coding-log/NN-handoff-{n}.md
   — read its ## Handoff first; its Facts are verified (cite them, do not
   re-derive), its Remaining is your task list.` — and, when the gate was
   red, the failing output, exactly as a red gate re-spawns a coder today.
   The panel is spawned only on a report without the sentinel.
4. **Parallel waves.** A part with the sentinel is continued (same part
   target) before concatenation; the combined report never carries it.
5. **Fix lane.** The regression-verification bash (`espalier-fix.md:916–1005`,
   which today appends `- REGRESSION_VERIFIED:` to `$COD` on every return)
   gains a first line: `grep -q '^- HANDOFF: true' "$COD"` → archive +
   continuation as above and skip the regression step. The appended line
   therefore lands only on a report without the sentinel, and LAST-line
   semantics hold.
6. Unattended runs (maprun workers) need no human for any of this.

**A.4 Why quality improves.** The coder that writes the second seam reads
its rubric, the pack, and a cited fact sheet at the top of a fresh context
instead of 250k tokens down. Facts carry citations so drift between spawns
is caught by the same rule the pack uses. No gate is skipped: the exit gate
runs on every return, the panel on the combined diff, the fix lane's
regression proof after the last report. Handoffs are counted per change
(Track F), so a coder that hands off habitually is visible.

**A.5 Grill reads: unlimited** (`espalier-grill.md:162, 168, 218` and
`espalier-map.md:174`, both lanes; pure-copy skills). The pre-existing
sentence at 218 — "Budget: ≤ 8 file reads per session; if you would exceed
it, ask instead", a read cap with a refusal — becomes: "Read as much of the
code as answering the question needs — there is no count. Ask the user only
for what the code cannot answer: product intent, priorities, an unratified
decision." The three references to the budget (grill 162 "does NOT count
against Step 2's ≤ 8 code-read budget", 168, map 174) lose the budget
clause — reading `rules/` and `wiki/` is simply always allowed. The grill's
existing stop rule is the only stop: "Stop the moment the next question's
answer would not change the implementation" (`espalier-grill.md:219`).
A verified premise handed to the coder in `requirements.md` and the pack's
"Facts established" is worth more than a saved read: the field shows
87 KB of "Staleness Encountered" sections and 25 reports naming a false doc
claim that Stage 1 could have caught (owner, 2026-09-09, §14). Check 65
asserts no `≤ 8` read budget remains in either skill. The grill's question
tiers (`light` ≤ 3, `full` ≤ 7) are interaction bounds and stay (§1).

Every grill read lands in the orchestrator's own context — Stage 1 runs in
the main session, not in a spawn. B.1's offer after Stage 2 approval is what
releases them: a fresh session starts from `requirements.md` and the pack,
and the code the grill read is gone. On "Continue here" they stay resident
for the rest of the run. The Stage 2 offer text says so, so the human
chooses knowingly; unlimited reads and the Stage 2 reset are one design.

### Track B — The orchestrator: fresh at boundaries, procedure near use

**B.1 Stage-boundary resume, offered** (`espalier.md` "Requirements
Approval Gate", line 263; the Stage 4 PASS write — panel procedure step 5,
lines 628–636, where the `| 4 | PASSED |` row and the Reviewed-Diff
certificate are written; serial-mode Stage 6 PASS; "Human Checkpoints",
line 1057).
After the state file is written at those points — it already is — the
orchestrator asks once (AskUserQuestion; first option is the default):

```
Continue here / Continue in a fresh session — run `/clear`, then
`/espalier` with no argument: Session Resumption picks this change up at
Stage {N} from pipeline-state.md.
(After Stage 2: everything Stage 1 read into this context — code, docs,
the grill's answers — stays resident on "Continue here"; a fresh session
starts from requirements.md and the context pack.)
```

Fix lane (`espalier-fix.md` approval gate at 605, Stage 4 at 740): the same
offer with a different second option — bare `/espalier-fix` does not resume;
the fresh session runs `/espalier-fix` with the same bug text, and the slug
collision offers Resume / extend (`espalier-fix.md:206, 238`).

Unattended runs (`interactivity_mode` returns `unattended`,
`drift-helpers.sh:325`) skip the offer exactly as the Completion's BUILT
offer does (`espalier.md:1079`). On resume, the orchestrator appends
`| {N} | RESUMED | {ts} | fresh session |` to Stage History (Track F reads
it). Nothing forces the reset; Session Resumption (`espalier.md:184–241`)
is unchanged.

**B.2 Procedure at stage entry** (`templates/skills/espalier.md` → router
plus stage files). The SKILL.md keeps: When to Use, Instructions, Before
Starting, Flag Parsing, Stage 0 Pre-Flight, Convention Promotion, Session
Resumption, Stage Execution Protocol, State File Format, Rollback Protocol,
Human Checkpoints, Completion. Each stage's procedure moves, verbatim, to
`templates/skills/espalier/stages/`:

| File | Sections moved (v0.24 line) |
|---|---|
| `1-2-requirements.md` | Requirements Approval Gate (263) |
| `3-coding.md` | Stage 3 Entry: Context Pack (359), Parallel Sub-Tasks (391), Sub-Agent Delegation Stage 3 + exit gate + test-mode (423–493) |
| `4-panel.md` | Stage 4 prompts + panel procedure (494–637), Stage 4 Post-Review (775) |
| `5-6-contract.md` | Stage 5/6 folded (638), serial Stage 5/6 (722 ff.) |
| `7-10-delivery.md` | Stage 7 convention index + commit recording + reverse-link (913–1000), Stage 8.5 (1001) |

The router's Stage Execution Protocol gains one line per stage:
`Procedure: read espalier/skills/espalier/stages/{file} now, then run it.`
The stage's procedure is the most recent thing in context when the stage
starts. A maprun worker (stages 1–6) never loads `7-10-delivery.md`.
Consumers (verified): `scripts/test-bootstrap.sh` asserts on the skill's text
23 times — each marker is re-pointed at its stage file in the same commit.
Template layout: `templates/skills/` is flat files copied one by one
(`bootstrap-espalier.sh:385–395`), and `espalier-coding/specs/` is
`mkdir` + LLM-written at init (`:339`, `:12`), not template-copied — so
`stages/` is NEW machinery: a template directory
`templates/skills/espalier-stages/{file}.md`, a bootstrap Stage 3 loop
copying it into `espalier/skills/espalier/stages/`, a per-file migration
`refresh`, and check 66. The `.claude/skills/espalier` symlink already
resolves to the directory. `espalier-fix.md` is a single-lane skill and is
NOT split (deferred, §11). `maprun.py` parses `pipeline.md` headings, not
the skill. **Ships in v0.25.1 (§9, §14).**

**B.3 `pipeline.md` is the contract, the skill is the procedure** (r2
Track C, carried). `templates/pipeline.md` keeps the lanes note and the
eleven stage headings verbatim (`### 1.` … `### 10.`, `### 8.5`), and per
stage only Trigger / Load / Gate (one line, the programmatic condition) /
Output / Limit, plus `Procedure: espalier skill → stages/{file}`. The
Maintenance-commit / per-key / slug-collision recipes (`pipeline.md:334,
346, 356`) move to `templates/skills/espalier-prune.md`, which owns the
maintenance discipline. Consumers (verified): `hook-templates/maprun.py:523`
`_stage_names()` parses `^###\s*(\d+)\.\s*(.+?)\s*$` — which also matches
`### 8.5 Doc Drift Check` as stage 8 with label `5 Doc Drift Check
(notify-only)`, overwriting "CI Verification" (tested on the v0.24
template). Pre-existing bug: the regex becomes `^### (\d+)\. (.+?)\s*$` (a
literal `N. `, so `8.5` cannot match) with a T22 case, and ships in v0.25.0
through the existing pure-copy `maprun.py` refresh whether or not the
contract lands; headings frozen, plus a fallback label table so fewer than
10 parsed stages logs a warning; test-bootstrap asserts on `pipeline.md` 33
times — re-pointed in the same commit;
`/espalier-ask` reads it as a doc (a shorter contract answers "which stage"
faster). Expected size ≈ 9 KB — an expectation recorded for the benchmark,
not a rule anything checks. **The contract form ships in v0.25.1 (§9, §14);
the regex fix ships in v0.25.0.**

**B.4 One gate helper** (`hook-templates/drift-helpers.sh`, sourced by both
lanes). `exit_gate DIR [TEST_FILES…]` runs the discovered build and lint as
two background jobs with per-pid waits, each job's output to its own temp
file, then the scoped test run — the exact procedure `espalier.md:456–475`
spells out in prose — and prints one line per job (`build: exit 0`,
`lint: exit 0`, `tests: exit 0 (12 files)`) plus the log path of any failure.
The commands have one source: the installed `espalier/hooks/pre-push-gate.sh`,
where init substitutes them into function bodies — `run_build() {
{build_command} }`, `run_lint`, `run_tests` (`pre-push-gate.sh:267, 286,
307`; a body may be a multi-line block) — and `/espalier-prune` refreshes
them. `exit_gate` extracts each body with `awk` from `run_X() {` to the line
where the running brace depth returns to zero (`gsub` counts of `{` and
`}` per line — mawk-safe; a brace-grouped multi-line body survives), checks
the extract with `bash -n`, and `eval`s it in a subshell from the repo
root: no config key, no bootstrap writer, no migration extraction, and
every existing install already carries the three functions (v0.9.2). Exit
codes are the contract: `1` = a gate job failed (red, with its log path);
`2` = helper could not extract a function (missing in a customised gate, or
`bash -n` rejects the extract) — printed as `exit_gate: run_lint not
found / not parseable in espalier/hooks/pre-push-gate.sh — run the gate by
hand as before`; `3` = the greenfield placeholder gate
(`bootstrap-espalier.sh:436–439`, `exit 0` and no functions, or
`espalier/.greenfield` present) — printed as `no gate yet; run build/lint
by hand from development-process.md`. The orchestrator treats 2 and 3 as
"helper unavailable, gate by hand as before", never as a red gate — only
exit 1 re-spawns a coder (owner, 2026-09-09). Four sites call the helper
instead of restating the script: the Stage 3 exit gate (`espalier.md:456`),
the contract-phase gate (`espalier.md:663`), the fix lane's Stage 3 exit
gate (`espalier-fix.md:711–736`), and the fix lane's Stage 4 loop
"Before every panel spawn, run the Stage 3 programmatic gate"
(`espalier-fix.md:746–749`). A gate that is one call is
run identically every time; the orchestrator's own resident Bash payload
(its largest own output, §0.6) shrinks as a by-product.

**B.5 Why quality improves.** Stages 7–10 — the human-facing delivery
procedure — run on a context that holds the stage's procedure and the
change's state, at the end of context where instructions are followed best,
instead of at 500k. The gate is a helper, so it cannot be retyped wrong.

### Track C — Current inputs for the panel (r3 carried; numeric caps removed)

**C.1 Coding report: state + log** (`espalier.md`, `espalier-fix.md`,
`harness-coder.md` "Coding Report", line 150).

```
espalier/changes/{type}/{slug}/
  coding-report.md          # CURRENT: the last coder spawn's report (+ the fix lane's appended sentinel lines)
  coding-log/               # NEW: one file per prior spawn, read only when named
    01-stage3-part1.md  02-handoff-1.md  03-round2-fix.md  04-contract-phase.md
```

- Orchestrator, before EVERY coder spawn after the first (fix re-spawn,
  handoff continuation, contract phase, exit-gate fix, resumed sub-task):
  `report_archive "{dir}" "{label}"`. Labels: `stage3-partN`, `handoff-N`,
  `handoff-N-partK`, `roundN-fix`, `contract-phase`, `exit-gate-fix`,
  `class-sweep`. Call sites, both lanes: the fix-round re-spawn
  (`espalier.md:580–582`, `espalier-fix.md:788–793` — `roundN-fix`, or
  `class-sweep` when the round carries a Class Sweep); the exit-gate red
  re-spawn (`espalier.md:471–474` and the fix lane's exit gate —
  `exit-gate-fix`); the contract-phase spawn (`espalier.md:657`,
  `espalier-fix.md:887` — `contract-phase`); the handoff continuation
  (A.3 — `handoff-N` / `handoff-N-partK`).
- Parallel sub-tasks (`espalier.md:411–415`): parts still concatenate into
  `coding-report.md` after the wave — one wave's reports ARE the current
  state.
- Coder: writes `coding-report.md` fresh (overwrite, never append). New
  first line under the heading: `- Prior reports: coding-log/ (read one only
  when this report cites it)`. A fix-round report cites the archived report
  it responds to by path when it changes a decision recorded there.
- Fix lane (`espalier-fix.md:916 ff.`): the `REGRESSION_VERIFIED` bash
  appends to the coder's fresh file — LAST-line semantics hold.
- Panel prompts (`espalier.md:503, 535`; fix-lane twins): "Read
  coding-report.md" wording unchanged; one added line: "Earlier spawns'
  reports are in `coding-log/` — open one only when the current report
  cites it or a finding needs the history." Round ≥ 2 gets
  `CHANGED SINCE LAST REVIEW` exactly as today (`espalier.md:513, 540`).

**C.2 Requirements: contract + notes** (`espalier-requirements.md` "Output
Format", line 12; `espalier-grill.md` Step 3, line 232 ff.; `espalier.md`
context-pack step).

- The contract is the five numbered sections (`espalier-requirements.md:16–39`),
  `## Open Questions`, `## Convention Notes`, and `## Retired Surface` when
  filed by simplify. Frontmatter unchanged. Derivation, alternatives,
  settled-for-next-time, and the grill transcript go to
  `requirements-notes.md` under the same headings, linked once from the
  Requirement Summary: `Notes: requirements-notes.md`.
- Grill: a resolved decision is written into the criterion it resolves (one
  clause) and the full Q&A into `requirements-notes.md` `## Resolved by
  grill`. Convention Notes stay in the contract.
- Stage 3 pre-spawn: `req_shape_check DIR` prints the headings in
  `requirements.md` that are outside the contract set, each with a one-line
  "→ requirements-notes.md". Information only, no size, no refusal — the
  human approved this text at Stage 2.
- Stage 2 requirements reviewer: a heading outside the contract set is a P2
  with Fix = "move to requirements-notes.md".
- Spawn prompts unchanged (they name `requirements.md`).
- Readers of decision history follow the split: `/espalier-ask`'s `why`
  row (`espalier-ask.md:62`) and `/espalier-simplify` Step 1 item 5
  (`espalier-simplify.md:81`) read `requirements-notes.md` beside
  `requirements.md` (both pure-copy skills, §5).

**C.3 Security contract, extracted for Stage 5/6** (`espalier.md:648, 659,
665`; `espalier-fix.md:889`; `harness-coder.md:371–389`;
`harness-reviewer.md:436–446`; `espalier-testing.md:31–35`).

- `harness-security` keeps writing `## Security-Sensitive Fields` into
  `security-record.md`; every grep in §0 of r3 stays.
- Orchestrator, right after the existing
  `grep -q '^## Security-Sensitive Fields'` gate passes:
  `contract_extract "{dir}"` writes `security-contract.md` = that block to
  the next `## ` heading or EOF.
- The contract-phase coder prompt and the Stage 6 reviewer prompt read
  `security-contract.md`; the coder's contract entry point and the
  reviewer's abuse-coverage section name the contract file with the
  fallback "if `security-contract.md` is absent, read the block from
  `security-record.md`". The auditor's round-N adjudication prose is never
  in a Stage 5/6 spawn again.

**C.4 Advisory findings: ranked rows, no count** (`harness-reviewer.md`
"Minimalism Review", line 334; "Readability Review", line 369). Each
advisory finding is one row — tag, `path:line`, the concrete replacement —
ranked by what the coder gains from doing it; rationale paragraphs are
dropped; a note the reviewer would not ask a coder to act on this round is
not written. The P1 exceptions in each section are unchanged and uncounted.
(r3 capped this at three. The field has 169 advisory rows against 66 P0/P1
across 42 records; the fix is signal density for the coder's fix round,
which a rule about content gives and a number does not.)

**C.5 Report hygiene** (`harness-coder.md` "Coding Report", line 150). A
section with no content is one line (`- Staleness: none`); a section exists
only when it has content; nothing the reader can run is restated (no test
output beyond the count line the exit gate prints; no repeated build
instructions — the pack has them); doc text is never pasted (C.6).

**C.6 Docs: edit the claim** (`harness-coder.md` "Editing Discipline",
line 295):

```
Docs. When your change makes a claim in a scoped doc (a workspace or
directory CLAUDE.md, espalier/wiki/*) false, edit THAT claim in place —
one line, present tense, no history of what it used to say. Never rewrite
or restructure a doc, never add a section for the feature you built,
never paste doc text into the report. List touched docs by path under
"- Docs:" in the report. Drift beyond your change is Stage 8.5's (notify)
and /espalier-prune's, not yours.
```

The reviewer's Readability review gains the mirror check (advisory): a doc
diff larger than the claim it corrects is `docs:` tagged. Stage 8.5 is
unchanged. (Field: 21 of 48 portal coding reports name `frontend/CLAUDE.md`,
and the file changed in 129 of the repo's 1,276 commits; the portal's own
root `CLAUDE.md` convention drives it; the plugin had no docs clause at all.)

**C.7 Grep-only files** (`espalier.md` context-pack template, line 359 ff.;
`harness-coder.md` "Before Writing ANY Code", line 22; the reviewer's and
auditor's "Before…" sections). The pack gains `- Grep-only: {path (size)} …`
filled by `grep_only_files` from a new `.espalier-config` key
`grep-only-paths: __generated__/ schema.graphql schema.prisma` (space-
separated patterns; bootstrap writes the default; migration appends
grep-guarded) — patterns and sizes, no threshold. Agents: "A Grep-only file
is searched, never Read; if you need a symbol from it, grep for the symbol."
(Portal: `frontend/src/__generated__/gql/graphql.ts` is 497 KB.) D.6 adds the
`- Scoped docs:` line beside it.

**C.8 Helpers** (`hook-templates/drift-helpers.sh`, next to `mark_stale`):

```bash
report_archive DIR LABEL   # coding-report.md → coding-log/NN-LABEL.md (mkdir -p; NN = next free, 2 digits); no-op when absent
contract_extract DIR       # security-record.md '## Security-Sensitive Fields' block → security-contract.md; exit 1 when absent
req_shape_check DIR        # prints headings outside the contract set, one per line; always exit 0
grep_only_files            # grep-only-paths patterns → tracked matches as "path (KB)", one per line
exit_gate DIR [TESTS…]     # Track B.4
contract_drift_lines FILE  # Track E.3
scoped_docs PATHS…         # Track D.6: CLAUDE.md / AGENTS.md on the path from each PATH up to, excluding, the repo root; nearest last; de-duplicated
rule_bullets FILE          # Track E.2: top-level "- " bullets, whitespace-normalised, one per line — the ledger key (from r2 §2.3; new, not in drift-helpers.sh today)
```

`awk` / `find` / `stat` only, mawk-safe (no `{n,m}` intervals), no
`-printf` (BSD find) — the v0.23 field lessons.

**C.9 Why quality improves.** The reviewer's verdict comes from the code it
reads; round ≥ 2 already reviews in delta scope; the report it gets is that
delta's report. Every block a gate greps (`VERDICT:`, `REGRESSION_VERIFIED:`,
`### Class Sweep`, `### Test files`, `### Retired Surface`) is produced by
the spawn whose report is current. The acceptance criteria the coder builds
to and the reviewer checks against are unchanged and in the same file. The
abuse-test contract is the same table, read from a file that holds nothing
else. Docs stay true because the claim is edited, not the doc rewritten.

### Track D — Load once, and read what the pointer names (all agents, all platforms)

**D.1 The self-read line.** Seven sites, five wordings — each is its own
migration anchor: `espalier.md:432, 499, 531` "Read
espalier/agents/harness-X.md for your full instructions"; `espalier.md:722`
"…for your instructions";
`espalier-fix.md:680` "…for full instructions"; `espalier-fix.md:1027` bare
"Read espalier/agents/harness-reviewer.md."; `espalier-audit.md:89` "Read
espalier/agents/harness-security.md and follow its…" (keeps its Repo-Audit
clause). All →
"Your instructions are `espalier/agents/harness-X.md` (auto-loaded as your
system prompt on Claude Code; read it only if it is not already in your
context)". On Codex the `.codex/agents/harness-coder.toml` body already
says "Read espalier/agents/harness-coder.md and follow it"
(`bootstrap-espalier.sh:887`) and on Copilot the custom agent carries the
body — the line stays the load mechanism there, exactly as the rules
reword does.

**D.2 The rules reword lines** (r2 §3.3; already in the portal by hand).
`harness-coder.md:346–347, 392`, `harness-reviewer.md:30–33`,
`harness-security.md:22–23` → "`espalier/rules/<file>` (auto-loaded on
Claude Code; read it only if it is not already in your context)". Template
text = the portal's wording (`harness-coder.md:344, 391`,
`harness-reviewer.md:31`, `harness-security.md:24` there), so the migration
anchor matches the one install that already has it.

**D.3 Read once.** One line in each agent's "Before…" section
(`harness-coder.md:22`, `harness-reviewer.md:21`, `harness-security.md:15`):
"A file already in your context is not Read again unless you or the gate
changed it. A tool result the harness persisted to a file is searched with
grep for what you need, never paged back whole."

**D.4** The `harness-security` step 3 clause from r2 stays: read each
changed file with the Read tool — a `git diff` in Bash is never the only
evidence.

**D.5 Spec applied — the one on-demand read that carries the layer's shape
leaves a trace** (`harness-coder.md` "Coding Report", line 150;
`harness-reviewer.md` "Review Process" step 3, line 35 ff.). The report
gains one mandatory line after `- Layers touched:`:

```
- Spec applied: espalier/skills/espalier-coding/specs/{layer}.md § {section} — {one clause: the shape followed}
  (one entry per touched layer; `none — no spec for {layer}` with the reason
  when the pack's Spec column says so)
```

The coder cannot cite a section it did not open. The reviewer's step 3
("check against the layer spec") gains: open the cited section; a citation
that names no existing section, or a diff that contradicts the cited shape,
is an advisory `[spec-unread]` row naming the section — advisory, never
counted, no cap. Fix lane: same coder, same line. The §7 fixtures make the
line testable.

**D.6 Scoped docs named in the pack — delivery that does not depend on the
platform** (`espalier.md` context-pack template, line 359 ff.;
`espalier-fix.md` pack step; `harness-coder.md:22`, `harness-reviewer.md:21`,
`harness-security.md:15`). The pack gains:

```
- Scoped docs: {path} … — workspace docs on the path from each reference file
  up to the repo root (root instruction file excluded — always loaded). Grep
  each for the files you touch; Read the matching sections (offset/limit). A
  claim there is a trap, an invariant, a deliberate stub, or a rejected
  alternative: verify it against the code before relying on it, as with the pack.
```

Filled by `scoped_docs` (C.8) from the pack's reference files: walk up each
directory chain collecting `CLAUDE.md` and `AGENTS.md`, nearest last, root
excluded, de-duplicated. A file the coder CREATES in a directory the pack
did not name is covered by the agent line. The three agents' "Before…"
sections gain one line: "Scoped docs named in the pack — and any `CLAUDE.md`
/ `AGENTS.md` above a file you create: grep for the files you touch, read
those sections; never re-Read a doc the platform already injected (D.3)." Grep does
not trigger nested memory; a sectioned Read costs the section, not the
chain. On Codex / Copilot this line is the only path by which a workspace
doc reaches a coder.

**D.7 Why quality improves.** A pointer is only as good as the read it
produces. D.5 is meant to make the layer-shape read visible and checkable;
D.6 to make the trap-and-invariant docs reach every coder on every platform, in
sections, instead of 19 % of August's coders on one platform and the whole
137 KB chain since. Neither line pastes content into a prompt, so reading
at the point of use keeps its recency advantage. No budget, no count: a
missing or wrong citation is one advisory row.

**D.8 Mode files — the agent body carries what every spawn needs; a mode
carries the rest** (v0.25.1, with B.2; `harness-coder.md`,
`harness-reviewer.md`, `harness-security.md`). Measured on the v0.24
templates, the always-on bodies carry sections that apply to a minority of
spawns:

| Body | mode-only sections | bytes | share of body |
|---|---|---:|---:|
| coder (23.4 KB) | Fix Rounds 2.7 KB, Simplification Changes 3.4 KB | 6.1 KB | 26 % |
| reviewer (25.0 KB) | Re-review Rounds 2.8, Simplification Review 3.2, Escalation Reason 0.7, Security Abuse-Test Coverage 0.7 | 7.4 KB | 30 % |
| security (13.4 KB) | Repo-Audit Mode + Findings 2.7, Re-review Rounds 2.1 | 4.8 KB | 36 % |

Each moves verbatim to `espalier/agents/modes/{fix-round, simplification,
re-review, repo-audit, stage6-abuse-coverage}.md`, and the prompt line that
already announces the mode names it first — `FIX ROUND {n}: read
espalier/agents/modes/fix-round.md first, then …` (`espalier.md:580–582`,
`espalier-fix.md:788–793`), `SIMPLIFICATION CHANGE: read …`, `ROUND {n}
(re-review): read …`, `REPO-AUDIT MODE: read …`, and the serial Stage 6
prompt. Same delivery as the context pack (100 % adoption in the field).
The body keeps a one-line pointer per mode. Net after D.1–D.7's additions:
coder ≈ 20 KB (from 23.4), reviewer ≈ 18 KB (from 25.0), security ≈ 9 KB
(from 13.4) — every call. Nothing is removed: a mode's text is read at the
moment it applies, at the end of context, where it is followed best.
Non-compliance is already caught by existing gates — a fix round without a
`### Class Sweep` block is a P1 `[class-sweep]` (`harness-reviewer.md:69
ff.`), a simplification change without `### Retired Surface` fails the
Simplification Review. Consumers: Test 34e asserts `## Simplification
Changes` / `## Simplification Review` in the agent templates (re-pointed to
the mode files); `eval/review/run.sh:60` copies the reviewer template into
the fixture project (copies `modes/` too); migration #36 `extract_block`
moves each section (customised body → skip-with-record, the body still
works as today); Codex / Copilot agent bodies read the same mode files by
the same prompt line.

### Track E — Rules that stay rules, without a budget (init + prune + doctor)

r2 Track A minus its numbers. The quality mechanism is the invariant ledger;
the writing contract is what makes a refresh shrink instead of ratchet.

**E.1 Writing Contract** (new first section in
`skills/espalier-init/templates/scout-prompts.md`, shipped as
`espalier/.scout-prompts.md`, mirrored in
`references/discovery-checklist.md`):

```
## Writing Contract — rule files (espalier/rules/*.md)

A rule file is read on every turn by every agent. It carries what a coder
must DO and a reviewer must CHECK, nothing else.
- One bullet per rule, present tense; a rubric table row is one rule.
- Exactly one citation per bullet: `path:line` of the shape to copy.
- No counts, dates, commit SHAs, PR numbers, or shell commands. A number
  that matters is re-derived by the doctor's scout, never stored.
- No history ("was deleted", "used to", "no longer", "pre-v0.x"). A
  surface that must not be copied is one line in `## Not Precedent`.
- No walkthroughs: a flow that needs more than two lines lives in
  `espalier/wiki/critical-paths.md` or the workspace CLAUDE.md; the rule
  keeps one bullet and a pointer.
- Universal seed text (severity tiers, required controls, taxonomy,
  maintenance-commits anchor) is fixed and never rewritten by a scout.
```

Scout 1.6 (`"invariants"`, `scout-prompts.md:109`) and Scout 1.11
(`"project_conventions"`, `:207`) gain one line each: entries are present
tense, one `file:line`, no history. Scout 1.3 (Coding Patterns) has neither
field; its per-pattern examples get the same `file:line`, present-tense
constraint.

**E.2 Prune renders under the contract; the ledger guards it**
(`templates/skills/espalier-prune.md` Per-File Refresh Protocol). Before
the AskUserQuestion gate on a rule file:
`comm -23 <(rule_bullets "$CURRENT" | sort) <(rule_bullets "$PROPOSED" | sort)`
renders as **Removed rules (N)** above the unified diff. The gate line shows
`size: 34.1 KB → 11.8 KB` as information. `keep-old` / `edit` unchanged.
Nothing refuses.

**E.3 Doctor reports contract drift** (`templates/skills/espalier-doctor.md`,
`--quick` too — it is `awk`, not a scout): `contract_drift_lines FILE` lists
lines that carry a SHA, a date, a PR number, a shell command, or a history
phrase; the report gains `contract drift: N line(s) in M rule file(s)` and
the Stage 0 STALE line gains ` · drift=N` when N > 0. Report only.

**E.4 `## Not Precedent`** (`templates/rules/engineering-structure.md`,
after `## File Conventions`; managed anchor
`<!-- ESPALIER NOT PRECEDENT v1 — managed anchor; evidence-refreshed, one line per entry, keep this comment -->`;
every reader matches the token `ESPALIER NOT PRECEDENT v1` only — the
portal has it with 13 entries). Scout 1.2 gains a `"not_precedent"` array
`{path, kind, clause, evidence}`; prune refreshes the section from that
array only: an entry the scout cannot re-prove is dropped, one it newly
proves is added. Negative knowledge is re-proved instead of decaying in
prose.

**E.5 Why quality improves.** A rule refresh cannot silently drop a rule
(ledger). Dead-surface knowledge is re-proved, not remembered. Walkthroughs
move to where the grill and `/espalier-ask` read them; the rule keeps the
pointer. Sizes fall as a by-product — the portal's hand compress under
essentially this contract landed at 15–19 KB per rubric file with round
counts unchanged.

### Track F — Measurement (numbers the human sees)

**F.1 `espalier-stats.sh` "## Spawn shape (per change)"** (new section
after "Review rounds + rollbacks", `hook-templates/espalier-stats.sh:76`):
coder spawns per change (= 1 + files in `coding-log/` once C.1 archives
every prior spawn; Stage History carries no per-spawn Stage-3 row — the
only `| 3 |` row is `IN_PROGRESS`, `espalier.md:903`, fix rounds land as
`| 4 | ROUND n |` and exit-gate re-spawns write no row), handoffs per change
(`HANDOFF` rows / `coding-log/*-handoff-*.md`), parts per change
(`coding-log/*-stage3-part*.md`), fresh-session resumes (`RESUMED` rows),
each as `n / median / max`. Degrades to `none` on an
install without the new rows. The round parser matches `ROUND` rows only.
The Stage-duration parser (`espalier-stats.sh:99–103`) books the gap to the
next row against the earlier row's stage and classifies it by the closing
row's note, with HUMAN markers `requirements approved`, `approved by user`,
`delivery`, `grilled`, `skipped:`; a `RESUMED … fresh session` row would
book the human's away time as agent time, so `resumed` joins the HUMAN
tuple (T22 case). A `HANDOFF` row only splits a Stage-3 span in two, both
attributed to Stage 3 — harmless.

**F.2 `scripts/context-report.py`** (plugin repo dev script, not a
template). Reads a Claude Code project directory
(`~/.claude/projects/<slug>/`) and prints §0.1–0.7 for that install:
first-turn / peak / calls / total per spawn by agent type, share of tokens
processed above 150k and 200k, baseline share, pack cohort, orchestrator
sessions. Documented in `docs/usage-cost.md`. This is how v0.25 measures
its own effect on the portal (§7) and how v0.26 gets a quality signal.

**F.3 Evals** — §7.

**F.4 What the plugin cannot control, shown anyway** (report-only).
Since Claude Code 2.1.259 a coder that Reads under a workspace gets that
workspace's doc chain injected whole — 54 KB median, 137 KB max per spawn on
the portal (§0.9), ≈ 7 % of a frontend coder spawn, resident to the end.
Espalier does not own those docs and cannot stop the injection without
losing the docs (§10). Two numbers the human sees instead: `context-report.py`
gains a per-spawn row for `nested_memory` attachments (count, KB, which
files), and `espalier-stats.sh` gains `## Workspace docs` — every
`CLAUDE.md` / `AGENTS.md` in the repo with its size and last-change date,
no threshold. C.6 keeps them from growing; trimming them is the owner's
lever, and these rows are how its effect is seen.

## 4. Why quality is not traded for context anywhere

Every "why quality improves" paragraph in §3 states the intended mechanism.
None is a measured result — §0.8 and §0.9 say so — and §7 is where each is
tested before the tag.

- No agent loses an input it uses: rules stay always-on on every platform;
  the pack, the contract, the report, the code are unchanged in content.
- No gate changes: exit gate on every coder return (handoffs included), the
  two-agent panel on the combined diff, sentinels and round caps untouched.
- Every reduction is a side effect of a quality rule: fresh spawn per seam,
  current report, contract file, edit-the-claim, load-once.
- Nothing refuses on size; the human sees sizes and drift and decides.
- Where a context lever would remove an input an agent uses — always-on
  rules, the reviewer's whole-file reads, the layer spec, the scoped docs,
  the grill's code reads — the lever is dropped (§10), never the input.
  Context is managed by when and how an input arrives, not by whether it
  does.

## 5. Migration #35 (`scripts/migrate-v0.24.0-to-v0.25.0.sh`)

Same helper set as #34 (`backup_once` → `.pre-v0.25.bak`, `refresh`,
`extract_block` with END-anchor-required, `insert_before` / `insert_after`,
`record_skip`, `add_lane_line`; `scripts/migrate-v0.23.1-to-v0.24.0.sh:157–314`).
`backup_once` also appends `*.pre-v0.*.bak` to the repo `.gitignore`
(grep-guarded) — the portal owner deleted 56 tracked backups in `eea0a620`;
existing tracked backups are left alone.

1. **Pure-copy refresh** (backup-on-diff; the bootstrap's own pure-copy set,
   `bootstrap-espalier.sh:385–395`): `espalier/pipeline.md`; the `espalier`
   SKILL.md (v0.25.1 adds the `stages/` files, one `refresh` each); the
   `espalier-fix`, `espalier-requirements` (its line 45 goes with the
   refresh), `espalier-grill` and `espalier-map` (their `≤ 8` code-read references
   go with the refresh, A.5), `espalier-audit`, `espalier-ask`,
   `espalier-simplify`, `espalier-prune`, `espalier-doctor` SKILLs;
   `espalier/.scout-prompts.md`; `espalier/hooks/{drift-helpers.sh,
   drift-detect.sh, maprun.py, espalier-stats.sh}`. A whole-file refresh
   replaces a customised copy (backed up, never merged) — the mechanism
   every migration has used for these files; the portal's only customised
   skill is `espalier-coding` (`.migrations-skipped`), which no step here
   touches.
2. **Anchored edits**, text EXTRACTED from the templates at run time:
   `harness-coder.md` — `## Handoff` section (before Editing Discipline),
   Docs clause (Editing Discipline), read-once + Grep-only + Scoped-docs
   lines (Before Writing), Prior-reports + Spec-applied lines + hygiene
   (Coding Report), contract-file reads (371–389), reword lines (347, 392);
   `harness-reviewer.md` — advisory rows (Minimalism, Readability),
   coding-log + read-once + Grep-only + Scoped-docs lines (Before Reviewing),
   spec-citation check + `[spec-unread]` tag (Review Process step 3),
   contract-file read (436–446), `docs:` tag, reword lines (30–33);
   `harness-security.md` — reword lines (22–23), coding-log + read-once +
   Grep-only + Scoped-docs lines (Before Auditing);
   `espalier/skills/espalier-testing/SKILL.md` — NOT pure-copy (LLM-written
   at init, absent from the bootstrap cp list): the contract read path
   (31–35) is an anchored edit; `espalier/agent.md` — Config row for
   `.espalier-config` gains `grep-only-paths`; Pipeline row names `stages/`
   in v0.25.1;
   `espalier/rules/engineering-structure.md` — `## Not Precedent` anchor
   appended, empty list; skipped when the token is already present
   (the portal). A customised file missing its anchor is skipped with a
   record in `espalier/.migrations-skipped` — the file still works; on the
   portal the reword lines are already present, so those steps no-op or
   skip-with-record by design.
3. **Config**: append `grep-only-paths:` to `espalier/.espalier-config`
   (grep-guarded, comment included). No budget keys; no gate-command keys
   (B.4 reads the gate itself).
4. **Report, do not act**: print `req_shape_check` for every `IN_PROGRESS`
   change and `contract_drift_lines` totals for `espalier/rules/*.md`, with
   "run /espalier-prune when you choose (interactive, per-file gate, Removed-
   rules ledger)". The migration never rewrites a rule or a requirement.
5. **Instruction files**: no new line.

`skills/espalier-migrate/SKILL.md` — the full four-surface checklist from
the v0.21 release note (the gap that recurred twice): description line,
`NEEDS_V0250_PATCH` detection (probe: `grep-only-paths` in
`.espalier-config` AND `scoped_docs()` in `espalier/hooks/drift-helpers.sh`;
v0.25.1's probe adds `espalier/skills/espalier/stages/`) + final up-to-date
check, Step 3/6 lists, numbered entry 35, chain paragraph, "Up to
THIRTY-FIVE" (lines 21, 430).

## 6. Validation checks (`scripts/bootstrap-espalier.sh`)

| # | name | passes when |
|---|---|---|
| 64 | `context-helpers` | `drift-helpers.sh` defines `report_archive`, `contract_extract`, `exit_gate`, `grep_only_files`, `scoped_docs`; `grep-only-paths` in `.espalier-config` |
| 65 | `spawn-protocols` | coder template carries `## Handoff`, `- HANDOFF: true`, and `- Spec applied:`; the espalier and fix SKILLs grep the sentinel and their pack templates carry `- Scoped docs:`; the reviewer template carries `[spec-unread]`; `espalier-requirements` carries no `≤ 5 files` line and neither `espalier-grill` nor `espalier-map` a `≤ 8` read budget |
| 66 | `stage-procedures` (v0.25.1) | every `espalier/skills/espalier/stages/*.md` and `espalier/agents/modes/*.md` present, named by the router's Stage Execution Protocol and the mode prompt lines |

Platform-neutral. v0.25.0 adds 64–65: totals 53 / 58 / 63 → **55 / 60 / 65**
by platform set; v0.25.1 adds 66 → 56 / 61 / 66. Since 2026-09-09
`scripts/test-bootstrap.sh` derives every total from three constants near
its top (`N_CLAUDE=53`, `N_CODEX=58`, `N_ALL=63`; suite re-run 311/311 after
the change) — a release bumps those three lines and nothing else; the
per-assert re-point list of r4.2 and the "Test 10 hardcode" pitfall are
gone. `references/validation.md` rows 64–65 + totals (66 later).

## 7. Proof (evals before the tag)

- **Coder** (`eval/coder/run.sh`, `CODER_TPL` at line 15): v0.24 vs v0.25
  template, same day, same pinned model (`--model`; a Fable default refuses
  headless agentic prompts). Existing fixtures are single-seam, so no handoff
  fires — pass = 4/4 unchanged. One NEW two-seam fixture exercises the
  protocol: pass = the coder either finishes or returns a report with
  `- HANDOFF: true`, a `## Handoff` block whose Facts all carry `path:line`,
  and a building tree — judged by script (grep + build), never by an LLM.
- **Disclosure fixtures (r4.1; built 2026-09-09, untracked).**
  `eval/coder/project/specs/services.md` (layer spec: log-line-first shape,
  `ORDER_STATUS` constants, exact error messages),
  `project/scoped/services/CLAUDE.md` (three traps: whole-row `saveOrder`,
  soft-deleted `findOrder`, a no-op stub), `project/extra/order-status.js`;
  fixtures `coder-06-scoped-doc-trap` (single seam, spec + doc, traps in
  `must_follow`) and `coder-07-two-seam` (services + controllers,
  `handoff_allowed: true`). `run.sh` copies spec / doc / extras only for
  fixtures that opt in (`spec:`, `scoped_doc:`, `extra_files:`), so the seed
  set's baseline is untouched; script-checks the `- Spec applied:` section
  against the spec (`SPEC_LINE=report` prints, `SPEC_LINE=gate` fails —
  flip when the v0.25 coder template ships); a `- HANDOFF: true` report
  passes on `coder-07` iff `## Handoff` carries `- Remaining:`, `- Facts:`
  with a `path:line`, and every touched `.js` passes `node --check`, and
  fails on any other fixture. Review eval: `spec-unread-09` (clean code,
  `report_extra:` cites `§ Retry policy`, which does not exist; expected an
  advisory `[spec-unread]` row; `pending_template: v0.25` — skipped unless
  `INCLUDE_PENDING=1`). Logic unit-tested without an LLM; the LLM runs are
  the §7 A/B once the templates exist.
- **Review** (`eval/review/run.sh`, `AGENT_TPL` at line 17): planted-defect
  catch 10/10 unchanged with the advisory rewording and the coding-log line;
  FP ≤ same-day baseline; any FP reproduced with `KEEP_WORK` before it is
  attributed (v0.23 discipline).
- **Security**: catch 1.00 on the 20 fixtures; the FP gate is known-broken
  at baseline (`eval/security/KNOWN-ISSUES.md`, deferred item) — compare to
  the same-day baseline only.
- **Field smoke on the migrated portal** (stages 1–6, one feat + one fix):
  round counts unchanged; a handoff observed or not is reported either way;
  `scripts/context-report.py` run on the weeks before and after, numbers
  recorded in `docs/context-benchmark-v0.25.md` beside §0. The portal already
  banked the rules half (three runs on the compressed rules, §0.8).

## 8. Test plan

`scripts/test-bootstrap.sh` — **Test 35: v0.25.0 quality-first context**
(shape of Test 34, line 1813):

- 35a–e templates carry the markers: `## Handoff` + `- HANDOFF: true`
  (coder); the CONTINUATION line and the `grep -q '^- HANDOFF: true'`
  detector (espalier + fix SKILLs); the `≤ 5 files` line absent from
  `espalier-requirements.md` and no `≤ 8` read budget left in
  `espalier-grill.md` / `espalier-map.md`; the PARALLEL DISPATCH clause in the Handoff
  section; the fix lane's sentinel guard before the regression bash;
  Writing Contract heading (scout-prompts); `NOT PRECEDENT v1`
  anchor (engineering-structure); reworded read lines in all three agents
  and all seven spawn prompts; `Continue in a fresh session` offer; the
  `Removed rules` gate text (prune); `contract drift` line (doctor);
  `- Spec applied:` (coder), `- Scoped docs:` (both pack templates),
  `[spec-unread]` (reviewer).
- 35f fresh install: `grep-only-paths` present; checks
  64–65 pass; totals 55/60/65 by platform. (v0.25.1: check 66, totals
  56/61/66, `.claude/skills/espalier` resolves to a directory containing
  `stages/`, `stages/` files + `Procedure:` lines in the router,
  `espalier/agents/modes/*.md` present and named by the mode prompt lines,
  Test 34e markers re-pointed to the mode files.)
- 35g–j migration triplet (apply / no-op / customised-skip-with-record),
  Test 30/31 shape — substituted files are `simulate_llm_writes` stubs, so
  expect skip-with-record first, never nothing-to-do.
- 35k migration leaves every `espalier/rules/*.md` and `requirements.md`
  byte-identical and prints the report-only lines; `.gitignore` gains the
  backup pattern once.

`scripts/test-hooks.sh` — **T22**: `report_archive` numbering + no-op when
absent; `contract_extract` block-to-next-heading + exit 1 when absent;
`req_shape_check` heading list; `grep_only_files` patterns; `exit_gate`
extracting multi-line `run_*` bodies from a fixture gate including one with
an inner brace group, exit 1 with per-job lines on a failing lint, exit 2
naming the function when one is absent or unparseable, exit 3 on the
greenfield placeholder;
`contract_drift_lines` on a fixture with one SHA, one date, one shell line;
`scoped_docs` on a fixture tree with nested `CLAUDE.md` / `AGENTS.md` files
(root excluded, nearest last, de-duplicated);
`rule_bullets` normalisation + the Removed-rules `comm` on a known pair;
the stats section on a fixture with `HANDOFF` and `RESUMED` rows, and the
duration parser booking a `RESUMED … fresh session` gap as human wait;
`maprun.py` `_stage_names` on the v0.24 template `pipeline.md` (stage 8 =
`CI Verification`, `8.5` ignored) and fallback labels with three headings
deleted.

Suite sizes are expected to land near bootstrap 311 → ~345, hooks
173 → ~190 — expectations, not thresholds.

## 9. Rollout

1. **v0.25.0** — branch `feat/v0.25-quality-first-context`. Order,
   smallest blast radius first: Track D (line rewords) → Track C helpers +
   report / requirements / contract → Track A (sizing incl. the `≤ 5 files`
   removal, handoff, detector, fix-lane guard) → Track B.1 offer + B.4 gate
   helper + the `maprun.py` regex fix → Track E contract + ledger +
   Not Precedent → Track F stats + `context-report.py` → tests. Both suites
   green.
   **v0.25.1** — Track B.2 router + B.3 pipeline contract on their own
   branch after v0.25.0 has run in the field: 23 + 33 assert re-points,
   check 66, migration #36 (pure-copy of the `stages/` files;
   `extract_block` moves of the D.8 mode sections), totals 56/61/66. D.8
   mode files ride the same branch — same class of change, same asserts.
2. Migrate `portal.quota.com.au` locally with #35 (`--dry-run` first).
   Expect: reword steps no-op or skip-with-record (already hand-applied);
   Not Precedent step skips on the existing token; `espalier-coding/SKILL.md`
   is customised and untouched by this migration (`.migrations-skipped`
   already records the unported v0.23.0 fold — unrelated, unchanged).
3. §7 evals + field smoke + benchmark doc.
4. Release surfaces: CHANGELOG 0.25.0; `plugin.json` + `marketplace.json`;
   `index.html` (pill, eyebrow, footer, chain); README (badge, latest
   release); `docs/usage-cost.md` (the §0 numbers, no "−N tokens" promise
   beyond what the benchmark measured); `references/validation.md` rows
   64–65 + totals; `docs/deferred-items.md` (§11).
5. PR → merge → annotated tag `v0.25.0` → GH release (notes = CHANGELOG
   section). Same recipe as v0.24.0. Sync to the release host by tar-pipe
   only; no `chmod` globs.
6. Migrate the other installs after their pending #33/#34.

## 10. Considered and rejected

- **Any hard budget** (rule-file KB, requirements KB, a turn cap, an
  advisory count, a prune refusal on size). A cap makes an agent drop
  content to fit and makes a human argue with a number; a protocol makes an
  agent finish or hand off, and a ledger makes a human see what changed.
  Owner direction, 2026-09-08.
- **Keeping the requirements template's `≤ 5 files` sub-task rule** —
  replaced by A.1's sizing paragraph; nothing enforced the number and it
  contradicted the rule above.
- **Keeping the grill's `≤ 8 file reads` cap** — same reasoning; reworded
  to a protocol (A.5).
- **Gate commands as `.espalier-config` keys** (r4.2) — a second copy of
  what `pre-push-gate.sh` already holds, with an init writer and a
  migration extractor to keep in sync; dropped for run-time extraction (B.4).
- **Parallel contract-phase dispatch** (r4.2 A.1) — `espalier.md:657` runs
  one test-coder and no part-file mechanism exists; an oversized contract
  phase hands off instead; deferred (§11).
- **Forcing the session reset.** An orchestrator cannot clear its own
  context, and a forced stop on an unattended maprun worker would strand the
  master's relay. Offered at boundaries, skipped unattended.
- **A turn counter the orchestrator enforces from outside.** It cannot see a
  subagent's context; the coder can judge its own remaining work, and the
  stats row shows the pattern.
- **Path-scoped rubric rules** — the panel's verdict must not depend on
  which files an agent Read.
- **Ship rules only via the context pack** — Codex / Copilot have no
  auto-load; the reviewer needs the whole rubric.
- **Deleting the explicit Read lines** — regresses Codex / Copilot, where the
  line is the load mechanism. Reworded, never deleted.
- **Compressing rules inside the migration** — an unattended rewrite of
  policy text is what the prune gate exists to prevent.
- **Splitting `espalier-fix.md` in this release** — same 60-plus-assert
  surface again; deferred (§11).
- **Reviewer reads only the diff** — the reviewer reads the diff (13 % of
  its tool bytes) AND every changed file whole (17 %). Kept: whole files
  carry the context hunks hide and are what triggers the scoped docs on
  Claude Code. Quality input; not a lever.
- **Reading source through Bash to dodge the platform's doc injection** —
  would lose the scoped docs on Claude Code; the injection is the docs
  reaching the coder. F.4 shows its size; the docs' size is the owner's.
- **Any lever that removes an input** — always-on rules, the spec, the
  scoped docs, the grill's code reads, the reviewer's whole-file reads:
  quality wins (constraint block, §4).
- **Model tiering per seat** — separate decision, separate evidence; stays
  deferred.

## 11. Deferred (carried / new)

- **Path-scoped `structure-<workspace>.md`** (r2 Track B): context-only,
  quality-neutral. Trigger: the portal's `engineering-structure.md:47`
  class of four-way flip conflict recurring after a Track E prune, or a
  doctor cycle showing module-map rows dominate the file.
- **`espalier-fix.md` router split** — trigger: B.2 lands cleanly and the
  fix lane's Stage 3–7 text is still the orchestrator's largest resident
  block on a fix run (`context-report.py`).
- **Workspace `CLAUDE.md` advisory** (not espalier-owned). C.6 stops the
  growth engine and D.6 delivers the docs in sections; a report-only doctor
  line on scoped-doc size waits for an owner decision on scope.
- **Parallel contract-phase dispatch** (one test-coder per endpoint
  family, part files, `contract-phase-partN` labels) — trigger: a contract
  phase that hands off more than once on a real change (stats: `HANDOFF`
  rows inside Stage 5).
- **Wiki size** — not read by pipeline agents (§0.7); no action.
- **A quality signal from transcripts** — `context-report.py` joins coder
  spawns to the next panel round's P0/P1 counts once `HANDOFF` / `RESUMED`
  rows exist; the 24-round join today is too thin to claim anything.
- Carried from v0.24: `eval/simplify` harness; maprun `refactor/` adoption;
  from v0.23: model tiering; security-eval judge recalibration.

## 12. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Coder hands off to dodge a hard part | Med | Med | Remaining must name the part and what was tried; the combined diff is reviewed once; handoffs per change in stats |
| 2 | Handoff at a non-building point | Med | Low | Sentinel archived first, then the exit gate runs as on every return; red → a fresh continuation coder with the handoff AND the log, as any red gate re-spawns today |
| 3 | A Handoff "fact" is wrong | Med | Med | Facts carry `path:line`; the next coder verifies before relying — the pack's rule; a fact without a citation is not a fact |
| 4 | Habitual handoffs inflate spawn count | Low | Low | Sizing at decomposition (A.1) is the first line; stats show the count; no cap to game |
| 5 | Resume offer ignored | — | — | Offered, not required; nothing depends on it |
| 6 | Skill router breaks an assert or a consumer | Med | Med | Headings frozen; `maprun.py` fallback; 23 + 33 asserts re-pointed in the same commit; landed in v0.25.1 on its own branch; `stages/` files refreshed one by one |
| 7 | Advisory rewording drops a note the coder wanted | Low | Low | Advisory never gates; P1 exceptions unchanged; a reviewer that would ask for it writes it |
| 8 | Ledger shows a removed rule the scout under-reported | Med | High | That is the ledger working; `keep-old` / `edit` at the gate; fixed seed text untouched; A/B evals |
| 9 | Eval "regression" is judge drift | Med | Med | Same-day baseline, pinned model, `KEEP_WORK` rerun before attribution |
| 10 | Validation totals forgotten on a release | Low | Low | Totals derive from three constants in `test-bootstrap.sh` (2026-09-09); a stale constant fails 12 asserts at once |
| 11 | Customised agent files miss an anchor | Med | Low | skip-with-record; the file works as before (double-loads as today) |
| 12 | Coder cites a spec section it did not open | Med | Low | Reviewer opens the cited section (D.5); `[spec-unread]` advisory; §7 fixture with a non-existent citation |
| 13 | Coder follows a stale scoped-doc claim | Med | Med | Docs verified against code like the pack (D.6); Staleness section + `.drift-state.tsv` STALE note unchanged; C.6 keeps claims true |
| 14 | Doc delivered twice (platform injection + explicit read) | Med | Low | Read-once line (D.3); grep-then-section read; `scoped_docs` names files, agents read sections |
| 15 | Customised `pre-push-gate.sh` lacks a `run_*` function, a body the brace-depth extract mis-cuts, or a greenfield placeholder gate | Low | Med | `bash -n` on the extract; exit 2 / 3 mean "gate by hand as before", never red; only exit 1 re-spawns; T22 covers an inner brace group and the placeholder |
| 16 | A mode file (D.8) is not read | Low | Med | Named first on the mode prompt line (pack-style delivery, 100 % in the field); existing gates catch the miss — missing `### Class Sweep` is P1, missing `### Retired Surface` fails Simplification Review; body keeps a pointer |

## 13. Open questions (owner) — all resolved 2026-09-09

1. ~~Resume offer points~~ — resolved 2026-09-09: after Stage 2 approval
   and after Stage 4 PASS (§14).
2. ~~B.2/B.3 in v0.25.0 or v0.25.1~~ — resolved r4.2: v0.25.1 (§14).
3. ~~`coding-log/` granularity~~ — resolved 2026-09-09: one file per spawn.
4. ~~Notes filename~~ — resolved 2026-09-09: `requirements-notes.md`.
5. ~~Migration backups~~ — resolved 2026-09-09: keep `backup_once`,
   gitignore `*.pre-v0.*.bak` from #35 on.
6. ~~`scoped_docs` file set~~ — resolved 2026-09-09: `CLAUDE.md` +
   `AGENTS.md`; Copilot's `applyTo` instruction files stay with the platform.
7. ~~Pre-existing escalation caps vs the no-budget rule~~ — resolved
   2026-09-09: kept; they are escalation caps, not context budgets (§14).
8. ~~`espalier-grill.md:218` "Budget: ≤ 8 file reads per session; if you
   would exceed it, ask instead" (pre-existing read cap, both lanes)~~ —
   resolved 2026-09-09: reword to protocol, no number (r4.3); amended the
   same day — reads unlimited, no soft stop either (r4.5).
9. ~~`exit_gate` command source~~ — resolved 2026-09-09: extract the
   `run_build` / `run_lint` / `run_tests` function bodies from the installed
   `espalier/hooks/pre-push-gate.sh` at run time; no config keys (r4.3).
10. ~~Contract-phase parallel dispatch (A.1 sentence)~~ — resolved
    2026-09-09: dropped; an oversized contract phase hands off via A.2;
    parallel contract dispatch deferred (r4.3).
11. ~~Other pre-existing numeric bounds in shipped skills~~ — resolved
    2026-09-09: read bounds reworded (A.5, all four `≤ 8` references);
    interaction and fan-out bounds (grill tiers, audit / simplify batches,
    simplify 12-lead cut) kept and disclosed (§1).

## 14. Decisions (resolved with the owner)

- r4 (2026-09-08): the goal is the highest coding quality; context reduction
  is a bonus; **no hard budget for anything**. The artifact diet (r3) is
  folded in as Track C without its two numbers; the rules diet (r2) as
  Track E without its budget and refusal.
- r4.1 (2026-09-08): owner asked whether the two disclosure lines are an
  improvement; assessment: yes on quality, neutral-to-positive on context —
  written in as D.5 / D.6 with their fixtures, as protocols with a visible
  trace, never as content pasted into a prompt.
- r4.2 (2026-09-09): fresh-eyes review applied (own pass + an independent
  reviewer with no prior context; 15 findings confirmed, 1 rejected).
  B.2/B.3 split to v0.25.1; the requirements template's `≤ 5 files` rule
  goes with A.1.
- 2026-09-09 (owner): the round caps stay — `max-req-rounds` /
  `max-code-rounds` / `max-test-rounds` / `max-rollbacks` are escalation
  caps that stop loops, not context budgets; the no-budget rule is about
  what an agent is fed and what it may write, never about when a human is
  called.
- 2026-09-09 (owner, Q1/Q3–Q6): resume offer after Stage 2 approval and
  Stage 4 PASS; `coding-log/` one file per spawn; `requirements-notes.md`;
  backups kept and gitignored; `scoped_docs` collects `CLAUDE.md` +
  `AGENTS.md` only.
- 2026-09-09 (owner, second review blockers): the grill's `≤ 8 file reads`
  sentence becomes a protocol without a number; `exit_gate` reads the gate
  commands from the installed `pre-push-gate.sh` function bodies (single
  source, no `.espalier-config` keys); the contract-phase per-family
  dispatch sentence is dropped — handoff covers an oversized contract
  phase. Applied as r4.3 with the mechanical review items.
- 2026-09-09 (owner, third review): the rule is about what one agent reads
  or writes. Every `≤ 8` code-read reference (grill 162 / 168 / 218, map
  174) becomes protocol; grill question tiers, auditor / scout batch counts
  and the simplify lead cut are interaction and fan-out bounds and stay,
  disclosed in §1. Applied as r4.4.
- 2026-09-09 (owner): the grill's code reads are unlimited — no count, no
  "ask instead" threshold; the grill asks the user only what the code cannot
  answer, and stops by its existing stop-early rule. Applied as r4.5.
- 2026-09-09 (owner): goal order restated — context under control, coding
  quality maximal; where they conflict, quality wins. r4.6 fills the
  context-goal gaps under that rule (§0.10, D.8, F.4, A.5 ↔ B.1, Appendix
  A, §4 / §10).

## 15. Revision history

- r4.10 (2026-09-09): **security FP gate fixed at the source** (owner: "fix
  the security FP gate"). The same-day A/B had the gate red at baseline
  (v0.24.0 templates, opus: catch 1.00, 8 FPs / 7 fixtures; v0.25.0
  candidate 2) — every extra a speculative or out-of-class P0/P1 (a session
  guard outside the fixture body, a field the record might carry, a
  whole-record response, production seeds, an unvalidated destination key,
  an unproven signup email). `harness-security.md` Priority Rubric gains
  "Shown, not assumed" + the `unverified:` Controls-confirmed convention
  (precision, no cap); `eval/security/rubric.md` codifies the class;
  `vuln-06` / `shadow-01` fixtures hardened; migration #35 steps; Test 35b;
  `docs/context-benchmark-v0.25.md` carries the before/after. Outcome:
  under the recalibrated rubric the stored records score baseline 16 /
  pre-bar candidate 17; the bar's first wording ran live at 3 (repo-03,
  vuln-05, vuln-06 — each a P0/P1 stating its own unverified premise); the
  shipped wording adds "client-supplied and reachable are shown the same
  way", replay / second effect = the reviewer's / a sibling read, and the
  tell (a finding stating its own unverified premise is not a P0/P1);
  `vuln-05` gains a watch line; full suite PASS 20/20, catch 1.00, FP 0;
  judge replay 24/24; suites 329/329 + 193/193.
- r4.9 (2026-09-09): **Commit Discipline** (owner: "the current commit
  behaviour is to commit large chunk into one single commit, make the
  coders and other agents do better commit behaviour"). Coder section
  `## Commit Discipline: Small, Atomic, Named` (one bounded unit per commit
  at a clean point, project Commit Conventions, staged by path, never
  rewrite what a panel saw, no git under PARALLEL DISPATCH — the
  orchestrator commits each part after the wave), `- Commits:` report line,
  handoff commits its finished units first; reviewer advisory `commits:`
  tag reading `git log <Base-Ref>..HEAD`; COMMITS prompt lines in both
  lanes; fix-round commit per class, contract-phase `test(...)` commit;
  Stage 7 commits only what is left by path (`chore(espalier):` for the
  records), never squashes, records every commit in `Base-Ref..HEAD`
  (`## Commits` one row per SHA — the fix lane's blame needs it); fix-lane
  revert covers the range; `development-process.md` managed block gains
  the atomic-commits bullet; stats `commits per change`; check 65 marker;
  migration #35 anchored steps (section, You-Must-NOT bullet, rule bullet);
  Test 35r, T22m. No number anywhere: small is a seam.
- r4.8 (2026-09-09): **v0.25.1 folded into v0.25.0** (owner). B.2: the
  espalier skill is a 22 KB router (Stage Execution Protocol gains a
  procedure table + the cross-stage sequencing rule; every historical
  marker phrase kept resolvable in SKILL.md so older migrations' and the
  migrate skill's probes still hold); stage files
  `templates/skills/espalier-stages/{1-2-requirements,3-coding,4-panel,
  5-6-contract,7-10-delivery}.md` → `espalier/skills/espalier/stages/`,
  read at stage entry; the mode prompt lines name the mode files. B.3:
  `pipeline.md` is the contract (14 KB; ten frozen `### N.` headings + 8.5,
  a `Procedure:` line per stage; the three conflict recipes moved to
  `/espalier-prune`). D.8: `templates/agents/modes/{fix-round,
  simplification,re-review,repo-audit,stage6-abuse-coverage}.md` — seven
  sections moved verbatim, each body keeps the heading + a one-line
  pointer (the reviewer's fix-lane `ESCALATION_REQUIRED` block stays in
  the body: the verdict vocabulary is a gate). Check 66
  `stage-procedures`; totals 56/61/66; check 34 also reads
  `modes/repo-audit.md`. Migration #35 gains the stages/modes copies, the
  seven mode swaps (`swap_block` → pointer; customised → skip-with-record,
  the inline section keeps working), the agent.md Pipeline row; migrations
  #33 / #34 extract from the mode files when the body template no longer
  carries a section, and the migrate skill's v0.21 / v0.23.1 probes accept
  the mode files (its v0.22 probe also accepts the v0.23 fold marker — a
  pre-existing always-yes). Tests: 28 espalier-skill asserts read the
  router + stage files as one text (`esp_all`), 19 agent-template asserts
  re-pointed to the mode files, 2 pipeline asserts to prune; Test 35 o–q.
  Eval runners copy `modes/`; the security repo-audit prompt names
  `modes/repo-audit.md`.
- r4.7 (2026-09-09): **implemented** (v0.25.0 scope, working tree, not
  committed). Deviations from the text above, all in the plan's own spirit:
  the context pack also gains `- Facts established:` (the line A.2's
  citation rule refers to; the portal's packs already carried it as
  `- Facts:`); `report_archive` labels name the spawn that WROTE the
  archived report (`stage3`, `stage3-part{k}`, `handoff-{n}`,
  `round{n}-fix`, `exit-gate-fix`, `contract-phase` — `class-sweep` folded
  into `round{n}-fix`); under overwrite semantics the report keeps two
  cumulative lines (`- Test files:`, the re-verified `### Class Sweep` /
  `### Retired Surface` / `### Test Scope Signal` blocks, carried forward
  with the archive path cited); `contract_extract` drops the trailing
  `VERDICT:` line from the contract file; `exit_gate` derives the test
  scope from the report's `- Test files:` line / `### Test files`
  subsection when no files are passed, scopes only path-taking runners
  (npm / pnpm / yarn `--`, jest / vitest / mocha / pytest / rspec / phpunit
  files, `go test` packages) and runs the full suite otherwise, skips
  tests when the build is red, and is safe when the helpers are sourced
  under zsh (no unquoted word-splitting anywhere in the new helpers);
  `req_shape_check`'s contract set also admits the headings the field
  writes (`Goal`, `Abuse tests`, `Not in scope`, the simplify proof
  sections, the map digest, the fix lane's sections); the doctor's
  `contract drift` line also reaches both lanes' Stage 0 pre-flight as
  ` · drift=N`; the migration gains a `swap_block` primitive (reworded
  sentences) with alternate anchors for an install that hand-applied the
  rules reword, and Test 35 migrates a REAL v0.24.0 install built from the
  git tag (byte-identical result, no skips). Every rule refresh stays
  interactive. Suites: bootstrap 328/328 (Test 35 a–q), hooks 193/193
  (T22 a–o); validation 55/60/65 (checks 64–65); `scripts/context-report.py`
  reproduces §0 on the portal (coder 197 spawns / 38 calls / 74k / 197k;
  51 % of coder tokens above 200k; `nested_memory` 45 KB median / 193 KB
  max per affected spawn; `--bare` 72k in this repo). Not done here, by
  design: the §7 LLM A/B runs (`--model` pinned), the portal migration
  (`--dry-run` first), the field smoke, the tag — owner actions (§9).
- r4.6a (2026-09-09): resolvable uncertainties resolved — §7 disclosure
  fixtures built (`coder-06`, `coder-07`, `spec-unread-09`, spec / scoped doc /
  extra file, runner keys, unit-tested); `test-bootstrap.sh` totals from
  three constants (311/311); portal gate bodies and pure-copy skills
  verified against templates (B.4 extraction works, #35 clobbers nothing).
- r4.6 (2026-09-09): context-goal gaps filled — §0.10 expected-effect
  model (coder ≈ −28 %, orchestrator ≈ −40 % now); D.8 mode files (v0.25.1,
  measured mode-only sections 26–36 % of each body); F.4 report-only rows
  for the platform's doc injection and workspace-doc sizes; A.5 ↔ B.1 link
  and the Stage 2 offer text; Appendix A checklist; §4 / §10 quality
  invariant; check 66 and Test 35 cover `modes/`; risk 16.
- r4.5 (2026-09-09): A.5 — grill code reads unlimited (owner); the four
  `≤ 8` references lose the budget entirely instead of naming a protocol.
- r4.4 (2026-09-09): third review applied — A.5 covers all four `≤ 8`
  code-read references (grill 162 / 168 / 218, map 174); pre-existing
  interaction / fan-out bounds classified and kept (constraint block, §1,
  §13 Q11); B.4 hardened (brace-depth extract, `bash -n`, exit 1 / 2 / 3,
  greenfield placeholder, fourth call site `espalier-fix.md:746–749`); F.1
  spawn count from `coding-log/`; anchors `espalier.md:471–474`, `:665`,
  `espalier-fix.md:916–1005`, `harness-coder.md:346–347`; risk 15; T22.
- r4.3 (2026-09-09): second review applied — A.5 grill read cap → protocol;
  B.4 `exit_gate` extracts `run_build` / `run_lint` / `run_tests` bodies
  from the installed gate (config keys dropped everywhere: §5, §6 check 64,
  §8, §9, risk 15, probe); A.1 contract-phase dispatch sentence dropped
  (§10, §11); C.1 archive call sites + `handoff-N-partK`; C.8 `rule_bullets`;
  A.2 "unrun build" scoped outside PARALLEL DISPATCH; D.1 five wordings
  (`espalier.md:722`); `espalier-fix.md:730`; Goal 3 and title carry the
  v0.25.0 / v0.25.1 split.
- r4.2 (2026-09-09): review fixes — A.1 removes `espalier-requirements.md:45`
  `≤ 5 files`; A.2/A.3 reordered (sentinel → archive → gate), PARALLEL
  DISPATCH clause, part-file detection, fix-lane regression guard; B.1
  anchored at the PASS write (628–636) with a fix-lane variant; B.2 template
  layout corrected, B.2/B.3 → v0.25.1, `maprun.py` `8.5` regex bug fixed in
  v0.25.0; B.4 gate-command keys; C.1/C.6/D.1/E.1 anchors and numbers;
  C.2 ask/simplify readers; D.6 new-file clause; F.1 duration-parser HUMAN
  marker; §4 hedge; checks renumbered 64–65 (+66 later), totals 55/60/65;
  risk 15; open question 7; scripts + field report copied into the repo.
- r4.1 (2026-09-08): §0.9 on-demand disclosure evidence (read rates by
  agent and month; nested-memory reach by Claude Code version; platform
  gap); Track D.5 spec-applied line + `[spec-unread]`, D.6 scoped docs in
  the pack + `scoped_docs` helper, D.7; check 66 renamed `spawn-protocols`;
  §7 disclosure fixtures; risks 12–14; open question 6.
- r4 (2026-09-08): reframed quality-first from transcript evidence (§0, 565
  spawns / 45 sessions): the per-turn baseline and spawn length outrank
  artifact size; Track A handoff protocol, Track B resume offer + router +
  gate helper, Track F measurement are new; r3 Track C and r2 Track A/C
  carried without caps; r2 Track B deferred.
- r3.1 (2026-09-08): artifact-diet reduction model (41 records, 40 % of
  artifact bytes) — file since lost from disk; text in the 05:42Z transcript.
- r3 (2026-09-08): the artifact diet (report state + log, requirements
  contract + notes, security contract, advisory cap, hygiene, docs clause,
  Grep-only); rules diet carried to v0.26.
- r2 (2026-09-08): re-measured after the owner's hand compress `eea0a620`;
  budgets 8/400 → 12/600; Not Precedent anchor and reword wording adopted
  from the portal.
- r1 (2026-09-07): first draft from the portal file-size analysis.

## Appendix A — Outside this release: the owner's global harness (checklist)

Not espalier's to change, recorded because it is the largest single lever
the field data shows: ≈ 70k of every subagent turn (§0.3), on every agent,
every call. Measured per spawn as attachments; "pipeline use" says whether
an `/espalier` run needs it.

| Item | size / spawn | what it is | pipeline use | action |
|---|---:|---|---|---|
| user + project instruction files | 110 KB (178 KB pre-compress) | `~/.claude/CLAUDE.md` + 15 `~/.claude/rules/*.md` (28.6 KB) + espalier rules (75 KB) + project `CLAUDE.md` | espalier rules yes; several user rules describe stores that are empty or tools the pipeline never calls | prune user rules that name no tool an espalier run uses; keep the rest |
| skill listing | 34 KB | ~130 skills' names + descriptions | espalier's own ~15 | disable plugins not used in coding sessions, per project |
| agent listing | 11 KB | ~50 agent types | 3 harness agents + scout / oracle | remove or scope agent definitions not used in coding sessions |
| MCP instructions | 3.7 KB | per-server instruction blocks | none for a pipeline run | scope MCP servers to the projects that use them |
| SessionStart / UserPromptSubmit hook output | unmeasured | memory index, skill-activation banner, caveman mode | none | keep only hooks whose output an agent acts on |

Halving the total is ≈ −35k per call on every agent, with no effect on any
espalier gate — the same order as Track A on the coder and larger than the
rules diet. `scripts/context-report.py` (Track F) measures a bare session's
first-turn context, so the effect of each trim is visible the same way this
plan's is: run it before and after.

## Appendix B — Where the field numbers live

The four mining scripts sit in the repo under `scripts/context-report/`
(`mine_transcripts.py`, `mine2.py`, `mine3.py`, `mine4.py` — the seed for
Track F.2's single `scripts/context-report.py`), and the full field report
is `docs/context-field-report-2026-09-08.md`; both were copied from the
2026-09-08 session scratchpad in r4.2. The memory index carries the
headline numbers.
