#!/bin/bash
# Migrate an Espalier v0.9.3 target repo to v0.9.4.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.9.4 is a security-skill clarity patch — no new lane, no new stage, no
# behaviour change to any gate or verdict. The security auditor's catch /
# false-positive behaviour is unchanged (eval 1.00 / 0 before and after):
#   - harness-security (per-project AGENT): frontmatter description gains
#     when-to-use + the five sensitive axes as trigger context; the P0 rubric and
#     the repo-audit "findings do not block" delta stop restating each other's
#     semantics and cross-reference one source instead.
#   - espalier-security (per-project SKILL): frontmatter description gains
#     when-to-use + trigger context.
#
# Both are per-project files created by init (or by migrate-v0.8.2-to-v0.9.0.sh)
# with {project} substituted, so a plugin update never reaches them and
# `bootstrap --force` does not re-copy them. v0.9.4 shipped these template
# improvements with no migration script, so no existing install ever received
# them. This script surgically re-splices exactly the changed regions.
#
# This migration:
#   1. Backs up harness-security.md + espalier-security SKILL.md → <file>.pre-v0.9.4.bak
#   2. Replaces the `description:` frontmatter line of each from the v0.9.4
#      template (substituting this project's name into the skill's).
#   3. Replaces the two changed body spans of harness-security.md.
#   4. Verifies everything landed.
#
# The frontmatter is edited LINE-WISE, never rewritten: an install created in
# `inherit` tools-mode has had its `tools:` line stripped, and re-copying the
# template's frontmatter would silently reintroduce it.
#
# Usage: bash migrate-v0.9.3-to-v0.9.4.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.9.4] $*"; }
die() { echo "[migrate-v0.9.4] ERROR: $*" >&2; exit 1; }

SECAGENT="espalier/agents/harness-security.md"
SECSKILL="espalier/skills/espalier-security/SKILL.md"

# --- Locate the installed espalier tree + the v0.9.4 plugin templates --------
[ -f "$SECAGENT" ] || die "run me from the TARGET project root ($SECAGENT not found).
If this install predates v0.9.0, run the v0.9.0 step first — it creates the agent."
[ -f "$SECSKILL" ] || die "$SECSKILL not found — run the v0.9.0 step first."

if [ -z "$PLUGIN_DIR" ]; then
  for c in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/marketplaces/espalier-engineering/espalier-engineering" \
    "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"; do
    [ -f "$c/skills/espalier-init/templates/agents/harness-security.md" ] && PLUGIN_DIR="$c" && break
  done
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin; pass --plugin-dir=<path to plugin root>."

TPL_AGENT="$PLUGIN_DIR/skills/espalier-init/templates/agents/harness-security.md"
TPL_SKILL="$PLUGIN_DIR/skills/espalier-init/templates/skills/espalier-security.md"
[ -f "$TPL_AGENT" ] || die "template not found: $TPL_AGENT"
[ -f "$TPL_SKILL" ] || die "template not found: $TPL_SKILL"

grep -qF "self-noops on changes with no sensitive surface" "$TPL_AGENT" || \
  die "template at $PLUGIN_DIR is not v0.9.4 (missing the sharpened agent description). Update the plugin first."

command -v python3 >/dev/null 2>&1 || die "python3 is required for the surgical frontmatter/body patch."

# --- Idempotency -------------------------------------------------------------
already_agent=no; already_skill=no
grep -qF "self-noops on changes with no sensitive surface" "$SECAGENT" 2>/dev/null && already_agent=yes
grep -qF "abuse-test recipe for" "$SECSKILL" 2>/dev/null && already_skill=yes
if [ "$already_agent" = yes ] && [ "$already_skill" = yes ]; then
  log "already at v0.9.4 (both security files carry the v0.9.4 markers) — nothing to do."
  exit 0
fi

# --- Discover this project's substituted name --------------------------------
# The "# Security Audit — <name>" heading of the installed skill is untouched by
# v0.9.4, so it holds the substituted name in every v0.9.3 install.
PROJ="$(sed -n 's/^# Security Audit — \(.*\)$/\1/p' "$SECSKILL" | head -1)"
if [ -z "$PROJ" ]; then
  PROJ="$(sed -n "s/.*checklist for \(.*\) — trust-boundary.*/\1/p" "$SECSKILL" | head -1)"
fi
[ -n "$PROJ" ] || die "could not discover this project's substituted name; aborting rather than write '{project}' literally."
log "project name discovered: $PROJ"

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  log "  1. back up $SECAGENT and $SECSKILL"
  log "  2. replace the description: line of both from the v0.9.4 template (project='$PROJ')"
  log "  3. re-splice 2 body spans of $SECAGENT (P0 rubric, repo-audit delta 5)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.9.4 security-skill patch to %s and %s? [y/N] " "$SECAGENT" "$SECSKILL"
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

cp "$SECAGENT" "$SECAGENT.pre-v0.9.4.bak"
cp "$SECSKILL" "$SECSKILL.pre-v0.9.4.bak"
log "backed up -> $SECAGENT.pre-v0.9.4.bak , $SECSKILL.pre-v0.9.4.bak"

# Record which body spans the ORIGINAL file actually carried. A span whose anchor
# is absent was customised by the project; the patch deliberately leaves it alone,
# so its post-check must WARN rather than fail — a hard error there would tell the
# user to restore from backup after a skip we chose on purpose.
SPAN_P0=no; SPAN_D5=no
grep -qE '^- \*\*P0\*\* — a client can move money' "$SECAGENT.pre-v0.9.4.bak" && SPAN_P0=yes
grep -qE '^5\. \*\*Findings do not block\.\*\*' "$SECAGENT.pre-v0.9.4.bak" && SPAN_D5=yes

