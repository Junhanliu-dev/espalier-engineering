#!/usr/bin/env bash
# espalier-outside.sh — outside mode: the espalier/ tree lives OUTSIDE the
# project repo, and the project's git never sees it.
#
#   <parent>/espalier-main/<name>/           the OUTSIDE ROOT
#     .espalier-origin                       one line: the project's absolute path
#     .git/                                  its own local repo — no remote, ever
#     espalier/                              the whole tree
#   <project>/espalier -> ../espalier-main/<name>/espalier   (relative symlink,
#                                            excluded via .git/info/exclude)
#
# Every `espalier/...` path in the skills, hooks and settings keeps working
# through the symlink; nothing is rewritten. What the project repo would have
# tracked (the symlink, the .claude/ wiring, CLAUDE.local.md, settings.local.json)
# is listed in .git/info/exclude — local to this clone, never committed.
#
#   espalier-outside.sh prepare   <project> [--main=<dir>] [--name=<n>]
#   espalier-outside.sh discover  <project>
#   espalier-outside.sh status    <project>
#   espalier-outside.sh commit    <project> <msg> [rel-paths-under-espalier...]
#   espalier-outside.sh exclude-add      <project> <entry>...
#   espalier-outside.sh exclude-defaults <project>      the base + platform entries
#   espalier-outside.sh exclude-remove   <project>
#   espalier-outside.sh gitignore-entries <project>     the sidecar list (one definition)
#   espalier-outside.sh repot-out <project> [--main=<dir>] [--name=<n>]
#   espalier-outside.sh repot-in  <project>
#
# The project also remembers its root in its LOCAL git config
# (`git config --local espalier.outside-root`), which survives `git clean -fdx`
# and is never committed — so a non-default root (--main / --name) is found
# again after the symlink is gone, not only the default sibling.
#
# Exit codes: 0 ok · 2 usage · 3 collision / wrong mode · 4 no install · 6 in flight
set -u

CMD="${1:-}"
PROJECT_ARG="${2:-}"
[ -n "$CMD" ] && [ -n "$PROJECT_ARG" ] || {
  sed -n '2,27p' "$0" >&2; exit 2
}
shift 2

MARK_OPEN="# >>> espalier (outside mode) >>>"
MARK_CLOSE="# <<< espalier (outside mode) <<<"
GITIGNORE_ENTRIES="espalier/.commit-index.tsv
espalier/.drift-state.tsv*
espalier/.drift.log
espalier/.drift-report.md
espalier/.doctor-last-run
espalier/.drift-overrides.log
espalier/.dep-audit-cache
espalier/.simple/
*.pre-v0.*.bak"
GITATTR_ENTRY="espalier/.ask-gaps.tsv merge=union"

log() { echo "[outside] $*"; }
tracked() { git -C "$PROJECT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }
die() { echo "[outside] ERROR: $*" >&2; exit "${2:-1}"; }

_abs() {  # physical absolute path of an existing dir
  ( cd "$1" 2>/dev/null && pwd -P )
}

_relpath() {  # _relpath TARGET BASE — TARGET relative to BASE (both absolute)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2" && return 0
  fi
  local t="$1" b="$2" up="" common
  common="$b"
  while [ -n "$common" ] && [ "${t#"$common"/}" = "$t" ] && [ "$t" != "$common" ]; do
    common="${common%/*}"; up="${up}../"
  done
  if [ -z "$common" ]; then printf '%s\n' "$t"; return 0; fi
  if [ "$t" = "$common" ]; then printf '%s\n' "${up%/}"; return 0; fi
  printf '%s%s\n' "$up" "${t#"$common"/}"
}

PROJECT="$(_abs "$PROJECT_ARG")" || die "project dir not found: $PROJECT_ARG" 2
cd "$PROJECT" || die "cannot cd to $PROJECT" 2
git -C "$PROJECT" rev-parse --show-toplevel >/dev/null 2>&1 || die "$PROJECT is not a git repository" 2

MAIN=""; NAME=""
for arg in "$@"; do
  case "$arg" in
    --main=*) MAIN="${arg#--main=}" ;;
    --name=*) NAME="${arg#--name=}" ;;
    *) ;;   # positional args are consumed per subcommand
  esac
done

