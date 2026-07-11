#!/bin/bash
# Migrate a v0.10.0 Espalier install to v0.11.0.
#
# v0.11.0 is the hook exit-code release: Claude Code PreToolUse/PostToolUse
# hooks block ONLY on exit code 2 with the message on stderr — exit 1 + stdout
# is a silent no-op, so the v0.10.0 push gate never actually blocked a push.
# This migration:
#   1. espalier/hooks/pre-push-gate.sh — if template-shaped, rebuild it from the
#      v0.11.0 template, PRESERVING the three substituted command bodies
#      (run_build / run_lint / run_tests). If customised: leave untouched,
#      write an espalier/.migrations-skipped marker, print the manual contract.
#   2. espalier/hooks/pre-push-gate-wrapper.sh + post-edit-wrapper.sh — pure
#      copies; overwrite from templates (backups: <file>.pre-v0.11.bak).
#   3. espalier/hooks/check-layer-boundaries.sh — LLM-adapted; anchored sed
#      turns `exit 1` into `exit 2` and sends the LAYER VIOLATION echo to
#      stderr. Unrecognizable shape → marker + instructions.
#   4. espalier/agents/harness-reviewer.md / harness-security.md — append
#      `, Write` to the frontmatter tools: line (skip in inherit mode) and fix
#      the "no Write/Edit" sentence.
#   5. espalier/pipeline.md + the pure-copy pipeline skills (espalier,
#      espalier-fix, espalier-requirements, espalier-grill, espalier-prune,
#      espalier-doctor, espalier-ask, espalier-audit) — overwrite from
#      templates (backups: <file>.pre-v0.11.bak).
#   6. espalier/skills/espalier-review + espalier-security SKILL.md — copy the
#      new template and re-substitute {project} with the name recovered from
#      the installed file. Recovery failure → marker + manual instructions.
#   7. Verification (exit 1 on any failure).
#
# Usage:
#   bash migrate-v0.10.0-to-v0.11.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.10.0→v0.11.0] $*"; }
die() { echo "[migrate v0.10.0→v0.11.0] ERROR: $*" >&2; exit 1; }

# sed -i differs between BSD (macOS, needs '' arg) and GNU (Linux, no arg)
if [ "$(uname)" = "Darwin" ]; then
  SED_INPLACE=(sed -i '')
else
  SED_INPLACE=(sed -i)
fi

skip_marker() {  # $1 = marker line (without trailing text changes)
  if [ "$DRY_RUN" != yes ] && ! grep -qF "${1%%:*}:" espalier/.migrations-skipped 2>/dev/null; then
    echo "$1" >> espalier/.migrations-skipped
  fi
}

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
[ -d "$TPL/hook-templates" ] || die "plugin dir $PLUGIN_DIR has no skills/espalier-init/hook-templates."

GATE_TPL="$TPL/hook-templates/pre-push-gate.sh"
grep -qF 'PIPELINE_TRACKED' "$GATE_TPL" || \
  die "template at $PLUGIN_DIR is not v0.11.0 (gate template lacks PIPELINE_TRACKED). Update the plugin first."

# --- Idempotency: fully migrated already? ------------------------------------
# The gate marker is the v0.11 header comment — NOT `PIPELINE_TRACKED`: a gate
# chain-migrated by the v0.9.2/v0.10.0 span splices already carries
# PIPELINE_TRACKED from the new template's spans while its stage/cert/secret
# sections still exit 1. Only a full v0.11 rebuild writes the header.
V011_GATE_MARKER='Exit-code contract (Claude Code PreToolUse semantics)'
GATE="espalier/hooks/pre-push-gate.sh"
ALREADY=yes
{ [ -f "$GATE" ] && grep -qF "$V011_GATE_MARKER" "$GATE"; } || \
  grep -qF 'v0.11.0-gate:' espalier/.migrations-skipped 2>/dev/null || ALREADY=no
