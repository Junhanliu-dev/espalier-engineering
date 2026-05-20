#!/bin/bash
# Migrate an Espalier v0.4.x target repo to v0.5.0 (doc-drift detection).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview every change before applying.
#
# v0.5.0 adds doc-drift detection — it keeps the generated espalier/ artifacts
# in sync with the codebase as it evolves. This migration:
#   1. Runs bootstrap-espalier.sh --force — copies the new drift hooks
#      (drift-detect.sh, drift-helpers.sh, parse-drift-blocks.py), installs the
#      espalier-prune + espalier-doctor skills, swaps the post-merge hook for
#      the dispatcher, gitignores the drift sidecars, writes .doctor-cadence,
#      and refreshes the pure-copy skills (pipeline.md, espalier, espalier-fix).
#   2. Patches the three LLM-substituted files bootstrap cannot regenerate:
#        - espalier/agents/harness-coder.md     (stale-doc check)
#        - espalier/agents/harness-reviewer.md  (Convention Drift + Observations)
#        - espalier/hooks/pre-push-gate.sh      (doctor-cadence reminder)
#   3. Verifies the result.
#
# What this script does NOT do:
#   - Touch espalier/rules/*, espalier/wiki/*, or espalier/changes/* — no drift
#     change affects them.
#   - Re-discover the codebase. To pick up genuine drift after upgrading, run
#     /espalier-doctor (a periodic scan) or /espalier-prune (per-file refresh).
#
# Usage:
#   bash migrate-v0.4-to-v0.5.sh [--dry-run] [--yes] [--doctor-cadence=<val>] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
DOCTOR_CADENCE=weekly
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)            DRY_RUN=yes ;;
    --yes)                SKIP_PROMPT=yes ;;
    --doctor-cadence=*)   DOCTOR_CADENCE="${arg#--doctor-cadence=}" ;;
    --plugin-dir=*)       PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.4→v0.5] $*"; }

case "$DOCTOR_CADENCE" in
  every-change|weekly|monthly|manual) ;;
  *)
    echo "WARNING: unknown --doctor-cadence='$DOCTOR_CADENCE', falling back to 'weekly'" >&2
    DOCTOR_CADENCE=weekly
    ;;
esac

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run the v0.3→v0.4 rename migration first (via /espalier-migrate)." >&2
  exit 1
fi

if [ ! -d "espalier" ]; then
  echo "ERROR: no espalier/ directory — not an Espalier install." >&2
  echo "Use /espalier-init to set up Espalier in a fresh project." >&2
  exit 1
fi

if [ ! -f "espalier/.merge-hook-decision" ]; then
  echo "ERROR: espalier/.merge-hook-decision missing — install looks incomplete." >&2
  echo "Re-run /espalier-init (or bootstrap-espalier.sh --force) to repair it first." >&2
  exit 1
fi

# Already-v0.5 detector — all three markers present.
if [ -f "espalier/hooks/drift-detect.sh" ] \
   && [ -f "espalier/.doctor-cadence" ] \
   && grep -q "Convention Drift Reporting" espalier/agents/harness-reviewer.md 2>/dev/null; then
  echo "Already on v0.5.0 (drift hooks + .doctor-cadence + patched agents present)."
  echo "Nothing to do. To scan for genuine drift, run /espalier-doctor."
  exit 0
fi

# Locate the plugin root (must contain scripts/bootstrap-espalier.sh).
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/repos/espalier-engineering" \
    "$HOME/SBM_Projects/espalier-engineering"; do
    if [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Update the plugin first (/plugin update espalier-engineering), or pass" >&2
  echo "--plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi

BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null)

cat << EOF

Espalier doc-drift upgrade (v0.4.x → v0.5.0)

Plan:
  1. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → drift hooks, espalier-prune + espalier-doctor skills, post-merge
         dispatcher, .gitignore sidecars, .doctor-cadence, refreshed skills
  2. Patch harness-coder.md / harness-reviewer.md / pre-push-gate.sh
  3. Verify

