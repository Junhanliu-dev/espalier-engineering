# Pipeline field report — where wall-clock goes (2026-09-14)

Source: 48 changes started on or after 2026-08-18 (`portal.quota.com.au` 27,
`portal.cneaustralia.com.au` 19; `ocv-dashboard`, `z-memo-palace` and the
acsproperty install have no changes in that window) read from
`espalier/changes/*/*/pipeline-state.md` Stage History, plus the
portal.quota Claude Code transcripts under
`~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au/`
(333 session files, 45 with `subagents/*.jsonl`). No external drive was
mounted at the time (`/Volumes` held only `Macintosh HD`). Companion to
`context-field-report-2026-09-08.md` (tokens); this one is seconds.

Sections 1–5 are the miner's report verbatim. Section 6 adds three direct
measurements taken alongside it.

Data: 48 changes started ≥ 2026-08-18 (quota 27, cne 19, ocv 0, zmp 0, acs 0 — ocv/zmp/acs have no post-Aug-18 changes) from `espalier/changes/*/*/pipeline-state.md` Stage History; 333 portal.quota Claude Code session files + 45 session dirs with `subagents/*.jsonl` (`.meta.json` carries `agentType`, `description`, `toolUseId`). Scripts + raw JSON in this scratchpad (`stages.py`, `sub.py`, `toollat.py`, `latency.py`, `orch.py`, `orchsum2.py`, `gaps.py`, `prepost.py`; `changes.json`, `subagents-*.json`, `orch-timelines.txt`, `per-change-table.md`).

Method for stage spans: the interval before each Stage History row is booked to that row's stage. A `2 PASSED … approved by user` row and `RESUMED` rows book to human wait. Everything else is "stage span" = agent wall + orchestrator bookkeeping + any un-flagged human absence. Legacy minute-only timestamps floor to 0.

## 1. Stage spans per change (seconds; medians / p75)

Per-change table: `per-change-table.md` (48 rows).

### feat (n=24: 21 pre-v0.25, 3 v0.25-era; 20 COMPLETE, 3 ABORTED_LATE, 1 IN_PROGRESS)

| stage | all med | all p75 | pre-v25 med | v25 med (n=3) |
|---|---|---|---|---|
| 1 requirements (incl. grill Q&A wait) | 385 | 764 | 360 | 615 |
| 2 review (agent) | 190 | 344 | 190 | 122 |
| 2 approval (human) | 81 | 160 | 0 | 102 |
| 3 coding | 1611 | 3600 | 1423 | 3294 |
| 4 panel (all rounds) | 936 | 1786 | 936 | 839 |
| 5 contract phase | 357 | 751 | 325 | 1430 |
| 6 contract review | 252 | 843 | 262 | 0 |
| 7 push | 0 | 171 | 0 | 0 |
| 8–10 | 0 | 279 | 0 | 0 |

Stage 3 first-return (entry → first `3` row after entry): med 1043s, p75 1326s (n=15). Coder spawns per feat: 22× one spawn, 1× four, 1× five (multi-spawn only in v25 era). Handoffs: 0. Stage 5/6 SKIPPED on 1/24 feats.

### fix (n=21: 17 pre-v25, 4 v25; 19 COMPLETE, 2 IN_PROGRESS)

| stage | all med | all p75 | pre-v25 med | v25 med (n=4) |
|---|---|---|---|---|
| 0 causal link | 0 | — | 0 | 0 |
| 1 requirements+approval | 247 | 373 | 247 | 345 |
| 3 coding | 660 | 1423 | 660 | 1423 |
| 4 panel | 605 | 2118 | 605 | 4426* |
| 5 | 0 | 300 | 0 | 0 |
| 6 | 0 | 456 | 0 | 0 |
| 7 push | 199 | 480 | 171 | 2581* |
| 8–10 | 0 | 0 | 0 | 0 |

*v25 fix medians are dominated by two outliers: cne `backend-lockfile` Stage 4 = 10235s (panel spawned, PASSED row 2.8h later — panel agents themselves take < 10 min; the gap is unflagged human/session absence) and quota `signup-postcode` Stage 7 = 36478s ("closed retroactively", session ended). Stage 5/6 SKIPPED (no contract) on 13/21 fixes. Stage 3 first-return med 685s. Exit-gate-red re-spawn rows (loose regex on "gate/red/fail"): fix 11 rows across 21 changes, feat 6 across 24 — the fix number is inflated by Stage 3 PASSED notes that mention "exit_gate green (…)"; hand-verified reds in v25 era: quota refactor `EXIT GATE RED` (backend baseline failure, 414s to clear by hand), zero on the v25 feats.

