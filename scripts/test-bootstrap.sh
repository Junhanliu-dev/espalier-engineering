#!/bin/bash
# Smoke tests for bootstrap-espalier.sh.
#
# Creates temp repos, simulates the LLM Write batch (writes minimal placeholder
# substitution files), invokes bootstrap, and asserts:
#   - dry-run is a no-op
#   - --copy-only / --wire-only / full all produce expected state
#   - re-run on complete install runs validation only
#   - safe-symlink refuses to clobber user files
#   - settings.json merge preserves user hooks
#   - portable abspath works without realpath binary
#   - parallel validation produces sorted output + correct exit code
#   - core.hooksPath honored (inside-repo install; outside-repo refusal)
#
# Usage: bash scripts/test-bootstrap.sh [--keep] [--verbose]

set -u

# dispatch pops a live watch TUI window on real runs — never during tests
export MAPRUN_NO_DASHBOARD=1

KEEP=no
VERBOSE=no
for arg in "$@"; do
  case "$arg" in
    --keep)    KEEP=yes ;;
    --verbose) VERBOSE=yes ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/bootstrap-espalier.sh"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../skills/espalier-init" && pwd)"
PASS=0
FAIL=0
FAILED_TESTS=()

assert() {
  local name=$1 cmd=$2
  if eval "$cmd" >/dev/null 2>&1; then
    [ "$VERBOSE" = "yes" ] && echo "  OK   $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL $name"
    [ "$VERBOSE" = "yes" ] && eval "$cmd"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name")
  fi
}