Plugin: $PLUGIN_DIR
EOF

if [ "$DRY_RUN" = "yes" ]; then
  echo "Mode: DRY RUN (no changes will be written)"
elif [ "$SKIP_PROMPT" != "yes" ]; then
  printf 'Apply upgrade? [y/N]: '
  read -r confirm
  case "$confirm" in
    y|Y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

# --- Step 1: bootstrap --force (mechanical 90%) ------------------------------

log "Step 1: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  if ! bash "$BOOTSTRAP" $BOOT_FLAGS; then
    echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
    exit 1
  fi
fi

# --- Step 2: patch the three LLM-substituted files --------------------------

log "Step 2: patch harness-coder.md / harness-reviewer.md / pre-push-gate.sh"
if [ "$DRY_RUN" = "yes" ]; then
  echo "[dry-run] patch espalier/agents/harness-coder.md (stale-doc check)"
  echo "[dry-run] patch espalier/agents/harness-reviewer.md (pre-flight + Convention Drift + Observations)"
  echo "[dry-run] patch espalier/hooks/pre-push-gate.sh (doctor-cadence reminder)"
else
  python3 - << 'PYPATCH'
import sys

CODER_ITEM = """6. Stale-doc check: `cut -f1 espalier/.drift-state.tsv 2>/dev/null` lists every
   flagged file (repo-relative). If a rule or spec you rely on is listed, note
   it in coding-report.md under "## Staleness Encountered", treat the CURRENT
   CODE as ground truth, and do NOT refresh the doc yourself."""

REVIEWER_STEP0 = """0. Pre-flight: if a rule or wiki file material to this review is listed in
   `espalier/.drift-state.tsv`, add a line to your `### Summary`:
   "STALE CONTEXT: {file} flagged stale — findings checked against current
   code, not the stale doc." This is a note only — do NOT change the
   PASS/FAIL verdict because of staleness."""

REVIEWER_CONVENTIONS = """## Convention Drift Reporting

If during review you observe one OR MORE recurring code patterns that differ
from project rules and are now used in 2+ places, emit a Convention Drift block
for EACH distinct drift, in exactly this shape:

```
## Convention Drift
- Rule file: espalier/rules/coding-standards.md (or specs/{layer}.md)
- Old convention: "{quoted from the rule}"
- New convention observed: "{what the code does now}"
- Evidence files: {2+ files showing the new pattern}
- Recommendation: update rule | document exception | reject this code
- coupled_with: {optional — another rule file whose drift depends on this one}
```

Constraints:
- DO NOT silently approve code that violates a rule — emit the block first.
- DO NOT use Convention Drift for one-off exceptions. 2+ evidence files required.
- DO NOT bundle unrelated drifts. One drift = one block. A block with two
  `- Rule file:` lines is malformed and will be rejected by the parser.
- Checking 2+ occurrences is a bounded grep over the layer you are already
  reviewing — NOT a whole-codebase audit. If you cannot confirm 2+ from files
  in scope, emit a Convention Observation instead (a lower-bar report — see the
  Convention Observations section below).

## Convention Observations

Separate from — and lower-bar than — a Convention Drift block: any time code
diverges from a rule, even a SINGLE occurrence, emit an Observation. Do NOT
assign an aggregation key; emit only what you can see locally. The orchestrator
canonicalizes keys across reviews (a fresh isolated reviewer cannot).

```
## Convention Observations
- description: "controllers return Result<T,E> instead of throwing"
  location: src/controllers/userController.ts:42
  rule_file: espalier/rules/coding-standards.md
```

Emit one `- description:` entry per divergence. A Convention Drift block (2+
occurrences, high confidence) and a Convention Observation (any occurrence) are
not mutually exclusive — a strong drift may warrant both.
"""

PREPUSH_REMINDER = """
# Doctor-cadence reminder — non-blocking, printed before any gate logic so it
# fires on every push regardless of gate outcome (the gate has early-exit
# paths). Never affects the exit code.
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  doctor_due && echo "Reminder: an /espalier-doctor drift scan is due."
fi"""

