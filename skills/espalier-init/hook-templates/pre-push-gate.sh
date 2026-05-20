#!/bin/bash
# Pre-push quality gate
# Blocks git push unless all conditions are met

# Doctor-cadence reminder — non-blocking, printed before any gate logic so it
# fires on every push regardless of gate outcome (the gate has early-exit
# paths). Never affects the exit code.
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  doctor_due && echo "Reminder: an /espalier-doctor drift scan is due."
fi

# Find the most-recently-modified pipeline-state.md across typed subdirs
# (espalier/changes/{type}/{slug}/pipeline-state.md — depth 3 from CHANGES_DIR).
CHANGES_DIR="espalier/changes"

# stat format differs between BSD (macOS) and GNU (Linux)
if [ "$(uname)" = "Darwin" ]; then
  STAT_ARGS=(-f '%m %N')
else
  STAT_ARGS=(-c '%Y %n')
fi

STATE_FILE=$(find "$CHANGES_DIR" -mindepth 3 -maxdepth 3 -name pipeline-state.md \
             -not -path "*/_template/*" \
             -exec stat "${STAT_ARGS[@]}" {} + 2>/dev/null \
             | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "WARNING: No Espalier change record found. Pushing without pipeline tracking."
  exit 0  # Allow but warn
fi

# Check pipeline stage (must be ≥ 7)
CURRENT_STAGE=$(grep "Current Stage:" "$STATE_FILE" | grep -oE '[0-9]+')
if [ -n "$CURRENT_STAGE" ] && [ "$CURRENT_STAGE" -lt 7 ]; then
  echo "BLOCKED: Pipeline is at Stage $CURRENT_STAGE (need ≥ 7 for push)"
  echo "Complete code review and tests before pushing."
  exit 1
fi

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

# Run tests and check count
TEST_OUTPUT=$({test_command} 2>&1)
TEST_EXIT=$?
TEST_COUNT=$(echo "$TEST_OUTPUT" | grep -oE '[0-9]+ (passed|tests)' | grep -oE '[0-9]+' | head -1)

if [ $TEST_EXIT -ne 0 ]; then
  echo "BLOCKED: Tests fail"
  exit 1
fi

if [ -z "$TEST_COUNT" ] || [ "$TEST_COUNT" -eq 0 ]; then
  echo "BLOCKED: No tests found (total_tests must be > 0)"
  exit 1
fi

echo "All gates passed. Push allowed."
exit 0
