#!/bin/bash
# Migrate an Espalier v0.9.6 target repo to v0.10.0.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.10.0 reshapes the generated push gate's three check steps:
#
#   - `{build_command}` / `{lint_command}` / `{test_command}` are substituted into
#     FUNCTION BODIES (`run_build` / `run_lint` / `run_tests`), so the value may be
#     a single command OR a multi-line block. Before, `{test_command}` landed inside
#     a command substitution — `TEST_OUTPUT=$({test_command} 2>&1)` — so a repo that
#     must run several suites (one per container in a Docker-first stack, one per
#     workspace in a monorepo) could not be expressed at all.
#
#   - Build and lint no longer discard stderr. The old template ran
#     `{build_command} 2>/dev/null` and, on failure, printed `BLOCKED: Build fails`
#     and nothing else. Output is now captured and its tail printed on failure — a
#     gate that blocks without saying why gets disabled.
#
# This migration rewrites those three spans in the installed gate, PRESERVING the
# commands this project substituted at init. A gate whose spans no longer match the
# template (customised at init — e.g. a Docker-first `docker compose exec` runner)
# is left completely untouched and reported, not mangled.
#
# Usage: bash migrate-v0.9.6-to-v0.10.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.10.0] $*"; }
die() { echo "[migrate-v0.10.0] ERROR: $*" >&2; exit 1; }

GATE="espalier/hooks/pre-push-gate.sh"
[ -f "$GATE" ] || die "run me from the TARGET project root ($GATE not found)."

if [ -z "$PLUGIN_DIR" ]; then
  for c in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/marketplaces/espalier-engineering/espalier-engineering" \
    "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"; do
    [ -f "$c/skills/espalier-init/hook-templates/pre-push-gate.sh" ] && PLUGIN_DIR="$c" && break
  done
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin; pass --plugin-dir=<path to plugin root>."

GATE_TPL="$PLUGIN_DIR/skills/espalier-init/hook-templates/pre-push-gate.sh"
[ -f "$GATE_TPL" ] || die "template not found: $GATE_TPL"
grep -qF 'run_tests() {' "$GATE_TPL" || \
  die "template at $PLUGIN_DIR is not v0.10.0 (no run_tests function). Update the plugin first."

command -v python3 >/dev/null 2>&1 || die "python3 is required for the surgical gate patch."

# --- Idempotency -------------------------------------------------------------
# ALL THREE must be function-shaped. A gate can legitimately be half-migrated:
# running migrate-v0.9.1-to-v0.9.2.sh against a v0.10.0 plugin re-splices only the
# TEST span from the new template, yielding run_tests with old build/lint. Keying
# the guard on run_tests alone would strand those two forever.
if grep -qF 'run_build() {' "$GATE" \
   && grep -qF 'run_lint() {' "$GATE" \
   && grep -qF 'run_tests() {' "$GATE"; then
  log "already at v0.10.0 (gate defines run_build/run_lint/run_tests) — nothing to do."
  exit 0
fi

# --- Can we recognise this gate as template-shaped? --------------------------
# The three span anchors must exist, or we do not touch it. The per-span command
# extraction is checked in python, which skips any span already function-shaped.
CUSTOMISED=no
grep -qxF '# Run build check' "$GATE" || CUSTOMISED=yes
grep -qxF '# Run lint check' "$GATE" || CUSTOMISED=yes
grep -qE '^# Run tests and check count' "$GATE" || CUSTOMISED=yes
grep -qE '^echo "All gates passed' "$GATE" || CUSTOMISED=yes
# A gate with neither the old TEST_OUTPUT shape nor run_tests is not one of ours.
grep -qE '^TEST_OUTPUT=\$\(.* 2>&1\)$' "$GATE" || grep -qF 'run_tests() {' "$GATE" || CUSTOMISED=yes

if [ "$CUSTOMISED" = yes ]; then
  echo
  echo "  This project's $GATE does not match the template shape — it was"
  echo "  customised at init (for example, a Docker-first gate that runs each suite"
  echo "  in its own container). Rewriting it automatically would destroy that."
  echo
  echo "  Leaving it untouched. What v0.10.0 changes, if you want it by hand:"
  echo "    - build/lint: capture output and print its tail on failure"
  echo "      (the old template ran '<cmd> 2>/dev/null' and printed nothing)"
  echo "    - tests: run via a run_tests() function so several suites can run"
  echo
  # Record the skip so /espalier-migrate reports this version as "handled
  # (manual)" once instead of re-proposing the patch every run. Append-once.
  if [ "$DRY_RUN" != yes ] \
     && ! grep -qF 'v0.10.0-gate:' espalier/.migrations-skipped 2>/dev/null; then
    echo "v0.10.0-gate: customised, manual port needed" >> espalier/.migrations-skipped
  fi
  log "gate left untouched (customised). Marker written to espalier/.migrations-skipped. Nothing else to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  log "  1. back up $GATE -> $GATE.pre-v0.10.0.bak"
  log "  2. rewrite its build / lint / test spans from the v0.10.0 template,"
  log "     preserving the commands substituted at init"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Rewrite the build/lint/test spans of %s? [y/N] " "$GATE"
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

