#!/usr/bin/env bash
# espalier-pr.sh — the pipeline's forge surface: the code PR and its espalier
# sibling.
#
#   espalier-pr.sh <type> <slug> project [msg] [path...]
#                                               project the named espalier/ paths onto
#                                               the espalier branch and commit them there
#   espalier-pr.sh <type> <slug> project-sweep <wiki|rules>
#                                               project exactly the files the latest
#                                               `### Wiki Sweep` block marked PATCH
#   espalier-pr.sh <type> <slug> sync [msg] [path...]
#                                               project, then push — for records written
#                                               after the PRs exist
#   espalier-pr.sh <type> <slug> close [msg] [path...]
#                                               Completion: sync, then retire the local
#                                               copies the pushed branch now holds as-is
#   espalier-pr.sh <type> <slug> push           push BOTH branches (by refspec)
#   espalier-pr.sh <type> <slug> open           open/find both PRs, record them
#   espalier-pr.sh <type> <slug> status         print the recorded PR table
#   espalier-pr.sh <type> <slug> ci-scan        report which workflows will (not) run
#                                               on the espalier PR
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

TYPE="${1:?usage: espalier-pr.sh <type> <slug> project|project-sweep|sync|close|push|open|status|ci-scan}"
SLUG="${2:?slug required}"
CMD="${3:?subcommand required: project|project-sweep|sync|close|push|open|status|ci-scan}"
MSG="${4:-}"
shift 4 2>/dev/null || shift $#   # anything left is an explicit path list for `project`/`sync`

REPO="$(git rev-parse --show-toplevel)"
STATE="$REPO/espalier/changes/$TYPE/$SLUG/pipeline-state.md"
CODE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
ESP_BRANCH="${TYPE}/${SLUG}-espalier"
# `|| true` on every config read: under pipefail a grep that finds no key fails
# the pipeline, and `set -e` would end the script silently — before the
# fallbacks below could ever apply.
REMOTE="$(grep -m1 '^canonical-remote:' "$REPO/espalier/.espalier-config" 2>/dev/null | awk '{print $2}' || true)"
REMOTE="${REMOTE:-origin}"

# The canonical branch is what both PRs target. Config first, then the remote's
# own default, then main — a project that never set the key still works.
BASE_BRANCH="$(grep -m1 '^canonical-branch:' "$REPO/espalier/.espalier-config" 2>/dev/null | awk '{print $2}' || true)"
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||" || true)"
fi
BASE_BRANCH="${BASE_BRANCH:-main}"

# The checkout guards apply to the subcommands that build or push branches.
# `status` and `ci-scan` only read, so they run from anywhere.
case "$CMD" in
  project|project-sweep|sync|close|push|open)
    if [ "$CODE_BRANCH" = "HEAD" ]; then
      echo "pr: ERROR — detached HEAD. The split needs a named code branch to push"
      echo "  and to open a PR from. Check out the change's branch and re-run."
      exit 1
    fi
    # Guard invariant 1 at every entry point, not just where it would corrupt state.
    if [ "$CODE_BRANCH" = "$ESP_BRANCH" ]; then
      echo "pr: ERROR — the checkout is on $ESP_BRANCH."
      echo "  The espalier branch is a projection and is never checked out here:"
      echo "  espalier/ is live working state through Stage 10, and the push gate"
      echo "  reads it. Switch back to the code branch and re-run."
      exit 1
    fi
    if [ "$CODE_BRANCH" = "$BASE_BRANCH" ]; then
      echo "pr: ERROR — the checkout is on $BASE_BRANCH, the canonical branch."
      echo "  The code PR needs a change branch to open from, and pushing from here"
      echo "  would push $BASE_BRANCH itself. Check out the change's branch and re-run."
      exit 1
    fi
    ;;
esac

