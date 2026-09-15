#!/bin/bash
# Regression tests for the mechanical hook layer:
#   - lookup-helpers.sh   (_fuzzy_file_overlap_match, _dedupe_entries_preserve_primary, _cache_append)
#   - post-merge-backlink.sh (squash detection + hardened overlap match)
#   - rebuild-commit-index.sh (section parsing)
#   - pre-push-gate.sh    (active-change selection, certificate, test-count parse,
#                          exit-2 blocking contract, secret scan, corrupt-state fail-closed)
#   - pre-push-gate-wrapper.sh (push detection matrix, fail-closed python probe)
#   - drift-helpers.sh    (mark/clear/tier, interactivity_mode; the v0.25 context helpers;
#                          the v0.26 turn-economy helpers + gate scoping)
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
# 14 blocking `exit 2` statements (10 serial-path + 4 in the v0.22 parallel
# section) and zero blocking `exit 1`.
TMP5=$(mktemp -d -t hooks-t5l.XXXX)
make_repo "$TMP5"
install_hooks "$TMP5"
make_gate "$TMP5" "echo '3 passed'"
assert "T5l installed gate has 14 'exit 2' sites" \
  "[ \"\$(grep -c 'exit 2' '$TMP5/espalier/hooks/pre-push-gate.sh')\" = '14' ]"
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

