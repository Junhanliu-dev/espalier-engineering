#!/usr/bin/env bash
# maprun-pr.sh — the run lane's forge surface: slice PRs on the integration branch.
#
#   maprun-pr.sh <map-dir> setup          capability probe + push integration + CI-filter scan
#   maprun-pr.sh <map-dir> open <key>     push ticket branch, create-or-find its slice PR,
#                                         record the number/url in state.json
#   maprun-pr.sh <map-dir> sync           push the integration branch (fast-forward only)
#   maprun-pr.sh <map-dir> final          open the assembly PR integration → base
#
# Topology is untouched: merges stay local (maprun-merge.sh, union rules intact).
# `open` runs BEFORE the local merge; when `sync` then pushes the integration
# branch, the forge sees the PR's head contained in its base and closes the PR
# as merged on its own — the slice diff and its CI verdict are preserved there.
#
# Everything here is opt-in and best-effort:
#   - no `pr` key in plan.json      → every subcommand is a no-op (exit 0)
#   - gh missing / unauthenticated  → exit 5; the master warns and continues,
#                                     the local merge NEVER blocks on the forge
#   - a rejected push               → exit 1 and report; never force. Only the
#                                     master advances the remote integration
#                                     branch, so a rejection means someone else
#                                     wrote to it — a human should look.
#
# All pushes run from the main checkout ($REPO): the push block is worktree-
# scoped, so the operator's checkout — and therefore the master — can push.
#
# Exit codes:  0 done (or pr flow disabled)   5 forge unavailable   1 error
set -euo pipefail

MAP_DIR="${1:?usage: maprun-pr.sh <map-dir> setup|open <key>|sync|final}"
CMD="${2:?subcommand required: setup|open|sync|final}"
KEY="${3:-}"

MAP_DIR="$(cd "$MAP_DIR" && pwd)"
PLAN="$MAP_DIR/plan/plan.json"
REPO="$(git rev-parse --show-toplevel)"
HOOKS="$REPO/espalier/hooks"
[ -f "$PLAN" ] || { echo "pr: no plan.json at $PLAN"; exit 1; }

field() { # field <name> [ticket|plan]  (ticket scope needs $KEY)
  PLAN="$PLAN" KEY="$KEY" F="$1" SCOPE="${2:-plan}" python3 - << 'PYF'
import json, os
p = json.load(open(os.environ["PLAN"]))
key, f, scope = os.environ["KEY"], os.environ["F"], os.environ["SCOPE"]
if scope == "ticket":
    t = next((x for x in p["tickets"] if x["key"] == key), None)
    if t is None:
        raise SystemExit(f"unknown ticket {key}")
    src = t
else:
    src = p
v = src.get(f, "")
print("" if v is None else v)
PYF
}

prcfg() { # prcfg <subkey> [default]
  PLAN="$PLAN" K="$1" D="${2:-}" python3 - << 'PYP'
import json, os
pr = json.load(open(os.environ["PLAN"])).get("pr")
if not isinstance(pr, dict):
    print("")
else:
    v = pr.get(os.environ["K"], os.environ["D"])
    if isinstance(v, bool):
        print("true" if v else "false")
    elif isinstance(v, list):
        print("\n".join(str(x) for x in v))
    else:
        print("" if v is None else v)
PYP
}

# ── opt-in gate: no `pr` config → the whole flow is a silent no-op ───────────
HAS_PR="$(PLAN="$PLAN" python3 -c 'import json,os;print("yes" if isinstance(json.load(open(os.environ["PLAN"])).get("pr"), dict) else "no")')"
if [ "$HAS_PR" != "yes" ]; then
  echo "pr: flow disabled (no \`pr\` config in plan.json) — nothing to do"
  exit 0
fi

INTEGRATION="$(field integration_branch plan)"
BASE="$(field base_branch plan)"
REMOTE="$(prcfg remote origin)"; REMOTE="${REMOTE:-origin}"
DRAFT="$(prcfg draft false)"
MAP_NAME="$(field map plan)"

# ── forge availability (every subcommand needs it past this point) ───────────
if ! command -v gh >/dev/null 2>&1; then
  echo "pr: gh CLI not found — slice PRs skipped (local merge unaffected)"
  exit 5
fi
# `gh auth status` exits 1 if ANY configured account is broken, even when the
# ACTIVE one is fine (e.g. a stale second account in the keyring). Probe the
# active account's token instead — that is the one every call here uses.
if ! gh auth token >/dev/null 2>&1; then
  echo "pr: gh has no usable active account (gh auth login) — slice PRs skipped"
  exit 5
fi

