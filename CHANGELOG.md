# Changelog

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