# T5q: certificate read is ANCHORED — a Stage History note quoting
# "Base-Ref:"/"Reviewed-Diff:" in prose must not outrank the real Status-block
# lines (v0.22 field find: unanchored last-match produced a bogus revision +
# empty-diff fingerprint and a false BLOCK on a correctly certified change).
TMP9=$(mktemp -d -t hooks-t5q.XXXX)
make_repo "$TMP9"
install_hooks "$TMP9"
make_gate "$TMP9" "echo '3 passed'"
T5Q_BASE=$(cd "$TMP9" && git rev-parse HEAD)
echo change > "$TMP9/work.txt"
( cd "$TMP9" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "fix change" )
T5Q_FP=$(cd "$TMP9" && git diff "$T5Q_BASE" -- . ':(exclude)espalier/' | git hash-object --stdin)
state_file "$TMP9" fix 2026-01-01-prose 7 IN_PROGRESS
{
  printf -- '- Base-Ref: %s\n- Reviewed-Diff: %s\n' "$T5Q_BASE" "$T5Q_FP"
  printf '| 0 | PASSED | 2026-01-01T10:00:00Z | rejected a Layer 1 match anchored at Base-Ref: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef (prose quote, not the certificate) |\n'
} >> "$TMP9/espalier/changes/fix/2026-01-01-prose/pipeline-state.md"
( cd "$TMP9" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP9/err.txt" )
T5Q_RC=$?
assert "T5q prose-quoted anchor token never outranks the real certificate (exit 0)" \
  "[ $T5Q_RC -eq 0 ] && ! grep -q 'Reviewed-Diff mismatch' '$TMP9/err.txt'"

[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2" "$TMP3" "$TMP4" "$TMP5" "$TMP6" "$TMP7" "$TMP8" "$TMP9"

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

# ─── T17: espalier-stats.sh — lane-quality report over synthetic audit data ──
echo "T17: espalier-stats"
STATS="$HOOKS_SRC/espalier-stats.sh"
TMP=$(mktemp -d -t hooks-t17.XXXX)
make_repo "$TMP"

# 17a: no espalier/ → honest no-op.
OUT=$( cd "$TMP" && bash "$STATS" )
assert "17a no espalier dir reports nothing-to-report" "echo \"\$OUT\" | grep -q 'nothing to report'"

# Synthetic audit chain: 2 feats (one charted, one not), 1 fix caused_by the
# uncharted feat, 1 map with mixed tickets/fog/sessions.
mkdir -p "$TMP/espalier/changes/feat/2026-08-01-alpha" \
         "$TMP/espalier/changes/feat/2026-08-02-beta" \
         "$TMP/espalier/changes/fix/2026-08-03-hotfix" \
         "$TMP/espalier/maps/2026-08-05-epic/tickets"
printf -- '- Status: COMPLETE\n- Total Rollbacks: 1\n- Review Rounds: req=1/3, code=3/3, test=1/3\n| 1 | PASSED | ts | GRILLED |\n' \
  > "$TMP/espalier/changes/feat/2026-08-01-alpha/pipeline-state.md"
printf '# reqs\n' > "$TMP/espalier/changes/feat/2026-08-01-alpha/requirements.md"
printf -- '- Status: IN_PROGRESS\n- Total Rollbacks: 0\n- Review Rounds: req=1/3, code=1/3, test=0/3\n| 1 | PASSED | ts | SKIPPED: crisp |\n' \
  > "$TMP/espalier/changes/feat/2026-08-02-beta/pipeline-state.md"
printf -- '---\ncharted_from: maps/2026-08-05-epic\n---\n' \
  > "$TMP/espalier/changes/feat/2026-08-02-beta/requirements.md"
printf -- '- Status: COMPLETE\n- Total Rollbacks: 0\n- Review Rounds: req=1/3, code=1/3, test=1/3\n' \
  > "$TMP/espalier/changes/fix/2026-08-03-hotfix/pipeline-state.md"
printf -- '---\ncaused_by: feat/2026-08-01-alpha\n---\n' \
  > "$TMP/espalier/changes/fix/2026-08-03-hotfix/requirements.md"
cat > "$TMP/espalier/maps/2026-08-05-epic/map.md" << 'MAPFIX'
---
map: 2026-08-05-epic
status: IN_PROGRESS
---
## Not yet specified
<!-- comment -->
- auth provider still fuzzy
## Session log
| Date | Ticket | Action |
|------|--------|--------|
| d1 | 001 | resolved |
| d2 | 002 | resolved |
## Spawned Changes
| Change | Status |
|--------|--------|
| feat/2026-08-02-beta | FILED |
MAPFIX
printf -- '---\nticket: 001\ntype: grilling\nstatus: closed\n---\n' > "$TMP/espalier/maps/2026-08-05-epic/tickets/001-a.md"
printf -- '---\nticket: 002\ntype: research\nstatus: closed\n---\n'  > "$TMP/espalier/maps/2026-08-05-epic/tickets/002-b.md"
printf -- '---\nticket: 003\ntype: task\nstatus: open\n---\n'       > "$TMP/espalier/maps/2026-08-05-epic/tickets/003-c.md"

OUT=$( cd "$TMP" && bash "$STATS" )
assert "17b lane counts + statuses"      "echo \"\$OUT\" | grep -qF 'feat**: 2' && echo \"\$OUT\" | grep -q 'IN_PROGRESS=1 COMPLETE=1'"
assert "17c code-round distribution"     "echo \"\$OUT\" | grep -q 'code rounds: n=3 min=1 median=1 mean=1.67 max=3'"
assert "17d grill verdict mix"           "echo \"\$OUT\" | grep -q 'GRILLED=1 (light=0 full=0 untiered=1)  crisp=1  no-grill=0  non-interactive=0'"
assert "17e cohort split"                "echo \"\$OUT\" | grep -q 'charted feats:   1' && echo \"\$OUT\" | grep -q 'uncharted feats: 1'"
assert "17f cohort round means differ"   "echo \"\$OUT\" | grep -q 'charted code rounds: n=1 min=1' && echo \"\$OUT\" | grep -q 'uncharted code rounds: n=1 min=3'"
assert "17g fix echo lands on uncharted" "echo \"\$OUT\" | grep -q 'against-charted=0 against-uncharted=1 unlinked=0'"
assert "17h map ticket/type/session/fog" "echo \"\$OUT\" | grep -q 'open=1 closed=2 out-of-scope=0 (grilling=1 research=1 prototype=0 task=1) sessions=2 fog-remaining=1 spawned=1'"
assert "17i read-only (no writes)"       "[ -z \"\$(cd \"$TMP\" && git status --porcelain espalier 2>/dev/null | grep -v '^??')\" ] && [ ! -f '$TMP/espalier/.stats-report.md' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T18: espalier-stats.sh — stage durations (v0.22) ─────────────────────
echo "T18: espalier-stats stage durations"
STATS="$HOOKS_SRC/espalier-stats.sh"
TMP=$(mktemp -d -t hooks-t18.XXXX)
make_repo "$TMP"
mkdir -p "$TMP/espalier/changes/fix/2026-08-10-dur"
cat > "$TMP/espalier/changes/fix/2026-08-10-dur/pipeline-state.md" << 'DURFIX'
# Pipeline State: dur

## Status
- Current Stage: 7
- Status: COMPLETE
- Review Rounds: req=1/3, code=1/3, test=1/3
- Total Rollbacks: 0

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 0 | PASSED | 2026-08-10T10:00:00Z | Auto-linked |
| 1 | PASSED | 2026-08-10T10:20:00Z | GRILLED |
| 3 | IN_PROGRESS | 2026-08-10T10:25:00Z | |
| 4 | PASSED | 2026-08-10T10:45:00Z | reviewer PASS |
| 6 | PASSED | badstamp | tests reviewed |
| 7 | PASSED | 2026-08-10T11:10:00Z | delivery auto-accepted (non-interactive) |

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
| 7 | 9999999 | a.ts |
DURFIX
OUT=$( cd "$TMP" && bash "$STATS" )
# Span math: 0→1 = 1200s (closed by GRILLED → human); 1→3 = 300s (agent);
# 3→4 = 1200s (agent); the badstamp row breaks its spans (skipped_rows=1);
# the auto-accepted closing row must never count as human.
assert "18a per-stage duration lines" \
  "echo \"\$OUT\" | grep -q 'stage 0: n=1 min=1200s' && echo \"\$OUT\" | grep -q 'stage 1: n=1 min=300s'"
assert "18b human/agent split with unattended exclusion" \
  "echo \"\$OUT\" | grep -q 'totals: human-wait=1200s agent-work=1500s other=0s (skipped_rows=1)'"
assert "18c Commits table rows never parsed as stages" \
  "! echo \"\$OUT\" | grep -q 'stage 7:'"
assert "18d degrade guard present (python3 probe + unavailable line)" \
  "grep -q 'command -v python3' '$STATS' && grep -q 'stage durations: unavailable' '$STATS'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP"

# ─── T19: pre-push-gate.sh — parallel gate sections + audit cache (v0.22) ──
echo "T19: pre-push parallel gates + audit cache"
make_gate22() {  # dir build lint test — full three-command substitution
  local dir=$1 b=$2 l=$3 t=$4
  mkdir -p "$dir/espalier/hooks"
  sed -e "s|{build_command}|$b|g" \
      -e "s|{lint_command}|$l|g" \
      -e "s|{test_command}|$t|g" \
      "$HOOKS_SRC/pre-push-gate.sh" > "$dir/espalier/hooks/pre-push-gate.sh"
  chmod +x "$dir/espalier/hooks/pre-push-gate.sh"
}

# 19a: key present → parallel path passes end-to-end.
TMP=$(mktemp -d -t hooks-t19a.XXXX)
make_repo "$TMP"
make_gate22 "$TMP" "echo building" "echo linting" "echo '3 passed'"
state_file "$TMP" feat 2026-08-11-par 7 IN_PROGRESS
printf 'hook-parallel-gates: yes\n' > "$TMP/espalier/.espalier-config"
( cd "$TMP" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
assert "19a parallel mode passes clean gates" "[ $? -eq 0 ]"

# 19b-d: each command failing in turn blocks with ITS message, exit 2.
for spec in "false|echo linting|echo '3 passed'|Build" \
            "echo building|false|echo '3 passed'|Lint" \
            "echo building|echo linting|false|Tests"; do
  b=${spec%%|*}; rest=${spec#*|}
  l=${rest%%|*}; rest=${rest#*|}
  t=${rest%%|*}; word=${rest#*|}
  D=$(mktemp -d -t hooks-t19x.XXXX)
  make_repo "$D"
  make_gate22 "$D" "$b" "$l" "$t"
  state_file "$D" feat 2026-08-11-parf 7 IN_PROGRESS
  printf 'hook-parallel-gates: yes\n' > "$D/espalier/.espalier-config"
  ( cd "$D" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$D/err.txt" )
  rc=$?
  assert "19b $word failure blocks in parallel mode (exit 2 + message)" \
    "[ $rc -eq 2 ] && grep -q 'BLOCKED: $word fail' '$D/err.txt'"
  [ "$KEEP" != "yes" ] && rm -rf "$D"
done

# 19e: parallel no-tests-found still blocks.
TMP2=$(mktemp -d -t hooks-t19e.XXXX)
make_repo "$TMP2"
make_gate22 "$TMP2" "echo building" "echo linting" "echo '0 passed'"
state_file "$TMP2" feat 2026-08-11-notests 7 IN_PROGRESS
printf 'hook-parallel-gates: yes\n' > "$TMP2/espalier/.espalier-config"
( cd "$TMP2" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP2/err.txt" )
assert "19e parallel zero-test-count blocks" \
  "[ $? -eq 2 ] && grep -q 'No tests found' '$TMP2/err.txt'"

# 19j (v0.23): the count parse takes the LAST summary match — an intermediate
# "N tests" progress line before a "0 passed" summary must still block, and a
# real final total must win over an early progress line.
TMPJ=$(mktemp -d -t hooks-t19j.XXXX)
make_repo "$TMPJ"
make_gate22 "$TMPJ" "true" "true" "printf '5 tests\\n0 passed\\n'"
state_file "$TMPJ" feat 2026-08-11-lastcount 7 IN_PROGRESS
( cd "$TMPJ" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMPJ/err.txt" )
assert "19j last-match count: 0-passed summary blocks despite earlier '5 tests' line" \
  "[ $? -eq 2 ] && grep -q 'No tests found' '$TMPJ/err.txt'"
[ "$KEEP" != "yes" ] && rm -rf "$TMPJ"

# 19k (v0.23): the Current Stage read is line-anchored — a Stage History note
# QUOTING "Current Stage: 2" in prose must not shadow the real Status line.
TMPK=$(mktemp -d -t hooks-t19k.XXXX)
make_repo "$TMPK"
make_gate22 "$TMPK" "true" "true" "echo '3 passed'"
mkdir -p "$TMPK/espalier/changes/feat/2026-08-11-anchor"
cat > "$TMPK/espalier/changes/feat/2026-08-11-anchor/pipeline-state.md" << 'ANCH'
# Pipeline State: anchor

## Status
- Current Stage: 7
- Status: IN_PROGRESS

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 4 | ROUND 1 FAIL | ts | note quoting Current Stage: 2 in prose |
ANCH
( cd "$TMPK" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMPK/err.txt" )
assert "19k anchored stage read ignores prose quoting a lower stage" "[ $? -eq 0 ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMPK"

# ─── T20: espalier-stats.sh — v0.23 tier split + adoption nudge + digest math ─
echo "T20: espalier-stats v0.23 (grill tiers + nudge)"
STATS="$HOOKS_SRC/espalier-stats.sh"
TMP20=$(mktemp -d -t hooks-t20.XXXX)
make_repo "$TMP20"
mkdir -p "$TMP20/espalier/changes/feat/2026-08-20-t1" \
         "$TMP20/espalier/changes/feat/2026-08-21-t2" \
         "$TMP20/espalier/changes/feat/2026-08-22-t3"
printf -- '- Status: COMPLETE\n| 1 | PASSED | ts | GRILLED (light) |\n## Commits\n| Stage | SHA | Files |\n| 7 | aaa | x |\n' \
  > "$TMP20/espalier/changes/feat/2026-08-20-t1/pipeline-state.md"
printf -- '- Status: COMPLETE\n| 1 | PASSED | ts | GRILLED (full) |\n## Commits\n| Stage | SHA | Files |\n| 7 | bbb | y |\n' \
  > "$TMP20/espalier/changes/feat/2026-08-21-t2/pipeline-state.md"
printf -- '- Status: COMPLETE\n| 1 | PASSED | ts | GRILLED |\n## Commits\n| Stage | SHA | Files |\n| 7 | ccc | z |\n' \
  > "$TMP20/espalier/changes/feat/2026-08-22-t3/pipeline-state.md"
OUT=$( cd "$TMP20" && bash "$STATS" )
assert "20a tier split counts light/full/untiered" \
  "echo \"\$OUT\" | grep -q 'GRILLED=3 (light=1 full=1 untiered=1)'"
assert "20b nudge fires: key absent + 3 push rows" \
  "echo \"\$OUT\" | grep -q 'hook-parallel-gates not set'"
printf 'hook-parallel-gates: no\n' > "$TMP20/espalier/.espalier-config"
OUT=$( cd "$TMP20" && bash "$STATS" )
assert "20c nudge silent when the key is present (any value)" \
  "! echo \"\$OUT\" | grep -q 'hook-parallel-gates not set'"
rm -f "$TMP20/espalier/.espalier-config"
rm -rf "$TMP20/espalier/changes/feat/2026-08-22-t3"
OUT=$( cd "$TMP20" && bash "$STATS" )
assert "20d nudge silent below 3 gated pushes" \
  "! echo \"\$OUT\" | grep -q 'hook-parallel-gates not set'"
assert "20e stats stays read-only with the nudge section" \
  "[ ! -f '$TMP20/espalier/.espalier-config' ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP20"

# 19f-h: dependency-audit cache. package-lock WITHOUT package.json → no audit
# tool runs, but the cache records the manifest hash; a seeded matching-hash
# cache replays its warning; a lockfile change forces a fresh (clean) run;
# an expired TTL also forces a fresh run.
TMP3=$(mktemp -d -t hooks-t19f.XXXX)
make_repo "$TMP3"
make_gate22 "$TMP3" "true" "true" "echo '3 passed'"
state_file "$TMP3" feat 2026-08-11-audit 7 IN_PROGRESS
printf 'lockv1\n' > "$TMP3/package-lock.json"
( cd "$TMP3" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m lock )
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 )
assert "19f first run writes the audit cache (hash + epoch)" \
  "[ -f '$TMP3/espalier/.dep-audit-cache' ] && awk 'NR==1{exit !(length(\$1)==40 && \$2 ~ /^[0-9]+\$/)}' '$TMP3/espalier/.dep-audit-cache'"
H=$(head -1 "$TMP3/espalier/.dep-audit-cache" | cut -d' ' -f1)
printf '%s %s cached-warning-marker\n' "$H" "$(date +%s)" > "$TMP3/espalier/.dep-audit-cache"
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP3/err.txt" )
assert "19g matching hash within TTL replays the cached warning" \
  "grep -q 'WARNING (cached): cached-warning-marker' '$TMP3/err.txt'"
printf 'lockv2\n' > "$TMP3/package-lock.json"
( cd "$TMP3" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m lock2 )
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP3/err.txt" )
assert "19h lockfile change busts the cache (fresh clean run, no replay)" \
  "! grep -q 'cached-warning-marker' '$TMP3/err.txt' && ! grep -q 'cached-warning-marker' '$TMP3/espalier/.dep-audit-cache'"
H2=$(head -1 "$TMP3/espalier/.dep-audit-cache" | cut -d' ' -f1)
printf '%s %s stale-ttl-marker\n' "$H2" "$(( $(date +%s) - 8*86400 ))" > "$TMP3/espalier/.dep-audit-cache"
( cd "$TMP3" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMP3/err.txt" )
assert "19i expired TTL forces a fresh run (no replay)" \
  "! grep -q 'stale-ttl-marker' '$TMP3/err.txt'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP" "$TMP2" "$TMP3"

# ─── T21: espalier-stats.sh — simplify-lane echo (v0.24) ───────────────────
echo "T21: espalier-stats simplify-lane echo"
STATS="$HOOKS_SRC/espalier-stats.sh"
TMP21=$(mktemp -d -t hooks-t21.XXXX)
make_repo "$TMP21"
mkdir -p "$TMP21/espalier/changes"
OUT=$( cd "$TMP21" && bash "$STATS" )
assert "21a degrades to none without simplify-filed changes" \
  "echo \"\$OUT\" | grep -q 'none — no simplify-filed changes yet'"
mkdir -p "$TMP21/espalier/changes/refactor/2026-09-03-a" \
         "$TMP21/espalier/changes/refactor/2026-09-03-b" \
         "$TMP21/espalier/changes/feat/2026-09-03-c"
# a: survey-filed cut, withdrawn after a missed consumer (2 code rounds)
printf -- '---\nsimplify_from: wiki/simplify-survey.md#1\nsurvey_commit: abc1234\n---\n# refactor: retire x\n' \
  > "$TMP21/espalier/changes/refactor/2026-09-03-a/requirements.md"
cat > "$TMP21/espalier/changes/refactor/2026-09-03-a/pipeline-state.md" << 'S21A'
# Pipeline State: retire x

## Status
- Current Stage: 4
- Status: ABORTED
- Total Rollbacks: 0
- Review Rounds: req=1/3, code=2/3, test=0/3

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 4 | ROUND 1 FAIL | 2026-09-03T01:00:00Z | reviewer: FAIL p0=1 p1=0 [P0 [simplify-consumer] src/jobs.ts:12 string dispatch]; security: PASS p0=0 p1=0 |
| 4 | ABORTED | 2026-09-03T01:30:00Z | simplify: missed consumer src/jobs.ts:12 |
S21A
# b: hand-written refactor (no simplify_from), clean in 1 round
printf -- '# refactor: rename y\n' > "$TMP21/espalier/changes/refactor/2026-09-03-b/requirements.md"
printf -- '- Status: COMPLETE\n- Total Rollbacks: 1\n- Review Rounds: req=1/3, code=1/3, test=1/3\n' \
  > "$TMP21/espalier/changes/refactor/2026-09-03-b/pipeline-state.md"
# c: retirement-map slice under feat/ carrying simplify_from, clean
printf -- '---\ncharted_from: maps/2026-09-01-retire-v1\nsimplify_from: wiki/simplify-survey.md#2\nsurvey_commit: abc1234\n---\n# feat: retire v1 export\n' \
  > "$TMP21/espalier/changes/feat/2026-09-03-c/requirements.md"
printf -- '- Status: COMPLETE\n- Total Rollbacks: 0\n- Review Rounds: req=1/3, code=1/3, test=1/3\n' \
  > "$TMP21/espalier/changes/feat/2026-09-03-c/pipeline-state.md"
BEFORE21=$( cd "$TMP21" && git status --porcelain )
OUT=$( cd "$TMP21" && bash "$STATS" )
AFTER21=$( cd "$TMP21" && git status --porcelain )
assert "21b cohort sizes: 2 simplify-filed (refactor/ + feat/ slice) vs 1 hand-written refactor" \
  "echo \"\$OUT\" | grep -q '^simplify-filed changes: 2$' && echo \"\$OUT\" | grep -q '^hand-written refactors: 1$'"
assert "21c code-round distributions per cohort" \
  "echo \"\$OUT\" | grep -q 'simplify-filed code rounds: n=2 min=1 median=1.5 mean=1.50 max=2' \
   && echo \"\$OUT\" | grep -q 'hand-written refactor code rounds: n=1 min=1 median=1 mean=1.00 max=1'"
assert "21d rollbacks per cohort" \
  "echo \"\$OUT\" | grep -q 'simplify-filed rollbacks: n=2 min=0 median=0 mean=0.00 max=0' \
   && echo \"\$OUT\" | grep -q 'hand-written refactor rollbacks: n=1 min=1 median=1 mean=1.00 max=1'"
assert "21e statuses, withdrawn count, tag count" \
  "echo \"\$OUT\" | grep -q 'simplify-filed statuses: ABORTED=1 COMPLETE=1' \
   && echo \"\$OUT\" | grep -q 'withdrawn (missed consumer): 1' \
   && echo \"\$OUT\" | grep -q 'simplify tags in review snapshots: 1'"
assert "21f stats stays read-only (working tree unchanged by the run)" \
  "[ \"\$BEFORE21\" = \"\$AFTER21\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP21"

# ─── T22: v0.25 context helpers (drift-helpers.sh) + stats spawn shape + maprun stage names ──
echo "T22: v0.25 context helpers, stats spawn shape, maprun stage names"
DH="$HOOKS_SRC/drift-helpers.sh"
TMP22=$(mktemp -d -t hooks-t22.XXXX)
make_repo "$TMP22"
mkdir -p "$TMP22/espalier/hooks" "$TMP22/espalier/changes/feat/2026-09-09-a" \
         "$TMP22/backend/src/orders" "$TMP22/frontend/src/__generated__" "$TMP22/frontend/src/pages"
cp "$DH" "$TMP22/espalier/hooks/drift-helpers.sh"
cp "$HOOKS_SRC/espalier-stats.sh" "$TMP22/espalier/hooks/espalier-stats.sh"
printf 'grep-only-paths: __generated__/ schema.graphql\n' > "$TMP22/espalier/.espalier-config"
head -c 2100 /dev/zero | tr '\0' 'x' > "$TMP22/frontend/src/__generated__/graphql.ts"
echo 'type Q' > "$TMP22/schema.graphql"
echo '# fe' > "$TMP22/frontend/CLAUDE.md"; echo '# be' > "$TMP22/backend/CLAUDE.md"
echo '# be agents' > "$TMP22/backend/AGENTS.md"; echo '# orders' > "$TMP22/backend/src/orders/CLAUDE.md"
echo '# root' > "$TMP22/CLAUDE.md"
touch "$TMP22/backend/src/orders/a.test.ts" "$TMP22/backend/src/orders/b.test.ts"
cat > "$TMP22/espalier/hooks/pre-push-gate.sh" << 'G22'
#!/bin/bash
run_build() {
  echo building
  { echo inner-group; true; }
}
gate_build_section() { :; }
run_lint() {
  true  # no lint command discovered at init
}
run_tests() {
  cd backend && npm test
}
G22
( cd "$TMP22" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null )
CH22="$TMP22/espalier/changes/feat/2026-09-09-a"
printf '## Coding Report\n- Files modified: backend/src/orders/a.ts\n- Test files: backend/src/orders/a.test.ts, backend/src/orders/b.test.ts\n' > "$CH22/coding-report.md"

# 22a report_archive: NN numbering, label sanitised, no-op when absent
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && report_archive "$CH22" "handoff-1" && printf 'r2\n' > "$CH22/coding-report.md" && report_archive "$CH22" "round1 fix" && report_archive "$CH22" "gone"; echo "rc=$?" )
assert "22a report_archive numbers 01, 02; sanitises the label; no-op (rc 0) when no report exists" \
  "[ -f '$CH22/coding-log/01-handoff-1.md' ] && [ -f '$CH22/coding-log/02-round1_fix.md' ] && [ ! -f '$CH22/coding-report.md' ] && echo \"\$OUT\" | grep -q 'rc=0'"
printf '## Coding Report\n- Test files: backend/src/orders/a.test.ts, backend/src/orders/b.test.ts\n' > "$CH22/coding-report.md"

# 22b contract_extract: block to the next heading, VERDICT dropped; exit 1 when absent
printf '## Security Audit: a (round 1)\n**Verdict:** PASS\n### Summary\n- x\n\n## Security-Sensitive Fields\n- field: cartId\n  abuse_test: "a"\n\nVERDICT: PASS p0=0 p1=0 round=1\n' > "$CH22/security-record.md"
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && contract_extract "$CH22"; echo "rc=$?"; contract_extract "$TMP22/espalier/changes/feat/none"; echo "rc=$?" )
assert "22b contract_extract writes the Security-Sensitive Fields block (no VERDICT line) and exits 1 when the record is absent" \
  "[ \"\$(head -1 '$CH22/security-contract.md')\" = '## Security-Sensitive Fields' ] && grep -q 'field: cartId' '$CH22/security-contract.md' \
   && ! grep -q '^VERDICT' '$CH22/security-contract.md' && ! grep -q 'Security Audit' '$CH22/security-contract.md' \
   && echo \"\$OUT\" | grep -q 'rc=0' && echo \"\$OUT\" | grep -q 'rc=1'"

# 22c req_shape_check: headings outside the contract set only; fenced headings skipped
printf '# Feat\n## 1. Requirement Summary\n## 2. Acceptance Criteria\n## Design Rationale\n### Alternatives considered\n## Open Questions\n## Resolved by grill\n```\n## fenced\n```\n## Out of scope\n' > "$CH22/requirements.md"
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && req_shape_check "$CH22"; echo "rc=$?" )
assert "22c req_shape_check lists only the three headings outside the contract set, always exit 0" \
  "[ \"\$(echo \"\$OUT\" | grep -c 'requirements-notes.md')\" -eq 3 ] && echo \"\$OUT\" | grep -q '^Design Rationale → requirements-notes.md' \
   && echo \"\$OUT\" | grep -q '^Resolved by grill → ' && ! echo \"\$OUT\" | grep -q 'fenced' && ! echo \"\$OUT\" | grep -q 'Acceptance' && echo \"\$OUT\" | grep -q 'rc=0'"

# 22d grep_only_files: patterns from .espalier-config, tracked files, sizes in KB
OUT=$( cd "$TMP22/backend" && . ../espalier/hooks/drift-helpers.sh && grep_only_files )
assert "22d grep_only_files lists tracked matches with sizes, from any cwd" \
  "echo \"\$OUT\" | grep -q '^frontend/src/__generated__/graphql.ts (3 KB)$' && echo \"\$OUT\" | grep -q '^schema.graphql (1 KB)$' && [ \"\$(echo \"\$OUT\" | grep -c .)\" -eq 2 ]"

# 22e scoped_docs: root excluded, nearest last, de-duplicated, absolute paths accepted
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && scoped_docs backend/src/orders/a.ts frontend/src/pages/Home.tsx "$TMP22/backend/src/orders/b.ts" )
assert "22e scoped_docs: nearest last, root CLAUDE.md excluded, de-duplicated across paths" \
  "[ \"\$(echo \"\$OUT\" | tr '\n' ' ')\" = 'backend/AGENTS.md backend/CLAUDE.md backend/src/orders/CLAUDE.md frontend/CLAUDE.md ' ]"

# 22f rule_bullets + the Removed-rules comm on a known pair
printf '# R\n- Rule one: do X.\n  continued `a.ts:1`.\n  - nested detail\n- Rule two.\n| Tier | Rule |\n|------|------|\n| P0 | row rule |\nProse line.\n```\n- fenced bullet\n```\n' > "$TMP22/cur.md"
printf '# R\n- Rule one: do X. continued `a.ts:1`. - nested detail\n| Tier | Rule |\n|---|---|\n| P0 | row rule |\n' > "$TMP22/new.md"
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && rule_bullets cur.md )
REMOVED=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && comm -23 <(rule_bullets cur.md | sort) <(rule_bullets new.md | sort) )
assert "22f rule_bullets folds continuation + nested lines, keeps table body rows, skips fences and prose; comm shows exactly the dropped rule" \
  "[ \"\$(echo \"\$OUT\" | grep -c .)\" -eq 4 ] && echo \"\$OUT\" | grep -q '^Rule one: do X. continued \`a.ts:1\`. - nested detail$' \
   && ! echo \"\$OUT\" | grep -q 'fenced' && ! echo \"\$OUT\" | grep -q 'Prose' && [ \"\$REMOVED\" = 'Rule two.' ]"

# 22g contract_drift_lines: one SHA, one date, one shell line, one history phrase; clean lines silent
printf '# Rules\n- one rule `a.ts:1`.\n- the commit abc1234 fixed it.\n- rotated on 2026-01-02.\n- run `npm test` first.\n- helper was deleted in v0.9.\n- decade facade (no digit, not a SHA).\n' > "$TMP22/drift.md"
OUT=$( cd "$TMP22" && . espalier/hooks/drift-helpers.sh && contract_drift_lines drift.md )
assert "22g contract_drift_lines tags sha / date / shell / history and nothing else" \
  "[ \"\$(echo \"\$OUT\" | grep -c .)\" -eq 4 ] && echo \"\$OUT\" | grep -q \"^3	sha	\" && echo \"\$OUT\" | grep -q \"^4	date	\" \
   && echo \"\$OUT\" | grep -q \"^5	shell	\" && echo \"\$OUT\" | grep -q \"^6	history	\""

# 22h-l exit_gate: brace-depth extraction (inner group), scoped test command, exit 1 on a red job with its log path,
# exit 2 naming a missing / unparseable function, exit 3 on the greenfield placeholder — under bash AND zsh (the
# orchestrator may source the helpers from either).
for SH22 in bash zsh; do
  command -v "$SH22" >/dev/null 2>&1 || continue
  DEF=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; _gate_fn_def espalier/hooks/pre-push-gate.sh run_build' )
  SC=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; _gate_scoped_cmd "$(_gate_fn_def espalier/hooks/pre-push-gate.sh run_tests)" backend/src/orders/a.test.ts backend/src/orders/b.test.ts' )
  GO=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; _gate_scoped_cmd "$(printf "run_tests() {\n  go test ./...\n}")" pkg/a/a_test.go pkg/b/b_test.go' )
  CARGO=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; _gate_scoped_cmd "$(printf "run_tests() {\n  cargo test\n}")" a.rs' )
  assert "22h [$SH22] _gate_fn_def keeps an inner brace group; scoped test command for npm-in-workspace and go packages; full suite (empty) for cargo" \
    "[ \"\$(printf '%s\n' \"\$DEF\" | grep -c .)\" -eq 4 ] && printf '%s\n' \"\$DEF\" | grep -q 'inner-group' \
     && [ \"\$SC\" = 'cd backend && npm test -- src/orders/a.test.ts src/orders/b.test.ts' ] \
     && [ \"\$GO\" = 'go test ./pkg/a/ ./pkg/b/' ] && [ -z \"\$CARGO\" ]"
  OUT=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  assert "22i [$SH22] exit_gate: build + lint green lines, tests red (2 files, npm absent → exit 1 with a log path)" \
    "echo \"\$OUT\" | grep -q '^build: exit 0$' && echo \"\$OUT\" | grep -q '^lint: exit 0$' \
     && echo \"\$OUT\" | grep -q '^tests: exit [1-9][0-9]* (2 files) — log: ' && echo \"\$OUT\" | grep -q 'rc=1'"
  sed 's/^  cd backend \&\& npm test$/  true/' "$TMP22/espalier/hooks/pre-push-gate.sh" > "$TMP22/g.tmp" && mv "$TMP22/g.tmp" "$TMP22/espalier/hooks/pre-push-gate.sh"
  OUT=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  assert "22j [$SH22] exit_gate green: exit 0, tests line says full suite (a bare true is not path-scopable)" \
    "echo \"\$OUT\" | grep -q '^tests: exit 0 (full suite)$' && echo \"\$OUT\" | grep -q 'rc=0'"
  sed 's/^  true  # no lint command discovered at init$/  echo lint-broken; false/' "$TMP22/espalier/hooks/pre-push-gate.sh" > "$TMP22/g.tmp" && mv "$TMP22/g.tmp" "$TMP22/espalier/hooks/pre-push-gate.sh"
  OUT=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  LOG22=$(echo "$OUT" | sed -n 's/^lint: exit 1 — log: //p')
  assert "22k [$SH22] exit_gate red lint: exit 1, per-job line with a log path holding the lint output; tests still run" \
    "echo \"\$OUT\" | grep -q '^lint: exit 1 — log: ' && [ -n \"\$LOG22\" ] && grep -q 'lint-broken' \"\$LOG22\" && echo \"\$OUT\" | grep -q '^tests: exit 0' && echo \"\$OUT\" | grep -q 'rc=1'"
  cp "$TMP22/espalier/hooks/pre-push-gate.sh" "$TMP22/gate.keep"
  sed '/^run_lint()/,/^}/d' "$TMP22/espalier/hooks/pre-push-gate.sh" > "$TMP22/g.tmp" && mv "$TMP22/g.tmp" "$TMP22/espalier/hooks/pre-push-gate.sh"
  OUT_MISSING=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  printf '#!/bin/bash\nrun_build() {\n  true\n}\nrun_lint() {\n  if then\n}\nrun_tests() {\n  true\n}\n' > "$TMP22/espalier/hooks/pre-push-gate.sh"
  OUT_BAD=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  printf '#!/bin/bash\n# greenfield placeholder — real gate is written by /espalier-init Pass 2\nexit 0\n' > "$TMP22/espalier/hooks/pre-push-gate.sh"
  OUT_GF=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  cp "$TMP22/gate.keep" "$TMP22/espalier/hooks/pre-push-gate.sh"; touch "$TMP22/espalier/.greenfield"
  OUT_GF2=$( cd "$TMP22" && $SH22 -c '. espalier/hooks/drift-helpers.sh; exit_gate espalier/changes/feat/2026-09-09-a; echo "rc=$?"' )
  rm -f "$TMP22/espalier/.greenfield"
  assert "22l [$SH22] exit_gate: exit 2 naming run_lint when missing or unparseable; exit 3 on the placeholder gate and on the .greenfield marker" \
    "echo \"\$OUT_MISSING\" | grep -q 'exit_gate: run_lint not found / not parseable' && echo \"\$OUT_MISSING\" | grep -q 'rc=2' \
     && echo \"\$OUT_BAD\" | grep -q 'exit_gate: run_lint not found / not parseable' && echo \"\$OUT_BAD\" | grep -q 'rc=2' \
     && echo \"\$OUT_GF\" | grep -q 'no gate yet' && echo \"\$OUT_GF\" | grep -q 'rc=3' \
     && echo \"\$OUT_GF2\" | grep -q 'no gate yet' && echo \"\$OUT_GF2\" | grep -q 'rc=3'"
  # restore the original gate (npm test body) for the next shell's pass
  cat > "$TMP22/espalier/hooks/pre-push-gate.sh" << 'G22'
#!/bin/bash
run_build() {
  echo building
  { echo inner-group; true; }
}
gate_build_section() { :; }
run_lint() {
  true  # no lint command discovered at init
}
run_tests() {
  cd backend && npm test
}
G22
done

# 22m stats spawn shape + RESUMED booked as human wait + workspace docs
rm -rf "$CH22/coding-log"; mkdir -p "$CH22/coding-log"; touch "$CH22/coding-log/01-stage3-part1.md" "$CH22/coding-log/02-handoff-1.md"
cat > "$CH22/pipeline-state.md" << 'S22'
## Status
- Status: COMPLETE
- Total Rollbacks: 0
- Review Rounds: req=1/3, code=1/3, test=0/3

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 2 | PASSED | 2026-09-09T10:00:00Z | Requirements approved by user |
| 3 | RESUMED | 2026-09-09T11:00:00Z | fresh session |
| 3 | HANDOFF 1 | 2026-09-09T11:30:00Z | 2 remaining; next: b.ts |
| 4 | PASSED | 2026-09-09T12:00:00Z | reviewer: PASS p0=0 p1=0; security: PASS p0=0 p1=0 |

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
| 7 | 0123abc | src/a.ts,src/a.test.ts |
| 7 | 4567def | src/b.ts |
S22
mkdir -p "$TMP22/espalier/changes/fix/2026-09-09-b"
printf -- '- Status: COMPLETE\n\n## Stage History\n| Stage | Status | Timestamp | Notes |\n|---|---|---|---|\n| 3 | IN_PROGRESS | 2026-09-09T10:00:00Z | |\n' > "$TMP22/espalier/changes/fix/2026-09-09-b/pipeline-state.md"
touch "$TMP22/espalier/changes/fix/2026-09-09-b/coding-report.md"
( cd "$TMP22" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm rows >/dev/null )
OUT=$( cd "$TMP22" && bash espalier/hooks/espalier-stats.sh )
assert "22m stats spawn shape: spawns 3/1, handoffs 1/0, parts 1, resumes 1/0, commits 2/0; the RESUMED gap is human wait; workspace docs listed" \
  "echo \"\$OUT\" | grep -q '^coder spawns per change: n=2 min=1 median=2 mean=2.00 max=3$' \
   && echo \"\$OUT\" | grep -q '^handoffs per change: n=2 min=0 median=0.5 mean=0.50 max=1$' \
   && echo \"\$OUT\" | grep -q '^parallel parts per change: n=1 min=1 median=1 mean=1.00 max=1$' \
   && echo \"\$OUT\" | grep -q '^fresh-session resumes per change: n=2 min=0 median=0.5 mean=0.50 max=1$' \
   && echo \"\$OUT\" | grep -q '^commits per change (Stage 7 rows): n=2 min=0 median=1 mean=1.00 max=2$' \
   && echo \"\$OUT\" | grep -q 'feat\*\* totals: human-wait=3600s agent-work=3600s' \
   && echo \"\$OUT\" | grep -q '^- backend/src/orders/CLAUDE.md — 1 KB — last change 20' \
   && echo \"\$OUT\" | grep -q '^- CLAUDE.md — 1 KB'"
rm -rf "$TMP22/espalier/changes"; mkdir -p "$TMP22/espalier/changes/feat/2026-09-09-c"
printf -- '- Status: IN_PROGRESS\n' > "$TMP22/espalier/changes/feat/2026-09-09-c/pipeline-state.md"
OUT=$( cd "$TMP22" && bash espalier/hooks/espalier-stats.sh )
assert "22n stats spawn shape degrades to none without coding reports" "echo \"\$OUT\" | grep -q 'none — no coding reports yet'"

# 22o maprun _stage_names: literal `### N. ` (8.5 ignored, stage 8 = CI Verification); fallback labels when headings are missing
mkdir -p "$TMP22/espalier/maps/m"
cp "$TEMPLATES/pipeline.md" "$TMP22/espalier/pipeline.md"
OUT=$( cd "$TMP22" && python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('maprun', '$HOOKS_SRC/maprun.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.Run.__new__(m.Run); r.repo_root = lambda: '$TMP22'
n = r._stage_names(); print(len(n), n[8], n[10])
" 2>&1 )
grep -v '^### 8\. \|^### 9\. \|^### 10\. ' "$TEMPLATES/pipeline.md" > "$TMP22/espalier/pipeline.md"
OUT2=$( cd "$TMP22" && python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('maprun', '$HOOKS_SRC/maprun.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.Run.__new__(m.Run); r.repo_root = lambda: '$TMP22'
n = r._stage_names(); print(len(n), n[8], n[9], n[10])
" 2>&1 )
assert "22o maprun _stage_names: ten stages from the template, 8 = CI Verification (8.5 ignored); three deleted headings → fallback labels + one warning" \
  "echo \"\$OUT\" | grep -q '^10 CI Verification User Confirmation$' \
   && echo \"\$OUT2\" | grep -q 'missing stage heading(s) 8, 9, 10' && echo \"\$OUT2\" | grep -q '^10 CI Verification Deployment Verification User Confirmation$'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP22"

# ─── T23: v0.26 turn-economy helpers, gate scoping, hook overlap ──────────
echo "T23: v0.26 turn-economy helpers, gate scoping, hook overlap"
TMP23=$(mktemp -d -t hooks-t23.XXXX)
make_repo "$TMP23"
install_hooks "$TMP23"
cp "$HOOKS_SRC/parse-drift-blocks.py" "$TMP23/espalier/hooks/"
mkdir -p "$TMP23/espalier/rules" "$TMP23/backend/src" "$TMP23/frontend/src" "$TMP23/t" "$TMP23/src"
printf '# Coding Standards\n- rule\n' > "$TMP23/espalier/rules/coding-standards.md"
CH23="$TMP23/espalier/changes/feat/2026-09-14-a"; mkdir -p "$CH23"

# 23a contract_gaps: covered / none / missing / fallback to the record / no contract
printf '## Security-Sensitive Fields\n- field: cartId\n  axis: owner\n  covered_by: tests/cart.abuse.test.js:41-58\n- field: price\n  axis: money\n  covered_by: none\n- field: role\n  axis: permission\n\n## Other\n' > "$CH23/security-contract.md"
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && contract_gaps "$CH23"; echo "rc=$?" )
printf '## Security-Sensitive Fields\n- field: cartId\n  covered_by: tests/a.js:1\n\nVERDICT: PASS p0=0 p1=0 round=1\n' > "$CH23/security-record.md"
OUT2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && rm -f "$CH23/security-contract.md" && contract_gaps "$CH23"; echo "rc=$?" )
OUT3=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && rm -f "$CH23/security-record.md" && contract_gaps "$CH23"; echo "rc=$?" )
assert "23a contract_gaps: prints the none + missing entries (not the covered one); empty on a fully covered record fallback; exit 1 without a contract" \
  "[ \"\$(echo \"\$OUT\" | grep -v rc= | tr '\n' ' ')\" = 'price role ' ] && echo \"\$OUT\" | grep -q 'rc=0' \
   && [ \"\$(echo \"\$OUT2\" | grep -v rc=)\" = '' ] && echo \"\$OUT2\" | grep -q 'rc=0' && echo \"\$OUT3\" | grep -q 'rc=1'"

# 23b certificate_write: inserted after Base-Ref, then overwritten in place; prose untouched; the push gate accepts it
echo change > "$TMP23/src/a.txt"
( cd "$TMP23" && git add src/a.txt && git -c user.email=t@t -c user.name=t commit -qm change )
BASE23=$(cd "$TMP23" && git rev-parse HEAD~1)
printf '## Status\n- Current Stage: 4\n- Status: IN_PROGRESS\n\n## Stage History\n| Stage | Status | Timestamp | Notes |\n|---|---|---|---|\n| 4 | ROUND 1 FAIL | ts | note quoting Reviewed-Diff: deadbeef in prose |\nBase-Ref: %s\n' "$BASE23" > "$CH23/pipeline-state.md"
H1=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && certificate_write "$CH23" )
echo more >> "$TMP23/src/a.txt"
H2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && certificate_write "$CH23" )
EXP23=$( cd "$TMP23" && git diff "$BASE23" -- . ':(exclude)espalier/' | git hash-object --stdin )
assert "23b certificate_write: one anchored Reviewed-Diff line after Base-Ref, overwritten in place on the second call, equal to the live fingerprint; the prose mention untouched; no Base-Ref → exit 1" \
  "[ \"\$(grep -c '^Reviewed-Diff:' '$CH23/pipeline-state.md')\" -eq 1 ] && [ \"\$H2\" = \"\$EXP23\" ] && [ \"\$H1\" != \"\$H2\" ] \
   && grep -q '^Reviewed-Diff: '\"\$H2\"'$' '$CH23/pipeline-state.md' && grep -qF 'quoting Reviewed-Diff: deadbeef' '$CH23/pipeline-state.md' \
   && ! ( cd '$TMP23' && . espalier/hooks/drift-helpers.sh && mkdir -p espalier/changes/feat/nobase && printf -- '- Current Stage: 4\n' > espalier/changes/feat/nobase/pipeline-state.md && certificate_write espalier/changes/feat/nobase 2>/dev/null )"

# 23c record_commits: rows oldest first, idempotent, cache self-healed
( cd "$TMP23" && git add -A && git -c user.email=t@t -c user.name=t commit -qm second )
SHA_A=$(cd "$TMP23" && git rev-parse HEAD~1); SHA_B=$(cd "$TMP23" && git rev-parse HEAD)
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && record_commits feat 2026-09-14-a )
OUT2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && record_commits feat 2026-09-14-a )
assert "23c record_commits: two rows oldest first under ## Commits, printed once, no duplicate on re-run, commit-index rows written" \
  "[ \"\$(echo \"\$OUT\" | grep -c '^| 7 | ')\" -eq 2 ] && [ -z \"\$OUT2\" ] \
   && [ \"\$(grep -c '^| 7 | ' '$CH23/pipeline-state.md')\" -eq 2 ] \
   && [ \"\$(grep -n '^| 7 | $SHA_A ' '$CH23/pipeline-state.md' | cut -d: -f1)\" -lt \"\$(grep -n '^| 7 | $SHA_B ' '$CH23/pipeline-state.md' | cut -d: -f1)\" ] \
   && grep -q \"^$SHA_A	feat/2026-09-14-a	original	\" '$TMP23/espalier/.commit-index.tsv'"

# 23d drift_index: DRIFT → stale row + line; MALFORMED → line only
printf '## Review\n\n## Convention Drift\n- Rule file: espalier/rules/coding-standards.md\n- Old convention: "x"\n- New convention observed: "y"\n- Evidence files: a.ts, b.ts\n- Recommendation: update rule\n\n## Convention Drift\n- Rule file: espalier/rules/coding-standards.md\n- Rule file: espalier/rules/other.md\n- Old convention: "x"\n\nVERDICT: PASS p0=0 p1=0 round=1\n' > "$CH23/review-record.md"
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && drift_index feat 2026-09-14-a )
assert "23d drift_index: a DRIFT block marks the rule stale and appends convention_drift:, a bundled block appends convention_drift_malformed:, both printed" \
  "echo \"\$OUT\" | grep -q '^convention_drift: espalier/rules/coding-standards.md' && echo \"\$OUT\" | grep -q '^convention_drift_malformed: ' \
   && grep -q '^convention_drift: espalier/rules/coding-standards.md' '$CH23/pipeline-state.md' \
   && grep -q '^espalier/rules/coding-standards.md	' '$TMP23/espalier/.drift-state.tsv'"