push_branch() { # push_branch <branch>  — fast-forward push from the main checkout
  local out
  if out="$(git -C "$REPO" push "$REMOTE" "$1" 2>&1)"; then
    echo "  pushed $1 → $REMOTE"
  else
    echo "  ERROR: push of $1 rejected — only the master writes these branches,"
    echo "  so someone else touched the remote. Git said:"
    echo "$out" | sed 's/^/    /' | head -6
    return 1
  fi
}

find_pr() { # find_pr <head> <base>  → "number<TAB>url" or nothing
  gh pr list --head "$1" --base "$2" --state all \
     --json number,url --limit 1 \
     --template '{{range .}}{{.number}}{{"\t"}}{{.url}}{{end}}' 2>/dev/null \
  || true
}

case "$CMD" in
  # ───────────────────────────────────────────────────────────────── setup ──
  setup)
    echo "pr: setup ($REMOTE, integration $INTEGRATION)"
    # Write capability: a read-only token satisfies `auth status` and still
    # fails at the first push — probe for push permission up front.
    PERM="$(gh api repos/{owner}/{repo} --jq .permissions.push 2>/dev/null || echo unknown)"
    case "$PERM" in
      true)    echo "  push permission: yes" ;;
      false)   echo "  ERROR: the gh token has no push permission on this repo"; exit 5 ;;
      *)       echo "  push permission: could not verify (non-GitHub remote?) — continuing" ;;
    esac
    # Setup normally runs right after `init`, before the first dispatch has
    # created the integration branch — create it here the same way dispatch
    # would, so the CI scan and the first push happen up front.
    if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$INTEGRATION"; then
      echo "  creating integration branch $INTEGRATION from $BASE"
      git -C "$REPO" branch "$INTEGRATION" "$BASE"
    fi
    push_branch "$INTEGRATION"
    # CI trigger scan: a pull_request workflow whose `branches:` filter does
    # not match the integration branch will run NOTHING on slice PRs — the
    # failure is a silent green PR. Warn now, not at the first slice.
    # Reads each workflow FROM THE INTEGRATION BRANCH (slice-PR merge refs
    # take the file from there), falling back to the checkout. Workflows that
    # fire only on `types: [closed]` (deploy-on-merge triggers) are skipped —
    # slice PRs must NOT be added to those.
    WFDIR="$REPO/.github/workflows"
    if [ -d "$WFDIR" ]; then
      REPO="$REPO" WFDIR="$WFDIR" INTEGRATION="$INTEGRATION" python3 - << 'PYCI'
import fnmatch, os, re, subprocess
repo = os.environ["REPO"]
wfdir, integ = os.environ["WFDIR"], os.environ["INTEGRATION"]

def items(raw, bracketed):
    # YAML strips inline comments; do the same before matching.
    out = []
    for x in (raw.split(",") if bracketed else re.findall(r"-\s*(.+)", raw)):
        x = x.split("#", 1)[0].strip().strip("'\"").strip()
        if x:
            out.append(x)
    return out
for name in sorted(os.listdir(wfdir)):
    if not name.endswith((".yml", ".yaml")):
        continue
    r = subprocess.run(
        ["git", "-C", repo, "show", f"{integ}:.github/workflows/{name}"],
        capture_output=True, text=True)
    if r.returncode == 0:
        text = r.stdout
    else:
        try:
            text = open(os.path.join(wfdir, name), errors="replace").read()
        except OSError:
            continue
    m = re.search(r"^\s*pull_request\s*:\s*\n((?:\s{2,}.*\n?)*)", text, re.M)
    if not m:
        continue
    block = m.group(1)
    t = re.search(r"types\s*:\s*\[([^\]]*)\]", block) \
        or re.search(r"types\s*:\s*\n((?:\s*-\s*.+\n?)+)", block)
    if t:
        types = items(t.group(1), "[" in t.group(0))
        if types and set(types) <= {"closed"}:
            continue  # merge/deploy trigger — slice PRs SHOULD stay out of it
    b = re.search(r"branches\s*:\s*\[([^\]]*)\]", block) \
        or re.search(r"branches\s*:\s*\n((?:\s*-\s*.+\n?)+)", block)
    if not b:
        continue  # unfiltered pull_request — fires on slice PRs, fine
    pats = items(b.group(1), "[" in b.group(0))
    if not any(fnmatch.fnmatch(integ, p) for p in pats):
        print(f"  WARNING: {name} filters pull_request to {pats} — slice PRs "
              f"against '{integ}' will NOT trigger it. Commit '{integ}' (or a "
              f"matching pattern) into that filter ON THE INTEGRATION BRANCH "
              f"so every slice PR's merge ref carries it.")
