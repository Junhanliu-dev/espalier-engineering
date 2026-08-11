#!/usr/bin/env bash
# maprun-dispatch.sh — start one headless espalier worker for one ticket.
#
#   maprun-dispatch.sh <map-dir> <ticket-key> [--dry-run]
#
# Creates an isolated git worktree on its own branch off the integration
# branch, makes `git push` physically impossible inside it, spawns a headless
# worker (claude -p or codex exec, per plan.json worker_platform) running the
# espalier pipeline, and records pid/paths in state.json.
#
# The worker never returns to this script — the master reaps it on a later pass
# by reading the sentinel it leaves behind. See espalier/skills/espalier-maprun/.
#
# Exit codes:
#   0 dispatched   3 integration-sync conflict (escalate the ticket)
#   4 unanswered question pending (relay it first)   1 other error
set -euo pipefail

MAP_DIR="${1:?usage: maprun-dispatch.sh <map-dir> <ticket-key> [--dry-run]}"
KEY="${2:?ticket key required}"
DRY_RUN="no"; [ "${3:-}" = "--dry-run" ] && DRY_RUN="yes"

MAP_DIR="$(cd "$MAP_DIR" && pwd)"
PLAN="$MAP_DIR/plan/plan.json"
REPO="$(git rev-parse --show-toplevel)"
HOOKS="$REPO/espalier/hooks"
[ -f "$PLAN" ] || { echo "dispatch: no plan.json at $PLAN"; exit 1; }

# Scalar lookup: ticket field wins over plan field when both asked.
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

# Array lookup: emits one TSV row per element of a list-of-objects key.
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

SLUG="$(field slug ticket)"
NAME="$(field name ticket)"
REQ="$(field requirement ticket)"
INTEGRATION="$(field integration_branch plan)"
BASE="$(field base_branch plan)"
WT_ROOT="$(field worktree_root plan)"
PERM="$(field permission_mode plan)"; PERM="${PERM:-bypassPermissions}"
# Never inherit the user's default model: a stricter-safeguard default (e.g.
# Fable) hard-refuses the autonomous-worker prompt and every dispatch dies.
MODEL="$(field model plan)"; MODEL="${MODEL:-opus}"
OUT_FMT="$(field output_format plan)"; OUT_FMT="${OUT_FMT:-stream-json}"
MAX_USD="$(field max_budget_usd plan)"
PLATFORM="$(field worker_platform plan)"; PLATFORM="${PLATFORM:-claude}"
WMODE="$(field worker_mode plan)"; WMODE="${WMODE:-session}"
SRC_SET="$(field worker_setting_sources plan)"
CHANGE_TYPE="$(field change_type plan)"; CHANGE_TYPE="${CHANGE_TYPE:-feat}"

[ -n "$SLUG" ] || { echo "dispatch: ticket $KEY has no slug"; exit 1; }