default_root() {
  local m="$MAIN" n="$NAME"
  [ -n "$m" ] || m="$(dirname "$PROJECT")/espalier-main"
  [ -n "$n" ] || n="$(basename "$PROJECT")"
  case "$m" in /*) ;; *) m="$PROJECT/$m" ;; esac
  printf '%s/%s\n' "${m%/}" "$n"
}

exclude_file() {
  local f
  f="$(git -C "$PROJECT" rev-parse --git-path info/exclude 2>/dev/null)" || f=".git/info/exclude"
  case "$f" in /*) ;; *) f="$PROJECT/$f" ;; esac
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || : > "$f"
  printf '%s\n' "$f"
}

exclude_add() {  # exclude_add ENTRY... — idempotent, inside the marker block
  local f tmp e
  f="$(exclude_file)"
  if ! grep -qxF "$MARK_OPEN" "$f"; then
    if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then printf '\n' >> "$f"; fi
    printf '%s\n%s\n' "$MARK_OPEN" "$MARK_CLOSE" >> "$f"
  fi
  for e in "$@"; do
    [ -n "$e" ] || continue
    grep -qxF -- "$e" "$f" && continue
    tmp="$(mktemp)" || return 1
    awk -v e="$e" -v cl="$MARK_CLOSE" '$0 == cl { print e } { print }' "$f" > "$tmp" && mv "$tmp" "$f"
  done
}

exclude_remove() {  # drop the whole marker block
  local f tmp
  f="$(exclude_file)"
  grep -qxF "$MARK_OPEN" "$f" || return 0
  tmp="$(mktemp)" || return 1
  awk -v o="$MARK_OPEN" -v c="$MARK_CLOSE" '$0 == o { inb = 1; next } $0 == c { inb = 0; next } !inb { print }' "$f" > "$tmp" && mv "$tmp" "$f"
}

base_excludes() {  # the entries every outside install needs (claude platform + sidecars)
  printf '%s\n' "/espalier" "/CLAUDE.local.md" "/.claude/settings.local.json*" "/.claude/settings.json.espalier-backup-*" \
    "/.claude/rules/espalier-*.md" "/.claude/skills/espalier*" "/.claude/agents/harness-*.md" \
    "*.pre-v0.*.bak"
}

platform_excludes() {  # from espalier/.platforms, when it exists
  local p
  p="$(head -1 "$PROJECT/espalier/.platforms" 2>/dev/null | tr -d '[:space:]')"
  case "$p" in *codex*)   printf '%s\n' "/.agents/skills/espalier*" "/.codex/agents/harness-*.toml" ;; esac
  case "$p" in *copilot*) printf '%s\n' "/.github/skills/espalier*" "/.github/agents/harness-*.agent.md" ;; esac
}

git_out() {  # git in the outside root, with an identity fallback (no global config needed)
  local root="$1"; shift
  if [ -n "$(git -C "$root" config user.email 2>/dev/null)" ]; then
    git -C "$root" "$@"
  else
    git -C "$root" -c user.name=espalier -c user.email=espalier@localhost "$@"
  fi
}

ensure_repo() {  # ensure_repo ROOT — git init when missing; the sidecars ignored there too
  if [ ! -d "$1/.git" ]; then
    git -C "$1" init -q || die "git init failed in $1"
    log "initialised a local git repo in $1 (no remote — history stays on this machine)"
  fi
  if [ ! -f "$1/.gitignore" ]; then
    { echo "# espalier per-clone sidecars (caches, drift state, the --simple scratch dir)"; printf '%s\n' "$GITIGNORE_ENTRIES"; } > "$1/.gitignore"
  fi
}

write_symlink() {  # write_symlink ROOT — <project>/espalier -> relative ROOT/espalier
  local rel
  rel="$(_relpath "$1/espalier" "$PROJECT")"
  if [ -e "$PROJECT/espalier" ] && [ ! -L "$PROJECT/espalier" ]; then
    die "$PROJECT/espalier is a real directory (an inside install). Move it with /espalier-repot, not prepare." 3
  fi
  ln -sfn "$rel" "$PROJECT/espalier" || die "could not write the espalier symlink"
}

config_set_root() {  # append outside-root: when the config exists and lacks it
  local cfg="$PROJECT/espalier/.espalier-config"
  [ -f "$cfg" ] || return 0
  grep -q '^outside-root:' "$cfg" && return 0
  if [ -s "$cfg" ] && [ -n "$(tail -c1 "$cfg")" ]; then printf '\n' >> "$cfg"; fi
  printf '\n# Outside mode (v0.30): the espalier/ tree lives here; the project holds a gitignored symlink.\noutside-root: %s\n' "$1" >> "$cfg"
}

config_sync_root() {  # config_sync_root ROOT — rewrite a stale outside-root: (the project moved with its sibling)
  local cfg="$PROJECT/espalier/.espalier-config" cur tmp
  [ -f "$cfg" ] || return 0
  cur="$(grep -m1 '^outside-root:' "$cfg" | awk '{print $2}')"
  [ -n "$cur" ] || { config_set_root "$1"; return 0; }
  [ "$cur" = "$1" ] && return 0
  tmp="$(mktemp)" || return 1
  awk -v r="$1" '/^outside-root:/ { print "outside-root: " r; next } { print }' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
  log "outside-root: updated $cur -> $1 (the install moved; the relative symlink never broke)"
}

config_drop_root() {
  local cfg="$PROJECT/espalier/.espalier-config" tmp
  [ -f "$cfg" ] || return 0
  tmp="$(mktemp)" || return 1
  grep -vE '^(outside-root:|# Outside mode \(v0\.30\))' "$cfg" > "$tmp"; mv "$tmp" "$cfg"
}

gitconfig_set_root()  { git -C "$PROJECT" config --local espalier.outside-root "$1" 2>/dev/null || true; }
gitconfig_get_root()  { git -C "$PROJECT" config --local --get espalier.outside-root 2>/dev/null || true; }
gitconfig_drop_root() { git -C "$PROJECT" config --local --unset-all espalier.outside-root 2>/dev/null || true; }

# The CODEOWNERS block bootstrap writes (ESPALIER OWNERS v1) names espalier/
# paths — espalier-related content the repo would keep carrying after a move.
strip_codeowners_block() {
  local c tmp
  for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    [ -f "$PROJECT/$c" ] || continue
    grep -qF '>>> ESPALIER OWNERS v1 >>>' "$PROJECT/$c" || continue
    tmp="$(mktemp)" || return 1
    awk '/^# >>> ESPALIER OWNERS v1 >>>/ { inb = 1; next } /^# <<< ESPALIER OWNERS v1 <<</ { inb = 0; next } !inb { print }' "$PROJECT/$c" > "$tmp"
    if grep -q '[^[:space:]]' "$tmp"; then
      mv "$tmp" "$PROJECT/$c"; git -C "$PROJECT" add -u -- "$c" >/dev/null 2>&1 || true
      log "  stripped the ESPALIER OWNERS block from $c"
    else
      rm -f "$tmp"; git -C "$PROJECT" rm -q --cached --ignore-unmatch -- "$c" >/dev/null 2>&1 || true; rm -f "$PROJECT/$c"
      log "  removed $c (it held only the ESPALIER OWNERS block)"
    fi
  done
}

# Where bootstrap put the post-merge dispatcher — the same resolution it uses:
# husky → .husky/post-merge; core.hooksPath → <path>/post-merge; else .git/hooks.
hook_dst() {
  local hp
  if [ -d "$PROJECT/.husky" ] && { [ -f "$PROJECT/.husky/_/husky.sh" ] || [ -f "$PROJECT/.husky/install.mjs" ] \
       || { [ -f "$PROJECT/package.json" ] && grep -q '"husky"' "$PROJECT/package.json" 2>/dev/null; }; }; then
    echo ".husky/post-merge"; return 0
  fi
  hp="$(git -C "$PROJECT" config core.hooksPath 2>/dev/null || true)"
  if [ -n "$hp" ]; then case "$hp" in /*) echo "$hp/post-merge" ;; *) echo "${hp%/}/post-merge" ;; esac; return 0; fi
  echo ".git/hooks/post-merge"
}

# The outside root this project is linked to, or "" when it is an inside install.
linked_root() {
  local link tgt
  [ -L "$PROJECT/espalier" ] || return 1
  link="$(readlink "$PROJECT/espalier")"
  case "$link" in /*) tgt="$link" ;; *) tgt="$PROJECT/$link" ;; esac
  tgt="$(_abs "$tgt")" || return 1
  [ -f "$(dirname "$tgt")/.espalier-origin" ] || return 1
  dirname "$tgt"
}

# A root the config names (survives a deleted symlink only while the config is
# reachable, i.e. never — kept for status output on a healthy install).
configured_root() {
  grep -m1 '^outside-root:' "$PROJECT/espalier/.espalier-config" 2>/dev/null | awk '{print $2}'
}

# Non-terminal changes and unmerged espalier PRs — repot never moves live state.
inflight_list() {  # inflight_list CHANGES_DIR
  local st status prs
  while IFS= read -r st; do
    [ -f "$st" ] || continue
    status="$(grep -E '^- Status:' "$st" | head -1 | sed 's/^- Status:[[:space:]]*//' | tr -d '[:space:]')"
    case "$status" in
      COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED|PARTIAL_FIX|"") ;;
      *) printf '  - %s (Status: %s)\n' "${st#"$1"/}" "$status"; continue ;;
    esac
    # An espalier PR recorded but not merged: the projection branch may still be live.
    prs="$(sed -n '/^## Pull Requests/,/^$/p' "$st" | grep -E '^\| espalier \|' | grep -vE 'merged|local:' || true)"
    if [ -n "$prs" ] && [ "$status" != "COMPLETE" ]; then
      printf '  - %s (espalier PR open)\n' "${st#"$1"/}"
    fi
  done << EOF_ST
