# Changelog

## 0.22.1 — 2026-08-18

Patch: **comment diet** — field feedback: agents still write too MANY
comment lines, not just long ones. The brevity default strengthens to
default-zero, always subordinate to the project's own discovered
convention (a codebase mandating JSDoc on exports keeps it):

- `harness-coder.md` — the Comments constraint becomes: default is NO
  comment; one plain line ONLY for a constraint the code cannot show;
  never banners, signature-restating doc-blocks, narration, or
  reviewer-directed notes; RE-SCAN the diff and DELETE failing comments
  before writing the coding-report (a diff whose comment lines rival its
  code lines is over-commented).
- `coding-standards.md` — new "Default to NO comment" bullet under
  `## Comments & Docstrings`.
- `harness-reviewer.md` — the Readability `comments:` tag now also flags
  EXCESS comments (banners / signature doc-blocks / obvious notes),
  naming the exact lines to delete.
- Migration #31: `scripts/migrate-v0.22.0-to-v0.22.1.sh` — anchored edits
  to the 3 per-project files (backups `.pre-v0.22.1.bak`; customised
  files skip-with-record); the reviewer edit is a substring splice that
  handles both the fresh-template and #29-migrated line wraps.

## 0.22.0 — 2026-08-18

Minor: **pipeline speed II** — the second speed release. Same gates,
sentinels, round caps, certificates, and both human checkpoints; every
change is dispatch-order, read-scope, or wait-scheduling. Design doc:
`docs/pipeline-speed-plan-v2.md` (two-agent fresh-eyes review + owner grill
recorded inside).

- **Speculative Stage 5 (quarantine-on-FAIL, both lanes).** The test-coder
  joins the ROUND-1 Stage 4 panel as a third concurrent agent — on the
  typical 1-round run the entire test-writing duration hides behind the
  panel (round-1 time = max(reviewer, security, tests), not sum). It
  reports to `coding-report.part-test.md`; the orchestrator appends it
  (guarded) only after the round resolves, so the panel's coding-report
  read is never racy, and both panel prompts + both reviewer agents carry
  the in-flight exclusion as an installed contract. On a panel
  FAIL/escalation the listed speculative files QUARANTINE under the change
  dir (fingerprint-excluded), so the pre-round whole-tree build/lint, the
  next panel round, and the coder re-spawn never see a stale artifact; a
  single post-final-PASS spawn restores/reconciles and carries the
  contracted abuse tests (one spawn, never two). Crash recovery: orphan
  part files are discarded WITH their listed files; an unenumerable orphan
  surfaces to the human — or sets ESCALATED on unattended runs, never a
  hang, never a guess-delete. `speculative-tests: off` in
  `.espalier-config` restores the serial flow verbatim (default: on).
- **Stage 6 delta rounds.** Test re-review rounds ≥ 2 now receive the
  `CHANGED SINCE LAST REVIEW:` set — the delta-scope contract Stage 4 got
  in v0.21, extended to the loop it missed. Floor not ceiling;
  whole-change verdict unchanged.
- **Stage durations in `espalier-stats.sh`.** Per-stage wall-clock from the
  Stage History timestamps the pipeline already writes, split
  human-wait / agent-work / other by the row that CLOSES each span;
  unattended `auto-*`/`non-interactive` rows never count as human;
  section-bounded parsing; one bad row skips that row, never the report.
  This is the field data the deferred Stage 3/5 fold decision keys on.
- **Pre-flight fold.** Non-critical drift/convention/doctor signals no
  longer block on their own prompt — they record a
  `deferred-to-approval-gate` marker and ride a third question on the
  approval gate the human already attends. Critical/expired rows keep the
  immediate blocking prompt. One fewer human round-trip per signal-carrying
  run.
- **Stage 9 deploy pre-authorization.** Deploy-configured repos collect
  `Deploy-Target:` at the approval gate (the Push-Target pattern); Stage 9
  honors it without re-prompting — removing the post-CI stall where the
  human has walked away. Health-check gate, rollback, and Stage 10
  acceptance untouched. Also defines the previously unspecified unattended
  Stage 9 posture: pre-auth deploys; `ASK` records SKIPPED needs-human; an
  unauthorized target is never auto-deployed.
- **Stage 8 CI wait protocol.** One blocking watch call (chunked ~9-minute
  budgets for long CI) instead of a model round-trip per poll; the
  notify-only Stage 8.5 drift check may ride the first watch message.
- **Orchestrator micro-parallelism.** Build+lint run as concurrent jobs at
  every Stage 3 exit gate / pre-panel re-run (per-pid exit codes; serial
  when the commands plainly depend on each other); the fix lane's Stage 7
  back-link contract becomes a function called N times inside ONE bash
  invocation; agent-free bookkeeping may batch.
- **Pre-push hook cost cuts (no check removed).** Opt-in
  `hook-parallel-gates: yes` runs build/lint/tests as concurrent jobs —
  sum → max per gated push — written only when init's discovery judges the
  commands independent AND the human confirms (new post-discovery
  question; `--hook-parallel` bootstrap flag; absent = serial,
  byte-equivalent). The WARN-only dependency audit caches per
  manifest+lockfile hash with a TTL (`dep-audit-ttl-days`, default 7) in
  gitignored `espalier/.dep-audit-cache`.