make_smoke_repo() {
  local dir=$1
  rm -rf "$dir"
  mkdir -p "$dir"
  ( cd "$dir" && git init --quiet --initial-branch=main )
  echo "# Smoke test repo" > "$dir/README.md"
  ( cd "$dir" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init" )
}

# Simulate LLM Write batch: write minimal substitution files.
# Bootstrap creates parent dirs in Stage 2 (mkdir -p), so we use a thin sim:
# call --copy-only first to create dirs, then write our placeholders.
simulate_llm_writes() {
  local dir=$1 lang=$2
  ( cd "$dir" && bash "$BOOTSTRAP" --copy-only --lang="$lang" --plugin-dir="$PLUGIN_DIR" >/dev/null 2>&1 )

  # Rules (substitution)
  cat > "$dir/espalier/rules/engineering-structure.md" << 'EOF'
# Engineering Structure
## Language & Stack
- Language: test
EOF
  cat > "$dir/espalier/rules/coding-standards.md"      << 'EOF'
# Coding Standards
EOF
  cat > "$dir/espalier/rules/development-process.md"   << 'EOF'
# Development Process
EOF

  # Orchestrator
  echo "# Agent" > "$dir/espalier/agent.md"

  # Skill SKILL.md files (substitution)
  for s in espalier-coding espalier-review espalier-testing; do
    cat > "$dir/espalier/skills/$s/SKILL.md" << EOF
---
name: $s
description: smoke test
---
EOF
  done

  # Sub-agents (names kept as harness-coder/harness-reviewer)
  cat > "$dir/espalier/agents/harness-coder.md" << 'EOF'
---
name: harness-coder
description: smoke
tools: Read, Write
---
EOF
  cat > "$dir/espalier/agents/harness-reviewer.md" << 'EOF'
---
name: harness-reviewer
description: smoke
tools: Read
---
EOF
  # v0.9.0 security substitution files (checks 30-32, 34)
  cat > "$dir/espalier/agents/harness-security.md" << 'EOF'
---
name: harness-security
description: smoke
tools: Read
---
## Repo-Audit Mode
EOF
  cat > "$dir/espalier/rules/security-standards.md" << 'EOF'
# Security Standards
EOF
  # production-standards.md is a Phase-2 substitution file (checks 35-36)
  cat > "$dir/espalier/rules/production-standards.md" << 'EOF'
# Production Standards
EOF
  mkdir -p "$dir/espalier/skills/espalier-security"
  cat > "$dir/espalier/skills/espalier-security/SKILL.md" << 'EOF'
---
name: espalier-security
description: smoke test
---
EOF

  # Wiki
  for f in architecture data-models critical-paths external-services; do
    echo "# $f" > "$dir/espalier/wiki/$f.md"
  done

  # Substitution hooks
  cat > "$dir/espalier/hooks/pre-push-gate.sh" << 'EOF'
#!/bin/bash
# Smoke pre-push gate
exit 0
EOF
  cat > "$dir/espalier/hooks/check-layer-boundaries.sh" << 'EOF'
#!/bin/bash
# Smoke boundary check
exit 0
EOF
}

# ─── Test 1: --dry-run is a no-op ─────────────────────────────────────────
echo "Test 1: --dry-run"
TMP=$(mktemp -d -t smoke1.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && bash "$BOOTSTRAP" --dry-run --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
assert "dry-run made no espalier/" "[ ! -d '$TMP/espalier' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 2: Full happy path (R1 — single invocation) ─────────────────────
echo "Test 2: full single invocation (R1)"
TMP=$(mktemp -d -t smoke2.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
EXIT=$?
assert "bootstrap exit 0"                 "[ $EXIT -eq 0 ]"
assert "espalier/pipeline.md exists"       "[ -f '$TMP/espalier/pipeline.md' ]"
assert "espalier/skills/espalier/SKILL.md exists"     "[ -f '$TMP/espalier/skills/espalier/SKILL.md' ]"
assert "espalier/skills/espalier-fix/SKILL.md exists" "[ -f '$TMP/espalier/skills/espalier-fix/SKILL.md' ]"
assert ".claude/rules symlinks exist"     "[ -L '$TMP/.claude/rules/espalier-structure.md' ]"
assert ".claude/skills/espalier-coding link" "[ -L '$TMP/.claude/skills/espalier-coding' ]"
assert ".claude/skills/espalier (main) link" "[ -L '$TMP/.claude/skills/espalier' ]"
assert "espalier-prune skill copied"        "[ -f '$TMP/espalier/skills/espalier-prune/SKILL.md' ]"
assert ".claude/skills/espalier-prune link" "[ -L '$TMP/.claude/skills/espalier-prune' ]"
assert "espalier-doctor skill copied"       "[ -f '$TMP/espalier/skills/espalier-doctor/SKILL.md' ]"
assert ".claude/skills/espalier-doctor link" "[ -L '$TMP/.claude/skills/espalier-doctor' ]"
assert "espalier-ask skill copied"          "[ -f '$TMP/espalier/skills/espalier-ask/SKILL.md' ]"
assert ".claude/skills/espalier-ask link"   "[ -L '$TMP/.claude/skills/espalier-ask' ]"
assert "espalier-audit skill copied"        "[ -f '$TMP/espalier/skills/espalier-audit/SKILL.md' ]"
assert ".claude/skills/espalier-audit link" "[ -L '$TMP/.claude/skills/espalier-audit' ]"
assert ".claude/agents/harness-security link" "[ -L '$TMP/.claude/agents/harness-security.md' ]"
assert ".claude/rules/espalier-production link" "[ -L '$TMP/.claude/rules/espalier-production.md' ]"
assert "scout-prompts shipped"              "[ -f '$TMP/espalier/.scout-prompts.md' ]"
assert ".doctor-cadence written"            "grep -q '^cadence: ' '$TMP/espalier/.doctor-cadence'"
assert ".claude/agents/harness-coder link"  "[ -L '$TMP/.claude/agents/harness-coder.md' ]"
assert "pre-push-gate.sh executable (R10)"      "[ -x '$TMP/espalier/hooks/pre-push-gate.sh' ]"
assert "check-layer-boundaries.sh executable"   "[ -x '$TMP/espalier/hooks/check-layer-boundaries.sh' ]"
assert "post-edit-wrapper.sh executable"        "[ -x '$TMP/espalier/hooks/post-edit-wrapper.sh' ]"
assert "merge decision persisted"               "grep -q ask-later '$TMP/espalier/.merge-hook-decision'"
assert "CLAUDE.md has Espalier section"         "grep -q '## Espalier' '$TMP/CLAUDE.md'"
assert ".claude/settings.json valid JSON"       "python3 -c 'import json,sys; json.load(open(\"$TMP/.claude/settings.json\"))'"
assert "gitignore has cache entry"              "grep -qxF 'espalier/.commit-index.tsv' '$TMP/.gitignore'"
assert "drift-detect.sh copied"                 "[ -f '$TMP/espalier/hooks/drift-detect.sh' ]"
assert "drift-helpers.sh copied"                "[ -f '$TMP/espalier/hooks/drift-helpers.sh' ]"
assert "parse-drift-blocks.py copied"           "[ -f '$TMP/espalier/hooks/parse-drift-blocks.py' ]"
assert "post-merge dispatcher installed"        "grep -q 'ESPALIER_POSTMERGE_DISPATCH' '$TMP/.git/hooks/post-merge'"
assert "gitignore has drift-state glob"         "grep -qxF 'espalier/.drift-state.tsv*' '$TMP/.gitignore'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 3: Idempotent re-run (detects complete install → validate only) ─
echo "Test 3: re-run on complete install"
TMP=$(mktemp -d -t smoke3.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
RERUN_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes 2>&1 )
RERUN_EXIT=$?
assert "re-run exit 0"                          "[ $RERUN_EXIT -eq 0 ]"
assert "re-run detected complete install"       "echo \"\$RERUN_OUT\" | grep -q 'Existing complete install'"
assert "re-run ran validation only"             "echo \"\$RERUN_OUT\" | grep -q 'Validation:'"
# Regression: a re-run must not nest a self-symlink inside each skill dir.
# Pre-fix, `ln -sf` dereferenced the existing .claude/skills/<X> symlink-to-dir
# and dropped espalier/skills/<X>/<X> -> <X>. -type l at depth 2 catches only
# that — SKILL.md is a file, specs/ is a real dir.
assert "re-run left no nested skill symlinks"   "[ -z \"\$(find '$TMP/espalier/skills' -mindepth 2 -maxdepth 2 -type l)\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 4: --force overrides re-run detection ───────────────────────────
echo "Test 4: --force override"
TMP=$(mktemp -d -t smoke4.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
FORCE_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 )
assert "--force does NOT trigger re-run path"   "echo \"\$FORCE_OUT\" | grep -qv 'Existing complete install'"
assert "--force re-run left no nested symlinks" "[ -z \"\$(find '$TMP/espalier/skills' -mindepth 2 -maxdepth 2 -type l)\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 5: --copy-only debug flag still works ──────────────────────────
echo "Test 5: --copy-only debug flag"
TMP=$(mktemp -d -t smoke5.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && bash "$BOOTSTRAP" --copy-only --lang=py --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
assert "copy-only created espalier/pipeline.md"  "[ -f '$TMP/espalier/pipeline.md' ]"
assert "copy-only did NOT create symlinks"      "[ ! -L '$TMP/.claude/rules/espalier-structure.md' ] || [ ! -e '$TMP/.claude/rules/espalier-structure.md' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 6: --wire-only debug flag still works ──────────────────────────
echo "Test 6: --wire-only debug flag"
TMP=$(mktemp -d -t smoke6.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && bash "$BOOTSTRAP" --copy-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
WIRE_EXIT=$?
assert "wire-only exit 0"                       "[ $WIRE_EXIT -eq 0 ]"
assert "wire-only created symlinks"             "[ -L '$TMP/.claude/rules/espalier-structure.md' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 7: safe_ln refuses to clobber regular file ─────────────────────
echo "Test 7: safe_ln pre-flight"
TMP=$(mktemp -d -t smoke7.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
mkdir -p "$TMP/.claude/rules"
echo "user content" > "$TMP/.claude/rules/espalier-structure.md"  # regular file, not symlink
SAFE_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "safe_ln blocked regular file"           "echo \"\$SAFE_OUT\" | grep -q 'exists as regular file'"
assert "user file preserved"                    "[ \"\$(cat '$TMP/.claude/rules/espalier-structure.md')\" = 'user content' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 8: settings.json merge preserves user hooks ─────────────────────
echo "Test 8: settings.json merge"
TMP=$(mktemp -d -t smoke8.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "echo user-hook"}]}]
  }
}
EOF
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "user hook survived merge"               "grep -q 'echo user-hook' '$TMP/.claude/settings.json'"
assert "Espalier hook added"                    "grep -q 'post-edit-wrapper' '$TMP/.claude/settings.json'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 9: portable abspath (no realpath binary needed) ────────────────
echo "Test 9: portable abspath"
TMP=$(mktemp -d -t smoke9.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
# Force absence of realpath by running with restricted PATH
( cd "$TMP" && env PATH="/usr/bin:/bin" bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
ABS_EXIT=$?
assert "bootstrap works without realpath"       "[ $ABS_EXIT -eq 0 ]"
assert "symlink target is relative"             "case \"\$(readlink '$TMP/.claude/rules/espalier-structure.md')\" in ../*) true ;; *) false ;; esac"
# D1: a moved repo keeps every link resolving (relative targets).
MOVED="$TMP-moved"
mv "$TMP" "$MOVED"
DANGLING=$( cd "$MOVED" && find .claude -type l ! -exec test -e {} \; -print )
assert "moved repo: all symlinks resolve"       "[ -z \"\$DANGLING\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$MOVED"

# ─── Test 10: parallel validation output is sorted ────────────────────────
echo "Test 10: parallel validation output order"
TMP=$(mktemp -d -t smoke10.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
VAL_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --validate-only --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes 2>&1 )
# Check that check numbers appear in order (1/24 before 2/24, etc.)
FIRST=$(echo "$VAL_OUT" | grep -oE '\[[0-9]+/52\]' | head -3 | sed 's/\[//;s/\/52\]//' | tr '\n' ' ')
assert "validation output sorted ascending"     "[ \"\$FIRST\" = '1 2 3 ' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 11: --merge-decision validation ─────────────────────────────────
echo "Test 11: merge-decision validation"
TMP=$(mktemp -d -t smoke11.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
INVALID_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=garbage --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "rejects invalid merge-decision"         "echo \"\$INVALID_OUT\" | grep -q \"invalid --merge-decision='garbage'\""
MISSING_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "rejects missing merge-decision"         "echo \"\$MISSING_OUT\" | grep -q 'required for mode'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 12: core.hooksPath honored ──────────────────────────────────────
echo "Test 12: core.hooksPath honored"

# 12a — core.hooksPath set INSIDE the repo: the dispatcher must land in that
#       dir, NOT in .git/hooks, and validation check 20 must still pass.
TMP=$(mktemp -d -t smoke12a.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && mkdir -p .githooks && git config core.hooksPath .githooks )
simulate_llm_writes "$TMP" typescript
HP_IN=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 )
assert "12a Stage 9 logged hooksPath resolution" "echo \"\$HP_IN\" | grep -q 'core.hooksPath set'"
assert "12a dispatcher at core.hooksPath dir"    "grep -q 'ESPALIER_POSTMERGE_DISPATCH' '$TMP/.githooks/post-merge'"
assert "12a nothing written to .git/hooks"       "[ ! -f '$TMP/.git/hooks/post-merge' ]"
assert "12a check 20 passed"                     "echo \"\$HP_IN\" | grep -qF '[20/52] OK'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# 12b — core.hooksPath set OUTSIDE the repo: bootstrap must refuse to install,
#       warn, write nothing, and validation check 20 must fail (honest red).
TMP=$(mktemp -d -t smoke12b.XXXX)
OUTSIDE=$(mktemp -d -t smoke12bout.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && git config core.hooksPath "$OUTSIDE" )
simulate_llm_writes "$TMP" typescript
HP_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "12b warns hooksPath outside repo"        "echo \"\$HP_OUT\" | grep -q 'points outside this repo'"
assert "12b no dispatcher in outside dir"        "[ ! -f '$OUTSIDE/post-merge' ]"
assert "12b no dispatcher in .git/hooks"         "[ ! -f '$TMP/.git/hooks/post-merge' ]"
assert "12b check 20 failed (honest red)"        "echo \"\$HP_OUT\" | grep -qF '[20/52] FAIL'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$OUTSIDE"

# ─── Test 13: --lang=unsupported writes a no-op boundary hook ─────────────
echo "Test 13: --lang=unsupported no-op hook"
TMP=$(mktemp -d -t smoke13.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
# The unsupported path must provide the hook itself: remove the simulated one.
rm -f "$TMP/espalier/hooks/check-layer-boundaries.sh"
( cd "$TMP" && bash "$BOOTSTRAP" --lang=unsupported --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "13a no-op hook exists"       "[ -f '$TMP/espalier/hooks/check-layer-boundaries.sh' ]"
assert "13b no-op hook executable"   "[ -x '$TMP/espalier/hooks/check-layer-boundaries.sh' ]"
# Write-if-absent: a Phase-2-adapted hook must survive a second run untouched.
echo "# customised marker" >> "$TMP/espalier/hooks/check-layer-boundaries.sh"
( cd "$TMP" && bash "$BOOTSTRAP" --lang=unsupported --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "13c second run does not overwrite a modified hook" \
  "grep -q 'customised marker' '$TMP/espalier/hooks/check-layer-boundaries.sh'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 14: --platforms=claude,codex wires both platforms ───────────────
echo "Test 14: --platforms=claude,codex"
TMP=$(mktemp -d -t smoke14.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
P_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude,codex --yes --force 2>&1 )
P_EXIT=$?
assert "14a exit 0"                          "[ $P_EXIT -eq 0 ]"
assert "14b .agents/skills/espalier link"    "[ -L '$TMP/.agents/skills/espalier' ] && [ -e '$TMP/.agents/skills/espalier' ]"
assert "14c .agents/skills/espalier-fix link" "[ -L '$TMP/.agents/skills/espalier-fix' ]"
assert "14d .claude wiring still present"    "[ -L '$TMP/.claude/skills/espalier' ]"
assert "14e AGENTS.md Espalier section"      "grep -q '## Espalier' '$TMP/AGENTS.md'"
assert "14f AGENTS.md platform mapping"      "grep -q 'Platform mapping (Codex)' '$TMP/AGENTS.md'"
assert "14g codex config hook block"         "grep -q 'espalier/hooks/post-edit-wrapper.sh' '$TMP/.codex/config.toml'"
assert "14h codex config marker"             "grep -q 'ESPALIER HOOKS v1' '$TMP/.codex/config.toml'"
assert "14i coder agent toml"                "grep -q '^name = \"harness-coder\"' '$TMP/.codex/agents/harness-coder.toml'"
assert "14j reviewer agent toml"             "[ -f '$TMP/.codex/agents/harness-reviewer.toml' ]"
assert "14k security agent toml"             "[ -f '$TMP/.codex/agents/harness-security.toml' ]"
assert "14l platforms persisted"             "grep -qx 'claude,codex' '$TMP/espalier/.platforms'"
assert "14m validation total is 57"          "echo \"\$P_OUT\" | grep -q 'Validation: 57/57 passed'"
assert "14n codex checks ran"                "echo \"\$P_OUT\" | grep -qF '[47/57] OK'"
assert "14o CLAUDE.md section still written" "grep -q '## Espalier' '$TMP/CLAUDE.md'"
# TOML sanity: python tomllib parses the generated config + agent files.
assert "14p config.toml parses"              "python3 -c 'import tomllib; tomllib.load(open(\"$TMP/.codex/config.toml\",\"rb\"))'"
assert "14q agent toml parses"               "python3 -c 'import tomllib; tomllib.load(open(\"$TMP/.codex/agents/harness-coder.toml\",\"rb\"))'"
# Idempotent re-run: no duplicate hook block, agent tomls preserved.
echo "# user tuning marker" >> "$TMP/.codex/agents/harness-coder.toml"
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --platforms=claude,codex --yes >/dev/null 2>&1 )
assert "14r re-run keeps ONE hook block"     "[ \$(grep -c '>>> ESPALIER HOOKS v1 >>>' '$TMP/.codex/config.toml') -eq 1 ]"
assert "14s re-run preserves agent tuning"   "grep -q 'user tuning marker' '$TMP/.codex/agents/harness-coder.toml'"
assert "14t re-run keeps ONE AGENTS.md section" "[ \$(grep -c '## Espalier' '$TMP/AGENTS.md') -eq 1 ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 15: codex added to legacy claude install (additive union) ───────
echo "Test 15: legacy install + --wire-only --platforms=codex"
TMP=$(mktemp -d -t smoke15.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
# Legacy claude-only install: full run WITHOUT --platforms, then delete
# .platforms to simulate a pre-v0.14 install.
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
rm -f "$TMP/espalier/.platforms"
# Add codex later: wire-only, codex flag only, no --merge-decision (reused).
W_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --platforms=codex --yes 2>&1 )
W_EXIT=$?
assert "15a wire-only exit 0"                "[ $W_EXIT -eq 0 ]"
assert "15b merge decision reused"           "echo \"\$W_OUT\" | grep -q \"reusing persisted merge decision 'ask-later'\""
assert "15c platforms unioned to claude,codex" "grep -qx 'claude,codex' '$TMP/espalier/.platforms'"
assert "15d codex wired"                     "[ -L '$TMP/.agents/skills/espalier' ] && grep -q 'ESPALIER HOOKS' '$TMP/.codex/config.toml'"
assert "15e claude wiring untouched"         "[ -L '$TMP/.claude/skills/espalier' ] && grep -q 'espalier/hooks' '$TMP/.claude/settings.json'"
assert "15f validation total is 57"          "echo \"\$W_OUT\" | grep -q 'Validation: 57/57 passed'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 16: codex-only install (no .claude litter, claude checks skip) ──
echo "Test 16: --platforms=codex only"
TMP=$(mktemp -d -t smoke16.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
# simulate_llm_writes' --copy-only helper ran with the claude default and made
# empty .claude/ dirs — remove them so we can assert codex-only recreates none.
rm -rf "$TMP/.claude"
C_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=codex --yes --force 2>&1 )
C_EXIT=$?
assert "16a exit 0"                          "[ $C_EXIT -eq 0 ]"
assert "16b no .claude dir created"          "[ ! -d '$TMP/.claude' ]"
assert "16c no CLAUDE.md section"            "! grep -q '## Espalier' '$TMP/CLAUDE.md' 2>/dev/null"
assert "16d codex fully wired"               "[ -L '$TMP/.agents/skills/espalier' ] && [ -f '$TMP/.codex/agents/harness-coder.toml' ] && grep -q '## Espalier' '$TMP/AGENTS.md'"
assert "16e claude checks skipped OK"        "echo \"\$C_OUT\" | grep -qF 'OK   rules-load (skipped — claude not targeted)'"
assert "16f validation passes"               "echo \"\$C_OUT\" | grep -q 'Validation: 57/57 passed'"
assert "16g platforms = codex"               "grep -qx 'codex' '$TMP/espalier/.platforms'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 17: --platforms=all wires claude+codex+copilot ──────────────────
echo "Test 17: --platforms=all (three platforms)"
TMP=$(mktemp -d -t smoke17.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
A_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=all --yes --force 2>&1 )
A_EXIT=$?
assert "17a exit 0"                            "[ $A_EXIT -eq 0 ]"
assert "17b platforms normalized+persisted"    "grep -qx 'claude,codex,copilot' '$TMP/espalier/.platforms'"
assert "17c .github/skills/espalier link"      "[ -L '$TMP/.github/skills/espalier' ] && [ -e '$TMP/.github/skills/espalier' ]"
assert "17d copilot agents written"            "grep -q '^name: harness-coder' '$TMP/.github/agents/harness-coder.agent.md' && [ -f '$TMP/.github/agents/harness-reviewer.agent.md' ] && [ -f '$TMP/.github/agents/harness-security.agent.md' ]"
assert "17e hooks json valid + adapter wired"  "python3 -c 'import json; json.load(open(\"$TMP/.github/hooks/espalier-gates.json\"))' && grep -q 'copilot-hook-adapter' '$TMP/.github/hooks/espalier-gates.json'"
assert "17f adapter copied + executable"       "[ -x '$TMP/espalier/hooks/copilot-hook-adapter.sh' ]"
assert "17g copilot-instructions section"      "grep -q '## Espalier' '$TMP/.github/copilot-instructions.md'"
assert "17h claude + codex wiring intact"      "[ -L '$TMP/.claude/skills/espalier' ] && [ -L '$TMP/.agents/skills/espalier' ]"
assert "17i validation total is 62"            "echo \"\$A_OUT\" | grep -q 'Validation: 62/62 passed'"
assert "17j copilot checks ran"                "echo \"\$A_OUT\" | grep -qF '[52/62] OK'"
# Idempotent re-run: sections/files not duplicated, user tuning preserved.
echo "<!-- user tuning marker -->" >> "$TMP/.github/agents/harness-coder.agent.md"
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --platforms=all --yes >/dev/null 2>&1 )
assert "17k re-run keeps ONE instructions section" "[ \$(grep -c '^## Espalier' '$TMP/.github/copilot-instructions.md') -eq 1 ]"
assert "17l re-run preserves agent tuning"     "grep -q 'user tuning marker' '$TMP/.github/agents/harness-coder.agent.md'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 18: copilot-only (no .claude litter, claude+codex checks skip) ──
echo "Test 18: --platforms=copilot only"
TMP=$(mktemp -d -t smoke18.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
rm -rf "$TMP/.claude"
P_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=copilot --yes --force 2>&1 )
P_EXIT=$?
assert "18a exit 0"                          "[ $P_EXIT -eq 0 ]"
assert "18b no .claude dir created"          "[ ! -d '$TMP/.claude' ]"
assert "18c no AGENTS.md written"            "[ ! -f '$TMP/AGENTS.md' ]"
assert "18d copilot fully wired"             "[ -L '$TMP/.github/skills/espalier' ] && [ -f '$TMP/.github/agents/harness-coder.agent.md' ] && grep -q '## Espalier' '$TMP/.github/copilot-instructions.md'"
assert "18e claude checks skipped OK"        "echo \"\$P_OUT\" | grep -qF 'OK   rules-load (skipped — claude not targeted)'"
assert "18f codex checks skipped OK"         "echo \"\$P_OUT\" | grep -qF 'OK   codex-skills-load (skipped — codex not targeted)'"
assert "18g validation total is 62"          "echo \"\$P_OUT\" | grep -q 'Validation: 62/62 passed'"
assert "18h platforms = copilot"             "grep -qx 'copilot' '$TMP/espalier/.platforms'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 19: .gitattributes union entry + canonical-ref config keys ──────
echo "Test 19: gitattributes + canonical config keys"
TMP=$(mktemp -d -t smoke19.XXXX)
make_smoke_repo "$TMP"
echo "*.bin binary" > "$TMP/.gitattributes"   # pre-existing user content
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "19a ask-gaps union attribute appended" \
  "grep -qxF 'espalier/.ask-gaps.tsv merge=union' '$TMP/.gitattributes'"
assert "19b pre-existing gitattributes content preserved" \
  "grep -qxF '*.bin binary' '$TMP/.gitattributes'"
assert "19c no other union attribute shipped (conventions/doctor-stamp excluded)" \
  "[ \"\$(grep -c 'merge=union' '$TMP/.gitattributes')\" = '1' ]"
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
assert "19d re-run adds nothing twice" \
  "[ \"\$(grep -cxF 'espalier/.ask-gaps.tsv merge=union' '$TMP/.gitattributes')\" = '1' ]"
assert "19e canonical-remote key written (printf-appended after quoted heredoc)" \
  "grep -q '^canonical-remote: origin$' '$TMP/espalier/.espalier-config'"
assert "19f canonical-branch key written (no remote HEAD → main fallback)" \
  "grep -q '^canonical-branch: main$' '$TMP/espalier/.espalier-config'"
assert "19g caps heredoc still intact ahead of the appended keys" \
  "grep -q '^max-code-rounds: 3$' '$TMP/espalier/.espalier-config'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# Preserve-if-exists branch: a pre-existing config keeps its values and gains
# ONLY the missing canonical keys.
TMP=$(mktemp -d -t smoke19b.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
mkdir -p "$TMP/espalier"
printf 'max-code-rounds: 5\ncanonical-remote: upstream\n' > "$TMP/espalier/.espalier-config"
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "19h user-tuned key preserved"                "grep -q '^max-code-rounds: 5$' '$TMP/espalier/.espalier-config'"
assert "19i present canonical key NOT overwritten"   "grep -q '^canonical-remote: upstream$' '$TMP/espalier/.espalier-config'"
assert "19j missing canonical key appended"          "grep -q '^canonical-branch: main$' '$TMP/espalier/.espalier-config'"
assert "19k no duplicate canonical keys"             "[ \"\$(grep -c '^canonical-remote:' '$TMP/espalier/.espalier-config')\" = '1' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 20: CODEOWNERS generation (marker block, GitHub search order) ───
echo "Test 20: CODEOWNERS generation"
TMP=$(mktemp -d -t smoke20.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --codeowners-rules=alice --codeowners-wiki=@docs-team --yes --force >/dev/null 2>&1 )
assert "20a CODEOWNERS created at .github/ (GitHub search order)" \
  "[ -f '$TMP/.github/CODEOWNERS' ]"
assert "20b rules handle normalized to @alice" \
  "grep -q '^espalier/rules/ @alice$' '$TMP/.github/CODEOWNERS'"
assert "20c wiki handle kept as @docs-team" \
  "grep -q '^espalier/wiki/ @docs-team$' '$TMP/.github/CODEOWNERS'"
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=typescript --plugin-dir="$PLUGIN_DIR" --codeowners-rules=alice --codeowners-wiki=@docs-team --yes >/dev/null 2>&1 )
assert "20d re-run keeps ONE marker block" \
  "[ \"\$(grep -c '>>> ESPALIER OWNERS v1 >>>' '$TMP/.github/CODEOWNERS')\" = '1' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# Existing root CODEOWNERS is the target (first in search order when .github/
# has none) and user lines survive outside the markers.
TMP=$(mktemp -d -t smoke20b.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
echo "* @global-owner" > "$TMP/CODEOWNERS"
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --codeowners-rules=@alice --yes --force >/dev/null 2>&1 )
assert "20e existing root CODEOWNERS edited in place"  "grep -q 'ESPALIER OWNERS v1' '$TMP/CODEOWNERS'"
assert "20f user line outside markers untouched"       "grep -qxF '* @global-owner' '$TMP/CODEOWNERS'"
assert "20g no .github/CODEOWNERS created over it"     "[ ! -f '$TMP/.github/CODEOWNERS' ]"
assert "20h unanswered wiki handle → line omitted"     "! grep -q 'espalier/wiki/' '$TMP/CODEOWNERS'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# No handles → sub-step no-ops, nothing written.
TMP=$(mktemp -d -t smoke20c.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "20i skip path writes no CODEOWNERS" \
  "[ ! -f '$TMP/.github/CODEOWNERS' ] && [ ! -f '$TMP/CODEOWNERS' ] && [ ! -f '$TMP/docs/CODEOWNERS' ]"
# Dry-run stays truthful for the new Stage 10 writes.
TMPD=$(mktemp -d -t smoke20d.XXXX)
make_smoke_repo "$TMPD"
( cd "$TMPD" && bash "$BOOTSTRAP" --dry-run --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --codeowners-rules=@alice --yes >/dev/null 2>&1 )
assert "20j dry-run writes neither gitattributes nor CODEOWNERS" \
  "[ ! -f '$TMPD/.gitattributes' ] && [ ! -f '$TMPD/.github/CODEOWNERS' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMPD"

# ─── Test 21: linked-worktree install (hooks land in the COMMON git dir) ──
echo "Test 21: linked worktree bootstrap"
TMP=$(mktemp -d -t smoke21.XXXX)
make_smoke_repo "$TMP"
WT="$TMP-wt"
( cd "$TMP" && git worktree add -b wt-branch "$WT" >/dev/null 2>&1 )
simulate_llm_writes "$WT" typescript
WT_OUT=$( cd "$WT" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 )
WT_EXIT=$?
assert "21a bootstrap from linked worktree exits 0"    "[ $WT_EXIT -eq 0 ]"
assert "21b dispatcher installed in the COMMON hooks dir" \
  "grep -q 'ESPALIER_POSTMERGE_DISPATCH' '$TMP/.git/hooks/post-merge'"
assert "21c full validation passes in the worktree"    "echo \"\$WT_OUT\" | grep -q 'Validation: 52/52 passed'"
assert "21d check 20 passes in the worktree"           "echo \"\$WT_OUT\" | grep -qF '[20/52] OK'"
[ "$KEEP" != "yes" ] && rm -rf "$WT" "$TMP"

# ─── Test 22: migration v0.15.0 → v0.16.0 (synthetic fixture) ─────────────
echo "Test 22: migrate-v0.15.0-to-v0.16.0.sh fixture"
MIGRATE="$SCRIPT_DIR/migrate-v0.15.0-to-v0.16.0.sh"
TMP=$(mktemp -d -t smoke22.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
# Regress the install to a v0.15.0 shape: strip every v0.16 artifact.
rm -f "$TMP/.gitattributes"
grep -v '^canonical-' "$TMP/espalier/.espalier-config" | grep -v '^# Canonical' > "$TMP/cfg.tmp" \
  && mv "$TMP/cfg.tmp" "$TMP/espalier/.espalier-config"
for f in pipeline.md skills/espalier/SKILL.md skills/espalier-fix/SKILL.md \
         skills/espalier-prune/SKILL.md skills/espalier-doctor/SKILL.md hooks/drift-helpers.sh; do
  echo "# pre-v0.16 stub" > "$TMP/espalier/$f"
done
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "v0.15 fixture" )
FIX_SNAP=$(cd "$TMP" && git status --porcelain | sort)
M_DRY=$( cd "$TMP" && bash "$MIGRATE" --dry-run --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
FIX_AFTER=$(cd "$TMP" && git status --porcelain | sort)
assert "22a dry-run mentions the plan"        "echo \"\$M_DRY\" | grep -qi 'dry'"
assert "22b dry-run writes nothing"           "[ \"\$FIX_SNAP\" = \"\$FIX_AFTER\" ]"
M_OUT=$( cd "$TMP" && bash "$MIGRATE" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M_EXIT=$?
assert "22c apply exits 0"                    "[ $M_EXIT -eq 0 ]"
assert "22d gitattributes marker landed"      "grep -qxF 'espalier/.ask-gaps.tsv merge=union' '$TMP/.gitattributes'"
assert "22e canonical keys landed"            "grep -q '^canonical-remote: ' '$TMP/espalier/.espalier-config' && grep -q '^canonical-branch: ' '$TMP/espalier/.espalier-config'"
assert "22f Maintenance Commits section landed" "grep -q 'ESPALIER MAINTENANCE COMMITS v1' '$TMP/espalier/rules/development-process.md'"
assert "22g pure-copy files refreshed"        "grep -q 'conv_fold' '$TMP/espalier/skills/espalier/SKILL.md' && grep -q 'conv_fold' '$TMP/espalier/hooks/drift-helpers.sh'"
assert "22h customised files backed up on diff" "[ -f '$TMP/espalier/pipeline.md.pre-v0.16.bak' ]"
M_RERUN=$( cd "$TMP" && bash "$MIGRATE" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "22i re-run is a no-op"                "echo \"\$M_RERUN\" | grep -qi 'nothing to do'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# Partial-apply: config keys + attribute pre-seeded (e.g. by an earlier
# bootstrap --force with the new plugin) — the surgical rule edit must still land.
TMP=$(mktemp -d -t smoke22b.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
# development-process.md lacks the section (simulate_llm_writes' minimal file),
# attribute + keys are present from the v0.16 bootstrap — a two-marker detector
# would falsely report done.
M_PART=$( cd "$TMP" && bash "$MIGRATE" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "22j partial-apply still applies the surgical edit" \
  "grep -q 'ESPALIER MAINTENANCE COMMITS v1' '$TMP/espalier/rules/development-process.md'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 23: A3/A5 insertion points present in installed skill text ──────
# Prompt-flow behavior itself can't be unit-tested mechanically (recorded
# exception) — these greps pin the six insertion points instead.
echo "Test 23: multi-dev insertion points in generated text"
TMP=$(mktemp -d -t smoke23.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "23a prune: lane table + worktree flow" \
  "grep -q 'Multi-Developer Discipline' '$TMP/espalier/skills/espalier-prune/SKILL.md' && grep -q 'git worktree add' '$TMP/espalier/skills/espalier-prune/SKILL.md'"
assert "23b prune: conflict recipe (checkout --theirs)" \
  "grep -q 'checkout --theirs' '$TMP/espalier/skills/espalier-prune/SKILL.md'"
assert "23c doctor: singleton lane text" \
  "grep -q 'Multi-Developer Discipline' '$TMP/espalier/skills/espalier-doctor/SKILL.md'"
assert "23d espalier: promotion feature-branch lane + race guard" \
  "grep -q 'Branch lane (multi-dev)' '$TMP/espalier/skills/espalier/SKILL.md' && grep -q 'FETCH_HEAD:espalier/.conventions.tsv' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "23e espalier: unattended Stage 0 continues to Stage 1" \
  "grep -q 'continue to\\s*$' '$TMP/espalier/skills/espalier/SKILL.md' || grep -q 'continue to Stage 1' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "23f fix lane: unattended Stage 0 continues to Auto-Link Discovery" \
  "grep -q 'Stage 0 Auto-Link' '$TMP/espalier/skills/espalier-fix/SKILL.md' && grep -q 'not Stage 1' '$TMP/espalier/skills/espalier-fix/SKILL.md'"
assert "23g fix lane: cross-branch slug-collision pointer" \
  "grep -q 'Slug collisions across branches' '$TMP/espalier/skills/espalier-fix/SKILL.md'"
assert "23h pipeline: maintenance section + slug recipe" \
  "grep -q 'Multi-Developer Maintenance' '$TMP/espalier/pipeline.md' && grep -q 'rebuild-commit-index.sh' '$TMP/espalier/pipeline.md'"
assert "23i development-process template: Maintenance Commits anchor" \
  "grep -q 'ESPALIER MAINTENANCE COMMITS v1' '$PLUGIN_DIR/templates/rules/development-process.md'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 24: B-team text + migration v0.16.0 → v0.17.0 fixture ───────────
echo "Test 24: v0.17.0 gardener/per-key text + migration fixture"
MIGRATE17="$SCRIPT_DIR/migrate-v0.16.0-to-v0.17.0.sh"
TMP=$(mktemp -d -t smoke24.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
# B-team generated-text pins (rota, defaults flip, stamp protocol, playbooks).
assert "24a doctor skill carries the shared-stamp protocol" \
  "grep -q '.doctor-stamp' '$TMP/espalier/skills/espalier-doctor/SKILL.md' && grep -q 'doctor_stamp_shared' '$TMP/espalier/skills/espalier-doctor/SKILL.md'"
assert "24b doctor skill states the restamp-clean end-of-session rule" \
  "grep -qi 're-run' '$TMP/espalier/skills/espalier-doctor/SKILL.md' && grep -q 'clean' '$TMP/espalier/skills/espalier-doctor/SKILL.md'"
assert "24c stamp-conflict one-liner present (keep the newer line)" \
  "grep -qi 'keep the newer line' '$TMP/espalier/skills/espalier-doctor/SKILL.md'"
assert "24d prune skill names the gardener rota" \
  "grep -qi 'gardener' '$TMP/espalier/skills/espalier-prune/SKILL.md'"
assert "24e same-key observation-append playbook (keep both lines)" \
  "grep -qi 'keep both lines' '$TMP/espalier/pipeline.md'"
assert "24f Stage 0 default flips to Proceed with rota pointer (full lane)" \
  "grep -qi 'gardener rota' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "24g Stage 0 default flips to Proceed with rota pointer (fix lane)" \
  "grep -qi 'gardener rota' '$TMP/espalier/skills/espalier-fix/SKILL.md'"
assert "24h promotion flip text targets the key file" \
  "grep -q 'conventions/k-' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "24i race guard reads the per-key file first" \
  "grep -q 'FETCH_HEAD:espalier/conventions/k-' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "24j tracked stamp not gitignored in a fresh install" \
  "( cd '$TMP' && ! git check-ignore -q espalier/.doctor-stamp )"

# Migration fixture: regress the v0.17 install to a v0.16 shape.
for f in pipeline.md skills/espalier/SKILL.md skills/espalier-fix/SKILL.md \
         skills/espalier-prune/SKILL.md skills/espalier-doctor/SKILL.md hooks/drift-helpers.sh; do
  echo "# pre-v0.17 stub" > "$TMP/espalier/$f"
done
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "v0.16 fixture" )
S24=$(cd "$TMP" && git status --porcelain | sort)
M17_DRY=$( cd "$TMP" && bash "$MIGRATE17" --dry-run --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
S24B=$(cd "$TMP" && git status --porcelain | sort)
assert "24k dry-run writes nothing"          "[ \"\$S24\" = \"\$S24B\" ]"
M17_OUT=$( cd "$TMP" && bash "$MIGRATE17" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M17_RC=$?
assert "24l apply exits 0"                   "[ $M17_RC -eq 0 ]"
assert "24m pure-copy files refreshed to v0.17" \
  "grep -q 'doctor_stamp_shared' '$TMP/espalier/hooks/drift-helpers.sh' && grep -qi 'gardener' '$TMP/espalier/skills/espalier-prune/SKILL.md'"
assert "24n customised files backed up on diff" "[ -f '$TMP/espalier/pipeline.md.pre-v0.17.bak' ]"
M17_RERUN=$( cd "$TMP" && bash "$MIGRATE17" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "24o re-run is a no-op"               "echo \"\$M17_RERUN\" | grep -qi 'nothing to do'"
# Hand-added ignore line must make the migration fail its gitignore assert.
echo "espalier/.doctor-stamp" >> "$TMP/.gitignore"
for f in pipeline.md; do echo "# stub again" > "$TMP/espalier/$f"; done
M17_BAD=$( cd "$TMP" && bash "$MIGRATE17" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1; echo "RC=$?" )
assert "24p ignored .doctor-stamp is refused at run time" \
  "echo \"\$M17_BAD\" | grep -q 'RC=1' && echo \"\$M17_BAD\" | grep -qi 'doctor-stamp'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 25: v0.18.0 map lane — wiring, greenfield, migration ────────────
echo "Test 25: v0.18.0 map lane (wiring + greenfield + migration)"
MIGRATE18="$SCRIPT_DIR/migrate-v0.17.0-to-v0.18.0.sh"

# 25a-h: fresh full install (all platforms) carries the map lane end to end.
TMP=$(mktemp -d -t smoke25.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
M25_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=all --yes --force 2>&1 )
assert "25a map skill copied"            "grep -q '^name: espalier-map' '$TMP/espalier/skills/espalier-map/SKILL.md'"
assert "25b map skill linked (all three)" "[ -L '$TMP/.claude/skills/espalier-map' ] && [ -L '$TMP/.agents/skills/espalier-map' ] && [ -L '$TMP/.github/skills/espalier-map' ]"
assert "25c map-guard executable"        "[ -x '$TMP/espalier/hooks/map-guard.sh' ]"
assert "25d settings.json map-guard entry" "grep -q 'map-guard' '$TMP/.claude/settings.json'"
assert "25e codex map-guard block"       "grep -q 'ESPALIER MAP GUARD v1' '$TMP/.codex/config.toml' && python3 -c 'import tomllib; tomllib.load(open(\"$TMP/.codex/config.toml\",\"rb\"))'"
assert "25f copilot gates map-guard"     "grep -q 'map-guard' '$TMP/.github/hooks/espalier-gates.json' && python3 -c 'import json; json.load(open(\"$TMP/.github/hooks/espalier-gates.json\"))'"
assert "25g max-open-tickets key"        "grep -q '^max-open-tickets: 9' '$TMP/espalier/.espalier-config'"
assert "25h checks 59+60 pass"           "echo \"\$M25_OUT\" | grep -qF '[59/62] OK' && echo \"\$M25_OUT\" | grep -qF '[60/62] OK'"
assert "25i maps dir created"            "[ -d '$TMP/espalier/maps' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# 25j-n: greenfield Pass 1 — no Phase 2 writes; placeholder gate; skips render.
TMP=$(mktemp -d -t smoke25g.XXXX)
make_smoke_repo "$TMP"
G25_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=unsupported --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --greenfield --yes --force 2>&1 )
G25_RC=$?
assert "25j greenfield bootstrap exits 0"  "[ $G25_RC -eq 0 ]"
assert "25k .greenfield marker recorded"   "[ -f '$TMP/espalier/.greenfield' ]"
assert "25l placeholder gate present"      "grep -q 'greenfield placeholder' '$TMP/espalier/hooks/pre-push-gate.sh'"
assert "25m phase2 checks render as skips" "echo \"\$G25_OUT\" | grep -qF 'phase2-coding-skill (skipped — pending greenfield Pass 2)'"
assert "25n greenfield validation passes"  "echo \"\$G25_OUT\" | grep -q 'Validation: 52/52 passed'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# 25o-t: migration v0.17.0 → v0.18.0 fixture — strip v0.18 bits from a fresh
# install, migrate, verify, re-run is a no-op.
TMP=$(mktemp -d -t smoke25m.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )
( cd "$TMP" \
  && rm -rf espalier/skills/espalier-map espalier/hooks/map-guard.sh espalier/maps .claude/skills/espalier-map \
  && grep -v 'mode=decision' espalier/skills/espalier-grill/SKILL.md > g.tmp && mv g.tmp espalier/skills/espalier-grill/SKILL.md \
  && grep -v '^max-open-tickets' espalier/.espalier-config > c.tmp && mv c.tmp espalier/.espalier-config )
M18_DRY=$( cd "$TMP" && bash "$MIGRATE18" --dry-run --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "25o dry-run lists missing markers"  "echo \"\$M18_DRY\" | grep -q 'espalier-map lane skill'"
assert "25p dry-run creates nothing"        "[ ! -f '$TMP/espalier/hooks/map-guard.sh' ]"
M18_OUT=$( cd "$TMP" && bash "$MIGRATE18" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M18_RC=$?
assert "25q apply exits 0"                  "[ $M18_RC -eq 0 ]"
assert "25r skill + guard + link installed" "grep -q '^name: espalier-map' '$TMP/espalier/skills/espalier-map/SKILL.md' && [ -x '$TMP/espalier/hooks/map-guard.sh' ] && [ -L '$TMP/.claude/skills/espalier-map' ]"
assert "25s config + settings wired"        "grep -q '^max-open-tickets:' '$TMP/espalier/.espalier-config' && grep -q 'map-guard' '$TMP/.claude/settings.json'"
M18_RERUN=$( cd "$TMP" && bash "$MIGRATE18" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "25t re-run is a no-op"              "echo \"\$M18_RERUN\" | grep -qi 'nothing to do'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 26: v0.19.0 run lane — wiring, engine, dispatch e2e, migration ──
echo "Test 26: v0.19.0 run lane (wiring + engine + stub-CLI dispatch + migration)"
MIGRATE19="$SCRIPT_DIR/migrate-v0.18.0-to-v0.19.0.sh"
TMP=$(mktemp -d -t smoke26.XXXX)
rm -rf "$TMP/../wt26"   # stale worktrees from an aborted prior run poison the resume path
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )
assert "26a run skill copied + linked" \
  "grep -q '^name: espalier-maprun' '$TMP/espalier/skills/espalier-maprun/SKILL.md' && [ -L '$TMP/.claude/skills/espalier-maprun' ]"
assert "26b maprun engine present + executable" \
  "[ -f '$TMP/espalier/hooks/maprun.py' ] && [ -x '$TMP/espalier/hooks/maprun-dispatch.sh' ] && [ -x '$TMP/espalier/hooks/maprun-verify.sh' ]"

# Stub CLI: a fake `claude` that reads the outcome path out of the -p prompt
# and writes the sentinel the mode asks for. Dispatch runs it via PATH.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" << 'FAKECLI'
#!/bin/bash
PROMPT="${2:-}"
OUT=$(printf '%s' "$PROMPT" | grep -o 'espalier/changes/[^ ]*\.maprun-outcome' | head -1)
sleep "${FAKE_CLAUDE_SLEEP:-1}"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1}'
[ -z "$OUT" ] && exit 0
case "${FAKE_CLAUDE_MODE:-pass}" in
  park)
    printf 'Q: which index?\n' > "$(dirname "$OUT")/.maprun-question.md"
    printf 'PARKED\n' > "$OUT" ;;
  *)
    # Commit real work like a real worker would — merge/verify need commits.
    echo "stub work $$" > "stub-work.txt"
    git add -A >/dev/null 2>&1
    git -c user.email=w@t -c user.name=w commit -qm "feat: stub work" >/dev/null 2>&1
    printf 'PASSED\n' > "$OUT" ;;
esac
FAKECLI
chmod +x "$TMP/bin/claude"

# Map fixture: two tickets, FILED skeletons committed on main (the base branch).
mkdir -p "$TMP/espalier/maps/m26/plan" \
         "$TMP/espalier/changes/feat/2026-01-01-alpha" "$TMP/espalier/changes/feat/2026-01-01-beta"
for s in alpha beta; do
  printf -- '---\ncharted_from: maps/m26\n---\n# req %s\n' "$s" > "$TMP/espalier/changes/feat/2026-01-01-$s/requirements.md"
  printf '# Pipeline State\n\n## Status\n- Current Stage: 0\n- Status: FILED\n' > "$TMP/espalier/changes/feat/2026-01-01-$s/pipeline-state.md"
done
cat > "$TMP/espalier/maps/m26/plan/plan.json" << 'PLAN26'
{
  "map": "m26", "integration_branch": "feat/m26", "base_branch": "main",
  "concurrency": 2, "worktree_root": "../wt26",
  "worker_platform": "claude", "worker_mode": "session", "model": "opus",
  "workspaces": [], "union_merge": [], "worker_env": {"CI": "1"},
  "verify": {"commands": [{"name": "smoke", "dir": ".", "run": "true"}]},
  "tickets": [
    {"key": "a", "slug": "2026-01-01-alpha", "name": "Alpha", "deps": [], "requirement": "feat: alpha"},
    {"key": "b", "slug": "2026-01-01-beta", "name": "Beta", "deps": ["a"], "requirement": "feat: beta"}
  ]
}
PLAN26
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "m26 fixture" )
MP="$TMP/espalier/maps/m26"
assert "26c init + frontier" \
  "( cd '$TMP' && python3 espalier/hooks/maprun.py '$MP' init >/dev/null && [ \"\$(python3 espalier/hooks/maprun.py '$MP' frontier)\" = 'a' ] )"
assert "26d invalid mark rejected" \
  "! ( cd '$TMP' && python3 espalier/hooks/maprun.py '$MP' mark a BOGUS >/dev/null 2>&1 )"
assert "26d2 pause empties frontier; resume restores it" \
  "( cd '$TMP' && python3 espalier/hooks/maprun.py '$MP' pause hold >/dev/null && [ -z \"\$(python3 espalier/hooks/maprun.py '$MP' frontier)\" ] && python3 espalier/hooks/maprun.py '$MP' status | grep -q PAUSED && python3 espalier/hooks/maprun.py '$MP' resume >/dev/null && [ \"\$(python3 espalier/hooks/maprun.py '$MP' frontier)\" = 'a' ] )"

# 26e-i: session-mode dispatch end to end with the stub CLI.
D26=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-dispatch.sh "$MP" a 2>&1 )
assert "26e dispatch records DISPATCHED + pid + worktree" \
  "python3 -c \"import json;s=json.load(open('$MP/plan/state.json'))['tickets']['a'];assert s['status']=='DISPATCHED' and s['pid'] and s['worktree']\""
SENT="$TMP/../wt26/m26/a/espalier/changes/feat/2026-01-01-alpha/.maprun-outcome"
for i in $(seq 1 20); do [ -f "$SENT" ] && break; sleep 1; done
assert "26f stub worker wrote PASSED sentinel"  "grep -q PASSED '$SENT'"
assert "26g heartbeat written by supervisor"    "[ -s '$MP/plan/logs/a.heartbeat' ]"
assert "26g2 push block is worktree-scoped (shared config untouched)" \
  "[ -z \"\$(git -C '$TMP' config remote.origin.pushurl 2>/dev/null)\" ] && [ \"\$(git -C '$TMP/../wt26/m26/a' config remote.origin.pushurl)\" = 'blocked://maprun-forbids-push' ]"
R26=$( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP" reap 2>&1 )
assert "26h reap classifies PASSED"             "echo \"\$R26\" | grep -q 'a: → PASSED'"
assert "26i merge + verify pass" \
  "( cd '$TMP' && bash espalier/hooks/maprun-merge.sh '$MP' a >/dev/null 2>&1 && python3 espalier/hooks/maprun.py '$MP' mark a MERGED >/dev/null && bash espalier/hooks/maprun-verify.sh '$MP' >/dev/null 2>&1 )"

# 26j-l: resume path — stale sentinel removed, uncommitted work checkpointed.
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP" mark a TODO >/dev/null )
echo "half-written" > "$TMP/../wt26/m26/a/scratch.txt"
printf 'STALE\n' > "$SENT"   # distinct stale verdict; dispatch must remove it
D26B=$( cd "$TMP" && PATH="$TMP/bin:$PATH" FAKE_CLAUDE_SLEEP=4 bash espalier/hooks/maprun-dispatch.sh "$MP" a 2>&1 )
assert "26j stale sentinel cleared on re-dispatch"  "! grep -q STALE '$SENT' 2>/dev/null"
assert "26k uncommitted work auto-checkpointed" \
  "( cd '$TMP/../wt26/m26/a' && git log --oneline -3 | grep -q 'wip(maprun)' )"
for i in $(seq 1 20); do [ -f "$SENT" ] && break; sleep 1; done
assert "26l re-dispatched worker completed"         "grep -q PASSED '$SENT'"
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP" reap >/dev/null 2>&1 && python3 espalier/hooks/maprun.py "$MP" mark a MERGED >/dev/null )

# 26m-o: question channel — worker parks in ITS worktree; reap collects.
D26C=$( cd "$TMP" && PATH="$TMP/bin:$PATH" FAKE_CLAUDE_MODE=park bash espalier/hooks/maprun-dispatch.sh "$MP" b 2>&1 )
BSENT="$TMP/../wt26/m26/b/espalier/changes/feat/2026-01-01-beta/.maprun-outcome"
for i in $(seq 1 20); do [ -f "$BSENT" ] && break; sleep 1; done
R26C=$( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP" reap 2>&1 )
assert "26m reap parks the ticket"          "echo \"\$R26C\" | grep -q 'b: → PARKED'"
assert "26n question collected master-side" \
  "[ -f '$MP/plan/questions/b.md' ] && [ ! -f '$TMP/../wt26/m26/b/espalier/changes/feat/2026-01-01-beta/.maprun-question.md' ]"
D26D=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-dispatch.sh "$MP" b 2>&1; echo "RC=$?" )
assert "26o dispatch refuses while question unanswered (exit 4)" \
  "echo \"\$D26D\" | grep -q 'RC=4'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP/../wt26" "$TMP"   # worktrees FIRST — $TMP/.. is unresolvable once $TMP is gone

# 26u-w: staged worker mode — the wrapper loops one session per stage group.
TMP=$(mktemp -d -t smoke26s.XXXX)
rm -rf "$TMP/../wt26s"   # stale worktrees from an aborted prior run poison the resume path
make_smoke_repo "$TMP"
mkdir -p "$TMP/espalier/hooks" "$TMP/espalier/maps/sm/plan" "$TMP/espalier/changes/feat/2026-01-02-gamma" "$TMP/bin"
cp "$PLUGIN_DIR/hook-templates/"maprun*.* "$TMP/espalier/hooks/"
chmod +x "$TMP/espalier/hooks/"*.sh
printf -- '---\ncharted_from: maps/sm\n---\n# req gamma\n' > "$TMP/espalier/changes/feat/2026-01-02-gamma/requirements.md"
printf '# Pipeline State\n\n## Status\n- Current Stage: 0\n- Status: FILED\n' > "$TMP/espalier/changes/feat/2026-01-02-gamma/pipeline-state.md"
cat > "$TMP/espalier/maps/sm/plan/plan.json" << 'PLAN26S'
{"map":"sm","integration_branch":"feat/sm","base_branch":"main","concurrency":1,
 "worktree_root":"../wt26s","worker_platform":"claude","worker_mode":"staged",
 "model":"opus","workspaces":[],"union_merge":[],"worker_env":{"CI":"1"},
 "tickets":[{"key":"g","slug":"2026-01-02-gamma","name":"Gamma","deps":[],"requirement":"feat: gamma"}]}
PLAN26S
cat > "$TMP/bin/claude" << 'FAKECLI2'
#!/bin/bash
# staged stub: leg 1 advances the stage to 3 (no sentinel); leg 2 writes PASSED
PROMPT="${2:-}"
OUT=$(printf '%s' "$PROMPT" | grep -o 'espalier/changes/[^ ]*\.maprun-outcome' | head -1)
STATE="$(dirname "$OUT")/pipeline-state.md"
sleep 1
CUR=$(grep -m1 '^- Current Stage:' "$STATE" | grep -o '[0-9][0-9]*' | head -1)
echo "leg saw stage=$CUR"
if [ "${CUR:-0}" -lt 3 ]; then
  sed -i '' 's/^- Current Stage:.*/- Current Stage: 3/' "$STATE" 2>/dev/null \
    || sed -i 's/^- Current Stage:.*/- Current Stage: 3/' "$STATE"
else
  printf 'PASSED\n' > "$OUT"
fi
FAKECLI2
chmod +x "$TMP/bin/claude"
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "staged fixture" )
MPS="$TMP/espalier/maps/sm"
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MPS" init >/dev/null 2>&1 )
( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-dispatch.sh "$MPS" g >/dev/null 2>&1 )
GSENT="$TMP/../wt26s/sm/g/espalier/changes/feat/2026-01-02-gamma/.maprun-outcome"
for i in $(seq 1 25); do [ -f "$GSENT" ] && break; sleep 1; done
assert "26u staged wrapper reached the sentinel"   "grep -q PASSED '$GSENT'"
assert "26v staged wrapper ran two legs"           "[ \"\$(grep -c 'leg saw stage=' '$MPS/plan/logs/g.log')\" = '2' ]"
R26S=$( cd "$TMP" && python3 espalier/hooks/maprun.py "$MPS" reap 2>&1 )
assert "26w staged outcome reaped as PASSED"       "echo \"\$R26S\" | grep -q 'g: → PASSED'"

# 26x-z: observability — feed renders stream-json human-readable; watch is read-only
cat >> "$MPS/plan/logs/g.log" << 'OBSLOG'
{"type":"system","subtype":"init","model":"claude-opus-5"}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"plan the gamma work"},{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"2 passing"}],"is_error":false}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.42}
OBSLOG
F26=$( cd "$TMP" && python3 espalier/hooks/maprun.py "$MPS" feed g 2>&1 )
assert "26x feed renders THINK/TOOL/RES lines" \
  "echo \"\$F26\" | grep -q 'THINK plan the gamma work' && echo \"\$F26\" | grep -q 'TOOL  Bash: npm test' && echo \"\$F26\" | grep -q 'RES  2 passing'"
S26_BEFORE=$(cat "$MPS/plan/state.json")
W26=$( cd "$TMP" && python3 espalier/hooks/maprun.py "$MPS" watch --once 2>&1 )
assert "26y watch --once renders a frame" \
  "echo \"\$W26\" | grep -q 'read-only view' && echo \"\$W26\" | grep -q 'PASSED     g'"
assert "26z watch mutates nothing" \
  "[ \"\$(cat '$MPS/plan/state.json')\" = \"\$S26_BEFORE\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP/../wt26s" "$TMP"   # worktrees FIRST — $TMP/.. is unresolvable once $TMP is gone

# 26p-t: migration v0.18.0 → v0.19.0 fixture.
TMP=$(mktemp -d -t smoke26m.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )
( cd "$TMP" \
  && rm -rf espalier/skills/espalier-maprun .claude/skills/espalier-maprun \
            espalier/hooks/maprun-dispatch.sh espalier/hooks/maprun-merge.sh \
            espalier/hooks/maprun-integration.sh espalier/hooks/maprun-verify.sh \
  && echo "# LOCAL ENGINE" > espalier/hooks/maprun.py \
  && grep -v espalier-maprun CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md )
M19_DRY=$( cd "$TMP" && bash "$MIGRATE19" --dry-run --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "26p dry-run lists missing markers"  "echo \"\$M19_DRY\" | grep -q 'espalier-maprun lane skill'"
assert "26q dry-run creates nothing"        "[ ! -f '$TMP/espalier/hooks/maprun-dispatch.sh' ]"
M19_OUT=$( cd "$TMP" && bash "$MIGRATE19" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M19_RC=$?
assert "26r apply exits 0 + wires the lane" \
  "[ $M19_RC -eq 0 ] && grep -q '^name: espalier-maprun' '$TMP/espalier/skills/espalier-maprun/SKILL.md' && [ -L '$TMP/.claude/skills/espalier-maprun' ] && [ -x '$TMP/espalier/hooks/maprun-dispatch.sh' ]"
assert "26s locally-adapted engine preserved" \
  "grep -q 'LOCAL ENGINE' '$TMP/espalier/hooks/maprun.py'"
M19_RERUN=$( cd "$TMP" && bash "$MIGRATE19" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "26t re-run is a no-op"              "echo \"\$M19_RERUN\" | grep -qi 'nothing to do'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 27: v0.20.0 slice PRs — engine, config hygiene, stub-gh e2e, migration ──
echo "Test 27: v0.20.0 slice PRs (maprun-pr + config hygiene + stub-gh e2e + migration)"
MIGRATE20="$SCRIPT_DIR/migrate-v0.19.0-to-v0.20.0.sh"
TMP=$(mktemp -d -t smoke27.XXXX)
rm -rf "$TMP/../wt27"   # stale worktrees from an aborted prior run poison the resume path
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )
assert "27a maprun-pr.sh shipped + executable" \
  "[ -x '$TMP/espalier/hooks/maprun-pr.sh' ]"

# Bare origin + stub gh: pushes are real (file remote), the forge is faked.
git init --bare -q "$TMP/.origin.git"
( cd "$TMP" && git remote add origin "$TMP/.origin.git" )
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" << 'FAKEGH'
#!/bin/bash
echo "gh $*" >> "${GH_LOG:?}"
case "$1" in
  auth) exit 0 ;;
  api)  echo "true" ;;
  pr)
    case "$2" in
      list)   ;;                                        # no existing PR
      create) echo "https://github.com/x/y/pull/7" ;;
    esac ;;
esac
exit 0
FAKEGH
chmod +x "$TMP/bin/gh"
export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"

cat > "$TMP/bin/claude" << 'FAKECLI'
#!/bin/bash
PROMPT="${2:-}"
OUT=$(printf '%s' "$PROMPT" | grep -o 'espalier/changes/[^ ]*\.maprun-outcome' | head -1)
sleep 1
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1}'
[ -z "$OUT" ] && exit 0
echo "stub work $$" > "stub-work.txt"
git add -A >/dev/null 2>&1
git -c user.email=w@t -c user.name=w commit -qm "feat: stub work" >/dev/null 2>&1
printf 'PASSED\n' > "$OUT"
FAKECLI
chmod +x "$TMP/bin/claude"

mkdir -p "$TMP/espalier/maps/m27/plan" "$TMP/espalier/changes/feat/2026-01-03-delta"
printf -- '---\ncharted_from: maps/m27\n---\n# req delta\n' > "$TMP/espalier/changes/feat/2026-01-03-delta/requirements.md"
printf '# Pipeline State\n\n## Status\n- Current Stage: 0\n- Status: FILED\n' > "$TMP/espalier/changes/feat/2026-01-03-delta/pipeline-state.md"
cat > "$TMP/espalier/maps/m27/plan/plan.json" << 'PLAN27'
{
  "map": "m27", "integration_branch": "feat/m27", "base_branch": "main",
  "concurrency": 1, "worktree_root": "../wt27",
  "worker_platform": "claude", "worker_mode": "session", "model": "opus",
  "workspaces": [], "union_merge": [], "worker_env": {"CI": "1"},
  "pr": { "remote": "origin", "draft": false, "labels": [] },
  "verify": {"commands": [{"name": "smoke", "dir": ".", "run": "true"}]},
  "tickets": [
    {"key": "d", "slug": "2026-01-03-delta", "name": "Delta", "deps": [], "requirement": "feat: delta"}
  ]
}
PLAN27
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "m27 fixture" )
MP27="$TMP/espalier/maps/m27"
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP27" init >/dev/null 2>&1 )

# setup: creates + pushes the integration branch before any dispatch exists
S27=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-pr.sh "$MP27" setup 2>&1 )
assert "27b setup pushes the integration branch to origin" \
  "git -C '$TMP/.origin.git' show-ref --verify --quiet refs/heads/feat/m27"

( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-dispatch.sh "$MP27" d >/dev/null 2>&1 )
DSENT="$TMP/../wt27/m27/d/espalier/changes/feat/2026-01-03-delta/.maprun-outcome"
for i in $(seq 1 20); do [ -f "$DSENT" ] && break; sleep 1; done
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP27" reap >/dev/null 2>&1 )

# open BEFORE merge: pushes the ticket branch, opens + records the slice PR
O27=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-pr.sh "$MP27" open d 2>&1 )
assert "27c open pushes the ticket branch to origin" \
  "git -C '$TMP/.origin.git' show-ref --verify --quiet refs/heads/espalier/2026-01-03-delta"
assert "27d open records the slice PR in state" \
  "python3 -c \"import json;s=json.load(open('$MP27/plan/state.json'))['tickets']['d'];assert s['pr_number']==7 and 'pull/7' in s['pr_url']\""
assert "27e status shows the PR number" \
  "( cd '$TMP' && python3 espalier/hooks/maprun.py '$MP27' status | grep -q 'PR#7' )"

( cd "$TMP" && bash espalier/hooks/maprun-merge.sh "$MP27" d >/dev/null 2>&1 \
  && python3 espalier/hooks/maprun.py "$MP27" mark d MERGED >/dev/null 2>&1 )
