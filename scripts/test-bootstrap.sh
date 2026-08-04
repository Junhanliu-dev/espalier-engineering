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
FIRST=$(echo "$VAL_OUT" | grep -oE '\[[0-9]+/48\]' | head -3 | sed 's/\[//;s/\/48\]//' | tr '\n' ' ')
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
assert "12a check 20 passed"                     "echo \"\$HP_IN\" | grep -qF '[20/48] OK'"
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
assert "12b check 20 failed (honest red)"        "echo \"\$HP_OUT\" | grep -qF '[20/48] FAIL'"
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
assert "14m validation total is 51"          "echo \"\$P_OUT\" | grep -q 'Validation: 53/53 passed'"
assert "14n codex checks ran"                "echo \"\$P_OUT\" | grep -qF '[47/53] OK'"
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
assert "15f validation total is 51"          "echo \"\$W_OUT\" | grep -q 'Validation: 53/53 passed'"
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
assert "16f validation passes"               "echo \"\$C_OUT\" | grep -q 'Validation: 53/53 passed'"
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
assert "17i validation total is 56"            "echo \"\$A_OUT\" | grep -q 'Validation: 58/58 passed'"
assert "17j copilot checks ran"                "echo \"\$A_OUT\" | grep -qF '[52/58] OK'"
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
assert "18g validation total is 56"          "echo \"\$P_OUT\" | grep -q 'Validation: 58/58 passed'"
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
assert "21c full validation passes in the worktree"    "echo \"\$WT_OUT\" | grep -q 'Validation: 48/48 passed'"
assert "21d check 20 passes in the worktree"           "echo \"\$WT_OUT\" | grep -qF '[20/48] OK'"
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
