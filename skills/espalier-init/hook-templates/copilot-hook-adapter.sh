#!/bin/bash
# Copilot → espalier hook adapter.
#
# GitHub Copilot hooks (CLI + cloud agent, .github/hooks/*.json) send a
# camelCase payload — {"toolName": "bash", "toolArgs": {...}} — while the two
# shared espalier wrappers speak the Claude Code / Codex shape
# ({"tool_name": ..., "tool_input": {...}}). This shim translates and
# dispatches, so the SAME wrapper scripts serve all three platforms.
#
# Usage (from .github/hooks/espalier-gates.json):
#   bash espalier/hooks/copilot-hook-adapter.sh pre-push-gate-wrapper.sh
#   bash espalier/hooks/copilot-hook-adapter.sh post-edit-wrapper.sh
#
# Exit code passes through untouched. Copilot preToolUse treats exit 2 — and
# any other non-timeout non-zero — as DENY (fail-closed), which matches the
# wrappers' own blocking contract; postToolUse output is advisory feedback.

WRAPPER_NAME="$1"
DIR=$(cd "$(dirname "$0")" && pwd)
WRAPPER="$DIR/$WRAPPER_NAME"
[ -f "$WRAPPER" ] || exit 0   # espalier hooks not installed here — never brick the session

INPUT=$(cat)

PYBIN=""
command -v python3 >/dev/null 2>&1 && PYBIN=python3
[ -z "$PYBIN" ] && command -v python >/dev/null 2>&1 && PYBIN=python

if [ -z "$PYBIN" ]; then
  # No python: pass the RAW payload through. The push-gate wrapper's fast path
  # greps the whole JSON for git+push tokens (camelCase or not), and its own
  # python probe then fails closed only for a suspected push; the post-edit
  # wrapper exits 0 without python (advisory). No translation needed to keep
  # both contracts intact.
  printf '%s' "$INPUT" | bash "$WRAPPER"
  exit $?
fi

TRANSLATED=$(printf '%s' "$INPUT" | "$PYBIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
args = d.get('toolArgs') or d.get('tool_input') or {}
if isinstance(args, dict):
    # Normalise the edited-file field name variants to file_path.
    if 'file_path' not in args:
        for k in ('path', 'file', 'filePath', 'fileName'):
            if args.get(k):
                args['file_path'] = args[k]
                break
out = {'tool_name': d.get('toolName') or d.get('tool_name') or '', 'tool_input': args}
print(json.dumps(out))
" 2>/dev/null)

if [ -z "$TRANSLATED" ]; then
  # Unparseable payload: same rationale as the no-python branch — hand the raw
  # bytes to the wrapper and let its own fail-open/fail-closed logic decide.
  printf '%s' "$INPUT" | bash "$WRAPPER"
  exit $?
fi

printf '%s' "$TRANSLATED" | bash "$WRAPPER"
exit $?