$(find "$1" -mindepth 3 -maxdepth 3 -name pipeline-state.md -not -path "*/_template/*" 2>/dev/null)
EOF_ST
}

refuse_inflight() {  # refuse_inflight CHANGES_DIR
  local l
  [ -d "$1" ] || return 0
  l="$(inflight_list "$1")"
  [ -z "$l" ] && return 0
  echo "[outside] ERROR: changes are in flight — finish or abort them first, then re-run:" >&2
  printf '%s\n' "$l" >&2
  exit 6
}

# ── settings.json <-> settings.local.json hook moves (python3) ───────────────
move_hooks() {  # move_hooks SRC DST — move the espalier hook entries from SRC into DST
  [ -f "$1" ] || return 0
  SRC="$1" DST="$2" python3 - << 'PYMOVE'
import json, os, sys, tempfile
src, dst = os.environ["SRC"], os.environ["DST"]
def load(p):
    if not os.path.exists(p): return {}
    with open(p) as f:
        try: return json.load(f)
        except json.JSONDecodeError as e:
            print(f"[outside] ERROR: {p} is invalid JSON: {e}", file=sys.stderr); sys.exit(1)
def write(p, data):
    d = os.path.dirname(p) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp", prefix=".settings-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2); f.write("\n")
    os.replace(tmp, p)
