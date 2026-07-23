#!/bin/bash
# Migrate a v0.13.1 Espalier install to v0.13.2.
#
# v0.13.2 is the readability release: "human readable" stops being an accident
# of discovered conventions and becomes an explicit duty on both agents. No new
# lane, no new stage; ONE new P1 class (a cryptic EXPORTED/public name) joins
# the sentinel's p1= count — everything else lands advisory P2/P3.
#
# Files patched (backed up to <file>.pre-v0.13.2.bak):
#   espalier/agents/harness-coder.md          ladder tie-break becomes clarity
#       then brevity (section refreshed from the plugin template; the rung-5
#       tie-break now reads "same correctness → take the more readable ...
#       still tied → take the shorter").
#   espalier/agents/harness-reviewer.md       + Readability Review section
#       (advisory naming:/nesting:/magic:/comments: tags; ONE P1: a cryptic
#       EXPORTED/public name), Review Process step 6 runs it alongside the
#       Minimalism Review, Summary gains a Readability line, the sentinel note
#       counts the readability P1 like any other, Must-NOT gains the
#       taste-vs-convention bullet. The Minimalism Review span is refreshed
#       from the template in the same splice.
#   espalier/rules/coding-standards.md        + naming-intent floor ("a name
#       STATES what it holds or does") + "## Comments & Docstrings" section.
#       The new section carries {observed ...} placeholders — run
#       /espalier-prune (scout 1.3) afterwards to fill them from the codebase.
#   espalier/skills/espalier-coding/SKILL.md  Solution Selection summary
#       refreshed (clarity then brevity; reviewer gate list now names the
#       cryptic-public-name gate).
#   espalier/skills/espalier-review/SKILL.md  panel description + code-review
#       Gate line mention readability advisories; General Checks gains the
#       Readability item.
#   espalier/.scout-prompts.md                scout 1.3 additionally extracts
#       comment conventions (density / docstrings / what earns a comment).
#
# The agent-description frontmatter lines and .scout-prompts.md are patched
# WARN-ONLY: an install migrated up from pre-v0.13 keeps its older description
# wording, and a customised scout-prompts file is reported with a manual
# snippet, never mangled. Requires python3 (exact-string splices).
#
# Usage:
#   bash migrate-v0.13.1-to-v0.13.2.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.13.1→v0.13.2] $*"; }
die() { echo "[migrate v0.13.1→v0.13.2] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."
command -v python3 >/dev/null 2>&1 || die "python3 is required (exact-string splices)."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates/agents" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
CODER_TPL="$TPL/agents/harness-coder.md"
REVIEWER_TPL="$TPL/agents/harness-reviewer.md"
CODING_TPL="$TPL/skills/espalier-coding.md"
REVIEW_TPL="$TPL/skills/espalier-review.md"
RULES_TPL="$TPL/rules/coding-standards.md"
SCOUT_TPL="$TPL/scout-prompts.md"
for f in "$CODER_TPL" "$REVIEWER_TPL" "$CODING_TPL" "$REVIEW_TPL" "$RULES_TPL" "$SCOUT_TPL"; do
  [ -f "$f" ] || die "plugin dir $PLUGIN_DIR is missing template $f."
done

# The templates must actually be v0.13.2 — otherwise a stale plugin would
# "migrate" the install to nothing.
grep -qF -- 'clarity then brevity break ties' "$CODER_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (coder template lacks the clarity tie-break). Update the plugin first."
grep -qF -- '## Readability Review' "$REVIEWER_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (reviewer template lacks the Readability Review). Update the plugin first."
grep -qF -- '## Comments & Docstrings' "$RULES_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (coding-standards template lacks Comments & Docstrings). Update the plugin first."
grep -qF -- 'what_gets_commented' "$SCOUT_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (scout-prompts template lacks the comments field). Update the plugin first."
grep -qF -- 'Readability: names state intent' "$REVIEW_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (review template lacks the Readability checklist item). Update the plugin first."
grep -qF -- 'clarity then brevity break ties' "$CODING_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.2 (coding template lacks the clarity tie-break). Update the plugin first."

CODER="espalier/agents/harness-coder.md"
REVIEWER="espalier/agents/harness-reviewer.md"
CODING="espalier/skills/espalier-coding/SKILL.md"
REVIEW="espalier/skills/espalier-review/SKILL.md"
RULES="espalier/rules/coding-standards.md"
SP="espalier/.scout-prompts.md"
for f in "$CODER" "$REVIEWER" "$CODING" "$REVIEW" "$RULES"; do
  [ -f "$f" ] || die "$f not found — is this a v0.13.1 install? Run the earlier chain steps first."
done
SP_PRESENT=yes
[ -f "$SP" ] || SP_PRESENT=no

# --- Prerequisite: the install must be v0.13.1 --------------------------------
# (same markers the espalier-migrate chain uses for v0.13.1 detection)
grep -qF -- '## How This Skill Applies by Stage' "$CODING" || \
  die "install is pre-v0.13.1 (coding skill lacks the By-Stage section) — run migrate-v0.13.0-to-v0.13.1.sh first."
grep -qF -- 'run the **Security Abuse-Test Coverage**' "$REVIEWER" || \
  die "install is pre-v0.13.1 (reviewer lacks the step-7 abuse-test line) — run migrate-v0.13.0-to-v0.13.1.sh first."
grep -qF -- 'max-code-rounds' "$REVIEW" || \
  die "install is pre-v0.13.1 (review skill lacks the code-review Gate line) — run migrate-v0.13.0-to-v0.13.1.sh first."

# --- Idempotency: already migrated? ------------------------------------------
if grep -qF -- 'clarity then brevity break ties' "$CODER" \
   && grep -qF -- '## Readability Review' "$REVIEWER" \
   && grep -qF -- '## Comments & Docstrings' "$RULES" \
   && grep -qF -- 'clarity then brevity break ties' "$CODING" \
   && grep -qF -- 'Readability: names state intent' "$REVIEW"; then
  log "already at v0.13.2 (all five core markers present). Nothing to do."
  exit 0
fi

# --- Plan ----------------------------------------------------------------------
log "will patch (surgical, anchored; python3 exact-string splices):"
grep -qF -- 'clarity then brevity break ties' "$CODER" || \
  log "  $CODER: ladder refreshed — clarity-then-brevity tie-break"
grep -qF -- '## Readability Review' "$REVIEWER" || \
  log "  $REVIEWER: + Readability Review section, step-6 mention, Summary line, sentinel note, Must-NOT bullet"
grep -qF -- '## Comments & Docstrings' "$RULES" || \
  log "  $RULES: + naming-intent floor + Comments & Docstrings ({observed} placeholders — refresh via /espalier-prune)"
grep -qF -- 'clarity then brevity break ties' "$CODING" || \
  log "  $CODING: Solution Selection summary refreshed"
grep -qF -- 'Readability: names state intent' "$REVIEW" || \
  log "  $REVIEW: panel description + Gate line + Readability checklist item"
if [ "$SP_PRESENT" = yes ]; then
  grep -qF -- 'what_gets_commented' "$SP" || \
    log "  $SP: scout 1.3 + comment-convention extraction (warn-only if customised)"
else
  log "  $SP: MISSING — skipped (warn-only; re-run /espalier-migrate after the v0.9.2 step restores it)"
fi

if [ "$DRY_RUN" = yes ]; then
  log "dry-run: no files changed."
  exit 0
fi
if [ "$SKIP_PROMPT" != yes ]; then
  printf '[migrate v0.13.1→v0.13.2] proceed? [y/N] '
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.13.2.bak" ] || cp "$1" "$1.pre-v0.13.2.bak"; }
for f in "$CODER" "$REVIEWER" "$CODING" "$REVIEW" "$RULES"; do backup_once "$f"; done
[ "$SP_PRESENT" = yes ] && backup_once "$SP"

# --- Apply (python3: exact-string splices, backtick/apostrophe safe) -----------
CODER="$CODER" REVIEWER="$REVIEWER" CODING="$CODING" REVIEW="$REVIEW" \
RULES="$RULES" SP="$SP" SP_PRESENT="$SP_PRESENT" \
CODER_TPL="$CODER_TPL" REVIEWER_TPL="$REVIEWER_TPL" CODING_TPL="$CODING_TPL" \
RULES_TPL="$RULES_TPL" \
python3 <<'PY' || die "patch failed — inspect the MISS lines above; backups at <file>.pre-v0.13.2.bak."
import os, re, sys

warns, missed = [], []

def read(p):  return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s)