grep -qF 'Advance ONLY when EVERY record' espalier/skills/espalier/SKILL.md 2>/dev/null || ALREADY=no
if [ "$ALREADY" = yes ]; then
  log "already at v0.11.0 (gate carries the v0.11 exit-code header or a skip marker; espalier skill carries the verdict gate). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  log "  1. rebuild $GATE from the v0.11.0 template, preserving the run_build/run_lint/run_tests bodies (backup .pre-v0.11.bak)"
  log "  2. overwrite pre-push-gate-wrapper.sh + post-edit-wrapper.sh from templates (backups .pre-v0.11.bak)"
  log "  3. patch check-layer-boundaries.sh: exit 1 → exit 2, VIOLATION echo → stderr"
  log "  4. add Write to harness-reviewer/-security tools: lines (skip in inherit mode); fix the 'no Write/Edit' sentence"
  log "  5. overwrite pipeline.md + the 8 pure-copy pipeline skills from templates (backups .pre-v0.11.bak)"
  log "  6. refresh espalier-review/espalier-security SKILL.md with {project} re-substitution"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.11.0 migration (exit-2 hook contract + verdict-word gates)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- 1. Push gate -------------------------------------------------------------
GATE_DONE=no
if [ ! -f "$GATE" ]; then
  log "no $GATE — skipping the gate step (install incomplete?)"
elif grep -qF "$V011_GATE_MARKER" "$GATE"; then
  log "gate already v0.11-shaped — skipping."
  GATE_DONE=yes
else
  CUSTOMISED=no
  grep -qF 'run_build() {' "$GATE" || CUSTOMISED=yes
  grep -qF 'run_lint() {'  "$GATE" || CUSTOMISED=yes
  grep -qF 'run_tests() {' "$GATE" || CUSTOMISED=yes
  if [ "$CUSTOMISED" = yes ]; then
    echo
    echo "  This project's $GATE does not match the v0.10.0 template shape — it was"
    echo "  customised. Rewriting it automatically would destroy that. Leaving it"
    echo "  untouched. The v0.11.0 contract to port by hand:"
    echo "    - blocking paths must exit 2 with the message on stderr"
    echo "      (Claude Code PreToolUse semantics; exit 1 does NOT block)"
    echo "    - warnings also print to stderr (stdout is invisible in hook context)"
    echo "    - the secret scan must run even when no pipeline change is in flight"
    skip_marker "v0.11.0-gate: customised, manual port needed"
    log "gate left untouched (customised). Marker written to espalier/.migrations-skipped."
  else
    cp "$GATE" "$GATE.pre-v0.11.bak"
    log "backed up -> $GATE.pre-v0.11.bak"
    GATE="$GATE" GATE_TPL="$GATE_TPL" python3 <<'PY'
import os, re, sys

gate_p, tpl_p = os.environ["GATE"], os.environ["GATE_TPL"]
gate = open(gate_p, encoding="utf-8").read()
tpl  = open(tpl_p,  encoding="utf-8").read()

def body(func):
    # Function body = everything between `func() {` and the first column-0 `}`.
    m = re.search(r"(?ms)^%s\(\) \{\n(.*?)^\}" % re.escape(func), gate)
    if not m:
        sys.exit("ERROR: could not read the %s body from the installed gate" % func)
    return m.group(1).rstrip("\n")

out = tpl
for func, ph in (("run_build", "{build_command}"),
                 ("run_lint",  "{lint_command}"),
                 ("run_tests", "{test_command}")):
    b = body(func)
    line = "  " + ph
    if line not in out:
        sys.exit("ERROR: template missing placeholder line %r" % line)
    out = out.replace(line, b, 1)

for ph in ("{build_command}", "{lint_command}", "{test_command}"):
    if ph in out:
        sys.exit("ERROR: refusing to write an unsubstituted %s" % ph)

open(gate_p, "w", encoding="utf-8").write(out)
print("  gate rebuilt from the v0.11.0 template (commands preserved)")
PY
    rc=$?
    [ $rc -eq 0 ] || die "gate rebuild failed — restore from $GATE.pre-v0.11.bak"
    chmod +x "$GATE"
    GATE_DONE=yes
  fi
fi

# --- 2. Wrappers (pure copies) -------------------------------------------------
for w in pre-push-gate-wrapper.sh post-edit-wrapper.sh; do
  src="$TPL/hook-templates/$w"
  dst="espalier/hooks/$w"
  [ -f "$src" ] || die "template missing: $src"
  [ -f "$dst" ] && cp "$dst" "$dst.pre-v0.11.bak"
  cp "$src" "$dst"
  chmod +x "$dst"
  log "refreshed $dst (backup .pre-v0.11.bak)"