base_ref() {  # the Stage 3 certificate anchor; merge-base is the legacy fallback
  local r
  r="$(grep -E '^(- )?Base-Ref:' "$STATE" 2>/dev/null | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]' || true)"
  [ -n "$r" ] || r="$(git -C "$REPO" merge-base HEAD "$REMOTE/$BASE_BRANCH" 2>/dev/null || true)"
  [ -n "$r" ] || r="$(git -C "$REPO" merge-base HEAD "$BASE_BRANCH" 2>/dev/null || true)"
  # NEVER fall back to HEAD. The espalier branch is cut from this ref, so HEAD
  # would put every code commit of the change on it — and the espalier PR would
  # carry the code as well, silently defeating the split. Fail instead.
  if [ -z "$r" ]; then
    echo "pr: ERROR — cannot determine this change's base." >&2
    echo "  No 'Base-Ref:' in $STATE, and no merge-base with $REMOTE/$BASE_BRANCH" >&2
    echo "  or $BASE_BRANCH. Record Base-Ref (Stage 3 writes it) or fetch the" >&2
    echo "  canonical branch, then re-run. Cutting the espalier branch from HEAD" >&2
    echo "  would put this change's code on the espalier PR." >&2
    exit 1
  fi
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

# The split is an invariant, so verify it instead of trusting it — before EVERY
# push of the code branch (`push`, `open` and `sync` all reach one). It leaks
# through a path nobody intends: `certificate_write` runs `git add -A` (it must
# — an untracked new file would otherwise be invisible to the fingerprint),
# which leaves espalier/ STAGED on the code branch, and a later `git commit`
# commits the whole index. Any rollback that re-enters Stage 3 puts a coder
# commit after a certificate write, so the code PR silently acquires the
# pipeline's own records. Fail closed rather than ship a code PR that is not code.
assert_no_leak() {
  local br out leaked ref
  # Not `$(base_ref)` inline: a failing substitution inside an argument does not
  # stop the script, so the range would become `..branch` — empty — and the
  # guard would pass on exactly the run it could not check.
  br="$(base_ref)" || exit 1
  # Commits ONLY the code branch has. Excluding the canonical branch as well as
  # Base-Ref keeps a rebase onto a newer canonical branch from reporting that
  # branch's own espalier/ commits as a leak — they are not in the PR's diff.
  set -- "$CODE_BRANCH" "^$br"
  for ref in "$BASE_BRANCH" "$REMOTE/$BASE_BRANCH"; do
    git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}" >/dev/null && set -- "$@" "^$ref"
  done
  if ! out="$(git -C "$REPO" log --format= --name-only "$@" -- espalier/ 2>&1)"; then
    echo "  ERROR: could not list $CODE_BRANCH's commits to check the split:"
    printf '%s\n' "$out" | sed 's/^/    /' | head -6
    echo "  Nothing was pushed."
    exit 1
  fi
  leaked="$(printf '%s\n' "$out" | grep . | sort -u || true)"
  if [ -n "$leaked" ]; then
    echo "  ERROR: $CODE_BRANCH carries espalier/ paths — the split has leaked:"
    printf '%s\n' "$leaked" | sed 's/^/    /' | head -10
    echo "  A commit on the code branch absorbed paths left staged by"
    echo "  certificate_write. Commit code with an explicit pathspec"
    echo "  (git commit -- <paths>), move these onto the espalier branch, and"
    echo "  re-run. Nothing was pushed."
    exit 1
  fi
}

find_pr() {  # find_pr <head> <base> → "number<TAB>url", or nothing
  # The OPEN PR for this head, or a closed/merged one whose head is still this
  # branch's tip (a re-run after merge is the same work, not new work). An
  # older closed PR for a reused slug must not stand in for the new change.
  local tip
  tip="$(git -C "$REPO" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null || true)"
  gh pr list --head "$1" --base "$2" --state all --limit 30 \
     --json number,url,state,headRefOid \
     --jq "[.[] | select(.state == \"OPEN\" or .headRefOid == \"$tip\")][0] // empty | \"\(.number)\t\(.url)\"" \
     2>/dev/null || true
}

record_pr() {  # record_pr <role> <branch> <number> <url>
  [ -f "$STATE" ] || return 0
  grep -q '^## Pull Requests' "$STATE" \
    || printf '\n## Pull Requests\n| Role | Branch | PR | URL |\n|------|--------|----|----|\n' >> "$STATE"
  grep -qF "| $1 | $2 | #$3 |" "$STATE" && return 0
  printf '| %s | %s | #%s | %s |\n' "$1" "$2" "$3" "$4" >> "$STATE"
}

pr_url() {  # pr_url <gh output> → the first pull URL in it, or nothing
  printf '%s\n' "$1" | grep -Eo 'https?://[^ ]+/pull/[0-9]+' | head -1 || true
}