# 23e stage85_drift: table appended + summary line; "no drift" when clean
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && stage85_drift feat 2026-09-14-a )
OUT2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && clear_stale espalier/rules/coding-standards.md && stage85_drift feat 2026-09-14-a )
assert "23e stage85_drift: one stale doc → notify table in doc-patches.md + the summary line; cleared → 'no drift'" \
  "echo \"\$OUT\" | grep -q '^Stage 8.5: 1 stale doc(s)' && grep -q '^| espalier/rules/coding-standards.md | fresh | convention drift' '$CH23/doc-patches.md' \
   && [ \"\$OUT2\" = 'Stage 8.5: no drift.' ]"

# 23f backlink_all: real slug linked once (idempotent), unknown_squash + note rows skipped
mkdir -p "$TMP23/espalier/changes/fix/2026-09-14-b"
printf -- '---\ntype: fix\ncaused_by:\n  - slug: feat/2026-09-14-a\n    sha: abc\n    role: primary\n    lookup: exact\n  - slug: unknown_squash\n    sha: def\n    role: call_path\n    lookup: skipped\n  - note: overflow, 3 more frames\n---\n\n# Bug: widget explodes\n' > "$TMP23/espalier/changes/fix/2026-09-14-b/requirements.md"
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && backlink_all 2026-09-14-b )
OUT2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && backlink_all 2026-09-14-b )
assert "23f backlink_all: one Follow-up Fixes row with the bug title, unknown_squash and note rows skipped, second run writes nothing" \
  "[ \"\$OUT\" = 'fix/2026-09-14-b -> feat/2026-09-14-a (primary)' ] && [ -z \"\$OUT2\" ] \
   && [ \"\$(grep -c '^| fix/2026-09-14-b | primary | exact | widget explodes | ' '$CH23/pipeline-state.md')\" -eq 1 ]"