done

# --- 3. check-layer-boundaries.sh (LLM-adapted — anchored sed only) -----------
LB="espalier/hooks/check-layer-boundaries.sh"
if [ ! -f "$LB" ]; then
  log "no $LB — skipping (nothing wired to post-edit)."
elif ! grep -q 'exit 1' "$LB"; then
  log "$LB has no 'exit 1' — already exit-2 (or a no-op). Skipping."
elif grep -q 'LAYER VIOLATION' "$LB"; then
  cp "$LB" "$LB.pre-v0.11.bak"
  "${SED_INPLACE[@]}" -E 's/exit 1$/exit 2/' "$LB"
  # Send the violation headline to stderr (anchored on the marker text; skip
  # lines already redirected).
  "${SED_INPLACE[@]}" -E '/LAYER VIOLATION/ { /(>&2|>\&2)/! s/$/ >\&2/; }' "$LB"
  bash -n "$LB" || die "$LB no longer parses — restore from $LB.pre-v0.11.bak"
  log "patched $LB: exit 1 → exit 2, VIOLATION echo → stderr (backup .pre-v0.11.bak)"
else
  echo
  echo "  $LB carries 'exit 1' but not the LAYER VIOLATION marker — unrecognized"
  echo "  shape; not touching it. Port by hand: PostToolUse contract is violations"
  echo "  exit 2 with the message on stderr; exit 0 otherwise."
  skip_marker "v0.11.0-layer-hook: unrecognized shape, manual port needed"
fi

# --- 4. Agents: Write tool + prose fix -----------------------------------------
for a in harness-reviewer harness-security; do
  f="espalier/agents/$a.md"
  if [ ! -f "$f" ]; then
    log "no $f — skipping."
    continue
  fi
  if ! grep -q '^tools:' "$f"; then
    log "$a: inherit mode — no tools line, skipping"
  elif grep -q '^tools:.*Write' "$f"; then
    log "$a: tools line already carries Write — skipping."
  else
    "${SED_INPLACE[@]}" -E 's/^(tools:.*[^ ])[[:space:]]*$/\1, Write/' "$f"
    log "$a: appended Write to the tools: line"
  fi
  # Anchor-guarded prose fix (skip silently if the user removed the sentence).
  if grep -qF "you have no Write/Edit" "$f"; then
    "${SED_INPLACE[@]}" 's|that.s the coder.s job — you have no Write/Edit|that'"'"'s the coder'"'"'s job — your Write tool is for the record file ONLY|' "$f"
    log "$a: fixed the 'no Write/Edit' sentence"
  fi
done

# --- 5. pipeline.md + pure-copy pipeline skills --------------------------------
copy_with_backup() {  # src dst
  [ -f "$1" ] || die "template missing: $1"
  [ -f "$2" ] && cp "$2" "$2.pre-v0.11.bak"
  cp "$1" "$2"
}

copy_with_backup "$TPL/templates/pipeline.md" espalier/pipeline.md
log "refreshed espalier/pipeline.md (backup .pre-v0.11.bak)"

for s in espalier espalier-fix espalier-requirements espalier-grill \
         espalier-prune espalier-doctor espalier-ask espalier-audit; do
  mkdir -p "espalier/skills/$s"
  copy_with_backup "$TPL/templates/skills/$s.md" "espalier/skills/$s/SKILL.md"
done
log "refreshed the 8 pure-copy pipeline skills (backups .pre-v0.11.bak)"