case "$CMD" in
  # ─────────────────────────────────────────────────────────────── project ──
  # Sync espalier/ from this checkout onto the espalier branch and commit it
  # there. One-way, always: the projection is never edited in place, so the two
  # copies cannot drift apart. Called at Stage 7 (records, then each class the
  # sweep patched), by `open` (the PR table it records), and at Completion via
  # `close` (brief + close).
  project)
    BR="$(base_ref)" || exit 1
    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      git -C "$REPO" branch "$ESP_BRANCH" "$BR"
      echo "pr: created $ESP_BRANCH at ${BR:0:8} (Base-Ref)"
    fi

    # WHAT gets projected is explicit, never "whatever is dirty under espalier/".
    # A whole-tree copy sweeps in other in-flight changes' records, migration
    # .bak backups, and any unrelated local edit — all of which would land in
    # THIS change's pull request. Default: this change's own records, plus the
    # convention index when the run wrote there. The sweep passes its own paths.
    if [ "$#" -eq 0 ]; then
      set -- "espalier/changes/$TYPE/$SLUG"
      [ -d "$REPO/espalier/conventions" ] && set -- "$@" espalier/conventions
    fi
    # The espalier branch carries espalier/** and nothing else — that is the
    # whole contract of the split. A caller path outside it is a bug upstream.
    for rel in "$@"; do
      case "$rel" in
        espalier/*) ;;
        *) echo "pr: ERROR — '$rel' is outside espalier/; the espalier branch carries espalier/** only."; exit 1 ;;
      esac
      case "/$rel/" in
        */../*|*/./*) echo "pr: ERROR — '$rel' is not a normalised path."; exit 1 ;;
      esac
    done

    WT="$(mktemp -d "${TMPDIR:-/tmp}/espalier-pr-XXXXXX")"
    cleanup() { git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true; }
    trap cleanup EXIT
    git -C "$REPO" worktree add --quiet "$WT" "$ESP_BRANCH"

    # Only existing paths are staged by name, because `git add -- <path>` exits
    # 128 on a pathspec that matches nothing and would abort the run under
    # `set -e`. A named path absent here but tracked on the espalier branch was
    # deleted in this checkout, so the deletion is projected; one absent from
    # both is reported, not fatal — the sweep may name a class an install lacks.
    N_ADD=0
    MISSING=""
    for rel in "$@"; do
      if [ ! -e "$REPO/$rel" ]; then
        if git -C "$WT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
          git -C "$WT" rm -r --quiet -- "$rel"
          N_ADD=$((N_ADD + 1))
        else
          MISSING="$MISSING $rel"
        fi
        continue
      fi
      if [ -d "$REPO/$rel" ]; then
        mkdir -p "$WT/$rel"
        # --delete retires files removed from this checkout, scoped to this path.
        if command -v rsync >/dev/null 2>&1; then
          rsync -a --delete "$REPO/$rel/" "$WT/$rel/"
        else
          cp -R "$REPO/$rel/." "$WT/$rel/"
          echo "  NOTE: rsync not found — copied $rel without --delete, so a file"
          echo "        removed from it still exists on $ESP_BRANCH."
        fi
      else
        mkdir -p "$WT/$(dirname "$rel")"
        cp "$REPO/$rel" "$WT/$rel"
      fi
      # Scoped to the paths named above. `-A espalier/` would stage anything else
      # that differs under espalier/, which is the whole-tree behaviour this
      # subcommand exists to avoid.
      git -C "$WT" add -A -- "$rel"
      N_ADD=$((N_ADD + 1))
    done

    [ -n "$MISSING" ] && echo "pr: not present, skipped —$MISSING"
    if [ "$N_ADD" -eq 0 ]; then
      echo "pr: nothing to project onto $ESP_BRANCH (no named path exists)"
      exit 0
    fi

    # Docs are additive on this path, mechanically, not just by instruction: the
    # sweep commits without a human accept, and a silently dropped rule is
    # unrecoverable. A deleted doc, or a doc that lost more lines than it gained,
    # is refused — the removal belongs under `### Proposed Removals` and the
    # prune protocol. An amendment (one line replaced by one line) passes.
    # ESPALIER_DOC_SHRINK_OK=1 is for a human who has read the diff, never for
    # the pipeline to set on its own.
    if [ "${ESPALIER_DOC_SHRINK_OK:-}" != 1 ]; then
      SHRUNK="$( { git -C "$WT" diff --cached --diff-filter=D --name-only -- espalier/wiki espalier/rules | sed 's/$/ (deleted)/'
                   git -C "$WT" diff --cached --numstat -- espalier/wiki espalier/rules \
                     | awk -F'\t' '$1 != "-" && $2 > $1 { printf "%s (+%s -%s)\n", $3, $1, $2 }'
                 } | sort -u || true)"
      if [ -n "$SHRUNK" ]; then
        echo "pr: ERROR — refusing to project a doc removal onto $ESP_BRANCH:"
        printf '%s\n' "$SHRUNK" | sed 's/^/    /'
        echo "  Wiki and rule edits on this path are additive or amending only. Put the"
        echo "  removal under '### Proposed Removals' in doc-patches.md, restore the text,"
        echo "  and re-run. Nothing was committed."
        exit 1
      fi
    fi

    if git -C "$WT" diff --cached --quiet; then
      echo "pr: nothing to project onto $ESP_BRANCH"
    else
      git -C "$WT" commit --quiet -m "${MSG:-chore(espalier): $SLUG — pipeline records}"
      echo "pr: projected onto $ESP_BRANCH — $(git -C "$WT" log -1 --pretty=%s)"
      git -C "$WT" diff-tree --no-commit-id --name-only -r HEAD | sed 's/^/    /'
    fi
    ;;

  # ───────────────────────────────────────────────────────── project-sweep ──
  # Project exactly the files the sweep says it patched — never the whole class
  # directory, which would also carry any unrelated local edit sitting in
  # espalier/wiki or espalier/rules into this change's PR as a "refresh". The
  # LAST `### Wiki Sweep` block wins: a rollback that re-runs Stage 7 appends a
  # fresh block, and the earlier one describes a diff that no longer exists.
  project-sweep)
    CLASS="$MSG"
    case "$CLASS" in
      wiki|rules) ;;
      *) echo "pr: usage — project-sweep <wiki|rules>"; exit 1 ;;
    esac
    DP="$REPO/espalier/changes/$TYPE/$SLUG/doc-patches.md"
    [ -f "$DP" ] || { echo "pr: no doc-patches.md — the sweep recorded nothing; no $CLASS refresh"; exit 0; }
    FILES="$(awk '
        /^### Wiki Sweep/ { buf = ""; on = 1; next }
        on && /^#+ /      { on = 0 }
        on                { buf = buf $0 "\n" }
        END               { printf "%s", buf }
      ' "$DP" \
      | sed -nE "s#^- \`?(espalier/)?($CLASS/[A-Za-z0-9._/-]+\.md)\`?:[[:space:]]*\**PATCH.*#\2#p" \
      | sort -u || true)"
    if [ -z "$FILES" ]; then
      echo "pr: the sweep patched no $CLASS file — nothing to project"
      exit 0
    fi
    set --
    for f in $FILES; do set -- "$@" "espalier/$f"; done
    exec "$0" "$TYPE" "$SLUG" project "docs(espalier): $CLASS refresh for $SLUG" "$@"
    ;;

  # ────────────────────────────────────────────────────────────────── sync ──
  # Project, then push. For records written AFTER the PRs exist — the PR table
  # `open` records, and Completion's brief and close — which a projection alone
  # would leave committed locally on the espalier branch and absent from its PR.
  sync)
    "$0" "$TYPE" "$SLUG" project "${MSG:-chore(espalier): $SLUG — pipeline records}" "$@"
    "$0" "$TYPE" "$SLUG" push
    ;;

  # ───────────────────────────────────────────────────────────────── close ──
  # Completion: sync, then retire this checkout's copies of what was synced.
  # The copies cannot stay: once the espalier PR merges, `git pull` refuses to
  # write over an UNTRACKED file even when its content is identical, so every
  # completed change would block the next pull — and a permanently dirty tree
  # also trips every clean-tree barrier (/espalier-migrate's Step 0). A file is
  # retired only when the PUSHED espalier branch holds exactly its content, so
  # nothing is lost: it is on the remote, and on main once the PR merges.
  # Anything else — a file written after the sync, another change's records —
  # is left in place and named.
  close)
    ESPALIER_PR_CLOSING=1 "$0" "$TYPE" "$SLUG" sync "${MSG:-chore(espalier): close $SLUG}" "$@"
    if [ "$#" -eq 0 ]; then
      set -- "espalier/changes/$TYPE/$SLUG"
      [ -d "$REPO/espalier/conventions" ] && set -- "$@" espalier/conventions
    fi
    git -C "$REPO" fetch --quiet "$REMOTE" "$ESP_BRANCH" 2>/dev/null || true
    LOCAL_TIP="$(git -C "$REPO" rev-parse --verify --quiet "refs/heads/$ESP_BRANCH" || true)"
    REMOTE_TIP="$(git -C "$REPO" rev-parse --verify --quiet "refs/remotes/$REMOTE/$ESP_BRANCH" || true)"
    if [ -z "$LOCAL_TIP" ] || [ "$LOCAL_TIP" != "$REMOTE_TIP" ]; then
      echo "pr: $ESP_BRANCH is not pushed as it stands — local copies kept."
      echo "  Re-run once the push succeeds: espalier/hooks/espalier-pr.sh $TYPE $SLUG close"
      exit 1
    fi
    N_RET=0; KEPT=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      want="$(git -C "$REPO" rev-parse --verify --quiet "$ESP_BRANCH:$f" 2>/dev/null || true)"
      have="$(git -C "$REPO" hash-object -- "$f" 2>/dev/null || true)"
      if [ -z "$want" ] || [ "$want" != "$have" ]; then
        KEPT="$KEPT $f"; continue
      fi
      if git -C "$REPO" cat-file -e "HEAD:$f" 2>/dev/null; then
        # Tracked on the code branch: back to its committed content, index too.
        git -C "$REPO" checkout --quiet HEAD -- "$f"
      else
        # New in this checkout (possibly staged by certificate_write's add -A).
        git -C "$REPO" rm --quiet --force --cached --ignore-unmatch -- "$f" >/dev/null
        rm -f -- "$REPO/$f"
      fi
      N_RET=$((N_RET + 1))
    done << EOF_RET
$(cd "$REPO" && git ls-files --cached --others --exclude-standard -- "$@" | sort -u)
EOF_RET
    echo "pr: retired $N_RET local cop$( [ "$N_RET" -eq 1 ] && echo y || echo ies) — each is on $REMOTE/$ESP_BRANCH as-is"
    [ -z "$KEPT" ] || echo "  kept (differs from the pushed branch, or not on it):$KEPT"
    ;;

  # ────────────────────────────────────────────────────────────────── push ──
  push)
    echo "pr: push ($CODE_BRANCH + $ESP_BRANCH → $REMOTE)"
    assert_no_leak
    push_branch "$CODE_BRANCH"
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      push_branch "$ESP_BRANCH"
    else
      echo "  NOTE: $ESP_BRANCH does not exist yet (nothing projected) — skipped"
    fi
    # Say why espalier/ is still dirty, once per push: anyone running
    # `git status` mid-run otherwise reads a permanently dirty tree as a bug.
    N_DIRTY="$(git -C "$REPO" status --porcelain -- espalier/ | grep -c . || true)"
    if [ "${N_DIRTY:-0}" -gt 0 ] && [ -z "${ESPALIER_PR_CLOSING:-}" ]; then
      echo "  note: $N_DIRTY path(s) under espalier/ stay uncommitted in this checkout by"
      echo "        design — they are the live source the espalier branch is projected from."
    fi
    ;;

  # ────────────────────────────────────────────────────────────────── open ──
  open)
    require_gh
    echo "pr: open ($CODE_BRANCH, $ESP_BRANCH → $BASE_BRANCH)"
    assert_no_leak
    push_branch "$CODE_BRANCH"
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      push_branch "$ESP_BRANCH"
    fi

    TITLE="$(grep -m1 '^# ' "$REPO/espalier/changes/$TYPE/$SLUG/requirements.md" 2>/dev/null | sed 's/^# //' || true)"
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
      OUT="$(gh pr create --head "$CODE_BRANCH" --base "$BASE_BRANCH" \
                    --title "$TITLE" --body "$BODY" 2>&1)" \
        || { echo "  ERROR: gh pr create failed:"; printf '%s\n' "$OUT" | sed 's/^/    /' | head -6; exit 5; }
      CODE_URL="$(pr_url "$OUT")"
      if [ -z "$CODE_URL" ]; then
        echo "  ERROR: gh pr create reported success but printed no PR URL:"
        printf '%s\n' "$OUT" | sed 's/^/    /' | head -6
        exit 5
      fi
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
        BR="$(base_ref)" || exit 1
        if git -C "$REPO" diff --name-only "$BR..$ESP_BRANCH" -- espalier/rules/ | grep -q .; then
          RULES_NOTE="

> This PR touches \`espalier/rules/\` — it needs the rule owner's review
> (CODEOWNERS, Rule-canon gate). Expect it to wait on them."
        fi
        BODY="Espalier records and doc refresh for \`$TYPE/$SLUG\` — \`espalier/\`
paths only. The code is on #$CODE_NUM.

**Merge #$CODE_NUM first.** Nothing enforces that; these are sibling PRs, not a
stack. Landing this one early only means the wiki briefly describes code that
has not merged yet — \`/espalier-doctor\` flags the mismatch on its next scan.$RULES_NOTE"
        OUT="$(gh pr create --head "$ESP_BRANCH" --base "$BASE_BRANCH" \
                     --title "chore(espalier): $SLUG — records and doc refresh" \
                     --body "$BODY" 2>&1)" \
          || { echo "  ERROR: gh pr create failed:"; printf '%s\n' "$OUT" | sed 's/^/    /' | head -6; exit 5; }
        ESP_URL="$(pr_url "$OUT")"
        if [ -z "$ESP_URL" ]; then
          echo "  ERROR: gh pr create reported success but printed no PR URL:"
          printf '%s\n' "$OUT" | sed 's/^/    /' | head -6
          exit 5
        fi
        ESP_NUM="${ESP_URL##*/}"
        echo "  opened espalier PR #$ESP_NUM"
      fi
      record_pr espalier "$ESP_BRANCH" "$ESP_NUM" "$ESP_URL"
    else
      echo "  NOTE: $ESP_BRANCH does not exist — no espalier PR opened"
    fi

    # The table just written lives in the state file, which is espalier/ — so
    # it reaches the espalier PR only by being projected and pushed like any
    # other record. Without this it would sit in the checkout and nowhere else.
    "$0" "$TYPE" "$SLUG" sync "chore(espalier): $SLUG — pull request links" \
      || { echo "  ERROR: the PR table was recorded locally but not projected — re-run:"
           echo "    espalier/hooks/espalier-pr.sh $TYPE $SLUG sync"; exit 1; }

    echo "pr: CI scan for the espalier PR"
    "$0" "$TYPE" "$SLUG" ci-scan || true
    ;;

  # ──────────────────────────────────────────────────────────────── status ──
  status)
    if [ -f "$STATE" ] && grep -q '^## Pull Requests' "$STATE"; then
      sed -n '/^## Pull Requests/,/^$/p' "$STATE"
    else
      echo "pr: no PRs recorded for $TYPE/$SLUG"
    fi
    ;;

  # ─────────────────────────────────────────────────────────────── ci-scan ──
  # The espalier PR's diff is `espalier/**` and nothing else, which interacts
  # badly with `pull_request` path filters in two OPPOSITE ways — so this
  # reports which workflows land in which bucket instead of giving one blanket
  # instruction:
  #
  #   - A workflow whose `paths:` does not match `espalier/**` never runs on the
  #     espalier PR. Harmless on its own; a DEADLOCK if any of its checks are
  #     required by branch protection, because a required check that never runs
  #     leaves the PR permanently un-mergeable.
  #   - A workflow with no path filter runs the full suite against a diff with
  #     no code in it. Mergeable, but it doubles CI for every change.
  #
  # Advice differs per bucket and the buckets contradict each other, so this
  # never edits a workflow. It reports, and names the required checks when the
  # token can read branch protection.
  ci-scan)
    WFDIR="$REPO/.github/workflows"
    [ -d "$WFDIR" ] || { echo "pr: no .github/workflows — nothing to scan"; exit 0; }
    command -v python3 >/dev/null 2>&1 \
      || { echo "pr: python3 not found — CI scan skipped (check path filters by hand)"; exit 0; }

    # Three-dot against the canonical branch — the same diff the forge computes
    # for the PR. A two-dot diff from Base-Ref answers a different question and
    # would misreport the moment the branch is not where you assume.
    FILES=""
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$ESP_BRANCH"; then
      for ref in "$BASE_BRANCH" "$REMOTE/$BASE_BRANCH"; do
        if git -C "$REPO" rev-parse --verify --quiet "$ref" >/dev/null; then
          FILES="$(git -C "$REPO" diff --name-only "$ref...$ESP_BRANCH" || true)"
          break
        fi
      done
    fi
    # Before the first projection there is no branch to diff; scan against the
    # paths the espalier PR is always made of, so the warning still arrives in
    # time to be acted on.
    [ -n "$FILES" ] || FILES="espalier/changes/$TYPE/$SLUG/pipeline-state.md