# 23g regression_verify: true / cached / false-on-fixed / harness-error skipped / handoff guard
FIX23="$TMP23/espalier/changes/fix/2026-09-14-b"
printf 'grep -q FIXED src/b.txt\n' > "$TMP23/t/reg.sh"
echo broken > "$TMP23/src/b.txt"
( cd "$TMP23" && git add -A && git -c user.email=t@t -c user.name=t commit -qm prefix )
BASEFIX=$(cd "$TMP23" && git rev-parse HEAD)
echo FIXED > "$TMP23/src/b.txt"
printf -- '- Current Stage: 3\nBase-Ref: %s\n' "$BASEFIX" > "$FIX23/pipeline-state.md"
printf '## Coding Report\n- Test files: t/reg.sh\n' > "$FIX23/coding-report.md"
R1=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && regression_verify "$FIX23" "bash t/reg.sh" t/reg.sh )
R2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && regression_verify "$FIX23" "bash t/reg.sh" t/reg.sh )
printf '## Coding Report\n- Test files: t/reg.sh\n' > "$FIX23/coding-report.md"
R3=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && regression_verify "$FIX23" "false" t/reg.sh )
printf '## Coding Report\n' > "$FIX23/coding-report.md"
R4=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && regression_verify "$FIX23" "bash t/missing.sh" t/reg.sh )
printf '## Coding Report\n- HANDOFF: true\n' > "$FIX23/coding-report.md"
R5=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && regression_verify "$FIX23" "bash t/reg.sh" t/reg.sh )
assert "23g regression_verify: true (fails at Base-Ref, passes on fix) then (cached); false on a fixed-tree failure; skipped on a harness error; a handoff report left untouched; worktree removed" \
  "echo \"\$R1\" | grep -q '^- REGRESSION_VERIFIED: true (test fails on pre-fix $BASEFIX, passes on fix)$' \
   && echo \"\$R2\" | grep -q '^- REGRESSION_VERIFIED: true .* (cached)$' \
   && echo \"\$R3\" | grep -q '^- REGRESSION_VERIFIED: false — regression test FAILS on the FIXED code' \
   && echo \"\$R4\" | grep -q '^- REGRESSION_VERIFIED: skipped — scoped invocation could not run on the fixed tree' \
   && echo \"\$R5\" | grep -q 'is a handoff' && [ \"\$(grep -c REGRESSION '$FIX23/coding-report.md')\" -eq 0 ] \
   && [ \"\$(cd '$TMP23' && git worktree list | grep -c reg-base)\" -eq 0 ]"

