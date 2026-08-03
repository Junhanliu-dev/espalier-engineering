#!/bin/bash
# Reads hook input JSON from stdin, extracts the edited file path(s), runs the
# layer-boundary check on each.
#
# Platform-neutral (Claude Code + Codex — both emit the same hook JSON shape):
#   - Claude Code Write|Edit  → tool_input.file_path (single path)
#   - Codex apply_patch       → tool_input.command (or .input) holds the patch
#     body; changed paths appear as "*** Add File:" / "*** Update File:" lines
INPUT=$(cat)

# PYBIN probe: prefer python3, fall back to python. Post-edit is advisory (not
# a gate), so python absence exits 0 — no fail-closed here.
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

# Hook subprocess cwd is not guaranteed to be the repo root on either platform.
# Claude Code sets CLAUDE_PROJECT_DIR; Codex does not — fall back to git.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0
[ -f "$ROOT/espalier/hooks/check-layer-boundaries.sh" ] || exit 0

# Check every edited file; exit 2 if ANY violates (each check writes its own
# reason to stderr — PostToolUse feedback semantics, same on both platforms).
RC=0
while IFS= read -r FILE_PATH; do
  [ -z "$FILE_PATH" ] && continue
  case "$FILE_PATH" in
    /*) ABS="$FILE_PATH" ;;
    *)  ABS="$ROOT/$FILE_PATH" ;;
  esac
  [ -f "$ABS" ] || continue
  bash "$ROOT/espalier/hooks/check-layer-boundaries.sh" "$ABS" || RC=2
done << EOF
$FILE_PATHS
EOF
exit $RC
