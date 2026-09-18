#!/usr/bin/env bash
# espalier-pr.sh — the pipeline's forge surface: the code PR and its espalier
# sibling.
#
#   espalier-pr.sh <type> <slug> project [msg] [path...]
#                                               project the named espalier/ paths onto
#                                               the espalier branch and commit them there
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

TYPE="${1:?usage: espalier-pr.sh <type> <slug> project|push|open|status}"
SLUG="${2:?slug required}"
CMD="${3:?subcommand required: project|push|open|status}"
MSG="${4:-}"
shift 4 2>/dev/null || shift $#   # anything left is an explicit path list for `project`

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

base_ref() {  # the Stage 3 certificate anchor; merge-base is the legacy fallback
  local r
  r="$(grep -E '^(- )?Base-Ref:' "$STATE" 2>/dev/null | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')"
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

    # WHAT gets projected is explicit, never "whatever is dirty under espalier/".
    # A whole-tree copy sweeps in other in-flight changes' records, migration
    # .bak backups, and any unrelated local edit — all of which would land in
    # THIS change's pull request. Default: this change's own records, plus the
    # convention index when the run wrote there. The sweep passes its own paths.
    if [ "$#" -gt 0 ]; then
      PATHS="$*"
    else
      PATHS="espalier/changes/$TYPE/$SLUG"
      [ -d "$REPO/espalier/conventions" ] && PATHS="$PATHS espalier/conventions"
    fi

    WT="$(mktemp -d "${TMPDIR:-/tmp}/espalier-pr-XXXXXX")"
    cleanup() { git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || true; }
    trap cleanup EXIT
    git -C "$REPO" worktree add --quiet "$WT" "$ESP_BRANCH"

    # ADD collects only the paths that actually exist, because `git add -- <path>`
    # exits 128 on a pathspec that matches nothing and would abort the run under
    # `set -e`. A path the caller named but that is not present is reported, not
    # fatal: the sweep names espalier/wiki and espalier/rules unconditionally,
    # and an install may legitimately have neither.
    ADD=""
    MISSING=""
    for rel in $PATHS; do
      if [ ! -e "$REPO/$rel" ]; then MISSING="$MISSING $rel"; continue; fi
      ADD="$ADD $rel"
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
    done

    [ -n "$MISSING" ] && echo "pr: not present, skipped —$MISSING"
    if [ -z "$ADD" ]; then
      echo "pr: nothing to project onto $ESP_BRANCH (no named path exists)"
      exit 0
    fi

    # Scoped to the paths named above. `-A espalier/` would stage anything else
    # that differs under espalier/, which is the whole-tree behaviour this
    # subcommand exists to avoid — it is equivalent only while the worktree
    # happens to be otherwise clean, and that is not a property to rely on.
    git -C "$WT" add -A -- $ADD
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
    # looks like JSON — a check context is a plain name.
    REQUIRED=""
    if command -v gh >/dev/null 2>&1 && gh auth token >/dev/null 2>&1; then
      if _rq="$(gh api "repos/{owner}/{repo}/branches/$BASE_BRANCH/protection/required_status_checks" \
                  --jq '.contexts[]?' 2>/dev/null)"; then
        REQUIRED="$(printf '%s\n' "$_rq" | grep -v '[{}]' || true)"
      fi
    fi

    WFDIR="$WFDIR" FILES="$FILES" REQUIRED="$REQUIRED" BASE_BRANCH="$BASE_BRANCH" python3 - << 'PYCI'
import os, re, sys

wfdir = os.environ["WFDIR"]
files = [f for f in os.environ["FILES"].split("\n") if f.strip()]
required = [c for c in os.environ["REQUIRED"].split("\n") if c.strip()]
base = os.environ["BASE_BRANCH"]

def items(raw, bracketed):
    out = []
    for x in (raw.split(",") if bracketed else re.findall(r"-\s*(.+)", raw)):
        x = x.split("#", 1)[0].strip().strip("'\"").strip()
        if x:
            out.append(x)
    return out

def to_re(pat):
    # GitHub filter globs: ** crosses /, * and ? do not. Build the regex in one
    # pass so a literal '*' after '**' is not re-expanded.
    out, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c == "*":
            if pat[i:i + 2] == "**":
                out.append(".*"); i += 2; continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")

def find_block(text, key):
    m = re.search(r"^\s*%s\s*:\s*\n((?:\s{2,}.*\n?)*)" % key, text, re.M)
    return m.group(1) if m else None

def filt(block, key):
    b = re.search(r"%s\s*:\s*\[([^\]]*)\]" % key, block) \
        or re.search(r"%s\s*:\s*\n((?:\s*-\s*.+\n?)+)" % key, block)
    return items(b.group(1), "[" in b.group(0)) if b else None

skipped, runs, negated = [], [], []
for name in sorted(os.listdir(wfdir)):
    if not name.endswith((".yml", ".yaml")):
        continue
    try:
        text = open(os.path.join(wfdir, name), errors="replace").read()
    except OSError:
        continue
    # `or` would be wrong here: a bare `pull_request:` with no sub-keys yields an
    # EMPTY block, which is falsy but entirely valid — and it is the commonest
    # shape there is. Test for None explicitly or those workflows vanish from
    # the report, which are exactly the ones that do run on the espalier PR.
    block = find_block(text, "pull_request")
    if block is None:
        block = find_block(text, "pull_request_target")
    if block is None:
        continue
    types = filt(block, "types")
    if types and set(types) <= {"closed"}:
        continue   # deploy-on-merge trigger; PRs are not meant to fire it
    br = filt(block, "branches")
    if br and not any(to_re(p).match(base) for p in br):
        continue   # does not run on either PR — pre-existing, not ours
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
    print("  %d workflow(s) use '!' negation in a path filter and were NOT evaluated:"
          " %s — check them by hand." % (len(negated), ", ".join(negated)))
if not (skipped or runs or negated):
    print("  no pull_request workflow affects the espalier PR")
PYCI
    ;;

  *)
    echo "pr: unknown subcommand '$CMD' (project|push|open|status|ci-scan)"; exit 1 ;;
esac