SY27=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-pr.sh "$MP27" sync 2>&1 )
assert "27f sync pushes the merged integration branch (slice branch contained)" \
  "[ \"\$(git -C '$TMP/.origin.git' rev-list --count 'espalier/2026-01-03-delta..feat/m27')\" -ge 1 ] \
   && [ \"\$(git -C '$TMP/.origin.git' merge-base espalier/2026-01-03-delta feat/m27)\" = \"\$(git -C '$TMP/.origin.git' rev-parse espalier/2026-01-03-delta)\" ]"

# F6 regression: creating the integration worktree (merge above) must NOT
# poison the shared git config — the master's own pushes depend on it.
assert "27g shared config never poisoned by the integration worktree" \
  "[ -z \"\$(git -C '$TMP' config remote.origin.pushurl 2>/dev/null)\" ]"
# ...and a config poisoned by a pre-v0.20 engine is healed on the next run.
( cd "$TMP" && git config remote.origin.pushurl "blocked://maprun-forbids-push" )
( cd "$TMP" && bash espalier/hooks/maprun-integration.sh "$MP27" >/dev/null 2>&1 )
assert "27h poisoned shared pushurl healed by maprun-integration.sh" \
  "[ -z \"\$(git -C '$TMP' config remote.origin.pushurl 2>/dev/null)\" ]"

