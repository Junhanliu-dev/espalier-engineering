#!/bin/bash
# Pre-push quality gate
# Blocks git push unless all conditions are met.
#
# Runs from the repo root: the wrapper cd's here, but cd defensively too so a
# direct invocation from a subdir still resolves the relative espalier/ paths
# below (a wrong cwd would make every `-f` test miss and fail OPEN).
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$_ROOT" ] && cd "$_ROOT" || true

# Doctor-cadence reminder — non-blocking, printed before any gate logic so it
# fires on every push regardless of gate outcome (the gate has early-exit
# paths). Never affects the exit code.
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
  if grep -qE '^- Status:[[:space:]]*(COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE)\b' "$_f" 2>/dev/null; then
    continue   # terminal — finished work never gates a later push
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

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "WARNING: No in-flight Espalier change found. Pushing without pipeline tracking."
  exit 0  # Allow but warn
fi

if [ "$ACTIVE_COUNT" -gt 1 ]; then
  echo "WARNING: $ACTIVE_COUNT in-flight changes found; gating the most recent: $STATE_FILE"
  echo "         Not checked:$OTHER_ACTIVE"
  echo "         If this push belongs to one of those, complete or abort the newer change first."
fi

# Check pipeline stage (must be ≥ 7). Take the FIRST match's first integer —
# `grep -oE '[0-9]+'` across multiple matching lines would concatenate digits.
CURRENT_STAGE=$(grep "Current Stage:" "$STATE_FILE" | head -1 | grep -oE '[0-9]+' | head -1)
if [ -n "$CURRENT_STAGE" ] && [ "$CURRENT_STAGE" -lt 7 ]; then
  echo "BLOCKED: Pipeline is at Stage $CURRENT_STAGE (need ≥ 7 for push)"
  echo "Complete code review and tests before pushing."
  exit 1
fi