# 23h _gate_scoped_cmd: multi-workspace body scoped per workspace; a file under no workspace → full suite; uv run pytest scoped
MW=$(printf 'run_tests() {\n  (cd backend && npm test) || return 1\n  (cd frontend && npm test) || return 1\n}')
SC1=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && _gate_scoped_cmd "$MW" backend/src/a.test.ts frontend/src/b.test.ts )
SC2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && _gate_scoped_cmd "$MW" backend/src/a.test.ts )
SC3=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && _gate_scoped_cmd "$MW" backend/src/a.test.ts tools/x.test.ts )
SC4=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && _gate_scoped_cmd "$(printf 'run_tests() {\n  uv run pytest -q\n}')" tests/test_a.py )
assert "23h _gate_scoped_cmd: two-workspace body → per-workspace scoped commands joined with &&; a workspace with no file dropped; a file under no workspace → full suite; uv run pytest scoped" \
  "[ \"\$SC1\" = '(cd backend && npm test -- src/a.test.ts) && (cd frontend && npm test -- src/b.test.ts)' ] \
   && [ \"\$SC2\" = '(cd backend && npm test -- src/a.test.ts)' ] && [ -z \"\$SC3\" ] \
   && [ \"\$SC4\" = 'uv run pytest -q tests/test_a.py' ]"

