#!/bin/bash
# Migrate an Espalier v0.8.0 target repo to v0.8.1.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.8.1 adds change-impact / runtime-surface guidance to the two sub-agents:
#   - espalier/agents/harness-coder.md gains a "## Change Impact Analysis"
#     section: before coding, enumerate every surface that produces/reads/
#     validates/persists the thing being changed (admin UIs, API validation,
#     client forms, persisted data, other callers) — not just the happy path. A
#     value that becomes system-derived must stop being user-required everywhere;
#     when mirroring a working element, copy its WHOLE config.
#   - espalier/agents/harness-reviewer.md gains a "## Runtime-Surface Review"
#     section: never approve a change verified only on the programmatic path; a
#     leftover "required" constraint on a now-derived value that blocks a UI/
#     client before the server hook runs is a P1 defect.
#
# Both agent files are written per-project at /espalier-init time, so a plugin
# update never reaches an existing install — this script does.
#
# Usage: bash migrate-v0.8-to-v0.8.1.sh [--dry-run] [--yes]

set -u

DRY_RUN=no
SKIP_PROMPT=no
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=yes ;;
    --yes)     SKIP_PROMPT=yes ;;
    # --plugin-dir is accepted but unused (this patch appends inline text, it
    # does not copy from the plugin) — kept for a uniform call signature with the
    # other migration scripts the espalier-migrate skill invokes.
    --plugin-dir=*) : ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.8.1] $*"; }

CODER="espalier/agents/harness-coder.md"
REVIEWER="espalier/agents/harness-reviewer.md"
CODER_MARKER="## Change Impact Analysis"
REVIEWER_MARKER="## Runtime-Surface Review"

# --- Preflight --------------------------------------------------------------
if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: pre-v0.4 install detected (harness/ directory)." >&2
  echo "Run /espalier-migrate first to apply the v0.1->v0.8 chain, then re-run." >&2
  exit 1
fi
if [ ! -f "$CODER" ]; then
  echo "ERROR: $CODER not found — run this from the target project root." >&2
  exit 1
fi
if [ ! -f "$REVIEWER" ]; then
  echo "ERROR: $REVIEWER not found — run this from the target project root." >&2
  exit 1
fi

# --- The sections to append -------------------------------------------------
emit_coder_section() {
cat << 'EOF'

## Change Impact Analysis (do this BEFORE writing code)

Most avoidable rework comes from changing a value's *happy path* while ignoring
the other surfaces that read or constrain the same thing. Before coding, map the
blast radius of the change:

1. **Enumerate every surface that produces, reads, validates, or persists what
   you are changing — not just the one call path in front of you.** Depending on
   the stack, these include: admin / CRUD / back-office UIs, API request
   validation, client-side forms and their validators, data already persisted in
   storage, event / queue consumers, and other callers of the function or field.
   The layer spec and `engineering-structure.md` tell you which surfaces exist in
   THIS project — let them, not assumption, define the list.
2. **A value that becomes system-derived must stop being user-required —
   everywhere.** When you make a field auto-generated, defaulted, or computed, any
   "required" / "must not be empty" constraint that used to force a human to
   supply it now fights the generator. Server-side generation can satisfy the API
   path while a UI- or client-level required check still blocks the user *before*
   your code runs. Relax the constraint on every surface, not just the one you
   exercised.
3. **When you mirror an existing working element, copy its WHOLE configuration,
   not one attribute.** If a sibling field / route / handler already does what you
   want and works, replicate its full shape — validation flags, visibility / UI
   settings, access rules, everything — not just the one hook or line you came
   for. Copying half a working pattern ships half a working feature.
4. **Record the blast radius.** Note any non-obvious surface you touched (or
   deliberately did not) in coding-report.md "Notes", so the reviewer can confirm
   it rather than re-derive it.

The goal is to surface a cross-surface impact at coding time, not discover it as
a fix round after the change ships.
EOF
}

emit_reviewer_section() {
cat << 'EOF'

## Runtime-Surface Review

Do NOT approve a change you have verified only on the programmatic / happy path.
For the code under review, ask which OTHER surfaces exercise it — admin / CRUD
UIs, API request validation, client-side forms, persisted data, event consumers,
other callers — and check the change against each that applies:

- **A value that became system-derived (auto-generated / defaulted / computed)
  must no longer be user-required on ANY surface.** A leftover "required" /
  "not-empty" constraint that blocks a UI or client *before* the server-side hook
  runs is a real defect, not a nitpick — flag it at least **P1**.
- **A change that mirrors an existing working element should copy that element's
  WHOLE configuration.** Verify nothing — validation, visibility, access — was
  left half-applied versus the element it was modelled on.
- **If you cannot tell whether a surface is affected, say so in the findings**
  rather than assuming the happy path is the only path. An unchecked surface is a
  reported gap, not a silent pass.

This catches the class of bug where server-side logic is correct but a UI- or
client-level constraint still rejects the user — the kind that otherwise escapes
review and returns as a fix round.
EOF
}

# --- Idempotency check (per file) -------------------------------------------
CODER_DONE=no
REVIEWER_DONE=no
grep -qF "$CODER_MARKER" "$CODER" && CODER_DONE=yes
grep -qF "$REVIEWER_MARKER" "$REVIEWER" && REVIEWER_DONE=yes

if [ "$CODER_DONE" = yes ] && [ "$REVIEWER_DONE" = yes ]; then
  log "Both agents already have the v0.8.1 sections — nothing to do."
  exit 0
fi

# --- Dry run ----------------------------------------------------------------
if [ "$DRY_RUN" = "yes" ]; then
  if [ "$CODER_DONE" = no ]; then
    log "[dry-run] would append the Change Impact Analysis section to $CODER:"
    emit_coder_section | sed 's/^/  | /'
  else
    log "[dry-run] $CODER already patched — skip."
  fi
  if [ "$REVIEWER_DONE" = no ]; then
    log "[dry-run] would append the Runtime-Surface Review section to $REVIEWER:"
    emit_reviewer_section | sed 's/^/  | /'
  else
    log "[dry-run] $REVIEWER already patched — skip."
  fi
  exit 0
fi

# --- Confirm ----------------------------------------------------------------
if [ "$SKIP_PROMPT" != "yes" ]; then
  ANS=""
  printf 'Append the v0.8.1 impact-analysis sections to the two agent files? [y/N] '
  read -r ANS || true
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "Aborted — nothing changed."; exit 0 ;;
  esac
fi

# --- Apply ------------------------------------------------------------------
# append_section <file> <emit-fn> — ensure a trailing newline so the appended
# heading is not glued to the file's last line.
append_section() {
  _file="$1"; _emit="$2"
  if [ -n "$(tail -c1 "$_file" 2>/dev/null)" ]; then
    echo >> "$_file"
  fi
  "$_emit" >> "$_file"
}

if [ "$CODER_DONE" = no ]; then
  append_section "$CODER" emit_coder_section
  log "Appended the Change Impact Analysis section to $CODER"
fi
if [ "$REVIEWER_DONE" = no ]; then
  append_section "$REVIEWER" emit_reviewer_section
  log "Appended the Runtime-Surface Review section to $REVIEWER"
fi

# --- Verify -----------------------------------------------------------------
PASS=0
FAIL=0
if grep -qF "$CODER_MARKER" "$CODER"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "ERROR: '$CODER_MARKER' missing from $CODER" >&2; fi
if grep -qF "$REVIEWER_MARKER" "$REVIEWER"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "ERROR: '$REVIEWER_MARKER' missing from $REVIEWER" >&2; fi
log "Verification: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
