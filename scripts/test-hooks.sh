#!/bin/bash
# Regression tests for the mechanical hook layer:
#   - lookup-helpers.sh   (_fuzzy_file_overlap_match, _dedupe_entries_preserve_primary, _cache_append)
#   - post-merge-backlink.sh (squash detection + hardened overlap match)
#   - rebuild-commit-index.sh (section parsing)
#   - pre-push-gate.sh    (active-change selection, certificate, test-count parse)
#   - drift-helpers.sh    (mark/clear/tier, interactivity_mode)
#   - phantom-helper lint (every `_fn` a skill template calls must be defined in a hook template)
#
# Complements scripts/test-bootstrap.sh (which covers install wiring).
# Bash 3.2 compatible (macOS system bash). No GNU-only tools.
#
# Usage: bash scripts/test-hooks.sh [--keep] [--verbose]

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
HOOKS_SRC="$SCRIPT_DIR/../skills/espalier-init/hook-templates"
TEMPLATES="$SCRIPT_DIR/../skills/espalier-init/templates"
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

# make_repo DIR — git repo with one baseline commit.
make_repo() {
  local dir=$1
  rm -rf "$dir"
  mkdir -p "$dir"
  ( cd "$dir" && git init --quiet --initial-branch=main \
      && echo base > base.txt && git add -A \
      && git -c user.email=t@t -c user.name=t commit -q -m "baseline" )
}

# install_hooks DIR — copy the hook templates into DIR/espalier/hooks/.
install_hooks() {
  local dir=$1
  mkdir -p "$dir/espalier/hooks" "$dir/espalier/changes/feat" "$dir/espalier/changes/fix" "$dir/espalier/changes/refactor"
  cp "$HOOKS_SRC/lookup-helpers.sh"       "$dir/espalier/hooks/"
  cp "$HOOKS_SRC/drift-helpers.sh"        "$dir/espalier/hooks/"
  cp "$HOOKS_SRC/post-merge-backlink.sh"  "$dir/espalier/hooks/"
  cp "$HOOKS_SRC/rebuild-commit-index.sh" "$dir/espalier/hooks/"
  chmod +x "$dir/espalier/hooks/"*.sh
}