# --- 6. espalier-review / espalier-security ({project} re-substitution) --------
resub_skill() {  # skill-name  recovery-regex-description
  local s="$1" f="espalier/skills/$1/SKILL.md" proj=""
  if [ ! -f "$f" ]; then
    log "no $f — skipping."
    return 0
  fi
  case "$s" in
    espalier-security)
      proj=$(sed -n 's/^# Security Audit — //p' "$f" | head -1) ;;
    espalier-review)
      proj=$(sed -n 's/.*Expert plan + code reviewer for \(.*\)\. Use in two spots.*/\1/p' "$f" | head -1) ;;
  esac
  if [ -z "$proj" ] || [ "$proj" = "{project}" ]; then
    echo "  Could not recover the project name from $f — not overwriting it."
    echo "  Port by hand: copy $TPL/templates/skills/$s.md over it and replace"
    echo "  every {project} with your project's name."
    skip_marker "v0.11.0-$s: project name unrecoverable, manual port needed"
    return 0
  fi
  cp "$f" "$f.pre-v0.11.bak"
  cp "$TPL/templates/skills/$s.md" "$f"
  PROJ="$proj" F="$f" python3 - <<'PY'
import os
f = os.environ["F"]
s = open(f, encoding="utf-8").read()
open(f, "w", encoding="utf-8").write(s.replace("{project}", os.environ["PROJ"]))
PY
  log "refreshed espalier/skills/$s/SKILL.md ({project} → $proj; backup .pre-v0.11.bak)"
}
resub_skill espalier-review
resub_skill espalier-security

# --- 7. Verification -----------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
if [ "$GATE_DONE" = yes ]; then
  check "gate parses clean (bash -n)"      "/bin/bash -n espalier/hooks/pre-push-gate.sh"
  check "gate has 10 'exit 2' sites"       "[ \"\$(grep -c 'exit 2' espalier/hooks/pre-push-gate.sh)\" = 10 ]"
  check "gate has zero 'exit 1' sites"     "[ \"\$(grep -c 'exit 1' espalier/hooks/pre-push-gate.sh)\" = 0 ]"
  check "gate runs the secret scan untracked" "grep -qF 'PIPELINE_TRACKED' espalier/hooks/pre-push-gate.sh"
  check "no placeholder left in the gate"  "! grep -qE '\{(build|lint|test)_command\}' espalier/hooks/pre-push-gate.sh"
else
  check "customised gate: skip marker written" "grep -qF 'v0.11.0-gate:' espalier/.migrations-skipped"
fi
check "push wrapper fails closed without python" "grep -qF 'python3 not found' espalier/hooks/pre-push-gate-wrapper.sh"
check "push wrapper strips quoted spans"    "grep -qF 'STRIPPED=' espalier/hooks/pre-push-gate-wrapper.sh"
check "post-edit wrapper has the PYBIN probe" "grep -qF 'PYBIN' espalier/hooks/post-edit-wrapper.sh"
if [ -f espalier/hooks/check-layer-boundaries.sh ] \
   && ! grep -qF 'v0.11.0-layer-hook:' espalier/.migrations-skipped 2>/dev/null; then
  check "layer hook has no blocking 'exit 1'" "! grep -qE '^[^#]*exit 1$' espalier/hooks/check-layer-boundaries.sh"
fi
for a in harness-reviewer harness-security; do
  if [ -f "espalier/agents/$a.md" ] && grep -q '^tools:' "espalier/agents/$a.md"; then
    check "$a tools line carries Write"     "grep -q '^tools:.*Write' espalier/agents/$a.md"
  fi
done
# Live agent files only — espalier/agents/ may hold *.bak backups from older
# migrations that legitimately still carry the sentence.
check "no 'no Write/Edit' sentence left"    "! cat espalier/agents/harness-reviewer.md espalier/agents/harness-security.md 2>/dev/null | grep -qF 'you have no Write/Edit'"
check "pipeline.md has no no-TTY wording"   "! grep -qF 'no-TTY' espalier/pipeline.md"
check "espalier skill gates on the verdict word" "grep -qF 'Advance ONLY when EVERY record' espalier/skills/espalier/SKILL.md"
check "espalier-fix gates on the verdict word"   "grep -qF 'Advance ONLY when EVERY record' espalier/skills/espalier-fix/SKILL.md"
check "no {project} literal in espalier-review"   "! grep -qF '{project}' espalier/skills/espalier-review/SKILL.md"
check "no {project} literal in espalier-security" "! grep -qF '{project}' espalier/skills/espalier-security/SKILL.md"

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — .pre-v0.11.bak backups hold the previous files"
log "v0.11.0 migration complete. Backups: *.pre-v0.11.bak (delete when satisfied)."
