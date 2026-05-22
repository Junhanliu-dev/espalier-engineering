#!/bin/bash
# Migrate an Espalier v0.5.0 / v0.5.1 / v0.5.2 target repo to v0.5.3.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.5.3 adds an "Editing Discipline" section to the coder sub-agent
# (espalier/agents/harness-coder.md): it forbids the coder from editing files
# by shelling out to python3/sed/awk heredocs, which bypass the
# post-edit-wrapper.sh boundary hook and leave no reviewable diff.
#
# harness-coder.md is written per-project at /espalier-init time, so a plugin
# update never reaches an existing install — this script does.
#
# Usage: bash migrate-v0.5.2-to-v0.5.3.sh [--dry-run] [--yes]

set -u

DRY_RUN=no
SKIP_PROMPT=no
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=yes ;;
    --yes)     SKIP_PROMPT=yes ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.5.3] $*"; }

AGENT="espalier/agents/harness-coder.md"
MARKER="## Editing Discipline"

# --- Preflight --------------------------------------------------------------
if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: pre-v0.4 install detected (harness/ directory)." >&2
  echo "Run /espalier-migrate first to apply the v0.1->v0.5 chain, then re-run." >&2
  exit 1
fi
if [ ! -f "$AGENT" ]; then
  echo "ERROR: $AGENT not found — run this from the target project root." >&2
  exit 1
fi

# --- Idempotency ------------------------------------------------------------
if grep -qF "$MARKER" "$AGENT"; then
  log "$AGENT already has the Editing Discipline section — nothing to do."
  exit 0
fi

# --- The section to append --------------------------------------------------
emit_section() {
cat << 'EOF'

## Editing Discipline

Modify files with the `Edit` tool (exact-string replacement); create new files
with `Write`. NEVER edit a file by shelling out — no `python3` / `sed` / `awk`
heredocs that read a file, splice it by string offset, and write it back.

Shell-splicing is banned because it:
- bypasses the `post-edit-wrapper.sh` PostToolUse hook, so the layer-boundary
  check never runs on the change;
- leaves no reviewable diff for the reviewer agent — just an opaque file write;
- relies on brittle literal offsets (`str.index`) that silently corrupt the
  file when whitespace or surrounding code shifts.

For a structural change `Edit` cannot express cleanly, use a real codemod for
the language (e.g. ts-morph / jscodeshift for TS/JS) — not a hand-rolled
string splice.
EOF
}

if [ "$DRY_RUN" = "yes" ]; then
  log "[dry-run] would append the Editing Discipline section to $AGENT:"
  emit_section | sed 's/^/  | /'
  exit 0
fi

# --- Confirm ----------------------------------------------------------------
if [ "$SKIP_PROMPT" != "yes" ]; then
  ANS=""
  printf 'Append the Editing Discipline section to %s? [y/N] ' "$AGENT"
  read -r ANS || true
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "Aborted — nothing changed."; exit 0 ;;
  esac
fi

# --- Apply ------------------------------------------------------------------
# Ensure a trailing newline so the appended heading is not glued to the last line.
if [ -n "$(tail -c1 "$AGENT" 2>/dev/null)" ]; then
  echo >> "$AGENT"
fi
emit_section >> "$AGENT"
log "Appended the Editing Discipline section to $AGENT"

# --- Verify -----------------------------------------------------------------
if grep -qF "$MARKER" "$AGENT" && grep -qF "post-edit-wrapper.sh" "$AGENT"; then
  log "Verification: 1/1 check passed"
  exit 0
else
  echo "ERROR: verification failed — '$MARKER' not found in $AGENT after append." >&2
  exit 1
fi