BRANCH="espalier/${SLUG}"
case "$WT_ROOT" in
  /*) WT_BASE="$WT_ROOT" ;;
  *)  WT_BASE="$REPO/$WT_ROOT" ;;
esac
WT="$WT_BASE/$(basename "$MAP_DIR")/$KEY"
LOGDIR="$MAP_DIR/plan/logs"
LOG="$LOGDIR/$KEY.log"
HB="$LOGDIR/$KEY.heartbeat"
QUESTIONS="$MAP_DIR/plan/questions"
CHANGE_REL="espalier/changes/$CHANGE_TYPE/$SLUG"
OUTCOME_REL="$CHANGE_REL/.maprun-outcome"
QUESTION_REL="$CHANGE_REL/.maprun-question.md"

echo "dispatch: $KEY"
echo "  slug      : $SLUG"
echo "  branch    : $BRANCH"
echo "  worktree  : $WT"
echo "  from      : $INTEGRATION"
echo "  platform  : $PLATFORM ($WMODE mode)"

if [ "$DRY_RUN" = "yes" ]; then
  echo "  DRY RUN — no worktree created, no worker spawned"
  exit 0
fi

mkdir -p "$LOGDIR" "$QUESTIONS" "$WT_BASE"

# ── an unanswered question blocks dispatch ───────────────────────────────────
# If the relay step (SKILL step 3) hasn't consumed this file, a fresh worker
# would be instantly re-PARKED by the next reap. Loud failure beats that.
if [ -f "$QUESTIONS/$KEY.md" ]; then
  echo "  ERROR: $QUESTIONS/$KEY.md still exists — relay it (SKILL step 3) before re-dispatching."
  exit 4
fi

# ── integration branch must exist ────────────────────────────────────────────
if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$INTEGRATION"; then
  echo "  creating integration branch $INTEGRATION from $BASE"
  git -C "$REPO" branch "$INTEGRATION" "$BASE"
fi

# ── union-merge the declared registries so concurrent tickets stop colliding ─
GA="$REPO/.gitattributes"
rows union_merge path | while IFS= read -r path; do
  [ -n "$path" ] || continue
  grep -qsF "$path merge=union" "$GA" 2>/dev/null && continue
  if [ -s "$GA" ] && [ -n "$(tail -c1 "$GA")" ]; then printf '\n' >> "$GA"; fi
  echo "$path merge=union" >> "$GA"
  echo "  added union-merge rule for $path"
done

# ── worktree (reuse on resume) ───────────────────────────────────────────────
if [ -d "$WT" ]; then
  echo "  reusing existing worktree (resume)"
  # A resumed worker must see what landed on the integration branch after it
  # first branched — relayed answers, merged sibling slices. Checkpoint any
  # half-written work first so the sync can never clobber it.
  if [ -n "$(git -C "$WT" status --porcelain)" ]; then
    git -C "$WT" add -A
    # Explicit identity: a host with no global git user must not silently
    # lose the checkpoint (the || true would swallow the failure).
    git -C "$WT" -c user.email=maprun@espalier -c user.name=maprun \
      commit --quiet -m "wip(maprun): auto-checkpoint before integration sync" || true
    echo "  checkpointed uncommitted work"
  fi
  if ! git -C "$WT" -c user.email=maprun@espalier -c user.name=maprun \
       merge --no-edit --quiet "$INTEGRATION" >/dev/null 2>&1; then
    git -C "$WT" merge --abort >/dev/null 2>&1 || true
    echo "  ERROR: syncing $INTEGRATION into $BRANCH conflicts — needs a human."
    echo "  Then: maprun.py mark $KEY ESCALATED --error 'integration sync conflict'"
    exit 3
  fi
else
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO" worktree add "$WT" "$BRANCH"
  else
    git -C "$REPO" worktree add -b "$BRANCH" "$WT" "$INTEGRATION"
  fi
fi

# ── make push physically impossible in this worktree ─────────────────────────
# Config, not instruction: an autonomous agent cannot talk its way past this.
# MUST be --worktree scoped: a plain `git config` inside a worktree writes the
# SHARED .git/config, which would block the operator's own checkout too. That
# needs extensions.worktreeConfig on the repo first.
git -C "$REPO" config extensions.worktreeConfig true
git -C "$WT" config --worktree remote.origin.pushurl "blocked://maprun-forbids-push" || true
git -C "$WT" config --worktree push.default nothing || true
echo "  push blocked at git config level (worktree-scoped)"

# ── a stale question from a pass that never reaped would insta-PARK the worker
if [ -f "$WT/$QUESTION_REL" ]; then
  echo "  ERROR: $WT/$QUESTION_REL exists — run a reap (it collects the question), relay it, then re-dispatch."
  exit 4
fi

# ── workspace dependencies (plan.json `workspaces`) ──────────────────────────
# deps=clone: copy <dir>/<deps_dir> from the main checkout (cp -Rc = APFS
# clone-on-write on macOS, plain copy elsewhere). deps=install: run install_cmd.
# deps=none: skip. Symlinking is deliberately unsupported — bundlers (e.g.
# Turbopack) reject out-of-root node_modules symlinks.
rows workspaces dir,deps,deps_dir,install_cmd | while IFS=$'\t' read -r wsdir wsdeps wsddir wscmd; do
  [ -n "$wsdir" ] || continue
  wsddir="${wsddir:-node_modules}"
  [ -d "$REPO/$wsdir" ] || continue
  [ -e "$WT/$wsdir/$wsddir" ] && continue
  case "$wsdeps" in
    none) ;;
    clone)
      if [ -d "$REPO/$wsdir/$wsddir" ]; then
        cp -Rc "$REPO/$wsdir/$wsddir" "$WT/$wsdir/$wsddir" 2>/dev/null \
          || cp -R "$REPO/$wsdir/$wsddir" "$WT/$wsdir/$wsddir"
        echo "  cloned $wsdir/$wsddir"
      elif [ -n "$wscmd" ]; then
        (cd "$WT/$wsdir" && bash -c "$wscmd" >/dev/null 2>&1) || true
        echo "  installed $wsdir deps"
      fi
      ;;
    install|*)
      [ -n "$wscmd" ] || continue
      echo "  installing $wsdir deps (this can be slow)…"
      (cd "$WT/$wsdir" && bash -c "$wscmd" >/dev/null 2>&1) || true
      ;;
  esac
done

# ── the worker contract ──────────────────────────────────────────────────────
PROMPT_FILE="$LOGDIR/$KEY.prompt.txt"
cat > "$PROMPT_FILE" << EOF
You are an autonomous Espalier pipeline worker. You are running headless: there
is NO human to answer you, and any attempt to ask will hang forever.

TICKET: $NAME
REQUIREMENT: $REQ

Run the /espalier pipeline for that requirement. Its change folder already
exists at $CHANGE_REL/ with a drafted requirements.md AND a pipeline-state.md
carrying '- Status: FILED' — the FILED-skeleton scan must adopt that folder
rather than create a new one.

BEFORE ANYTHING ELSE, confirm both files exist. If either is missing the
branch is mis-based and you must NOT improvise a folder: write MISBASED to
$OUTCOME_REL and stop.

HARD RULES — these are not negotiable:

1. STAGES 1 THROUGH 6 ONLY. Stop after Stage 6 (test review) passes. Do NOT run
   Stage 7 (push), 8, 9 or 10. Commit your work to the current branch locally.
2. NEVER run 'git push'. Push is blocked at git config level in this worktree;
   attempting it wastes a turn and fails.
3. SKIP THE STAGE 1 GRILL. Requirements were already grilled during mapping and
   again by the run master; the answers are cited in requirements.md. Treat
   --no-grill as given.
4. READ SCOPE. You may read: your change folder ($CHANGE_REL/), espalier/rules/,
   espalier/wiki/, this map's decision tickets under espalier/maps/, and the
   source tree. You may NOT read other espalier/changes/ folders — sibling
   slices are other workers' business and reading them pollutes your run.
5. THE CHANGE FOLDER IS THE TICKET. Read $CHANGE_REL/requirements.md and treat
   it as THE requirements document, exactly as the normal /espalier runner
   does — the REQUIREMENT line above is only its title. Never rewrite it from
   scratch; the grill answers are already inside it.
6. KEEP pipeline-state.md CURRENT through every stage — '- Current Stage:',
   Stage History rows, and the '- Status:' line — exactly as the normal
   /espalier runner does. PRESERVE that Status line (the template lacks it;
   rewriting the file from the template silently drops it and breaks resume).
   Set it to IN_PROGRESS when you begin and to the terminal value when you stop.
7. If you hit a question you genuinely cannot answer from requirements.md, the
   map tickets, or espalier/rules/ — do NOT guess and do NOT stall. Write the
   question to $QUESTION_REL, then write the single word PARKED to
   $OUTCOME_REL and STOP immediately.
8. On finishing Stage 6 cleanly, write the single word PASSED to $OUTCOME_REL.
   If the pipeline escalates (review rounds exhausted, or an agent returns
   ESCALATION_REQUIRED), write ESCALATED to $OUTCOME_REL, the reason
   underneath, and STOP.
9. RESUME DISCIPLINE. If pipeline-state.md already exists for this change, a
   previous worker ran here and may have died mid-write. Before resuming,
   verify the worktree actually contains what pipeline-state.md claims — the
   commits and files of its recorded stage. If it claims more than the git
   evidence supports, correct pipeline-state.md down to what exists, then
   resume from there. The worktree is the fact; the state file is the claim.

The outcome sentinel is how the master learns what happened. Writing it is the
last thing you do, and you must always write exactly one.
EOF

# ── a re-dispatch must never inherit a previous attempt's verdict ────────────
rm -f "$WT/$OUTCOME_REL"

# ── spawn command builder (platform adapter) ─────────────────────────────────
# Emits to $LOGDIR/$KEY.spawn.sh a function `run_worker <extra-prompt-file>`
# that runs ONE headless session in $WT with the contract prompt (+ optional
# leg addendum), streaming to $LOG. worker_env pairs are exported first.
SPAWN="$LOGDIR/$KEY.spawn.sh"
{
  echo '#!/bin/bash'
  echo "# generated by maprun-dispatch.sh — spawn helper for $KEY"
  echo "cd '$WT' || exit 1"
  echo "export ESPALIER_UNATTENDED=1"
  # plan.json worker_env: {"KEY": "value", ...} — build-time seeds some stacks
  # need (values are placeholders/ephemeral, never real secrets).
  PLAN="$PLAN" python3 - << 'PYENV'
import json, os, shlex
p = json.load(open(os.environ["PLAN"]))
for k, v in (p.get("worker_env") or {}).items():
    print(f"export {k}={shlex.quote(str(v))}")
PYENV
  echo "run_worker() {"
  echo "  local extra=\"\${1:-}\""
  echo "  local ptmp; ptmp=\$(mktemp)"
  echo "  cat '$PROMPT_FILE' > \"\$ptmp\""
  echo "  [ -n \"\$extra\" ] && [ -f \"\$extra\" ] && cat \"\$extra\" >> \"\$ptmp\""
  case "$PLATFORM" in
    codex)
      # codex exec: non-interactive run. bypassPermissions maps to the
      # no-approvals full-access flag; anything else stays sandboxed full-auto.
      if [ "$PERM" = "bypassPermissions" ]; then
        CODEX_FLAGS="--dangerously-bypass-approvals-and-sandbox"
      else
        CODEX_FLAGS="--full-auto"
      fi
      echo "  codex exec $CODEX_FLAGS ${MODEL:+-m '$MODEL'} \"\$(cat \"\$ptmp\")\" >> '$LOG' 2>&1"
      ;;
    *)
      ARGS="--permission-mode '$PERM'"
      [ -n "$MODEL" ] && ARGS="$ARGS --model '$MODEL'"
      ARGS="$ARGS --output-format '$OUT_FMT'"
      # `claude -p --output-format stream-json` hard-errors without --verbose
      # ("requires --verbose") and the worker dies before its first turn.
      [ "$OUT_FMT" = "stream-json" ] && ARGS="$ARGS --verbose"
      # Optional context hygiene: strip user-level settings/hooks from workers.
      [ -n "$SRC_SET" ] && ARGS="$ARGS --setting-sources '$SRC_SET'"
      [ -n "$MAX_USD" ] && [ "$MAX_USD" != "0" ] && ARGS="$ARGS --max-budget-usd '$MAX_USD'"
      echo "  claude -p \"\$(cat \"\$ptmp\")\" $ARGS >> '$LOG' 2>&1"
      ;;
  esac
  echo "  local rc=\$?"
  echo "  rm -f \"\$ptmp\""
  echo "  return \$rc"
  echo "}"
} > "$SPAWN"
chmod +x "$SPAWN"

: > "$LOG"

if [ "$WMODE" = "staged" ]; then
  # ── staged worker: one fresh headless session per stage group ──────────────
  # Bounds worker context (long tickets never compact mid-pipeline) and gives
  # finer crash/quota resume. The wrapper — not the master — owns the loop, so
  # the worker still outlives the master. Escalates after 2 no-progress legs.
  WRAP="$LOGDIR/$KEY.worker.sh"
  cat > "$WRAP" << WRAPEOF
#!/bin/bash
# generated by maprun-dispatch.sh — staged worker wrapper for $KEY
source '$SPAWN'
OUTCOME='$WT/$OUTCOME_REL'
STATE='$WT/$CHANGE_REL/pipeline-state.md'
noprog=0; legs=0
while :; do
  [ -f "\$OUTCOME" ] && exit 0
  legs=\$((legs+1))
  if [ "\$legs" -gt 12 ]; then
    printf 'ESCALATED\nstaged wrapper: exceeded 12 legs without an outcome\n' > "\$OUTCOME"; exit 0
  fi
  stage=\$(grep -m1 '^- Current Stage:' "\$STATE" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1)
  stage=\${stage:-0}
  pre_log=\$(wc -c < '$LOG' 2>/dev/null); pre_log=\${pre_log:-0}
  if [ "\$stage" -lt 3 ]; then
    boundary="Stage 2 passes (requirements review clean; unattended auto-approval applies)"
  elif [ "\$stage" -lt 5 ]; then
    boundary="the Stage 4 panel passes and the Reviewed-Diff certificate is recorded"
  else
    boundary="Stage 6 passes (then write the PASSED sentinel per the contract)"
  fi
  legf=\$(mktemp)
  printf '\nTHIS LEG ONLY: continue the pipeline from the stage recorded in pipeline-state.md. STOP and end your session cleanly once %s. Do NOT write the outcome sentinel except as rules 7-8 direct (PASSED only after Stage 6; PARKED/ESCALATED/MISBASED whenever their conditions occur, any leg). A fresh session continues from pipeline-state.md after you exit.\n' "\$boundary" > "\$legf"
  run_worker "\$legf"
  rm -f "\$legf"
  [ -f "\$OUTCOME" ] && exit 0
  # A usage-limit death must surface as resumable QUOTA, not a wrapper
  # escalation: exit with NO sentinel so reap's log check classifies it.
  # Only THIS leg's output is scanned — an old quota line must not re-trigger.
  if tail -c "+\$((pre_log + 1))" '$LOG' 2>/dev/null \
     | grep -qiE 'usage limit|rate.?limit|quota|"status" *: *429|overloaded|insufficient.*credit|exceeded.*budget'; then
    exit 0
  fi
  new_stage=\$(grep -m1 '^- Current Stage:' "\$STATE" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1)
  new_stage=\${new_stage:-0}
  if [ "\$new_stage" -le "\$stage" ]; then noprog=\$((noprog+1)); else noprog=0; fi
  if [ "\$noprog" -ge 2 ]; then
    printf 'ESCALATED\nstaged wrapper: no stage progress across 2 legs (stage %s)\n' "\$new_stage" > "\$OUTCOME"; exit 0
  fi
done
WRAPEOF
  chmod +x "$WRAP"
  ( nohup bash "$WRAP" >> "$LOG" 2>&1 & echo $! > "$LOGDIR/$KEY.pid" ) </dev/null
else
  # ── session worker: one headless session runs the whole ticket ─────────────
  ( nohup bash -c "source '$SPAWN'; run_worker" >> "$LOG" 2>&1 & echo $! > "$LOGDIR/$KEY.pid" ) </dev/null
fi

# The pid file is written by a backgrounded subshell — under load it can lag
# well past a fixed sleep, and a missing read here would abort dispatch AFTER
# the worker spawned (orphan worker, no state record). Wait for it properly.
PID=""
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$LOGDIR/$KEY.pid" ] && { PID="$(cat "$LOGDIR/$KEY.pid")"; break; }
  sleep 1
done
[ -n "$PID" ] || { echo "  ERROR: worker pid never appeared in $LOGDIR/$KEY.pid"; exit 1; }

# Heartbeat: driven by the supervisor, not the agent, so it measures process
# liveness rather than the agent's willingness to report it.
(
  while kill -0 "$PID" 2>/dev/null; do
    date -u +%s > "$HB"
    sleep 60
  done
) >/dev/null 2>&1 &

python3 "$HOOKS/maprun.py" "$MAP_DIR" mark "$KEY" DISPATCHED \
  --pid "$PID" --worktree "$WT" --branch "$BRANCH" --log "$LOG" >/dev/null

echo "  spawned pid $PID → $LOG"

# ── auto-dashboard (best-effort, never fatal) ────────────────────────────────
# Pop a live read-only `watch` TUI in the operator's terminal app when workers
# start. Skipped when: plan sets auto_dashboard=false, MAPRUN_NO_DASHBOARD=1
# (the test suite sets this), CI, no GUI available, or a watch is already
# running for this map (so a 3-worker pass opens ONE window, not three).
open_dashboard() {
  [ "${MAPRUN_NO_DASHBOARD:-0}" = "1" ] && return 0
  [ "${CI:-}" = "1" ] && return 0
  [ "${CI:-}" = "true" ] && return 0
  [ "$(field auto_dashboard)" = "false" ] && return 0
  pgrep -f "maprun.py $MAP_DIR watch" >/dev/null 2>&1 && return 0
  WATCH_CMD="python3 '$HOOKS/maprun.py' '$MAP_DIR' watch"
  if [ "$(uname)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
    osascript >/dev/null 2>&1 << OSA
tell application "Terminal"
  activate
  do script "$WATCH_CMD"
end tell
OSA
    echo "  dashboard opened (Terminal window — read-only watch)"
  elif [ -n "${DISPLAY:-}" ]; then
    for T in x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
      command -v "$T" >/dev/null 2>&1 || continue
      case "$T" in
        gnome-terminal) "$T" -- bash -lc "$WATCH_CMD" >/dev/null 2>&1 & ;;
        *)              "$T" -e "bash -lc \"$WATCH_CMD\"" >/dev/null 2>&1 & ;;
      esac
      echo "  dashboard opened ($T — read-only watch)"
      break
    done
  fi
  return 0
}
open_dashboard || true