# 23i exit_gate ordering: tests start after the build while a slow lint finishes; a red build still prints the lint line
cat > "$TMP23/espalier/hooks/pre-push-gate.sh" << 'G23'
#!/bin/bash
run_build() {
  true
}
run_lint() {
  sleep 1; echo lint-done
}
run_tests() {
  echo tests-ran > /tmp/.t23-tests-ran
}
G23
printf '## Coding Report\n' > "$CH23/coding-report.md"
rm -f /tmp/.t23-tests-ran
T0=$(date +%s)
OUT=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && exit_gate "$CH23"; echo "rc=$?" )
sed 's/^  true$/  echo build-broken; false/' "$TMP23/espalier/hooks/pre-push-gate.sh" > "$TMP23/g.tmp" && mv "$TMP23/g.tmp" "$TMP23/espalier/hooks/pre-push-gate.sh"
rm -f /tmp/.t23-tests-ran
OUT2=$( cd "$TMP23" && . espalier/hooks/drift-helpers.sh && exit_gate "$CH23"; echo "rc=$?" )
assert "23i exit_gate: green run prints build, lint, tests in order (rc 0); a red build prints the lint line and 'tests: skipped — build red' (rc 1) without running the tests" \
  "[ \"\$(echo \"\$OUT\" | tr '\n' ' ')\" = 'build: exit 0 lint: exit 0 tests: exit 0 (full suite) rc=0 ' ] \
   && echo \"\$OUT2\" | grep -q '^build: exit 1 — log: ' && echo \"\$OUT2\" | grep -q '^lint: exit 0$' && echo \"\$OUT2\" | grep -q '^tests: skipped — build red$' && echo \"\$OUT2\" | grep -q 'rc=1' \
   && [ ! -f /tmp/.t23-tests-ran ]"