cp "$GATE" "$GATE.pre-v0.10.0.bak"
log "backed up -> $GATE.pre-v0.10.0.bak"

GATE="$GATE" GATE_TPL="$GATE_TPL" python3 <<'PY'
import os, re, sys

gate_p, tpl_p = os.environ["GATE"], os.environ["GATE_TPL"]
gate = open(gate_p, encoding="utf-8").read()
tpl  = open(tpl_p,  encoding="utf-8").read()

def span(text, start, end):
    m = re.search(r"(?ms)^" + start + r".*?(?=^" + end + r")", text)
    return m.group(0) if m else None

B_S, L_S = r"# Run build check$", r"# Run lint check$"
T_S, T_E = r"# Run tests and check count", r'echo "All gates passed'

# The two `<cmd> 2>/dev/null` statements are the OLD build/lint form, in order.
old_stmts = re.findall(r"^(.*) 2>/dev/null$", gate, re.M)

def old_build():
    return old_stmts[0] if len(old_stmts) >= 1 else None

def old_lint():
    return old_stmts[1] if len(old_stmts) >= 2 else None

def old_test():
    # NEVER read this from `TEST_OUTPUT=$(run_tests 2>&1)` — that yields the
    # function name, not the command. Only the pre-v0.10.0 shape is valid here.
    m = re.search(r"^TEST_OUTPUT=\$\((.*) 2>&1\)$", gate, re.M)
    if not m:
        return None
    cmd = m.group(1).strip()
    return None if cmd == "run_tests" else cmd

out = gate
applied, skipped = [], []

# Each span is handled independently: a gate half-migrated by running the v0.9.2
# step against a v0.10.0 plugin has run_tests already but old build/lint.
# `func` is spelled out, not derived from `name` — the test step's function is
# run_testS, and building the name by concatenation silently never matches.
for name, func, start, end, fn, ph in (
    ("build", "run_build", B_S, L_S, old_build, "{build_command}"),
    ("lint",  "run_lint",  L_S, T_S, old_lint,  "{lint_command}"),
    ("test",  "run_tests", T_S, T_E, old_test,  "{test_command}"),
):
    if re.search(r"^%s\(\) \{$" % re.escape(func), out, re.M):
        skipped.append("%s (already function-shaped)" % name)
        continue
    cmd = fn()
    if cmd is None:
        sys.exit("ERROR: could not read the substituted %s command" % name)
    t = span(tpl, start, end)
    g = span(out, start, end)
    if t is None:
        sys.exit("ERROR: template missing span %r" % start)
    if g is None:
        sys.exit("ERROR: install missing span %r" % start)
    out = out.replace(g, t.replace(ph, cmd), 1)
    applied.append("%s: %s" % (name, cmd))

for ph in ("{build_command}", "{lint_command}", "{test_command}"):
    if ph in out:
        sys.exit("ERROR: refusing to write an unsubstituted %s" % ph)

open(gate_p, "w", encoding="utf-8").write(out)
for a in applied:
    print("  %s" % a)
for s in skipped:
    print("  skipped %s" % s)
PY
rc=$?
[ $rc -eq 0 ] || die "surgical patch failed — restore from $GATE.pre-v0.10.0.bak"
chmod +x "$GATE"

# --- Verify ------------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "gate parses clean (bash -n)"        "/bin/bash -n $GATE"
check "gate defines run_build"             "grep -qF 'run_build() {' $GATE"
check "gate defines run_lint"              "grep -qF 'run_lint() {' $GATE"
check "gate defines run_tests"             "grep -qF 'run_tests() {' $GATE"
check "build failure prints its output"    "grep -qF 'BUILD_OUTPUT' $GATE"
check "lint failure prints its output"     "grep -qF 'LINT_OUTPUT' $GATE"
# The old shape ran the command as a bare statement with stderr discarded. Its
# absence is what proves the rewrite landed (a substituted command may legitimately
# contain 2>/dev/null itself, so only the standalone statement form is checked).
check "old stderr-discarding form is gone" "! grep -qE '^[^ #].* 2>/dev/null\$' $GATE"
check "no placeholder left"                "! grep -qE '\{(build|lint|test)_command\}' $GATE"
check "count parse preserved"              "grep -qF 'could not parse a test count' $GATE"
check "active-change selection preserved"  "grep -qF 'Find the ACTIVE change' $GATE"

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — restore from $GATE.pre-v0.10.0.bak"
log "v0.10.0 migration complete. Backup: $GATE.pre-v0.10.0.bak (delete when satisfied)."
