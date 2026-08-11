#!/usr/bin/env bash
# maprun-merge.sh — merge one PASSED ticket branch into the integration branch.
#
#   maprun-merge.sh <map-dir> <ticket-key> [--dry-run]
#
# The merge happens in a dedicated integration worktree, never in your working
# checkout — the runner must never touch the tree you have open.
#
# Exit codes:  0 merged   2 conflict (left for a human)   1 error
set -euo pipefail

MAP_DIR="${1:?usage: maprun-merge.sh <map-dir> <ticket-key> [--dry-run]}"
KEY="${2:?ticket key required}"
DRY_RUN="no"; [ "${3:-}" = "--dry-run" ] && DRY_RUN="yes"

MAP_DIR="$(cd "$MAP_DIR" && pwd)"
PLAN="$MAP_DIR/plan/plan.json"
REPO="$(git rev-parse --show-toplevel)"
[ -f "$PLAN" ] || { echo "merge: no plan.json at $PLAN"; exit 1; }

field() { # field <name> [ticket|plan]
  PLAN="$PLAN" KEY="$KEY" F="$1" SCOPE="${2:-plan}" python3 - << 'PYF'
import json, os
p = json.load(open(os.environ["PLAN"]))
key, f, scope = os.environ["KEY"], os.environ["F"], os.environ["SCOPE"]
t = next((x for x in p["tickets"] if x["key"] == key), None)
if t is None:
    raise SystemExit(f"unknown ticket {key}")
src = t if scope == "ticket" else p
v = src.get(f, "")
print("" if v is None else v)
PYF
}

SLUG="$(field slug ticket)"
NAME="$(field name ticket)"
INTEGRATION="$(field integration_branch plan)"
BASE="$(field base_branch plan)"

BRANCH="espalier/${SLUG}"

echo "merge: $KEY ($BRANCH → $INTEGRATION)"

if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "  ERROR: branch $BRANCH does not exist"; exit 1
fi

if [ "$DRY_RUN" = "yes" ]; then
  # No side effects on a dry run — the integration worktree is NOT created.
  echo "  DRY RUN — would merge $BRANCH into $INTEGRATION"
  git -C "$REPO" log --oneline "$INTEGRATION..$BRANCH" 2>/dev/null | sed 's/^/    /' || true
  exit 0
fi

IWT="$(bash "$REPO/espalier/hooks/maprun-integration.sh" "$MAP_DIR")"
git -C "$IWT" checkout --quiet "$INTEGRATION"

COUNT="$(git -C "$REPO" rev-list --count "$INTEGRATION..$BRANCH")"
if [ "$COUNT" = "0" ]; then
  echo "  nothing to merge (branch has no commits ahead) — treating as merged"
  exit 0
fi
echo "  $COUNT commit(s) to merge"

# Explicit identity: the merge commit must not depend on host git config.
MERGE_OUT="$(git -C "$IWT" -c user.email=maprun@espalier -c user.name=maprun \
  merge --no-ff "$BRANCH" -m "merge($KEY): $NAME

Espalier slice $SLUG, stages 1-6 clean.
Merged by the map runner; not pushed." 2>&1)" && { echo "  merged cleanly"; exit 0; }

# ── failed: a real conflict (exit 2) or an operational error (exit 1)? ───────
CONFLICTS="$(git -C "$IWT" diff --name-only --diff-filter=U || true)"
if [ -n "$CONFLICTS" ]; then
  echo "  CONFLICT in:"
  echo "$CONFLICTS" | sed 's/^/    /'
  echo "  aborting merge — this needs a human"
  git -C "$IWT" merge --abort || true
  exit 2
fi
echo "  ERROR: merge failed without conflicts — git said:"
echo "$MERGE_OUT" | sed 's/^/    /' | head -8
git -C "$IWT" merge --abort >/dev/null 2>&1 || true
exit 1