- **Fix (field-found by the release's live smoke): anchored pre-push
  certificate read.** The hook's `Base-Ref:`/`Reviewed-Diff:` greps were
  unanchored last-match, so a Stage History note QUOTING either token in
  prose could outrank the real Status-block line — bogus revision,
  empty-diff fingerprint, false BLOCK on a correctly certified change.
  Now anchored to the line-start `- Key:`/`Key:` shapes (fail-closed
  direction preserved; regression test T5q).
- **Known issue (pre-existing, documented — not a v0.22 regression):** the
  `eval/security` FP gate fails under today's model AT BASELINE too
  (v0.21.1 templates: 2 FPs incl. a clean-fixture mismatch; last held
  FP=0 on 2026-07-08 under that era's model). Catch-rate is 1.00 in every
  run on both template versions; the counted "false positives" are the
  judge double-counting axis-sliced findings of the SAME planted defect.
  Needs a judge-collapse/fixture recalibration pass — see
  `eval/security/KNOWN-ISSUES.md` and `docs/deferred-items.md`.
- Migration #30: `scripts/migrate-v0.21.1-to-v0.22.0.sh` — refreshes 4
  pure-copy surfaces (backups `.pre-v0.22.bak`); anchored edits into the 4
  substituted per-project files including a span-splice of the hook's
  audit block and the anchored certificate read (`bash -n` verified
  after; customised files skip-with-record); appends the audit-cache
  gitignore entry; writes no config keys.

## 0.21.1 — 2026-08-17

Patch: **comment brevity** — field feedback: the generated coder agents write
comments that run too long. Three per-project files gain a short-comments
default, always subordinate to the project's own discovered convention (a
codebase that mandates fuller docstrings, e.g. JSDoc on exports, keeps them):

- `harness-coder.md` — new constraint bullet: comments are SHORT, clear, and
  few — one plain line stating the non-obvious constraint or the why; never a
  paragraph, never narration, never reviewer-directed commentary; multi-
  sentence explanations belong in the change's docs, not the code.
- `coding-standards.md` — "Keep comments SHORT" bullet under
  `## Comments & Docstrings`: one plain line beats a paragraph.
- `harness-reviewer.md` — the Readability `comments:` tag now also flags an
  OVERLONG comment (a paragraph where one line would carry the constraint),
  with the one-line replacement named in the Fix cell.
- Migration #29: `scripts/migrate-v0.21.0-to-v0.21.1.sh` — anchored edits to
  the 3 per-project files (backups `.pre-v0.21.1.bak`, once per file);
  customised files skip-with-record. Suites: bootstrap 257/257 (new Test 29),
  hooks 146/146.

## 0.21.0 — 2026-08-17

Minor: **pipeline speed** — the same gates, round caps, and review contract,
with the redundant reads and redundant human waits removed. Nothing about the
quality machinery changes: coder/reviewer/security stay separate agents, every
fix still triggers a fresh panel round with per-round sentinels, all
programmatic gates (build/lint re-run, fingerprint certificate, push gate) are
untouched. What changes is the cost per spawn and per round:

- **Context pack** (`context-pack.md`, assembled once at Stage 3 entry, both
  lanes). The orchestrator derives the touched layers, spec paths, rules
  files, and 1-2 reference files per layer ONCE and hands the pack to every
  Stage 3-6 spawn — previously the coder, both panel agents, and both test
  spawns EACH repeated that discovery from scratch (5-11 cold starts per
  change). The pack carries paths and facts only, never conclusions; every
  agent still reads the named files itself and the current code always
  outranks the pack. A spawn that finds no pack falls back to its own
  discovery — accelerator, never a gate.
- **Delta-scoped re-review rounds.** On round n≥2 the panel's REQUIRED reads
  are the fix's files + the prior round's findings + direct callers/dependents
  of what changed — a floor, not a ceiling (any suspicion → expand; the
  whole-diff verdict duty is unchanged). Soundness: every line of the final
  diff was reviewed fresh in the round it last changed, build/lint re-runs
  whole-tree before every round, and the `Reviewed-Diff` fingerprint blocks
  unreviewed edits at push. The security agent additionally gets **delta
  mode**: when its own prior round was clean (the round exists because the
  correctness reviewer failed), it audits the fix delta for new
  trust-boundary reads / contract changes and re-issues a fresh current-round
  sentinel — full re-audit the moment either question answers yes.
- **Parallel disjoint sub-tasks** (full lane, Stage 3). Sub-tasks whose
  planned file sets are pairwise disjoint (shared modules count as overlap)
  may dispatch as concurrent coder spawns; parts concatenate into one
  coding-report and the exit gate + panel run on the combined result. Any
  overlap or doubt → serial, as before.
- **Push-target pre-authorization** (both lanes). The requirements approval
  gate's `AskUserQuestion` gains a second question: pre-authorize the Stage 7
  push target, name another, or "ask me again at Stage 7". A pre-authorized
  green run no longer stalls mid-pipeline on a redundant confirm; every
  programmatic push gate still applies, and Stage 10 delivery acceptance
  remains a human act.
- **Grill: light-tier batching.** `light`-tier questions that are pairwise
  INDEPENDENT (no answer could eliminate/reorder/rephrase another) may be
  batched into one `AskUserQuestion`. `full` tier and decision mode stay
  strictly sequential — there the discriminating question depends on the last
  answer by design.
- **Deferred** (recorded in `docs/deferred-items.md`): folding interface-test
  writing into Stage 3 and merging Stage 5/6 into the panel — highest
  remaining spawn saving, but it restructures the stage contract; punted
  until the field data (espalier-stats round distributions) justifies it.
- Migration #28: `scripts/migrate-v0.20.0-to-v0.21.0.sh` — refreshes the 4
  pure-copy files (backup-on-diff → `.pre-v0.21.bak`, backed up ONCE per file
  even across multiple inserts) and anchored-inserts the agent sections; a
  customised agent file is skipped with a `.migrations-skipped` record, never
  mangled, and a skip record counts as handled so the migration still reaches
  its "nothing to do" exit on customised installs.
- Fix (pre-existing, surfaced by this release's review): `/espalier-migrate`'s
  Step 1 detection machinery, Step 2 plugin probe, and Step 3/6 run lists
  ended at v0.18.0 — a v0.18+ install could never auto-detect or run the
  v0.19.0/v0.20.0 migrations through the documented runner path. All four
  now extend through v0.21.0 (detection e2e-verified for up-to-date,
  marker-missing, and skip-recorded installs).
- Suites: bootstrap 251/251 (new Test 28 incl. migration apply / no-op /
  customised-skip paths), hooks 146/146.

## 0.20.0 — 2026-08-12

Minor: **slice PRs** — the run lane's work becomes reviewable one ticket at a
time, without changing its merge topology. Field-derived: the motivating
14-slice production run ended in a single integration PR of 103 files /
+14,051 lines — mergeable, not reviewable. A stacked-PR design (one branch
per ticket based on its dependency) was drafted first and rejected on review
— merge-strategy coupling (squash rewrites break retargeted children),
stateful base derivation, a missing rework loop, later sibling-conflict
discovery, unsound diamond-dependency bases; the record lives in
`docs/maprun-pr-lane-plan.md` (which replaces the stacked draft).

- **Slice-PR flow** (new engine file `maprun-pr.sh`, **opt-in** via a `pr`
  key in a map's plan.json — without it nothing is ever pushed, exactly v0.19
  behavior). Per PASSED ticket the master runs **open → merge → sync**: push
  the ticket branch, open its PR against the integration branch *before* the
  local merge, then merge locally as before (union-merge rules intact) and
  push the integration branch — the forge sees the PR's head contained in its
  base and closes the slice PR as **merged** on its own, preserving the
  slice's diff and CI verdict as the review surface. Slice review is
  advisory-after-merge (a PASSED slice already survived grill + reviewer +
  security); feedback becomes follow-up fix tickets. At run completion,
  `maprun-pr.sh final` opens the assembly PR (integration → base) whose body
  links every slice PR — the CI + sign-off gate; merging it stays a human
  act.
- **`maprun-pr.sh setup`** — plan-time probe: verifies gh auth *and push
  permission* (a read-only token passes `auth status` and dies at the first
  push), creates + pushes the integration branch, and scans
  `.github/workflows/` for `pull_request` workflows whose `branches:` filter
  would silently skip CI on slice PRs (the field repo hit exactly this).
  Pushes are fast-forward only — only the master ever advances the maprun
  branches, so a rejected push means someone else wrote to them and is
  reported, never forced.
- **Fix: shared-config push-block poisoning.** `maprun-integration.sh`
  applied its push block with a plain `git config`, writing the SHARED
  `.git/config` — blocking pushes from the operator's own checkout (latent in
  v0.19: nobody pushed; fatal once the master must). Now `--worktree`-scoped
  like dispatch, with a self-heal that unsets the poisoned shared value on
  sight.
- **Engine** — `maprun.py` state gains `pr_number`/`pr_url` (+ `set-pr`
  subcommand, `status` prints `PR#`); the lane skill's plan step asks the PR
  opt-in explicitly (naming the rail change), pass step 4 is open → merge →
  sync with warn-and-continue on forge failure (exit 5 never blocks the local
  merge), safety rails restated.
- **`worker_mode: inline`** — a second execution mode beside the headless
  ones: dispatch prepares the isolated worktree (branch off the integration
  branch, push block, deps) and spawns nothing; the MASTER works the ticket
  in-session, spawning the stage agents directly, one ticket at a time, with
  questions going straight to the human (no parking) and state marked
  directly (no sentinels). No headless CLI needed — the one mode available on
  a Copilot-only install. A session killed mid-ticket leaves `DISPATCHED`
  with no live pid; the next session's reap retries it from
  `pipeline-state.md` like any dead worker. The headless modes keep the
  dashboard (`watch`) and the never-run-a-pipeline master doctrine; the SKILL
  scopes that rule per mode and tells the plan step to put the trade-off to
  the human.
- **eval/maprun**: new fixture `run-07-pr-flow` (open-before-merge ordering;
  a forge failure that must warn and continue; stop-after-one-pass).
- Suites: bootstrap adds Test 27 (stub-gh + bare-remote e2e: setup/open/sync
  push for real against a file remote; shared-config hygiene regression;
  opt-in no-op gate; migration trio). Migration #27
  (`scripts/migrate-v0.19.0-to-v0.20.0.sh`) installs `maprun-pr.sh`
  (write-if-absent), refreshes the lane skill (backup-on-diff), patches the
  stock push-block lines in an existing `maprun-integration.sh`, heals a
  poisoned shared config, and re-blocks existing `_integration` worktrees
  worktree-scoped.

## 0.19.0 — 2026-08-11

Minor: **the run lane** — a cleared map executes itself, survivably. The lane
was field-built inside a production repo (a 14-slice Keystone schema map)
before being generalized here. Suites: bootstrap 225/225, hooks 146/146;
eval/maprun 6/6 fixtures, catch-rate 1.00, zero judge-verdict mismatches
(provisional until judge validation + shadow fixtures); validation is
52/57/62 by platform set (new checks 61-62); migration #26.

- **`/espalier-maprun` lane** (new pure-copy skill `espalier-maprun`) — drives a
  CLEARED map's FILED slices to completion over hours and days. Three moving
  parts: an interactive **master** pass (reap → halt-on-escalation → relay
  parked questions → merge → grill-then-dispatch → verify → report, then
  STOP), up to N headless **workers** (`claude -p` / `codex exec`, one per
  isolated git worktree, stages 1–6 only, push blocked at git config level),
  and disk **state** (`plan.json` + `state.json` beside the map — the master
  holds nothing in context, so a master killed at any instant loses at most
  the pass it was in). A `plan` step authors the execution config from the
  cleared map (ticket deps confirmed by the human; workspaces/verify/env
  seeded from what init discovered).
- **Survival model** — pass-per-fresh-session master ("status output is the
  only memory"); supervisor-owned heartbeats with pid-identity + staleness
  cross-checks (a recycled pid is a SUSPECT, not a worker); death diagnosis
  (usage-limit log signatures → resumable `QUOTA`; git-state check catches a
  state file claiming work the worktree cannot show, and clears the false
  stage claim); resume-safe dispatch (checkpoints uncommitted work, merges
  the integration branch into the reused worktree so relayed answers reach
  the resumed worker, deletes stale outcome sentinels, refuses to dispatch
  over an unanswered question).
- **Context hygiene** — workers get no access to the master's `plan/` dir:
  questions park into the worker's OWN change folder (`.maprun-question.md`)
  and reap carries them over; the contract scopes what a worker may read
  (never sibling slices); `worker_mode: staged` bounds worker context with
  one fresh session per stage group (wrapper-owned loop, no-progress
  escalation); optional `worker_setting_sources` strips user-level config
  from workers; the master reads escalation records only through subagent
  excerpts.
- **Engine** (`hook-templates/maprun.py` + `maprun-{dispatch,merge,
  integration,verify}.sh`) — stdlib-only state machine (init/status/frontier/
  reap/tail/mark/graph + optional ClickUp/Harvest sync that no-ops without
  config and never blocks the build); dependency-graph validation at init;
  atomic state writes; stream-json worker logs summarized by `tail`.
  Bootstrap installs engine files **write-if-absent** so a locally-adapted
  engine survives re-runs and migration.
- **`eval/maprun/` harness** (grill-harness pattern) — six fixtures plant the
  lane's designed-against failures (merging/dispatching past an escalation,
  answering a parked question instead of relaying, skipping the pre-dispatch
  grill, trusting state over the worktree, treating QUOTA as an error,
  resolving a merge conflict — including a human "just fix it yourself"
  bait); mock command scripts stand in for the repo; LLM judge, derived
  verdicts, 0.80 catch-rate gate, judge-validation harness.
- **Field-hardened during a live production run** (three fixes/features born
  from the lane driving a real 14-slice map the day of release): the push
  block is **worktree-scoped** (`extensions.worktreeConfig` + `--worktree` —
  a plain `git config` in a worktree writes the SHARED config and had blocked
  the operator's own checkout); **durable dispatch pause** (`maprun.py pause
  [reason]` / `resume` — `dispatch_paused` in state.json empties the
  frontier, in-flight workers finish and merge, the instruction survives
  every session boundary); Harvest **`"mode": "record_only"`** (hours
  recorded in state.json, never posted — for operators running their own
  timer) plus tracker-ref note prefixes.
- **Operator observability** (`maprun.py watch` / `feed`): headless workers
  were invisible without asking the master. `watch [sec] [--once]` is a
  read-only live dashboard (state, live stage from the worktree's
  pipeline-state.md, process-alive check, heartbeat age, waiting
  outcome/question sentinels, last visible worker action) safe to leave
  running beside a live master; `feed <key> [--follow]` renders a worker's
  stream-json log as greppable `THINK`/`SAY`/`TOOL`/`RES` lines — the
  worker's whole thought process, live. Codex/plain logs pass through raw.
  On a TTY, `watch` is a full-screen tabbed TUI (stdlib curses): Overview
  plus one tab per active worker (←/→ switch) with job detail, live
  commits/changed-files, and the worker's feed streaming terminal-style;
  `--plain`/`--once`/non-TTY keep the text frames. `clickup-stages` mirrors
  each DISPATCHED ticket's LIVE stage to ClickUp — a "Pipeline: stage N —
  <label>" subtask under the ticket's task, renamed as stages advance and
  finalized at rest states, plus stage comments; sidecar-deduped and
  state.json-untouched so it is cron-safe beside a live master.
- **Fix (eval/map):** `validate-judge.sh` rollup used an undefined variable
  (`ps` for `p`) in the non-coverage-only verdict derivation — divide-by-zero
  on that path.
- Wiring: skill symlinks on all three platforms; `/espalier-maprun` line in the
  CLAUDE.md / AGENTS.md / copilot-instructions Espalier sections;
  `pipeline.md` + map-SKILL handoff name the batch executor. Migration #26
  (`scripts/migrate-v0.18.0-to-v0.19.0.sh`) is additive + backup-on-diff.

## 0.18.0 — 2026-08-06

Minor: **the map lane** — multi-session planning above the pipeline, and a
road into greenfield. Concept adapted from Matt Pocock's `wayfinder` skill
(MIT); the enforcement layer is Espalier's. Suites: bootstrap 197/197, hooks
146/146; validation is 50/55/60 by platform set (new checks 59-60).

- **`/espalier-map` lane** (new pure-copy skill `espalier-map`) — an effort
  too big for one session (epic, greenfield build, product on a boilerplate)
  is charted as a **decision map** under `espalier/maps/{date}-{slug}/`:
  `map.md` (index, not store — Destination / Notes / Decisions-so-far /
  Not-yet-specified fog / Out-of-scope / Session log / Spawned Changes) +
  one file per ticket (`tickets/NNN-{kebab}.md`, frontmatter
  `type: grilling|prototype|research|task`, `status`, `blocked_by`,
  `claimed_by`) + `assets/`. File-per-ticket = no cross-ticket merge
  conflicts (the v0.17 file-per-key argument); claims are the lock. The
  frontier (open ∧ blockers-closed ∧ unclaimed) is grep-derivable — no
  tracker dependency. Chart mode names the destination FIRST (grilled),
  fans out breadth-first, exits with no map when no fog surfaces ("the
  split is session count, not project size"), and fires research tickets as
  parallel scouts. Work mode resolves ONE non-research ticket per session,
  graduates fog into fresh tickets, and stops. A cleared map hands off as
  `Status: FILED` change skeletons with `charted_from:` + `tickets:`
  frontmatter — adopted by the EXISTING FILED-skeleton scan, so the audit
  chain reads decision → ticket → change → commit. Completion offers (never
  auto-flips) map `CLEARED → BUILT` when every spawned change is COMPLETE.
- **`map-guard.sh`** (new hook, all three platforms) — plan-don't-do,
  machine-verified: while `espalier/maps/.active-session` exists and is
  fresher than 12h, Write/Edit outside `espalier/maps/` is blocked (exit 2 +
  stderr; same JSON extraction as post-edit-wrapper, so Claude `file_path`,
  Codex `apply_patch` bodies, and Copilot camelCase-via-adapter all guard).
  Task-ticket write windows are user-approved `allow: <prefix>` marker lines;
  absolute/traversal prefixes are ignored. Stale markers self-expire so a
  crashed session never bricks the repo. Upstream wayfinder's most-reported
  failure (production code written mid-map, Notes self-licensing) is closed
  structurally — there is no Notes execution override at all.
- **Grill `mode=decision`** — grilling tickets resolve through the existing
  grill machinery inverted for sharp questions: no signal-count tier
  (default `light`), divergent CANDIDATE ANSWERS instead of divergent
  interpretations, Step 1.5 cross-checks the candidates against `rules/` +
  `wiki/` before a decision locks, resolutions land in the ticket's
  `## Resolution` with citations.
- **`max-open-tickets: 9`** (`espalier/.espalier-config`) — the
  anti-waterfall cap: charting past it forces narrow / split / raise.
- **Greenfield decide-then-bind** (`/espalier-init`) — a near-empty repo
  takes two passes: Pass 1 `bootstrap --greenfield` installs the full
  skeleton (placeholder push gate, `espalier/.greenfield` marker; validation
  renders every Phase-2-artifact check — 5, 9, 15-16, 30-32, 34-36, 38-45 —
  as a pending-skip) and routes to `/espalier-map greenfield: <idea>`;
  Pass 2 (map CLEARED) synthesizes DISCOVERY **from the decisions** (merged
  with scouts over whatever the scaffold ticket produced — decisions win
  conflicts, scouts fill gaps) and runs the normal Phase 2 writes with
  `decided_in: maps/{slug}/tickets/NNN` citations in place of `file:line`.
  Boilerplate repos are documented as NOT greenfield: init normally, then
  map the product against the discovered conventions.
- **Wiring** — `espalier-map` joins `ESPALIER_SKILL_NAMES` (symlinked on
  claude/codex/copilot); settings.json gains the map-guard PreToolUse entry
  (additive); `.codex/config.toml` a second marker block (`ESPALIER MAP
  GUARD v1` — own markers so v0.17 installs still receive it);
  fresh copilot gates carry the entry, existing ones get a targeted json
  insert at migration. Platform instruction sections gain the
  `/espalier-map` line. Validation: checks 2/47/52 lists extended, new 59
  (map skill wired) + 60 (map-guard executable + registered).
- **`espalier-stats.sh`** (new shipped hook — lane-quality Layer 3) — a
  read-only markdown report over the audit chain, run manually
  (`bash espalier/hooks/espalier-stats.sh`): per-lane volume + terminal
  statuses, review-round/rollback distributions (min/median/mean/max),
  grill verdict mix, **charted-vs-uncharted feat cohorts** (code rounds,
  rollbacks, and the fix echo via `caused_by` back-links — the lagging
  measure of whether charting pays), per-map ticket/type/session/fog/
  spawned-state, and convention-divergence hotspots via `conv_fold`.
  Writes nothing; every section degrades to "none" on a fresh install.
- **`eval/map/` harness** (dev/QA, not shipped — lane-quality Layer 2) —
  the grill-harness pattern applied to the map lane: 8 fixtures with
  planted decisions/collisions + `answer_script` simulated users
  (chart coverage ×2, no-fog exit, cap stop, plan-don't-do probe,
  greenfield shape, work one-ticket + fog graduation, decision-mode
  collision citations), an LLM judge scored against `eval/map/rubric.md`
  (coverage / placement / typing / hard contract bar / behavior), verdicts
  derived from dimensions (never the judge's own verdict string), 0.80
  catch-rate gate with the shadow-subset discipline, and distinct
  PASS/FAIL/INCONCLUSIVE exit codes. Judge not yet human-validated — the
  runner marks every result PROVISIONAL until rubric.md's validation
  protocol has been run.
- **`scripts/migrate-v0.17.0-to-v0.18.0.sh`** (new, migration #25) — new
  files (incl. the stats hook) + per-platform symlinks + pure-copy refresh
  (backup-on-diff `<file>.pre-v0.18.bak`: pipeline.md, espalier,
  espalier-grill) + hook wiring per `espalier/.platforms` + config append +
  grep-guarded instruction lines; idempotent re-run exits "nothing to do".

## 0.17.0 — 2026-08-04

Minor: **multi-dev maintenance, Release B-team** — maintenance becomes a
scheduled singleton with two small shared files, closing G2 (doctor
diffusion) and G3 (conventions merge unsafety) structurally instead of via
event-log machinery (design §4, revision 5). Suites: bootstrap 177/177,
hooks 127/127 (all new assertions red-first, incl. two-clone git sims).

- **`espalier/.doctor-stamp`** (tracked, ONE line: `ts sha writer result`) —
  written only by the doctor, at the END of the maintenance session, as its
  own commit in the weekly maintenance PR. `doctor_due()` v2: only a fresh
  `clean` stamp satisfies team-wide; `dirty:<N>` satisfies just the writing
  clone (via its gitignored local stamp); a stamp beyond now + 25h skew is
  rejected with a warning. End-of-session rule: if the session's prune
  cleared every finding, the doctor re-runs and restamps `clean` — a dirty
  stamp whose findings were fixed in the same PR would nag the team forever.
  Last-writer-wins whole-file; deliberately never append-only and never
  union-merged. Conflict story: keep the newer line (or either `clean`).
- **Conventions file-per-key** — observations and decisions live in
  `espalier/conventions/k-<slug>.tsv` (same 5/6-col row format; the `k-`
  prefix keeps `aux`/`con`/`nul` off Windows-reserved filenames; filename is
  routing only — `conv_fold` folds by column value). `append_convention` v2
  targets the key file (created on first write) and dedupes across the key
  file AND the legacy file; status flips edit the key file IN PLACE — safe
  now, and a concurrent same-key decision surfaces as an ordinary git
  conflict in that ~5-line file, which IS the race detection. The legacy
  `.conventions.tsv` is read forever, written never. Honest costs measured
  in the two-clone sims: same-key append-vs-append AND append-vs-flip both
  conflict on current git (the plan's flip-vs-append auto-merge expectation
  was an empirical claim — measured false; its recorded §7 fallback applies)
  — playbook: keep both lines, `conv_fold` dedupes at read time.
- **Weekly gardener rota** — one rotating dev per cadence interval runs the
  ~15-minute loop (worktree of the canonical branch → doctor → prune →
  restamp-clean if everything cleared → one `docs: weekly espalier
  maintenance` PR). Stage 0 pre-flight defaults flip to **Proceed** with a
  rota pointer in BOTH lanes; "Handle now" stays the default only for your
  own critical/expired flag. A skipped week self-corrects — the stamp ages
  out and the pre-rota nagging returns.
- **Race guard v2** — reads `FETCH_HEAD:espalier/conventions/k-<slug>.tsv`
  first (single-file read via the same `conv_slug` the writer uses), legacy
  scan as the pre-conversion fallback.
- **`scripts/migrate-v0.16.0-to-v0.17.0.sh`** (new, migration #24) —
  pure-copy refresh only (backup-on-diff `<file>.pre-v0.17.bak`); no config,
  attribute, or data migration (dir + stamp appear on first write); run-time
  `git check-ignore` assert that `.doctor-stamp` is not ignored.

## 0.16.0 — 2026-08-04

Minor: **multi-dev maintenance, Release A** — the discipline, guards, and
compatibility floor that make espalier maintenance team-shaped (design:
`docs/multi-dev-maintenance-implementation-plan.md`, revision 5). Docs,
config, and one executable bash helper — no new state files; the tolerant
reader ships BEFORE the v0.17.0 per-key writer exists (readers-first).
Binding invariants hold: no hook writes a tracked file, refresh is never
silent, bash-3.2 safe. Suites: bootstrap 161/161, hooks 99/99 (all new
assertions red-first); validation is 48/53/58 by platform set.

- **`hook-templates/drift-helpers.sh`** — `conv_fold`, the single executable
  reader of convention state: folds the legacy `espalier/.conventions.tsv`
  AND every `espalier/conventions/*.tsv` per-key file (same 5/6-col row
  format; the dir arrives in v0.17.0) into `key/diverges_count/status` lines.
  Width-tolerant (malformed rows skipped, never fatal), empty-glob safe,
  read-time observation dedupe on `(slug,key,location)` across both sources,
  clock-free status precedence (a per-key decision beats a legacy one; legacy
  honored when the key file has none). `conv_observations <key>` returns the
  evidence rows for the promotion prompt. Every call site (Stage 0 scans,
  promotion, the Stage-4 key reader, check #27) now consumes the helper.
- **`scripts/bootstrap-espalier.sh`** — Stage 9 detects and appends
  `canonical-remote`/`canonical-branch` to `.espalier-config` (outside the
  quoted heredoc; append-missing-key on existing configs). Stage 10 appends
  the ONE union attribute (`espalier/.ask-gaps.tsv merge=union` — never
  `.conventions.tsv`, whose in-place status writer would make union resurrect
  edited rows) and an optional CODEOWNERS marker block
  (`--codeowners-rules`/`--codeowners-wiki`, GitHub search order,
  replace-within-markers; advisory until branch protection requires
  code-owner review). Worktree fix: the post-merge dispatcher lands via
  `git rev-parse --git-path hooks` and check #20 resolves the same way — a
  linked-worktree bootstrap now installs AND validates green. Validation
  gains unconditional base checks 57 (gitattributes-union) + 58
  (canonical-ref keys); totals 48/53/58, shipped platform IDs 47-56 stable.
- **Skill text (six insertion points)** — per-mechanism maintenance lanes
  (doctor: weekly maintenance PR; prune: weekly PR with a critical/expired
  feature-branch escape hatch; promotion: feature branch fine, own isolated
  commit + CODEOWNERS merge gate); the temporary-worktree ergonomics flow;
  the corrected promotion race guard (FETCH_HEAD, fetch-failure skip, width
  guard); unattended Stage 0 per-lane continuation (`/espalier` → Stage 1,
  `/espalier-fix` → its own Auto-Link Discovery; report-only, never
  prune/promote); prune-vs-prune conflict recipe (`checkout --theirs` +
  re-prune; modify/delete = deletion); cross-branch slug-collision recipe
  (rename + `rebuild-commit-index.sh` + Follow-up-Fixes rewrite, one
  commit); `## Maintenance Commits` section (stable
  `ESPALIER MAINTENANCE COMMITS v1` anchor) in the development-process
  template.
- **`skills/espalier-migrate/SKILL.md`** — ENFORCED Step 0 barrier: clean
  tree, no in-flight change (terminal-status vocabulary reused from
  `pre-push-gate.sh`, missing status = active, fail closed), canonical-branch
  check with explicit interactive acknowledgment; `git add -A` replaced by
  stage-exactly-reported-files. Migration #23 wired (detection, Step 4d
  CODEOWNERS question, probe bump).
- **`scripts/migrate-v0.15.0-to-v0.16.0.sh`** (new) — all-marker detection
  (hardened against `--force` partial-applies); backup-on-diff refresh
  (`<file>.pre-v0.16.bak`), surgical Maintenance-Commits append (text
  extracted from the template), `--wire-only` re-wire with the merge decision
  read back; synthetic-fixture test covers dry-run/apply/re-run/partial-apply.

## 0.15.0 — 2026-08-03

Minor: **GitHub Copilot platform support** — the wiring layer goes
three-platform. `--platforms` (and espalier-init's platform question) now
accepts any subset of `claude`, `codex`, `copilot` (shorthands `both` /
`all`); the `espalier/` tree stays the single platform-neutral source of
truth. Additive as ever: `espalier/.platforms` unions, nothing unwires,
claude-only output stays byte-stable. Suites: bootstrap 117/117 (+3-platform,
copilot-only, idempotent-re-run fixtures), hooks 86/86 (+adapter payload
matrix); validation is 46/51/56 by platform set.

- **`scripts/bootstrap-espalier.sh`** — new stages: 7c appends the
  `## Espalier` section to `.github/copilot-instructions.md` (grep-guarded;
  always-read-rules instruction + Copilot platform-mapping table:
  `@harness-*` custom agents, per-surface hook caveats); 8d writes
  `.github/agents/harness-{coder,reviewer,security}.agent.md` custom agents
  (write-if-absent; bodies point at the same `espalier/agents/*.md`); 8e
  writes `.github/hooks/espalier-gates.json` (own file — user hook files
  untouched; write-if-absent; self-heals the adapter copy on wire-only runs).
  Stage 5 symlinks the 12 skills into `.github/skills/` — the one Agent
  Skills location ALL Copilot surfaces read (VS Code, CLI, cloud coding
  agent). Validation: checks 52-56; totals 46/51/56 with codex's 47-51
  skip-rendered when only copilot forces the range, keeping numbering
  contiguous.
- **`hook-templates/copilot-hook-adapter.sh`** (new) — translates Copilot's
  camelCase hook payload (`toolName`/`toolArgs`, incl. `path`/`filePath` →
  `file_path`) into the Claude/Codex shape and dispatches to the shared
  wrappers; exit codes pass through (Copilot fails non-zero `preToolUse`
  exits closed — the exit-2 contract carries over). Without python it passes
  the raw payload through, preserving the push gate's grep fast-path and
  fail-closed probe. Missing wrapper → exit 0, never bricks a session.
- **`skills/espalier-init/SKILL.md`** — Q4 becomes multiSelect across the
  three platforms; Phase 3/Phase 4 and the "Running under Codex or Copilot"
  fallback table extended (Copilot user-scope install via `~/.copilot/skills`).
- **`skills/espalier-migrate/SKILL.md` + `scripts/migrate-v0.14.0-to-v0.15.0.sh`**
  — migration #22: always installs the adapter (one new file, no backups
  needed); `--with-copilot` (asked in the skill's Step 4c) wires copilot
  additively via `bootstrap --wire-only`.
- **Docs** — `docs/copilot-integration.md` (surfaces matrix incl. the
  VS Code-runs-no-hooks gap, adapter contract, troubleshooting),
  `docs/migrating-v0.14-to-v0.15.md`, README Copilot install section;
  `references/wiring.md` + `references/validation.md` extended.

## 0.14.0 — 2026-08-03

Minor: **Codex platform support** — the same discovered guardrails wire into
OpenAI Codex as a first-class target. `espalier-init` gains a Phase 0 platform
question (Claude Code / Codex / Both) and `bootstrap-espalier.sh` a
`--platforms=` flag; the `espalier/` tree stays platform-neutral, only wiring
differs. Additive + idempotent: `espalier/.platforms` records the set, re-runs
union (adding codex later never unwires claude), and a complete pre-v0.14
install is inferred as `claude`. Suites: bootstrap 97/97 (+3 codex tests),
hooks 73/73 (+payload matrix), validation 51 checks on codex installs while
claude-only output stays byte-stable at 46.

- **`scripts/bootstrap-espalier.sh`** — new stages: 7b appends the `## Espalier`
  section to `AGENTS.md` (grep-guarded; carries the always-read-rules
  instruction — Codex has no auto-loaded rules dir — plus the platform-mapping
  table: `AskUserQuestion` → chat, sub-agent spawn → `.codex/agents/`,
  `/espalier*` → `$espalier*`); 8b appends a marker-guarded hook block to
  `.codex/config.toml` (`PostToolUse ^(apply_patch|Edit|Write)$` →
  post-edit-wrapper, `PreToolUse ^(Bash|shell|local_shell)$` →
  pre-push-gate-wrapper — Codex shares Claude Code's hook JSON schema and
  exit-2-blocks contract, so the same wrappers serve both; backup + valid-TOML
  append); 8c writes `.codex/agents/harness-{coder,reviewer,security}.toml`
  (write-if-absent — user model tuning survives; `developer_instructions`
  point at the same `espalier/agents/*.md`). Stage 5 symlinks the 12 skills
  into `.agents/skills/` (Codex repo-skill discovery; same folder-name ==
  frontmatter-name invariant). Claude-only stages gate on the platform set;
  codex-only installs create no `.claude/` litter. `--wire-only` now reuses a
  persisted `--merge-decision` and runs `stage_mkdirs`, so "add a platform
  later" is one flag. Validation: checks 47-51 (codex wiring), dynamic totals,
  claude checks skip (or swap to `espalier/`-source equivalents) when claude
  is not targeted.
- **`hook-templates/post-edit-wrapper.sh`** — platform-neutral: uses
  `tool_input.file_path` when present, else extracts every
  `*** Add|Update File:` path from the apply_patch body (string or argv
  array); checks each file, exit 2 if any violates; repo root from
  `$CLAUDE_PROJECT_DIR` else `git rev-parse --show-toplevel`.
- **`hook-templates/pre-push-gate-wrapper.sh`** — joins argv-array commands
  before the push-pattern match (the Python-list rendering would have been
  eaten by the quote-span stripper and failed OPEN); `CLAUDE_PROJECT_DIR`
  fallback is now unset-safe.
- **`skills/espalier-init/SKILL.md`** — Phase 0 Q4 (platforms), Phase 3
  `--platforms=` flag + `${CLAUDE_SKILL_DIR}` Codex fallback, Phase 4
  codex trust steps in the completion message, and a "Running under Codex"
  fallback table so `$espalier-init` runs from inside Codex itself.
- **`skills/espalier-migrate/SKILL.md` + `scripts/migrate-v0.13.2-to-v0.14.0.sh`**
  — migration #21: always refreshes the two wrappers (backups
  `<file>.pre-v0.14.bak`); `--with-codex` (asked in the skill's Step 4b)
  wires codex additively via `bootstrap --wire-only`.
- **Docs** — `docs/codex-integration.md` (surfaces, trust model, degradations,
  troubleshooting), `docs/migrating-v0.13-to-v0.14.md`, README Codex install
  section; `references/wiring.md` + `references/validation.md` extended.

## 0.13.2 — 2026-07-23

Patch: **the readability release** — "human readable" stops being an accident
of discovered conventions and becomes an explicit duty on both agents. The
gap: the coder had no semantic-naming duty (the naming table encodes casing,
not meaning), comment conventions were never discovered, the reviewer had no
channel that could block a cryptic name, and the ladder's tie-break actively
preferred shorter over clearer. ONE new P1 class (a cryptic EXPORTED/public
name) joins the sentinel's `p1=` count; everything else lands advisory P2/P3.
Suites green: coder 4/4 (over-scope 0, over-build 0); review 9/9 (catch-rate
1.00, FP 0, verdict match 9/9) — including the new readability fixture.

- **`templates/agents/harness-coder.md`** — the Solution Selection Ladder
  tie-break becomes **clarity then brevity**: same correctness → take the
  more readable (intent-stating names, no nested cleverness — the version a
  maintainer new to the change parses without decoding); still tied → take
  the shorter. The slogan is updated everywhere it is quoted (agent
  description, ladder intro, `espalier-coding` summary, coder eval rubric).
- **`templates/rules/coding-standards.md`** — Naming Conventions gains an
  intent floor ("a name STATES what it holds or does"; public/exported names
  are contracts) and a new `## Comments & Docstrings` section. Scout 1.3 now
  extracts comment conventions — density / docstring style / what earns a
  comment — in BOTH mirror copies (`references/discovery-checklist.md`,
  shipped `templates/scout-prompts.md`) and the init skill's Phase 1 list.
- **`templates/agents/harness-reviewer.md`** — new **Readability Review**
  (advisory — P2/P3 only, one exception): `naming:` / `nesting:` / `magic:` /
  `comments:` findings, judged against the project's own conventions never
  personal taste, each Fix cell naming the concrete rewrite. **The one P1: a
  cryptic EXPORTED/public name** (exported function/class, endpoint path, DB
  column, event field, config key) — public names freeze into contracts
  callers bind to, so this is the only readability finding that blocks the
  gate; internal locals never P1. Review Process step 6 runs it beside the
  Minimalism Review; the Summary gains a `Readability:` line; the sentinel
  note counts the readability P1 like any other; Must-NOT gains the
  taste-vs-convention bullet. **`templates/skills/espalier-review.md`**
  mirrors the checklist item, panel description, and Gate-line wording.
- **Review eval** — the canned ReviewApp rules gain a citable `## Readability`
  rule; new fixture `rule-readability-07` plants an exported `proc` service
  function (works, follows every other convention, name states nothing —
  expected FAIL at P1) with false-positive guards for internal locals and
  double-counting; the rubric lists internal-local readability notes as
  canonical advisory behaviour on clean fixtures. Seed 7 → 8 (9 rows with
  both cleans). Rule text landed BEFORE the fixture so the judge's
  no-convention-invention clause cannot punish the catch.
- **`scripts/migrate-v0.13.1-to-v0.13.2.sh`** (new) — surgical, anchored,
  idempotent target-repo upgrade (requires python3 for backtick/apostrophe-
  safe exact-string splices): refreshes the ladder and the
  Minimalism+Readability spans from the plugin templates at runtime, splices
  the step-6 / Summary / sentinel / Must-NOT / Gate / checklist lines,
  inserts the naming-intent floor + `## Comments & Docstrings` before
  `## Required Patterns` (EOF fallback), and patches scout 1.3 in
  `espalier/.scout-prompts.md`. Agent-description lines and scout-prompts are
  warn-only (chain-migrated installs keep older wording; a customised file is
  reported, never mangled). Verified: fresh-v0.13.1 AND
  v0.13.0→v0.13.1→v0.13.2 chain fixtures both converge byte-identical to a
  fresh v0.13.2 install (sole benign delta: the fresh-install-only
  `{e.g., ...}` checklist illustration, per the v0.13.1 design). The new
  coding-standards sections carry `{observed ...}` placeholders until
  `/espalier-prune` re-scouts. Backs up to `<file>.pre-v0.13.2.bak`.
  `--dry-run` / `--yes` / `--plugin-dir=`.
  **`skills/espalier-migrate/SKILL.md`** gains the chain step (twentieth),
  the v0.13.2 detection block, and its plugin-location probe bumps to this
  script.

## 0.13.1 — 2026-07-17

Patch: **v0.13.0 polish round** — the three residuals the v0.13.0 quality
report named, fixed and re-verified. No gate math, sentinel vocabulary, round
cap, or review-dimension change; this sharpens what v0.13.0 already mandates.
Post-fix scores: espalier-coding 75.7 → 90.4, harness-reviewer 91.0 → 96.0,
espalier-review 88.1 → 93.8; suites green (coder 4/4, over-scope 0, over-build
0; review 8/8, catch-rate 1.00, FP 0, verdict match 8/8).

- **`templates/skills/espalier-coding.md`** — new `## How This Skill Applies
  by Stage` section delivering the stage-conditional guidance the frontmatter
  always promised: Stage 3 (the whole skill applies), Stage 5 testing mode
  (layer specs govern where tests live; the ladder applies to test code —
  reuse the project's test helpers/fixtures first, and a test-only dependency
  is still a NEW dependency needing its `requirements.md` line; the abuse-test
  and failure-mode recipes stay canonical in `harness-coder.md` /
  `espalier-security`), and fix rounds (findings-only scope, smallest
  convention-compliant change, never "improve" adjacent code the finding
  didn't name). The Implementation Checklist placeholder gains an
  `{e.g., ...}` illustration for the init scout (fresh-install only — an
  existing install's checklist is already scout-filled).
- **`templates/agents/harness-reviewer.md`** — the Stage 6 Security Abuse-Test
  Coverage duty (a section since v0.9.0) is now numbered Review Process step 7,
  explicitly conditional ("Test-review rounds only … Skip this step on
  code-review rounds"); "Produce findings" renumbers to step 8. The duty
  itself is unchanged.
- **`templates/skills/espalier-review.md`** — the code-review loop gains the
  Gate line its plan-review loop got in v0.13.0: verdict
  `PASS`/`PASS_WITH_FIXES` with `p0=0 p1=0` on the sentinel, P2/P3 (minimalism
  advisories included) never blocking, round counting and escalation owned by
  pipeline Stage 4 (`max-code-rounds`).
- **`scripts/migrate-v0.13.0-to-v0.13.1.sh`** (new) — surgical, anchored,
  idempotent target-repo upgrade: inserts the By-Stage section (extracted from
  the plugin template at runtime, placeholder-free), splices abuse-test step 7
  + the renumber, inserts the code-review Gate line. Anchors verified on both
  fresh v0.13.0 installs and installs migrated from v0.12.0. Skips the
  `{e.g., ...}` checklist illustration by design (scout authoring hint —
  nothing to illustrate in an already-filled install). Backs up to
  `<file>.pre-v0.13.1.bak`. `--dry-run` / `--yes` / `--plugin-dir=`.
  **`skills/espalier-migrate/SKILL.md`** gains the chain step (nineteenth) and
  its plugin-location probe bumps to this script.
- Docs: `docs/quality-report-v0.13.0.md` residuals annotated as fixed, with
  the new scorer-surfaced follow-ups recorded; score history in
  `eval/{coder,review}/auto-optimize-results.tsv`.

## 0.13.0 — 2026-07-17

Minor: **the coder gets a laziness ladder; the reviewer gets an advisory
minimalism lens.** Idea adapted from
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) —
an idea-level borrow, re-grounded in Espalier's convention-first model. The
governing rule everywhere: **conventions first, correctness within them,
brevity only breaks ties.** "Short is always best" is explicitly NOT the rule
— a construct the project's rules or layer specs mandate is never over-build,
even when a shorter form exists. MINOR because the generated `harness-coder`
and `harness-reviewer` agent files change shape.

**Solution Selection Ladder (`harness-coder`, `espalier-coding`).** Before
choosing a change's shape, the coder climbs: (1) speculative extra → don't
build it; (2) the project already has it (reference files, `espalier/wiki/`)
→ reuse; (3) a convention names the mechanism → use THAT, even when stdlib
would be shorter; (4) conventions silent → stdlib, then native platform
feature, then already-installed dependency — never a NEW dependency without a
`requirements.md` line naming it; (5) only then the leanest
convention-compliant implementation that is correct on the edge cases. The
ladder runs after understanding (specs, references, blast radius), never
instead of it; trust-boundary validation, the project error pattern, and the
security/production rules are the floor, not rungs. Deliberate
simplifications land in coding-report.md "Notes" so the reviewer confirms
them instead of re-deriving them.

**Minimalism Review (`harness-reviewer`, `espalier-review`).** A new advisory
dimension: `delete:` / `stdlib:` / `native:` / `yagni:` findings, each
required to name its concrete replacement, capped at **P2/P3** so they can
never re-open the Stage 4 fixpoint loop or touch the sentinel's `p0=`/`p1=`.
ONE exception may block at P1: a NEW dependency covering what stdlib, a
native feature, or an installed dependency provides — the objectively
checkable mirror image of the existing "hand-rolls what the discovered
wrapper covers" P1. Tie-break: a finding is invalid against a
rules/specs-mandated construct; "the convention itself is over-built" routes
to a Convention Observation (the human promotion path), never a finding. No
finding quota — "Minimalism: lean" is the expected common case. Gate math,
sentinel vocabulary, round caps, and panel structure are untouched.

**Eval hardening.** Coder eval gains an `overbuild` judge field (built the
in-scope task too big: new dependency, hand-rolled stdlib, single-impl
abstraction, unrequested config) with a `== 0` release gate alongside
`overscope`, plus the `coder-04-overbuild-trap` fixture (the classic
date-formatting trap: `toISOString().slice(0, 10)` vs a date library or a
formatter class). Review eval gains `clean-02-minimal-guard` (lean,
convention-mandated code — any minimalism P0/P1 is a false positive, guarding
severity inflation) and `rule-newdep-06` (a planted `dayjs` import for a
stdlib-covered format — the one minimalism finding that must gate at P1).
Separately, a baseline attribution run (v0.12 templates + fixtures under the
current default model) showed the review suite was already failing — a
stronger reviewer surfaces genuine defects the fixtures accidentally carried.
Fixed at source (elided `AppError` imports in `rule-throw-01`/`rule-timeout-04`,
a genuinely-defective "clean" fixture body, over-broad watch lines that
shadowed real findings) plus a rubric class-rule: harness-world findings
(missing sibling modules, absent requirements.md) are genuine, never false
positives. Logged as eval-integrity in `auto-optimize-results.tsv` — NOT a
skill win.

**Quality gate (darwin rubric).** All four touched artifacts scored by
independent reviewer agents (8 dimensions, structure + measured effect from
the real harness runs), every scorer finding fixed, suites re-run green after
each fix: `harness-reviewer` 87.9 → **91.0** (adds the `p1=` row-count
binding; restores the fan-out P1 bullet that had drifted from
production-standards.md), `harness-coder` 83.2 → **88.6**, `espalier-review`
82.4 → **88.1** (plan-review loop gains an explicit pass condition),
`espalier-coding` 75.7 (frontmatter 6→9; Before-Writing steps de-duplicated
into a pointer at the canonical coder sequence). Average **82.3 → 85.9**.
Full report: `docs/quality-report-v0.13.0.md`.

**Migration.** `scripts/migrate-v0.12.0-to-v0.13.0.sh` — surgical anchored
inserts into the four per-project files (never a template overwrite; section
bodies extracted from the installed plugin's templates at runtime so script
and templates cannot drift), idempotent, backups at `<file>.pre-v0.13.bak`.
`/espalier-migrate` chain extended (18 steps). Fresh-install-only cosmetic
delta: the richer frontmatter descriptions. See
`docs/migrating-v0.12-to-v0.13.md`.

## 0.12.0 — 2026-07-13

Minor: **Stage 1 now cross-references your own conventions.** Grill gains a
blind-spot pass (Step 1.5) that reads `espalier/rules/` + `espalier/wiki/` and
turns a convention collision into a Stage 1 question before any code is written.
MINOR rather than PATCH because the generated grill skill changes shape (a new
process step, a new `## Convention Notes` block in `requirements.md`).

**Grill blind-spot pass (the feature).** After scoring the requirement's text
signals and before the question loop, grill cross-references the requirement
against the project map and looks for three collision classes: a **rule
collision** (the approach contradicts a `rules/` convention — `throw` where
coding-standards mandates `Result<T>`), a **wiki duplication** (re-implementing a
capability `wiki/` documents — a new HTTP client for an API `external-services.md`
already wraps), and an **unstated ripple** (a new field on a model
`critical-paths.md` shows feeding several consumers). Each **confirmed** collision
becomes a Stage 1 question citing the exact `rules/<file>#section`, and floors the
tier so a crisp-but-colliding requirement can't skip grilling. Before raising a
collision grill **verifies the cited convention still holds in the code** — a
stale doc is flagged via `mark_stale` (the same signal `/espalier-doctor` and the
post-merge hook use), never raised as a false collision. It surfaces collisions
with existing conventions only (never brainstorms new designs) and stays **silent
when there is no map to collide with**, so behaviour is unchanged on an
uninitialised input — zero regression by construction. Resolutions are written
back to `requirements.md` (Acceptance Criteria / Scope-out / Open Questions) plus a
`## Convention Notes` audit block. `SKIPPED: crisp` now additionally requires zero
collisions. Reads of `rules/`/`wiki/` do not count against grill's ≤ 8 code-read
budget; code-verification of a candidate collision does.

**Grill eval harness hardening.** All four `eval/grill/KNOWN-ISSUES.md` defects
fixed: (1) `run.sh` retries `claude -p` and reports a call that still can't
execute as a distinct **INCONCLUSIVE** exit (3), never folded into the scoring
gate — an infra hiccup no longer reads as a regression; (2) fenced/prose-wrapped
judge JSON now parses (`json_extract` keeps the first `{`…last `}`); (3) the
mis-tiered `shadow-light-04` (4 signals at a 3-question cap) merged its two
format-related signals into one, so it is satisfiable at `light`; (4) three
announced-gap fixtures (`full-01` already, `full-03` + `light-02` new) carry
`coverage_only: true`, so the non-obviousness bar they could never clear no longer
fails them. New rubric dimension 6 (collision coverage + false-collision penalty);
collisions fold into the existing `planted`/`surfaced` counts, so the harness math
is unchanged. Four new fixtures: three `collision-*` and one anti-stale (which
stays `skip` — a wrongly-raised collision floors the tier off `skip` and fails
depth-calibration, so the false positive is caught by the existing gate). Full
golden-set run: **24/24 PASS, catch-rate 1.00 all / 1.00 shadow** (was 0.98 /
0.97), `RESULT` FAIL→PASS.

**Honest caveat.** The `collision-*` fixtures inline their mock `rules/`/`wiki/`
context, which **under-measures** the real gain: a capable model reasons over any
context handed to it, so an A/B that pre-supplies the map erases the difference
Step 1.5 makes. The fixtures are a capability + regression check, not a clean
causal isolation; a faithful A/B needs an on-disk `espalier/` fixture project and
is deferred (`docs/grill-blindspot-crosscheck-plan.md` §5.1).

**Migration.** New `scripts/migrate-v0.11.0-to-v0.12.0.sh` — the change is confined
to one pure-copy file, so it backs up and refreshes
`espalier/skills/espalier-grill/SKILL.md` from the v0.12.0 template
(`.pre-v0.12.bak`), verifies Step 1.5 landed, and no-ops on re-run. It refuses a
stale plugin whose grill template lacks Step 1.5. No `python3` needed. Wired into
`/espalier-migrate` (detection keyed on Step 1.5 absence; the seventeenth step in
the chain). See `docs/migrating-v0.11-to-v0.12.md`.

## 0.11.0 — 2026-07-10

Minor: **the push gate now actually blocks** — Claude Code hooks block on exit 2,
not exit 1; every gate script and wrapper is updated, and the verdict gate reads
the verdict word, closing the FAIL-with-p1-only and ESCALATION_REQUIRED-as-PASS
holes. MINOR rather than PATCH because generated files change shape (gate exit
codes, wrapper, agent frontmatter).

**Hook exit-code contract (Workstream A).** For PreToolUse/PostToolUse hooks,
ONLY exit code 2 blocks, and the message must be on **stderr** — exit 1 + stdout
is a silent no-op. All 10 blocking paths in `pre-push-gate.sh` now exit 2 with
the reason on stderr (warnings too, exit 0 unchanged); the three
`check-layer-boundaries-*.sh` templates follow the same PostToolUse contract.
The gate no longer early-exits when no pipeline change is in flight — the secret
scan and dependency audit run on EVERY push (pipeline-only gates are wrapped in
`gate_*_section` functions behind a `PIPELINE_TRACKED` guard, preserving the
migration span markers). A corrupt state file (no parsable `Current Stage:`, or
a Stage-4 PASSED row with a missing review certificate) fails closed.
`pre-push-gate-wrapper.sh` fails CLOSED when python is absent, matches
`git -C … push` / multi-line / after-`&&` pushes, ignores quoted mentions, and
documents `ESPALIER_SKIP_GATE=1`. `test-hooks.sh` asserts exit codes exactly
(2 for blocked, 0 for allowed, BLOCKED on stderr) plus a 6-case wrapper matrix,
secret-scan, corrupt-state, and multi-line-build cases.

**Verdict-word gates (Workstreams B/C).** One canonical gate paragraph at every
Stage 4/6 gate site in both lanes: `ESCALATION_REQUIRED` (either agent, either
lane, any stage) runs the escalation protocol; verdict `FAIL` or `p0>0` or
`p1>0` re-spawns the coder; advance ONLY on PASS/PASS_WITH_FIXES with p0=0 AND
p1=0. The cap check runs BEFORE re-spawning. Escalations now write
`- Status: ESCALATED` / `ESCALATED_LATE`; PARTIAL_FIX root-cause skeletons are
created AFTER the Stage 7 push with `- Status: FILED` (adopted later, never
gating pushes). Resume is status-driven, not stage-numbered. The reviewer and
security agents get a Write tool restricted to their own record file; the
security no-op example ends with the mandatory sentinel; P1 severity text,
kebab truncation (80 in both lanes), stage-count prose ("7 stages (0–7, no
Stage 2)"), and the merge-decision prompt (now an orchestrator
`AskUserQuestion`) are aligned.

**Init/bootstrap (Workstream D).** `.claude/` symlinks are RELATIVE
(`../../espalier/…`) so a moved repo keeps resolving; Stage 5 prints
`WIRED: skills=<n> rules=<n> agents=<n>`. The language vocabulary is
`typescript|python|go|unsupported` end-to-end, and `--lang=unsupported` writes a
no-op boundary hook (write-if-absent). Stage 11 grows to **46 checks** (Phase-2
skills, wiki pages, development-process rule, boundary hook); `validation.md`
mirrors it 1:1. Phase 0/3 instructions substitute literal values — no dead
shell-variable state between Bash calls.

**Migration chain repair (Workstream E).** New
`scripts/migrate-v0.10.0-to-v0.11.0.sh` rebuilds the gate from the v0.11
template preserving the substituted command bodies, refreshes wrappers +
pipeline + pure-copy skills (`.pre-v0.11.bak` backups), patches the boundary
hook and agent tools lines, and re-substitutes `{project}` in
espalier-review/security. Customised gates get an `espalier/.migrations-skipped`
marker (reported once, never re-proposed). The v0.3→v0.4 sed no longer corrupts
`harness-reviewer`; the five older scripts exit 1 on failed verification; the
v0.1→v0.2 apply line carries `--plugin-dir` and the script probes its own
checkout first. Chain regression verified: a pre-v0.9.2 install reaches exact
v0.11.0 template parity.

**Docs.** README/index.html refreshed; new `docs/migrating-v0.10-to-v0.11.md`.

## 0.10.0 — 2026-07-09

Minor: **the push gate can run more than one command per check, and says why it blocked.**
MINOR rather than PATCH because the generated `espalier/hooks/pre-push-gate.sh` changes
shape. No pipeline stage, lane, gate semantic, or verdict changes.

**`{build_command}` / `{lint_command}` / `{test_command}` are now function bodies.**

The old template substituted the test command into a command substitution:

```sh
TEST_OUTPUT=$({test_command} 2>&1)
```

so the value had to be a single expression. A repo that must run several suites — one
per container in a Docker-first stack, one per workspace in a monorepo — could not be
expressed at all; init had to hand-write a bespoke gate, which then fell out of the
migration chain (every later script's anchors missed it). Now:

```sh
run_tests() {
  {test_command}
}
TEST_OUTPUT=$(run_tests 2>&1)
```

The substituted value may be a single command OR a multi-line block. A block MUST
return non-zero if ANY step fails: join steps with `&&`, or end each with `|| return 1`.
`run_build` and `run_lint` work the same way.

`run_tests` is defined **inside** the `# Run tests and check count` … `echo "All gates
passed` span on purpose: `migrate-v0.9.1-to-v0.9.2.sh` re-splices exactly that span, so
the definition must travel with its caller or a patched gate would call an undefined
function.

**Build and lint stop discarding stderr.**

The old template ran `{build_command} 2>/dev/null` and, on failure, printed
`BLOCKED: Build fails` and nothing else — a gate that blocks without saying why gets
disabled. Output is now captured and its tail printed on failure.

**New: `scripts/migrate-v0.9.6-to-v0.10.0.sh`.**

Rewrites the three spans of an installed gate, preserving the commands substituted at
init. Three behaviours worth naming:

- **Each span is independent.** A gate can be half-migrated: running the v0.9.2 step
  against a v0.10.0 plugin re-splices only the test span, leaving `run_tests` with old
  build/lint. The idempotency guard therefore requires all three functions, and a span
  already function-shaped is skipped rather than re-read.
- **The test command is never read back from `TEST_OUTPUT=$(run_tests 2>&1)`** — that
  yields the function name, not the command.
- **A customised gate is left completely untouched**, reported with the manual change
  list, exit 0. Never mangled.

Verified: a migrated gate is byte-identical to a fresh v0.10.0 init with the same
commands. Idempotent.

**Fixed: `migrate-v0.9.1-to-v0.9.2.sh` mislabelled a customised gate as a failure.**

Its `gate kept its substituted test command` check asserted `^TEST_OUTPUT=`, which a
gate customised at init can never satisfy — so a correct migration reported `✗`. The
hard check is now the real invariant (no `{test_command}` placeholder survived); the
template-shape assertion is warn-only.

**Also:**

- `NEEDS_V0100_PATCH` joins the chain; the plugin-locate probe moves to the newest
  script; `espalier-init`'s SKILL documents the multi-line block form.

`scripts/test-hooks.sh` 28/28, `scripts/test-bootstrap.sh` 60/60. Gate behaviour
re-tested end to end in a real repo: build failure prints its output and blocks;
a multi-suite block whose *second* suite fails blocks; zero tests blocks; unparseable
runner output warns and allows; the no-test-command stub still fails closed.

## 0.9.6 — 2026-07-09

Patch: **the v0.9.4 migration that was never written**, plus a stale skill description
shipped in 0.9.5. Same bug class as 0.9.5: an improvement lands in the init templates,
and nothing carries it to installs that already exist.

**New: `scripts/migrate-v0.9.3-to-v0.9.4.sh`.**

v0.9.4 sharpened two **per-project** files — the `harness-security` agent and the
`espalier-security` skill — but shipped no migration script. Both are created at init
(or by `migrate-v0.8.2-to-v0.9.0.sh`) with `{project}` substituted, so `bootstrap --force`
never re-copies them and a plugin update cannot reach them. No existing install ever
received those improvements.

The new script surgically re-splices exactly the changed regions:

- the `description:` frontmatter line of each file, taken from the v0.9.4 template, with
  this project's name substituted into the skill's;
- the agent's `## Priority Rubric` P0 bullet and its Repo-Audit Mode "findings do not
  block" delta, which now cross-reference one source instead of restating each other.

Two things it deliberately does **not** do:

- **It never rewrites frontmatter wholesale.** An install created in `inherit` tools-mode
  has had its `tools:` line stripped; copying the template's frontmatter would silently
  reintroduce it. Only the `description:` line is replaced, and verification asserts the
  install's original tools-mode survived.
- **A customised body span is left alone and reported warn-only**, not `✗`. The v0.9.4
  wording is a clarity improvement, not a behaviour change, so a project that rewrote a
  span keeps its version and the script still exits 0 after applying every span it could
  match. (A hard failure there would tell the user to restore from backup after a skip the
  script chose on purpose.)

Verified against a real migrated install: the patched agent is **byte-identical to what a
fresh v0.9.4 init produces**, once `{project_name}` is substituted and `tools:` stripped
for inherit mode. Idempotent; re-running detects both v0.9.4 markers and no-ops.

**Fixed: `espalier-migrate`'s frontmatter description was stale.**

0.9.5 wired the v0.9.3 step into the skill's *body* — detection, dry-run, apply, prose,
flags — but left the `description:` line enumerating migrations only through "the v0.9.2
correctness patch". That line is what Claude reads to decide whether to invoke the skill.
It now lists v0.9.3 and v0.9.4, and "Up to TWELVE migrations" reads FOURTEEN.

**Also:**

- `NEEDS_V094_PATCH` joins the chain, detecting on the same two markers the new script uses
  for its own idempotency check (agent `self-noops on changes with no sensitive surface`,
  skill `abuse-test recipe for`). An install with neither security file yet is flagged too —
  the v0.9.0 step creates them, then v0.9.4 sharpens them.
- The plugin-locate probe moves to the newest migration script (`migrate-v0.9.3-to-v0.9.4.sh`),
  so a plugin predating the current chain fails to resolve with "update the plugin" rather
  than dying mid-apply.

`scripts/test-bootstrap.sh` 60/60. All four bash blocks in `SKILL.md` pass `bash -n`.

## 0.9.5 — 2026-07-09

Patch: **migration-chain repair** — two bugs made the documented upgrade path fail for
installs that reached v0.9.x by migrating rather than by a fresh `/espalier-init`. No
new lane, stage, gate, or verdict behaviour; no change to what a fresh init produces.

**`/espalier-migrate` could not reach v0.9.3.**

- `scripts/migrate-v0.9.2-to-v0.9.3.sh` shipped in 0.9.3, but `skills/espalier-migrate/SKILL.md`
  never referenced it — no `NEEDS_` flag, no detection, no dry-run line, no apply line.
  Followed literally, the skill stopped at v0.9.2 and reported "Already fully up to date",
  leaving the v0.9.3 grill + review changes unreachable for every install.
- Adds `NEEDS_V093_PATCH`, detecting on the same two markers the script uses for its own
  idempotency check (grill `Coverage guard (before returning`, review
  `SINGLE SOURCE for these checks`), plus the dry-run, apply, chain prose, and flags entry.

**`migrate-v0.8.2-to-v0.9.0.sh` never wrote to the review skill.**

- It declared `REVIEWSKILL="espalier/skills/espalier-review/SKILL.md"` and never referenced
  the variable again, so the `espalier-review` SKILL never received its
  `## Production-Readiness Checks` section. Fresh v0.9.0+ inits get the section from
  `templates/skills/espalier-review.md`; migrated installs did not — and
  `migrate-v0.9.2-to-v0.9.3.sh` requires it, dying with
  `ERROR: install missing section '## Production-Readiness Checks'`.
- The section is now appended via the existing `append_section` helper, guarded on the bare
  heading so both the v0.9.0 form (with the rules-path suffix) and the v0.9.3 form count as
  already-present.
- The section text is **inlined rather than extracted from the template**. On a v0.9.3+
  plugin the template section carries the phrase `SINGLE SOURCE for these checks`, which is
  exactly the marker `migrate-v0.9.2-to-v0.9.3.sh` greps to decide the review skill is
  already patched. Extracting it would have made v0.9.3 report "already at v0.9.3 — nothing
  to do" and silently skip its own frontmatter + Two-Review-Loops splice — a passing no-op.
- The section joins the already-v0.9.0 detector (ten artifacts → eleven) and the verification
  block, so an install migrated by an earlier build is completed on re-run rather than
  short-circuiting. The `/espalier-migrate` v0.9.0 detection flags a missing section too, so
  the chain self-repairs before v0.9.3 needs it.

**Also:**

- The plugin-locate probe in `espalier-migrate` now looks for the newest migration script
  (`migrate-v0.9.2-to-v0.9.3.sh`) instead of `migrate-v0.7-to-v0.8.sh`. A plugin predating the
  current chain now fails to resolve with a clear "update the plugin" message rather than
  resolving and dying mid-apply on a missing script.
- Documents that a dry-run preview of a later step may legitimately refuse until its
  prerequisite step has been applied (e.g. the v0.9.2 preview needs the `pipeline.md` that
  v0.9.1 rewrites) — the refusal is a precondition guard, not a failure.
- Notes that the v0.9.2 gate check `^TEST_OUTPUT=` assumes the single-host-command shape
  `hook-templates/pre-push-gate.sh` generates; a gate customised at init to run tests another
  way (e.g. per-container `docker compose exec`) cannot satisfy it, warns, and reports that one
  check as `✗`. Template-shape mismatch, not a failed migration.
- **Version fields corrected.** `plugin.json` and `marketplace.json` still declared `0.9.3`
  after the v0.9.4 release, which bumped only `CHANGELOG.md`. All three fields now read `0.9.5`.

Validated against a synthetic v0.9.2 install: the original `install missing section` error
reproduced, then cleared, with the project-substituted checklist lines preserved and no literal
`{project}` leaked; re-run is a clean no-op. `scripts/test-bootstrap.sh` 60/60.

## 0.9.4 — 2026-07-08

Patch: **security eval expansion + skill clarity** — dev/QA infra plus sharper skill
instructions. No new lane, stage, gate, or verdict behaviour; the security auditor's
catch / false-positive behaviour is unchanged (eval gate 1.00 catch-rate / 0 false
positives both before and after).

**Security eval harness (dev/QA, not shipped to target projects):**

- **Seed suite expanded 9 → 20 fixtures.** New coverage: an identity-spoof (actor from
  the request body), a stock/balance **P1** race (the first non-P0 gradient case),
  owner×state cross-axis IDOR (a *legal* transition on another actor's object),
  unbounded-refund money tampering, two shadow (author-blind) vulns (a partial
  allow-list that mass-assigns `verified`/`plan`, and a header-derived role), three
  clean false-positive traps (control one hop away in a helper, a pure-calc refactor,
  and an ownership check *moved but kept*), and two more repo-audit fixtures (mixed
  P0+P1 with section routing, and all-controlled queue consumers). All five risk axes
  are now covered; 4 fixtures are `shadow: true` (~20%).
- **Added `judge-validation/`.** A 6-fixture hand-score vs the LLM judge agrees on
  24/24 cells (100%), above the 75% bar — including the drift-prone case where a record
  emits more findings than planted (the judge correctly collapses to caught==planted
  with zero false positives). Records for the validated subset are checked in as an
  audit trail.
- **`run.sh` gains an env-gated `KEEP_WORK` mode** that preserves auditor records for
  judge-validation and debugging. Default behaviour is unchanged.

**Shipped skills (clarity only, effect-neutral):**

- **`harness-security` (agent) + `espalier-security` (skill) — frontmatter gains
  when-to-use + trigger context.** Each description now names *when* it runs (Stage 4
  panel / `/espalier-audit`) and the five sensitive axes (money / identity / permission
  / ownership / state) reaching an auth or persistence sink, so skill/agent matching
  keys off the surface it guards, not just the name.
- **`harness-security` — mode redundancy deduped.** The P0 / no-manufacture semantics
  that were restated across pipeline and repo-audit modes collapse to one source plus a
  cross-reference. The output-format tables, the abuse-test contract block, every
  section heading, and the `VERDICT:` sentinel are untouched; the security eval scores
  identically before and after (catch-rate 1.00, zero false positives, all 20 verdicts
  match).

**Ask eval:** three adversarial `sourced` fixtures (multi-file flow, multi-value
enumerate, mixed doc/code provenance) that stress per-claim citation; the ask skill
holds at 2/2 on all Gate-2 dimensions.

**Existing users:** no migration. This release changes dev-only eval harnesses and
skill-template wording — target-project installs pick up the sharper `harness-security`
/ `espalier-security` descriptions on the next `/espalier-init` or `/espalier-prune`;
no behaviour change requires action.

## 0.9.3 — 2026-07-07

Patch: **skill-clarity + eval calibration** — no new lane, no new stage, no gate or
verdict behaviour change. Two shipped skills get sharper instructions; the eval
harnesses that guard them get a recalibrated judge and a fixture-integrity fix.

**Shipped skills:**

- **`espalier-grill` (pure-copy) — three loop guarantees made explicit.** (1) *User
  tier-override:* if the user pushes back on the chosen tier ("this is more involved" /
  "don't bother grilling"), grill now adopts their read — their sense of the
  requirement's stakes overrides the raw signal count. (2) *Coverage guard:* every
  ambiguity signal counted in Step 1 must end resolved, scoped-out, or recorded under
  `## Open Questions`; stop-early now applies only to questions *beyond* the counted
  signals, so the exact ambiguity grill exists to catch can no longer be skipped. (3)
  *Non-answer handling:* an "I don't know" is recorded with a named safe default
  instead of being silently dropped.
- **`espalier-review` (substituted) — same checks, clearer instructions.** The two
  review loops become an explicit when / input / do / output / who workflow. The
  production-readiness checklist stops restating severities (P0/P1) — `production-
  standards.md` is named the single source, removing a second copy that could drift.
  The frontmatter gains when-to-use + trigger phrases. Effect is unchanged: the review
  eval harness scores identically before and after (catch-rate 1.00, zero false
  positives).

**Eval harness (dev/QA infra — not shipped):**

- **Grill judge recalibrated.** The `non_obvious` rubric anchors were sharpened
  (a standard scoping ask = 1; a question that overturns a likely-wrong default = 2;
  filler = 0) after the judge was found to inflate the dimension by ~0.3. The
  judge-validation agreement tolerance tightened ±0.5 → ±0.3 so that drift surfaces
  instead of hiding inside the band. Hand-scores were cross-checked against a second
  model and reconciled; judge-validation now agrees 24/24.
- **Review eval fixture-integrity fix.** The `clean-01` fixture used `new AppError()`
  with no import, so a literal read was a `ReferenceError` — the reviewer correctly
  flagged the undefined symbol and it was miscounted as a false positive. Added the
  import (it is the project-standard error type); the reviewer was not changed. Also
  adds the review eval's shadow discipline notes and a darwin optimization ledger.

**Existing installs:** run `bash scripts/migrate-v0.9.2-to-v0.9.3.sh` from the target
repo root (`--dry-run` to preview). It refreshes the pure-copy `espalier-grill` and
surgically re-splices the three changed sections of the substituted `espalier-review`
in place — preserving your project's substituted name and discovered conventions.
Idempotent; backs up both skills to `*.pre-v0.9.3.bak`.

## 0.9.2 — 2026-07-04

Patch: **correctness sweep** — a full-repo audit surfaced a cluster of defects concentrated in bash embedded in skill markdown (code no interpreter had ever run end-to-end) plus gate/doc inconsistencies. All fixed, each proven by a red-first regression test or a sandbox reproduction. No new lane, no new stage; non-breaking.

**Fix lane (`espalier-fix.md` — pure-copy):**

- **Late-escalation gates called a phantom helper.** The Stage 5/6 checks invoked `_fire_late_escalation_prompt`, a function defined nowhere — executed literally, bash errors and the human gate never fires. The bash blocks now only DETECT (grep → print a `LATE_ESCALATION_GATE:` marker); the prompt is an `AskUserQuestion` the orchestrator runs, per the existing Late-Escalation section.
- **Back-link `Reason` was always `---`.** Stage 7.2 read `head -1` of a frontmatter'd requirements.md; it now greps the `# Bug:` title. Its two bare `continue` statements — invalid outside a loop in the per-entry standalone execution the section specifies — became `exit 0`, so the missing-state and idempotency guards actually guard.
- **Regression verification could certify a test that never ran.** The old check ran the WHOLE suite at `Base-Ref` in a bare worktree: with no installed deps (node_modules/.venv) the run fails environmentally and ANY test — tautological included — earned `REGRESSION_VERIFIED: true`. Redesigned two-step and scoped: the invocation (limited to the new regression test files) must pass on the FIXED tree first, then re-runs at `Base-Ref` with installed dep dirs linked in; a harness error classifies `skipped` (reviewer reads the assertions), never `true`. Verdict tokens `{true|false|skipped}` unchanged, so the Stage 6 contract holds. Sandbox-verified across five scenarios including the original dep-missing false positive.

**Gates:**

- **Push gate gates the ACTIVE change.** Selection was newest-mtime regardless of Status, so (a) after any completed pipeline change, every later manual push was blocked forever by its stale `Reviewed-Diff` (the fingerprint can never match again), and (b) a newer finished change could shadow the in-flight one. The gate now picks the newest NON-terminal change (missing `- Status:` = legacy in-flight; `PARTIAL_FIX` stays gate-eligible — it is written before its own Stage 7 push); no in-flight change → warn + allow; several → gate the newest and name the rest.
- **Push gate test-count parse was jest-shaped.** `'N passed|N tests'` false-BLOCKED passing suites under mocha (`N passing`), rspec (`N examples`), and go (per-package `ok` lines). Patterns broadened + a go `ok`-line fallback; an unparseable format on exit 0 downgrades to a warning (exit code stays the gate); an explicit `0` still blocks.
- **`/espalier-audit` + `/espalier-prune` missed the v0.9.0 TTY sweep.** The audit's per-finding `/espalier-fix` dispatch was gated on "session has a TTY" and prune's `--all-stale` on `detect_run_mode` — both always read non-interactive inside Claude Code, silently skipping the handoff / demoting every attended prune to report-only. Both now use `interactivity_mode`; `detect_run_mode` stays in drift-helpers for old installs, marked deprecated with no callers.

**Orchestrator (`espalier.md` — pure-copy):** Session Resumption said "any in-progress state file → resume it", conflicting with Before-Starting's matching rule — a new requirement could hijack a parked change. Resumption now matches on the slug's kebab tail (the fix lane's collision rule); unrelated in-flight changes are surfaced in one line; a bare `/espalier` with several in flight asks which. The `fix:`-prefix semantics are stated (full pipeline = large fixes; typical bug → suggest `/espalier-fix`), matching the reworded README routing row.

**Hooks:**

- **One fuzzy squash matcher.** `post-merge-backlink.sh` still ran the pre-v0.9.0 naive overlap loop (word-splitting, substring match where `a.ts` ⊆ `a.tsx`). The heuristic now lives once in `lookup-helpers.sh` as `_fuzzy_scan` (sets `FUZZY_SLUG/BEST_STATE/BEST_COUNT/TOTAL`, optional max-age window); `_fuzzy_file_overlap_match` remains the fix-lane stdout wrapper and the backlink hook sources the shared core with its 30-day window.
- **Every ERE metachar escaped.** The matcher's escape class missed `()+?{}|`, so `app/(dashboard)/page.tsx` compiled as a regex group and could never match itself — Next.js route-group files were fuzzy-invisible.
- **`rebuild-commit-index.sh` section leak.** The `/^## [^CS]/` reset let headings starting with C/S (`## Checks`, `## Stage History`) keep the previous section's flag alive and index non-commit rows. Any heading now closes both sections.
- **drift-detect maps `pyproject.toml` to external-services** too (it is the modern Python dep manifest, not only a lint-config carrier).

**Discovery + init:**

- **`ci_checks` gains the null convention `deploy` already had** (checklist + shipped scout-prompts copy): a repo with no lint/build/test command gets `null`, never an invented command that blocks every push. Phase 2 substitutes `true  # none discovered` for a null build/lint and a fail-closed actionable stub for a null test; the gate template documents it.
- **Scout 1.11 ships in `.scout-prompts.md`** and prune/doctor's Scout Mapping tables gain `security-standards.md` (1.11) and `production-standards.md` (1.3 + 1.10 + 1.8) rows with an explicit fixed-vs-discovered note — closing the dead-end where ask/audit/migration pointed users at prune/doctor for files those skills couldn't refresh.
- **Bootstrap check #2 validates all 12 skill symlinks** (was missing `espalier-prune` + `espalier-doctor`). Still 37 checks.

**Tests (dev/QA):** new `scripts/test-hooks.sh` — 28 assertions over the mechanical hook layer (fuzzy matcher incl. metachar paths + age window, dedupe, cache idempotency, backlink link/no-link, index section routing, 10 push-gate cases incl. four no-degradation guards, drift-helpers, and a phantom-helper lint that fails if any skill template calls an `_helper` no hook template defines — the class behind the phantom above). Written red-first: 12 failed on v0.9.1, all 28 green now. `test-bootstrap.sh` stays 60/60.

**Maintenance:** `migrate-v0.8.2-to-v0.9.0.sh` now EXTRACTS the security sections + gate scan block from the templates at run time (byte-identical output verified) instead of duplicating ~180 lines — the same no-drift pattern its production emitters already used. Machine-specific personal dev-path fallbacks removed from 8 scripts + the migrate skill (the documented `~/repos/espalier-engineering` dev-checkout location remains the only local fallback). Doc-drift sweep: `validation.md` check #1 says 5 rule symlinks (production landed in v0.9.0); CONTRIBUTING's counts/layout/PR-checklist match reality and document `eval/` + both test suites; the migrate skill says TWELVE migrations and gains the missing v0.9.1/v0.9.2 flags tables; README's Phase-1 scout list names the security-surface scout; `pipeline.md` uses the typed `changes/{type}/{slug}/` path throughout.

- **`scripts/migrate-v0.9.1-to-v0.9.2.sh`** (new) — idempotent target-repo upgrade: backup-on-diff (`<file>.pre-v0.9.2.bak`), `bootstrap --force` refreshes the pure-copy skills/pipeline/scout-prompts/hooks, and two anchored surgical patches update the per-project substituted `pre-push-gate.sh` (active-change selection + portable count parse — the target's substituted test command is read out of the old gate and carried forward; anchors verified present in every v0.8.2+ gate; customised gates get a warn + manual snippet). 16-check verification. End-to-end tested against a real v0.9.1 install bootstrapped by the actual v0.9.1 plugin: 16/16 apply, idempotent re-run, migrated gate behaves, 37/37 re-validation. **`skills/espalier-migrate/SKILL.md`** gains the twelfth chain step.

## 0.9.1 — 2026-07-03

Patch: **configurable escalation caps.** The review-round and rollback hard stops — how many coder↔reviewer rounds run before the pipeline stops and asks a human — were hardcoded prose (`Max 2 P0 rounds`, `Max 3 review rounds`, `>3 rollbacks`) scattered across the pipeline templates, with no way to tune them short of editing skill files. They now live in a single tracked config file the orchestrator reads at runtime. The defaults are unified to **3** for all three review types (code and test caps rise 2→3; requirements stays 3) and 3 for the rollback counter.

- **`skills/espalier-init/templates/... (new)`** `espalier/.espalier-config` — a key-value sidecar (mirrors the `.doctor-cadence` precedent: tracked, written once by bootstrap, preserved on re-bootstrap, greppable with an integer parse like `pre-push-gate.sh`). Holds `max-req-rounds`, `max-code-rounds`, `max-test-rounds`, `max-rollbacks` (all default 3), each with an inline `#` comment documenting which stage it gates and how to tune it. `#` comment lines and blanks are ignored by the reader.
- **`scripts/bootstrap-espalier.sh`** — writes `.espalier-config` (preserve-if-exists, so a user's tuning survives re-bootstrap) alongside the `.doctor-cadence` block, with a matching `--dry-run` line; the `_template/pipeline-state.md` `Review Rounds` denominators become `{max-*-rounds}` placeholders substituted from the config at change-creation.
- **`pipeline.md` + `skills/espalier.md` + `skills/espalier-fix.md`** — every hardcoded round-limit literal now references its config key (`at counter = max-code-rounds`, default stated inline); the Stage 2/4/6 gates and the rollback gate read the value via `grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'`, falling back to 3 when the file or key is absent (never blocks). The `## Review Cycle Limits` table is keyed by config name. The `"3 stages in a single rollback"` span guard is unchanged (a separate, fixed limit).
- **`templates/agent.md`** config index gains an `espalier/.espalier-config` row; **`references/wiring.md`** documents the file and the runtime read.
- **`scripts/migrate-v0.9.0-to-v0.9.1.sh`** (new) — idempotent target-repo upgrade: creates `espalier/.espalier-config` if absent and refreshes the three pure-copy pipeline files (`espalier/pipeline.md`, `espalier/skills/espalier/SKILL.md`, `espalier/skills/espalier-fix/SKILL.md`) from the plugin so the new prose reads the config (a customised file is backed up to `<file>.pre-v0.9.1.bak` first). `--dry-run` / `--yes` / `--plugin-dir=`. **`skills/espalier-migrate/SKILL.md`** gains the v0.9.0 → v0.9.1 chain step (absent `.espalier-config` ⇒ needed).

## 0.9.0 — 2026-07-01

Minor: **security audit** — a new `harness-security` sub-agent joins Stage 4 as a second reviewer in the same fixpoint loop, auditing the change's trust boundary on one axiom: *never trust data the frontend sent.* It traces each client-supplied value to where it reaches an authorization decision or a persistent write, classifies it on five risk axes (money / identity / permission / owner / state), and hard-blocks any sensitive field the backend fails to re-derive, re-authorize, or recompute — the IDOR, price-tampering, mass-assignment, and illegal-state-transition classes. Every flagged field becomes an abuse-test contract Stage 5 must satisfy and Stage 6 enforces. `harness-coder` reads the same taxonomy at write-time, so security shifts left. And because Stage 4 only audits *new* changes, a new **`/espalier-audit`** lane runs the same auditor repo-wide over the **existing** code — a point-in-time findings inventory in `espalier/wiki/security-audit.md`, each finding dispatchable to `/espalier-fix`.

- **`skills/espalier-init/templates/agents/harness-security.md`** (new) — the auditor sub-agent (tools `Read, Grep, Glob, Bash` — fresh eyes, no Write/Edit). Self-noops on changes with no sensitive surface; on a real one, traces data-flow, verifies the required control per axis, writes `security-record.md`, and emits the `## Security-Sensitive Fields` abuse-test contract. Re-audits every fix like the reviewer. Carries a **`## Repo-Audit Mode`** section for `/espalier-audit`: audits listed existing files instead of a change diff, returns findings as its final message (no security-record.md), routes controlled surfaces to `### Controls Confirmed` and no-input files to `### No Sensitive Fields`, and emits contract entries per-defect only.
- **`skills/espalier-init/templates/skills/espalier-audit.md`** (new) — the `/espalier-audit` repo-wide lane (pure-copy): enumerates the security surface from the discovered trust boundary + wiki critical paths (generic sweep fallback when undiscovered), batches it across ≤4 concurrent repo-audit auditors, consolidates to `espalier/wiki/security-audit.md` (OVERWRITE, point-in-time; findings + abuse-test contracts + controls confirmed), then offers per-finding dispatch into `/espalier-fix` (interactive only; each fix keeps its own approval gate + panel re-audit). Never edits code, never spawns the coder directly, never blocks; flags a contradicted `security-standards.md` via the drift sidecar, notify-only.
- **`skills/espalier-init/templates/rules/security-standards.md`** (new) — always-loaded rule: the trust-boundary doctrine, the five-axis sensitive-field taxonomy (universal seed patterns + `{discovered}` project-specific fields), the required control per axis, the mass-assignment ban, and the abuse-test requirement. Symlinked into `.claude/rules/`; read by coder + auditor.
- **`skills/espalier-init/templates/skills/espalier-security.md`** (new) — the audit checklist skill (mirrors `espalier-review`): method, control checklist, good/bad shapes, and the abuse-test recipe with worked IDOR / price / privilege-escalation / state examples.
- **`skills/espalier-init/templates/skills/espalier.md` + `pipeline.md`** — Stage 4 is now a **two-agent review panel** (`harness-reviewer` ∥ `harness-security`); any P0 from either loops the coder, and the `Reviewed-Diff` certificate is written only when both are clean (a security P0 shares the "max 2 rounds → escalate" counter). Stage 5 writes the contracted abuse tests; Stage 6 blocks if any is missing.
- **`skills/espalier-init/templates/skills/espalier-fix.md`** — the same panel + abuse-test enforcement in the 5-stage fix lane; a bug fix is treated as hostile-input surface.
- **`skills/espalier-init/templates/agents/harness-coder.md`** — new **`## Security-Aware Coding`** section (re-derive / re-authorize / recompute sensitive fields while writing) + Stage 5 abuse-test duty. **`harness-reviewer.md`** — new **`## Security Abuse-Test Coverage`** Stage 6 gate. **`espalier-testing.md`** — the abuse-test convention.
- **`skills/espalier-init/hook-templates/pre-push-gate.sh`** — a secret scan (BLOCKS — gitleaks if present, else a high-signal pattern grep over the pushed diff) + a dependency audit (WARNS — npm / pip-audit / govulncheck / cargo per stack). Both degrade gracefully when tooling is absent.
- **`skills/espalier-init/SKILL.md` + `references/discovery-checklist.md`** — Phase 1 gains a security-surface scout (1.11 — entry points, identity/ownership/validation patterns, project sensitive fields → `DISCOVERY.security`); Phase 2 writes the three new files. **`scripts/bootstrap-espalier.sh`** wires them plus the pure-copy `espalier-audit` skill (mkdir + copy + 4 symlinks), adds `/espalier-audit` to the CLAUDE.md block, and grows to **37 validation checks** (added: security rule/agent/skill, audit skill, repo-audit mode, production rule + symlink, scout-prompts). **`templates/agent.md`** config index gains an Audit row. **`scripts/test-bootstrap.sh`** catches up (it had been stale since v0.7): simulates the security substitution files and asserts against the 37-check output.
- **`scripts/migrate-v0.8.2-to-v0.9.0.sh`** (new) — idempotent target-repo upgrade: creates the 3 new files (project-name + tools-mode substitution), `bootstrap --force` refreshes the pure-copy pipeline files + installs/symlinks the `espalier-audit` skill + validates (37 checks), surgical appends add the security sections to the per-project coder/reviewer/testing files (and the Repo-Audit Mode section — extracted from the plugin template at run time so the two can't drift — to a pre-fold `harness-security.md`), a surgical insert adds the scan to the push gate, and CLAUDE.md + `espalier/agent.md` are patched to mention `/espalier-audit`. Backs up customised pipeline files (`<file>.pre-v0.9.0.bak`). The already-done detector requires all ten artifacts, so a crash mid-run is completed on re-run. `--dry-run` / `--yes` / `--plugin-dir=`.
- **`skills/espalier-migrate/SKILL.md`** — the auto-detect chain gains the v0.8.2 → v0.9.0 step (a tenth migration; the Stage 4 panel + `harness-security` agent + `espalier-audit` skill + Repo-Audit Mode section — any absent ⇒ needed).
- **Migration-chain fix** (`migrate-v0.4-to-v0.5.sh` … `migrate-v0.8.1-to-v0.8.2.sh`) — the five intermediate migrations no longer hard-abort when `bootstrap --force`'s final health check reports missing artifacts: with a v0.9.0 plugin, checks 30-37 test security/audit/production artifacts that only the *final* chain step installs, so every pre-v0.8.2 chain died mid-way. They now distinguish a validation-only failure (stages 1-10 wired, health check red — warn and continue; the chain's terminal step re-validates everything) from a real bootstrap failure (still aborts). Verified end-to-end: a v0.8.1 install migrated through v0.8.1 → v0.8.2 → v0.9.0 lands on 37/37 validation.
- **`eval/security/`** (new, dev/QA — not shipped) — an eval harness for `harness-security`, mirroring `eval/grill`: runner + rubric + 9 golden fixtures (5 change-scoped vuln across the five axes + mass-assignment + queue-consumer; 2 change-scoped clean for self-noop + false-positive precision; 2 `mode: repo-audit` — a mixed repo exercising findings/controls-confirmed/no-sensitive-fields routing, and a clean repo). Gates on catch-rate ≥ 0.90 with zero false positives, so a prompt edit that regresses the auditor's judgment in either mode fails closed.

**Production hardening (folded into v0.9.0).** Alongside the security audit, v0.9.0 raises the bar the pipeline holds the *generated* code to and closes a set of mechanical gate defects found in a full-system audit:

- **`skills/espalier-init/templates/rules/production-standards.md`** (new, always-loaded) — a universal NFR bar on three axes with tiered severity: **resilience** (external calls carry a timeout + a decided failure behaviour; list reads are bounded; shared state is applied atomically), **observability** (new endpoints/consumers emit a structured log with actor/entity/outcome; errors are never swallowed), **data safety** (migrations follow expand→migrate→contract; destructive ops need requirement sign-off; mutating consumers are idempotent). P0 for the data-loss class (hard-blocks the fixpoint loop), P1 for readiness gaps. `harness-coder` writes to it (`## Production-Aware Coding`), `harness-reviewer` enforces it (`## Production-Readiness Review`), and `espalier-testing` adds failure-mode tests for every new external-call path. Seeds are universal; `{discovered}` cells carry the project's own mechanisms.
- **Contract hardening** — `harness-reviewer` and `harness-security` now emit a machine-greppable `VERDICT: … p0=N round=N` sentinel as the last line of their record, and **both** records are OVERWRITTEN per round (round history snapshots into pipeline-state.md). The orchestrator freshness-checks BOTH records and gates on the sentinel — closing the stale-reviewer-verdict hole (a dead reviewer could previously certify on an old PASS) and the reviewer/skill verdict-vocabulary divergence. `espalier-review.md` now defers to `harness-reviewer.md` as the canonical format.
- **Gate integrity** — the push gate now `cd`s to the repo root in both the wrapper and the gate itself, closing a fail-OPEN hole where a push from a subdirectory skipped the stage/certificate/secret checks entirely; the stage parse is `head -1`-bounded. Stage 3 gains a **programmatic build/lint re-run** by the orchestrator (the coder's self-reported status is no longer the gate). The human-checkpoint gates (grill, requirements approval) key off a new explicit `interactivity_mode` signal instead of a bash TTY test — which always read "non-interactive" inside Claude Code, silently auto-approving every interactive run.
- **Fix-lane hardening** — the Stage 0 blame procedure is now inlined (it referenced a plan doc that never shipped); the lane documents its per-stage state-write protocol (the push gate requires `Current Stage ≥ 7`) and Status lifecycle; Stage 5 mechanically verifies the regression test FAILS at `Base-Ref` via a detached worktree (`REGRESSION_VERIFIED`); the causal-regression check reaches the Stage 4 reviewer, not only Stage 6.
- **Stage 9/10** — deploy verification is now real when init discovers deploy config (scout 1.5 gains deploy/health discovery → `development-process.md` Deploy & Verification), and a clean recorded `SKIPPED: no-deploy-config` when it doesn't. Stage 10 gains an acceptance template with a non-interactive exception.
- **P3** — the triplicated discovery-scout prompts collapse into one shipped `espalier/.scout-prompts.md` read by both `/espalier-prune` and `/espalier-doctor`; the TS boundary hook matches CJS `require()`/dynamic `import()`; the fuzzy squash-match is whole-path (no `a.ts`⊂`a.tsx`) and space-safe; `agent.md`'s config index gains the Security/Production/Grill/Audit rows.
- **`scripts/bootstrap-espalier.sh`** grows to **37 checks** (production rule + symlink + scout-prompts); **`scripts/test-bootstrap.sh`** simulates the new files (60 assertions). The v0.8.2→v0.9.0 migration installs all of the above idempotently (already-done check now covers ten artifacts).

Additive to every existing install — new pipeline runs get the audit + the production bar, and the auditor self-noops on non-security changes so the cost lands only where it matters. See [docs/migrating-v0.8-to-v0.9.md](./docs/migrating-v0.8-to-v0.9.md).

## 0.8.2 — 2026-06-25

Patch: **re-review fixpoint loop + push-gate certificate** — code review is now a loop, not a single pass. When the reviewer files a P0 and the coder fixes it, the fix is re-reviewed; the only way out of Stage 4 (and Stage 6) is a fresh review of the *current* code returning zero P0 — so the coder is never the last actor before the gate, a reviewer always is. A new push-gate certificate binds the verdict to a content fingerprint of the reviewed source, so a fix that skips re-review fails closed at push time. Closes the gap where a NEW bug introduced by a fix could ship unreviewed.

- **`skills/espalier-init/templates/pipeline.md`** — Stage 4 (Code Review) rewritten from a single pass + one-way "rollback to Stage 3" into a **fixpoint loop**: every coder fix returns to a fresh reviewer, and the gate to leave Stage 4 is "the most-recent review saw the current code and returned zero P0," not "the earlier P0s were addressed." Stage 3 records a `Base-Ref` anchor before any code is written; Stage 4 writes a `Reviewed-Diff` certificate on PASS — a `git hash-object` fingerprint of the source diff vs `Base-Ref`, `espalier/` bookkeeping excluded; Stage 6 (Test Review) refreshes it to cover the added tests. Max 2 P0 rounds → escalate (unchanged).
- **`skills/espalier-init/templates/skills/espalier-fix.md`** — the same fixpoint loop for the 5-stage fix lane's Stage 4 (previously a single "spawn reviewer" line), plus the `Base-Ref` record at Stage 3 and the certificate refresh at Stage 6.
- **`skills/espalier-init/templates/agents/harness-reviewer.md`** — new **`## Re-review Rounds`** section: on re-spawn the reviewer is handed the "changed since last review" delta, scrutinizes it hardest, confirms the fix did not regress previously-passed code, and still returns a whole-diff verdict — a re-review is a real review, not a rubber stamp.
- **`skills/espalier-init/hook-templates/pre-push-gate.sh`** — new review-certificate check: blocks the push unless the `Reviewed-Diff` fingerprint still matches the code being pushed (recomputed against `Base-Ref`, `espalier/` excluded). Fail-open for legacy state — no `Base-Ref`/`Reviewed-Diff` ⇒ warn and skip — so in-flight pre-upgrade changes are never blocked.
- **`scripts/migrate-v0.8.1-to-v0.8.2.sh`** — idempotent target-repo upgrade. `bootstrap --force` refreshes the two pure-copy files (`pipeline.md`, `espalier-fix`) carrying the loop + certificate writes; a surgical append adds the `## Re-review Rounds` section to the LLM-written `harness-reviewer.md`; a surgical insert adds the certificate check to the LLM-written `pre-push-gate.sh` before its build check (graceful warn + manual snippet if the gate was customised past the anchor). Backs up customised pipeline files on diff (`<file>.pre-v0.8.2.bak`). `--dry-run` / `--yes` / `--plugin-dir=` flags. macOS `/bin/bash` 3.2 compatible.
- **`skills/espalier-migrate/SKILL.md`** — the auto-detect chain gains the v0.8.1 → v0.8.2 step (a ninth migration; pipeline loop / reviewer section / gate certificate all present ⇒ done), plus dry-run/apply lines and a flags table.

Non-breaking: new pipeline runs get the loop + certificate; in-flight changes without a certificate fall through the push gate with a warning; fresh installs and unattended runs are unaffected. No migrating doc (a patch, like v0.8.1).

## 0.8.1 — 2026-06-25

Patch: **change-impact / runtime-surface guidance for the sub-agents** — the coder and reviewer now reason about *every* surface a change touches (admin/CRUD UIs, API validation, client forms, persisted data, other callers), not just the programmatic happy path. This closes a class of avoidable fix-round: a value made system-derived (auto-generated/defaulted/computed) that is left user-required on a UI, so server-side generation succeeds while the UI still blocks the user before the hook runs.

- **`skills/espalier-init/templates/agents/harness-coder.md`** — new **`## Change Impact Analysis`** section (run before writing code): enumerate every surface that produces/reads/validates/persists the thing being changed; a value that becomes system-derived must stop being user-required *everywhere*; when mirroring a working element copy its WHOLE configuration, not one attribute; record the blast radius in coding-report.md "Notes". Stack-agnostic prose — concrete surfaces come from the project's own layer specs / `engineering-structure.md`.
- **`skills/espalier-init/templates/agents/harness-reviewer.md`** — new **`## Runtime-Surface Review`** section + a Review Process step that points at it: never approve a change verified only on the happy path; a leftover "required"/"not-empty" constraint on a now-derived value that blocks a UI/client before the server hook runs is a **P1** defect; an unchecked surface is a reported gap, not a silent pass. A matching `You Must NOT` bullet is added.
- **`scripts/migrate-v0.8-to-v0.8.1.sh`** — idempotent target-repo upgrade. Both agent files are written per-project at `/espalier-init` time, so a plugin update never reaches an existing install; this script appends the two sections (one per file), patching each independently and no-opping per file if already present. `--dry-run` / `--yes` flags (`--plugin-dir` accepted and ignored — the patch appends inline text). macOS `/bin/bash` 3.2 compatible.
- **`skills/espalier-migrate/SKILL.md`** — the auto-detect chain gains the v0.8 → v0.8.1 step (an eighth migration; either agent section absent ⇒ needed), plus dry-run/apply lines and a flags table.

Purely additive agent guidance — non-breaking for every existing install, fresh installs, and unattended runs. No migrating doc (a patch, like v0.5.3).

## 0.8.0 — 2026-06-15

Minor: **requirements approval gate** — both pipelines now STOP after the requirement is written and reviewed, and wait for explicit user sign-off before any code is written. Previously Stage 1 → Stage 2 → Stage 3 chained automatically, so coding began the moment the requirement doc existed.

- **`skills/espalier-init/templates/skills/espalier.md`** — new **Requirements Approval Gate** (BLOCKING) between Stage 2 (requirements review) and Stage 3 (coding). After Stage 2's gate passes, the orchestrator presents the final `requirements.md` (goal, acceptance criteria, what the Stage 1 grill resolved/scoped-out) and asks via `AskUserQuestion` → Approve / Edit / Abort. Coding starts only on **Approve**; **Edit** revises the doc, re-runs the Stage 2 gate, and re-asks; **Abort** writes `Status: ABORTED`. The Stage Execution Protocol's `PASS → advance` rule now explicitly carves out the Stage 2 → Stage 3 transition so a Stage 2 PASS alone no longer authorizes coding.
- **`skills/espalier-init/templates/skills/espalier-fix.md`** — same gate for the 5-stage fix lane, placed after Stage 1 (bug requirements + diagnosis grill) and before Stage 3. Runs *after* the Stage 1 escalation gate (escalation may migrate the fix to the feat lane first); only an in-lane fix reaches the approval gate.
- **`skills/espalier-init/templates/pipeline.md`** — removed the weak Stage 1 "Confirm understanding" checkpoint (it never fired — Stage 1's gate passed silently and the orchestrator advanced). The blocking human checkpoint now sits on Stage 2, pointing at the espalier skill's Requirements Approval Gate.
- **Non-interactive exception** — on a no-TTY run (the same condition that auto-skips the Stage 1 grill), the gate cannot prompt: it auto-approves and records `requirements auto-approved (non-interactive)` in the Stage History, so unattended pipelines never hang. Interactive runs ALWAYS prompt.
- **`scripts/migrate-v0.7-to-v0.8.sh`** — idempotent target-repo upgrade. Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.8.bak`) since `bootstrap --force` re-copies them all, then runs `bootstrap --force` to refresh the three changed templates (`pipeline.md`, `espalier`, `espalier-fix`) and verifies the gate text is present. `--dry-run` / `--yes` / `--plugin-dir=` flags.
- **`skills/espalier-migrate/SKILL.md`** — the auto-detect chain gains the v0.7 → v0.8 step (a seventh migration; the approval-gate text absent from `espalier/skills/espalier/SKILL.md` ⇒ needed).

The approval gate is interactive-only — non-breaking for unattended runs (auto-approve) and fresh installs. See [docs/migrating-v0.7-to-v0.8.md](./docs/migrating-v0.7-to-v0.8.md).

## 0.7.0 — 2026-06-13

Minor: **read-only `/espalier-ask` lane** — answer questions about the codebase from the `espalier/` docs first, verified against the code. Purely additive; no pipeline change.

- **`skills/espalier-init/templates/skills/espalier-ask.md`** — new `espalier-ask` skill. Answers "how / where / why / what-changed" questions by classifying the question, reading the `espalier/` docs that bear on it (wiki for *how/where*, `changes/*/requirements.md` + `review-record.md` for *why*), verifying every doc-sourced claim against the cited code before asserting it, and falling back to a from-scratch codebase search when the docs are silent. Every claim is sourced (doc path and/or `file:line`). Strictly read-only — it is not a pipeline lane (no stages, gates, or `changes/` folder) and never edits a doc. Two notify-only byproducts: a wiki it reads that contradicts the code is flagged via the existing `mark_stale` drift sidecar (reason `ask-verify: …`, pointing the user at `/espalier-prune`), and a question the docs cannot answer is appended to a git-tracked `espalier/.ask-gaps.tsv` as a wiki-gap backlog. Degrades gracefully — missing wiki/`changes/` or no `espalier/` dir at all → answer from code, write nothing, never crash.
- **`scripts/bootstrap-espalier.sh`** — Stage 2 makes `espalier/skills/espalier-ask/`, Stage 3 copies the SKILL.md, Stage 5 symlinks `.claude/skills/espalier-ask`, Stage 7's `CLAUDE.md` block gains a `/espalier-ask` line, and Stage 11 adds validation check 29 (`espalier-ask-skill`) plus the skill in check 2's load list — the validation total moves 28 → 29.
- **`skills/espalier-init/templates/agent.md`** — the config-index table gains an `Ask` row (`Via /espalier-ask`).
- **`scripts/migrate-v0.6-to-v0.7.sh`** — idempotent target-repo upgrade. Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.7.bak`) since `bootstrap --force` re-copies them all, runs `bootstrap --force` to install + wire the skill, then patches `CLAUDE.md` and `espalier/agent.md` to mention `/espalier-ask` (bootstrap's `CLAUDE.md` writer is append-once and never touches the per-project `agent.md`). `--dry-run` / `--yes` / `--plugin-dir=` flags.
- **`skills/espalier-migrate/SKILL.md`** — the auto-detect chain gains the v0.6 → v0.7 step (a sixth migration; `espalier-ask` skill absent ⇒ needed). Also fixes a stale `description` that had never been updated past the v0.5.3 patch.
- **`eval/ask/`** — eval harness for the skill: fixtures across five buckets (classify, docs-first, drift, gap, no-install), a two-gate rubric (deterministic sidecar/behaviour assertions + an LLM answer-quality judge), and `run.sh`, which materializes a temp git repo per fixture before running the skill.

`/espalier-ask` is read-only and additive — non-breaking for every existing install and unattended runs. See [docs/migrating-v0.6-to-v0.7.md](./docs/migrating-v0.6-to-v0.7.md).

## 0.6.0 — 2026-06-02

Minor: **Stage 1 grilling** — the pipeline now interrogates a requirement or a bug diagnosis before any code is written. Plus chronologically-sortable change folders.

- **`skills/espalier-init/templates/skills/espalier-grill.md`** — new `espalier-grill` skill. An under-specified requirement (or an unconfirmed diagnosis) that passes Stage 1 is trusted by every later stage, and no later gate audits it. Grill is that audit: it counts concrete ambiguity *signals* in the Stage 1 input (undefined terms, unstated actors, missing failure behaviour, hidden quantifiers, unscoped edge cases; for fixes: unconfirmed cause, weak reproduction), maps the count to a depth tier, and runs an adaptive sequential interrogation that resolves each gap into the change's `requirements.md`. Two modes: `spec` (from `/espalier`) and `diagnosis` (from `/espalier-fix`). Invoked *by* Stage 1 — never a user-facing slash command. Skips itself with verdict `SKIPPED: non-interactive` when there is no TTY, so an unattended pipeline never hangs on a grill question.
- **`templates/skills/espalier.md`, `espalier-fix.md`, `espalier-requirements.md`** — Stage 1 of both pipelines now invokes the grill. On by default; opt out per-invocation with `--no-grill` (parsed via `GRILL_DISABLED` in `/espalier`, a `--no-grill` flag in `/espalier-fix`).
- **`eval/grill/`** — eval harness for the skill: nine fixtures across three buckets (full-depth, light-touch, skip), a scoring rubric, and `run.sh`.
- **`scripts/migrate-v0.5-to-v0.6.sh`** — idempotent target-repo upgrade. Backs up any customised pipeline skill on diff (`<file>.pre-v0.6.bak`), then `bootstrap --force` installs the grill skill, refreshes the four changed pipeline templates, and symlinks the new skill. `--dry-run` / `--yes` flags.
- **Dated change folders** — change folders now use `{slug}` = `YYYY-MM-DD-{kebab}` (UTC creation date as a prefix), so a listing of `changes/{feat,fix,refactor}/` orders chronologically (ISO date prefix makes lexical sort == chronological sort). Fix-lane collision/resume matches by the `{kebab}` tail (re-deriving on a later day changes the prefix), `--slug` override is literal, and reverse-lookup is unaffected (it derives slug from the folder basename). Existing undated folders are untouched; the v0.6 migration's template refresh carries the change to new pipeline runs.

Stage 1 grilling is additive and interactive-only — non-breaking for fresh installs and unattended runs. See [docs/migrating-v0.5-to-v0.6.md](./docs/migrating-v0.5-to-v0.6.md).

## 0.5.6 — 2026-05-26

Minor: `/espalier-init` now ends with a telemetry-free feedback prompt.

- **`skills/espalier-init/SKILL.md`** — new Phase 4 (Completion message). After Phase 3's bootstrap exits 0, the install agent prints a fixed block confirming the install, linking the repo for a ⭐, and linking `issues/new` for feedback. No metrics, no callback, no follow-up nag. Skipped on idempotent re-runs (the `espalier/.merge-hook-decision` marker file signals a re-run) and skipped on non-zero bootstrap exit so a failure surfaces instead.

Rationale: prior to this, a successful install ended in silence — no moment where the user was prompted to acknowledge it worked. Silent installs convert to neither stars (which help the next visitor evaluate the plugin) nor issues (which are the only useful signal back). A single one-shot ask at the natural celebratory moment captures a slice of each without resembling a tracking mechanism.

## 0.5.5 — 2026-05-22

Patch: skill symlinks stop nesting a self-referencing loop on a wiring re-run.

- **`scripts/bootstrap-espalier.sh`** — `safe_ln` wired skills with `ln -sf`. On a re-run (`bootstrap --force`, or a migration that re-wires), the destination `.claude/skills/<skill>` already exists as a symlink to a directory. Without `-n`, `ln` follows that symlink and creates the new link *inside* the real directory — `espalier/skills/<skill>/<skill>` pointing back at its own parent — instead of replacing the link. A v0.4→v0.5 migration re-run left eight such self-referencing loops in a target repo (one per skill); they break recursive directory walks — `find`, drift scans, backups. `safe_ln` now passes `ln -sfn`; `-n` (no-dereference) is portable across BSD and GNU `ln`.
- **`scripts/migrate-v0.1-to-v0.2.sh`, `scripts/migrate-v0.3-to-v0.4.sh`** — the raw `ln -sf` calls that wire skills, rules, and agents had the same defect; both now use `ln -sfn`.
- **`skills/espalier-init/SKILL.md`, `skills/espalier-init/references/wiring.md`, `README.md`, `CONTRIBUTING.md`** — the documented manual `ln -sf` wiring commands, which a user or the init skill runs by hand, updated to `ln -sfn` so a re-run is safe.
- **`scripts/test-bootstrap.sh`** — Test 3 and Test 4 both re-run the bootstrap but only asserted the `.claude/skills/<skill>` link still existed — true even with the nested loop present, which is why the bug shipped. Each now also asserts no symlink exists two levels deep under `espalier/skills/`, the exact signature of the bug.

No behavior change for a first-time `/espalier-init` — the bug only triggered when wiring ran a second time over existing symlinks. An install that already accrued the loops can clear them with `find espalier/skills -mindepth 2 -maxdepth 2 -type l -delete` (removes only the stray links, not the skills).

## 0.5.4 — 2026-05-22

Patch: skills resolve their own plugin directory instead of guessing paths.

- **`skills/espalier-migrate/SKILL.md`** — Step 2 located the plugin scripts with a hard-coded list of guessed paths (`~/.claude/plugins/<name>`, `~/repos/...`, a personal dev dir). None matched Claude Code's actual marketplace layout (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so `/espalier-migrate` either failed outright for a normal install, or — if a same-named dev checkout happened to sit in `$HOME` — silently ran *that* checkout's scripts instead of the installed plugin. It now derives the plugin root from `${CLAUDE_SKILL_DIR}` (the skill's own directory, set by Claude Code), which resolves the installed plugin in every layout.
- **`skills/espalier-init/SKILL.md`** — Phase 3 invoked `bootstrap-espalier.sh` through `$PLUGIN_DIR`, a variable the skill never defined. It now uses `${CLAUDE_SKILL_DIR}` for both the script path and bootstrap's `--plugin-dir`.

`${CLAUDE_PLUGIN_ROOT}` is not available to skill-spawned Bash — `${CLAUDE_SKILL_DIR}` is the documented mechanism. An `ESPALIER_PLUGIN_DIR` override plus a dev-checkout fallback remain for the rare case the variable is unset.

## 0.5.3 — 2026-05-22

Patch: the coder sub-agent gets an explicit editing-discipline rule.

- **`templates/agents/harness-coder.md`** — new `## Editing Discipline` section. The coder agent ships with `Bash` in its tool list and previously had no rule on *how* to edit files, so it could (and did) edit source by shelling out to `python3`/`sed`/`awk` heredocs that splice a file by string offset. That bypasses the `post-edit-wrapper.sh` PostToolUse hook (layer-boundary checks never run), leaves no reviewable diff, and corrupts the file when whitespace shifts. The new section requires the `Edit`/`Write` tools and bans shell-splicing.
- **`scripts/migrate-v0.5.2-to-v0.5.3.sh`** — new. `harness-coder.md` is written per-project at `/espalier-init` time, so a plugin update never reaches an existing install. This script appends the `## Editing Discipline` section to `espalier/agents/harness-coder.md` in an existing repo. Idempotent, `--dry-run`/`--yes` flags, pure bash.
- **`skills/espalier-migrate/SKILL.md`** — `/espalier-migrate` now detects when the coder-agent patch is needed (content check on `harness-coder.md`) and applies `migrate-v0.5.2-to-v0.5.3.sh` as the final step of the chain.

No behavior change for fresh `/espalier-init` runs beyond the new agent rule.

## 0.5.2 — 2026-05-22

Patch: the `core.hooksPath` fix from v0.5.1 extended to the migration scripts.

- `scripts/migrate-v0.4-to-v0.5.sh` — the Step 3 "post-merge dispatcher installed" verification grepped a hard-coded `.git/hooks/post-merge`, the same blind spot v0.5.1 fixed in the bootstrap. On a `core.hooksPath` repo the migration itself succeeded (Step 1 runs the now-fixed `bootstrap-espalier.sh --force`) but the check reported a false failure. It now resolves `core.hooksPath`.
- `scripts/migrate-v0.1-to-v0.2.sh` — the post-merge hook install now resolves `core.hooksPath` instead of assuming `.git/hooks/`.
- `scripts/migrate-v0.3-to-v0.4.sh` — the `harness/` → `espalier/` hook-path rewrite now resolves `core.hooksPath` when locating the live hook.
- `docs/migrating-v0.4-to-v0.5.md` — the manual post-migration verification snippet honors `core.hooksPath`.

No behavior change for repos without `core.hooksPath` set. The canonical resolution (with the outside-repo skip) lives in `bootstrap-espalier.sh` Stage 9; the migration scripts do a plain resolve and the chain's final `bootstrap --force` is the safety net.

## 0.5.1 — 2026-05-22

Patch: `scripts/bootstrap-espalier.sh` now honors `git config core.hooksPath`.

- Bootstrap Stage 9 wrote the post-merge dispatcher to a hard-coded `.git/hooks/post-merge` (or `.husky/post-merge`). When a repo sets `core.hooksPath` — husky v9, lefthook, or an org-wide global hooks dir — git ignores `.git/hooks` entirely, so the dispatcher landed at a path git never reads: `drift-detect.sh` and `post-merge-backlink.sh` silently never ran. Stage 9 now resolves `core.hooksPath` and installs to git's real hooks dir.
- A `core.hooksPath` that points outside the repo (e.g. a stale absolute path inherited from a repo copy/rename) cannot be wired safely — Stage 9 now skips the install and prints a fix instead of a false success. A value containing `..` is rejected for the same reason.
- Validation check 20 (`post-merge-dispatcher`) greps the resolved hooks dir instead of the fixed `.git/hooks` path, so it can no longer report a green check for a dispatcher git will never execute.
- `scripts/test-bootstrap.sh` gains Test 12 — covers the inside-repo install and the outside-repo refusal.

Verified with the smoke suite (51 asserts across 12 tests) and a live end-to-end run: a `core.hooksPath` repo, the real bootstrap, and a real `git merge` firing the dispatcher.

## 0.5.0 — 2026-05-20

Doc-drift detection. The artifacts `/espalier-init` generates — rules, wiki, layer specs, hooks — no longer silently rot as the codebase evolves. v0.5.0 adds detection, surfacing, gated remediation, and validation, **without ever auto-overwriting a doc** and without a hook that dirties the working tree.

> **Existing users:** run `/espalier-migrate`. A v0.4.x install gets the v0.4→v0.5 upgrade; v0.1.x–v0.3.x installs get the full chain (v0.1→v0.2→v0.4→v0.5) applied in order. See [`docs/migrating-v0.4-to-v0.5.md`](./docs/migrating-v0.4-to-v0.5.md).

### The problem

`/espalier-init` writes the project's rules, wiki, specs, and hooks once. After init they were never refreshed. A new architectural layer, a schema change, a convention that shifted during review — each leaves a generated artifact describing a codebase that no longer exists. Worst case: a stale rule sits in the Always context layer, auto-loaded every session, actively misguiding every future agent run.

### Added

- **Post-merge drift detector** — `drift-detect.sh`, installed unconditionally, runs on every merge/pull. Diffs `ORIG_HEAD..HEAD` and flags drifted artifacts (new/removed layers, cross-layer moves, schema/route/dependency/CI/lint-config changes) into a gitignored sidecar, `espalier/.drift-state.tsv`. Heuristic, cheap, never edits a doc.
- **`drift-helpers.sh`** — pure-bash shared library (bash-3.2 safe — no associative arrays), sourced by every drift consumer. Sidecar upsert, staleness tiering, convention-index append, doctor cadence, run-mode detection.
- **Reviewer convention-drift capture** — a file diff cannot see a convention shift ("controllers now return `Result<T,E>` instead of throwing"); only the reviewer can. `harness-reviewer.md` gains a Convention Drift Reporting protocol; `parse-drift-blocks.py` parses the emitted blocks at Stage 4.
- **Cross-PR convention index** — `espalier/.conventions.tsv` (tracked). The reviewer emits lower-bar Convention Observations; the orchestrator canonicalizes their keys across reviews; when one `pattern_key` reaches 3 `diverges` rows the Stage 0 pre-flight surfaces a promote / reject / exception / wait prompt.
- **`/espalier-prune`** — the only component that edits a generated doc. Per flagged file: re-run the matching discovery scout, two-way-diff current vs proposed, gated apply by file class (wiki / rules / specs / hooks). Interactive, never silent; unattended runs only write a report.
- **`/espalier-doctor`** — periodic re-scout that catches what the file-diff detector and the reviewer miss: silent refactors that change no file structure, and drift that landed before this clone existed. Cadence (`every-change` / `weekly` / `monthly` / `manual`) is chosen at init and activity-gated — an idle repo never triggers a scan.
- **Stage 0 pre-flight** — one consolidated `AskUserQuestion` at the start of `/espalier` and `/espalier-fix`, summarising stale docs (tiered), conventions over the promotion threshold, and a due doctor scan. Replaces what would otherwise be three separate prompts.
- **Stage 8.5** — a notify-only doc-drift check between Stage 8 (CI verify) and Stage 9 (deploy). Writes a table to the change's `doc-patches.md`, surfaces one line, blocks nothing.
- **Validation checks 25–28** — stale-artifact tiers (Policy 3: fresh / aging / stale / critical / expired by age), plus structural checks for `.drift-state.tsv`, `.conventions.tsv`, and `.doctor-cadence`.
- **Phase 0 Q3** — doctor cadence, chosen alongside the squash-merge strategy and sub-agent tool scope.
- **`scripts/migrate-v0.4-to-v0.5.sh`** — the v0.4→v0.5 upgrade. `/espalier-migrate` now detects three migration stages and applies the needed chain in order.

### Changed

- **`scripts/bootstrap-espalier.sh`** — Stage 4 copies the three new drift hooks; Stage 9 installs a stable post-merge **dispatcher** instead of inlining `post-merge-backlink.sh` (this also fixes a pre-existing bug — the inline copy meant a plugin update never reached an installed hook; the dispatcher calls scripts by path); Stage 10 gitignores five drift sidecars; Stage 11 grew from 24 to 28 checks. New flags: `--doctor-cadence`, `--ignore-drift` (+ `--ignore-drift-reason`).
- **The post-merge hook is now installed unconditionally.** Previously it was installed only when the squash-merge decision was `installed`. The dispatcher always runs `drift-detect.sh`; `post-merge-backlink.sh` is still gated — now at runtime, by `espalier/.merge-hook-decision` — so flipping that file toggles backlink with no hook reinstall.
- **`hook-templates/pre-push-gate.sh`** prints a non-blocking "an /espalier-doctor scan is due" reminder.
- **`espalier.md` / `espalier-fix.md` / `harness-coder.md` / `harness-reviewer.md` / `pipeline.md`** — Stage 0 pre-flight, Stage 4 drift-capture glue, Stage 7 convention-index staging, Stage 8.5, reader-side stale-doc gates for the coder and reviewer sub-agents.
- **Phase 0** is now a three-question `AskUserQuestion` (squash strategy, sub-agent tools, doctor cadence).

### Not breaking

- **Pipeline semantics** — 10 stages, gates, escalation, rollback — unchanged. Stage 8.5 is a label, not a numeric stage; `Current Stage:` never holds `8.5`, so `pre-push-gate.sh`'s integer parse is unaffected.
- **The 24 original validation checks** keep their semantics — only check #20 was repointed from the backlink marker to the dispatcher marker (both verify a working post-merge hook).
- **Sub-agent identifiers `harness-coder` / `harness-reviewer`, typed `changes/{type}/{slug}/` layout, squash-merge decision values** — unchanged.
- **Drift detection is additive** — a v0.4 install that never migrates keeps working exactly as before.
- **Drift state is gitignored** — no automation writes a tracked file; no `git pull` and no pipeline stage is left with a dirty working tree.

### Migration

`/espalier-migrate` auto-detects the install version and applies the needed migration chain. For a v0.4.x install that is just the v0.4→v0.5 step: `bootstrap-espalier.sh --force` (drift hooks, the two new skills, the dispatcher, gitignore, `.doctor-cadence`, refreshed pure-copy skills) plus an anchor-patch of the three LLM-substituted files bootstrap cannot regenerate (`harness-coder.md`, `harness-reviewer.md`, `pre-push-gate.sh`). Idempotent; dry-run-first. Full guide: [`docs/migrating-v0.4-to-v0.5.md`](./docs/migrating-v0.4-to-v0.5.md).

### Why this release

Generated guardrails that describe a codebase as it was on init day are worse than no guardrails — the reviewer trusts a stale `coding-standards.md`, approves wrong-pattern code, and the drift compounds. v0.5.0 closes the loop: detect drift mechanically where possible (file diffs, reviewer judgment, cross-PR aggregation, periodic re-scout), surface it at the moments work already pauses (Stage 0, push, CI), and refresh only through an explicit, gated `/espalier-prune`. Defense-in-depth, never an auto-overwrite.

## 0.4.1 — 2026-05-19

Patch: `scripts/migrate-v0.3-to-v0.4.sh` portability on macOS.

- `declare -A` (associative arrays, bash 4+) silently no-op'd on macOS system bash 3.2, then `${!ARRAY[@]}` tripped `set -u`. Replaced with parallel indexed arrays (`SKILL_OLD` / `SKILL_NEW`).
- A `sed -E` alternation anchor (`(^|[^chars])`) is rejected by BSD `sed` with "parentheses not balanced". Replaced with a two-pass substitution (line-start and non-word-boundary handled separately). BSD + GNU compatible.

Verified end-to-end on `/bin/bash` 3.2.57 and homebrew bash 5.x.

## 0.4.0 — 2026-05-19

The rebrand. Plugin renamed `harness-engineering` → `espalier-engineering`. Target-project directory `harness/` → `espalier/`. Slash commands collapsed and rebranded. Sub-agent identifiers kept for in-flight stability. Migration is mechanical via `/espalier-migrate`.

> **Existing v0.1.x – v0.3.x users:** run `/espalier-migrate` from inside Claude Code. It auto-detects which migration(s) you need (v0.1→v0.2 typed-changes layout, v0.3→v0.4 rename, or both) and applies them in order. See [`docs/migrating-v0.3-to-v0.4.md`](./docs/migrating-v0.3-to-v0.4.md).

### Breaking changes

| Component | Before | After |
|---|---|---|
| Plugin name | `harness-engineering` | `espalier-engineering` |
| GitHub repo | `Junhanliu-dev/harness-engineering` | `Junhanliu-dev/espalier-engineering` (redirects active) |
| Target-project dir | `harness/` | `espalier/` |
| Slash command | `/harness-engineering` | `/espalier-init` |
| Slash command | `/harness-run <req>` | `/espalier <req>` (bare — no `-run` suffix) |
| Slash command | `/harness-fix <bug>` | `/espalier-fix <bug>` |
| Slash command | `/harness-migrate` | `/espalier-migrate` |
| Child skill folders | `harness-{coding,review,testing,requirements,fix}` | `espalier-*` |
| Child skill folder | `harness-run` | `espalier` (matches new bare slash command) |
| `.claude/rules/` symlink names | `harness-{structure,standards,process}.md` | `espalier-*.md` |
| `.claude/skills/` symlink names | `harness-*` | `espalier-*` (or bare `espalier`) |
| `.claude/settings.json` hook paths | `harness/hooks/...` | `espalier/hooks/...` |
| `CLAUDE.md` section header | `## Harness Engineering` | `## Espalier` |
| `.gitignore` cache entry | `harness/.commit-index.tsv` | `espalier/.commit-index.tsv` |
| Reverse-lookup cache | `harness/.commit-index.tsv` | `espalier/.commit-index.tsv` |
| Bootstrap script | `scripts/bootstrap-harness.sh` | `scripts/bootstrap-espalier.sh` |
| Env var | `HARNESS_PLUGIN_DIR` (still honored) | `ESPALIER_PLUGIN_DIR` (preferred) |
| Env var | `HARNESS_CACHE_THRESHOLD_MS` (still honored) | `ESPALIER_CACHE_THRESHOLD_MS` (preferred) |
| Env var | `HARNESS_NONINTERACTIVE` (still honored) | `ESPALIER_NONINTERACTIVE` (preferred) |
| Post-merge hook marker | `HARNESS_BACKLINK_HOOK` (still detected) | `ESPALIER_BACKLINK_HOOK` (new installs) |

### Not breaking (intentionally preserved)

- **Sub-agent identifiers `harness-coder` / `harness-reviewer`** — internal names baked into orchestrator. Renaming would break any in-flight pipeline mid-stage.
- **`.claude/agents/harness-{coder,reviewer}.md` filenames** — match agent identifiers above.
- **Pipeline semantics** — 10 stages, gates, escalation paths, rollback rules, review cycle limits — all unchanged.
- **Typed `changes/{type}/{slug}/` layout** — preserved through rename.
- **Squash-merge decision values** — `not-needed | installed | fuzzy-allowed | skip-only | never-ask | ask-later`. Path moved (`harness/.merge-hook-decision` → `espalier/.merge-hook-decision`), content unchanged.
- **Causal links, `Follow-up Fixes` tables, `Commits` tables in `pipeline-state.md`** — history rows reference old `harness/` paths in their text columns but stay readable. Pass `--rewrite-history` to the migration script if you want history bodies updated too.
- **Legacy env vars + post-merge marker** — all `HARNESS_*` env vars and the `HARNESS_BACKLINK_HOOK` marker still recognized for graceful migration.

### Added

- **`/espalier-migrate` skill** (replaces `/harness-migrate`) — auto-detects install version (v0.1.x via missing `.merge-hook-decision`; v0.2.x–v0.3.x via present decision file with `harness/` dir; v0.4.x via `espalier/` dir) and dispatches to the correct migration script in correct order. Same dry-run-first + confirm pattern.
- **`scripts/migrate-v0.3-to-v0.4.sh`** — mechanical rename migration: `git mv harness espalier`, child-skill renames, sed cross-refs, symlink rebuild, settings.json patch, CLAUDE.md/.gitignore/post-merge-hook updates, cache regen, 12 verification checks. Idempotent + dry-run + `--rewrite-history` opt-in.
- **`docs/migrating-v0.3-to-v0.4.md`** — full rebrand migration guide with rename matrix, kept-stable list, pre-migration checklist, rollback, common issues, post-migration verification flow.

### Changed

- **`scripts/bootstrap-harness.sh` → `scripts/bootstrap-espalier.sh`** — every `harness/` path rewritten to `espalier/`, every child-skill name rewritten, plugin-dir auto-detect covers both new (`espalier-engineering`) and legacy (`harness-engineering`) install paths. `HARNESS_BACKLINK_HOOK` marker detection now accepts either variant (idempotent re-install).
- **`scripts/migrate-v0.1-to-v0.2.sh`** — plugin-dir auto-detect extended to cover the new install paths; references to `/harness-migrate` updated to `/espalier-migrate` where appropriate. The script itself remains v0.1→v0.2 only (frozen behavior); rename is a separate migration.
- **`.claude-plugin/{plugin,marketplace}.json`** — name → `espalier-engineering`, version → `0.4.0`, repo URL → `Junhanliu-dev/espalier-engineering`, description rewritten to lead with the espalier-vine metaphor.
- **All skill SKILL.md frontmatter `name:` fields** — updated to match renamed folders.
- **All template + reference + hook files** — path refs, skill name refs, slash command mentions updated. Identifier matrix:
  - **Renamed:** `harness/`, `harness-{coding,review,testing,requirements,fix}`, `harness-run`, `harness-engineering`, `harness-migrate`, `bootstrap-harness.sh`, settings.json hook paths.
  - **Untouched:** `harness-coder`, `harness-reviewer`.
- **`README.md`** — rewritten to lead with the espalier-vine metaphor (training a vine flat along a wall = training the AI flat along your codebase patterns). 30-second install up top. Slash command table. v0.4.0 breaking-change banner. Restated philosophy + 5 principles.
- **`docs/migrating-v0.1-to-v0.2.md`** — preserved (still the source of truth for the older typed-changes migration), but now cross-references the new v0.3→v0.4 guide and uses updated plugin install paths.

### Migration script test coverage

`scripts/test-bootstrap.sh` retained; updated all assertions to `espalier/` paths and `espalier-*` skill names. All 32 assertions still passing on macOS.

### Why this release

Three reasons:

1. **Brand fit.** "Harness engineering" conveyed the mechanism but felt mechanical. "Espalier" carries the same idea — training a living thing to grow along a structure — with a metaphor that maps cleanly to what the tool actually does: discover the shape your code already has, then train the AI to grow along it.
2. **Command ergonomics.** `/harness-run feat: add stripe checkout` was 8 keystrokes of overhead before the actual requirement. `/espalier feat: add stripe checkout` cuts that to 2. The full pipeline is the *main* thing this tool does; it deserves the bare verb.
3. **Path consistency.** `harness/` lived under `~/your-project/` while the plugin was named `harness-engineering`. Now everything reads `espalier-*` end to end — plugin, repo, dir, slash commands, child skills, env vars. One name, one search.

The two-track migration (`/espalier-migrate` handles both v0.1→v0.2 and v0.3→v0.4) means existing users upgrade in-place without manually editing settings.json, symlinks, or scattered string refs.

## 0.3.0 — 2026-05-19

Init-speedup release. `/harness-engineering` first run is now ~30-50% faster on a fresh repo via parallelism + a bundled bootstrap script. **Zero workflow semantic change** — every artifact in `harness/` is byte-equivalent to v0.2.x output (modulo discovery-driven substitutions).

### Added
- **`scripts/bootstrap-harness.sh`** — single idempotent bash script bundling Phase 8 (Hooks) + Phase 10 (Wiring) + Phase 11 (Validation) + pure-template copies. 11 internal stages, 7 flags, 24 parallel validation checks. Safe-symlink pre-flight, portable `abspath` (no `realpath` dependency on macOS), atomic `.claude/settings.json` merge that preserves user hooks.
- **`scripts/test-bootstrap.sh`** — 11-test smoke suite covering dry-run / full / re-run / `--force` / `--copy-only` / `--wire-only` / safe-symlink refusal / settings.json merge / portable abspath / parallel validation order / merge-decision validation. All 32 assertions passing on macOS.
- **Phase 0** in `/harness-engineering` skill — front-loaded `AskUserQuestion` (multi-question form) at init start:
  - **Q1: squash-merge decision** (relocated from Phase 10 in v0.2.x). All 6 baseline values preserved (`not-needed` / `installed` / `fuzzy-allowed` / `skip-only` / `never-ask` / `ask-later`).
  - **Q2 (new): sub-agent tool access scope.** Options: `restricted` (default — keep template `tools:` field verbatim, sub-agents limited to Read/Write/Edit/Bash/Glob/Grep) or `inherit` (drop `tools:` field — sub-agents inherit every tool the calling Claude Code session has, including MCPs/plugins/WebFetch). Useful for projects that depend on MCP-backed databases or internal-API tooling.
- **3 new discovery scouts** (1.8 data-models, 1.9 critical-paths, 1.10 external-services) — Phase 1 wiki files (`harness/wiki/data-models.md`, `critical-paths.md`, `external-services.md`) are now populated from discovery scouts in the parallel batch instead of separate sequential synthesis. No more stub regressions.
- **Phase 1.7 oracle fires ctx7 + WebSearch in parallel** — best-practices research now hits both authoritative docs (ctx7/perplexity MCP) AND the live web in a single oracle invocation. ctx7 captures official recommendations; WebSearch captures community drift / recent vulns / idioms not yet in docs. Same wall time as either alone but doubles coverage. Output JSON includes a `sources` field marking which provided each finding.
- **Parallel layer-spec scouts** — Phase 3 per-layer spec generation now fires N scouts concurrently (one per detected layer).
- **`docs/init-speedup-plan.md`** — full design doc with 12 sections + Appendix A (settings.json merge algorithm), risk register, effort estimate.

### Changed
- **`skills/harness-engineering/SKILL.md`** — collapsed from 11 sequential phases to Phase 0 (prompt) → Phase 1 (parallel discovery, 10 calls) → Phase 2 (parallel substitution writes) → Phase 3 (single `bootstrap-harness.sh` invocation). Bundle of pure-copy templates, hooks, symlinks, CLAUDE.md, settings.json, validation all happen inside the script.
- **`skills/harness-engineering/references/discovery-checklist.md`** — added "Parallel Execution Recipe" with copy-paste scout prompts for all 10 calls + scout output JSON schema + `status: no_evidence` batched follow-up rule.
- **`skills/harness-engineering/references/wiring.md`** — added v0.3.0 note: bundled into bootstrap script; manual steps retained for debug.
- **`skills/harness-engineering/references/validation.md`** — added v0.3.0 note: runs via `bootstrap-harness.sh --validate-only`; per-check table retained as source of truth.

### Performance
- Tool calls: ~110-140 sequential → ~25-35 raw calls across ~5-7 batched turns.
- Wall clock (medium repo, ~150 source files): 20+ min → 10-15 min.
- Wall clock (small repo, ~50 files): scales down proportionally.
- LLM token cost (Opus): meaningful reduction (fewer round-trips, less repeated context loading). Exact savings vary with repo size + scout depth.

Note: Earlier release notes overstated the speedup (claimed 75-80% / ~5x). Real-world runs on medium-large repos show a more modest 30-50% improvement — discovery scouts still take time reading source files, and the oracle (ctx7 + WebSearch) is single-flight with network latency. Numbers above reflect observed runs.

### Fixed (latent v0.2.x bugs surfaced during dry-run)
- **`pre-push-gate-wrapper.sh` was referenced in `.claude/settings.json` but never shipped as a template.** Result on v0.2.x: PreToolUse hook on Bash failed to find the wrapper at fire time. v0.3.0 ships `hook-templates/pre-push-gate-wrapper.sh` (parses stdin, dispatches to `pre-push-gate.sh` only for `git push` commands), bootstrap cp's it, validation Check 6 verifies it's executable.
- **`.claude/settings.json` merge was undefined in v0.2.x wiring instructions** ("create if needed" — no merge spec). Bootstrap now uses an additive merge algorithm (per `docs/init-speedup-plan.md` Appendix A): match by `(matcher, command)` tuple, atomic temp-file write, automatic backup with rotation, never overwrites user hooks.
- **`ln -sf` could silently clobber a user file at a symlink target** (e.g., if user had `.claude/rules/harness-structure.md` as a regular file pre-install). Bootstrap's `safe_ln` helper refuses with a clear error.
- **`realpath` is not portable to macOS without coreutils**. Replaced with portable `abspath()` helper using `cd && pwd`.
- **Re-run semantics were undefined** — manual instructions implied "just re-run", but symlinks would multiply, settings.json would duplicate hook entries. Bootstrap now auto-detects complete installs (presence of `harness/.merge-hook-decision`) and runs validation only. v0.1.x installs are detected via wired symlinks and blocked with a `/harness-migrate` suggestion.

### Backward compatibility
- v0.2.x installs are NOT touched. `/harness-engineering` is for fresh repos; existing installs continue working unchanged.
- `/harness-fix`, `/harness-run`, `/harness-migrate` skills unchanged. Pipeline semantics, 5-final-value merge decision, typed `harness/changes/{type}/{slug}/` layout — all preserved.
- All 6 skill folders + 2 agent files maintain `folder name == frontmatter name:` parity (verified via skill-loading dry-run).
- `.claude/settings.json` merge is additive — never overwrites user hooks (algorithm in `docs/init-speedup-plan.md` Appendix A).

### Not in this release
- Track F (small-repo content skip) was proposed but dropped during workflow-preservation audit — would have changed baseline output.
- Best-practices research opt-out (Phase 0 Q2) was proposed but dropped — Phase 1.7 always runs to preserve baseline behavior.

## 0.2.2 — 2026-05-18

Bug fix: `.gitignore` append could produce a glued line if the existing `.gitignore` was missing a trailing newline.

### Fixed
- **`.gitignore` newline guard** in `scripts/migrate-v0.1-to-v0.2.sh` AND `skills/harness-engineering/references/wiring.md` §10.8 Step 6.
  - Symptom: a target repo with `.gitignore` whose last line was `harness` (no trailing newline) and ran the migration / wiring would end up with `harnessharness/.commit-index.tsv` as a single concatenated line.
  - Fix: check `tail -c1 .gitignore` before append; insert `\n` first if needed.
  - Verified against 4 scenarios: missing newline, with newline, empty file, idempotent re-run.

### Manual fix for already-affected repos
If your `.gitignore` already has a `harnessharness/.commit-index.tsv` line, edit it by hand:
```bash
# Replace the bad line with a properly-separated one
sed -i.bak 's|harnessharness/.commit-index.tsv|harness/.commit-index.tsv|' .gitignore
# Make sure the line before is on its own
```
Then re-run `/harness-migrate` to confirm idempotency.

## 0.2.1 — 2026-05-18

Migration UX improvements for marketplace users.

### Added
- **`/harness-migrate` skill** (plugin-level, like `/harness-engineering`): wraps `scripts/migrate-v0.1-to-v0.2.sh` with auto-locate + dry-run preview + user-confirm prompt. Marketplace users no longer need to know where the plugin is installed — they invoke `/harness-migrate` from inside Claude Code.

### Changed
- **`docs/migrating-v0.1-to-v0.2.md`**: TL;DR now explicitly enumerates marketplace, manual-clone, and curl-one-shot install paths. Added "Where is the plugin installed?" table covering all 3 install methods.

### Why this patch
v0.2.0 shipped `scripts/migrate-v0.1-to-v0.2.sh` but didn't document the marketplace install path, leaving plugin users to guess where the script lived. `/harness-migrate` closes the gap.

## 0.2.0 — 2026-05-18

> **Existing v0.1.0 users**: run `bash scripts/migrate-v0.1-to-v0.2.sh` from your target project root. See [`docs/migrating-v0.1-to-v0.2.md`](./docs/migrating-v0.1-to-v0.2.md) for the full walkthrough.

### New skills
- **`/harness-fix`** — 5-stage bug-fix orchestrator with auto-link to the change that introduced the bug. Slimmer than `/harness-run` (no separate reqs review, no CI verify, no deploy verify, no user-confirm gate) but adds Stage 0 auto-link discovery.

### New layout
- Typed change directory: `harness/changes/{type}/{slug}/` (was flat `harness/changes/{slug}/`). Types: `feat/`, `fix/`, `refactor/`, `docs/`. Existing flat layouts remain readable.
- `/harness-run` now parses requirement prefix (`feat:`, `fix:`, `refactor:`, `docs:`) to derive type; defaults to `feat`.
- `pre-push-gate.sh` updated to scan typed subdirs via `find -mindepth 3 -maxdepth 3`.

### Stage 7 commit recording
- `/harness-run` and `/harness-fix` Stage 7 now record commit SHA + files into `pipeline-state.md` `## Commits` table. Drives reverse-lookup at fix-time.

### Bidirectional causal links
- Fix's `requirements.md` carries `caused_by:` frontmatter with per-entry `role` (primary/call_path) and `lookup` layer (exact/squash_hook/fuzzy/…). Stack-trace order determines role; cap=5 frames; dedupe primary>call_path.
- Causing change's `pipeline-state.md` gets a `## Follow-up Fixes` table row at the fix's Stage 7, with Role + Lookup columns for audit filtering.

### Escalation paths
- **Stage 1/3 (predictive/reactive)**: clean migration `fix/{slug}` → `feat/{slug}-fix`; preserves causal link.
- **Stage 5 (TEST_SCOPE_INFLATION)**: test sub-agent self-reports when meaningful tests cross scope; orchestrator prompts user.
- **Stage 6 (ESCALATION_REQUIRED reviewer verdict)**: reviewer can flag symptom-mask/wrong-scope/architectural concerns; orchestrator prompts user.
- **PARTIAL_FIX state**: new first-class Status. Fix ships symptom-mask; auto-creates `feat/{slug}-root-cause` skeleton; when root-cause feat completes Stage 7, reverse-links back via `## Root Cause Addressed By` table.
- **Tombstones**: when fix migrates to feat-lane, old `fix/{slug}/TOMBSTONE.md` forwards audit queries.

### Squash-merge resilience
- Init-time prompt during `/harness-engineering` Phase 10 (front-loaded per the prompt-timing principle). Decision cached in `harness/.merge-hook-decision` (one of: not-needed, installed, fuzzy-allowed, skip-only, never-ask, ask-later).
- Optional `.git/hooks/post-merge` install (husky-aware) — records `squashed_to:` mappings in causing change's pipeline-state.md when a squash commit matches by file overlap.
- Tiered reverse-lookup at fix-time: cache → exact SHA → squash_hook → fuzzy (if allowed) → unknown. Fix-time prompt fires only when decision was deferred.

### Reverse-lookup cache (Path F)
- `harness/.commit-index.tsv` — TSV cache mapping SHA → slug. Self-healing: scan misses append discovered row.
- Auto-built on first cold scan > 1s (configurable via `HARNESS_CACHE_THRESHOLD_MS`).
- Manual flags: `--build-index`, `--rebuild-index`, `--no-index`.
- `harness/hooks/rebuild-commit-index.sh` reconstructs from `pipeline-state.md` files anytime.
- Cache added to `.gitignore` (regenerable; per-machine).

### Reviewer + coder agent extensions
- `harness-reviewer.md`: new verdict `ESCALATION_REQUIRED` + required `## Escalation Reason` section format.
- `harness-coder.md`: new `### Test Scope Signal` self-report block for fix-lane Stage 5.

### Validation
- 13 new verification rows (12-24): typed layout, harness-fix presence, merge-hook decision cached, hook templates copied, cache hooks executable, .gitignore wired.
- 7 manual integration tests (A causal-link, B escalation, C pre-push, D-F squash resilience variants, G cache).

### Files added
- `skills/harness-engineering/templates/skills/harness-fix.md`
- `skills/harness-engineering/hook-templates/post-merge-backlink.sh`
- `skills/harness-engineering/hook-templates/lookup-helpers.sh`
- `skills/harness-engineering/hook-templates/rebuild-commit-index.sh`
- `CHANGELOG.md`
- `docs/plan.md` (implementation rationale; ~2270 lines)

### Files edited
- `skills/harness-engineering/SKILL.md` (Phase 3 table, layout diagram)
- `skills/harness-engineering/templates/skills/harness-run.md` (typed paths, Stage 7 commit + reverse-link to PARTIAL_FIX)
- `skills/harness-engineering/templates/pipeline.md` (Stage 7 output)
- `skills/harness-engineering/templates/agent.md` (Config Index Fix row)
- `skills/harness-engineering/templates/agents/harness-reviewer.md` (ESCALATION_REQUIRED verdict)
- `skills/harness-engineering/templates/agents/harness-coder.md` (TEST_SCOPE_INFLATION signal)
- `skills/harness-engineering/hook-templates/pre-push-gate.sh` (recursive find with BSD/GNU stat compat)
- `skills/harness-engineering/references/wiring.md` (10.2 fix-symlink, 10.6 typed dirs + lazy mkdir, 10.7 chmod expanded, 10.8 NEW merge-strategy prompt + hook install + cache .gitignore)
- `skills/harness-engineering/references/validation.md` (rows 12-24, integration tests A-G index)
- `README.md` (fix lane mention, optional unidecode dep, status line)
- `.claude-plugin/plugin.json` (0.1.0 → 0.2.0)
- `.claude-plugin/marketplace.json` (0.1.0 → 0.2.0)

### Optional runtime dependency
- `unidecode` (Python) — Unicode → ASCII transliteration in `/harness-fix` slug derivation. Falls back to ASCII-strip if missing.

### Breaking changes
- None. Typed layout is additive; legacy `harness/changes/{slug}/` directories from v0.1.0 remain readable. New work lands in typed dirs.

## 0.1.0 — 2026-05-15

Initial release.
