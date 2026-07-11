#!/bin/bash
# Reads PreToolUse hook input from stdin. If the Bash command being run is a
# `git push`, dispatch to pre-push-gate.sh. Otherwise exit 0 (don't block).
#
# Without this wrapper, pre-push-gate.sh would fire for EVERY Bash command —
# blocking everything. The PreToolUse matcher in settings.json catches all
# Bash invocations; this wrapper narrows the scope to push operations only.
#
# Exit-code contract: blocking paths exit with code 2 and the reason on stderr
# (Claude Code PreToolUse semantics — exit code 1 would NOT block).

INPUT=$(cat)

# Documented escape hatch.
[ -n "${ESPALIER_SKIP_GATE:-}" ] && exit 0

# Fast path: if the raw hook JSON doesn't even contain "git" and "push",
# this is not a push — allow without needing python at all.
if ! printf '%s' "$INPUT" | grep -q 'git' || ! printf '%s' "$INPUT" | grep -q 'push'; then
  exit 0
fi

PYBIN=""
command -v python3 >/dev/null 2>&1 && PYBIN=python3
[ -z "$PYBIN" ] && command -v python >/dev/null 2>&1 && PYBIN=python
if [ -z "$PYBIN" ]; then
  # Cannot parse the command reliably and it plausibly contains a push: fail CLOSED.
  echo "BLOCKED: espalier push gate cannot run — python3 not found (needed to parse the hook input). Install python3, or bypass once with ESPALIER_SKIP_GATE=1." >&2
  exit 2
fi
COMMAND=$(printf '%s' "$INPUT" | "$PYBIN" -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))") \
  || { echo "BLOCKED: espalier push gate could not parse hook input JSON." >&2; exit 2; }

# Match a real `git push` invocation anywhere in the (possibly multi-line,
# possibly `git -C dir push`) command. Strip quoted SPANS first (not whole lines)
# so `echo "git push"` doesn't trigger but `git commit -m "git push docs" && git push`
# still does.
STRIPPED=$(printf '%s\n' "$COMMAND" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
if printf '%s\n' "$STRIPPED" \
   | grep -qE '(^|[;&|[:space:]])git([[:space:]]+(-C[[:space:]]*[^[:space:]]+|--?[[:alnum:]][^[:space:]]*))*[[:space:]]+push([[:space:]]|$)'; then
  # Run the gate from the repo root so its relative espalier/ paths resolve
  # regardless of the cwd the push was invoked from. Prefer the git toplevel;
  # fall back to CLAUDE_PROJECT_DIR. A push from a subdir must NEVER silently
  # skip the gate (that would fail OPEN — the exact hole this closes).
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
  cd "$ROOT" || { echo "BLOCKED: cannot cd to repo root ($ROOT) to run the push gate." >&2; exit 2; }
  exec bash "$ROOT/espalier/hooks/pre-push-gate.sh"
fi

exit 0
