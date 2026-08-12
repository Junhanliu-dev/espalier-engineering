#!/usr/bin/env bash
# maprun-integration.sh — ensure the integration worktree exists; print its path.
#
#   maprun-integration.sh <map-dir>
#
# The master needs somewhere to edit requirements.md and merge ticket branches
# WITHOUT touching your working checkout. That place is this worktree, sitting
# on the integration branch, with push blocked like every other worktree.
set -euo pipefail

MAP_DIR="${1:?usage: maprun-integration.sh <map-dir>}"
MAP_DIR="$(cd "$MAP_DIR" && pwd)"
PLAN="$MAP_DIR/plan/plan.json"
REPO="$(git rev-parse --show-toplevel)"
[ -f "$PLAN" ] || { echo "integration: no plan.json at $PLAN" >&2; exit 1; }

get() { PLAN="$PLAN" F="$1" python3 -c 'import json,os;v=json.load(open(os.environ["PLAN"])).get(os.environ["F"],"");print("" if v is None else v)'; }
rows() { # rows <key> <field1,field2,...>
  PLAN="$PLAN" K="$1" FIELDS="$2" python3 - << 'PYR'
import json, os
p = json.load(open(os.environ["PLAN"]))
fields = os.environ["FIELDS"].split(",")
for item in (p.get(os.environ["K"]) or []):
    if isinstance(item, str):
        print(item)
    else:
        print("\t".join(str(item.get(f, "")) for f in fields))
PYR
}

INTEGRATION="$(get integration_branch)"
BASE="$(get base_branch)"
WT_ROOT="$(get worktree_root)"

case "$WT_ROOT" in
  /*) WT_BASE="$WT_ROOT" ;;
  *)  WT_BASE="$REPO/$WT_ROOT" ;;
esac
IWT="$WT_BASE/$(basename "$MAP_DIR")/_integration"

if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$INTEGRATION"; then
  git -C "$REPO" branch "$INTEGRATION" "$BASE" >&2
  echo "created branch $INTEGRATION from $BASE" >&2
fi

# Self-heal: earlier versions applied the push block below WITHOUT --worktree,
# poisoning the SHARED .git/config — which blocks the operator's own checkout
# (and the master's PR pushes). Only maprun ever writes this value, so unset
# on sight.
if [ "$(git -C "$REPO" config remote.origin.pushurl 2>/dev/null)" = "blocked://maprun-forbids-push" ]; then
  git -C "$REPO" config --unset remote.origin.pushurl || true
  echo "healed: removed maprun push block from the SHARED git config" >&2
fi

if [ ! -d "$IWT" ]; then
  mkdir -p "$(dirname "$IWT")"
  git -C "$REPO" worktree add "$IWT" "$INTEGRATION" >&2
  # MUST be --worktree scoped (needs extensions.worktreeConfig): a plain
  # `git config` here writes the SHARED .git/config and blocks the operator's
  # checkout too — see the identical note in maprun-dispatch.sh.
  git -C "$REPO" config extensions.worktreeConfig true
  git -C "$IWT" config --worktree remote.origin.pushurl "blocked://maprun-forbids-push" || true
  git -C "$IWT" config --worktree push.default nothing || true
  # Workspace deps: clone from the main checkout (verify has to build here).
  # Symlinks unsupported — bundlers reject out-of-root node_modules links.
  rows workspaces dir,deps,deps_dir,install_cmd | while IFS=$'\t' read -r wsdir wsdeps wsddir wscmd; do
    [ -n "$wsdir" ] || continue
    wsddir="${wsddir:-node_modules}"
    [ -d "$REPO/$wsdir" ] || continue
    [ -e "$IWT/$wsdir/$wsddir" ] && continue
    [ "$wsdeps" = "none" ] && continue
    if [ -d "$REPO/$wsdir/$wsddir" ] && [ "$wsdeps" != "install" ]; then
      cp -Rc "$REPO/$wsdir/$wsddir" "$IWT/$wsdir/$wsddir" 2>/dev/null \
        || cp -R "$REPO/$wsdir/$wsddir" "$IWT/$wsdir/$wsddir"
    elif [ -n "$wscmd" ]; then
      (cd "$IWT/$wsdir" && bash -c "$wscmd" >/dev/null 2>&1) || true
    fi
  done
  echo "created integration worktree" >&2
fi

echo "$IWT"
