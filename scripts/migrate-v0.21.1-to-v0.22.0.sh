#!/bin/bash
# Migrate a v0.21.1 Espalier install to v0.22.0.
#
# v0.22.0 is the second pipeline-speed release: same gates, sentinels, round
# caps, certificates, and human checkpoints — the changes are dispatch-order,
# read-scope, and wait-scheduling only:
#
#   - Speculative Stage 5 (quarantine-on-FAIL): the test-coder joins the
#     round-1 Stage 4 panel as a third concurrent agent, reporting to
#     coding-report.part-test.md; a panel FAIL quarantines the speculative
#     tests under the change dir so no later gate/round/re-spawn ever sees a
#     stale artifact. `speculative-tests: off` restores the serial flow.
#   - Stage 6 delta rounds: test re-review rounds >= 2 get the same
#     CHANGED SINCE LAST REVIEW delta-scope contract Stage 4 got in v0.21.
#   - Stage durations in espalier-stats.sh (human-wait vs agent-work split).
#   - Pre-flight fold: non-critical drift/conv/doctor signals ride a third
#     question on the approval gate; critical/expired keeps the immediate
#     blocking prompt.
#   - Deploy-Target pre-authorization at the approval gate (deploy-configured
#     repos only) + a defined unattended Stage 9 posture.
#   - Stage 8 CI wait protocol (blocking chunked watch; 8.5 rides the wait).
#   - Concurrent build+lint at the Stage 3 exit gate; one-invocation Stage 7
#     bookkeeping in the fix lane.
#   - pre-push-gate.sh: opt-in parallel gate sections (hook-parallel-gates:
#     yes — NOT enabled by this migration; init proposes it) + a WARN-only
#     dependency-audit cache keyed on the manifest/lockfile hash.
#
# Mechanics:
#   - Refresh 4 pure-copy files from templates (backup-on-diff →
#     <file>.pre-v0.22.bak): espalier/pipeline.md, the espalier +
#     espalier-fix SKILL files, and espalier/hooks/espalier-stats.sh.
#   - Anchored edits into the 4 SUBSTITUTED per-project files (never
#     wholesale-copied): coder gains the Speculative/Contract entry points;
#     reviewer + security gain the in-flight exclusion paragraph;
#     pre-push-gate.sh gains the HOOK_PARALLEL read, the parallel section,
#     the guard-line switches, and the audit cache (span-splice, the v0.9.2
#     precedent). A customised file missing its anchor is skipped with a
#     record in espalier/.migrations-skipped, never mangled.
#   - Appends espalier/.dep-audit-cache to .gitignore (newline-guarded).
#   - No config keys written: speculative-tests defaults on when absent;
#     hook-parallel-gates absent = serial (init-time opt-in only).
#
# Usage:
#   bash migrate-v0.21.1-to-v0.22.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,46p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.21.1→v0.22.0] $*"; }
die() { echo "[migrate v0.21.1→v0.22.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
# v0.23 note: the plugin's templates moved past the speculative dispatch (the
# Stage 3/5 fold). This migration still runs mid-chain for older installs: the
# pure-copy refresh below installs the CURRENT templates (per the chain
# convention), so its pure-copy markers/probe track the current template text,
# while the anchored agent/hook splices below stay v0.22-shaped — migration
# #32 replaces those spans afterward.
grep -q "test-mode" "$TPL/skills/espalier.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not current (espalier template lacks the test-mode read). Update the plugin first."

# --- v0.22 markers (also the idempotency check) ------------------------------
# Pure-copy markers track the CURRENT template text (v0.23 fold).
PIPE_MARK='Contract Phase (folded)'
ESP_MARK='Stage 5/6 (folded)'
FIX_MARK='Stage 5/6 (folded)'
STATS_MARK='Stage durations'
CODER_MARK='Speculative & Contract entry points'
REV_MARK='SPECULATIVE TESTS IN FLIGHT'
HOOK_PAR_MARK='hook-parallel-gates'
HOOK_CACHE_MARK='dep-audit-cache'
HOOK_CERT_MARK='(- )?Reviewed-Diff:'
SKIPFILE="espalier/.migrations-skipped"

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.22.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$PIPE_MARK"  espalier/pipeline.md                    2>/dev/null || mark "pipeline.md speculative Stage 5 trigger"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md       2>/dev/null || mark "espalier SKILL Stage 4→5 handoff"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md   2>/dev/null || mark "espalier-fix SKILL speculative Stage 5"
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh        2>/dev/null || mark "espalier-stats stage durations"
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-speculative    || mark "coder speculative/contract entry points"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-inflight    || mark "reviewer in-flight exclusion"
handled "$REV_MARK"   espalier/agents/harness-security.md security-inflight    || mark "security in-flight exclusion"
handled "$HOOK_PAR_MARK"   espalier/hooks/pre-push-gate.sh hook-parallel       || mark "pre-push parallel gate sections"
handled "$HOOK_CACHE_MARK" espalier/hooks/pre-push-gate.sh hook-audit-cache    || mark "pre-push dependency-audit cache"
handled "$HOOK_CERT_MARK"  espalier/hooks/pre-push-gate.sh hook-cert-anchor    || mark "pre-push anchored certificate read"

if [ -z "$missing" ]; then
  log "already at v0.22.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh pipeline.md + espalier/espalier-fix SKILLs + espalier-stats.sh (backup-on-diff → .pre-v0.22.bak)"
  log "DRY RUN — would anchored-edit coder/reviewer/security + pre-push-gate.sh (skip-with-record if customised)"
  log "DRY RUN — would append espalier/.dep-audit-cache to .gitignore"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh espalier/pipeline.md, 2 pipeline SKILL files, and espalier-stats.sh from templates (backups: <file>.pre-v0.22.bak)"
  echo "  - anchored-edit the 3 per-project agent files + pre-push-gate.sh (customised files skipped, never mangled)"
  echo "  - append espalier/.dep-audit-cache to .gitignore"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.22.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
refresh "$TPL/pipeline.md"            espalier/pipeline.md
refresh "$TPL/skills/espalier.md"     espalier/skills/espalier/SKILL.md
refresh "$TPL/skills/espalier-fix.md" espalier/skills/espalier-fix/SKILL.md
refresh "$HTPL/espalier-stats.sh"     espalier/hooks/espalier-stats.sh
chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true

# --- 2. Anchored edits -------------------------------------------------------
BLK=$(mktemp -t v022blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.22 '$1' change from the template yourself."
  grep -qF "v0.22.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.22.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

backup_once() { [ -f "$1.pre-v0.22.bak" ] || cp "$1" "$1.pre-v0.22.bak"; }

insert_before() {  # $1 = file, $2 = anchor (fixed string) — block from $BLK
  local f="$1" anchor="$2"
  backup_once "$f"
  local tmp="$f.v022tmp"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); done=1
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# 2a. coder — Speculative & Contract entry points (before Production-Aware Coding)
if ! handled "$CODER_MARK" espalier/agents/harness-coder.md coder-speculative; then
  ANCHOR='## Production-Aware Coding (do this WHILE writing, not only at review)'
  if grep -qF -- "$ANCHOR" espalier/agents/harness-coder.md; then
    cat > "$BLK" << 'EOF'
### Speculative & Contract entry points (Stage 5 dispatch modes)

Testing mode has two prompt-marked entry points beyond the classic
post-review dispatch:

- **`SPECULATIVE DISPATCH:`** — you run CONCURRENTLY with the round-1
  review panel. Write everything EXCEPT the contracted abuse tests. Do NOT
  read security-record.md (it may be mid-write). Write your report to the
  prompt's `REPORT TARGET:` part file, never to coding-report.md (the
  panel is reading it), and list EVERY file you create under "Files
  created" — the orchestrator's quarantine/discard mechanics operate on
  that exact list, so an unlisted file is an unmanaged file. Run only
  scoped invocations of your new test files; no whole-tree builds, no
  dependency installs.
- **`CONTRACT PHASE:`** — the panel has passed. Read security-record.md's
  `## Security-Sensitive Fields` and write the named abuse tests. When the
  prompt also carries "code changed since your tests", first reconcile the
  restored speculative tests against those files. Append your test report
  to coding-report.md normally.

EOF
    insert_before espalier/agents/harness-coder.md "$ANCHOR"
    log "inserted coder Speculative/Contract entry points"
  else
    record_skip coder-speculative espalier/agents/harness-coder.md "the Production-Aware Coding heading"
  fi
fi

# 2b. reviewer — in-flight exclusion (before ## Review Process)
if ! handled "$REV_MARK" espalier/agents/harness-reviewer.md reviewer-inflight; then
  ANCHOR='## Review Process'
  if grep -qF -- "$ANCHOR" espalier/agents/harness-reviewer.md; then
    cat > "$BLK" << 'EOF'
If your prompt carries a `SPECULATIVE TESTS IN FLIGHT:` line, a test-writing
agent is running concurrently with you: new/changed TEST files that
coding-report.md does not list are its work-in-progress — exclude them from
your scope and your verdict; they are reviewed at Stage 6. This narrows
nothing that was ever this round's scope (tests were never Stage 4's
subject), and your suspicion-expansion license over the CHANGE's files is
unchanged.