def span(text, start, end):
    """Lines from the line starting with `start` (inclusive) to the line
    starting with `end` (exclusive). end=None → to EOF."""
    lines = text.splitlines(keepends=True)
    s = e = None
    for i, ln in enumerate(lines):
        if s is None and ln.startswith(start):
            s = i
        elif s is not None and end is not None and ln.startswith(end):
            e = i
            break
    if s is None:
        return None
    return "".join(lines[s:e]) if e is not None else "".join(lines[s:])

def sub_once(path, old, new, label, required=True):
    text = read(path)
    n = text.count(old)
    if n == 0:
        if new in text:
            return  # already applied
        (missed if required else warns).append(f"{path}: {label} — anchor not found")
        print(("MISS " if required else "WARN ") + f"{path}: {label}")
        return
    if n > 1:
        missed.append(f"{path}: {label} — anchor not unique ({n} hits)")
        print(f"MISS {path}: {label} (ambiguous)")
        return
    write(path, text.replace(old, new, 1))
    print(f"patched {path}: {label}")

def swap_span(path, start, end, tpl_path, marker, label):
    text = read(path)
    if marker in text:
        return
    block = span(read(tpl_path), start, end)
    old = span(text, start, end)
    if block is None or old is None:
        missed.append(f"{path}: {label} — span not found")
        print(f"MISS {path}: {label}")
        return
    write(path, text.replace(old, block, 1))
    print(f"patched {path}: {label}")