F27=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-pr.sh "$MP27" final 2>&1 )
assert "27i final opens the assembly PR against the base branch" \
  "grep -q 'pr create' '$GH_LOG' && grep -q -- '--base main' '$GH_LOG' && grep -q 'map(m27)' '$GH_LOG'"

# Opt-in gate: without a `pr` key every subcommand is a silent no-op.
python3 - << PYSTRIP
import json
p = json.load(open("$MP27/plan/plan.json"))
p.pop("pr", None)
json.dump(p, open("$MP27/plan/plan.json", "w"), indent=2)
PYSTRIP
N27=$( cd "$TMP" && PATH="$TMP/bin:$PATH" bash espalier/hooks/maprun-pr.sh "$MP27" open d 2>&1; echo "RC=$?" )
assert "27j no pr config → no-op exit 0" \
  "echo \"\$N27\" | grep -q 'flow disabled' && echo \"\$N27\" | grep -q 'RC=0'"
unset GH_LOG

# 27p-r: inline worker mode — dispatch prepares the worktree, spawns NOTHING.
mkdir -p "$TMP/espalier/maps/m27i/plan" "$TMP/espalier/changes/feat/2026-01-04-echo"
printf -- '---\ncharted_from: maps/m27i\n---\n# req echo\n' > "$TMP/espalier/changes/feat/2026-01-04-echo/requirements.md"
printf '# Pipeline State\n\n## Status\n- Current Stage: 0\n- Status: FILED\n' > "$TMP/espalier/changes/feat/2026-01-04-echo/pipeline-state.md"
cat > "$TMP/espalier/maps/m27i/plan/plan.json" << 'PLAN27I'
{"map":"m27i","integration_branch":"feat/m27i","base_branch":"main","concurrency":1,
 "worktree_root":"../wt27","worker_platform":"claude","worker_mode":"inline",
 "model":"opus","workspaces":[],"union_merge":[],
 "tickets":[{"key":"e","slug":"2026-01-04-echo","name":"Echo","deps":[],"requirement":"feat: echo"}]}