rm -f /tmp/.t23-tests-ran

# 23j pre-push hook: build ∥ lint by default (key absent) — both run, a lint failure blocks with its message, the serial functions are gone
TMPH=$(mktemp -d -t hooks-t23h.XXXX)
make_repo "$TMPH"
mkdir -p "$TMPH/espalier/hooks"
sed -e "s|{build_command}|touch $TMPH/.built; sleep 1|g" -e "s|{lint_command}|touch $TMPH/.linted|g" -e "s|{test_command}|echo '3 passed'|g" \
    "$HOOKS_SRC/pre-push-gate.sh" > "$TMPH/espalier/hooks/pre-push-gate.sh"
state_file "$TMPH" feat 2026-09-14-h 7 IN_PROGRESS
( cd "$TMPH" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>&1 ); RCH=$?
sed -e "s|{build_command}|true|g" -e "s|{lint_command}|echo lint-broken; false|g" -e "s|{test_command}|echo '3 passed'|g" \
    "$HOOKS_SRC/pre-push-gate.sh" > "$TMPH/espalier/hooks/pre-push-gate.sh"
( cd "$TMPH" && bash espalier/hooks/pre-push-gate.sh >/dev/null 2>"$TMPH/err.txt" ); RCH2=$?
assert "23j pre-push hook default: build and lint both ran (exit 0); a lint failure blocks with 'BLOCKED: Lint fails' + its output (exit 2); no gate_build_section / gate_lint_section left" \
  "[ $RCH -eq 0 ] && [ -f '$TMPH/.built' ] && [ -f '$TMPH/.linted' ] \
   && [ $RCH2 -eq 2 ] && grep -q 'BLOCKED: Lint fails' '$TMPH/err.txt' && grep -q 'lint-broken' '$TMPH/err.txt' \
   && ! grep -q 'gate_build_section\|gate_lint_section' '$HOOKS_SRC/pre-push-gate.sh'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP23" "$TMPH"

# ─── T24: v0.27 unknowns helpers (drift-helpers.sh) + stats deviations row ──
echo "T24: v0.27 unknowns helpers, stats deviations row"
TMP24=$(mktemp -d -t hooks-t24.XXXX)
make_repo "$TMP24"
install_hooks "$TMP24"
cp "$HOOKS_SRC/espalier-stats.sh" "$TMP24/espalier/hooks/" 2>/dev/null || true
CH24="$TMP24/espalier/changes/feat/2026-09-14-u"; mkdir -p "$CH24"

# 24a _md_section: the section body to the next same-or-higher heading, fences kept, sentinel stops it
printf '# T\n\n## A\nline a\n```\n## not a heading\n```\n### A1\nsub\n## B\nline b\n- HANDOFF: true\ntrailing\n' > "$TMP24/md.md"
OUT=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && _md_section md.md "## A" | tr '\n' '|' )
OUT2=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && _md_section md.md "## B" | tr '\n' '|' )
OUT3=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && _md_section md.md "## Z"; echo "rc=$?" )
assert "24a _md_section: '## A' runs through its fenced block and '### A1' and stops at '## B'; '## B' stops at the HANDOFF sentinel; a missing heading prints nothing, exit 0" \
  "[ \"\$OUT\" = 'line a|\`\`\`|## not a heading|\`\`\`|### A1|sub|' ] && [ \"\$OUT2\" = 'line b|' ] && [ \"\$OUT3\" = 'rc=0' ]"

# 24b deviations_list: entries only, blanks dropped; nothing without the block or the report
printf '## Coding Report\n- Files created: a.js\n- Notes: skipped X\n\n### Deviations\n- "AC1" → built: narrow; because: `a.js:3`; left undone: wide\n\n- "AC2" → built: strict; because: `b.js:9`; left undone: lax\n\n### Class Sweep\n- none\n' > "$CH24/coding-report.md"
OUT=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && deviations_list "$CH24" )
mkdir -p "$CH24-none"; printf '## Coding Report\n- Notes: none\n' > "$CH24-none/coding-report.md"
OUT2=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && deviations_list "$CH24-none"; echo "rc=$?" )
OUT3=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && deviations_list "$CH24-missing"; echo "rc=$?" )
assert "24b deviations_list: two entries, no blank lines, the Class Sweep block excluded; no block → empty exit 0; no report → empty exit 0" \
  "[ \"\$(echo \"\$OUT\" | grep -c .)\" -eq 2 ] && echo \"\$OUT\" | grep -qF 'AC1' && echo \"\$OUT\" | grep -qF 'AC2' && ! echo \"\$OUT\" | grep -qF 'none' \
   && [ \"\$OUT2\" = 'rc=0' ] && [ \"\$OUT3\" = 'rc=0' ]"

# 24c open_question_append: creates the heading at EOF, then appends inside the section (before the next heading), idempotent per call, exit 1 without requirements.md
printf '### 1. Requirement Summary\n- What: x\n### 2. Acceptance Criteria\n- [ ] AC1\n' > "$CH24/requirements.md"
OUT=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && open_question_append "$CH24" 'AC1 → narrow (ratified at Stage 3 BLOCKED 1)' )
( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && printf '\n## Convention Notes\n- rules/x cleared\n' >> "$CH24/requirements.md" && open_question_append "$CH24" 'second (default — revisit)' >/dev/null )
OUT2=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && open_question_append "$CH24-missing" 'x' 2>/dev/null; echo "rc=$?" )
assert "24c open_question_append: '## Open Questions' created once at EOF with the line; a second line lands inside the section above the following heading; printed; exit 1 without requirements.md" \
  "[ \"\$OUT\" = '- AC1 → narrow (ratified at Stage 3 BLOCKED 1)' ] \
   && [ \"\$(grep -c '^## Open Questions' '$CH24/requirements.md')\" -eq 1 ] \
   && [ \"\$(grep -n '^- second' '$CH24/requirements.md' | cut -d: -f1)\" -lt \"\$(grep -n '^## Convention Notes' '$CH24/requirements.md' | cut -d: -f1)\" ] \
   && [ \"\$(grep -n '^- AC1' '$CH24/requirements.md' | cut -d: -f1)\" -lt \"\$(grep -n '^- second' '$CH24/requirements.md' | cut -d: -f1)\" ] \
   && [ \"\$OUT2\" = 'rc=1' ]"

