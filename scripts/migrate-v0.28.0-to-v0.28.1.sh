#!/bin/bash
# Migrate a v0.28.0 Espalier install to v0.28.1.
#
# v0.28.1 is the trim patch: the shipped agent, skill, rule, and stage files
# say the same things in fewer lines. Contract-equal to v0.28.0 — every rule,
# gate, rubric, sentinel, tag, cap, path, and heading is unchanged; only
# restated rationale, history notes, and doubled sentences went. NOTHING here
# sets a budget.
#
# Mechanism (new in this release, reusable for any text-only refresh): the
# release ships the exact template diff (scripts/patches/v0.28.0-to-v0.28.1.patch,
# generated from the plugin's own git history at release time). Each file's
# hunks are checked one by one with `git apply --check` and the file is
# handled ALL-OR-NOTHING:
#   - a hunk whose v0.28.0 text is present applies; a hunk whose v0.28.1 text
#     is ALREADY present (an earlier migration extracted that block from the
#     current templates, or a prior run of this script) is a no-op — so a
#     file still at the v0.28.0 shape (with its init-time `{project_name}`
#     substitution) ends byte-identical to a fresh install (backup →
#     <file>.pre-v0.28.1.bak), and a file already trimmed is left alone;
#   - a file with ANY hunk that fits neither shape is customised: it is left
#     UNTOUCHED, with a record in espalier/.migrations-skipped (label
#     v0.28.1-trim-<path>). The trim is text-only, so a skipped file loses
#     nothing — port the shorter wording by hand only if you want it.
#   No config key, no new instruction-file line, no hooks, no symlinks, no
#   validation check.
#
# Usage:
#   bash migrate-v0.28.0-to-v0.28.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.28.0→v0.28.1] $*"; }
die() { echo "[migrate v0.28.0→v0.28.1] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."
command -v git >/dev/null 2>&1 || die "git is required (the trim is applied with 'git apply')."
command -v python3 >/dev/null 2>&1 || die "python3 is required (splits the shipped patch per file)."

# --- Locate plugin (probe: this release's own patch file) --------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -f "$_self_root/scripts/patches/v0.28.0-to-v0.28.1.patch" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
PATCH="$PLUGIN_DIR/scripts/patches/v0.28.0-to-v0.28.1.patch"
[ -f "$PATCH" ] || die "plugin dir '$PLUGIN_DIR' is not v0.28.1 (no scripts/patches/v0.28.0-to-v0.28.1.patch)."
SKIPFILE="espalier/.migrations-skipped"

# --- Split the shipped patch per installed file ------------------------------
# Python rewrites each file's header from the template path to the installed
# path, substitutes `{project_name}` / `{project}` with the value this install
# used (read back from the installed file through the template's own line
# shape), and writes one piece per file plus a manifest:
#   <n>\t<installed path>\t<ok|noname|unmapped>
WORK=$(mktemp -d -t v0281.XXXX)
trap 'rm -rf "$WORK"' EXIT
python3 - "$PATCH" "$WORK" <<'PYEND'
import re, sys, os
patch, work = sys.argv[1], sys.argv[2]
text = open(patch, encoding="utf-8").read()
pieces = re.split(r"(?m)^(?=diff --git )", text)
TPL = "skills/espalier-init/templates/"
def installed(rel):
    if rel.startswith("agents/") or rel.startswith("rules/"): return "espalier/" + rel
    if rel in ("agent.md", "pipeline.md"): return "espalier/" + rel
    if rel == "scout-prompts.md": return "espalier/.scout-prompts.md"
    if rel.startswith("skills/espalier-stages/"): return "espalier/skills/espalier/stages/" + rel[len("skills/espalier-stages/"):]
    if rel.startswith("skills/espalier-coding-references/"): return "espalier/skills/espalier-coding/references/" + rel[len("skills/espalier-coding-references/"):]
    if rel == "skills/espalier-coding-spec.md": return None            # a spec template, never installed as-is
    m = re.fullmatch(r"skills/([a-z-]+)\.md", rel)
    if m: return "espalier/skills/%s/SKILL.md" % m.group(1)
    return None
manifest = []
n = 0
for piece in pieces:
    if not piece.startswith("diff --git "): continue
    m = re.match(r"diff --git (?:a/)?(\S+) (?:b/)?(\S+)\n", piece)
    rel = m.group(1)
    if not rel.startswith(TPL): continue
    rel = rel[len(TPL):]
    dst = installed(rel)
    n += 1
    if dst is None:
        manifest.append((n, rel, "unmapped", 0)); continue
    body = piece.split("\n", 1)[1]
    hdr = "diff --git a/%s b/%s\n" % (dst, dst)   # a/ b/ prefixes: git apply strips one component
    lines = body.split("\n")
    out = []
    for ln in lines:
        if ln.startswith("--- a/") or ln.startswith("--- " + TPL): ln = "--- a/" + dst
        elif ln.startswith("+++ b/") or ln.startswith("+++ " + TPL): ln = "+++ b/" + dst
        elif ln.startswith("index "): continue
        elif ln.startswith("@@ "): ln = ln[:ln.index("@@", 3) + 2]   # drop the function-context tail (ignored by git apply)
        out.append(ln)
    body = "\n".join(out)
    status = "ok"
    tokens = sorted(set(re.findall(r"\{project(?:_name)?\}", body)))
    if tokens and os.path.isfile(dst):
        inst = open(dst, encoding="utf-8", errors="replace").read().split("\n")
        for tok in tokens:
            name = None
            for ln in out:
                if (ln.startswith(" ") or ln.startswith("-")) and tok in ln:
                    src = ln[1:]
                    pat = "^" + re.escape(src).replace(re.escape(tok), "(.+?)") + "$"
                    for il in inst:
                        mm = re.match(pat, il)
                        if mm: name = mm.group(1); break
                if name is not None: break
            if name is None: status = "noname"; break
            body = body.replace(tok, name)
    # one piece per hunk (each with the file header) so a hunk an earlier
    # migration already landed can be recognised on its own
    blines = body.split("\n")
    pre = []; hunks = []; cur = None
    for ln in blines:
        if ln.startswith("@@ "):
            cur = [ln]; hunks.append(cur)
        elif cur is None: pre.append(ln)
        else: cur.append(ln)
    if hunks and hunks[-1] and hunks[-1][-1] == "": hunks[-1].pop()
    for k, h in enumerate(hunks, 1):
        open(os.path.join(work, "%d.%d.patch" % (n, k)), "w", encoding="utf-8").write(hdr + "\n".join(pre) + "\n" + "\n".join(h) + "\n")
    manifest.append((n, dst, status, len(hunks)))
with open(os.path.join(work, "manifest"), "w") as f:
    for n, dst, st, hk in manifest: f.write("%d\t%s\t%s\t%d\n" % (n, dst, st, hk))
PYEND
[ -s "$WORK/manifest" ] || die "the shipped patch names no template file — refusing to guess."

# --- Classify every file (also the idempotency check) ------------------------
# done     : already at the v0.28.1 shape (the reverse patch applies cleanly)
# apply    : matches the v0.28.0 shape (the patch applies cleanly)
# recorded : customised, already recorded in espalier/.migrations-skipped
# skip     : customised, not yet recorded
# absent   : the install has no such file — nothing to do
# hunk_state PIECE → done (reverse applies: v0.28.1 text present) | apply
# (forward applies: v0.28.0 text present) | none (neither: customised)
hunk_state() {
  if git apply --check --whitespace=nowarn -R "$1" >/dev/null 2>&1; then echo done
  elif git apply --check --whitespace=nowarn "$1" >/dev/null 2>&1; then echo apply
  else echo none; fi
}
classify() {  # $1 = file index, $2 = installed path, $3 = status from python, $4 = hunk count
  [ -f "$2" ] || { echo absent; return; }
  if grep -qF "v0.28.1-trim-$2:" "$SKIPFILE" 2>/dev/null; then echo recorded; return; fi
  [ "$3" = ok ] || { echo skip; return; }
  local k st any_apply=no
  for k in $(seq 1 "$4"); do
    st=$(hunk_state "$WORK/$1.$k.patch")
    case "$st" in none) echo skip; return ;; apply) any_apply=yes ;; esac
  done
  [ "$any_apply" = yes ] && echo apply || echo done
}
PLAN=""; N_APPLY=0; N_SKIP=0
while IFS=$'\t' read -r n dst st hk; do
  [ "$st" = unmapped ] && continue
  c=$(classify "$n" "$dst" "$st" "$hk")
  PLAN="$PLAN
