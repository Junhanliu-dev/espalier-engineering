#!/bin/bash
# map-guard.sh — PreToolUse guard for /espalier-map sessions (plan, don't do).
#
# While a map session is active (espalier/maps/.active-session exists and is
# fresh), Write/Edit calls outside espalier/maps/ are BLOCKED: exit 2 with the
# reason on stderr (the only exit code PreToolUse blocks on — same contract as
# pre-push-gate). No marker, or a stale one → exit 0 fast, zero overhead on
# every non-map session.
#
# Marker format (written by the espalier-map skill at session start, removed
# at session end):
#   map: <slug>
#   session_started: <ISO>
#   allow: <path-prefix>        # zero or more — user-approved task-ticket
#   allow: <path-prefix>        # write windows, repo-root-relative
#
# Staleness: a marker whose mtime is older than 12h is treated as INACTIVE
# (a crashed session must never brick later work). The skill still removes it
# on every exit path; this is the backstop.
#
# Platform-neutral (Claude Code + Codex hook JSON; Copilot via
# copilot-hook-adapter.sh): file paths come from tool_input.file_path, or from
# "*** Add/Update File:" lines of an apply_patch body.

INPUT=$(cat)

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0

MARKER="$ROOT/espalier/maps/.active-session"
[ -f "$MARKER" ] || exit 0

# Stale marker → inactive. BSD vs GNU stat.
if [ "$(uname)" = "Darwin" ]; then
  M_TS=$(stat -f %m "$MARKER" 2>/dev/null)
else
  M_TS=$(stat -c %Y "$MARKER" 2>/dev/null)
fi
NOW=$(date -u +%s)
if [ -n "$M_TS" ] && [ $(( NOW - M_TS )) -gt 43200 ]; then
  exit 0
fi

# Guard is a discipline gate, not a security boundary: no python → advisory
# no-op (same policy as post-edit-wrapper).
PYBIN=""
command -v python3 >/dev/null 2>&1 && PYBIN=python3
[ -z "$PYBIN" ] && command -v python >/dev/null 2>&1 && PYBIN=python
[ -z "$PYBIN" ] && exit 0

FILE_PATHS=$(printf '%s' "$INPUT" | "$PYBIN" -c "
import sys, json, re
try:
    ti = json.load(sys.stdin).get('tool_input', {}) or {}
except Exception:
    sys.exit(0)
fp = ti.get('file_path', '')
if fp:
    print(fp)
else:
    patch = ti.get('command') or ti.get('input') or ''
    if isinstance(patch, list):
        patch = ' '.join(str(x) for x in patch)
    for m in re.findall(r'^\*\*\* (?:Add|Update) File: (.+)$', str(patch), re.M):
        print(m.strip())
" 2>/dev/null)

[ -z "$FILE_PATHS" ] && exit 0

# Allowed prefixes: the map dir itself + every user-approved `allow:` line.
ALLOW_PREFIXES="espalier/maps/"
while IFS= read -r line; do
  case "$line" in
    allow:*)
      p=$(printf '%s' "${line#allow:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # Reject escapes: absolute or parent-traversal prefixes are ignored.
      case "$p" in
        ""|/*|*..*) ;;
        *) ALLOW_PREFIXES="$ALLOW_PREFIXES
$p" ;;
      esac
      ;;
  esac
done < "$MARKER"

MAP_SLUG=$(grep '^map:' "$MARKER" | head -1 | sed 's/^map:[[:space:]]*//')

RC=0
while IFS= read -r FILE_PATH; do
  [ -z "$FILE_PATH" ] && continue
  # Normalize to repo-root-relative; writes OUTSIDE the repo are out of scope.
  case "$FILE_PATH" in
    "$ROOT"/*) REL="${FILE_PATH#"$ROOT"/}" ;;
    /*)        continue ;;
    *)         REL="$FILE_PATH" ;;
  esac
  ALLOWED=no
  while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    case "$REL" in
      "$prefix"*) ALLOWED=yes; break ;;
    esac
  done << EOF
$ALLOW_PREFIXES
EOF
  if [ "$ALLOWED" = "no" ]; then
    {
      echo "BLOCKED by map-guard: a map session is active (map: ${MAP_SLUG:-unknown}) — plan, don't do."
      echo "  attempted write: $REL"
      echo "  Map sessions write only under espalier/maps/. To write elsewhere:"
      echo "  - finish or abort the session (the espalier-map skill removes espalier/maps/.active-session), or"
      echo "  - for an approved task-ticket window, append 'allow: <path-prefix>' to espalier/maps/.active-session (user approval first)."
    } >&2
    RC=2
  fi
done << EOF
$FILE_PATHS
EOF
exit $RC