espalier/wiki/architecture.md
espalier/rules/development-process.md"

    # Required checks, best effort: needs branch-protection read, which many
    # tokens lack and which 404s when protection is off. Absence is not proof
    # that nothing is required — the report says so rather than implying safety.
    # `gh api` writes the error BODY to stdout on a 4xx (403 on a private repo
    # without Pro, 404 when protection is off), so a bare `|| true` leaves JSON
    # in REQUIRED and the report announces an error object as the required
    # checks. Take the output only on success, and drop anything that still
    # looks like JSON — a check context is a plain name. Protection set through
    # the newer `checks[]` form carries its names there, not in `contexts[]`.
    REQUIRED=""
    if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
      if _rq="$(gh api "repos/{owner}/{repo}/branches/$BASE_BRANCH/protection/required_status_checks" \
                  --jq '(.contexts[]?), (.checks[]?.context)' 2>/dev/null)"; then
        REQUIRED="$(printf '%s\n' "$_rq" | grep -v '[{}]' | sort -u || true)"
      fi
    fi

    WFDIR="$WFDIR" FILES="$FILES" REQUIRED="$REQUIRED" BASE_BRANCH="$BASE_BRANCH" python3 - << 'PYCI'
import os, re, sys

wfdir = os.environ["WFDIR"]
files = [f for f in os.environ["FILES"].split("\n") if f.strip()]
required = [c for c in os.environ["REQUIRED"].split("\n") if c.strip()]
base = os.environ["BASE_BRANCH"]
EVENTS = ("pull_request", "pull_request_target")