PROJ="$PROJ" TPL_AGENT="$TPL_AGENT" TPL_SKILL="$TPL_SKILL" \
SECAGENT="$SECAGENT" SECSKILL="$SECSKILL" python3 <<'PY'
import os, re, sys

proj = os.environ["PROJ"]

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)

DESC = re.compile(r"(?m)^description:.*$")

def desc_of(text, what):
    """The single-line `description:` entry inside the leading frontmatter."""
    if not text.startswith("---"):
        sys.exit("ERROR: %s has no leading frontmatter" % what)
    end = text.index("\n---", 3)
    m = DESC.search(text, 0, end)
    if not m:
        sys.exit("ERROR: could not locate a description: line in %s frontmatter" % what)
    return m.group(0)

def replace_desc(inst, tpl, name):
    """Swap only the description LINE. Never rewrite frontmatter wholesale — an
    `inherit` tools-mode install has had its `tools:` line stripped, and copying
    the template's frontmatter would silently reintroduce it."""
    old = desc_of(inst, "installed " + name)
    new = desc_of(tpl, "template " + name).replace("{project}", proj)
    return inst.replace(old, new, 1), (old != new)

def span(text, start_re, end_re, what):
    m = re.search(r"(?ms)^" + start_re + r".*?(?=^" + end_re + r")", text)
    if not m:
        return None
    return m.group(0)

def replace_span(inst, tpl, start_re, end_re, what):
    t = span(tpl, start_re, end_re, what)
    if t is None:
        sys.exit("ERROR: template missing span %r" % what)
    i = span(inst, start_re, end_re, what)
    if i is None:
        print("  WARN: install missing span %r — customised? leaving it alone." % what)
        return inst, False
    if i == t:
        return inst, False
    return inst.replace(i, t, 1), True

# --- agent -------------------------------------------------------------------
inst = read(os.environ["SECAGENT"])
tpl = read(os.environ["TPL_AGENT"])
changed = 0

inst, c = replace_desc(inst, tpl, "harness-security"); changed += c

inst, c = replace_span(
    inst, tpl,
    r"- \*\*P0\*\* — a client can move money",
    r"- \*\*P1\*\*",
    "Priority Rubric P0 bullet",
); changed += c

inst, c = replace_span(
    inst, tpl,
    r"5\. \*\*Findings do not block\.\*\*",
    r"[ \t]*$",
    "Repo-Audit Mode delta 5",
); changed += c

if "{project}" in inst:
    sys.exit("ERROR: refusing to write a literal {project} into the agent")
write(os.environ["SECAGENT"], inst)
print("  harness-security: %d region(s) updated" % changed)

# --- skill -------------------------------------------------------------------
inst = read(os.environ["SECSKILL"])
tpl = read(os.environ["TPL_SKILL"])
inst, c = replace_desc(inst, tpl, "espalier-security")
if "{project}" in inst:
    sys.exit("ERROR: refusing to write a literal {project} into the skill")
write(os.environ["SECSKILL"], inst)
print("  espalier-security: description updated" if c else "  espalier-security: already current")
PY
rc=$?
if [ $rc -ne 0 ]; then
  die "surgical patch failed — restore from $SECAGENT.pre-v0.9.4.bak / $SECSKILL.pre-v0.9.4.bak"
fi

# --- Verify ------------------------------------------------------------------
pass=0; fail=0; warn=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
warn_check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else warn=$((warn+1)); echo "  ! $1 (span was customised — update it by hand)"; fi; }
# A span the install carries MUST be patched; one it customised away is warn-only.
span_check() { if [ "$1" = yes ]; then check "$2" "$3"; else warn_check "$2" "$3"; fi; }

log "verification"
check "agent description sharpened"     "grep -qF 'self-noops on changes with no sensitive surface' $SECAGENT"
span_check "$SPAN_P0" "agent P0 rubric cross-refs mode" "grep -qF 'see Repo-Audit Mode, delta 5' $SECAGENT"
span_check "$SPAN_D5" "agent delta 5 dedup'd"           "grep -qF 'Priority Rubric bar unchanged' $SECAGENT"
check "skill description sharpened"     "grep -qF 'abuse-test recipe for' $SECSKILL"
check "skill kept the project name"     "grep -qF '$PROJ' $SECSKILL"
check "no literal {project} in agent"   "! grep -qF '{project}' $SECAGENT"
check "no literal {project} in skill"   "! grep -qF '{project}' $SECSKILL"
check "agent kept its VERDICT sentinel" "grep -q '^VERDICT:' $SECAGENT || grep -qF 'VERDICT:' $SECAGENT"
check "agent kept Repo-Audit Mode"      "grep -qF '## Repo-Audit Mode' $SECAGENT"
# `tools:` must not be reintroduced into an inherit-mode install: it had no
# tools: line before, and the template does.
if grep -qF 'tools:' "$SECAGENT.pre-v0.9.4.bak"; then
  check "agent kept its tools: line"    "grep -qF 'tools:' $SECAGENT"
else
  check "agent stayed tools-less (inherit mode)" "! grep -qF 'tools:' $SECAGENT"
fi

echo
log "Verification: $pass passed, $fail failed, $warn warn-only"
[ "$fail" -eq 0 ] || die "verification failed — restore from the .pre-v0.9.4.bak files."
if [ "$warn" -gt 0 ]; then
  log "$warn customised span(s) left untouched — the v0.9.4 wording is a clarity"
  log "improvement, not a behaviour change, so this is safe to leave or hand-merge."
fi
log "v0.9.4 migration complete. Backups: *.pre-v0.9.4.bak (delete when satisfied)."