### refactor (n=3): s3 med 3363, s4 med 2941, one `ROUND 2 RESPAWN` after an API 403 killed the reviewer (3282s lost).

## 2. Stage 4 — panel rounds

- Round wall = the reviewer, not the security agent: v25 reviewer med 241s (p75 317, max 540) vs security med 190s (p75 244, max 363); both spawned within ~25s of each other, run in background concurrently. Aug18+ reviewer med 293s (n=103).
- Stage History `4`-row deltas (row to row, includes the coder fix-round between two panel rows): feat med 893s / p75 1289s (n=31); fix med 462s / p75 876s (n=45).
- Round-1 outcome (first Stage-4 verdict row, 48 changes): reviewer PASS_WITH_FIXES 20, FAIL 6, PASS 2, unparsed 16; security PASS 17, PASS_WITH_FIXES 8, unparsed 19, FAIL 0. **Every round-1 FAIL is the reviewer.** Changes with ≥1 `ROUND n FAIL` row: feat 6/24, fix 2/21, refactor 1/3.
- Across all Stage-4 rows Aug 1+ (all installs): 81 PASSED rows, 30 `ROUND n FAIL` rows, 5 rows of user-chosen P2/P3 rounds after a PASS (`voluntary`, `REOPENED`, "requester chose").
- P0/P1 by tag: not measurable — records are overwritten each round; the final-round records hold rev P0=1, P1=2, sec P1=1, P2 32, P3 84, none tagged. Round-1 findings survive only as the bracketed snippet in the `ROUND n FAIL` Stage History row (30 rows).
- Session cfd69823 (3-sub-task feat): round 1 wall 05:14:02→05:23:06 = 544s (reviewer 540s); fix-round coder 720s; round 2 = 317s. Panel-to-fix-spawn gap 46s; fix-return-to-panel gap 74s.

## 3. Stage 3 — coder

Subagent transcripts, portal.quota, harness-coder:

| | v25 (n=20) | Aug18+ (n=151) |
|---|---|---|
| wall med / p75 / max | 627 / 953 / 1351 s | 601 / 901 / 7985 s |
| assistant turns med / p75 | 37 / 58 | 34 / 54 |
| Bash calls med | 22 | 25 |
| Edit calls med | 14 | 12 |
| Read med (espalier / project) | 3 / 6 | 2 / 4 |
| Bash test/build calls med | 18 | 15 |
| tail after last Edit | 17 s | 19 s |
| peak ctx med | 210k | 206k |
| s per turn med | 15 | 14 |

Where coder wall goes (v25, 12856s over 20 spawns, tool-result timestamp minus tool-use timestamp):

| bucket | s | share | calls | avg |
|---|---|---|---|---|
| model + harness (no tool pending) | 9020 | 70% | — | — |
| Bash test/build/lint (keyword match) | 2300 | 18% | 380 | 6.1s |
| Edit (tool + hooks) | 1275 | 10% | 295 | 4.3s |
| Write / Bash other / Read / git | 261 | 2% | 486 | 0.5s |

Edit latency is user-global hooks, not espalier: espalier's `map-guard.sh` + `post-edit-wrapper.sh` measure 0.03s + 0.06s; `~/.claude/settings.json` runs 3 PreToolUse + 6 PostToolUse hooks on Edit (typescript-preflight timeout 80s, compiler-in-the-loop 60s, post-tool-use-tracker 240s). Sample Edit: tool_use 04:41:02.1 → result 04:41:12.3 (10.2s).

Model latency does not scale with context in this data (per assistant message, v25 harness spawns): 50–100k ctx med 5.6s; 100–150k 7.4s; 150–200k 8.6s; 200–250k 7.3s; 250–300k 6.9s. ≈ 2.3–3.1 s per 100 output tokens in every bucket. Turn count, not context size, sets coder wall.

Bash test/build inside coder (v25, 386 calls): build med 9.5s p90 20s (63 calls, 763s); scoped test runs med 4.4s (57 calls, 440s); lint med 2.6s (37, 246s); the "full test" bucket (229 calls, 1017s, med 0.2s) is keyword noise (`grep test`, etc.) mixed with real suite runs — treat the split as rough.

