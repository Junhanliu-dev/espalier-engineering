#!/usr/bin/env bash
# espalier-pr.sh — the pipeline's forge surface: the code PR and its espalier
# sibling.
#
#   espalier-pr.sh <type> <slug> project [msg]  project espalier/ onto the espalier
#                                               branch and commit it there
#   espalier-pr.sh <type> <slug> push           push BOTH branches (by refspec)
#   espalier-pr.sh <type> <slug> open           open/find both PRs, record them
#   espalier-pr.sh <type> <slug> status         print the recorded PR table
#
# Two invariants this script exists to protect:
#
#  1. THE MAIN CHECKOUT NEVER SWITCHES BRANCHES. espalier/ is live working state
#     through Stage 10 — the state file, the records, doc-patches, the delivery
#     brief are all still being written after Stage 7. Checking out the espalier
#     branch would take those files out of the tree and the push gate would find
#     no in-flight change at all. So the espalier branch is a PROJECTION, built
#     in a temporary worktree and synced one-way from this checkout.
#
#  2. BOTH BRANCHES ARE PUSHED BY REFSPEC, FROM THE CODE BRANCH. pre-push-gate.sh
#     fingerprints `git diff <Base-Ref> -- . ':(exclude)espalier/'` against the
#     CURRENT checkout and blocks on a mismatch. On an espalier-only branch that
#     diff is empty, so the fingerprint can never match and the push is BLOCKED.
#     Pushing `<branch>:<branch>` while HEAD is still the code branch lets the
#     gate check what it was written to check. (Same reason maprun-pr.sh pushes
#     from the main checkout.) The gate is not modified and has no bypass.
#
# The two PRs are SIBLINGS — both based on the canonical branch. They are
# deliberately NOT stacked: GitHub closes a child PR when its base branch is
# deleted rather than retargeting it, and that close is irrecoverable (the base
# of a closed PR cannot be changed, and it cannot be reopened without its base).
# A repo with deleteBranchOnMerge would destroy the espalier PR of every change.
# Ordering is advisory — PR2's body says which PR to merge first.
#
# Degradation, as everywhere else in this plugin: gh missing or unauthenticated
# is exit 5 and a warning; the pipeline continues. Nothing here ever force-pushes.
#
# Exit codes:  0 done   5 forge unavailable   1 error
set -euo pipefail

TYPE="${1:?usage: espalier-pr.sh <type> <slug> project|push|open|status}"
SLUG="${2:?slug required}"
CMD="${3:?subcommand required: project|push|open|status}"
MSG="${4:-}"

REPO="$(git rev-parse --show-toplevel)"
STATE="$REPO/espalier/changes/$TYPE/$SLUG/pipeline-state.md"
CODE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
ESP_BRANCH="${TYPE}/${SLUG}-espalier"
REMOTE="$(grep -m1 '^canonical-remote:' "$REPO/espalier/.espalier-config" 2>/dev/null | awk '{print $2}')"
REMOTE="${REMOTE:-origin}"

# The canonical branch is what both PRs target. Config first, then the remote's
# own default, then main — a project that never set the key still works.
BASE_BRANCH="$(grep -m1 '^canonical-branch:' "$REPO/espalier/.espalier-config" 2>/dev/null | awk '{print $2}')"
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||")"
fi
BASE_BRANCH="${BASE_BRANCH:-main}"

# Guard invariant 1 at every entry point, not just where it would corrupt state.
if [ "$CODE_BRANCH" = "$ESP_BRANCH" ]; then
  echo "pr: ERROR — the checkout is on $ESP_BRANCH."
  echo "  The espalier branch is a projection and is never checked out here:"
  echo "  espalier/ is live working state through Stage 10, and the push gate"
  echo "  reads it. Switch back to the code branch and re-run."
  exit 1
fi

base_ref() {  # the Stage 3 certificate anchor; merge-base is the legacy fallback
  local r
  r="$(grep -E '^(- )?Base-Ref:' "$STATE" 2>/dev/null | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')"
  [ -n "$r" ] || r="$(git -C "$REPO" merge-base HEAD "$REMOTE/$BASE_BRANCH" 2>/dev/null || true)"
  [ -n "$r" ] || r="$(git -C "$REPO" rev-parse HEAD)"
  printf '%s' "$r"
}

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || { echo "pr: gh CLI not found — PRs skipped (branches are pushed, open them by hand)"; exit 5; }
  # `gh auth status` fails when ANY configured account is broken, even if the
  # active one is fine. Probe the active token, which is what every call uses.
  gh auth token >/dev/null 2>&1 \
    || { echo "pr: gh has no usable active account (gh auth login) — PRs skipped"; exit 5; }
}