CODER, REVIEWER, CODING = os.environ["CODER"], os.environ["REVIEWER"], os.environ["CODING"]
REVIEW, RULES, SP = os.environ["REVIEW"], os.environ["RULES"], os.environ["SP"]
CODER_TPL, REVIEWER_TPL, CODING_TPL = os.environ["CODER_TPL"], os.environ["REVIEWER_TPL"], os.environ["CODING_TPL"]

# --- Coder: ladder section refresh + description slogan (warn-only) ---
swap_span(CODER, "## Solution Selection Ladder", "## Output Format",
          CODER_TPL, "clarity then brevity break ties.**", "Solution Selection Ladder refresh")
sub_once(CODER,
  "  (conventions first, correctness within them, brevity only breaks ties).\n",
  "  (conventions first, correctness within them, clarity then brevity break ties).\n",
  "description slogan", required=False)

# --- Reviewer: Minimalism span refresh brings the Readability Review with it ---
swap_span(REVIEWER, "## Minimalism Review", "## Security Abuse-Test Coverage",
          REVIEWER_TPL, "## Readability Review", "Minimalism + Readability Review sections")
sub_once(REVIEWER,
  "6. Run the **Minimalism Review** (see section below) — advisory P2/P3 notes,\n"
  "   plus the single new-dependency P1 rule.\n",
  "6. Run the **Minimalism Review** and the **Readability Review** (see sections\n"
  "   below) — advisory P2/P3 notes, plus two P1 rules: minimalism's new\n"
  "   dependency, readability's cryptic public name.\n",
  "Review Process step 6")
sub_once(REVIEWER,
  "- Minimalism: {lean / N advisory notes}\n",
  "- Minimalism: {lean / N advisory notes}\n"
  "- Readability: {clear / N advisory notes}\n",
  "Summary Readability line")
sub_once(REVIEWER,
  "minimalism new-dependency P1 counts like any other P1); a missing or\n",
  "minimalism new-dependency P1 or a readability cryptic-public-name P1 counts\n"
  "like any other P1); a missing or\n",
  "sentinel p1= note")
sub_once(REVIEWER,
  "  Observation, not a finding)\n",
  "  Observation, not a finding)\n"
  "- File a readability finding above P2 (sole exception: the cryptic-public-name\n"
  "  P1), or one grounded in personal taste rather than the project's own\n"
  "  conventions\n",
  "Must-NOT readability bullet")
sub_once(REVIEWER,
  "  production-readiness seeds, and (advisory) minimalism. Spawned fresh by the\n"
  "  pipeline each Stage 4 code-review round and each Stage 6 test-review round,\n",
  "  production-readiness seeds, and (advisory) minimalism + readability. Spawned\n"
  "  fresh by the pipeline each Stage 4 code-review round and each Stage 6\n"
  "  test-review round,\n",
  "description readability mention", required=False)

# --- Coding skill: Solution Selection summary refresh (section is last → EOF) ---
swap_span(CODING, "## Solution Selection (keep it lean)", None,
          CODING_TPL, "clarity then brevity break ties", "Solution Selection summary refresh")

# --- Review skill: panel description, Gate line, Readability checklist ---
sub_once(REVIEW,
  "  Runtime-Surface, Production-Readiness, and (advisory) Minimalism reviews and\n"
  "  writes `review-record.md`.\n",
  "  Runtime-Surface, Production-Readiness, and (advisory) Minimalism +\n"
  "  Readability reviews and writes `review-record.md`.\n",
  "panel description")
sub_once(REVIEW,
  "  on the sentinel — P2/P3 (minimalism advisories included) are recorded, never\n"
  "  blocking. On a non-pass, the coder fixes and the change is re-reviewed; round\n"
  "  counting and escalation are owned by pipeline Stage 4 (`max-code-rounds`),\n"
  "  not this skill.\n",
  "  on the sentinel — P2/P3 (minimalism + readability advisories included) are\n"
  "  recorded, never blocking. On a non-pass, the coder fixes and the change is\n"
  "  re-reviewed; round counting and escalation are owned by pipeline Stage 4\n"
  "  (`max-code-rounds`), not this skill.\n",
  "code-review Gate line")