# An indentation-aware reader for the one corner of workflow YAML this needs —
# the `on:` mapping and the filters under a pull_request event. Not a YAML
# parser, and not trying to be: a regex over the whole file swallows sibling
# events into the pull_request block (`push:`'s paths read as the PR's), and
# misses the inline trigger forms entirely.

def indent(line):
    return len(line) - len(line.lstrip(" "))

def meaningful(line):
    s = line.strip()
    return bool(s) and not s.startswith("#")

def strip_comment(s):
    return re.sub(r"\s+#.*$", "", s).strip()

def flow_to_block(s):
    # `{branches: [main], paths: ['src/**']}` → one `key: value` line per key,
    # so the same filter reader handles both forms.
    s = s.strip()
    if s.startswith("{") and s.endswith("}"):
        s = s[1:-1]
    return re.sub(r",\s*(?=[A-Za-z_-]+\s*:)", "\n", s) + "\n"

def child_blocks(lines):
    """[(key, inline_value, body_lines)] for the shallowest keys in `lines`."""
    kids = [indent(l) for l in lines if meaningful(l)]
    if not kids:
        return []
    at = min(kids)
    out = []
    for i, l in enumerate(lines):
        if not meaningful(l) or indent(l) != at:
            continue
        m = re.match(r"\s*-\s*([A-Za-z_]+)\s*$", strip_comment(l))   # list form: `- pull_request`
        if m:
            out.append((m.group(1), "", []))
            continue
        m = re.match(r"""\s*["']?([A-Za-z_-]+)["']?\s*:\s*(.*)$""", l)
        if not m:
            continue
        body = []
        for l2 in lines[i + 1:]:
            if meaningful(l2) and indent(l2) <= at:
                break
            body.append(l2)
        out.append((m.group(1), strip_comment(m.group(2)), body))
    return out

