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
    exec bash "$CLAUDE_PROJECT_DIR/harness/hooks/pre-push-gate.sh"
    ;;
esac

exit 0
