#!/bin/bash
# Pre-push quality gate
# Blocks git push unless all conditions are met.
#
# Exit-code contract (Claude Code PreToolUse semantics): blocking paths exit
# with code 2 and the reason on stderr — exit code 1 would NOT block, and
# stdout is invisible in hook context. Warnings also print to stderr, exit 0.
#
# Runs from the repo root: the wrapper cd's here, but cd defensively too so a
# direct invocation from a subdir still resolves the relative espalier/ paths
# below (a wrong cwd would make every `-f` test miss and fail OPEN).
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$_ROOT" ] && cd "$_ROOT" || true

# Doctor-cadence reminder — non-blocking, printed before any gate logic so it
# fires on every push regardless of gate outcome (the gate has early-exit
# paths). Never affects the exit code. Blocking paths elsewhere in this script
# exit with code 2 and the reason on stderr — Claude Code PreToolUse semantics;
# exit code 1 would NOT block.
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  doctor_due && echo "Reminder: an /espalier-doctor drift scan is due."
fi

# Find the ACTIVE change: the most recently modified pipeline-state.md whose
# Status is not terminal (espalier/changes/{type}/{slug}/pipeline-state.md —
# depth 3 from CHANGES_DIR). A COMPLETE/ABORTED change describes FINISHED work;
# letting it gate later pushes would (a) block every manual push after a
# completed pipeline (its stale Reviewed-Diff never matches again) and (b) let
# a newer finished change shadow an in-flight one. A state file with no
# `- Status:` line (pre-v0.9.2 full-pipeline runs) counts as in-flight.
# PARTIAL_FIX is deliberately NOT terminal — it is written BEFORE that fix's
# own Stage 7 push, which must still be gated; the follow-up root-cause feat
# then supersedes it as the active change.
CHANGES_DIR="espalier/changes"

# stat format differs between BSD (macOS) and GNU (Linux)
if [ "$(uname)" = "Darwin" ]; then
  STAT_ARGS=(-f '%m %N')
else
  STAT_ARGS=(-c '%Y %n')
fi

STATE_FILE=""
ACTIVE_COUNT=0
OTHER_ACTIVE=""
while IFS= read -r _cand; do
  [ -n "$_cand" ] || continue
  _f="${_cand#* }"   # strip the leading epoch; path may contain spaces
  [ -f "$_f" ] || continue
  if grep -qE '^- Status:[[:space:]]*(COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED)\b' "$_f" 2>/dev/null; then
    continue   # terminal or not-yet-started (FILED skeleton) — never gates a later push
  fi
  ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
  if [ -z "$STATE_FILE" ]; then
    STATE_FILE="$_f"
  else
    OTHER_ACTIVE="$OTHER_ACTIVE $_f"
  fi
done << EOF_STATES
$(find "$CHANGES_DIR" -mindepth 3 -maxdepth 3 -name pipeline-state.md \
    -not -path "*/_template/*" \
    -exec stat "${STAT_ARGS[@]}" {} + 2>/dev/null | sort -rn)
EOF_STATES

# No in-flight change is NOT an early exit: the pipeline-only gates (stage,
# certificate, build/lint/test) are skipped, but the secret scan and dependency
# audit below still run — a leaked credential must fail closed on EVERY push.
PIPELINE_TRACKED=yes
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  PIPELINE_TRACKED=no
  echo "WARNING: No in-flight Espalier change found. Pushing without pipeline tracking." >&2
fi

if [ "$ACTIVE_COUNT" -gt 1 ]; then
  {
    echo "WARNING: $ACTIVE_COUNT in-flight changes found; gating the most recent: $STATE_FILE"
    echo "         Not checked:$OTHER_ACTIVE"
    echo "         If this push belongs to one of those, complete or abort the newer change first."
  } >&2
fi