# state_file DIR TYPE SLUG STAGE STATUS COMMITS_ROW... — write a pipeline-state.md
state_file() {
  local dir=$1 type=$2 slug=$3 stage=$4 status=$5; shift 5
  local d="$dir/espalier/changes/$type/$slug"
  mkdir -p "$d"
  {
    printf '# Pipeline State: %s\n\n## Status\n- Current Stage: %s\n- Status: %s\n\n## Stage History\n| Stage | Status | Timestamp | Notes |\n|---|---|---|---|\n\n## Commits\n| Stage | SHA | Files |\n|-------|-----|-------|\n' "$slug" "$stage" "$status"
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$d/pipeline-state.md"
}

# ─── T1: _fuzzy_file_overlap_match ────────────────────────────────────────
echo "T1: lookup-helpers _fuzzy_file_overlap_match"
TMP=$(mktemp -d -t hooks-t1.XXXX)
make_repo "$TMP"
install_hooks "$TMP"

# Commit touching ONLY a Next.js route-group file (ERE metachars in path) so the
# 50% threshold rides entirely on matching that one path. git add SPECIFIC paths —
# `-A` would sweep in the installed espalier/hooks files and dilute the ratio.
mkdir -p "$TMP/app/(dashboard)"
echo x > "$TMP/app/(dashboard)/page.tsx"
( cd "$TMP" && git add 'app/(dashboard)/page.tsx' && git -c user.email=t@t -c user.name=t commit -q -m "feat stuff" )
SHA=$(cd "$TMP" && git rev-parse HEAD)

# Candidate state lists the path → 1/1 overlap → should match.
state_file "$TMP" feat 2026-01-01-routegroup 7 COMPLETE \
  "| 7 | $SHA | app/(dashboard)/page.tsx |"

OUT=$(cd "$TMP" && . espalier/hooks/lookup-helpers.sh && _fuzzy_file_overlap_match "$SHA")
assert "T1a fuzzy matches path with ERE metachars (route group)" "[ \"$OUT\" = 'feat/2026-01-01-routegroup' ]"

# a.ts must NOT substring-match a.tsx: commit touches src/a.ts; state lists only src/a.tsx.
TMP2=$(mktemp -d -t hooks-t1b.XXXX)
make_repo "$TMP2"
install_hooks "$TMP2"
mkdir -p "$TMP2/src"
echo x > "$TMP2/src/a.ts"
( cd "$TMP2" && git add src/a.ts && git -c user.email=t@t -c user.name=t commit -q -m "add a.ts" )
SHA2=$(cd "$TMP2" && git rev-parse HEAD)
state_file "$TMP2" feat 2026-01-01-tsx 7 COMPLETE \
  "| 7 | 0000000 | src/a.tsx |"
OUT2=$(cd "$TMP2" && . espalier/hooks/lookup-helpers.sh && _fuzzy_file_overlap_match "$SHA2")
assert "T1b a.ts does not match a.tsx (whole-path anchor)" "[ -z \"$OUT2\" ]"

# Age filter: candidate older than the max-age arg is skipped; no arg keeps it.
TMP3=$(mktemp -d -t hooks-t1c.XXXX)
make_repo "$TMP3"
install_hooks "$TMP3"
mkdir -p "$TMP3/src"
echo x > "$TMP3/src/old.ts"
( cd "$TMP3" && git add src/old.ts && git -c user.email=t@t -c user.name=t commit -q -m "old work" )
SHA3=$(cd "$TMP3" && git rev-parse HEAD)
state_file "$TMP3" feat 2020-01-01-ancient 7 COMPLETE \
  "| 7 | $SHA3 | src/old.ts |"
touch -t 202001010000 "$TMP3/espalier/changes/feat/2020-01-01-ancient/pipeline-state.md"
OUT3A=$(cd "$TMP3" && . espalier/hooks/lookup-helpers.sh && _fuzzy_file_overlap_match "$SHA3" 30)
OUT3B=$(cd "$TMP3" && . espalier/hooks/lookup-helpers.sh && _fuzzy_file_overlap_match "$SHA3")
assert "T1c max-age arg skips stale candidate"    "[ -z \"$OUT3A\" ]"
assert "T1d no max-age arg keeps stale candidate" "[ \"$OUT3B\" = 'feat/2020-01-01-ancient' ]"

[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2" "$TMP3"

# ─── T2: _dedupe_entries_preserve_primary + _cache_append ─────────────────
echo "T2: lookup-helpers dedupe + cache"
TMP=$(mktemp -d -t hooks-t2.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
DEDUP_OUT=$(cd "$TMP" && . espalier/hooks/lookup-helpers.sh && \
  _push_entry feat/a s1 call_path exact && \
  _push_entry feat/a s2 primary exact && \
  _push_entry feat/b s3 call_path exact && \
  _dedupe_entries_preserve_primary && \
  printf '%s:%s ' "${ENTRIES_SLUG[@]}" "${ENTRIES_ROLE[@]}" 2>/dev/null; echo "n=${#ENTRIES_SLUG[@]}")
assert "T2a dedupe keeps primary over call_path" "echo \"$DEDUP_OUT\" | grep -q 'n=2'"
CACHE_OUT=$(cd "$TMP" && . espalier/hooks/lookup-helpers.sh && \
  _cache_append aaa1111 feat/x original && _cache_append aaa1111 feat/x original && \
  wc -l < espalier/.commit-index.tsv | tr -d ' ')
assert "T2b cache append is idempotent" "[ \"$CACHE_OUT\" = '1' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T3: post-merge-backlink.sh ────────────────────────────────────────────
echo "T3: post-merge-backlink"
# T3a: genuine 100% overlap on a squash-shaped commit → link recorded.
TMP=$(mktemp -d -t hooks-t3a.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
mkdir -p "$TMP/src"
echo x > "$TMP/src/feature.ts"
( cd "$TMP" && git add src/feature.ts && git -c user.email=t@t -c user.name=t commit -q -m "add feature (#12)" )
state_file "$TMP" feat 2026-01-01-feature 7 COMPLETE \
  "| 7 | 1234abc | src/feature.ts |"
( cd "$TMP" && bash espalier/hooks/post-merge-backlink.sh >/dev/null 2>&1 )
assert "T3a squash overlap records squashed_to row" \
  "grep -q 'squashed_to:' '$TMP/espalier/changes/feat/2026-01-01-feature/pipeline-state.md'"

# T3b: commit touches ONLY src/a.ts; candidate lists ONLY src/a.tsx → must NOT link.
TMP2=$(mktemp -d -t hooks-t3b.XXXX)
make_repo "$TMP2"
install_hooks "$TMP2"
mkdir -p "$TMP2/src"
echo x > "$TMP2/src/a.ts"
( cd "$TMP2" && git add src/a.ts && git -c user.email=t@t -c user.name=t commit -q -m "unrelated (#13)" )
state_file "$TMP2" feat 2026-01-01-tsxonly 7 COMPLETE \
  "| 7 | 9999aaa | src/a.tsx |"
( cd "$TMP2" && bash espalier/hooks/post-merge-backlink.sh >/dev/null 2>&1 )
assert "T3b a.ts does not fuzzy-link to a.tsx change" \
  "! grep -q 'squashed_to:' '$TMP2/espalier/changes/feat/2026-01-01-tsxonly/pipeline-state.md'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2"

# ─── T4: rebuild-commit-index.sh section parsing ──────────────────────────
echo "T4: rebuild-commit-index section parsing"
TMP=$(mktemp -d -t hooks-t4.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
D="$TMP/espalier/changes/feat/2026-01-01-idx"
mkdir -p "$D"
cat > "$D/pipeline-state.md" << 'EOF'
# Pipeline State: idx

## Status
- Current Stage: 7
- Status: COMPLETE

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
| 7 | abc1234 | src/f.ts |

## Checks
| 42 | deadbee | not-a-commit-row |

## Squash Merges
| Squashed Into | Date | File Overlap |
|---------------|------|--------------|
| squashed_to: fedc4321 | 2026-01-01 | 1/1 files |

## Stage History
| 5 | squashed_to: 0000bad should not be indexed from history |
EOF
( cd "$TMP" && bash espalier/hooks/rebuild-commit-index.sh >/dev/null 2>&1 )
IDX="$TMP/espalier/.commit-index.tsv"
assert "T4a commits row indexed"                    "grep -q '^abc1234' '$IDX'"
assert "T4b squash row indexed"                     "grep -q '^fedc4321' '$IDX'"
assert "T4c row under '## Checks' NOT indexed"      "! grep -q 'deadbee' '$IDX'"
assert "T4d squashed_to in Stage History NOT indexed" "! grep -q '0000bad' '$IDX'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T5: pre-push-gate.sh ──────────────────────────────────────────────────
echo "T5: pre-push-gate"

# make_gate DIR TEST_CMD — materialize the gate template with fake commands.
make_gate() {
  local dir=$1 test_cmd=$2
  mkdir -p "$dir/espalier/hooks"
  sed -e "s|{build_command}|true|g" \
      -e "s|{lint_command}|true|g" \
      -e "s|{test_command}|$test_cmd|g" \
      "$HOOKS_SRC/pre-push-gate.sh" > "$dir/espalier/hooks/pre-push-gate.sh"
  chmod +x "$dir/espalier/hooks/pre-push-gate.sh"
}

# T5a: completed change with a stale certificate must NOT gate later manual pushes.
TMP=$(mktemp -d -t hooks-t5a.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
make_gate "$TMP" "echo '3 passed'"
BASE=$(cd "$TMP" && git rev-parse HEAD)
echo change > "$TMP/work.txt"
( cd "$TMP" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "pipeline change" )
FP=$(cd "$TMP" && git diff "$BASE" -- . ':(exclude)espalier/' | git hash-object --stdin)
state_file "$TMP" feat 2026-01-01-done 10 COMPLETE "| 7 | headsha | work.txt |"
{
  printf 'Base-Ref: %s\nReviewed-Diff: %s\n' "$BASE" "$FP"
} >> "$TMP/espalier/changes/feat/2026-01-01-done/pipeline-state.md"
# post-completion manual commit → live fingerprint no longer matches the old cert
echo manual >> "$TMP/work.txt"
( cd "$TMP" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "manual follow-up" )
( cd "$TMP" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
assert "T5a terminal-status change does not block manual push" "[ $? -eq 0 ]"

# T5b: in-progress change below Stage 7 still blocks.
TMP2=$(mktemp -d -t hooks-t5b.XXXX)
make_repo "$TMP2"
install_hooks "$TMP2"
make_gate "$TMP2" "echo '3 passed'"
state_file "$TMP2" feat 2026-01-01-wip 3 IN_PROGRESS
( cd "$TMP2" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
assert "T5b in-progress change at Stage 3 blocks push" "[ $? -ne 0 ]"

# T5c: active change is gated even when a terminal change has a NEWER state file.
TMP3=$(mktemp -d -t hooks-t5c.XXXX)
make_repo "$TMP3"
install_hooks "$TMP3"
make_gate "$TMP3" "echo '3 passed'"
BASE3=$(cd "$TMP3" && git rev-parse HEAD)
echo live > "$TMP3/live.txt"
( cd "$TMP3" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "active change" )
FP3=$(cd "$TMP3" && git diff "$BASE3" -- . ':(exclude)espalier/' | git hash-object --stdin)
state_file "$TMP3" feat 2026-01-01-active 7 IN_PROGRESS
{
  printf 'Base-Ref: %s\nReviewed-Diff: %s\n' "$BASE3" "$FP3"
} >> "$TMP3/espalier/changes/feat/2026-01-01-active/pipeline-state.md"
sleep 1
state_file "$TMP3" feat 2026-01-01-newerdone 10 COMPLETE
printf 'Base-Ref: %s\nReviewed-Diff: bogus\n' "$BASE3" \
  >> "$TMP3/espalier/changes/feat/2026-01-01-newerdone/pipeline-state.md"
GATE3_OUT=$(cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh 2>&1)
GATE3_RC=$?
assert "T5c newer terminal state does not shadow the active change" "[ $GATE3_RC -eq 0 ]"

# T5d: active change whose source changed after review is still blocked (cert holds).
echo tamper >> "$TMP3/live.txt"
( cd "$TMP3" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "sneaky post-review edit" )
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
assert "T5d post-review edit on ACTIVE change fails closed" "[ $? -ne 0 ]"

# T5e: two in-flight changes → gate warns about the ambiguity.
TMP4=$(mktemp -d -t hooks-t5e.XXXX)
make_repo "$TMP4"
install_hooks "$TMP4"
make_gate "$TMP4" "echo '3 passed'"
state_file "$TMP4" feat 2026-01-01-one 7 IN_PROGRESS
state_file "$TMP4" fix  2026-01-02-two 7 IN_PROGRESS
GATE4_OUT=$(cd "$TMP4" && bash espalier/hooks/pre-push-gate.sh 2>&1)
assert "T5e multiple in-flight changes produce a warning" "echo \"$GATE4_OUT\" | grep -qi 'in-flight'"

# T5f/g/h: test-count parsing across runner output formats (all runs exit 0).
run_count_case() {  # name, fake-test-command, expect_rc
  local name=$1 cmd=$2 expect=$3
  local dir; dir=$(mktemp -d -t hooks-t5cnt.XXXX)
  make_repo "$dir"
  install_hooks "$dir"
  make_gate "$dir" "$cmd"
  state_file "$dir" feat 2026-01-01-cnt 7 IN_PROGRESS
  ( cd "$dir" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
  local rc=$?
  assert "$name" "[ $rc -eq $expect ]"
  [ "$KEEP" != "yes" ] && rm -rf "$dir"
}
run_count_case "T5f jest-style '5 passed' passes"        "echo '5 passed'"                 0
run_count_case "T5g mocha-style '12 passing' passes"     "echo '  12 passing (34ms)'"      0
run_count_case "T5h go-style 'ok <pkg>' passes"          "printf 'ok  \texample.com/pkg\t0.012s\n'" 0
run_count_case "T5i rspec-style '8 examples' passes"     "echo '8 examples, 0 failures'"   0
run_count_case "T5j explicit '0 passed' still blocks"    "echo '0 passed'"                 1

[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4"

# ─── T6: drift-helpers basics ──────────────────────────────────────────────
echo "T6: drift-helpers"
TMP=$(mktemp -d -t hooks-t6.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
mkdir -p "$TMP/espalier/wiki"
echo doc > "$TMP/espalier/wiki/architecture.md"
DH_OUT=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && \
  mark_stale espalier/wiki/architecture.md deadbeef "test reason" && \
  stale_files && classify_tier espalier/wiki/architecture.md && \
  clear_stale espalier/wiki/architecture.md && stale_files; echo "END")
assert "T6a mark_stale flags the file"   "echo \"$DH_OUT\" | grep -q 'espalier/wiki/architecture.md'"
assert "T6b fresh row classifies fresh"  "echo \"$DH_OUT\" | grep -q 'fresh'"
assert "T6c clear_stale removes the row" "[ \"$(echo \"$DH_OUT\" | grep -c 'espalier/wiki/architecture.md')\" = '1' ]"
IM1=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && interactivity_mode)
IM2=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && ESPALIER_HEADLESS=1 interactivity_mode)
assert "T6d interactivity_mode defaults interactive"      "[ \"$IM1\" = 'interactive' ]"
assert "T6e ESPALIER_HEADLESS forces unattended"          "[ \"$IM2\" = 'unattended' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T7: phantom-helper lint ───────────────────────────────────────────────
# Every `_helper` invoked at command position in a skill template must be
# defined either in a hook template or inline in a template itself.
echo "T7: phantom-helper lint"
DEFINED=$(
  { grep -hoE '^[[:space:]]*_[a-z_]+\(\)' "$HOOKS_SRC"/*.sh 2>/dev/null
    grep -hoE '^[[:space:]]*_[a-z_]+\(\)' "$TEMPLATES"/skills/*.md "$TEMPLATES"/agents/*.md 2>/dev/null
  } | tr -d ' ()' | sort -u
)
CALLED=$(
  { grep -hoE '^[[:space:]]*_[a-z_]{3,}([[:space:]]|$)' "$TEMPLATES"/skills/*.md 2>/dev/null
    grep -hoE '\$\(_[a-z_]{3,}' "$TEMPLATES"/skills/*.md 2>/dev/null
  } | sed -E 's/^[[:space:]]*//; s/\$\(//; s/[[:space:]]*$//' | sort -u
)
PHANTOMS=""
for fn in $CALLED; do
  echo "$DEFINED" | grep -qxF "$fn" || PHANTOMS="$PHANTOMS $fn"
done
assert "T7a no skill template calls an undefined _helper" "[ -z \"$PHANTOMS\" ]"
[ -n "$PHANTOMS" ] && echo "       phantoms:$PHANTOMS"

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