Stage-3 span vs coder wall (cfd69823): sub-task 1 span 1258s vs coder 1103s; sub-task 2 1113 vs 1022; sub-task 3 1495 vs 1351 → 90–150s orchestrator per spawn (exit gate via `docker exec` build/tests + `git status` + state rows). All 3 sub-tasks serial by the orchestrator's choice ("serial dispatch, 3 sub-tasks"); Stage 3 = 62 min of a 148-min session.

## 4. Orchestrator sessions (portal.quota)

Time classification of the 5 v25-era sessions that spawned harness agents (gap booked to: agent-in-flight; ask-pending; >300s with neither = idle; else orchestrator):

| session | lane | agent wait | human (ask) | orchestrator | idle | spawns | asks |
|---|---|---|---|---|---|---|---|
| cfd69823 09-10 | feat 3 sub-tasks | 6337 | 669 | 1861 | 0 | 10 | 10 |
| f92d8ee9 09-11 | fix → escalate → feat | 4514 | 555 | 3021 | 3234 | 16 | 14 |
| 2c36d5d3 09-11 | fix | 333 | 1140 | 557 | 0 | 3 | 3 |
| be477e65 09-11 | fix | 1073 | 47 | 1256 | 0 | 5 | 5 |
| 611df2e5 09-14 | feat (to Stage 3) | 3 | 207 | 714 | 0 | 1 | 3 |
| **total v25** | | **12261 (55%)** | **2618 (12%)** | **7409 (33%)** | 3234 | | |
| Aug18–Sep9 (30 sessions) | | 440708 (76%) | 88790 (15%) | 52118 (9%) | 103709 | | |

Orchestrator time before the first harness spawn (Stage 0–2 work, ask waits and >5-min idles removed): feat med 615s (n=16; tool calls before first spawn med ~30, asks med 4–7); fix med 446s (n=19). After the last agent returns (Stage 7–10 + close): feat med 244s, fix med 240s. Gap agent-return → next spawn (exit gate + bookkeeping, no ask between): coder→panel med 91s p75 122s (n=48); coder→coder 58s (n=13); panel→Stage-5 coder 58s (n=10); panel→fix coder 47s (n=5).

cfd69823 breakdown (148 min /espalier → COMPLETE): agents 105 min (coders 86: 1103+1022+1351+720+953; panels 19.5: 544+317+313); asks 11 min; orchestrator ~31 min of which Stage 1 code reading + requirements writing ≈ 8 min (30 bash reads 03:53→03:56, writes 04:03→04:05), Stage 7–10 push/CI/lint ≈ 8 min, inter-spawn gates ≈ 8 min.

f92d8ee9: `/espalier-fix` predictive gate tripped (12 files, 3 layers) → user escalated → Stage 1 re-run as feat with 5 grill asks (01:23→01:36); 2641s "USER: continue" gap after the Stage-5 coder = user away.

## 5. Ranked time sinks

1. **Coder spawn wall (Stage 3 + fix rounds + Stage 5 contract coder)** — 86 of 148 min in the one full v25 feat; med 627s per spawn, 70% model turns (med 37 turns × 15s), 18% test/build waits, 10% Edit hooks (user-global). Serial sub-task dispatch stacks these end to end.
2. **Stage 1–2 orchestrator + grill** — feat pre-spawn orchestrator med 615s + ask waits med 422s; fix 446s + 89s. Pure human wait share of session time is 12–15%.
3. **Panel rounds** — 544s per round (reviewer-bound; security finishes ~35% earlier); 1 extra round on 6/24 feats, always from the reviewer; +5 user-chosen P2 rounds. Fix lane Stage 4 med 605s.
4. **Stage 5/6 contract phase** — when a contract exists: coder 953s + reviewer 313s + ~170s gates = 24 min (cfd69823); 2995s once (quota leads: "1 of 2 entries already covered"). Skipped on 13/21 fixes.
5. **Inter-spawn orchestrator gates** — ~1–1.5 min per transition, ~6–8 transitions per feat → 6–10 min.
6. **Stage 7–10** — med 4 min orchestrator, plus deploy/delivery asks (4 min in cfd69823).
7. **Outliers, not machinery**: API-403 reviewer death (3282s), session-end/retroactive closes (36478s), coder running under a dev container with a baseline-red backend suite (414s hand gate).