# Review-certificate check — the code being pushed must match what the last review
# (Stage 4 code / Stage 6 test) actually saw. Reviewed-Diff is a content fingerprint
# of the source diff (espalier/ bookkeeping excluded), anchored to the Base-Ref
# recorded at Stage 3. A code change after review changes the fingerprint and blocks
# the push until a fresh review re-certifies the current diff. This is what makes the
# coder→reviewer→coder loop fail closed: a fix that skipped re-review cannot ship.
REVIEWED=$(grep "Reviewed-Diff:" "$STATE_FILE" | tail -1 | sed 's/.*Reviewed-Diff:[[:space:]]*//' | tr -d '[:space:]')
BASE_REF=$(grep "Base-Ref:" "$STATE_FILE" | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
if [ -n "$REVIEWED" ] && [ -n "$BASE_REF" ]; then
  CURRENT=$(git diff "$BASE_REF" -- . ':(exclude)espalier/' | git hash-object --stdin)
  if [ "$CURRENT" != "$REVIEWED" ]; then
    echo "BLOCKED: Source changed after its last review (Reviewed-Diff mismatch)."
    echo "  reviewed fingerprint: $REVIEWED"
    echo "  current  fingerprint: $CURRENT"
    echo "Re-run code review on the current diff (Stage 4) before pushing."
    exit 1
  fi
else
  echo "WARNING: No review certificate (Base-Ref/Reviewed-Diff) in $STATE_FILE —"
  echo "         legacy or pre-review change. Skipping the re-review check."
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
  echo "WARNING: cannot determine a push range (no Base-Ref, upstream, or prior commit) — secret scan skipped."
fi

if [ -n "$SEC_RANGE" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks detect --no-banner --redact --log-opts="$SEC_RANGE" >/dev/null 2>&1; then
      echo "BLOCKED: gitleaks found a potential secret in the pushed diff."
      echo "  Inspect with: gitleaks detect --log-opts=\"$SEC_RANGE\" -v"
      exit 1
    fi
  else
    # Fallback: high-signal pattern grep over the ADDED lines of the pushed diff.
    ADDED=$(git diff "$SEC_RANGE" -- . ':(exclude)espalier/' 2>/dev/null | grep '^+' | grep -v '^+++')
    if printf '%s\n' "$ADDED" | grep -qiE '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Za-z ]*PRIVATE KEY-----|(secret|api[_-]?key|apikey|access[_-]?token|password|passwd|private[_-]?key)[[:space:]]*[:=][[:space:]]*.{0,3}[A-Za-z0-9/+_-]{16,})'; then
      echo "BLOCKED: a possible hard-coded secret was added in this push."
      echo "  Matched an AWS key / private key / long api_key=… assignment."
      echo "  Move it to config/env and re-push (install 'gitleaks' for higher fidelity)."
      exit 1
    fi
  fi
fi

# Dependency audit — WARN only, per available tool for the detected stack. Wrapped
# in a timeout when available so a slow / offline advisory fetch can't hang the
# push; a nonzero exit may mean vulnerabilities OR a tool/network error (never blocks).
command -v timeout >/dev/null 2>&1 && _to="timeout 45" || _to=""
if   [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  $_to npm audit --omit=dev --audit-level=high >/dev/null 2>&1 || echo "WARNING: 'npm audit' flagged high-severity advisories or errored (non-blocking)."
elif { [ -f pyproject.toml ] || [ -f requirements.txt ]; } && command -v pip-audit >/dev/null 2>&1; then
  $_to pip-audit >/dev/null 2>&1 || echo "WARNING: 'pip-audit' flagged vulnerable dependencies or errored (non-blocking)."
elif [ -f go.mod ] && command -v govulncheck >/dev/null 2>&1; then
  $_to govulncheck ./... >/dev/null 2>&1 || echo "WARNING: 'govulncheck' flagged vulnerabilities or errored (non-blocking)."
elif [ -f Cargo.toml ] && command -v cargo-audit >/dev/null 2>&1; then
  $_to cargo audit >/dev/null 2>&1 || echo "WARNING: 'cargo audit' flagged vulnerable crates or errored (non-blocking)."
fi

# The three {command} placeholders below were substituted from
# DISCOVERY.ci_checks at init. A kind the repo did not have (null) was
# substituted as a clean no-op for build/lint (`true  # none discovered`) or a
# fail-closed, actionable stub for test — never an invented command. Refresh
# via /espalier-prune when the project gains one.

# Run build check
{build_command} 2>/dev/null
if [ $? -ne 0 ]; then
  echo "BLOCKED: Build fails"
  exit 1
fi

# Run lint check
{lint_command} 2>/dev/null
if [ $? -ne 0 ]; then
  echo "BLOCKED: Lint fails"
  exit 1
fi

# Run tests and check count. Runners word their counts differently —
# jest/pytest/cargo "N passed", mocha "N passing", rspec "N examples",
# go prints per-package "ok" lines with no aggregate count at all.
TEST_OUTPUT=$({test_command} 2>&1)
TEST_EXIT=$?

if [ $TEST_EXIT -ne 0 ]; then
  echo "BLOCKED: Tests fail"
  exit 1
fi

TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ (passed|passing|tests|examples|specs)' | grep -oE '[0-9]+' | head -1)
if [ -z "$TEST_COUNT" ]; then
  _go_ok=$(echo "$TEST_OUTPUT" | grep -cE '^ok[[:space:]]')
  [ "$_go_ok" -gt 0 ] 2>/dev/null && TEST_COUNT=$_go_ok
fi

if [ -z "$TEST_COUNT" ]; then
  # A passing suite whose output format we cannot parse must not hard-block
  # the push — that is a false BLOCKED on mocha/rspec/go-shaped output, and a
  # blocking gate that cries wolf gets disabled. Exit code stays the gate.
  echo "WARNING: could not parse a test count from the runner output (unrecognized format)."
  echo "         Exit code 0 accepted; the total_tests>0 check was skipped this push."
elif [ "$TEST_COUNT" -eq 0 ]; then
  echo "BLOCKED: No tests found (total_tests must be > 0)"
  exit 1
fi

echo "All gates passed. Push allowed."
exit 0