EOF
    insert_before espalier/agents/harness-reviewer.md "$ANCHOR"
    log "inserted reviewer in-flight exclusion"
  else
    record_skip reviewer-inflight espalier/agents/harness-reviewer.md "the Review Process heading"
  fi
fi

# 2c. security — in-flight exclusion (before ## Scope Gate)
if ! handled "$REV_MARK" espalier/agents/harness-security.md security-inflight; then
  ANCHOR='## Scope Gate (self-noop on irrelevant changes)'
  if grep -qF -- "$ANCHOR" espalier/agents/harness-security.md; then
    cat > "$BLK" << 'EOF'
If your prompt carries a `SPECULATIVE TESTS IN FLIGHT:` line, a test-writing
agent is running concurrently with you: new/changed TEST files that
coding-report.md does not list are its work-in-progress — exclude them from
your scope and your verdict; they are reviewed at Stage 6. Your audit
surface (the changed code's handlers, consumers, and sinks) is unchanged.

EOF
    insert_before espalier/agents/harness-security.md "$ANCHOR"
    log "inserted security in-flight exclusion"
  else
    record_skip security-inflight espalier/agents/harness-security.md "the Scope Gate heading"
  fi
fi

# 2d. pre-push-gate.sh — HOOK_PARALLEL read + guard switches + parallel section
GATE=espalier/hooks/pre-push-gate.sh
if ! handled "$HOOK_PAR_MARK" "$GATE" hook-parallel; then
  A1='# The three {command} placeholders below were substituted from'
  G1='if [ "${PIPELINE_TRACKED:-yes}" = "yes" ]; then gate_build_section; fi'
  G2='if [ "${PIPELINE_TRACKED:-yes}" = "yes" ]; then gate_lint_section; fi'
  G3='if [ "${PIPELINE_TRACKED:-yes}" = "yes" ]; then gate_tests_section; fi'
  A2='echo "All gates passed. Push allowed."'
  if grep -qF -- "$A1" "$GATE" && grep -qF -- "$G1" "$GATE" \
     && grep -qF -- "$G2" "$GATE" && grep -qF -- "$G3" "$GATE" \
     && grep -qF -- "$A2" "$GATE"; then
    backup_once "$GATE"
    # (i) config read before the placeholder comment
    cat > "$BLK" << 'EOF'
# Parallel gate mode (opt-in): `hook-parallel-gates: yes` in
# espalier/.espalier-config runs build/lint/tests as concurrent jobs
# (sum → max wall-clock). The key is written at init only when discovery
# judged the three commands independent AND the human confirmed. Every check
# still runs and still blocks on failure — only the overlap changes. Key
# absent (the default): the serial sections below run exactly as before.
HOOK_PARALLEL=$(grep '^hook-parallel-gates:' espalier/.espalier-config 2>/dev/null | awk '{print $2}')

EOF
    insert_before "$GATE" "$A1"
    # (ii) guard-line switches (exact-line replacement, BSD/GNU portable via awk)
    tmp="$GATE.v022tmp"; cp "$GATE" "$tmp"
    awk '
      $0 == "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ]; then gate_build_section; fi" \
        { print "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ] && [ \"$HOOK_PARALLEL\" != \"yes\" ]; then gate_build_section; fi"; next }
      $0 == "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ]; then gate_lint_section; fi" \
        { print "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ] && [ \"$HOOK_PARALLEL\" != \"yes\" ]; then gate_lint_section; fi"; next }
      $0 == "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ]; then gate_tests_section; fi" \
        { print "if [ \"${PIPELINE_TRACKED:-yes}\" = \"yes\" ] && [ \"$HOOK_PARALLEL\" != \"yes\" ]; then gate_tests_section; fi"; next }
      { print }
    ' "$tmp" > "$GATE"
    rm -f "$tmp"
    # (iii) parallel section before the final success line
    cat > "$BLK" << 'EOF'
# Parallel gate execution (hook-parallel-gates: yes) — the SAME three checks
# with the SAME messages and the same exit-2 blocking; build/lint/tests
# overlap instead of queue. Failures report in the serial order (build first)
# so multi-failure output stays deterministic. bash-3.2 safe: per-pid `wait`
# (no `wait -n`), per-job temp-file output.
gate_parallel_section() {
  _pb=$(mktemp); _pl=$(mktemp); _pt=$(mktemp)
  run_build  > "$_pb" 2>&1 & _pid_b=$!
  run_lint   > "$_pl" 2>&1 & _pid_l=$!
  run_tests  > "$_pt" 2>&1 & _pid_t=$!
  wait "$_pid_b"; _rc_b=$?
  wait "$_pid_l"; _rc_l=$?
  wait "$_pid_t"; _rc_t=$?
  if [ "$_rc_b" -ne 0 ]; then
    { echo "BLOCKED: Build fails"; tail -20 "$_pb"; } >&2
    rm -f "$_pb" "$_pl" "$_pt"; exit 2
  fi
  if [ "$_rc_l" -ne 0 ]; then
    { echo "BLOCKED: Lint fails"; tail -20 "$_pl"; } >&2
    rm -f "$_pb" "$_pl" "$_pt"; exit 2
  fi
  TEST_OUTPUT=$(cat "$_pt")
  rm -f "$_pb" "$_pl" "$_pt"
  if [ "$_rc_t" -ne 0 ]; then
    { echo "BLOCKED: Tests fail"; printf '%s\n' "$TEST_OUTPUT" | tail -20; } >&2
    exit 2
  fi
  # Same count-parse as gate_tests_section (kept in lockstep).
  TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ (passed|passing|tests|examples|specs)' | grep -oE '[0-9]+' | head -1)
  if [ -z "$TEST_COUNT" ]; then
    _go_ok=$(echo "$TEST_OUTPUT" | grep -cE '^ok[[:space:]]')
    [ "$_go_ok" -gt 0 ] 2>/dev/null && TEST_COUNT=$_go_ok
  fi
  if [ -z "$TEST_COUNT" ]; then
    {
      echo "WARNING: could not parse a test count from the runner output (unrecognized format)."
      echo "         Exit code 0 accepted; the total_tests>0 check was skipped this push."
    } >&2
  elif [ "$TEST_COUNT" -eq 0 ]; then
    echo "BLOCKED: No tests found (total_tests must be > 0)" >&2
    exit 2
  fi
}
if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" = "yes" ]; then gate_parallel_section; fi

EOF
    insert_before "$GATE" "$A2"
    log "inserted pre-push parallel gate sections + guard switches"
  else
    record_skip hook-parallel "$GATE" "the placeholder comment / serial guard lines / success line"
  fi
fi

# 2e. pre-push-gate.sh — dependency-audit cache (span-splice, v0.9.2 precedent)
if ! handled "$HOOK_CACHE_MARK" "$GATE" hook-audit-cache; then
  SPAN_START='# Dependency audit — WARN only, per available tool for the detected stack. Wrapped'
  if grep -qF -- "$SPAN_START" "$GATE"; then
    backup_once "$GATE"
    cat > "$BLK" << 'EOF'
# Dependency audit — WARN only, per available tool for the detected stack. Wrapped
# in a timeout when available so a slow / offline advisory fetch can't hang the
# push; a nonzero exit may mean vulnerabilities OR a tool/network error (never blocks).
# Cached per lockfile hash (gitignored espalier/.dep-audit-cache) with a TTL
# (dep-audit-ttl-days, default 7): the audit never blocks, so replaying a cached
# warning weakens no gate — a new dependency changes the lockfile and forces a
# fresh run; the TTL bounds staleness for newly published advisories.
AUDIT_CACHE="espalier/.dep-audit-cache"
_lock_hash=$( { cat package.json package-lock.json pnpm-lock.yaml yarn.lock pyproject.toml poetry.lock uv.lock requirements.txt go.mod go.sum Cargo.toml Cargo.lock 2>/dev/null; } | git hash-object --stdin 2>/dev/null )
_audit_should_run() {
  [ -z "$_lock_hash" ] && return 0   # nothing to key on — run as before
  _ttl_days=$(grep '^dep-audit-ttl-days:' espalier/.espalier-config 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [ -z "$_ttl_days" ] && _ttl_days=7
  if [ -f "$AUDIT_CACHE" ]; then
    _c_hash=$(head -1 "$AUDIT_CACHE" | cut -d' ' -f1)
    _c_epoch=$(head -1 "$AUDIT_CACHE" | cut -d' ' -f2)
    case "$_c_epoch" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$_c_hash" = "$_lock_hash" ] \
       && [ $(( $(date +%s) - _c_epoch )) -lt $(( _ttl_days * 86400 )) ]; then
      _c_msg=$(head -1 "$AUDIT_CACHE" | cut -d' ' -f3-)
      [ -n "$_c_msg" ] && echo "WARNING (cached): $_c_msg" >&2
      return 1
    fi
  fi
  return 0
}
_audit_record() {  # $1 = warning message ("" = clean)
  [ -n "$_lock_hash" ] && echo "$_lock_hash $(date +%s) $1" > "$AUDIT_CACHE" 2>/dev/null || true
}
if _audit_should_run; then
  command -v timeout >/dev/null 2>&1 && _to="timeout 45" || _to=""
  _audit_msg=""
  if   [ -f package.json ] && command -v npm >/dev/null 2>&1; then
    $_to npm audit --omit=dev --audit-level=high >/dev/null 2>&1 || _audit_msg="'npm audit' flagged high-severity advisories or errored (non-blocking)."
  elif { [ -f pyproject.toml ] || [ -f requirements.txt ]; } && command -v pip-audit >/dev/null 2>&1; then
    $_to pip-audit >/dev/null 2>&1 || _audit_msg="'pip-audit' flagged vulnerable dependencies or errored (non-blocking)."
  elif [ -f go.mod ] && command -v govulncheck >/dev/null 2>&1; then
    $_to govulncheck ./... >/dev/null 2>&1 || _audit_msg="'govulncheck' flagged vulnerabilities or errored (non-blocking)."
  elif [ -f Cargo.toml ] && command -v cargo-audit >/dev/null 2>&1; then
    $_to cargo audit >/dev/null 2>&1 || _audit_msg="'cargo audit' flagged vulnerable crates or errored (non-blocking)."
  fi
  [ -n "$_audit_msg" ] && echo "WARNING: $_audit_msg" >&2
  _audit_record "$_audit_msg"
fi
EOF
    # Replace the span: from SPAN_START through the first bare `fi` line
    # (the audit chain's closing fi — no inner bare-fi exists in the stock span).
    tmp="$GATE.v022tmp"; cp "$GATE" "$tmp"
    awk -v blk="$BLK" -v start="$SPAN_START" '
      !insp && index($0, start) == 1 {
        while ((getline line < blk) > 0) print line
        close(blk); insp=1; skipping=1; next
      }
      skipping && $0 == "fi" { skipping=0; next }
      skipping { next }
      { print }
    ' "$tmp" > "$GATE"
    rm -f "$tmp"
    if grep -qF "$HOOK_CACHE_MARK" "$GATE"; then
      log "spliced pre-push dependency-audit cache"
    else
      cp "$GATE.pre-v0.22.bak" "$GATE"
      record_skip hook-audit-cache "$GATE" "the dependency-audit span"
    fi
  else
    record_skip hook-audit-cache "$GATE" "the dependency-audit comment line"
  fi
fi

# 2f. pre-push-gate.sh — anchored certificate read (field find: a Stage
# History note quoting "Base-Ref:"/"Reviewed-Diff:" in prose outranked the
# real Status-block line via the unanchored last-match, producing a bogus
# fingerprint and a false BLOCK).
if ! handled "$HOOK_CERT_MARK" "$GATE" hook-cert-anchor; then
  C1='REVIEWED=$(grep "Reviewed-Diff:" "$STATE_FILE"'
  C2='BASE_REF=$(grep "Base-Ref:" "$STATE_FILE"'
  if grep -qF -- "$C1" "$GATE" && grep -qF -- "$C2" "$GATE"; then
    backup_once "$GATE"
    tmp="$GATE.v022tmp"; cp "$GATE" "$tmp"
    awk '
      index($0, "REVIEWED=$(grep \"Reviewed-Diff:\" \"$STATE_FILE\"") {
        print "  # Anchored to line start (Status-block shape `- Key:` or bare `Key:`): a"
        print "  # Stage History note QUOTING either token in prose must never outrank the"
        print "  # real certificate line (v0.22 field find: unanchored last-match produced"
        print "  # a bogus revision + empty-diff fingerprint and a false BLOCK)."
        print "  REVIEWED=$(grep -E \x27^(- )?Reviewed-Diff:\x27 \"$STATE_FILE\" | tail -1 | sed \x27s/.*Reviewed-Diff:[[:space:]]*//\x27 | tr -d \x27[:space:]\x27)"
        next
      }
      index($0, "BASE_REF=$(grep \"Base-Ref:\" \"$STATE_FILE\"") {
        print "  BASE_REF=$(grep -E \x27^(- )?Base-Ref:\x27 \"$STATE_FILE\" | tail -1 | sed \x27s/.*Base-Ref:[[:space:]]*//\x27 | tr -d \x27[:space:]\x27)"
        next
      }
      { print }
    ' "$tmp" > "$GATE"
    rm -f "$tmp"
    log "anchored the pre-push certificate read"
  else
    record_skip hook-cert-anchor "$GATE" "the stock Reviewed-Diff/Base-Ref grep lines"
  fi
fi

# --- 3. .gitignore append (idempotent + newline guard) -----------------------
entry="espalier/.dep-audit-cache"
if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  echo "$entry" >> .gitignore
  log "appended $entry to .gitignore"
fi

# --- 4. Verify ---------------------------------------------------------------
fail=""
grep -qF "$PIPE_MARK"  espalier/pipeline.md                  || fail="$fail pipeline.md"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md     || fail="$fail espalier-SKILL"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md || fail="$fail espalier-fix-SKILL"
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh      || fail="$fail espalier-stats"
[ -n "$fail" ] && die "post-migration verification failed for:$fail"

handled "$CODER_MARK"      espalier/agents/harness-coder.md    coder-speculative || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$REV_MARK"        espalier/agents/harness-reviewer.md reviewer-inflight || die "post-migration verification failed: reviewer lacks '$REV_MARK'"
handled "$REV_MARK"        espalier/agents/harness-security.md security-inflight || die "post-migration verification failed: security lacks '$REV_MARK'"
handled "$HOOK_PAR_MARK"   "$GATE"                             hook-parallel     || die "post-migration verification failed: gate lacks '$HOOK_PAR_MARK'"
handled "$HOOK_CACHE_MARK" "$GATE"                             hook-audit-cache  || die "post-migration verification failed: gate lacks '$HOOK_CACHE_MARK'"
handled "$HOOK_CERT_MARK"  "$GATE"                             hook-cert-anchor  || die "post-migration verification failed: gate lacks the anchored certificate read"
bash -n "$GATE" || die "post-migration verification failed: pre-push-gate.sh no longer parses (restore from $GATE.pre-v0.22.bak)"

log "done. v0.22.0 applied — backups at <file>.pre-v0.22.bak."
log "Same gates, caps, and certificates; Stage 5 now overlaps the round-1"
log "panel (quarantine-on-FAIL), Stage 6 rounds run delta scope, and the"
log "push hook can overlap its sections once init confirms independence."
exit 0