def is_esp(entry):
    return any("espalier/hooks" in (h.get("command") or "") for h in entry.get("hooks", []))
def same(a, b):
    return a.get("matcher") == b.get("matcher") and \
        {h.get("command") for h in a.get("hooks", [])} & {h.get("command") for h in b.get("hooks", [])}
s = load(src); moved = {}
hooks = s.get("hooks")
if isinstance(hooks, dict):
    for ev in list(hooks):
        keep = [e for e in hooks[ev] if not is_esp(e)]
        take = [e for e in hooks[ev] if is_esp(e)]
        if take: moved[ev] = take
        if keep: hooks[ev] = keep
        else: del hooks[ev]
    if not hooks: del s["hooks"]
if not moved:
    print("[outside]   no espalier hooks in " + src); sys.exit(0)
d = load(dst); dh = d.setdefault("hooks", {})
added = 0
for ev, entries in moved.items():
    ex = dh.setdefault(ev, [])
    for e in entries:
        if any(same(e, x) for x in ex): continue
        ex.append(e); added += 1
write(dst, d)
write(src, s)
print(f"[outside]   moved {sum(len(v) for v in moved.values())} espalier hook entr{'y' if added == 1 else 'ies'}: {src} -> {dst}")
PYMOVE
}

# ── the `## Espalier` section: CLAUDE.md <-> CLAUDE.local.md ──────────────────
move_section() {  # move_section SRC DST — cut the `## Espalier` section out of SRC, append to DST
  [ -f "$1" ] || return 0
  grep -q '^## Espalier[[:space:]]*$' "$1" || return 0
  local sec rest
  sec="$(mktemp)"; rest="$(mktemp)"
  awk -v sec="$sec" '
    /^## Espalier[[:space:]]*$/ { on = 1 }
    on && /^## / && !/^## Espalier[[:space:]]*$/ { on = 0 }
    { if (on) print > sec; else print }
  ' "$1" > "$rest"
  # trim trailing blank lines left where the section was cut
  awk 'NF { blank = 0 } !NF { blank++ } { lines[NR] = $0 } END { n = NR - blank; for (i = 1; i <= n; i++) print lines[i] }' "$rest" > "$1"
  [ -s "$1" ] || rm -f "$1"
  if [ -f "$2" ] && grep -q '^## Espalier[[:space:]]*$' "$2"; then
    log "  $2 already carries the Espalier section — the copy in $1 was dropped"
  else
    if [ -s "$2" ] && [ -n "$(tail -c1 "$2")" ]; then printf '\n' >> "$2"; fi
    printf '\n' >> "$2"; cat "$sec" >> "$2"
    log "  moved the ## Espalier section: $1 -> $2"
  fi
  rm -f "$sec" "$rest"
}

