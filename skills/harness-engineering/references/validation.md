# Phase 11: Validation (Dry Run)

After all generation and wiring is complete, validate end-to-end.

## Final Wiring Verification

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Rules auto-load | `ls -la .claude/rules/harness-*` | 3 symlinks |
| 2 | Skills discoverable | `ls -la .claude/skills/harness-*` | 5 symlinks |
| 3 | Agents registered | `ls -la .claude/agents/harness-*` | 2 symlinks |
| 4 | Hooks configured | `cat .claude/settings.json \| grep harness` | Hook entries |
| 5 | Symlinks valid | `readlink .claude/rules/harness-structure.md` | Points to harness/ |
| 6 | Hooks executable | `test -x harness/hooks/check-layer-boundaries.sh` | Exit 0 |
| 7 | Pipeline state template | `cat harness/changes/_template/pipeline-state.md` | Template content |
| 8 | CLAUDE.md updated | `grep "harness" CLAUDE.md` | Reference found |
| 9 | Build command works | `{build_command}` | Exit 0 |
| 10 | Test command works | `{test_command}` | Exit 0 with count > 0 |
| 11 | Skill folder/name parity | `for f in harness/skills/*/SKILL.md; do dir=$(basename $(dirname "$f")); name=$(grep '^name:' "$f" \| awk '{print $2}'); [ "$dir" = "$name" ] \|\| echo "MISMATCH $dir != $name"; done` | No output (all match) |
| 12 | Typed changes layout | `find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md` | All state files at depth 3 under `{type}/{slug}/` |
| 13 | harness-fix skill present | `ls .claude/skills/harness-fix/SKILL.md` | Symlink resolves |
| 14 | harness-fix folder/name parity | `grep '^name:' .claude/skills/harness-fix/SKILL.md` | `name: harness-fix` |
| 15 | Pre-push gate finds typed paths | (manual — see Test C) | Gate reads correct state file |
| 16 | Commits table format (when present) | `grep -A2 '## Commits' harness/changes/*/*/pipeline-state.md 2>/dev/null \|\| true` | Either header rows visible OR clean exit (no fixes shipped yet) |
| 17 | Merge-hook decision cached | `cat harness/.merge-hook-decision` | One of: not-needed, installed, fuzzy-allowed, skip-only, never-ask, ask-later |
| 18 | Hook template copied | `test -f harness/hooks/post-merge-backlink.sh && test -x harness/hooks/post-merge-backlink.sh` | Exit 0 |
| 19 | Lookup helpers present | `test -f harness/hooks/lookup-helpers.sh` | Exit 0 |
| 20 | If decision=installed → hook live | `[ "$(cat harness/.merge-hook-decision)" = "installed" ] && grep -q HARNESS_BACKLINK_HOOK .git/hooks/post-merge .husky/post-merge 2>/dev/null` | Match found (or N/A if decision ≠ installed) |
| 21 | Rebuild script present + executable | `test -x harness/hooks/rebuild-commit-index.sh` | Exit 0 |
| 22 | .gitignore excludes cache | `grep -qxF "harness/.commit-index.tsv" .gitignore` | Exit 0 |
| 23 | Manual rebuild produces valid cache | `bash harness/hooks/rebuild-commit-index.sh && test -f harness/.commit-index.tsv` | All exit 0 |
| 24 | Cache TSV format valid | `[ ! -s harness/.commit-index.tsv ] || awk -F'\t' 'NF != 4 { exit 1 }' harness/.commit-index.tsv` | Exit 0 (empty file allowed; all populated rows have 4 tab-separated fields) |

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
   - Run `/harness-run` → it should resume, not restart

## Manual Integration Tests (run after generation + wiring)

Full test bodies in the harness-engineering repo at `docs/plan.md` §10.3 (https://github.com/Junhanliu-dev/harness-engineering/blob/main/docs/plan.md). Quick summary:

| Test | Purpose | Tripwire |
|------|---------|----------|
| A | Causal-link round-trip | Fix's caused_by → causing feat's Follow-up Fixes |
| B | Stage 1/3 escalation | Rename + reset + tombstone |
| C | Pre-push gate | Blocks at Stage <7, passes at ≥7 |
| D | Squash hook recording | post-merge writes `squashed_to:` row |
| E | Squash skip-only path | Marks `unknown_squash`, fix proceeds |
| F | ask-later fallback | Prompt fires once; subsequent invocations silent |
| G | Reverse-lookup cache | Cold scan auto-builds; Layer 0 hit on second invocation; --no-index bypass; --rebuild-index works |

Report: "Harness validated. {N} checks passed, {M} issues found: {list}"