push_branch() {  # fast-forward push, from THIS checkout, by refspec (invariant 2)
  local out
  if out="$(git -C "$REPO" push "$REMOTE" "$1:$1" 2>&1)"; then
    echo "  pushed $1 → $REMOTE"
  else
    echo "  ERROR: push of $1 was rejected. Git said:"
    printf '%s\n' "$out" | sed 's/^/    /' | head -6
    return 1
  fi
}

find_pr() {  # find_pr <head> <base> → "number<TAB>url", or nothing
  gh pr list --head "$1" --base "$2" --state all --json number,url --limit 1 \
     --template '{{range .}}{{.number}}{{"\t"}}{{.url}}{{end}}' 2>/dev/null || true
}

record_pr() {  # record_pr <role> <branch> <number> <url>
  [ -f "$STATE" ] || return 0
  grep -q '^## Pull Requests' "$STATE" \
    || printf '\n## Pull Requests\n| Role | Branch | PR | URL |\n|------|--------|----|----|\n' >> "$STATE"
  grep -qF "| $1 | $2 | #$3 |" "$STATE" && return 0
  printf '| %s | %s | #%s | %s |\n' "$1" "$2" "$3" "$4" >> "$STATE"
}

case "$CMD" in
  # ─────────────────────────────────────────────────────────────── project ──
  # Sync espalier/ from this checkout onto the espalier branch and commit it
  # there. One-way, always: the projection is never edited in place, so the two
  # copies cannot drift apart. Called at Stage 7 (records), after the doc sweep
  # (wiki/rules refresh), and at Completion (brief + close).
  project)
    BR="$(base_ref)"
    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      git -C "$REPO" branch "$ESP_BRANCH" "$BR"
      echo "pr: created $ESP_BRANCH at ${BR:0:8} (Base-Ref)"
    fi

    WT="$(mktemp -d "${TMPDIR:-/tmp}/espalier-pr-XXXXXX")"
    cleanup() { git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true; }
    trap cleanup EXIT
    git -C "$REPO" worktree add --quiet "$WT" "$ESP_BRANCH"

    # Project. rsync --delete also retires files removed from this checkout;
    # without rsync we copy over the top and say plainly what we cannot do.
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$REPO/espalier/" "$WT/espalier/"
    else
      cp -R "$REPO/espalier/." "$WT/espalier/"
      echo "  NOTE: rsync not found — copied without --delete, so a file removed"
      echo "        from espalier/ in this checkout still exists on $ESP_BRANCH."
    fi

    # `git add` honours .gitignore, so per-clone sidecars stay untracked.
    git -C "$WT" add -A espalier/
    if git -C "$WT" diff --cached --quiet; then
      echo "pr: nothing to project onto $ESP_BRANCH"
    else
      git -C "$WT" commit --quiet -m "${MSG:-chore(espalier): $SLUG — pipeline records}"
      echo "pr: projected onto $ESP_BRANCH — $(git -C "$WT" log -1 --pretty=%s)"
      git -C "$WT" diff-tree --no-commit-id --name-only -r HEAD | sed 's/^/    /'
    fi
    ;;

  # ────────────────────────────────────────────────────────────────── push ──
  push)
    echo "pr: push ($CODE_BRANCH + $ESP_BRANCH → $REMOTE)"
    push_branch "$CODE_BRANCH"
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      push_branch "$ESP_BRANCH"
    else
      echo "  NOTE: $ESP_BRANCH does not exist yet (nothing projected) — skipped"
    fi
    ;;

  # ────────────────────────────────────────────────────────────────── open ──
  open)
    require_gh
    echo "pr: open ($CODE_BRANCH, $ESP_BRANCH → $BASE_BRANCH)"
    push_branch "$CODE_BRANCH"
    git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH" \
      && push_branch "$ESP_BRANCH"

    TITLE="$(grep -m1 '^# ' "$REPO/espalier/changes/$TYPE/$SLUG/requirements.md" 2>/dev/null | sed 's/^# //')"
    [ -n "$TITLE" ] || TITLE="$TYPE: $SLUG"

    # ── the code PR ──
    EX="$(find_pr "$CODE_BRANCH" "$BASE_BRANCH")"
    if [ -n "$EX" ]; then
      CODE_NUM="${EX%%$'\t'*}"; CODE_URL="${EX#*$'\t'}"
      echo "  code PR already exists: #$CODE_NUM"
    else
      BODY="Espalier change \`$TYPE/$SLUG\` — code only. Every \`espalier/\`