# 24d req_shape_check: References is contract; a stray heading still reported
printf '\n## References\n- vendor/x: backoff semantics\n## Design rationale\n- why\n' >> "$CH24/requirements.md"
OUT=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && req_shape_check "$CH24" )
assert "24d req_shape_check: '## References' and '## Open Questions' are contract headings; 'Design rationale' is reported" \
  "[ \"\$OUT\" = 'Design rationale → requirements-notes.md' ]"

# 24e delivery_brief: assembled from the records, count line, none-lines, exit 1 without requirements
printf '## Status\n- Current Stage: 10\n\n## Stage History\n| Stage | Status | Timestamp | Notes |\n|---|---|---|---|\n| 3 | BLOCKED 1 | ts | AC1 |\n| 4 | ROUND 1 FAIL | ts | reviewer: FAIL |\n| 4 | PASSED | ts | deviations: 2 |\n\n## Commits\n| Stage | SHA | Files |\n|---|---|---|\n| 7 | abc1234 | a.js |\n| 7 | def5678 | b.js |\n' > "$CH24/pipeline-state.md"
printf '## Review\n\nVERDICT: PASS p0=0 p1=0 round=2\n' > "$CH24/review-record.md"
printf '## Audit\n\nVERDICT: PASS_WITH_FIXES p0=0 p1=0 round=2\n' > "$CH24/security-record.md"
OUT=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && delivery_brief feat 2026-09-14-u )
BRIEF="$CH24/delivery-brief.md"
OUT2=$( cd "$TMP24" && . espalier/hooks/drift-helpers.sh && delivery_brief feat nope 2>/dev/null; echo "rc=$?" )
assert "24e delivery_brief: path + count line; requirement / criteria / Open Questions / References / Deviations / Notes / verdicts / rows / commits copied; empty sources are 'none'; exit 1 without requirements.md" \
  "echo \"\$OUT\" | grep -qF 'delivery brief: 2 deviations, 1 rounds, 2 commits' && echo \"\$OUT\" | grep -qF '$BRIEF' \
   && grep -qF '# Delivery Brief: feat/2026-09-14-u' '$BRIEF' && grep -qF -- '- What: x' '$BRIEF' && grep -qF -- '- [ ] AC1' '$BRIEF' \
   && grep -qF -- '- AC1 → narrow (ratified at Stage 3 BLOCKED 1)' '$BRIEF' && grep -qF -- '- vendor/x: backoff semantics' '$BRIEF' \
   && grep -qF -- '\"AC2\" → built: strict' '$BRIEF' && grep -qF 'skipped X' '$BRIEF' \
   && grep -qF -- '- review: VERDICT: PASS p0=0' '$BRIEF' && grep -qF -- '- security: VERDICT: PASS_WITH_FIXES' '$BRIEF' \
   && grep -qF '| 3 | BLOCKED 1 |' '$BRIEF' && grep -qF '| 4 | ROUND 1 FAIL |' '$BRIEF' && ! grep -qF '| 4 | PASSED |' '$BRIEF' \
   && [ \"\$(grep -c '^| 7 | ' '$BRIEF')\" -eq 2 ] \
   && awk '/^## Decisions the code froze/{f=1; next} f && /^## /{exit} f && /none/{ok=1} END{exit !ok}' '$BRIEF' \
   && grep -qF -- '- ci-result.md: none' '$BRIEF' \
   && [ \"\$OUT2\" = 'rc=1' ]"

# 24f stats: the deviations row counts changes with a logged block (report or archive) and BLOCKED rows
mkdir -p "$TMP24/espalier/changes/feat/2026-09-14-v/coding-log"
printf '## Status\n- Current Stage: 10\n- Status: COMPLETE\n\n## Stage History\n| 3 | BLOCKED 1 | ts | x |\n| 3 | BLOCKED 2 | ts | y |\n' > "$TMP24/espalier/changes/feat/2026-09-14-v/pipeline-state.md"
printf '## Coding Report\n- Notes: none\n' > "$TMP24/espalier/changes/feat/2026-09-14-v/coding-report.md"
printf '## Coding Report\n### Deviations\n- old one\n' > "$TMP24/espalier/changes/feat/2026-09-14-v/coding-log/01-stage3.md"
OUT=$( cd "$TMP24" && bash espalier/hooks/espalier-stats.sh 2>/dev/null )
assert "24f espalier-stats: 'deviations: changes-with-logged-deviations=2 stage3-blocked-rows=3' (one live block, one archived block; 1 + 2 BLOCKED rows)" \
  "echo \"\$OUT\" | grep -qF 'deviations: changes-with-logged-deviations=2 stage3-blocked-rows=3'"
[ "$KEEP" != "yes" ] && rm -rf "$TMP24"

# ─── T25: v0.28 stats ceiling-marker ledger ─────────────────────────────────
echo "T25: v0.28 stats ceiling-marker ledger"
TMP25=$(mktemp -d -t hooks-t25.XXXX)
make_repo "$TMP25"
install_hooks "$TMP25"
cp "$HOOKS_SRC/espalier-stats.sh" "$TMP25/espalier/hooks/" 2>/dev/null || true
mkdir -p "$TMP25/src/lib" "$TMP25/src/__generated__" "$TMP25/espalier/agents"
printf 'grep-only-paths: __generated__/ schema.graphql\n' > "$TMP25/espalier/.espalier-config"
# one marker with a trigger, one without, one in a block comment; espalier/ and
# a grep-only path carry markers that must NOT count; prose "ceiling:" with no
# comment leader must not count either.
printf 'const seen = new Map();\n// ceiling: single-process map, no eviction; a shared store when a second instance ships\nfunction f() {}\n' > "$TMP25/src/lib/a.js"
printf 'lock = threading.Lock()\n# ceiling: global lock\ndef g(): pass\n' > "$TMP25/src/lib/b.py"
printf '/* ceiling: O(n^2) scan; index the list past 10k rows */\nSELECT 1;\n' > "$TMP25/src/lib/c.sql"
printf 'const s = "the ceiling: is prose";\n' > "$TMP25/src/lib/d.js"
printf '// ceiling: generated; never\n' > "$TMP25/src/__generated__/x.js"
printf '# ceiling: in espalier; never\n' > "$TMP25/espalier/agents/note.md"
( cd "$TMP25" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm markers >/dev/null )
OUT=$( cd "$TMP25" && bash espalier/hooks/espalier-stats.sh 2>/dev/null )
assert "25a espalier-stats: 'ceilings: markers=3 no-trigger=1' — tracked source only (espalier/ and grep-only paths excluded, prose excluded); rows carry path:line, a blame date, the limit; trigger, and [no-trigger] where the ; is missing" \
  "echo \"\$OUT\" | grep -qF 'ceilings: markers=3 no-trigger=1' \
   && echo \"\$OUT\" | grep -qE '^- src/lib/a.js:2 \\(since [0-9]{4}-[0-9]{2}-[0-9]{2}\\) — single-process map, no eviction; a shared store when a second instance ships$' \
   && echo \"\$OUT\" | grep -qE '^- src/lib/b.py:2 \\(since [0-9-]+\\) — global lock \\[no-trigger\\]$' \
   && echo \"\$OUT\" | grep -qE '^- src/lib/c.sql:1 \\(since [0-9-]+\\) — O\\(n\\^2\\) scan; index the list past 10k rows$' \
   && ! echo \"\$OUT\" | grep -qF '__generated__' && ! echo \"\$OUT\" | grep -qF 'espalier/agents/note.md' && ! echo \"\$OUT\" | grep -qF 'd.js'"
( cd "$TMP25" && git rm -q src/lib/a.js src/lib/b.py src/lib/c.sql && git -c user.email=t@t -c user.name=t commit -qm rm >/dev/null )
OUT=$( cd "$TMP25" && bash espalier/hooks/espalier-stats.sh 2>/dev/null )
assert "25b espalier-stats: no markers → 'none — no ceiling: markers in tracked source'; read-only" \
  "echo \"\$OUT\" | grep -qF 'none — no ceiling: markers in tracked source' \
   && [ -z \"\$(cd \"$TMP25\" && git status --porcelain 2>/dev/null | grep -v '^??')\" ]"
[ "$KEEP" != "yes" ] && rm -rf "$TMP25"

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