def pr_triggers(text):
    """{event: block_text} for the pull_request events this workflow declares."""
    lines = text.split("\n")
    for i, l in enumerate(lines):
        m = re.match(r"""^(?:on|"on"|'on'|true)\s*:\s*(.*)$""", l)
        if not m:
            continue
        inline = strip_comment(m.group(1))
        if inline:   # on: pull_request | on: [push, pull_request] | on: {pull_request: …}
            if inline.startswith("{"):
                return {k: flow_to_block(v) for k, v, _ in
                        child_blocks(flow_to_block(inline).split("\n")) if k in EVENTS}
            names = re.findall(r"[A-Za-z_]+", inline)
            return {e: "" for e in EVENTS if e in names}
        body = []
        for l2 in lines[i + 1:]:
            if meaningful(l2) and indent(l2) == 0:
                break
            body.append(l2)
        found = {}
        for key, val, blk in child_blocks(body):
            if key not in EVENTS:
                continue
            if val and val not in ("{}", "null", "~"):
                found[key] = flow_to_block(val)
            else:
                found[key] = "\n".join(blk) + "\n"
        return found
    return {}

def items(raw, bracketed):
    out = []
    for x in (raw.split(",") if bracketed else re.findall(r"-\s*(.+)", raw)):
        x = x.split("#", 1)[0].strip().strip("'\"").strip()
        if x:
            out.append(x)
    return out

