#!/bin/bash
# Migrate an Espalier v0.9.2 target repo to v0.9.3.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.9.3 is a skill-clarity patch — no new lane, no new stage, no behaviour
# change to any gate or verdict:
#   - espalier-grill (pure-copy): explicit user tier-override — if the user
#     pushes back on the chosen tier, adopt their read; a coverage guard so
#     every counted ambiguity signal ends resolved / scoped-out / recorded in
#     `## Open Questions`; a non-answer ("I don't know") is recorded with a
#     named safe default instead of being silently dropped.
#   - espalier-review (substituted): the two review loops become an explicit
#     when / input / do / output / who workflow; the production-readiness
#     checklist stops restating severities (production-standards.md is the
#     single source); the frontmatter gains when-to-use + trigger phrases.
#
# This migration:
#   1. Backs up espalier-grill + espalier-review SKILL.md → <file>.pre-v0.9.3.bak
#   2. Refreshes the pure-copy espalier-grill SKILL.md from the v0.9.3 template.
#   3. Surgically re-splices the THREE changed sections of the substituted
#      espalier-review SKILL.md from the v0.9.3 template, substituting this
#      project's name and preserving every other (init-substituted) section —
#      notably the "{detected convention}" checklist line.
#   4. Verifies both landed.
#
# Usage: bash migrate-v0.9.2-to-v0.9.3.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.9.3] $*"; }
die() { echo "[migrate-v0.9.3] ERROR: $*" >&2; exit 1; }

GRILL="espalier/skills/espalier-grill/SKILL.md"
REVIEW="espalier/skills/espalier-review/SKILL.md"

# --- Locate the installed espalier tree + the v0.9.3 plugin templates --------
[ -f "$GRILL" ] || die "run me from the TARGET project root ($GRILL not found)."
[ -f "$REVIEW" ] || die "$REVIEW not found — is Espalier installed here?"

if [ -z "$PLUGIN_DIR" ]; then
  for c in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/marketplaces/espalier-engineering/espalier-engineering" \
    "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"; do
    [ -f "$c/skills/espalier-init/templates/skills/espalier-review.md" ] && PLUGIN_DIR="$c" && break
  done
fi
TPL="$PLUGIN_DIR/skills/espalier-init/templates/skills"
[ -f "$TPL/espalier-review.md" ] || die "cannot find v0.9.3 templates; pass --plugin-dir=<path to plugin root>."
grep -q "SINGLE SOURCE for these checks" "$TPL/espalier-review.md" || \
  die "template at $TPL is not v0.9.3 (missing the review-skill changes). Update the plugin first."

command -v python3 >/dev/null 2>&1 || die "python3 is required for the surgical espalier-review patch."

# --- Idempotency -------------------------------------------------------------
already_grill=no; already_review=no
grep -q "Coverage guard (before returning" "$GRILL" 2>/dev/null && already_grill=yes
grep -q "SINGLE SOURCE for these checks" "$REVIEW" 2>/dev/null && already_review=yes
if [ "$already_grill" = yes ] && [ "$already_review" = yes ]; then
  log "already at v0.9.3 (both skills carry the v0.9.3 markers) — nothing to do."
  exit 0
fi

# --- Discover this project's substituted name from the installed review skill -
# The unchanged "Review Checklist" line "Follows {project}'s naming conventions"
# holds the substituted name in every v0.9.2 install.
PROJ="$(sed -n "s/.*Follows \(.*\)'s naming conventions.*/\1/p" "$REVIEW" | head -1)"
if [ -z "$PROJ" ]; then
  # Fallback: the harness-reviewer agent carries it too.
  PROJ="$(sed -n 's/.*review agent for \([^.]*\)\..*/\1/p' espalier/agents/harness-reviewer.md 2>/dev/null | head -1)"
fi
[ -n "$PROJ" ] || die "could not discover this project's substituted name; aborting rather than write '{project}' literally."
log "project name discovered: $PROJ"

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  log "  1. back up $GRILL and $REVIEW"
  log "  2. refresh $GRILL from $TPL/espalier-grill.md (pure-copy)"
  log "  3. re-splice 3 sections of $REVIEW from template (project='$PROJ')"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "[migrate-v0.9.3] apply to this repo (project='%s')? [y/N] " "$PROJ"
  read -r ans; case "$ans" in y|Y|yes) ;; *) die "aborted by user." ;; esac