# Check pipeline stage (must be ≥ 7). Line-anchored like the certificate
# reads below — a Stage History note QUOTING the token in prose must never
# outrank the real Status line (the v0.22 cert-field lesson, applied here
# too). Take the FIRST match's first integer.
CURRENT_STAGE=$(grep -E '^(- )?Current Stage:' "$STATE_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
if [ "$PIPELINE_TRACKED" = "yes" ]; then
  if [ -z "$CURRENT_STAGE" ]; then
    # Fail closed: a tracked change whose stage cannot be parsed means the
    # state file is corrupt or hand-edited — never silently skip the gate.
    {
      echo "BLOCKED: pipeline-state.md has no parsable 'Current Stage:' line — state file corrupt or hand-edited."
      echo "  File: $STATE_FILE"
      echo "Restore the 'Current Stage:' line (or abort the change) before pushing."
    } >&2
    exit 2
  fi
  if [ "$CURRENT_STAGE" -lt 7 ]; then
    {
      echo "BLOCKED: Pipeline is at Stage $CURRENT_STAGE (need ≥ 7 for push)"
      echo "Complete the review stages (panel + contract phase, or serial tests) before pushing."
    } >&2
    exit 2
  fi
fi

# Review-certificate check — the code being pushed must match what the last review
# (the Stage 4 panel, or the contract delta review / serial Stage 6) actually
# saw. Reviewed-Diff is a content fingerprint
# of the source diff (espalier/ bookkeeping excluded), anchored to the Base-Ref
# recorded at Stage 3. A code change after review changes the fingerprint and blocks
# the push until a fresh review re-certifies the current diff. This is what makes the
# coder→reviewer→coder loop fail closed: a fix that skipped re-review cannot ship.
REVIEWED=""
BASE_REF=""
if [ "$PIPELINE_TRACKED" = "yes" ]; then
  # Anchored to line start (Status-block shape `- Key:` or bare `Key:`): a
  # Stage History note QUOTING either token in prose must never outrank the
  # real certificate line — an unanchored last-match once produced a bogus
  # revision + empty-diff fingerprint and a false BLOCK (v0.22 field find).
  REVIEWED=$(grep -E '^(- )?Reviewed-Diff:' "$STATE_FILE" | tail -1 | sed 's/.*Reviewed-Diff:[[:space:]]*//' | tr -d '[:space:]')
  BASE_REF=$(grep -E '^(- )?Base-Ref:' "$STATE_FILE" | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
  if [ -n "$REVIEWED" ] && [ -n "$BASE_REF" ]; then
    CURRENT=$(git diff "$BASE_REF" -- . ':(exclude)espalier/' | git hash-object --stdin)
    if [ "$CURRENT" != "$REVIEWED" ]; then
      {
        echo "BLOCKED: Source changed after its last review (Reviewed-Diff mismatch)."
        echo "  reviewed fingerprint: $REVIEWED"
        echo "  current  fingerprint: $CURRENT"
        echo "Re-run code review on the current diff (Stage 4) before pushing."
      } >&2
      exit 2
    fi
  elif grep -qE '^\|[[:space:]]*4[[:space:]]*\|[[:space:]]*PASSED' "$STATE_FILE" 2>/dev/null; then
    # A Stage-4 PASSED row proves a review ran, so the certificate SHOULD exist.
    # Its absence means the state file was hand-edited or corrupted: fail closed.
    {
      echo "BLOCKED: Stage 4 passed but the review certificate is missing"
      echo "  (no Base-Ref/Reviewed-Diff in $STATE_FILE despite a '| 4 | PASSED |' row)."
      echo "Re-run code review (Stage 4) to re-certify, or restore the certificate lines."
    } >&2
    exit 2
  else
    # True legacy: no Stage-4 PASSED row means no review ever recorded one —
    # pre-certificate installs only. Warn, don't block.
    {
      echo "WARNING: No review certificate (Base-Ref/Reviewed-Diff) in $STATE_FILE —"
      echo "         legacy or pre-review change. Skipping the re-review check."
    } >&2
  fi
fi

# --- Security scan: secrets BLOCK, dependency audit WARNS -------------------
# Deterministic backstop to the harness-security audit. A leaked credential must
# fail closed; a pre-existing dependency CVE should not block THIS change. Both
# degrade gracefully — absent tooling never fails the push.
#
# Determine the range to scan. Prefer the reviewed range (Base-Ref..HEAD). With no
# Base-Ref (legacy / first push), fall back to the upstream tracking branch, then
# the previous commit — so the scan always sees the pushed code and never silently
# scans nothing.
SEC_RANGE=""
if [ -n "$BASE_REF" ]; then
  SEC_RANGE="$BASE_REF..HEAD"
else
  _up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  if [ -n "$_up" ]; then
    SEC_RANGE="$_up..HEAD"
  elif git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    SEC_RANGE="HEAD~1..HEAD"
  fi
fi
if [ -z "$SEC_RANGE" ]; then
  echo "WARNING: cannot determine a push range (no Base-Ref, upstream, or prior commit) — secret scan skipped." >&2
fi

if [ -n "$SEC_RANGE" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks detect --no-banner --redact --log-opts="$SEC_RANGE" >/dev/null 2>&1; then
      {
        echo "BLOCKED: gitleaks found a potential secret in the pushed diff."
        echo "  Inspect with: gitleaks detect --log-opts=\"$SEC_RANGE\" -v"
      } >&2
      exit 2
    fi
  else
    # Fallback: high-signal pattern grep over the ADDED lines of the pushed diff.
    ADDED=$(git diff "$SEC_RANGE" -- . ':(exclude)espalier/' 2>/dev/null | grep '^+' | grep -v '^+++')
    if printf '%s\n' "$ADDED" | grep -qiE '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Za-z ]*PRIVATE KEY-----|(secret|api[_-]?key|apikey|access[_-]?token|password|passwd|private[_-]?key)[[:space:]]*[:=][[:space:]]*.{0,3}[A-Za-z0-9/+_-]{16,})'; then
      {
        echo "BLOCKED: a possible hard-coded secret was added in this push."
        echo "  Matched an AWS key / private key / long api_key=… assignment."
        echo "  Move it to config/env and re-push (install 'gitleaks' for higher fidelity)."
      } >&2
      exit 2
    fi
  fi
fi

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

# Parallel gate mode (opt-in): `hook-parallel-gates: yes` in
# espalier/.espalier-config runs build/lint/tests as concurrent jobs
# (sum → max wall-clock). The key is written at init only when discovery
# judged the three commands independent AND the human confirmed. Every check
# still runs and still blocks on failure — only the overlap changes. Key
# absent (the default): the serial sections below run exactly as before.
HOOK_PARALLEL=$(grep '^hook-parallel-gates:' espalier/.espalier-config 2>/dev/null | awk '{print $2}')

# The three {command} placeholders below were substituted from
# DISCOVERY.ci_checks at init. A kind the repo did not have (null) was
# substituted as a clean no-op for build/lint (`true  # none discovered`) or a
# fail-closed, actionable stub for test — never an invented command. Refresh
# via /espalier-prune when the project gains one.

# Run build check
# Each {..._command} is substituted into a FUNCTION BODY, so the value may be a
# single command OR a multi-line block. A repo that must run several suites — one
# per container in a Docker-first stack, one per workspace in a monorepo —
# expresses that here instead of being forced into one expression. A block MUST
# return non-zero if ANY step fails: join steps with `&&`, or end each with
# `|| return 1`.
run_build() {
  {build_command}
}
# Pipeline-only gate: wrapped in a function so a no-state-file push can skip it
# with a single-line guard while the secret scan above still ran.
gate_build_section() {
  BUILD_OUTPUT=$(run_build 2>&1)
  if [ $? -ne 0 ]; then
    {
      echo "BLOCKED: Build fails"
      # Show why. A gate that blocks without printing the failure gets disabled.
      printf '%s\n' "$BUILD_OUTPUT" | tail -20
    } >&2
    exit 2
  fi
}
if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" != "yes" ]; then gate_build_section; fi

# Run lint check
run_lint() {
  {lint_command}
}
gate_lint_section() {
  LINT_OUTPUT=$(run_lint 2>&1)
  if [ $? -ne 0 ]; then
    {
      echo "BLOCKED: Lint fails"
      printf '%s\n' "$LINT_OUTPUT" | tail -20
    } >&2
    exit 2
  fi
}
if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" != "yes" ]; then gate_lint_section; fi

# Run tests and check count. Runners word their counts differently —
# jest/pytest/cargo "N passed", mocha "N passing", rspec "N examples",
# go prints per-package "ok" lines with no aggregate count at all.
# run_tests is defined INSIDE this block on purpose: migrate-v0.9.1-to-v0.9.2.sh
# re-splices the span from `# Run tests and check count` to `echo "All gates
# passed`, so the definition must travel with its caller.
run_tests() {
  {test_command}
}
gate_tests_section() {
  TEST_OUTPUT=$(run_tests 2>&1)
  TEST_EXIT=$?

  if [ $TEST_EXIT -ne 0 ]; then
    {
      echo "BLOCKED: Tests fail"
      printf '%s\n' "$TEST_OUTPUT" | tail -20
    } >&2
    exit 2
  fi

  # LAST count match, not first — a runner printing an intermediate "N tests"
  # progress line before its summary must not shadow the final total.
  TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ (passed|passing|tests|examples|specs)' | grep -oE '[0-9]+' | tail -1)
  if [ -z "$TEST_COUNT" ]; then
    _go_ok=$(echo "$TEST_OUTPUT" | grep -cE '^ok[[:space:]]')
    [ "$_go_ok" -gt 0 ] 2>/dev/null && TEST_COUNT=$_go_ok
  fi

  if [ -z "$TEST_COUNT" ]; then
    # A passing suite whose output format we cannot parse must not hard-block
    # the push — that is a false BLOCKED on mocha/rspec/go-shaped output, and a
    # blocking gate that cries wolf gets disabled. Exit code stays the gate.
    {
      echo "WARNING: could not parse a test count from the runner output (unrecognized format)."
      echo "         Exit code 0 accepted; the total_tests>0 check was skipped this push."
    } >&2
  elif [ "$TEST_COUNT" -eq 0 ]; then
    echo "BLOCKED: No tests found (total_tests must be > 0)" >&2
    exit 2
  fi
}
if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" != "yes" ]; then gate_tests_section; fi

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
  # Same count-parse as gate_tests_section (kept in lockstep): LAST match.
  TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ (passed|passing|tests|examples|specs)' | grep -oE '[0-9]+' | tail -1)
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

echo "All gates passed. Push allowed."
exit 0