PLAN27I
( cd "$TMP" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "m27i fixture" )
MP27I="$TMP/espalier/maps/m27i"
( cd "$TMP" && python3 espalier/hooks/maprun.py "$MP27I" init >/dev/null 2>&1 )
I27=$( cd "$TMP" && bash espalier/hooks/maprun-dispatch.sh "$MP27I" e 2>&1; echo "RC=$?" )
assert "27p inline dispatch prepares worktree without spawning" \
  "echo \"\$I27\" | grep -q 'RC=0' && echo \"\$I27\" | grep -q 'no worker spawned' \
   && [ -d '$TMP/../wt27/m27i/e' ] && [ ! -f '$MP27I/plan/logs/e.spawn.sh' ] && [ ! -f '$MP27I/plan/logs/e.pid' ]"
assert "27q inline dispatch marks DISPATCHED pid-less" \
  "python3 -c \"import json;s=json.load(open('$MP27I/plan/state.json'))['tickets']['e'];assert s['status']=='DISPATCHED' and not s['pid'] and s['worktree']\""
assert "27r inline worktree push-blocked, branch off integration" \
  "[ \"\$(git -C '$TMP/../wt27/m27i/e' config remote.origin.pushurl)\" = 'blocked://maprun-forbids-push' ] \
   && [ \"\$(git -C '$TMP/../wt27/m27i/e' branch --show-current)\" = 'espalier/2026-01-04-echo' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP/../wt27" "$TMP"   # worktrees FIRST — $TMP/.. is unresolvable once $TMP is gone