sub_once(REVIEW,
  "      Review). Never flag a construct the rules/specs mandate.\n",
  "      Review). Never flag a construct the rules/specs mandate.\n"
  "- [ ] Readability: names state intent, judged against the project's own\n"
  "      conventions — never personal taste. A cryptic EXPORTED/public name is the\n"
  "      single P1; everything else advisory P2/P3 — canonical rules in\n"
  "      `espalier/agents/harness-reviewer.md` (Readability Review).\n",
  "Readability checklist item")

# --- Rules: naming-intent floor + Comments & Docstrings before Required Patterns ---
rules_text = read(RULES)
if "## Comments & Docstrings" not in rules_text:
    tpl_block = span(read(os.environ["RULES_TPL"]),
                     "Beyond casing, a name STATES", "## Required Patterns")
    if tpl_block is None:
        missed.append(f"{RULES}: template block extraction failed")
        print(f"MISS {RULES}: template block extraction")
    elif "## Required Patterns" in rules_text:
        write(RULES, rules_text.replace("## Required Patterns", tpl_block + "## Required Patterns", 1))
        print(f"patched {RULES}: + naming-intent floor + Comments & Docstrings")
    else:
        write(RULES, rules_text.rstrip("\n") + "\n\n" + tpl_block.rstrip("\n") + "\n")
        warns.append(f"{RULES}: no '## Required Patterns' anchor — block appended at EOF")
        print(f"WARN {RULES}: anchor missing — appended at EOF")

# --- Scout prompts: scout 1.3 comment-convention extraction (warn-only) ---
if os.environ["SP_PRESENT"] == "yes":
    sub_once(SP,
      "pattern, async style, type discipline, logging library + format, validation.\n",
      "pattern, async style, type discipline, logging library + format, validation,\n"
      "comment conventions (density / docstring style / what earns a comment).\n",
      "scout 1.3 prose", required=False)
    sub_once(SP,
      '    "validation": "..."\n',
      '    "validation": "...",\n'
      '    "comments": {"density": "...", "docstrings": "...", "what_gets_commented": "..."}\n',
      "scout 1.3 JSON comments field", required=False)
else:
    warns.append(f"{SP}: file missing — scout 1.3 not patched")

if warns:
    print("WARN-ONLY items (manual follow-up optional):")
    for w in warns:
        print("  - " + w)
if missed:
    print("REQUIRED anchors missed:")
    for m in missed:
        print("  - " + m)
    sys.exit(3)
PY

# --- Verify -------------------------------------------------------------------
pass=0; fail=0
check() {
  if grep -qF -- "$2" "$1"; then pass=$((pass+1)); echo "  ✓ $1: $3"
  else fail=$((fail+1)); echo "  ✗ $1: $3"; fi
}
check_absent() {
  if grep -qF -- "$2" "$1"; then fail=$((fail+1)); echo "  ✗ $1: $3"
  else pass=$((pass+1)); echo "  ✓ $1: $3"; fi
}
log "verification:"
check        "$CODER"    'clarity then brevity break ties'                  "clarity tie-break slogan"
check        "$CODER"    'take the more readable'                           "rung-5 readable tie-break"
check_absent "$CODER"    'one; same correctness → take the shorter.'        "old rung-5 tie-break gone"
check        "$REVIEWER" '## Readability Review'                            "Readability Review section"
check        "$REVIEWER" '**The one P1 — a cryptic PUBLIC name:**'          "cryptic-public-name P1 rule"
check        "$REVIEWER" 'and the **Readability Review** (see sections'     "step-6 mention"
check        "$REVIEWER" '- Readability: {clear / N advisory notes}'        "Summary Readability line"
check        "$REVIEWER" 'readability cryptic-public-name P1 counts'        "sentinel p1= note"
check        "$REVIEWER" 'File a readability finding above P2'              "Must-NOT bullet"
check        "$RULES"    'Beyond casing, a name STATES'                     "naming-intent floor"
check        "$RULES"    '## Comments & Docstrings'                         "Comments & Docstrings section"
check        "$CODING"   'clarity then brevity break ties'                  "Solution Selection refresh"
check        "$CODING"   'cryptic-public-name gates'                        "reviewer gate list"
check        "$REVIEW"   'Readability: names state intent'                  "Readability checklist item"
check        "$REVIEW"   'minimalism + readability advisories included'     "Gate line advisories"
if [ "$SP_PRESENT" = yes ] && grep -qF -- 'what_gets_commented' "$SP"; then
  pass=$((pass+1)); echo "  ✓ $SP: scout 1.3 comments field"
else
  echo "  - $SP: scout 1.3 comments field (warn-only — see WARN lines above)"
fi
log "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — inspect the ✗ lines; backups at <file>.pre-v0.13.2.bak."
log "done. Backups: <file>.pre-v0.13.2.bak. The new coding-standards sections carry"
log "{observed ...} placeholders — run /espalier-prune (scout 1.3) to fill them."
log "Review with: git diff"
