#!/bin/bash
# Reads hook input JSON from stdin, extracts file_path, runs boundary check
INPUT=$(cat)

# PYBIN probe: prefer python3, fall back to python. Post-edit is advisory (not
# a gate), so python absence exits 0 — no fail-closed here.
PYBIN=""
command -v python3 >/dev/null 2>&1 && PYBIN=python3
[ -z "$PYBIN" ] && command -v python >/dev/null 2>&1 && PYBIN=python
[ -z "$PYBIN" ] && exit 0

FILE_PATH=$(echo "$INPUT" | "$PYBIN" -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
  exec bash "$CLAUDE_PROJECT_DIR/espalier/hooks/check-layer-boundaries.sh" "$FILE_PATH"
fi
exit 0