$n	$dst	$c	$hk"
  case "$c" in apply) N_APPLY=$((N_APPLY+1)) ;; skip) N_SKIP=$((N_SKIP+1)) ;; esac
done < "$WORK/manifest"

if [ "$N_APPLY" -eq 0 ] && [ "$N_SKIP" -eq 0 ]; then
  log "already at v0.28.1 (every shipped file trimmed, recorded, or absent). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — per-file plan (apply = trim lands byte-for-byte; skip = customised, left untouched + recorded):"
  echo "$PLAN" | awk -F'\t' 'NF==4 && $3!="absent" {printf "  %-9s %s\n", $3, $2}'
  log "DRY RUN — $N_APPLY file(s) would be trimmed, $N_SKIP customised file(s) would be recorded in $SKIPFILE. No backups, no writes."
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - apply the v0.28.1 trim to $N_APPLY file(s) that still match the v0.28.0 templates (backups: <file>.pre-v0.28.1.bak)"
  echo "  - leave $N_SKIP customised file(s) untouched and record them in $SKIPFILE (text-only trim — nothing lost)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.28.1.bak" ] || cp "$1" "$1.pre-v0.28.1.bak"; }
record_skip() {  # $1 = installed path
  log "WARN: $1 is customised past the v0.28.0 shape — left untouched (the trim is text-only; nothing to port)."
  grep -qF "v0.28.1-trim-$1:" "$SKIPFILE" 2>/dev/null \
    || echo "v0.28.1-trim-$1: customised, trim not applied (text-only — no action needed)" >> "$SKIPFILE"
}