PYCI
    fi
    echo "  setup complete"
    ;;

  # ────────────────────────────────────────────────────────────────── open ──
  open)
    [ -n "$KEY" ] || { echo "pr: open needs a ticket key"; exit 1; }
    SLUG="$(field slug ticket)"
    NAME="$(field name ticket)"
    BRANCH="espalier/${SLUG}"
    echo "pr: open $KEY ($BRANCH → $INTEGRATION)"
    git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH" \
      || { echo "  ERROR: branch $BRANCH does not exist"; exit 1; }
    # Base must exist on the remote before a PR can target it.
    push_branch "$INTEGRATION"
    push_branch "$BRANCH"
    EXISTING="$(find_pr "$BRANCH" "$INTEGRATION")"
    if [ -n "$EXISTING" ]; then
      NUM="${EXISTING%%$'\t'*}"; URL="${EXISTING#*$'\t'}"
      echo "  slice PR already exists: #$NUM"
    else
      BODY="Espalier slice \`$SLUG\` of map \`$MAP_NAME\` — stages 1–6 clean
(grill + reviewer + security passed in the worker; see the change folder's
records).

This PR is the review surface for this slice. The map runner merges the
branch into \`$INTEGRATION\` locally (union-merge rules applied) and pushes;
the PR then closes as merged on its own. Review comments become follow-up
fix tickets — nothing in the run blocks on them. The final assembly PR
against \`$BASE\` links every slice."
      CREATE_ARGS=(--head "$BRANCH" --base "$INTEGRATION" --title "$NAME" --body "$BODY")
      [ "$DRAFT" = "true" ] && CREATE_ARGS+=(--draft)
      while IFS= read -r lbl; do
        [ -n "$lbl" ] && CREATE_ARGS+=(--label "$lbl")
      done < <(prcfg labels)
      URL="$(gh pr create "${CREATE_ARGS[@]}" 2>&1)" \
        || { echo "  ERROR: gh pr create failed:"; echo "$URL" | sed 's/^/    /' | head -6; exit 5; }
      URL="$(printf '%s\n' "$URL" | grep -Eo 'https?://[^ ]+/pull/[0-9]+' | head -1)"
      NUM="${URL##*/}"
      echo "  opened slice PR #$NUM"
    fi
    python3 "$HOOKS/maprun.py" "$MAP_DIR" set-pr "$KEY" "$NUM" "$URL" >/dev/null
    echo "  recorded: PR #$NUM — $URL"
    ;;

  # ────────────────────────────────────────────────────────────────── sync ──
  sync)
    echo "pr: sync ($INTEGRATION → $REMOTE)"
    push_branch "$INTEGRATION"
    ;;

  # ───────────────────────────────────────────────────────────────── final ──
  final)
    echo "pr: final ($INTEGRATION → $BASE)"
    push_branch "$INTEGRATION"
    EXISTING="$(find_pr "$INTEGRATION" "$BASE")"
    if [ -n "$EXISTING" ]; then
      NUM="${EXISTING%%$'\t'*}"; URL="${EXISTING#*$'\t'}"
      echo "  assembly PR already exists: #$NUM — $URL"
      exit 0
    fi
    # Body: one line per ticket with its slice PR — the review trail.
    SLICES="$(PLAN="$PLAN" STATE="$MAP_DIR/plan/state.json" python3 - << 'PYB'
import json, os
plan = json.load(open(os.environ["PLAN"]))
try:
    state = json.load(open(os.environ["STATE"]))["tickets"]
except Exception:
    state = {}
for t in plan["tickets"]:
    st = state.get(t["key"], {})
    n, u = st.get("pr_number"), st.get("pr_url")
    tail = f"#{n} ({u})" if n else "(no slice PR recorded)"
    print(f"- `{t['key']}` {t.get('name', '')} — {tail}")
PYB
)"
    VERIFY_NOTE=""
    [ -f "$MAP_DIR/plan/verify-report.md" ] \
      && VERIFY_NOTE="$(grep -m1 'VERDICT' "$MAP_DIR/plan/verify-report.md" || true)"
    BODY="Assembly of Espalier map \`$MAP_NAME\` — every slice built, tested
and reviewed on its own PR:

$SLICES

$VERIFY_NOTE

Every line of this diff was reviewed on its slice PR above; this PR is the
CI + sign-off gate. Merging it is a human act."
    URL="$(gh pr create --head "$INTEGRATION" --base "$BASE" \
             --title "map($MAP_NAME): assembled integration branch" \
             --body "$BODY" 2>&1)" \
      || { echo "  ERROR: gh pr create failed:"; echo "$URL" | sed 's/^/    /' | head -6; exit 5; }
    URL="$(printf '%s\n' "$URL" | grep -Eo 'https?://[^ ]+/pull/[0-9]+' | head -1)"
    echo "  opened assembly PR ${URL##*/}: $URL"
    ;;

  *)
    echo "pr: unknown subcommand '$CMD' (setup|open|sync|final)"; exit 1 ;;
esac
