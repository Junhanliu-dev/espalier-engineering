# Phase 11: Validation (Dry Run)

> **v0.4.0+ note:** Phase 11 runs via `scripts/bootstrap-espalier.sh` (Stage 11 of that script — 28 checks: 27 in parallel, plus #25 run serially so its per-tier table reaches stdout). Normal flow invokes this automatically. Manual usage: `bash scripts/bootstrap-espalier.sh --validate-only --plugin-dir=...` to re-run only the validation block (e.g., after manual file edits); add `--ignore-drift` to downgrade check #25's expired-drift hard fail to a logged override. The per-check table below describes what each check verifies and is retained as the source of truth for the check definitions.

After all generation and wiring is complete, validate end-to-end.

## Final Wiring Verification

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Rules auto-load | `ls -la .claude/rules/espalier-*` | 3 symlinks |
| 2 | Skills discoverable | `ls -la .claude/skills/espalier*` | 6 symlinks (incl. bare `espalier`) |
| 3 | Agents registered | `ls -la .claude/agents/harness-*` | 2 symlinks (names kept for stability) |
| 4 | Hooks configured | `cat .claude/settings.json \| grep espalier` | Hook entries |
| 5 | Symlinks valid | `readlink .claude/rules/espalier-structure.md` | Points to espalier/ |
| 6 | Hooks executable | `test -x espalier/hooks/check-layer-boundaries.sh` | Exit 0 |
| 7 | Pipeline state template | `cat espalier/changes/_template/pipeline-state.md` | Template content |
| 8 | CLAUDE.md updated | `grep "espalier" CLAUDE.md` | Reference found |
| 9 | Build command works | `{build_command}` | Exit 0 |
| 10 | Test command works | `{test_command}` | Exit 0 with count > 0 |
| 11 | Skill folder/name parity | `for f in espalier/skills/*/SKILL.md; do dir=$(basename $(dirname "$f")); name=$(grep '^name:' "$f" \| awk '{print $2}'); [ "$dir" = "$name" ] \|\| echo "MISMATCH $dir != $name"; done` | No output (all match) |
| 12 | Typed changes layout | `find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md` | All state files at depth 3 under `{type}/{slug}/` |
| 13 | espalier-fix skill present | `ls .claude/skills/espalier-fix/SKILL.md` | Symlink resolves |
| 14 | espalier-fix folder/name parity | `grep '^name:' .claude/skills/espalier-fix/SKILL.md` | `name: espalier-fix` |
| 15 | Pre-push gate finds typed paths | (manual — see Test C) | Gate reads correct state file |
| 16 | Commits table format (when present) | `grep -A2 '## Commits' espalier/changes/*/*/pipeline-state.md 2>/dev/null \|\| true` | Either header rows visible OR clean exit (no fixes shipped yet) |
| 17 | Merge-hook decision cached | `cat espalier/.merge-hook-decision` | One of: not-needed, installed, fuzzy-allowed, skip-only, never-ask, ask-later |
| 18 | Hook template copied | `test -f espalier/hooks/post-merge-backlink.sh && test -x espalier/hooks/post-merge-backlink.sh` | Exit 0 |
| 19 | Lookup helpers present | `test -f espalier/hooks/lookup-helpers.sh` | Exit 0 |
| 20 | Post-merge dispatcher installed | `_hd=$(git config core.hooksPath); grep -qE "ESPALIER_POSTMERGE_DISPATCH" "${_hd:-.git/hooks}/post-merge" .husky/post-merge 2>/dev/null` | Match found at git's real hooks dir — `core.hooksPath` is honored. Dispatcher installed unconditionally; runs drift-detect every merge, backlink only when decision=installed. If `core.hooksPath` points outside the repo, bootstrap skips the install and warns. |
| 21 | Rebuild script present + executable | `test -x espalier/hooks/rebuild-commit-index.sh` | Exit 0 |
| 22 | .gitignore excludes cache | `grep -qxF "espalier/.commit-index.tsv" .gitignore` | Exit 0 |
| 23 | Manual rebuild produces valid cache | `bash espalier/hooks/rebuild-commit-index.sh && test -f espalier/.commit-index.tsv` | All exit 0 |
| 24 | Cache TSV format valid | `[ ! -s espalier/.commit-index.tsv ] || awk -F'\t' 'NF != 4 { exit 1 }' espalier/.commit-index.tsv` | Exit 0 (empty file allowed; all populated rows have 4 tab-separated fields) |
| 25 | Stale-artifact tiers (Policy 3) | (serial — `run_check_25`; reads `espalier/.drift-state.tsv`) | Per-tier table; exit 0 unless an artifact is expired (>90d). `--ignore-drift` downgrades the hard fail to a logged override |
| 26 | Drift-state TSV structural | `[ ! -s espalier/.drift-state.tsv ] \|\| awk -F'\t' 'NF != 4 { exit 1 }' espalier/.drift-state.tsv` | Exit 0 (absent/empty allowed; every row has 4 tab-separated fields) |
| 27 | Conventions TSV structural | `[ ! -s espalier/.conventions.tsv ] \|\| awk -F'\t' 'NF != 5 && NF != 6 { exit 1 }' espalier/.conventions.tsv` | Exit 0 (absent/empty allowed; every row has 5 or 6 tab-separated fields) |
| 28 | Doctor cadence valid | `[ ! -f espalier/.doctor-cadence ] \|\| grep -qE '^cadence: (every-change\|weekly\|monthly\|manual)$' espalier/.doctor-cadence` | Exit 0 (absent allowed; if present, `cadence:` is a known value) |

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
   - Create a file violating layer boundaries → hook blocks
   - Attempt push at Stage 2 → gate blocks
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
| F | ask-later fallback | Prompt fires once; subsequent invocations silent |
| G | Reverse-lookup cache | Cold scan auto-builds; Layer 0 hit on second invocation; --no-index bypass; --rebuild-index works |

Report: "Espalier validated. {N} checks passed, {M} issues found: {list}"