gitignore_remove_entries() {
  local f tmp
  f="$PROJECT/.gitignore"; [ -f "$f" ] || return 0
  tmp="$(mktemp)" || return 1
  printf '%s\n' "$GITIGNORE_ENTRIES" | awk 'NR==FNR { drop[$0] = 1; next } !($0 in drop)' - "$f" > "$tmp"
  if grep -q . "$tmp"; then mv "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
  f="$PROJECT/.gitattributes"; [ -f "$f" ] || return 0
  tmp="$(mktemp)" || return 1
  grep -vxF -- "$GITATTR_ENTRY" "$f" > "$tmp"
  if grep -q . "$tmp"; then mv "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
}

gitignore_add_entries() {
  local e
  printf '%s\n' "$GITIGNORE_ENTRIES" | while IFS= read -r e; do
    grep -qxF -- "$e" "$PROJECT/.gitignore" 2>/dev/null && continue
    if [ -s "$PROJECT/.gitignore" ] && [ -n "$(tail -c1 "$PROJECT/.gitignore")" ]; then printf '\n' >> "$PROJECT/.gitignore"; fi
    printf '%s\n' "$e" >> "$PROJECT/.gitignore"
  done
  if ! grep -qxF -- "$GITATTR_ENTRY" "$PROJECT/.gitattributes" 2>/dev/null; then
    if [ -s "$PROJECT/.gitattributes" ] && [ -n "$(tail -c1 "$PROJECT/.gitattributes")" ]; then printf '\n' >> "$PROJECT/.gitattributes"; fi
    printf '%s\n' "$GITATTR_ENTRY" >> "$PROJECT/.gitattributes"
  fi
}