path of this change is on its sibling PR, so this diff is the change itself.

The pipeline's records (requirements, review verdicts, deviations, commits)
are on that PR; \`delivery-brief.md\` there is the summary written for a
reviewer."
      CODE_URL="$(gh pr create --head "$CODE_BRANCH" --base "$BASE_BRANCH" \
                    --title "$TITLE" --body "$BODY" 2>&1)" \
        || { echo "  ERROR: gh pr create failed:"; printf '%s\n' "$CODE_URL" | sed 's/^/    /' | head -6; exit 5; }
      CODE_URL="$(printf '%s\n' "$CODE_URL" | grep -Eo 'https?://[^ ]+/pull/[0-9]+' | head -1)"
      CODE_NUM="${CODE_URL##*/}"
      echo "  opened code PR #$CODE_NUM"
    fi
    record_pr code "$CODE_BRANCH" "$CODE_NUM" "$CODE_URL"

    # ── the espalier PR ──
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      EX="$(find_pr "$ESP_BRANCH" "$BASE_BRANCH")"
      if [ -n "$EX" ]; then
        ESP_NUM="${EX%%$'\t'*}"; ESP_URL="${EX#*$'\t'}"
        echo "  espalier PR already exists: #$ESP_NUM"
      else
        # A rules edit needs the rule owner (development-process.md, Rule-canon
        # gate). Say so in the body — a PR that stalls on CODEOWNERS should look
        # like it is waiting for someone, not like it is stuck.
        RULES_NOTE=""
        if git -C "$REPO" diff --name-only "$(base_ref)..$ESP_BRANCH" -- espalier/rules/ | grep -q .; then
          RULES_NOTE="

> This PR touches \`espalier/rules/\` — it needs the rule owner's review
> (CODEOWNERS, Rule-canon gate). Expect it to wait on them."
        fi
        BODY="Espalier records and doc refresh for \`$TYPE/$SLUG\` — \`espalier/\`
paths only. The code is on #$CODE_NUM.

**Merge #$CODE_NUM first.** Nothing enforces that; these are sibling PRs, not a
stack. Landing this one early only means the wiki briefly describes code that
has not merged yet — \`/espalier-doctor\` flags the mismatch on its next scan.$RULES_NOTE"
        ESP_URL="$(gh pr create --head "$ESP_BRANCH" --base "$BASE_BRANCH" \
                     --title "chore(espalier): $SLUG — records and doc refresh" \
                     --body "$BODY" 2>&1)" \
          || { echo "  ERROR: gh pr create failed:"; printf '%s\n' "$ESP_URL" | sed 's/^/    /' | head -6; exit 5; }
        ESP_URL="$(printf '%s\n' "$ESP_URL" | grep -Eo 'https?://[^ ]+/pull/[0-9]+' | head -1)"
        ESP_NUM="${ESP_URL##*/}"
        echo "  opened espalier PR #$ESP_NUM"
      fi
      record_pr espalier "$ESP_BRANCH" "$ESP_NUM" "$ESP_URL"
    else
      echo "  NOTE: $ESP_BRANCH does not exist — no espalier PR opened"
    fi
    ;;

  # ──────────────────────────────────────────────────────────────── status ──
  status)
    if [ -f "$STATE" ] && grep -q '^## Pull Requests' "$STATE"; then
      sed -n '/^## Pull Requests/,/^$/p' "$STATE"
    else
      echo "pr: no PRs recorded for $TYPE/$SLUG"
    fi
    ;;

  *)
    echo "pr: unknown subcommand '$CMD' (project|push|open|status)"; exit 1 ;;
esac