fi

# --- 1. Backups --------------------------------------------------------------
cp "$GRILL" "$GRILL.pre-v0.9.3.bak"
cp "$REVIEW" "$REVIEW.pre-v0.9.3.bak"
log "backed up -> $GRILL.pre-v0.9.3.bak , $REVIEW.pre-v0.9.3.bak"

# --- 2. espalier-grill: pure-copy refresh ------------------------------------
cp "$TPL/espalier-grill.md" "$GRILL"
log "refreshed $GRILL from template."

# --- 3. espalier-review: surgical section re-splice --------------------------
# Replace the frontmatter `description:` and the two changed body sections
# (## Two Review Loops, ## Production-Readiness Checks) with the template's
# versions, substituting {project} -> PROJ. Every other section is preserved
# verbatim, so init-time values like {detected convention} are untouched.
TEMPLATE="$TPL/espalier-review.md" INSTALL="$REVIEW" PROJ="$PROJ" python3 - <<'PY'
import os, re, sys

tpl_path, inst_path, proj = os.environ["TEMPLATE"], os.environ["INSTALL"], os.environ["PROJ"]
tpl = open(tpl_path, encoding="utf-8").read().replace("{project}", proj)
inst = open(inst_path, encoding="utf-8").read()

def split_front(text):
    m = re.match(r"^(---\n.*?\n---\n)(.*)$", text, re.DOTALL)
    if not m:
        sys.exit("ERROR: %s has no YAML frontmatter" % text[:0])
    return m.group(1), m.group(2)

def get_desc(front):
    # description: value that may be a '>-' block spanning indented lines
    m = re.search(r"(?ms)^description:.*?(?=^\S|\Z)", front)
    return m.group(0) if m else None

def sect(body, header):
    # header line through (but not including) the next '## ' header or EOF
    m = re.search(r"(?ms)^" + re.escape(header) + r"\b.*?(?=^## |\Z)", body)
    return m.group(0) if m else None

tpl_front, tpl_body = split_front(tpl)
inst_front, inst_body = split_front(inst)

# --- frontmatter description ---
td, id_ = get_desc(tpl_front), get_desc(inst_front)
if td is None or id_ is None:
    sys.exit("ERROR: could not locate description in template or install frontmatter")
inst_front = inst_front.replace(id_, td)

# --- body sections ---
changed = 0
for header in ("## Two Review Loops", "## Production-Readiness Checks"):
    tsec, isec = sect(tpl_body, header), sect(inst_body, header)
    if tsec is None:
        sys.exit("ERROR: template missing section %r" % header)
    if isec is None:
        sys.exit("ERROR: install missing section %r (unexpected v0.9.2 layout)" % header)
    inst_body = inst_body.replace(isec, tsec)
    changed += 1

out = inst_front + inst_body
if "{project}" in out:
    sys.exit("ERROR: refusing to write — a literal {project} placeholder remains")
open(inst_path, "w", encoding="utf-8").write(out)
print("[migrate-v0.9.3] espalier-review: description + %d sections re-spliced (project=%s)" % (changed, proj))
PY
[ $? -eq 0 ] || die "surgical patch of $REVIEW failed — restore from $REVIEW.pre-v0.9.3.bak"

# --- 4. Verify ---------------------------------------------------------------
ok=yes
grep -q "Coverage guard (before returning" "$GRILL" || { echo "  MISS: grill coverage guard"; ok=no; }
grep -q "adopt" "$GRILL"                             || { echo "  MISS: grill tier-override"; ok=no; }
grep -q "SINGLE SOURCE for these checks" "$REVIEW"   || { echo "  MISS: review production single-source"; ok=no; }
grep -q "review the diff/PR" "$REVIEW"               || { echo "  MISS: review frontmatter triggers"; ok=no; }
grep -q "$PROJ" "$REVIEW"                            || { echo "  MISS: project name lost in review"; ok=no; }
grep -q "{project}" "$REVIEW"                        && { echo "  BAD: literal {project} left in review"; ok=no; }

if [ "$ok" = yes ]; then
  log "v0.9.3 migration complete. Backups: *.pre-v0.9.3.bak (delete when satisfied)."
else
  die "verification failed — restore the .pre-v0.9.3.bak files and report this."
fi