# --- Apply --------------------------------------------------------------------
while IFS=$'\t' read -r n dst c hk; do
  [ -n "${n:-}" ] || continue
  case "$c" in
    apply)
      backup_once "$dst"
      for k in $(seq 1 "$hk"); do
        [ "$(hunk_state "$WORK/$n.$k.patch")" = apply ] || continue
        git apply --whitespace=nowarn "$WORK/$n.$k.patch" || die "git apply failed on $dst (hunk $k) after a clean --check (backup at $dst.pre-v0.28.1.bak)"
      done
      log "trimmed $dst" ;;
    skip) record_skip "$dst" ;;
  esac
done <<PLANEOF
$PLAN
PLANEOF

# --- .gitignore: migration backups (already there from #35 on most installs)
if ! grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '# espalier migration backups (one per file per migration)\n*.pre-v0.*.bak\n' >> .gitignore
  log "added '*.pre-v0.*.bak' to .gitignore"
fi

# --- Verify ------------------------------------------------------------------
while IFS=$'\t' read -r n dst c hk; do
  [ "${c:-}" = apply ] || continue
  for k in $(seq 1 "$hk"); do
    [ "$(hunk_state "$WORK/$n.$k.patch")" = done ] \
      || die "post-migration verification failed: $dst hunk $k is not at the v0.28.1 shape"
  done
done <<PLANEOF
$PLAN
PLANEOF

if grep -q 'v0.28.1-trim-' "$SKIPFILE" 2>/dev/null; then
  log "done with skips — see $SKIPFILE (customised files keep their longer v0.28.0 wording; nothing to port)."
fi
log "done. v0.28.1 applied — backups at <file>.pre-v0.28.1.bak (gitignored)."
log "Every rule, gate, cap, tag, and path is unchanged; the files only read shorter."
exit 0