# 27k-n: migration v0.19.0 → v0.20.0 fixture.
TMP=$(mktemp -d -t smoke27m.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )
# Rewind to a v0.19 install: no maprun-pr.sh, a pre-slice-PR SKILL, and the
# stock v0.19 unscoped push block in maprun-integration.sh.
( cd "$TMP" \
  && rm -f espalier/hooks/maprun-pr.sh \
  && printf -- '---\nname: espalier-maprun\n---\n# v0.19 lane doc (no slice PRs)\n' > espalier/skills/espalier-maprun/SKILL.md )
cat > "$TMP/espalier/hooks/maprun-integration.sh" << 'OLDMI'
#!/usr/bin/env bash
# stock v0.19 excerpt — the unscoped push block the migration must patch
if [ ! -d "$IWT" ]; then
  git -C "$REPO" worktree add "$IWT" "$INTEGRATION" >&2
  git -C "$IWT" config remote.origin.pushurl "blocked://maprun-forbids-push" || true
  git -C "$IWT" config push.default nothing || true
fi
OLDMI
M20_DRY=$( cd "$TMP" && bash "$MIGRATE20" --dry-run --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "27k dry-run lists missing markers + patch"  \
  "echo \"\$M20_DRY\" | grep -q 'maprun-pr.sh' && echo \"\$M20_DRY\" | grep -q 'worktree scope'"
assert "27l dry-run creates nothing"        "[ ! -f '$TMP/espalier/hooks/maprun-pr.sh' ]"
M20_OUT=$( cd "$TMP" && bash "$MIGRATE20" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M20_RC=$?
assert "27m apply installs engine + patches the push block to worktree scope" \
  "[ $M20_RC -eq 0 ] && [ -x '$TMP/espalier/hooks/maprun-pr.sh' ] \
   && grep -qF 'maprun-pr.sh' '$TMP/espalier/skills/espalier-maprun/SKILL.md' \
   && grep -q -- '--worktree' '$TMP/espalier/hooks/maprun-integration.sh' \
   && [ -f '$TMP/espalier/hooks/maprun-integration.sh.pre-v0.20.bak' ]"
M20_RERUN=$( cd "$TMP" && bash "$MIGRATE20" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "27n re-run is a no-op"              "echo \"\$M20_RERUN\" | grep -qi 'nothing to do'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 28: v0.21.0 pipeline speed — context pack, delta rounds, migration ──
echo "Test 28: v0.21.0 pipeline speed (context pack + delta re-review + migration)"
MIGRATE21="$SCRIPT_DIR/migrate-v0.20.0-to-v0.21.0.sh"
TMP=$(mktemp -d -t smoke28.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" typescript
( cd "$TMP" && bash "$BOOTSTRAP" --lang=typescript --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --platforms=claude --yes --force >/dev/null 2>&1 )

assert "28a espalier SKILL carries the context-pack section" \
  "grep -qF 'Stage 3 Entry: Context Pack' '$TMP/espalier/skills/espalier/SKILL.md'"
assert "28b pipeline.md carries delta-scope doctrine + push pre-auth" \
  "grep -qF 'DELTA SCOPE' '$TMP/espalier/pipeline.md' && grep -qF 'Push-Target' '$TMP/espalier/pipeline.md'"
assert "28c agent TEMPLATES carry context-pack + delta sections" \
  "grep -qF 'CONTEXT PACK' '$SCRIPT_DIR/../skills/espalier-init/templates/agents/harness-coder.md' \
   && grep -qF 'Delta read scope' '$SCRIPT_DIR/../skills/espalier-init/templates/agents/harness-reviewer.md' \
   && grep -qF 'Delta mode (when YOUR prior round was clean)' '$SCRIPT_DIR/../skills/espalier-init/templates/agents/harness-security.md'"
assert "28d grill batching rule + fix-lane pack/pre-auth present" \
  "grep -qF 'pairwise INDEPENDENT' '$TMP/espalier/skills/espalier-grill/SKILL.md' \
   && grep -qF 'context-pack.md' '$TMP/espalier/skills/espalier-fix/SKILL.md' \
   && grep -qF 'Push-Target' '$TMP/espalier/skills/espalier-fix/SKILL.md'"

# BSD/GNU-portable in-place sed (the suite's established fallback pattern)
sedi() { sed -i '' "$1" "$2" 2>/dev/null || sed -i "$1" "$2"; }

# The smoke install's agent files are stubs without the stock anchors — the
# migration must degrade to skip-with-record, never mangle or fail.
M21_SKIP=$( cd "$TMP" && bash "$MIGRATE21" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M21_SKIP_RC=$?
assert "28e customised agents skip-with-record (exit 0)" \
  "[ $M21_SKIP_RC -eq 0 ] && grep -qF 'v0.21.0-coder-context-pack' '$TMP/espalier/.migrations-skipped'"
M21_SKIP2=$( cd "$TMP" && bash "$MIGRATE21" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "28e2 re-run after skip-with-record is a no-op" \
  "echo \"\$M21_SKIP2\" | grep -qi 'nothing to do'"

# Simulate a stock v0.20 install: strip pure-copy markers, seed agent files
# carrying the stock anchors, then migrate for real.
( cd "$TMP" \
  && rm -f espalier/.migrations-skipped \
  && sedi '/Stage 3 Entry: Context Pack/d' espalier/skills/espalier/SKILL.md \
  && sedi '/DELTA SCOPE/d' espalier/pipeline.md \
  && sedi '/pairwise INDEPENDENT/d' espalier/skills/espalier-grill/SKILL.md \
  && sedi '/context-pack/d' espalier/skills/espalier-fix/SKILL.md )
cat > "$TMP/espalier/agents/harness-coder.md" << 'V20CODER'
## Before Writing ANY Code

1. Read `espalier/skills/espalier-coding/SKILL.md` for the implementation checklist
2. Identify which layers this task touches
V20CODER
cat > "$TMP/espalier/agents/harness-reviewer.md" << 'V20REV'
## Before Reviewing

1. Read `espalier/skills/espalier-review/SKILL.md` for the review checklist

## Re-review Rounds (you may be re-spawned on a fix)

Never assume the fix is correct because it addresses your previous finding. Review
the new code as fresh code.
V20REV
cat > "$TMP/espalier/agents/harness-security.md" << 'V20SEC'
## Before Auditing

1. Read `espalier/rules/security-standards.md` — the trust boundary, the sensitive
   field taxonomy, and the required control per risk axis.

Never assume the fix is correct because it addresses your prior finding. Audit the
new code as fresh code.
V20SEC
M21_OUT=$( cd "$TMP" && bash "$MIGRATE21" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
M21_RC=$?
assert "28f apply restores every v0.21 marker + backups" \
  "[ $M21_RC -eq 0 ] \
   && grep -qF 'Stage 3 Entry: Context Pack' '$TMP/espalier/skills/espalier/SKILL.md' \
   && grep -qF 'DELTA SCOPE' '$TMP/espalier/pipeline.md' \
   && grep -qF 'CONTEXT PACK' '$TMP/espalier/agents/harness-coder.md' \
   && grep -qF 'Delta read scope' '$TMP/espalier/agents/harness-reviewer.md' \
   && grep -qF 'Delta mode (when YOUR prior round was clean)' '$TMP/espalier/agents/harness-security.md' \
   && [ -f '$TMP/espalier/pipeline.md.pre-v0.21.bak' ] \
   && [ -f '$TMP/espalier/agents/harness-coder.md.pre-v0.21.bak' ]"
assert "28g inserts land BEFORE their anchors" \
  "awk '/CONTEXT PACK/{p=NR} /implementation checklist/{a=NR} END{exit !(p && a && p<a)}' '$TMP/espalier/agents/harness-coder.md' \
   && awk '/Delta read scope/{p=NR} /addresses your previous finding/{a=NR} END{exit !(p && a && p<a)}' '$TMP/espalier/agents/harness-reviewer.md'"
M21_RERUN=$( cd "$TMP" && bash "$MIGRATE21" --yes --plugin-dir="$SCRIPT_DIR/.." 2>&1 )
assert "28h re-run is a no-op" "echo \"\$M21_RERUN\" | grep -qi 'nothing to do'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Tests passed: $PASS"
echo "  Tests failed: $FAIL"
echo "═══════════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