# (path, marker, anchor, position, block)
PATCHES = [
    ("espalier/agents/harness-coder.md",
     "Stale-doc check:",
     "5. Follow the template structure exactly",
     "after", CODER_ITEM),
    ("espalier/agents/harness-reviewer.md",
     "Pre-flight: if a rule or wiki file material",
     "1. Read the coding report from the coder agent (what was done)",
     "before", REVIEWER_STEP0),
    ("espalier/agents/harness-reviewer.md",
     "Convention Drift Reporting",
     "## You Must NOT",
     "before", REVIEWER_CONVENTIONS),
    ("espalier/hooks/pre-push-gate.sh",
     "Doctor-cadence reminder",
     "# Blocks git push unless all conditions are met",
     "after", PREPUSH_REMINDER),
]

rc = 0
for path, marker, anchor, pos, block in PATCHES:
    try:
        text = open(path).read()
    except FileNotFoundError:
        print("  skip (not found): %s" % path)
        continue
    if marker in text:
        print("  already patched: %s" % path)
        continue
    lines = text.split("\n")
    out = []
    done = False
    for line in lines:
        if not done and anchor in line:
            if pos == "before":
                out.extend(block.split("\n"))
                out.append(line)
            else:
                out.append(line)
                out.extend(block.split("\n"))
            done = True
        else:
            out.append(line)
    if not done:
        print("  WARN anchor not found in %s — patch by hand:" % path)
        print("       expected a line containing: %s" % anchor)
        rc = 1
        continue
    open(path, "w").write("\n".join(out))
    print("  patched: %s" % path)

sys.exit(rc)
PYPATCH
  PATCH_RC=$?
  if [ "$PATCH_RC" -ne 0 ]; then
    echo "WARNING: one or more files could not be auto-patched (see above)." >&2
    echo "The mechanical upgrade still applied; patch the flagged file(s) by hand." >&2
  fi
fi

# --- Step 3: verification ----------------------------------------------------

log "Step 3: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0
  check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  check "drift-detect.sh installed"        "test -f espalier/hooks/drift-detect.sh"
  check "drift-helpers.sh installed"       "test -f espalier/hooks/drift-helpers.sh"
  check "parse-drift-blocks.py installed"  "test -f espalier/hooks/parse-drift-blocks.py"
  check "espalier-prune skill present"     "test -f espalier/skills/espalier-prune/SKILL.md"
  check "espalier-doctor skill present"    "test -f espalier/skills/espalier-doctor/SKILL.md"
  check ".claude/skills/espalier-prune link"  "test -L .claude/skills/espalier-prune"
  check ".claude/skills/espalier-doctor link" "test -L .claude/skills/espalier-doctor"
  check "post-merge dispatcher installed"  "grep -qE 'ESPALIER_POSTMERGE_DISPATCH' .git/hooks/post-merge .husky/post-merge 2>/dev/null"
  check ".doctor-cadence written"          "grep -qE '^cadence: (every-change|weekly|monthly|manual)$' espalier/.doctor-cadence"
  check ".gitignore has drift sidecars"    "grep -qxF 'espalier/.drift-state.tsv*' .gitignore"
  check "harness-coder.md patched"         "grep -q 'Stale-doc check:' espalier/agents/harness-coder.md"
  check "harness-reviewer.md patched"      "grep -q 'Convention Drift Reporting' espalier/agents/harness-reviewer.md"
  check "pre-push-gate.sh patched"         "grep -q 'Doctor-cadence reminder' espalier/hooks/pre-push-gate.sh"
  echo ""
  echo "  Verification: $pass passed, $fail failed"
fi

echo ""
echo "Upgrade complete. Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.5.0 (doc-drift detection)'"
echo "  3. Run a drift scan to catch any drift that accrued before the upgrade:"
echo "       /espalier-doctor"
echo "  4. Doctor cadence is '$DOCTOR_CADENCE' — edit espalier/.doctor-cadence to change."
