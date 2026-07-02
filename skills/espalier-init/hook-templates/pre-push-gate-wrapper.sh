#!/bin/bash
# Reads PreToolUse hook input from stdin. If the Bash command being run is a
# `git push`, dispatch to pre-push-gate.sh. Otherwise exit 0 (don't block).
#
# Without this wrapper, pre-push-gate.sh would fire for EVERY Bash command —
# blocking everything. The PreToolUse matcher in settings.json catches all
# Bash invocations; this wrapper narrows the scope to push operations only.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Match `git push`, `git push origin`, `git push --force`, etc.
# Don't match unrelated mentions like `echo 'git push'` or comments.
case "$COMMAND" in
  "git push"|"git push "*|*" git push"|*" git push "*)
    # Run the gate from the repo root so its relative espalier/ paths resolve
    # regardless of the cwd the push was invoked from. Prefer the git toplevel;
    # fall back to CLAUDE_PROJECT_DIR. A push from a subdir must NEVER silently
    # skip the gate (that would fail OPEN — the exact hole this closes).
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
    cd "$ROOT" || { echo "BLOCKED: cannot cd to repo root ($ROOT) to run the push gate." >&2; exit 1; }
    exec bash "$ROOT/espalier/hooks/pre-push-gate.sh"
    ;;
esac

exit 0