def filt(block, key):
    k = re.escape(key)
    b = re.search(r"^\s*%s\s*:\s*\[([^\]]*)\]" % k, block, re.M)
    if b:
        return items(b.group(1), True)
    b = re.search(r"^\s*%s\s*:\s*\n((?:\s*-\s*.+\n?)+)" % k, block, re.M)
    if b:
        return items(b.group(1), False)
    b = re.search(r"^\s*%s\s*:\s*([^\s\[#{][^#\n]*)$" % k, block, re.M)   # scalar
    if b:
        return [b.group(1).strip().strip("'\"")]
    return None

def to_re(pat):
    # GitHub filter globs: ** crosses /, * and ? do not, and `**/` also matches
    # zero directories — `**/*.md` matches a root-level README.md. Build the
    # regex in one pass so a literal '*' after '**' is not re-expanded.
    out, i = [], 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith("**/", i):
            out.append("(?:.*/)?"); i += 3; continue
        if pat.startswith("**", i):
            out.append(".*"); i += 2; continue
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")

skipped, runs, negated = [], [], []
for name in sorted(os.listdir(wfdir)):
    if not name.endswith((".yml", ".yaml")):
        continue
    try:
        text = open(os.path.join(wfdir, name), errors="replace").read()
    except OSError:
        continue
    trig = pr_triggers(text)
    # A bare `pull_request:` yields an EMPTY block — falsy, entirely valid, and
    # the commonest shape there is. Membership, not truthiness.
    if "pull_request" in trig:
        block = trig["pull_request"]
    elif "pull_request_target" in trig:
        block = trig["pull_request_target"]
    else:
        continue
    types = filt(block, "types")
    if types and set(types) <= {"closed"}:
        continue   # deploy-on-merge trigger; PRs are not meant to fire it
    br, br_ignore = filt(block, "branches"), filt(block, "branches-ignore")
    if any(p.startswith("!") for p in (br or []) + (br_ignore or [])):
        negated.append(name); continue
    if br and not any(to_re(p).match(base) for p in br):
        continue   # does not run on either PR — pre-existing, not ours
    if br_ignore and any(to_re(p).match(base) for p in br_ignore):
        continue
    paths, ignore = filt(block, "paths"), filt(block, "paths-ignore")
    if any(p.startswith("!") for p in (paths or []) + (ignore or [])):
        negated.append(name); continue
    if paths is not None:
        (runs if any(to_re(p).match(f) for p in paths for f in files) else skipped).append(name)
    elif ignore is not None:
        (skipped if all(any(to_re(p).match(f) for p in ignore) for f in files) else runs).append(name)
    else:
        runs.append(name)