Thin/ambiguous: v25 era = 3 feats + 4 fixes (+1 refactor); ocv/zmp have no post-Aug-18 changes; P0/P1 tag counts unavailable (records overwritten); test/build classifier is a keyword match; Stage History spans include unflagged human absence (two v25 fix outliers); Aug18+ orchestrator share (9%) vs v25 (33%) differs mostly because the v25 sample has one 3-sub-task feat and one fix→feat escalation session.

## 6. Direct measurements added

### 6.1 Gate command durations (portal.quota, Bash tool_use → tool_result, since 2026-09-01)

| command class | where | n | median | p75 | max |
|---|---|---:|---:|---:|---:|
| `npm run build` / `next build` | coder | 41 | 12s | 16s | 33s |
| `npm run build` | orchestrator | 17 | 9s | 15s | 19s |
| `exit_gate` helper | orchestrator | 5 | 19s | 80s | 89s |
| tests (`vitest`, `npm test`) | coder | 345 | 4s | 10s | 108s |
| tests | orchestrator | 45 | 7s | 27s | 130s |
| `tsc --noEmit` | coder | 124 | 6s | 9s | 76s |
| lint / prettier | coder | 141 | 3s | 5s | 62s |
| regression verification (worktree) | orchestrator | 3 | 7s | 14s | 14s |
| `git push` (pre-push hook) | orchestrator | 37 | 4s | 34s | 163s |

The full backend or frontend suite is 65–108s; a scoped run is ~5s. On
portal.quota `run_tests` is a two-line `(cd backend && npm test) || return 1;
(cd frontend && npm test) || return 1` body, which `_gate_scoped_cmd` does
not scope (multi-line body → full suite), so every `exit_gate` call runs
both full suites. `z-memo-palace`'s `uv run pytest -q` is not in the runner
table either (full suite).

### 6.2 Bash blocks the orchestrator retypes (portal.quota main sessions, since 2026-08-25)

| block | Bash calls | sessions | median chars | total chars |
|---|---:|---:|---:|---:|
| fix-lane regression verification (`REGRESSION_VERIFIED`) | 45 | 14 | 1,247 | 76k |
| Stage 7 commit recording (`## Commits` / `_cache_append`) | 57 | 22 | 1,648 | 112k |
| `Reviewed-Diff` certificate | 89 | 26 | 1,386 | 148k |
| Stage 4 post-review drift parse (`parse-drift-blocks`) | 35 | 23 | 1,179 | 49k |
| Stage 8.5 drift table (`doc-patches`) | 24 | 13 | 1,558 | 41k |
| fix-lane back-link (`_backlink_one`) | 8 | 5 | 2,529 | 21k |
| by-hand build/lint (`… & wait`) | 98 | 26 | 698 | 161k |
| `exit_gate` helper call | 21 | 3 | 384 | 13k |

≈ 620 KB of orchestrator-typed bash across 26 sessions, at the measured
2.3–3.1s per 100 output tokens (§3) ≈ 2–3 minutes of pure output per
session, plus the transcription risk each retype carries (the v0.22 field
find — an unanchored certificate read — was one such retype).

### 6.3 Contract phase rows, folded era (portal.quota, Stage 5 `IN_PROGRESS` → `PASSED`)

| change | span | note |
|---|---:|---|
| 2026-09-01 realtime-messaging | 6 min | 17/17 entries: security marked all PROVEN — verification spawn, 2 tests written |
| 2026-09-07 quote-accepted notifications | 11 min | 6 fields, 2 already covered per auditor |
| 2026-09-10 notification-settings | 23 min | 13 fields, 19 new abuse cases; 5 "already covered" |
| 2026-09-11 leads default radius | 50 min | 1 of 2 entries already fully covered; one store-unchanged leg added |
| 2026-09-10 fix logout (P2 pass) | 11 min | 3 contracted abuse tests |
| 2026-08-31 refactor graphql | 5 min | 9/9 entries COVERED by existing suites; no test written |
| 2026-09-11 refactor constants | 5 min | join leg covered; leave leg uncovered → one test |

In 7 of 7 the auditor's contract already carried coverage marks
(`status: SATISFIED by …`, "PROVEN", "already covered") — a field
convention, not a template line. In 2 of 7 the coder spawn wrote nothing.
Every contract phase was followed by a ~4-minute delta-review spawn.