# The post-merge dispatcher block in a TRACKED husky hook has to go: it is
# espalier-related content the repo would carry. bootstrap --wire-only --outside
# re-installs it where git reads untracked hooks.
strip_tracked_dispatcher() {
  local rel f tmp
  rel="$(hook_dst)"
  case "$rel" in /*) f="$rel" ;; *) f="$PROJECT/$rel" ;; esac
  [ -f "$f" ] || return 0
  tracked "$rel" || return 0      # an untracked hook (.git/hooks, an untracked dir) carries nothing the repo ships
  grep -q 'ESPALIER_POSTMERGE_DISPATCH' "$f" || return 0
  tmp="$(mktemp)" || return 1
  awk '/^# >>> ESPALIER_POSTMERGE_DISPATCH/ { inb = 1; next } /^# <<< ESPALIER_POSTMERGE_DISPATCH/ { inb = 0; skipexit = 1; next } inb { next } skipexit && /^exit 0$/ { skipexit = 0; next } { print }' "$f" > "$tmp"
  if grep -vq '^#!/bin/bash$' "$tmp" && grep -q . "$tmp"; then mv "$tmp" "$f"; git -C "$PROJECT" add -u -- "$rel" >/dev/null 2>&1 || true; log "  stripped the post-merge dispatcher from the tracked $rel"
  else rm -f "$tmp"; git -C "$PROJECT" rm -q --cached --ignore-unmatch -- "$rel" >/dev/null 2>&1 || true; rm -f "$f"; log "  removed $rel (it held only the espalier dispatcher)"; fi
}

case "$CMD" in
  # ─────────────────────────────────────────────────────────────── prepare ──
  prepare)
    ROOT="$(default_root)"
    if [ -e "$PROJECT/espalier" ] && [ ! -L "$PROJECT/espalier" ]; then
      die "$PROJECT/espalier is a real directory (an inside install). Move it with /espalier-repot, not prepare." 3
    fi
    # An existing link is never repointed: a re-run with other (or no) flags
    # must not move the project onto a second, empty root.
    if CUR="$(linked_root)" && [ "$CUR" != "$(cd "$ROOT" 2>/dev/null && pwd -P || printf '%s' "$ROOT")" ]; then
      die "$PROJECT is already linked to $CUR — prepare never repoints a link. Use that root (no --main/--name), or move it with /espalier-repot." 3
    fi
    if [ -d "$ROOT" ]; then
      if [ -f "$ROOT/.espalier-origin" ]; then
        ORIGIN="$(head -1 "$ROOT/.espalier-origin" | tr -d '\r\n')"
        [ "$ORIGIN" = "$PROJECT" ] || die "$ROOT belongs to another project ($ORIGIN). Pass --name=<other> (init: --outside-name=<other>) to keep them apart." 3
      elif [ -n "$(ls -A "$ROOT" 2>/dev/null)" ]; then
        die "$ROOT exists, is not empty, and carries no .espalier-origin — refusing to adopt it. Empty it or pass --name=<other>." 3
      fi
    fi
    mkdir -p "$ROOT/espalier" || die "could not create $ROOT/espalier"
    [ -f "$ROOT/.espalier-origin" ] || printf '%s\n' "$PROJECT" > "$ROOT/.espalier-origin"
    ensure_repo "$ROOT"
    write_symlink "$ROOT"
    set -f; exclude_add $(base_excludes); set +f
    config_sync_root "$ROOT"
    gitconfig_set_root "$ROOT"
    log "outside root: $ROOT (project: $PROJECT; symlink espalier -> $(readlink "$PROJECT/espalier"))"
    printf '%s\n' "$ROOT"
    ;;

  # ────────────────────────────────────────────────────────────── discover ──
  discover)
    if [ -d "$PROJECT/espalier" ] && [ ! -L "$PROJECT/espalier" ]; then
      echo "inside $PROJECT/espalier"; exit 0
    fi
    if ROOT="$(linked_root)"; then
      # The symlink IS the link: a project moved together with its sibling
      # still points at its own root, so the origin follows the project.
      if [ "$(head -1 "$ROOT/.espalier-origin" | tr -d '\r\n')" != "$PROJECT" ]; then
        printf '%s\n' "$PROJECT" > "$ROOT/.espalier-origin"
        log ".espalier-origin: updated to $PROJECT (the install moved)"
      fi
      config_sync_root "$ROOT"; gitconfig_set_root "$ROOT"
      echo "outside $ROOT"; exit 0
    fi
    # The symlink is gone. The project's local git config remembers a
    # non-default root; the default sibling is the fallback.
    for ROOT in "$(gitconfig_get_root)" "$(default_root)"; do
      [ -n "$ROOT" ] || continue
      if [ -f "$ROOT/.espalier-origin" ] && [ "$(head -1 "$ROOT/.espalier-origin" | tr -d '\r\n')" = "$PROJECT" ] && [ -d "$ROOT/espalier" ]; then
        [ -L "$PROJECT/espalier" ] && rm -f "$PROJECT/espalier"   # a dangling link
        write_symlink "$ROOT"
        set -f; exclude_add $(base_excludes) $(platform_excludes); set +f
        config_sync_root "$ROOT"; gitconfig_set_root "$ROOT"
        echo "relinked $ROOT"; exit 0
      fi
    done
    echo "no espalier install — run /espalier-init first" >&2
    exit 4
    ;;

  # ──────────────────────────────────────────────────────────────── status ──
  status)
    if [ -d "$PROJECT/espalier" ] && [ ! -L "$PROJECT/espalier" ]; then
      echo "mode: inside"; echo "espalier: $PROJECT/espalier"; exit 0
    fi
    ROOT="$(linked_root)" || { echo "mode: none (no espalier install)"; exit 4; }
    echo "mode: outside"
    echo "root: $ROOT"
    echo "origin: $(head -1 "$ROOT/.espalier-origin")"
    echo "config: $(configured_root)$([ "$(configured_root)" = "$ROOT" ] || echo '  (STALE — run discover to repair)')"
    echo "git-config: $(gitconfig_get_root)"
    if [ -d "$ROOT/.git" ]; then
      echo "pending: $(git -C "$ROOT" status --short 2>/dev/null | wc -l | tr -d ' ') path(s) uncommitted"
      echo "last commit: $(git -C "$ROOT" log -1 --pretty='%h %s (%cr)' 2>/dev/null || echo none)"
      _rm="$(git -C "$ROOT" remote 2>/dev/null | head -1)"; echo "remote: ${_rm:-none}"
    else
      echo "git: none (no repo in $ROOT)"
    fi
    ;;

  # ──────────────────────────────────────────────────────────────── commit ──
  # Record the pipeline's bookkeeping in the OUTSIDE repo — the stand-in for
  # the espalier branch / espalier PR of an inside install.
  commit)
    MSG="${1:-chore(espalier): records}"; [ $# -gt 0 ] && shift
    ROOT="$(linked_root)" || die "$PROJECT is not an outside install (espalier is not a symlink into an espalier-main root)" 3
    ensure_repo "$ROOT"
    if [ $# -eq 0 ]; then
      git -C "$ROOT" add -A -- . 2>/dev/null || true    # the whole root: .espalier-origin, its .gitignore, espalier/
      set --
    fi
    for rel in "$@"; do
      case "$rel" in --*) continue ;; esac
      case "$rel" in espalier|espalier/*) ;; *) die "'$rel' is outside espalier/ — only espalier/** lives in the outside root" 2 ;; esac
      if [ -e "$ROOT/$rel" ] || git -C "$ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        git -C "$ROOT" add -A -- "$rel" 2>/dev/null || true
      fi
    done
    # Before the first commit `diff --cached` compares against an empty tree,
    # so it reports the staged files either way — the check holds in both cases.
    git -C "$ROOT" diff --cached --quiet 2>/dev/null && { echo "nothing to commit"; exit 0; }
    git_out "$ROOT" commit -q -m "$MSG" || die "commit failed in $ROOT"
    git -C "$ROOT" rev-parse --short HEAD
    ;;

  exclude-add)      exclude_add "$@" ;;
  exclude-defaults) set -f; exclude_add $(base_excludes) $(platform_excludes); set +f ;;
  exclude-remove)   exclude_remove ;;
  gitignore-entries) printf '%s\n' "$GITIGNORE_ENTRIES" ;;

  # ───────────────────────────────────────────────────────────── repot-out ──
  repot-out)
    [ -d "$PROJECT/espalier" ] && [ ! -L "$PROJECT/espalier" ] || die "no inside espalier/ directory to move (already outside, or no install)" 3
    refuse_inflight "$PROJECT/espalier/changes"
    ROOT="$(default_root)"
    if [ -d "$ROOT" ]; then
      if [ -f "$ROOT/.espalier-origin" ]; then
        [ "$(head -1 "$ROOT/.espalier-origin" | tr -d '\r\n')" = "$PROJECT" ] || die "$ROOT belongs to another project. Pass --name=<other>." 3
      elif [ -n "$(ls -A "$ROOT" 2>/dev/null)" ]; then
        die "$ROOT exists, is not empty, and carries no .espalier-origin — refusing to move into a foreign folder. Empty it or pass --name=<other>." 3
      fi
      [ -z "$(ls -A "$ROOT/espalier" 2>/dev/null)" ] || die "$ROOT/espalier already holds a tree — refusing to overwrite it. Empty it or pass --name=<other>." 3
    fi
    mkdir -p "$ROOT" || die "could not create $ROOT"
    rmdir "$ROOT/espalier" 2>/dev/null || true
    mv "$PROJECT/espalier" "$ROOT/espalier" || die "could not move espalier/ to $ROOT"
    printf '%s\n' "$PROJECT" > "$ROOT/.espalier-origin"
    ensure_repo "$ROOT"
    write_symlink "$ROOT"
    log "moved espalier/ -> $ROOT/espalier (symlink left behind)"
    # Untrack what the repo carried — the deletions stay STAGED, never committed here.
    git -C "$PROJECT" rm -r -q --cached --ignore-unmatch -- espalier \
      '.claude/rules/espalier-*.md' '.claude/skills/espalier*' '.claude/agents/harness-*.md' \
      '.agents/skills/espalier*' '.codex/agents/harness-*.toml' \
      '.github/skills/espalier*' '.github/agents/harness-*.agent.md' '.github/hooks/espalier-gates.json' >/dev/null 2>&1 || true
    move_hooks "$PROJECT/.claude/settings.json" "$PROJECT/.claude/settings.local.json"
    move_section "$PROJECT/CLAUDE.md" "$PROJECT/CLAUDE.local.md"
    gitignore_remove_entries
    strip_tracked_dispatcher
    strip_codeowners_block
    set -f; exclude_add $(base_excludes) $(platform_excludes); set +f
    config_set_root "$ROOT"
    gitconfig_set_root "$ROOT"
    # One path per call: `git add -u -- a b` aborts the whole add when any one
    # pathspec matches nothing (the project may have no .husky at all).
    for p in .gitignore .gitattributes CLAUDE.md .claude/settings.json .husky/post-merge; do
      git -C "$PROJECT" add -u -- "$p" >/dev/null 2>&1 || true
    done
    git_out "$ROOT" add -A -- . >/dev/null 2>&1 || true
    if ! git -C "$ROOT" diff --cached --quiet 2>/dev/null; then
      git_out "$ROOT" commit -q -m "chore(espalier): repot from $PROJECT" && log "baseline commit in $ROOT: $(git -C "$ROOT" rev-parse --short HEAD)"
    fi
    echo
    log "done — staged in the project repo (NOT committed):"
    git -C "$PROJECT" status --short | head -40
    echo
    log "suggested commit: git commit -m 'chore: repot espalier outside the repo'"
    log "then re-wire: bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --outside --yes"
    printf '%s\n' "$ROOT"
    ;;

  # ────────────────────────────────────────────────────────────── repot-in ──
  repot-in)
    ROOT="$(linked_root)" || die "$PROJECT is not an outside install — nothing to bring back in" 3
    refuse_inflight "$ROOT/espalier/changes"
    # Copy beside the link first; the link is replaced only once the copy is
    # complete, so a failed copy leaves the install reachable.
    STAGING="$PROJECT/.espalier.repot-in.tmp"; rm -rf "$STAGING"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a "$ROOT/espalier/" "$STAGING/" || { rm -rf "$STAGING"; die "copy failed — the symlink is untouched"; }
    else
      cp -R "$ROOT/espalier" "$STAGING" || { rm -rf "$STAGING"; die "copy failed — the symlink is untouched"; }
    fi
    rm -f "$PROJECT/espalier"
    mv "$STAGING" "$PROJECT/espalier" || die "could not move the copied tree into place (it is at $STAGING)"
    log "copied $ROOT/espalier -> $PROJECT/espalier (the outside root is left in place; delete it by hand once you are sure)"
    exclude_remove
    config_drop_root
    gitconfig_drop_root
    move_hooks "$PROJECT/.claude/settings.local.json" "$PROJECT/.claude/settings.json"
    [ -f "$PROJECT/.claude/settings.local.json" ] && [ "$(tr -d '[:space:]' < "$PROJECT/.claude/settings.local.json")" = "{}" ] && rm -f "$PROJECT/.claude/settings.local.json"
    rm -f "$PROJECT"/.claude/settings.local.json.espalier-backup-* 2>/dev/null
    move_section "$PROJECT/CLAUDE.local.md" "$PROJECT/CLAUDE.md"
    gitignore_add_entries
    for p in espalier .gitignore .gitattributes CLAUDE.md .claude/settings.json; do
      [ -e "$PROJECT/$p" ] && git -C "$PROJECT" add -- "$p" >/dev/null 2>&1
    done
    for g in '.claude/rules/espalier-*.md' '.claude/skills/espalier*' '.claude/agents/harness-*.md' \
             '.agents/skills/espalier*' '.codex/agents/harness-*.toml' \
             '.github/skills/espalier*' '.github/agents/harness-*.agent.md'; do
      git -C "$PROJECT" add -- $g 2>/dev/null || true
    done
    echo
    log "done — staged in the project repo (NOT committed):"
    git -C "$PROJECT" status --short | head -40
    echo
    log "suggested commit: git commit -m 'chore: repot espalier into the repo'"
    log "then re-wire: bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --yes"
    ;;

  *) die "unknown subcommand: $CMD (prepare|discover|status|commit|exclude-add|exclude-defaults|exclude-remove|gitignore-entries|repot-out|repot-in)" 2 ;;
esac
exit 0
