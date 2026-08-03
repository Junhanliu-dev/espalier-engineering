# Phase 11: Validation (Dry Run)

> **v0.4.0+ note:** Phase 11 runs via `scripts/bootstrap-espalier.sh` (Stage 11 of that script — 46 checks when only claude is targeted, 51 with codex: all but #25 in parallel, #25 run serially so its per-tier table reaches stdout). Normal flow invokes this automatically. Manual usage: `bash scripts/bootstrap-espalier.sh --validate-only --plugin-dir=...` to re-run only the validation block (e.g., after manual file edits); add `--ignore-drift` to downgrade check #25's expired-drift hard fail to a logged override.
>
> **Platform gating (v0.14.0):** the platform set comes from `--platforms` unioned with `espalier/.platforms`. When claude is NOT targeted, checks 1-5 and 8 report `OK … (skipped — claude not targeted)`, and checks 13/14/29-33/35 swap their `.claude/…` paths for the `espalier/…` source equivalents. Checks 47-51 run only when codex IS targeted (claude-only installs still print exactly 46 lines — byte-stable with pre-v0.14 output).

> **This table mirrors bootstrap-espalier.sh Stage 11 — update BOTH in the same commit.**

After all generation and wiring is complete, validate end-to-end.

## Final Wiring Verification

| # | Check name | What it runs | How to fix a failure |
|---|-----------|--------------|----------------------|
| 1 | rules-load | `ls .claude/rules/espalier-*.md` | Re-run bootstrap Stage 5 (`--wire-only`) to recreate the rule symlinks |
| 2 | skills-load | `ls -d .claude/skills/espalier-coding … espalier-audit` (all 12 skill symlinks, incl. bare `espalier`) | Re-run bootstrap Stage 5; a missing source folder means the Phase 2/Stage 3 write was skipped |
| 3 | agents-load | `ls .claude/agents/harness-coder.md harness-reviewer.md harness-security.md` | Re-run bootstrap Stage 5; missing source = Phase 2 agent write skipped |
| 4 | hooks-configured | `grep -q "espalier/hooks" .claude/settings.json` | Re-run bootstrap Stage 8 (settings merge) |
| 5 | symlinks-valid | `[ -L .claude/rules/espalier-structure.md ] && [ -e … ]` | Broken link → the target rule file is missing; re-run Phase 2 write, then Stage 5 |
| 6 | hooks-executable | `test -x` post-edit-wrapper.sh, pre-push-gate.sh, pre-push-gate-wrapper.sh | `chmod +x espalier/hooks/*.sh` (bootstrap Stage 4 does this) |
| 7 | state-template | `test -f espalier/changes/_template/pipeline-state.md` | Re-run bootstrap Stage 6 |
| 8 | claudemd-updated | `grep -q "## Espalier" CLAUDE.md` | Re-run bootstrap Stage 7 |
| 9 | espalier-agent-md | `test -f espalier/agent.md` | Re-run espalier-init Phase 2 (agent.md write) |
| 10 | espalier-pipeline-md | `test -f espalier/pipeline.md` | Re-run bootstrap Stage 3 (pure copy) |
| 11 | skill-name-parity | every `espalier/skills/*/SKILL.md` folder name == its `name:` frontmatter | Rename the folder or fix the frontmatter so they match |
| 12 | typed-changes-dirs | `[ -d espalier/changes/feat ] && fix && refactor` | Re-run bootstrap Stage 2 (mkdir) |
| 13 | espalier-fix-skill | `test -f .claude/skills/espalier-fix/SKILL.md` | Re-run bootstrap Stages 3 + 5 |
| 14 | espalier-fix-name | `grep -q "^name: espalier-fix" .claude/skills/espalier-fix/SKILL.md` | The copied template is stale/edited — recopy from the plugin |
| 15 | rules-engineering | `test -f espalier/rules/engineering-structure.md` | Re-run espalier-init Phase 2 |
| 16 | rules-standards | `test -f espalier/rules/coding-standards.md` | Re-run espalier-init Phase 2 |
| 17 | merge-decision | `.merge-hook-decision` is one of the six accepted values | Rewrite the file with a valid value (or re-run bootstrap Stage 9) |
| 18 | hook-template-copy | `test -f && test -x espalier/hooks/post-merge-backlink.sh` | Re-run bootstrap Stage 4 |
| 19 | lookup-helpers | `test -f espalier/hooks/lookup-helpers.sh` | Re-run bootstrap Stage 4 |
| 20 | post-merge-dispatcher | `ESPALIER_POSTMERGE_DISPATCH` present in git's real hooks dir (`core.hooksPath` honored) or `.husky/post-merge` | Re-run bootstrap Stage 9; if `core.hooksPath` points outside the repo, bootstrap refuses and warns — fix the config first |
| 21 | rebuild-script | `test -x espalier/hooks/rebuild-commit-index.sh` | Re-run bootstrap Stage 4 |
| 22 | gitignore-cache | `grep -qxF "espalier/.commit-index.tsv" .gitignore` | Re-run bootstrap Stage 10 |
| 23 | rebuild-runs | `bash espalier/hooks/rebuild-commit-index.sh && test -f espalier/.commit-index.tsv` | Read the script's stderr — usually a malformed pipeline-state.md |
| 24 | cache-tsv-format | every populated `.commit-index.tsv` row has 4 tab-separated fields | Delete the cache and re-run the rebuild script |
| 25 | stale-tiers (serial — `run_check_25`) | reads `espalier/.drift-state.tsv`; per-tier table; fails only on expired (>90d) artifacts | Run `/espalier-prune --all-stale`, or `--ignore-drift` to log an override |
| 26 | drift-state-format | every populated `.drift-state.tsv` row has 4 tab-separated fields | Fix or delete the malformed row (see `.drift.log` for its origin) |
| 27 | conventions-format | every populated `.conventions.tsv` row has 5 or 6 tab-separated fields | Fix or delete the malformed row |
| 28 | doctor-cadence | `.doctor-cadence` absent, or `cadence:` is a known value | Rewrite the file (`cadence: weekly` etc.) |
| 29 | espalier-ask-skill | `test -f .claude/skills/espalier-ask/SKILL.md` | Re-run bootstrap Stages 3 + 5 |
| 30 | security-rule | `[ -L .claude/rules/espalier-security.md ] && [ -e … ]` | Re-run Phase 2 (security-standards.md) + Stage 5 |
| 31 | security-agent | `test -f .claude/agents/harness-security.md` | Re-run Phase 2 agent write + Stage 5 |
| 32 | security-skill | `test -f .claude/skills/espalier-security/SKILL.md` | Re-run Phase 2 write + Stage 5 |
| 33 | audit-skill | `test -f .claude/skills/espalier-audit/SKILL.md` | Re-run bootstrap Stages 3 + 5 |
| 34 | audit-mode | `grep -qF "## Repo-Audit Mode" espalier/agents/harness-security.md` | The agent file is stale — re-run Phase 2 from the current template |
| 35 | production-rule | `[ -L .claude/rules/espalier-production.md ] && [ -e … ]` | Re-run Phase 2 (production-standards.md) + Stage 5 |
| 36 | production-file | `test -f espalier/rules/production-standards.md` | Re-run espalier-init Phase 2 |
| 37 | scout-prompts | `test -f espalier/.scout-prompts.md` | Re-run bootstrap Stage 3 |
| 38 | phase2-coding-skill | `test -f espalier/skills/espalier-coding/SKILL.md` | Re-run espalier-init Phase 2 (LLM write) |
| 39 | phase2-review-skill | `test -f espalier/skills/espalier-review/SKILL.md` | Re-run espalier-init Phase 2 (LLM write) |
| 40 | phase2-testing-skill | `test -f espalier/skills/espalier-testing/SKILL.md` | Re-run espalier-init Phase 2 (LLM write) |
| 41 | wiki-architecture | `test -f espalier/wiki/architecture.md` | Re-run espalier-init Phase 2 (scout 1.2 → wiki write) |
| 42 | wiki-data-models | `test -f espalier/wiki/data-models.md` | Re-run espalier-init Phase 2 (scout 1.8 → wiki write) |
| 43 | wiki-critical-paths | `test -f espalier/wiki/critical-paths.md` | Re-run espalier-init Phase 2 (scout 1.9 → wiki write) |
| 44 | wiki-external-services | `test -f espalier/wiki/external-services.md` | Re-run espalier-init Phase 2 (scout 1.10 → wiki write) |
| 45 | rules-development-process | `test -f espalier/rules/development-process.md` | Re-run espalier-init Phase 2 (LLM write) |
| 46 | layer-boundaries-hook | `test -f && test -x espalier/hooks/check-layer-boundaries.sh` | Phase 2 writes it for typescript/python/go; `--lang=unsupported` makes bootstrap write a no-op; `chmod +x` if present but not executable |
| 47 | codex-skills-load *(codex only)* | `ls -d .agents/skills/espalier-coding … espalier-audit` (all 12 skill symlinks) | Re-run bootstrap Stage 5 with `--platforms=codex` (or `claude,codex`) |
| 48 | codex-symlinks-valid *(codex only)* | `[ -L .agents/skills/espalier ] && [ -e … ]` | Broken link → source skill folder missing; re-run Stage 3/Phase 2, then Stage 5 |
| 49 | codex-agents-toml *(codex only)* | `name = "harness-…"` present in all three `.codex/agents/harness-*.toml` | Re-run bootstrap Stage 8c (delete the bad file first — stage is write-if-absent) |
| 50 | codex-hooks-configured *(codex only)* | `grep -q "espalier/hooks" .codex/config.toml` | Re-run bootstrap Stage 8b; if a stale `ESPALIER HOOKS` marker exists without the commands, delete the block and re-run |
| 51 | codex-agentsmd *(codex only)* | `grep -q "## Espalier" AGENTS.md` | Re-run bootstrap Stage 7b |

**Policy 3 — staleness tiers (check #25):** an artifact's age is measured from
its `stale_first_seen` timestamp — fresh (<14d, silent), aging (14–30d, INFO),
stale (30–60d, WARN), critical (60–90d, loud WARN), expired (>90d, check #25
fails). Thresholds are hardcoded in v1.

## End-to-End Checks

1. **Trace a simple requirement** through all 10 stages mentally
2. **Verify all cross-references resolve:**
   - pipeline.md references skills → skills exist
   - agent.md references rules → rules exist
   - coding SKILL.md references specs → specs exist
   - sub-agents reference skills → skills exist
   - **every skill folder name equals its SKILL.md `name:` frontmatter**
3. **Check for contradictions:**
   - coding-standards.md vs. layer specs (no conflicts?)
   - pipeline gates vs. development-process (aligned?)
4. **Test hooks:**
   - Create a file violating layer boundaries → hook blocks (exit 2, stderr)
   - Attempt push at Stage 2 → gate blocks (exit 2, stderr)
5. **Session resumption test:**
   - Create a pipeline-state.md at Stage 3
   - Run `/espalier` → it should resume, not restart

## Manual Integration Tests (run after generation + wiring)

Quick summary:

| Test | Purpose | Tripwire |
|------|---------|----------|
| A | Causal-link round-trip | Fix's caused_by → causing feat's Follow-up Fixes |
| B | Stage 1/3 escalation | Rename + reset + tombstone |
| C | Pre-push gate | Blocks at Stage <7, passes at ≥7 |
| D | Squash hook recording | post-merge writes `squashed_to:` row |
| E | Squash skip-only path | Marks `unknown_squash`, fix proceeds |
| F | ask-later fallback | Orchestrator prompt fires once; subsequent invocations silent |
| G | Reverse-lookup cache | Cold scan auto-builds; Layer 0 hit on second invocation; --no-index bypass; --rebuild-index works |

Report: "Espalier validated. {N} checks passed, {M} issues found: {list}"
