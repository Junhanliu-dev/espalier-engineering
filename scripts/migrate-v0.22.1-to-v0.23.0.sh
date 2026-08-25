#!/bin/bash
# Migrate a v0.22.1 Espalier install to v0.23.0.
#
# v0.23.0 is the round-economy release (the Stage 3/5 fold). Same gates,
# sentinels, round caps, certificates, and both human checkpoints; the
# dispatch is restructured so tests ride the coder and the panel reviews
# code+tests together:
#
#   - Stage 3/5 fold (`test-mode: folded`, the default): the coder writes the
#     interface/failure-mode tests WITH the code; the Stage 3 exit gate runs
#     build+lint+scoped tests on every coder return; the 2-agent Stage 4
#     panel reviews code AND tests in one verdict. Stages 5/6 become the
#     security-contract phase (contract spawn → delta review) or SKIPPED
#     rows; stage numbers stay 3→4→5→6→7 for every integer consumer.
#     `test-mode: serial` keeps the pre-v0.22 flow; the legacy
#     `speculative-tests` key maps through (off → serial, else folded).
#     The speculative dispatch (part files, quarantine, restore/reconcile)
#     is retired.
#   - Contract-FAIL routing: a contract fix touching any non-test file goes
#     back to a FULL Stage 4 panel round (security eyes on the code again).
#   - Fix lane: regression verification moves into the Stage 3 exit gate
#     (re-runs per coder return, last-line-wins, REGRESSION_VERIFIED_SCOPE
#     skip hash); scope detectors count non-test files only.
#   - Findings digest (map feedback): FAIL-round snapshots carry bracketed
#     finding lines; charted changes write per-change digest files under
#     espalier/maps/{slug}/findings/; adoption folds the newest 12 P0/P1
#     lines into the slice's requirements.
#   - Crispness gate: the map handoff scores each drafted slice (grill
#     mode=score) and refuses would-be-full slices; CLEARED flips LAST.
#   - Readable by default: the coder gains a "Write It Readable" section
#     (named constants over magic values, intent names, guard clauses,
#     small functions, comments last); coding-standards gains the matching
#     "Readable by Default" defaults; the espalier-coding SKILL points at both;
#     the reviewer's Readability Review gains the `structure:` tag and the
#     magic-constant declaration-comment check.
#   - Grill verdicts carry their tier: GRILLED (light) / GRILLED (full).
#   - espalier-stats: tier split + adoption nudge; espalier-doctor: config
#     advisory; pre-push-gate: anchored Current Stage read + last-match
#     test-count parse.
#
# Mechanics:
#   - Refresh 11 pure-copy files from templates (backup-on-diff →
#     <file>.pre-v0.23.bak): pipeline.md; the espalier, espalier-fix,
#     espalier-map, espalier-maprun, espalier-grill, espalier-requirements,
#     espalier-doctor SKILLs; espalier/hooks/espalier-stats.sh,
#     espalier/hooks/rebuild-commit-index.sh (mawk squash-SHA truncation
#     fix), and espalier/hooks/maprun-dispatch.sh (skipped silently when a
#     pre-maprun install has no such hook).
#   - Anchored edits into the SUBSTITUTED per-project files (never
#     wholesale-copied): harness-coder / harness-reviewer / harness-security,
#     production-standards / security-standards / coding-standards, the
#     espalier-coding and espalier-testing SKILLs, and pre-push-gate.sh. A customised file
#     missing its anchor is skipped with a record in
#     espalier/.migrations-skipped, never mangled.
#   - Writes NO config keys: test-mode absent = folded (legacy
#     speculative-tests honored at read time).
#
# Usage:
#   bash migrate-v0.22.1-to-v0.23.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,55p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.22.1→v0.23.0] $*"; }
die() { echo "[migrate v0.22.1→v0.23.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
grep -q 'test-mode' "$TPL/skills/espalier.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.23.0 (espalier template lacks the test-mode read). Update the plugin first."

# --- v0.23 markers (also the idempotency check) ------------------------------
PIPE_MARK='Contract Phase (folded)'
ESP_MARK='Stage 5/6 (folded)'
FIX_MARK='REGRESSION_VERIFIED_SCOPE'
MAP_MARK='crispness gate'
RUN_MARK='findings/'
GRILL_MARK='mode=score'
REQ_MARK='GRILLED (light)'
DOC_MARK='Config Advisories'
STATS_MARK='untiered'
RIDX_MARK='split($0, cols, /[^a-f0-9]+/)'
CODER_MARK='Contract entry point (post-panel dispatch mode)'
READ_MARK='Write It Readable'
CSTD_MARK='Readable by Default'
CSKL2_MARK='Write it readable as you go'
REV2_MARK='`structure:`'
REV_MARK='## Test Review (folded Stage 4 / serial Stage 6)'
SEC_MARK='fixture-data leakage'
PROD_MARK='a coding-stage duty'
SSTD_MARK='contract delta'
CSKL_MARK='folded test-writing duty'
TSKL_MARK='contract delta review'
GATE_MARK='(- )?Current Stage:'
SKIPFILE="espalier/.migrations-skipped"

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.23.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$PIPE_MARK"  espalier/pipeline.md                        2>/dev/null || mark "pipeline.md folded stage contract"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md           2>/dev/null || mark "espalier SKILL fold"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md       2>/dev/null || mark "espalier-fix SKILL fold"
grep -qF "$MAP_MARK"   espalier/skills/espalier-map/SKILL.md       2>/dev/null || mark "espalier-map crispness gate"
[ -f espalier/skills/espalier-maprun/SKILL.md ] && { grep -qF "$RUN_MARK" espalier/skills/espalier-maprun/SKILL.md 2>/dev/null || mark "espalier-maprun findings duty"; }
grep -qF "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md     2>/dev/null || mark "espalier-grill score mode + tiers"
grep -qF "$REQ_MARK"   espalier/skills/espalier-requirements/SKILL.md 2>/dev/null || mark "espalier-requirements tier verdict"
[ -f espalier/skills/espalier-doctor/SKILL.md ] && { grep -qF "$DOC_MARK" espalier/skills/espalier-doctor/SKILL.md 2>/dev/null || mark "espalier-doctor config advisory"; }
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh            2>/dev/null || mark "espalier-stats tier split + nudge"
grep -qF "$RIDX_MARK"  espalier/hooks/rebuild-commit-index.sh      2>/dev/null || mark "rebuild-commit-index mawk-safe squash extraction"
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-fold      || mark "coder fold (contract-only entry point)"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-fold   || mark "reviewer fold (test review at Stage 4)"
handled "$SEC_MARK"   espalier/agents/harness-security.md security-fold   || mark "security test-file scope stance"
handled "$PROD_MARK"  espalier/rules/production-standards.md prod-fold    || mark "production-standards re-point"
handled "$SSTD_MARK"  espalier/rules/security-standards.md   sstd-fold    || mark "security-standards re-point"
handled "$CSKL_MARK"  espalier/skills/espalier-coding/SKILL.md  coding-fold  || mark "espalier-coding stage re-point"
handled "$TSKL_MARK"  espalier/skills/espalier-testing/SKILL.md testing-fold || mark "espalier-testing re-point"
handled "$GATE_MARK"  espalier/hooks/pre-push-gate.sh gate-fold            || mark "pre-push anchored stage read + last-match count"
handled "$READ_MARK"  espalier/agents/harness-coder.md coder-readable      || mark "coder readable-by-default section"
handled "$CSTD_MARK"  espalier/rules/coding-standards.md cstd-readable     || mark "coding-standards Readable by Default"
handled "$CSKL2_MARK" espalier/skills/espalier-coding/SKILL.md coding-readable || mark "espalier-coding readable pointer"
handled "$REV2_MARK"  espalier/agents/harness-reviewer.md rev-readable        || mark "reviewer structure: tag + magic-constant comment check"

if [ -z "$missing" ]; then
  log "already at v0.23.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh 11 pure-copy files (backup-on-diff → .pre-v0.23.bak)"
  log "DRY RUN — would anchored-edit agents/rules/coding/testing + pre-push-gate.sh (skip-with-record if customised)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh pipeline.md, 7 SKILL files, espalier-stats.sh, rebuild-commit-index.sh, and maprun-dispatch.sh from templates (backups: <file>.pre-v0.23.bak)"
  echo "  - anchored-edit the 3 agent files, 3 rules files, 2 substituted SKILLs, and pre-push-gate.sh (customised files skipped, never mangled)"
  echo "  - write NO config keys (test-mode absent = folded; legacy speculative-tests honored)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.23.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
refresh "$TPL/pipeline.md"                     espalier/pipeline.md
refresh "$TPL/skills/espalier.md"              espalier/skills/espalier/SKILL.md
refresh "$TPL/skills/espalier-fix.md"          espalier/skills/espalier-fix/SKILL.md
refresh "$TPL/skills/espalier-map.md"          espalier/skills/espalier-map/SKILL.md
[ -f espalier/skills/espalier-maprun/SKILL.md ] \
  && refresh "$TPL/skills/espalier-maprun.md"  espalier/skills/espalier-maprun/SKILL.md
refresh "$TPL/skills/espalier-grill.md"        espalier/skills/espalier-grill/SKILL.md
refresh "$TPL/skills/espalier-requirements.md" espalier/skills/espalier-requirements/SKILL.md
[ -f espalier/skills/espalier-doctor/SKILL.md ] \
  && refresh "$TPL/skills/espalier-doctor.md"  espalier/skills/espalier-doctor/SKILL.md
refresh "$HTPL/espalier-stats.sh"              espalier/hooks/espalier-stats.sh
chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
refresh "$HTPL/rebuild-commit-index.sh"        espalier/hooks/rebuild-commit-index.sh
chmod +x espalier/hooks/rebuild-commit-index.sh 2>/dev/null || true
if [ -f espalier/hooks/maprun-dispatch.sh ]; then
  refresh "$HTPL/maprun-dispatch.sh"           espalier/hooks/maprun-dispatch.sh
  chmod +x espalier/hooks/maprun-dispatch.sh 2>/dev/null || true
fi

# --- 2. Anchored edits -------------------------------------------------------
BLK=$(mktemp -t v023blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.23 '$1' change from the template yourself."
  grep -qF "v0.23.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.23.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

backup_once() { [ -f "$1.pre-v0.23.bak" ] || cp "$1" "$1.pre-v0.23.bak"; }

# span_replace FILE START END — replace [first line containing START .. first
# later line containing END] inclusive with $BLK.
span_replace() {
  local f="$1" start="$2" end="$3" tmp="$1.v023tmp"
  backup_once "$f"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v start="$start" -v end="$end" '
    !insp && index($0, start) {
      while ((getline line < blk) > 0) print line
      close(blk); insp=1; skipping=1; next
    }
    skipping && index($0, end) { skipping=0; next }
    skipping { next }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# 2a. coder — abuse-test + speculative sections become the contract-only shape.
CODER=espalier/agents/harness-coder.md
if ! handled "$CODER_MARK" "$CODER" coder-fold; then
  A_START='### Writing Abuse Tests (Stage 5)'
  A_END='to coding-report.md normally.'
  B_HEAD='### Writing Failure-Mode Tests (Stage 5)'
  C_HEAD='### Test-mode self-report (fix lane Stage 5 only)'
  D_LINE='- Files modified: {list}'
  if grep -qF -- "$A_START" "$CODER" && grep -qF -- "$A_END" "$CODER" \
     && grep -qF -- "$B_HEAD" "$CODER" && grep -qF -- "$C_HEAD" "$CODER" \
     && grep -qF -- "$D_LINE" "$CODER"; then
    cat > "$BLK" << 'EOF'
### Writing Abuse Tests (contract phase)

When you run in CONTRACT PHASE mode, read the `## Security-Sensitive Fields`
contract in `espalier/changes/{type}/{slug}/security-record.md` (emitted by the
Stage 4 auditor). For EACH field listed, write the negative test named in its
`abuse_test`: tamper the value, assert the request is rejected, and assert the
persistent store is unchanged. A contracted field with no such test blocks
the contract delta review (serial mode: Stage 6) — do not skip one. See
`espalier/skills/espalier-security/SKILL.md` for the recipe.

### Contract entry point (post-panel dispatch mode)

- **`CONTRACT PHASE:`** — the panel has passed. Read security-record.md's
  `## Security-Sensitive Fields` and write the named abuse tests — nothing
  else. Append your test report to coding-report.md normally. (Under
  folded test-mode this is the ONLY post-panel test dispatch: the
  interface/failure-mode tests were your own Stage 3 duty, written with
  the code and reviewed with it.)
EOF
    span_replace "$CODER" "$A_START" "$A_END"
    tmp="$CODER.v023tmp"; cp "$CODER" "$tmp"
    awk '
      $0 == "### Writing Failure-Mode Tests (Stage 5)" { print "### Writing Failure-Mode Tests (testing duty)"; next }
      $0 == "In testing mode, for each NEW external-call path this change introduced, write" { print "When writing tests (a Stage 3 duty under folded test-mode; the serial test"; print "pass otherwise), for each NEW external-call path this change introduced, write"; next }
      $0 == "failure-mode coverage on a new external call is a P1 at Stage 6." { print "failure-mode coverage on a new external call is a P1 at review."; next }
      $0 == "### Test-mode self-report (fix lane Stage 5 only)" { print "### Test Scope Signal (fix lane)"; next }
      $0 == "When running in test-writing mode under `/espalier-fix` Stage 5 AND a meaningful" { print "When writing the fix'\''s tests (a Stage 3 duty under folded test-mode; the"; print "serial test pass otherwise) AND a meaningful"; next }
      { print }
      $0 == "- Files modified: {list}" {
        print "- Test files: {list — ALWAYS its own line: the exit gate'\''s scoped test"
        print "  run, the review panel, and the escalation detectors key off this split}"
      }
    ' "$tmp" > "$CODER"
    rm -f "$tmp"
    log "folded the coder testing sections (contract-only entry point)"
  else
    record_skip coder-fold "$CODER" "the v0.22 testing-section anchors"
  fi
fi

# 2a2. coder — the readable-by-default section + constraints pointer.
if ! handled "$READ_MARK" "$CODER" coder-readable; then
  OF_HEAD='## Output Format (when task complete)'
  if grep -qF -- "$OF_HEAD" "$CODER" 2>/dev/null; then
    backup_once "$CODER"
    cat > "$BLK" << 'EOF'
## Write It Readable (while writing, not at review)

Code is read far more often than written — produce the version a
maintainer new to the change parses without decoding. The reviewer flags
violations (`naming:` / `nesting:` / `magic:` tags); write it right the
first time. A documented project convention always outranks any default
here — match the project, don't fight it:

1. **No magic values.** A literal on a decision path — a threshold, limit,
   retry count, timeout, fee rate, status string — is NEVER inlined: it
   becomes a NAMED constant per the project's constants convention, named
   for what the value MEANS (`MAX_LOGIN_ATTEMPTS`,
   `FREE_SHIPPING_THRESHOLD_CENTS`), living where the project keeps such
   constants. If the name alone cannot carry what the value is or where
   it comes from, ONE short comment at the declaration explains it — that
   is exactly the comment budget's allowed case (a domain fact the code
   cannot show). Self-explaining literals stay literal: 0 as a start
   index, 1 as a step, `""` as empty.
2. **Names state intent.** A reader who has not opened the body can tell
   what an identifier holds or does. No `data2`, `tmp`, `proc` on
   anything that outlives a few lines; a function name says what it does,
   and a `getX` never mutates.
3. **Flat beats clever.** Guard clauses and early returns over nested
   conditionals; one step per line over a chained one-liner doing three
   things; the boring explicit form over the compressed construct that
   needs mental unpacking.
4. **Small, single-purpose functions.** A function does the one thing its
   name says. When a block inside needs its own explanation, extract it
   under an intent-stating name — the call site then reads as prose.
5. **Comments are the last resort, not the fix.** The comment budget in
   Your Constraints is unchanged: default NO comment, ONE plain line only
   for genuinely complex logic or a business rule the code cannot show (a
   why, an invariant, a domain fact). If a comment is forming, first try
   a better name or an extraction — most comments are a naming failure.

EOF
    tmp="$CODER.v023tmp"; cp "$CODER" "$tmp"
    awk -v blk="$BLK" '
      $0 == "## Output Format (when task complete)" && !done {
        while ((getline line < blk) > 0) print line
        close(blk); done=1
      }
      $0 == "- Report what you did in structured format when done" && !bul {
        print "- Readable by default: named constants over magic values, intent-stating"
        print "  names, guard clauses over nesting — see \"Write It Readable\" below. A"
        print "  documented project convention outranks these defaults."
        bul=1
      }
      { print }
    ' "$tmp" > "$CODER"
    rm -f "$tmp"
    log "inserted the readable-by-default coder section"
  else
    record_skip coder-readable "$CODER" "the Output Format heading"
  fi
fi

# 2b. reviewer — in-flight exclusion out; test checklist in; abuse check re-scoped.
REV=espalier/agents/harness-reviewer.md
if ! handled "$REV_MARK" "$REV" reviewer-fold; then
  R1_START='If your prompt carries a `SPECULATIVE TESTS IN FLIGHT:` line, a test-writing'
  R1_END='unchanged.'
  R2_START='7. Test-review rounds only (Stage 6): run the **Security Abuse-Test Coverage**'
  R2_END='8. Produce findings in the required format'
  R3_START='## Security Abuse-Test Coverage (Stage 6 — test review)'
  R3_END='coverage, not a suggestion.'
  if grep -qF -- "$R1_START" "$REV" && grep -qF -- "$R1_END" "$REV" \
     && grep -qF -- "$R2_START" "$REV" && grep -qF -- "$R2_END" "$REV" \
     && grep -qF -- "$R3_START" "$REV" && grep -qF -- "$R3_END" "$REV"; then
    printf '' > "$BLK"
    span_replace "$REV" "$R1_START" "$R1_END"
    cat > "$BLK" << 'EOF'
7. When the diff carries test files (folded mode Stage 4; serial Stage 6):
   run the **Test Review** checklist (see section below) — assertions
   meaningful and not tautological, changed-interface coverage,
   failure-mode coverage (missing = P1), and in the fix lane the
   `- REGRESSION_VERIFIED:` LAST line of coding-report.md (`false` = P0).
   Same verdict, same sentinel — tests are part of the diff you judge.
8. Contract delta-review rounds only (and serial Stage 6): run the
   **Security Abuse-Test Coverage**
   check (see section below) — every contracted security-sensitive field needs
   its passing negative test; a gap is a P0 back to the contract phase.
   Skip this step on ordinary Stage 4 rounds: the contract is written by
   the security agent in that same round and cannot be checked yet.
9. Produce findings in the required format
EOF
    span_replace "$REV" "$R2_START" "$R2_END"
    cat > "$BLK" << 'EOF'
## Test Review (folded Stage 4 / serial Stage 6)

When the diff you review carries test files, they are IN your verdict —
judge them with the code in view:
- **Meaningful assertions, never tautological** — a test asserting the
  code's masked/current behaviour instead of the intended one proves
  nothing; in the fix lane, a regression test must capture the BUG.
- **Changed-interface coverage** — every changed public interface has a
  test.
- **Failure-mode coverage** — every NEW external-call path has a
  dependency-failure test (per `espalier/rules/production-standards.md`);
  a missing one is a **P1**.
- **Fix lane:** read the LAST `- REGRESSION_VERIFIED:` line in
  coding-report.md (`grep '^- REGRESSION_VERIFIED:' | tail -1`) —
  `false` is a **P0** (the test does not capture the bug); `skipped` →
  verify the assertions capture the bug by reading them.
- Do NOT run the abuse-coverage check on an ordinary Stage 4 round — the
  contract is being written concurrently; it runs at the contract delta
  review (below).

## Security Abuse-Test Coverage (contract delta review — serial: Stage 6)

When reviewing the contract tests, with the change's
`espalier/changes/{type}/{slug}/security-record.md` carrying a
`## Security-Sensitive Fields` contract (emitted by the Stage 4 `harness-security`
audit), verify EVERY listed field has a passing negative test that (a) tampers the
value, (b) asserts the request is rejected, and (c) asserts the persistent store is
unchanged. A missing or happy-path-only test for any contracted field is a **P0** —
the tests do not prove the control holds. Send it back to the contract
phase (serial: Stage 5). This is enforced coverage, not a suggestion.
EOF
    span_replace "$REV" "$R3_START" "$R3_END"
    log "folded the reviewer (test checklist at Stage 4; abuse check at the delta review)"
  else
    record_skip reviewer-fold "$REV" "the v0.22 reviewer anchors"
  fi
fi

# 2b2. reviewer — Readability Review gains `structure:` + the magic-constant
#      declaration-comment check.
if ! handled "$REV2_MARK" "$REV" rev-readable; then
  MAGIC_LINE='- `magic:` an unexplained literal on a decision path. Replacement: the named'
  if grep -qF -- "$MAGIC_LINE" "$REV" 2>/dev/null; then
    backup_once "$REV"
    tmp="$REV.v023tmp"; cp "$REV" "$tmp"
    awk '
      $0 == "- `magic:` an unexplained literal on a decision path. Replacement: the named" && !done {
        print "- `structure:` a function doing more than its name says, or a block whose"
        print "  purpose needs decoding in place. Replacement: extract it under an"
        print "  intent-stating name (the coder'\''s \"Write It Readable\" duty)."
        done=1
      }
      $0 == "  constant, per the project'\''s constants convention." {
        print "  constant, per the project'\''s constants convention (a constant whose name"
        print "  cannot carry the meaning gets its one-line declaration comment)."
        next
      }
      { print }
    ' "$tmp" > "$REV"
    rm -f "$tmp"
    log "extended the reviewer Readability Review (structure: tag + constant-comment check)"
  else
    record_skip rev-readable "$REV" "the stock magic: tag line"
  fi
fi

# 2c. security — in-flight exclusion becomes the test-file scope stance.
SEC=espalier/agents/harness-security.md
if ! handled "$SEC_MARK" "$SEC" security-fold; then
  S1_START='If your prompt carries a `SPECULATIVE TESTS IN FLIGHT:` line, a test-writing'
  S1_END='sinks) is unchanged.'
  S2_LINE='### Abuse-Test Contract (Stage 5 must satisfy, Stage 6 enforces)'
  if grep -qF -- "$S1_START" "$SEC" && grep -qF -- "$S1_END" "$SEC" \
     && grep -qF -- "$S2_LINE" "$SEC"; then
    cat > "$BLK" << 'EOF'
Test files in the diff are in scope for secrets, live-endpoint calls, and
fixture-data leakage ONLY — a test hard-coding a real credential, hitting a
production endpoint, or embedding real customer data is a finding;
otherwise test files are not findings surface. Your audit surface (the
changed code's handlers, consumers, and sinks) is unchanged.
EOF
    span_replace "$SEC" "$S1_START" "$S1_END"
    tmp="$SEC.v023tmp"; cp "$SEC" "$tmp"
    awk '
      $0 == "### Abuse-Test Contract (Stage 5 must satisfy, Stage 6 enforces)" { print "### Abuse-Test Contract (the contract phase must satisfy, the delta review enforces)"; next }
      $0 == "Emit one block per sensitive field in scope. Stage 5 (`harness-coder` in testing" { print "Emit one block per sensitive field in scope. The post-panel contract phase"; print "(`harness-coder` in CONTRACT PHASE mode) writes a test for each; the"; print "contract delta review (`harness-reviewer`; serial mode: Stage 6) blocks if"; print "any is missing."; skiptail=2; next }
      skiptail > 0 { skiptail--; next }
      { print }
    ' "$tmp" > "$SEC"
    rm -f "$tmp"
    log "re-pointed the security agent (test-file scope stance + contract wording)"
  else
    record_skip security-fold "$SEC" "the v0.22 security anchors"
  fi
fi

# 2d. production-standards — Stage 5 duty heading re-pointed.
PROD=espalier/rules/production-standards.md
if ! handled "$PROD_MARK" "$PROD" prod-fold; then
  P_START='## Failure-Mode Tests (Stage 5 duty)'
  P_END='external call is a **P1** at Stage 6.'
  if grep -qF -- "$P_START" "$PROD" && grep -qF -- "$P_END" "$PROD"; then
    cat > "$BLK" << 'EOF'
## Failure-Mode Tests (a coding-stage duty)

Production code is proven by how it fails, not only how it succeeds. For each
NEW external-call path the change introduces, the coder writes at least one
failure-mode test alongside the code (Stage 3 under folded test-mode; the
serial test pass otherwise): the dependency times out / errors / returns
garbage → assert
the decided failure behaviour happens (fallback used, error propagated with
context, no partial write persisted). Missing failure-mode coverage on a new
external call is a **P1** at review.
EOF
    span_replace "$PROD" "$P_START" "$P_END"
    log "re-pointed production-standards failure-mode duty"
  else
    record_skip prod-fold "$PROD" "the Stage 5 duty heading span"
  fi
fi

# 2e. security-standards — Stage 5/6 sentence re-pointed.
SSTD=espalier/rules/security-standards.md
if ! handled "$SSTD_MARK" "$SSTD" sstd-fold; then
  Q_LINE='Stage 5 writes them and Stage 6 blocks if any is missing.'
  if grep -qF -- "$Q_LINE" "$SSTD"; then
    backup_once "$SSTD"
    tmp="$SSTD.v023tmp"; cp "$SSTD" "$tmp"
    awk '
      index($0, "Stage 5 writes them and Stage 6 blocks if any is missing.") {
        sub(/Stage 5 writes them and Stage 6 blocks if any is missing\./, "the post-panel contract phase writes them and the contract delta review blocks if any is missing (serial test-mode: Stage 5 writes, Stage 6 blocks).")
      }
      { print }
    ' "$tmp" > "$SSTD"
    rm -f "$tmp"
    log "re-pointed security-standards abuse-test sentence"
  else
    record_skip sstd-fold "$SSTD" "the Stage 5/6 abuse-test sentence"
  fi
fi

# 2e2. coding-standards — the Readable by Default section.
CSTD=espalier/rules/coding-standards.md
if ! handled "$CSTD_MARK" "$CSTD" cstd-readable; then
  RP_HEAD='## Required Patterns'
  if grep -qF -- "$RP_HEAD" "$CSTD" 2>/dev/null; then
    backup_once "$CSTD"
    cat > "$BLK" << 'EOF'
## Readable by Default
- No magic values: a literal on a decision path (threshold, limit, retry
  count, timeout, rate, status string) is never inlined — it becomes a
  named constant per the constants convention above, and when the name
  alone cannot carry what the value is or where it comes from, one short
  comment at the declaration explains it. Self-explaining literals
  (0, 1, "") stay literal.
- Flat control flow: guard clauses and early returns over nested
  conditionals; no chained one-liner doing three things.
- Small, single-purpose functions: a block that needs its own explanation
  is extracted under an intent-stating name.
- Comments are the last resort: structure the code so it explains itself;
  per the comment rules above, one plain line only for genuinely complex
  logic or a business rule the code cannot show.

EOF
    tmp="$CSTD.v023tmp"; cp "$CSTD" "$tmp"
    awk -v blk="$BLK" '
      $0 == "## Required Patterns" && !done {
        while ((getline line < blk) > 0) print line
        close(blk); done=1
      }
      { print }
    ' "$tmp" > "$CSTD"
    rm -f "$tmp"
    log "inserted the Readable by Default section into coding-standards"
  else
    record_skip cstd-readable "$CSTD" "the Required Patterns heading"
  fi
fi

# 2f. espalier-coding SKILL — stage references re-pointed.
CSKL=espalier/skills/espalier-coding/SKILL.md
if ! handled "$CSKL_MARK" "$CSKL" coding-fold; then
  L1='  Stage 3 (implementation), Stage 5 (testing mode), and on fix rounds.'
  T_START='- **Stage 3 — implementation.** The whole skill applies'
  T_END='- **Fix rounds — Stage 4/6 re-spawns.** Scope is the findings, nothing else:'
  if grep -qF -- "$L1" "$CSKL" && grep -qF -- "$T_START" "$CSKL" && grep -qF -- "$T_END" "$CSKL"; then
    cat > "$BLK" << 'EOF'
- **Stage 3 — implementation (code AND, folded, its tests).** The whole
  skill applies: the layer spec for
  every layer touched, the full Implementation Checklist, the Solution
  Selection Ladder before choosing the change's shape.
- **Test writing (Stage 3 folded duty / contract phase / serial test
  pass).** Layer specs still govern WHERE tests live and
  what naming/structure they follow; the ladder applies to test code too —
  reuse the project's existing test helpers, fixtures, and factories before
  writing new ones, and a new test-only dependency is still a NEW dependency
  (needs its `requirements.md` line). The test recipes themselves (abuse
  tests, failure-mode tests) are canonical in
  `espalier/agents/harness-coder.md` and
  `espalier/skills/espalier-security/SKILL.md`, not here.
- **Fix rounds — review re-spawns.** Scope is the findings, nothing else:
EOF
    span_replace "$CSKL" "$T_START" "$T_END"
    tmp="$CSKL.v023tmp"; cp "$CSKL" "$tmp"
    awk '
      $0 == "  Stage 3 (implementation), Stage 5 (testing mode), and on fix rounds." { print "  Stage 3 (implementation — including its folded test-writing duty), the"; print "  contract phase, and on fix rounds."; next }
      { print }
    ' "$tmp" > "$CSKL"
    rm -f "$tmp"
    log "re-pointed espalier-coding stage sections"
  else
    record_skip coding-fold "$CSKL" "the v0.22 stage-section anchors"
  fi
fi

# 2f2. espalier-coding SKILL — readable-as-you-go pointer.
if ! handled "$CSKL2_MARK" "$CSKL" coding-readable; then
  GATES_LINE='new-dependency and cryptic-public-name gates).'
  if grep -qF -- "$GATES_LINE" "$CSKL" 2>/dev/null; then
    backup_once "$CSKL"
    tmp="$CSKL.v023tmp"; cp "$CSKL" "$tmp"
    awk '
      { print }
      index($0, "new-dependency and cryptic-public-name gates).") && !done {
        print "Write it readable as you go: named constants over magic values, guard"
        print "clauses over nesting, small intent-named functions — defaults canonical in"
        print "`espalier/agents/harness-coder.md` (\"Write It Readable\") and"
        print "`espalier/rules/coding-standards.md` (\"Readable by Default\")."
        done=1
      }
    ' "$tmp" > "$CSKL"
    rm -f "$tmp"
    log "appended the readable-as-you-go pointer to espalier-coding"
  else
    record_skip coding-readable "$CSKL" "the solution-selection gates line"
  fi
fi

# 2g. espalier-testing SKILL — two enforcement lines re-pointed.
TSKL=espalier/skills/espalier-testing/SKILL.md
if ! handled "$TSKL_MARK" "$TSKL" testing-fold; then
  U1='`espalier/skills/espalier-security/SKILL.md` for the recipe. Enforced at Stage 6 —'
  U2='Enforced at Stage 6 — a new external call with no failure-mode test is a P1.'
  if grep -qF -- "$U1" "$TSKL" && grep -qF -- "$U2" "$TSKL"; then
    backup_once "$TSKL"
    tmp="$TSKL.v023tmp"; cp "$TSKL" "$tmp"
    awk '
      $0 == "`espalier/skills/espalier-security/SKILL.md` for the recipe. Enforced at Stage 6 —" { print "`espalier/skills/espalier-security/SKILL.md` for the recipe. Enforced at the"; print "contract delta review (serial test-mode: Stage 6) —"; next }
      $0 == "Enforced at Stage 6 — a new external call with no failure-mode test is a P1." { print "Enforced at review (the Stage 4 panel under folded test-mode; Stage 6 in"; print "serial) — a new external call with no failure-mode test is a P1."; next }
      { print }
    ' "$tmp" > "$TSKL"
    rm -f "$tmp"
    log "re-pointed espalier-testing enforcement lines"
  else
    record_skip testing-fold "$TSKL" "the two Enforced-at-Stage-6 lines"
  fi
fi

# 2h. pre-push-gate.sh — anchored stage read + message/comment text +
#     last-match test-count parse (both serial and parallel copies).
GATE=espalier/hooks/pre-push-gate.sh
if ! handled "$GATE_MARK" "$GATE" gate-fold; then
  G1='CURRENT_STAGE=$(grep "Current Stage:" "$STATE_FILE" 2>/dev/null | head -1 | grep -oE '\''[0-9]+'\'' | head -1)'
  if grep -qF -- 'CURRENT_STAGE=$(grep "Current Stage:" "$STATE_FILE"' "$GATE"; then
    backup_once "$GATE"
    tmp="$GATE.v023tmp"; cp "$GATE" "$tmp"
    awk '
      index($0, "CURRENT_STAGE=$(grep \"Current Stage:\" \"$STATE_FILE\"") {
        print "# Line-anchored like the certificate reads — a Stage History note QUOTING"
        print "# the token in prose must never outrank the real Status line (the v0.22"
        print "# cert-field lesson, applied here too)."
        print "CURRENT_STAGE=$(grep -E \x27^(- )?Current Stage:\x27 \"$STATE_FILE\" 2>/dev/null | head -1 | grep -oE \x27[0-9]+\x27 | head -1)"
        next
      }
      $0 == "      echo \"Complete code review and tests before pushing.\"" {
        print "      echo \"Complete the review stages (panel + contract phase, or serial tests) before pushing.\""
        next
      }
      index($0, "# (Stage 4 code / Stage 6 test) actually saw.") {
        print "# (the Stage 4 panel, or the contract delta review / serial Stage 6) actually"
        print "# saw. Reviewed-Diff is a content fingerprint"
        next
      }
      index($0, "TEST_COUNT=$(echo \"$TEST_OUTPUT\" | grep -oE \x27[0-9]+ (passed|passing|tests|examples|specs)\x27 | grep -oE \x27[0-9]+\x27 | head -1)") {
        sub(/head -1\)$/, "tail -1)")
      }
      { print }
    ' "$tmp" > "$GATE"
    rm -f "$tmp"
    log "anchored the stage read + last-match count parse in pre-push-gate.sh"
  else
    record_skip gate-fold "$GATE" "the stock Current Stage grep line"
  fi
fi

# --- 3. Verify ---------------------------------------------------------------
fail=""
grep -qF "$PIPE_MARK"  espalier/pipeline.md                        || fail="$fail pipeline.md"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md           || fail="$fail espalier-SKILL"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md       || fail="$fail espalier-fix-SKILL"
grep -qF "$MAP_MARK"   espalier/skills/espalier-map/SKILL.md       || fail="$fail espalier-map-SKILL"
grep -qF "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md     || fail="$fail espalier-grill-SKILL"
grep -qF "$REQ_MARK"   espalier/skills/espalier-requirements/SKILL.md || fail="$fail espalier-requirements-SKILL"
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh            || fail="$fail espalier-stats"
grep -qF "$RIDX_MARK"  espalier/hooks/rebuild-commit-index.sh      || fail="$fail rebuild-commit-index"
[ -n "$fail" ] && die "post-migration verification failed for:$fail"

handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-fold    || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-fold || die "post-migration verification failed: reviewer lacks the Test Review section"
handled "$SEC_MARK"   espalier/agents/harness-security.md security-fold || die "post-migration verification failed: security lacks the test-scope stance"
handled "$PROD_MARK"  espalier/rules/production-standards.md prod-fold  || die "post-migration verification failed: production-standards not re-pointed"
handled "$SSTD_MARK"  espalier/rules/security-standards.md   sstd-fold  || die "post-migration verification failed: security-standards not re-pointed"
handled "$CSKL_MARK"  espalier/skills/espalier-coding/SKILL.md  coding-fold  || die "post-migration verification failed: espalier-coding not re-pointed"
handled "$TSKL_MARK"  espalier/skills/espalier-testing/SKILL.md testing-fold || die "post-migration verification failed: espalier-testing not re-pointed"
handled "$READ_MARK"  espalier/agents/harness-coder.md coder-readable || die "post-migration verification failed: coder lacks the Write It Readable section"
handled "$CSTD_MARK"  espalier/rules/coding-standards.md cstd-readable || die "post-migration verification failed: coding-standards lacks Readable by Default"
handled "$CSKL2_MARK" espalier/skills/espalier-coding/SKILL.md coding-readable || die "post-migration verification failed: espalier-coding lacks the readable pointer"
handled "$REV2_MARK"  espalier/agents/harness-reviewer.md rev-readable || die "post-migration verification failed: reviewer lacks the structure: readability tag"
handled "$GATE_MARK"  "$GATE" gate-fold || die "post-migration verification failed: gate lacks the anchored stage read"
bash -n "$GATE" || die "post-migration verification failed: pre-push-gate.sh no longer parses (restore from $GATE.pre-v0.23.bak)"
bash -n espalier/hooks/espalier-stats.sh || die "post-migration verification failed: espalier-stats.sh no longer parses"

log "done. v0.23.0 applied — backups at <file>.pre-v0.23.bak."
log "Tests now ride the coder (test-mode: folded, the default); the 2-agent"
log "panel reviews code+tests together; Stages 5/6 are the contract phase or"
log "SKIPPED rows; test-mode: serial restores the pre-v0.22 flow per repo."
exit 0