if skipped:
    print("  %d workflow(s) will NOT run on the espalier PR (path filters exclude"
          " espalier/): %s" % (len(skipped), ", ".join(skipped)))
    if required:
        print("  Branch protection on '%s' requires: %s" % (base, ", ".join(required)))
        print("  If any of those checks come from the workflows above, the espalier PR")
        print("  can never merge — a required check that never runs blocks it forever.")
        print("  Add espalier/** to those filters, or drop those checks from the")
        print("  required list.")
    else:
        print("  No required checks were readable for '%s' (protection off, or the"
              " token cannot read it — absence is NOT proof none are required)." % base)
        print("  If any are required, the espalier PR will never merge: add espalier/**")
        print("  to those filters, or exclude those checks.")
if runs:
    print("  %d workflow(s) WILL run on the espalier PR: %s" % (len(runs), ", ".join(runs)))
    print("  That PR's diff contains no code, so this is your full suite against an")
    print("  unchanged tree — correct, but it doubles CI per change. Adding")
    print("  paths-ignore: ['espalier/**'] cuts it, but ONLY if none of their checks")
    print("  are required (see above).")
if negated:
    print("  %d workflow(s) use '!' negation in a branch or path filter and were NOT"
          " evaluated: %s — check them by hand." % (len(negated), ", ".join(negated)))
if not (skipped or runs or negated):
    print("  no pull_request workflow affects the espalier PR")
PYCI
    ;;

  *)
    echo "pr: unknown subcommand '$CMD' (project|project-sweep|sync|close|push|open|status|ci-scan)"; exit 1 ;;
esac
