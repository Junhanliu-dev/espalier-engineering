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
( cd "$TMP" && bash "$BOOTSTRAP" --dry-run --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
assert "dry-run made no espalier/" "[ ! -d '$TMP/espalier' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 2: Full happy path (R1 — single invocation) ─────────────────────
echo "Test 2: full single invocation (R1)"
TMP=$(mktemp -d -t smoke2.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
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
simulate_llm_writes "$TMP" ts
( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
RERUN_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes 2>&1 )
RERUN_EXIT=$?
assert "re-run exit 0"                          "[ $RERUN_EXIT -eq 0 ]"
assert "re-run detected complete install"       "echo \"\$RERUN_OUT\" | grep -q 'Existing complete install'"
assert "re-run ran validation only"             "echo \"\$RERUN_OUT\" | grep -q 'Validation:'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 4: --force overrides re-run detection ───────────────────────────
echo "Test 4: --force override"
TMP=$(mktemp -d -t smoke4.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
FORCE_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 )
assert "--force does NOT trigger re-run path"   "echo \"\$FORCE_OUT\" | grep -qv 'Existing complete install'"
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
( cd "$TMP" && bash "$BOOTSTRAP" --copy-only --lang=ts --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
simulate_llm_writes "$TMP" ts
( cd "$TMP" && bash "$BOOTSTRAP" --wire-only --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes >/dev/null 2>&1 )
WIRE_EXIT=$?
assert "wire-only exit 0"                       "[ $WIRE_EXIT -eq 0 ]"
assert "wire-only created symlinks"             "[ -L '$TMP/.claude/rules/espalier-structure.md' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 7: safe_ln refuses to clobber regular file ─────────────────────
echo "Test 7: safe_ln pre-flight"
TMP=$(mktemp -d -t smoke7.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
mkdir -p "$TMP/.claude/rules"
echo "user content" > "$TMP/.claude/rules/espalier-structure.md"  # regular file, not symlink
SAFE_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "safe_ln blocked regular file"           "echo \"\$SAFE_OUT\" | grep -q 'exists as regular file'"
assert "user file preserved"                    "[ \"\$(cat '$TMP/.claude/rules/espalier-structure.md')\" = 'user content' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 8: settings.json merge preserves user hooks ─────────────────────
echo "Test 8: settings.json merge"
TMP=$(mktemp -d -t smoke8.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "echo user-hook"}]}]
  }
}
EOF
( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
assert "user hook survived merge"               "grep -q 'echo user-hook' '$TMP/.claude/settings.json'"
assert "Espalier hook added"                    "grep -q 'post-edit-wrapper' '$TMP/.claude/settings.json'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 9: portable abspath (no realpath binary needed) ────────────────
echo "Test 9: portable abspath"
TMP=$(mktemp -d -t smoke9.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
# Force absence of realpath by running with restricted PATH
( cd "$TMP" && env PATH="/usr/bin:/bin" bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
ABS_EXIT=$?
assert "bootstrap works without realpath"       "[ $ABS_EXIT -eq 0 ]"
assert "symlink uses absolute path"             "[ \"\$(readlink '$TMP/.claude/rules/espalier-structure.md' | head -c 1)\" = '/' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 10: parallel validation output is sorted ────────────────────────
echo "Test 10: parallel validation output order"
TMP=$(mktemp -d -t smoke10.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force >/dev/null 2>&1 )
VAL_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --validate-only --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes 2>&1 )
# Check that check numbers appear in order (1/24 before 2/24, etc.)
FIRST=$(echo "$VAL_OUT" | grep -oE '\[[0-9]+/28\]' | head -3 | sed 's/\[//;s/\/28\]//' | tr '\n' ' ')
assert "validation output sorted ascending"     "[ \"\$FIRST\" = '1 2 3 ' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 11: --merge-decision validation ─────────────────────────────────
echo "Test 11: merge-decision validation"
TMP=$(mktemp -d -t smoke11.XXXX)
make_smoke_repo "$TMP"
simulate_llm_writes "$TMP" ts
INVALID_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=garbage --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "rejects invalid merge-decision"         "echo \"\$INVALID_OUT\" | grep -q \"invalid --merge-decision='garbage'\""
MISSING_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "rejects missing merge-decision"         "echo \"\$MISSING_OUT\" | grep -q 'required for mode'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── Test 12: core.hooksPath honored ──────────────────────────────────────
echo "Test 12: core.hooksPath honored"

# 12a — core.hooksPath set INSIDE the repo: the dispatcher must land in that
#       dir, NOT in .git/hooks, and validation check 20 must still pass.
TMP=$(mktemp -d -t smoke12a.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && mkdir -p .githooks && git config core.hooksPath .githooks )
simulate_llm_writes "$TMP" ts
HP_IN=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 )
assert "12a Stage 9 logged hooksPath resolution" "echo \"\$HP_IN\" | grep -q 'core.hooksPath set'"
assert "12a dispatcher at core.hooksPath dir"    "grep -q 'ESPALIER_POSTMERGE_DISPATCH' '$TMP/.githooks/post-merge'"
assert "12a nothing written to .git/hooks"       "[ ! -f '$TMP/.git/hooks/post-merge' ]"
assert "12a check 20 passed"                     "echo \"\$HP_IN\" | grep -qF '[20/28] OK'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# 12b — core.hooksPath set OUTSIDE the repo: bootstrap must refuse to install,
#       warn, write nothing, and validation check 20 must fail (honest red).
TMP=$(mktemp -d -t smoke12b.XXXX)
OUTSIDE=$(mktemp -d -t smoke12bout.XXXX)
make_smoke_repo "$TMP"
( cd "$TMP" && git config core.hooksPath "$OUTSIDE" )
simulate_llm_writes "$TMP" ts
HP_OUT=$( cd "$TMP" && bash "$BOOTSTRAP" --lang=ts --merge-decision=ask-later --plugin-dir="$PLUGIN_DIR" --yes --force 2>&1 || true )
assert "12b warns hooksPath outside repo"        "echo \"\$HP_OUT\" | grep -q 'points outside this repo'"
assert "12b no dispatcher in outside dir"        "[ ! -f '$OUTSIDE/post-merge' ]"
assert "12b no dispatcher in .git/hooks"         "[ ! -f '$TMP/.git/hooks/post-merge' ]"
assert "12b check 20 failed (honest red)"        "echo \"\$HP_OUT\" | grep -qF '[20/28] FAIL'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$OUTSIDE"

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
