#!/bin/bash
# Regression tests for the mechanical hook layer:
#   - lookup-helpers.sh   (_fuzzy_file_overlap_match, _dedupe_entries_preserve_primary, _cache_append)
#   - post-merge-backlink.sh (squash detection + hardened overlap match)
#   - rebuild-commit-index.sh (section parsing)
#   - pre-push-gate.sh    (active-change selection, certificate, test-count parse,
#                          exit-2 blocking contract, secret scan, corrupt-state fail-closed)
#   - pre-push-gate-wrapper.sh (push detection matrix, fail-closed python probe)
#   - drift-helpers.sh    (mark/clear/tier, interactivity_mode)
#   - phantom-helper lint (every `_fn` a skill template calls must be defined in a hook template)
#
# Hook exit-code contract asserted throughout: a blocking run exits 2 with
# BLOCKED on stderr (Claude Code PreToolUse semantics); an allowed run exits 0.
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
GATE2_ERR="$TMP2/err.txt"
( cd "$TMP2" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$GATE2_ERR" )
GATE2_RC=$?
assert "T5b in-progress change at Stage 3 blocks push (exit 2)" "[ $GATE2_RC -eq 2 ]"
assert "T5b2 stage block writes BLOCKED to stderr" "grep -q 'BLOCKED' '$GATE2_ERR'"

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
GATE3D_ERR="$TMP3/err.txt"
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$GATE3D_ERR" )
GATE3D_RC=$?
assert "T5d post-review edit on ACTIVE change fails closed (exit 2)" "[ $GATE3D_RC -eq 2 ]"
assert "T5d2 cert block writes BLOCKED to stderr" "grep -q 'BLOCKED' '$GATE3D_ERR'"

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
# A blocked case must exit 2 (not merely non-zero) with BLOCKED on stderr.
run_count_case() {  # name, fake-test-command, expect_rc
  local name=$1 cmd=$2 expect=$3
  local dir; dir=$(mktemp -d -t hooks-t5cnt.XXXX)
  make_repo "$dir"
  install_hooks "$dir"
  make_gate "$dir" "$cmd"
  state_file "$dir" feat 2026-01-01-cnt 7 IN_PROGRESS
  ( cd "$dir" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$dir/err.txt" )
  local rc=$?
  assert "$name" "[ $rc -eq $expect ]"
  if [ "$expect" -eq 2 ]; then
    assert "$name (BLOCKED on stderr)" "grep -q 'BLOCKED' '$dir/err.txt'"
  fi
  [ "$KEEP" != "yes" ] && rm -rf "$dir"
}
run_count_case "T5f jest-style '5 passed' passes"        "echo '5 passed'"                 0
run_count_case "T5g mocha-style '12 passing' passes"     "echo '  12 passing (34ms)'"      0
run_count_case "T5h go-style 'ok <pkg>' passes"          "printf 'ok  \texample.com/pkg\t0.012s\n'" 0
run_count_case "T5i rspec-style '8 examples' passes"     "echo '8 examples, 0 failures'"   0
run_count_case "T5j explicit '0 passed' still blocks"    "echo '0 passed'"                 2
run_count_case "T5k failing test command blocks"         "echo '1 failed'; false"          2

# T5l: gate-template exit-code totals — the installed gate must have exactly the
# 10 blocking `exit 2` statements and zero blocking `exit 1`.
TMP5=$(mktemp -d -t hooks-t5l.XXXX)
make_repo "$TMP5"
install_hooks "$TMP5"
make_gate "$TMP5" "echo '3 passed'"
assert "T5l installed gate has 10 'exit 2' sites" \
  "[ \"\$(grep -c 'exit 2' '$TMP5/espalier/hooks/pre-push-gate.sh')\" = '10' ]"
assert "T5l2 installed gate has zero 'exit 1' sites" \
  "[ \"\$(grep -c 'exit 1' '$TMP5/espalier/hooks/pre-push-gate.sh')\" = '0' ]"

# T5m: multi-line two-command build function body, second command fails → blocked.
# make_gate's sed is line-based, so splice the two-line body with awk.
awk '{
  if ($0 ~ /^[[:space:]]*true[[:space:]]*$/ && !done_build) { print "  echo compiling"; print "  false"; done_build=1 }
  else print
}' "$TMP5/espalier/hooks/pre-push-gate.sh" > "$TMP5/espalier/hooks/pre-push-gate.sh.new" \
  && mv "$TMP5/espalier/hooks/pre-push-gate.sh.new" "$TMP5/espalier/hooks/pre-push-gate.sh"
state_file "$TMP5" feat 2026-01-01-mlbuild 7 IN_PROGRESS
( cd "$TMP5" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP5/err.txt" )
T5M_RC=$?
assert "T5m multi-line build body failing 2nd command blocks (exit 2)" "[ $T5M_RC -eq 2 ]"
assert "T5m2 build block writes BLOCKED to stderr" "grep -q 'BLOCKED: Build fails' '$TMP5/err.txt'"

# T5n: no state file + committed fake secret → secret scan still runs, blocks.
# Two commits so the HEAD~1 fallback range exists; secret added in the second.
TMP6=$(mktemp -d -t hooks-t5n.XXXX)
make_repo "$TMP6"
install_hooks "$TMP6"
make_gate "$TMP6" "echo '3 passed'"
printf 'aws_key = "AKIAABCDEFGHIJKLMNOP"\n' > "$TMP6/config.py"
( cd "$TMP6" && git add config.py && git -c user.email=t@t -c user.name=t commit -q -m "leak" )
( cd "$TMP6" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP6/err.txt" )
T5N_RC=$?
assert "T5n secret scan blocks even with no in-flight change (exit 2)" "[ $T5N_RC -eq 2 ]"
assert "T5n2 secret block names the secret on stderr" "grep -q 'BLOCKED' '$TMP6/err.txt'"

# T5o: state file missing its 'Current Stage:' line → fail closed.
TMP7=$(mktemp -d -t hooks-t5o.XXXX)
make_repo "$TMP7"
install_hooks "$TMP7"
make_gate "$TMP7" "echo '3 passed'"
state_file "$TMP7" feat 2026-01-01-nostage 7 IN_PROGRESS
sed '/Current Stage:/d' "$TMP7/espalier/changes/feat/2026-01-01-nostage/pipeline-state.md" \
  > "$TMP7/tmp.md" && mv "$TMP7/tmp.md" "$TMP7/espalier/changes/feat/2026-01-01-nostage/pipeline-state.md"
( cd "$TMP7" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP7/err.txt" )
T5O_RC=$?
assert "T5o missing 'Current Stage:' line fails closed (exit 2)" "[ $T5O_RC -eq 2 ]"
assert "T5o2 corrupt-state block on stderr" "grep -q 'no parsable' '$TMP7/err.txt'"

# T5p: Stage-4 PASSED row but no Base-Ref/Reviewed-Diff → certificate required.
TMP8=$(mktemp -d -t hooks-t5p.XXXX)
make_repo "$TMP8"
install_hooks "$TMP8"
make_gate "$TMP8" "echo '3 passed'"
state_file "$TMP8" feat 2026-01-01-nocert 7 IN_PROGRESS \
  "| 4 | PASSED | 2026-01-01T10:00 | 1 round, no P0s |"
( cd "$TMP8" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP8/err.txt" )
T5P_RC=$?
assert "T5p Stage-4-PASSED without certificate fails closed (exit 2)" "[ $T5P_RC -eq 2 ]"
assert "T5p2 missing-certificate block on stderr" "grep -q 'review certificate is missing' '$TMP8/err.txt'"

[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP8"

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

# ─── T8: pre-push-gate-wrapper.sh push-detection matrix ───────────────────
# The wrapper reads PreToolUse JSON on stdin. A dispatch must reach the gate
# (stub exits 2 with GATE_RAN on stderr); a non-push must exit 0 untouched.
echo "T8: pre-push-gate-wrapper"
WRAPPER="$HOOKS_SRC/pre-push-gate-wrapper.sh"
TMP=$(mktemp -d -t hooks-t8.XXXX)
make_repo "$TMP"
mkdir -p "$TMP/espalier/hooks"
printf '#!/bin/bash\necho GATE_RAN >&2\nexit 2\n' > "$TMP/espalier/hooks/pre-push-gate.sh"
chmod +x "$TMP/espalier/hooks/pre-push-gate.sh"

# run_wrapper_case NAME JSON EXPECT_RC EXPECT_DISPATCH(yes|no)
run_wrapper_case() {
  local name=$1 json=$2 expect_rc=$3 expect_dispatch=$4
  local rc err="$TMP/w_err.txt"
  ( cd "$TMP" && printf '%s' "$json" | bash "$WRAPPER" >/dev/null 2>"$err" )
  rc=$?
  assert "$name (rc)" "[ $rc -eq $expect_rc ]"
  if [ "$expect_dispatch" = "yes" ]; then
    assert "$name (gate dispatched)" "grep -q 'GATE_RAN' '$err'"
  else
    assert "$name (gate NOT dispatched)" "! grep -q 'GATE_RAN' '$err'"
  fi
}

run_wrapper_case "T8a plain 'git push' dispatches" \
  '{"tool_input":{"command":"git push"}}' 2 yes
run_wrapper_case "T8b 'git -C /tmp/x push' dispatches" \
  '{"tool_input":{"command":"git -C /tmp/x push"}}' 2 yes
run_wrapper_case "T8c multi-line 'npm test\\ngit push' dispatches" \
  '{"tool_input":{"command":"npm test\ngit push"}}' 2 yes
run_wrapper_case "T8d quoted mention 'echo \"git push\"' does NOT dispatch" \
  '{"tool_input":{"command":"echo \"git push\""}}' 0 no
run_wrapper_case "T8e commit message + real push dispatches" \
  '{"tool_input":{"command":"git commit -m \"git push docs\" && git push"}}' 2 yes

# T8f: python3 AND python absent → fail CLOSED (exit 2, BLOCKED on stderr).
# Build a PATH with only the non-python tools the wrapper needs.
PBIN="$TMP/nopython-bin"
mkdir -p "$PBIN"
for _t in bash sh cat grep sed git; do
  _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -s "$_p" "$PBIN/$_t"
done
( cd "$TMP" && printf '%s' '{"tool_input":{"command":"git push"}}' \
    | env PATH="$PBIN" "$PBIN/bash" "$WRAPPER" >/dev/null 2>"$TMP/w_err.txt" )
T8F_RC=$?
assert "T8f no python on PATH fails closed (exit 2)" "[ $T8F_RC -eq 2 ]"
assert "T8f2 no-python block on stderr" "grep -q 'BLOCKED' '$TMP/w_err.txt'"

run_wrapper_case "T8g codex argv-array push dispatches" \
  '{"tool_input":{"command":["bash","-lc","git push origin main"]}}' 2 yes
run_wrapper_case "T8h codex argv-array non-push exits 0" \
  '{"tool_input":{"command":["bash","-lc","git status && ls"]}}' 0 no

[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T9: post-edit-wrapper.sh payload matrix (Claude file_path + Codex apply_patch) ──
echo "T9: post-edit-wrapper"
PWRAP="$HOOKS_SRC/post-edit-wrapper.sh"
TMP=$(mktemp -d -t hooks-t9.XXXX)
make_repo "$TMP"
mkdir -p "$TMP/espalier/hooks" "$TMP/src"
# Boundary-check stub: exit 2 (violation) for any path containing "bad", else 0.
# Echoes CHECKED:<path> to stderr so dispatch + path resolution are observable.
cat > "$TMP/espalier/hooks/check-layer-boundaries.sh" << 'STUB'
#!/bin/bash
echo "CHECKED:$1" >&2
case "$1" in *bad*) echo "violation in $1" >&2; exit 2 ;; esac
exit 0
STUB
chmod +x "$TMP/espalier/hooks/check-layer-boundaries.sh"
touch "$TMP/src/ok.ts" "$TMP/src/bad.ts" "$TMP/src/ok2.ts"

# run_pwrap_case NAME JSON EXPECT_RC EXPECT_CHECKED_SUBSTR("-" = none)
run_pwrap_case() {
  local name=$1 json=$2 expect_rc=$3 expect_checked=$4
  local rc err="$TMP/p_err.txt"
  ( cd "$TMP" && printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR bash "$PWRAP" >/dev/null 2>"$err" )
  rc=$?
  assert "$name (rc)" "[ $rc -eq $expect_rc ]"
  if [ "$expect_checked" = "-" ]; then
    assert "$name (no check ran)" "! grep -q 'CHECKED:' '$err'"
  else
    assert "$name (checked $expect_checked)" "grep -q 'CHECKED:.*$expect_checked' '$err'"
  fi
}

run_pwrap_case "T9a claude file_path clean file" \
  "{\"tool_input\":{\"file_path\":\"$TMP/src/ok.ts\"}}" 0 "src/ok.ts"
run_pwrap_case "T9b claude file_path violating file" \
  "{\"tool_input\":{\"file_path\":\"$TMP/src/bad.ts\"}}" 2 "src/bad.ts"
CODEX_PATCH='{"tool_input":{"command":"*** Begin Patch\n*** Update File: src/ok.ts\n@@\n-a\n+b\n*** Add File: src/ok2.ts\n+x\n*** End Patch"}}'
run_pwrap_case "T9c codex apply_patch multi-file (both clean)" \
  "$CODEX_PATCH" 0 "src/ok2.ts"
CODEX_BAD='{"tool_input":{"command":"*** Begin Patch\n*** Update File: src/ok.ts\n@@\n-a\n+b\n*** Update File: src/bad.ts\n@@\n-a\n+b\n*** End Patch"}}'
run_pwrap_case "T9d codex apply_patch one violation → exit 2" \
  "$CODEX_BAD" 2 "src/bad.ts"
run_pwrap_case "T9e codex deleted-file patch line ignored" \
  '{"tool_input":{"command":"*** Begin Patch\n*** Delete File: src/ok.ts\n*** End Patch"}}' 0 "-"
run_pwrap_case "T9f empty/unknown tool_input exits 0" \
  '{"tool_input":{"description":"noop"}}' 0 "-"
# T9g: relative path from patch resolves against the git root even from a subdir.
mkdir -p "$TMP/deep/nest"
( cd "$TMP/deep/nest" && printf '%s' "$CODEX_BAD" | env -u CLAUDE_PROJECT_DIR bash "$PWRAP" >/dev/null 2>"$TMP/p_err.txt" )
T9G_RC=$?
assert "T9g subdir cwd still resolves + blocks (rc 2)" "[ $T9G_RC -eq 2 ]"
# Absolute-path assertion, not string-equal to $TMP: on macOS git returns the
# /private/var realpath while mktemp reports /var — same dir, different spelling.
assert "T9g2 checked path is absolute repo-rooted" "grep -q 'CHECKED:/.*src/bad.ts' '$TMP/p_err.txt'"

[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T10: copilot-hook-adapter.sh payload translation ─────────────────────
echo "T10: copilot-hook-adapter"
ADAPTER="$HOOKS_SRC/copilot-hook-adapter.sh"
TMP=$(mktemp -d -t hooks-t10.XXXX)
make_repo "$TMP"
mkdir -p "$TMP/espalier/hooks" "$TMP/src"
cp "$ADAPTER" "$TMP/espalier/hooks/copilot-hook-adapter.sh"
cp "$HOOKS_SRC/pre-push-gate-wrapper.sh" "$TMP/espalier/hooks/pre-push-gate-wrapper.sh"
cp "$HOOKS_SRC/post-edit-wrapper.sh" "$TMP/espalier/hooks/post-edit-wrapper.sh"
chmod +x "$TMP/espalier/hooks/"*.sh
printf '#!/bin/bash\necho GATE_RAN >&2\nexit 2\n' > "$TMP/espalier/hooks/pre-push-gate.sh"
cat > "$TMP/espalier/hooks/check-layer-boundaries.sh" << 'STUB2'
#!/bin/bash
echo "CHECKED:$1" >&2
case "$1" in *bad*) exit 2 ;; esac
exit 0
STUB2
chmod +x "$TMP/espalier/hooks/pre-push-gate.sh" "$TMP/espalier/hooks/check-layer-boundaries.sh"
touch "$TMP/src/ok.ts" "$TMP/src/bad.ts"

# run_adapter_case NAME WRAPPER JSON EXPECT_RC EXPECT_MARK("-" = none)
run_adapter_case() {
  local name=$1 wrapper=$2 json=$3 expect_rc=$4 expect_mark=$5
  local rc err="$TMP/a_err.txt"
  ( cd "$TMP" && printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR bash espalier/hooks/copilot-hook-adapter.sh "$wrapper" >/dev/null 2>"$err" )
  rc=$?
  assert "$name (rc)" "[ $rc -eq $expect_rc ]"
  if [ "$expect_mark" = "-" ]; then
    assert "$name (no dispatch)" "! grep -qE 'GATE_RAN|CHECKED:' '$err'"
  else
    assert "$name (marker)" "grep -q '$expect_mark' '$err'"
  fi
}

run_adapter_case "T10a copilot bash push payload dispatches gate" \
  pre-push-gate-wrapper.sh '{"toolName":"bash","toolArgs":{"command":"git push origin main"}}' 2 GATE_RAN
run_adapter_case "T10b copilot bash non-push exits 0" \
  pre-push-gate-wrapper.sh '{"toolName":"bash","toolArgs":{"command":"git status"}}' 0 -
run_adapter_case "T10c copilot edit payload (path field) checks file" \
  post-edit-wrapper.sh "{\"toolName\":\"edit\",\"toolArgs\":{\"path\":\"$TMP/src/bad.ts\"}}" 2 "CHECKED:.*src/bad.ts"
run_adapter_case "T10d copilot edit payload (filePath variant) clean file" \
  post-edit-wrapper.sh "{\"toolName\":\"str_replace_editor\",\"toolArgs\":{\"filePath\":\"$TMP/src/ok.ts\"}}" 0 "CHECKED:.*src/ok.ts"
run_adapter_case "T10e garbage payload passes through harmlessly" \
  post-edit-wrapper.sh 'not json at all' 0 -
# T10f: missing wrapper → exit 0, never bricks the session.
( cd "$TMP" && printf '%s' '{"toolName":"bash","toolArgs":{"command":"git push"}}' | bash espalier/hooks/copilot-hook-adapter.sh no-such-wrapper.sh >/dev/null 2>&1 )
assert "T10f missing wrapper exits 0" "[ $? -eq 0 ]"
# T10g: no python on PATH → raw passthrough; push-gate wrapper still fails CLOSED.
PBIN10="$TMP/nopython-bin"
mkdir -p "$PBIN10"
for _t in bash sh cat grep sed git dirname; do
  _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -s "$_p" "$PBIN10/$_t"
done
( cd "$TMP" && printf '%s' '{"toolName":"bash","toolArgs":{"command":"git push"}}' \
    | env -u CLAUDE_PROJECT_DIR PATH="$PBIN10" "$PBIN10/bash" espalier/hooks/copilot-hook-adapter.sh pre-push-gate-wrapper.sh >/dev/null 2>"$TMP/a_err.txt" )
T10G_RC=$?
assert "T10g no-python push still fails closed (exit 2)" "[ $T10G_RC -eq 2 ]"
assert "T10g2 BLOCKED reason on stderr" "grep -q 'BLOCKED' '$TMP/a_err.txt'"

[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T11: conv_fold / conv_observations (drift-helpers) ───────────────────
# The executable conventions reader: folds the legacy espalier/.conventions.tsv
# AND every espalier/conventions/*.tsv per-key file (same 5/6-col row format)
# into `key<TAB>diverges_count<TAB>status` lines. Width-tolerant (malformed
# rows skipped, never fatal), empty-glob safe (bash 3.2), read-time observation
# dedupe on (slug,key,location) ACROSS both sources, status precedence:
# a per-key-file status beats a legacy status; legacy honored when the key
# file has no decision.
echo "T11: conv_fold / conv_observations"
TMP=$(mktemp -d -t hooks-t11.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
printf '%s\n' \
  "$(printf '2026-01-01\tfeat/a\terror-shape\tsrc/x.ts:1\tdiverges')" \
  "$(printf '2026-01-02\tfeat/b\terror-shape\tsrc/y.ts:2\tdiverges')" \
  "$(printf '2026-01-03\tfeat/c\terror-shape\tsrc/z.ts:3\tdiverges\tlogging-style')" \
  "malformed row with no tabs" \
  "$(printf '2026-01-04\tfeat/d\tlogging-style\tsrc/l.ts:4\tpromoted')" \
  "$(printf '2026-01-05\tfeat/e\tnaming\tsrc/n.ts:5\tdiverges')" \
  "$(printf '2026-01-08\tfeat/h\tretry-style\tsrc/r.ts:8\texception')" \
  > "$TMP/espalier/.conventions.tsv"

# Legacy-only folding (no per-key dir yet — the Release A shape).
F_OUT=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_fold; echo "RC=$?")
assert "T11a legacy 5+6-col diverges rows fold (count 3)" \
  "echo \"$F_OUT\" | grep -q \"$(printf 'error-shape\t3\tdiverges')\""
assert "T11b malformed legacy row skipped, not fatal"     "echo \"$F_OUT\" | grep -q 'RC=0'"
assert "T11c legacy status row wins for its key"          \
  "echo \"$F_OUT\" | grep -q \"$(printf 'logging-style\t0\tpromoted')\""
OBS_OUT=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_observations error-shape)
OBS_CNT=$(printf '%s\n' "$OBS_OUT" | grep -c 'feat/')
assert "T11d conv_observations returns the evidence rows" "[ \"$OBS_CNT\" = '3' ]"
assert "T11e conv_observations keeps coupled_with column" \
  "echo \"$OBS_OUT\" | grep -q 'logging-style'"

# Empty per-key dir: bash 3.2 iterates the literal *.tsv pattern — must not die.
mkdir -p "$TMP/espalier/conventions"
F_EMPTY=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_fold; echo "RC=$?")
assert "T11f empty per-key dir is glob-safe"              "echo \"$F_EMPTY\" | grep -q 'RC=0'"
assert "T11g empty dir leaves legacy counts intact"       \
  "echo \"$F_EMPTY\" | grep -q \"$(printf 'error-shape\t3\tdiverges')\""

# Per-key files alongside the legacy file (the B-team shape; A's reader must
# already understand it — readers-first contract).
printf '2026-01-06\tfeat/f\terror-shape\tsrc/w.ts:6\tdiverges\n2026-01-01\tfeat/a\terror-shape\tsrc/x.ts:1\tdiverges\nbad row\n' \
  > "$TMP/espalier/conventions/k-error-shape.tsv"
printf '2026-01-07\tfeat/g\tnaming\tsrc/n2.ts:7\trejected\n' \
  > "$TMP/espalier/conventions/k-naming.tsv"
printf '2026-01-09\tfeat/i\tretry-style\tsrc/r2.ts:9\tpromoted\n' \
  > "$TMP/espalier/conventions/k-retry-style.tsv"
F_MIX=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_fold; echo "RC=$?")
assert "T11h cross-source duplicate observation counted once (3+1 new = 4)" \
  "echo \"$F_MIX\" | grep -q \"$(printf 'error-shape\t4\tdiverges')\""
assert "T11i key-file status beats legacy diverges"       \
  "echo \"$F_MIX\" | grep -q \"$(printf 'naming\t1\trejected')\""
assert "T11j key-file status beats legacy status"         \
  "echo \"$F_MIX\" | grep -q \"$(printf 'retry-style\t0\tpromoted')\""
assert "T11k legacy status honored when key file has none" \
  "echo \"$F_MIX\" | grep -q \"$(printf 'logging-style\t0\tpromoted')\""
assert "T11l malformed key-file row skipped, not fatal"   "echo \"$F_MIX\" | grep -q 'RC=0'"

# Dir-only folding (legacy file absent — a fresh v0.17+ repo).
rm -f "$TMP/espalier/.conventions.tsv"
F_DIR=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_fold; echo "RC=$?")
assert "T11m dir-only folding works without a legacy file" \
  "echo \"$F_DIR\" | grep -q \"$(printf 'error-shape\t2\tdiverges')\" && echo \"$F_DIR\" | grep -q 'RC=0'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T12: doctor_due v2 — tracked shared stamp (clean/dirty semantics) ────
# Only a fresh `clean` shared stamp satisfies team-wide; a `dirty` stamp
# satisfies only the writing clone (via its gitignored local stamp, which the
# doctor keeps writing). A stamp beyond now+25h skew is rejected (reads as
# absent → due). Restamp-clean: a session that scans dirty, prunes all, and
# re-scans ends with a clean stamp — no team-wide nag deadlock.
echo "T12: doctor_due v2 (shared .doctor-stamp)"
TMP=$(mktemp -d -t hooks-t12.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
echo "cadence: weekly" > "$TMP/espalier/.doctor-cadence"

d_due() { ( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_due 2>/dev/null && echo DUE || echo NOT_DUE ); }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

assert "T12a no stamp at all → due" "[ \"$(d_due)\" = 'DUE' ]"
( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared deadbeef clean )
assert "T12b fresh clean shared stamp satisfies team-wide" "[ \"$(d_due)\" = 'NOT_DUE' ]"
( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared deadbeef dirty:3 )
assert "T12c fresh dirty shared stamp does NOT satisfy a non-writer clone" "[ \"$(d_due)\" = 'DUE' ]"
# The writing clone is satisfied via its LOCAL stamp (doctor keeps writing it).
( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_stamp deadbeef )
assert "T12d dirty shared + fresh local stamp satisfies the writer clone" "[ \"$(d_due)\" = 'NOT_DUE' ]"
rm -f "$TMP/espalier/.doctor-last-run"
# Future-dated clean stamp (now + 2 days) must be REJECTED, not honored.
if [ "$(uname)" = "Darwin" ]; then FUT=$(date -u -v+2d +%Y-%m-%dT%H:%M:%SZ); else FUT=$(date -u -d '+2 days' +%Y-%m-%dT%H:%M:%SZ); fi
printf '%s\tdeadbeef\tt@t\tclean\n' "$FUT" > "$TMP/espalier/.doctor-stamp"
assert "T12e future-skewed clean stamp rejected (reads as absent → due)" "[ \"$(d_due)\" = 'DUE' ]"
D_WARN=$( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_due 2>&1 >/dev/null; true )
assert "T12f skew rejection warns on stderr" "echo \"$D_WARN\" | grep -qi 'future'"
# Malformed stamp → due, never fatal.
echo "not a stamp" > "$TMP/espalier/.doctor-stamp"
assert "T12g malformed stamp reads as absent (due)" "[ \"$(d_due)\" = 'DUE' ]"
# Restamp-clean flow: dirty stamp then (after prune cleared all) clean stamp.
( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared aaa dirty:2 && doctor_stamp_shared bbb clean )
assert "T12h restamp-clean ends NOT due (deadlock case closed)" "[ \"$(d_due)\" = 'NOT_DUE' ]"
STAMP_LINES=$(wc -l < "$TMP/espalier/.doctor-stamp" | tr -d ' ')
assert "T12i stamp stays ONE line (last-writer-wins, never append)" "[ \"$STAMP_LINES\" = '1' ]"
D_BAD=$( cd "$TMP" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared ccc bogus 2>&1; echo "RC=$?" )
assert "T12j invalid result vocabulary refused" "echo \"$D_BAD\" | grep -q 'RC=1'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T13: conv_slug — per-key filename stem ───────────────────────────────
echo "T13: conv_slug"
TMP=$(mktemp -d -t hooks-t13.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
c_slug() { ( cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_slug "$1" ); }
assert "T13a plain key passes through"        "[ \"$(c_slug error-shape)\" = 'error-shape' ]"
assert "T13b slash + space map to underscore" "[ \"$(c_slug 'api/v2 retry')\" = 'api_v2_retry' ]"
SLUG_UTF=$(c_slug 'Näming.stylé')
assert "T13c UTF-8 maps into the safe charset" \
  "case \"$SLUG_UTF\" in *[!A-Za-z0-9._-]*) false ;; N*g.styl*) true ;; *) false ;; esac"
assert "T13d empty key becomes underscore"    "[ \"$(c_slug '')\" = '_' ]"
# Reserved names are made safe by the fixed k- FILE prefix, not by the slug:
# aux → k-aux.tsv can never collide with Windows' reserved 'aux'.
KF=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && append_convention feat/x aux src/a.ts:1 && ls espalier/conventions)
assert "T13e reserved key writes k-prefixed file" "[ \"$KF\" = 'k-aux.tsv' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T14: append_convention v2 — per-key writer ───────────────────────────
echo "T14: append_convention v2 (file-per-key)"
TMP=$(mktemp -d -t hooks-t14.XXXX)
make_repo "$TMP"
install_hooks "$TMP"
# Legacy row exists for the same observation — cross-file dedupe must hold.
printf '2026-01-01\tfeat/a\terror-shape\tsrc/x.ts:1\tdiverges\n' > "$TMP/espalier/.conventions.tsv"
( cd "$TMP" && . espalier/hooks/drift-helpers.sh && \
  append_convention feat/a error-shape src/x.ts:1 && \
  append_convention feat/b error-shape src/y.ts:2 && \
  append_convention feat/b error-shape src/y.ts:2 && \
  append_convention feat/c logging-style src/l.ts:3 coupling-key )
assert "T14a key file created under espalier/conventions/" \
  "[ -f '$TMP/espalier/conventions/k-error-shape.tsv' ]"
assert "T14b duplicate-vs-legacy observation NOT re-appended" \
  "! grep -q 'src/x.ts:1' '$TMP/espalier/conventions/k-error-shape.tsv'"
Y_CNT=$(grep -c 'src/y.ts:2' "$TMP/espalier/conventions/k-error-shape.tsv" 2>/dev/null)
assert "T14c writer-side dedupe within the key file" "[ \"$Y_CNT\" = '1' ]"
assert "T14d coupled_with lands as 6th column" \
  "grep -q 'coupling-key' '$TMP/espalier/conventions/k-logging-style.tsv'"
LEG_LINES=$(wc -l < "$TMP/espalier/.conventions.tsv" | tr -d ' ')
assert "T14e v0.17 writer NEVER touches the legacy file" "[ \"$LEG_LINES\" = '1' ]"
# In-place status flip in the key file — conv_fold sees the decision.
sed_flip() { if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi; }
sed_flip 's/\tdiverges$/\tpromoted/' "$TMP/espalier/conventions/k-error-shape.tsv"
F14=$(cd "$TMP" && . espalier/hooks/drift-helpers.sh && conv_fold)
assert "T14f in-place flip in key file wins over legacy diverges row" \
  "echo \"$F14\" | grep -q \"$(printf 'error-shape\t1\tpromoted')\""
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T15: two-clone sims — shared stamp + per-key merge behavior ──────────
echo "T15: two-clone sims (stamp semantics, per-key conflicts)"
BASE=$(mktemp -d -t hooks-t15.XXXX)
ORIGIN="$BASE/origin.git"
A="$BASE/cloneA"; B="$BASE/cloneB"
git init -q --bare --initial-branch=main "$ORIGIN"
git clone -q "$ORIGIN" "$A" 2>/dev/null
( cd "$A" && git checkout -qb main 2>/dev/null; true )
install_hooks "$A"
mkdir -p "$A/espalier/conventions"
echo "cadence: weekly" > "$A/espalier/.doctor-cadence"
printf '2026-01-01\tfeat/1\tkey-x\tsrc/a.ts:1\tdiverges\n2026-01-02\tfeat/2\tkey-x\tsrc/b.ts:2\tdiverges\n2026-01-03\tfeat/3\tkey-x\tsrc/c.ts:3\tdiverges\n' > "$A/espalier/conventions/k-key-x.tsv"
( cd "$A" && git add -A && git -c user.email=a@t -c user.name=a commit -qm base && git push -q origin main )
git clone -q "$ORIGIN" "$B" 2>/dev/null

# a) dirty stamp from clone A does not satisfy clone B; clean does.
( cd "$A" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared s1 dirty:2 && git add espalier/.doctor-stamp && git -c user.email=a@t -c user.name=a commit -qm "doctor: dirty" && git push -q origin main )
( cd "$B" && git pull -q origin main )
B_DUE=$( cd "$B" && . espalier/hooks/drift-helpers.sh && doctor_due 2>/dev/null && echo DUE || echo NOT_DUE )
assert "T15a clone A's dirty stamp leaves clone B due" "[ \"$B_DUE\" = 'DUE' ]"
( cd "$A" && . espalier/hooks/drift-helpers.sh && doctor_stamp_shared s2 clean && git add espalier/.doctor-stamp && git -c user.email=a@t -c user.name=a commit -qm "doctor: clean" && git push -q origin main )
( cd "$B" && git pull -q origin main )
B_DUE2=$( cd "$B" && . espalier/hooks/drift-helpers.sh && doctor_due 2>/dev/null && echo DUE || echo NOT_DUE )
assert "T15b clone A's clean stamp satisfies clone B" "[ \"$B_DUE2\" = 'NOT_DUE' ]"

# b) same-key promotion race → git conflict in EXACTLY that key file.
( cd "$A" && if [ "$(uname)" = "Darwin" ]; then sed -i '' 's/\tdiverges$/\tpromoted/' espalier/conventions/k-key-x.tsv; else sed -i 's/\tdiverges$/\tpromoted/' espalier/conventions/k-key-x.tsv; fi \
  && git add -A && git -c user.email=a@t -c user.name=a commit -qm "promote key-x" && git push -q origin main )
( cd "$B" && if [ "$(uname)" = "Darwin" ]; then sed -i '' 's/\tdiverges$/\trejected/' espalier/conventions/k-key-x.tsv; else sed -i 's/\tdiverges$/\trejected/' espalier/conventions/k-key-x.tsv; fi \
  && git add -A && git -c user.email=b@t -c user.name=b commit -qm "reject key-x" )
MERGE_OUT=$( cd "$B" && git pull --no-rebase -q origin main 2>&1; echo "RC=$?" )
CONFLICTS=$( cd "$B" && git diff --name-only --diff-filter=U )
assert "T15c same-key double decision CONFLICTS (structural race detection)" "echo \"$MERGE_OUT\" | grep -q 'RC=1'"
assert "T15d conflict confined to exactly that key file" "[ \"$CONFLICTS\" = 'espalier/conventions/k-key-x.tsv' ]"
( cd "$B" && git checkout --theirs espalier/conventions/k-key-x.tsv 2>/dev/null && git add -A && git -c user.email=b@t -c user.name=b commit -qm "resolve: keep promoted" )

# c) different-key concurrent writes merge clean.
( cd "$A" && git pull -q origin main 2>/dev/null; . espalier/hooks/drift-helpers.sh && append_convention feat/4 key-a src/d.ts:4 && git add -A && git -c user.email=a@t -c user.name=a commit -qm "obs key-a" && git push -q origin main )
( cd "$B" && . espalier/hooks/drift-helpers.sh && append_convention feat/5 key-b src/e.ts:5 && git add -A && git -c user.email=b@t -c user.name=b commit -qm "obs key-b" )
DK_OUT=$( cd "$B" && git pull --no-rebase -q origin main 2>&1; echo "RC=$?" )
assert "T15e different-key concurrent writes merge clean" "echo \"$DK_OUT\" | grep -q 'RC=0'"
( cd "$B" && git push -q origin main )

# d) flip-vs-append on ONE key. The plan's auto-merge expectation was an
# EMPIRICAL hunk-adjacency claim (§7) — measured here: git's xdiff treats a
# tail-modify and an EOF-append as overlapping and CONFLICTS. Per §7 the case
# degrades to the keep-both playbook (flipped rows + appended observation),
# never to data loss — this sim asserts that contract.
( cd "$A" && git pull -q origin main )
( cd "$A" && if [ "$(uname)" = "Darwin" ]; then sed -i '' 's/\tdiverges$/\texception/' espalier/conventions/k-key-a.tsv; else sed -i 's/\tdiverges$/\texception/' espalier/conventions/k-key-a.tsv; fi \
  && git add -A && git -c user.email=a@t -c user.name=a commit -qm "exception key-a" && git push -q origin main )
( cd "$B" && . espalier/hooks/drift-helpers.sh && append_convention feat/6 key-a src/f.ts:6 && git add -A && git -c user.email=b@t -c user.name=b commit -qm "obs2 key-a" )
FA_OUT=$( cd "$B" && git pull --no-rebase -q origin main 2>&1; echo "RC=$?" )
FA_CONFLICTS=$( cd "$B" && git diff --name-only --diff-filter=U )
assert "T15f flip-vs-append conflicts confined to that key file (playbook case)" \
  "echo \"$FA_OUT\" | grep -q 'RC=1' && [ \"$FA_CONFLICTS\" = 'espalier/conventions/k-key-a.tsv' ]"
# Keep-both resolution: the decided (flipped) rows AND the fresh observation.
( cd "$B" && printf '' > espalier/conventions/k-key-a.tsv \
  && git show MERGE_HEAD:espalier/conventions/k-key-a.tsv >> espalier/conventions/k-key-a.tsv \
  && git show HEAD:espalier/conventions/k-key-a.tsv | grep 'src/f.ts:6' >> espalier/conventions/k-key-a.tsv \
  && git add -A && git -c user.email=b@t -c user.name=b commit -qm "resolve: keep decided rows + fresh observation" )
FA_FOLD=$( cd "$B" && . espalier/hooks/drift-helpers.sh && conv_fold | grep '^key-a' )
assert "T15g keep-both resolution folds decided-plus-one-fresh-observation" \
  "echo \"$FA_FOLD\" | grep -q \"$(printf 'key-a\t1\texception')\""
[ "$KEEP" != "yes" ] && rm -rf "$BASE"

# ─── T16: map-guard.sh — /espalier-map plan-don't-do write guard ──────────
echo "T16: map-guard"
MGUARD="$HOOKS_SRC/map-guard.sh"
TMP=$(mktemp -d -t hooks-t16.XXXX)
make_repo "$TMP"
mkdir -p "$TMP/espalier/maps" "$TMP/src"

# run_mguard NAME JSON EXPECT_RC (env CLAUDE_PROJECT_DIR pins ROOT to the fixture)
run_mguard() {
  local name=$1 json=$2 want=$3
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$TMP" bash "$MGUARD" >/dev/null 2>"$TMP/mg.err"
  local rc=$?
  assert "$name" "[ $rc -eq $want ]"
}

# 16a: no marker → allow anything.
run_mguard "16a no marker allows write" '{"tool_input":{"file_path":"src/a.ts"}}' 0

# 16b-d: fresh marker → block outside, allow maps, block by stderr contract.
printf 'map: t16\nsession_started: now\n' > "$TMP/espalier/maps/.active-session"
run_mguard "16b marker blocks outside write" '{"tool_input":{"file_path":"src/a.ts"}}' 2
assert "16c blocked reason on stderr" "grep -q 'BLOCKED by map-guard' '$TMP/mg.err'"
run_mguard "16d maps-path write allowed" "{\"tool_input\":{\"file_path\":\"$TMP/espalier/maps/x/map.md\"}}" 0

# 16e-f: approved allow-window prefix passes; traversal/absolute prefixes ignored.
printf 'allow: scaffold/\n' >> "$TMP/espalier/maps/.active-session"
run_mguard "16e allow-window prefix passes" '{"tool_input":{"file_path":"scaffold/package.json"}}' 0
printf 'allow: ../\nallow: /etc/\n' >> "$TMP/espalier/maps/.active-session"
run_mguard "16f escape prefixes ignored (still blocks)" '{"tool_input":{"file_path":"src/b.ts"}}' 2

# 16g: apply_patch body paths are extracted and blocked.
run_mguard "16g apply_patch body blocked" '{"tool_input":{"command":"*** Update File: src/c.ts\nbody"}}' 2

# 16h: writes outside the repo are out of scope.
run_mguard "16h outside-repo path allowed" '{"tool_input":{"file_path":"/tmp/elsewhere/x.md"}}' 0

# 16i: stale marker (>12h mtime) reads as inactive.
touch -t 202601010000 "$TMP/espalier/maps/.active-session"
run_mguard "16i stale marker allows write" '{"tool_input":{"file_path":"src/a.ts"}}' 0

# 16j: camelCase payload through the copilot adapter still blocks.
printf 'map: t16\nsession_started: now\n' > "$TMP/espalier/maps/.active-session"
mkdir -p "$TMP/espalier/hooks"
cp "$MGUARD" "$TMP/espalier/hooks/map-guard.sh"
cp "$HOOKS_SRC/copilot-hook-adapter.sh" "$TMP/espalier/hooks/copilot-hook-adapter.sh"
chmod +x "$TMP/espalier/hooks/"*.sh
printf '%s' '{"toolName":"write","toolArgs":{"path":"src/a.ts"}}' \
  | ( cd "$TMP" && CLAUDE_PROJECT_DIR="$TMP" bash espalier/hooks/copilot-hook-adapter.sh map-guard.sh ) >/dev/null 2>&1
assert "16j copilot camelCase payload blocked via adapter" "[ $? -eq 2 ]"
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
