# Changelog

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

- **`skills/espalier-migrate/SKILL.md`** — Step 2 located the plugin scripts with a hard-coded list of guessed paths (`~/.claude/plugins/<name>`, `~/repos/...`, `~/SBM_Projects/...`). None matched Claude Code's actual marketplace layout (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so `/espalier-migrate` either failed outright for a normal install, or — if a same-named dev checkout happened to sit in `$HOME` — silently ran *that* checkout's scripts instead of the installed plugin. It now derives the plugin root from `${CLAUDE_SKILL_DIR}` (the skill's own directory, set by Claude Code), which resolves the installed plugin in every layout.
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
