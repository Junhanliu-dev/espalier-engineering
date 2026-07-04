#!/bin/bash
# Migrate an Espalier v0.8.2 target repo to v0.9.0.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.9.0 adds a SECURITY AUDIT to the pipeline. A new `harness-security` agent
# joins Stage 4 as a second reviewer in the same fixpoint loop — it audits the
# change's trust boundary (never trust data the frontend sent) and hard-blocks on
# any client-trusted sensitive field (price, userId, role, orderId, status, …).
# Its findings become an abuse-test contract Stage 5 must satisfy and Stage 6
# enforces. A new always-loaded `security-standards.md` rule carries the field
# taxonomy that harness-coder also reads at write-time, and the push gate gains a
# secret scan (blocks) + dependency audit (warns).
#
# v0.9.0 also ships /espalier-audit — a standalone repo-wide audit lane: it runs
# harness-security in repo-audit mode over the EXISTING code (not a change diff),
# writes the findings inventory to espalier/wiki/security-audit.md, and hands
# selected findings to /espalier-fix. Pure-copy skill + a "## Repo-Audit Mode"
# section in the harness-security agent.
#
# This migration:
#   1. Backs up any customised pure-copy pipeline file → <file>.pre-v0.9.0.bak
#   2. Creates the 3 new per-project files (security-standards rule,
#      harness-security agent, espalier-security skill) with project-name +
#      tools-mode substitution.
#   3. bootstrap --force — refreshes the pure-copy pipeline files (Stage 4 panel +
#      abuse-test coupling), copies + symlinks the espalier-audit skill, symlinks
#      the 3 new files, runs the 37-check validation.
#   4. Appends the security sections to harness-coder / harness-reviewer / testing,
#      and the Repo-Audit Mode section to harness-security (pre-fold installs).
#   5. Inserts the secret/dependency scan into the LLM-written push gate.
#   6. Patches CLAUDE.md + espalier/agent.md to mention /espalier-audit.
#   7. Verifies everything landed.
#
# What this script does NOT do:
#   - Fill the {discovered} sections of security-standards.md (trust boundary +
#     project-specific sensitive fields). The universal taxonomy/controls are live
#     immediately; run /espalier-doctor (or edit the file) to fill the discovered
#     parts from your codebase.
#   - Re-gate any in-flight change. v0.9.0 affects new pipeline runs.
#
# Usage:
#   bash migrate-v0.8.2-to-v0.9.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)            DRY_RUN=yes ;;
    --yes)                SKIP_PROMPT=yes ;;
    --plugin-dir=*)       PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)
      sed -n '2,38p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.8.2→v0.9.0] $*"; }

CODER="espalier/agents/harness-coder.md"
REVIEWER="espalier/agents/harness-reviewer.md"
SECAGENT="espalier/agents/harness-security.md"
SECRULE="espalier/rules/security-standards.md"
SECSKILL="espalier/skills/espalier-security/SKILL.md"
AUDITSKILL="espalier/skills/espalier-audit/SKILL.md"
PRODRULE="espalier/rules/production-standards.md"
REVIEWSKILL="espalier/skills/espalier-review/SKILL.md"
TESTING="espalier/skills/espalier-testing/SKILL.md"
GATE="espalier/hooks/pre-push-gate.sh"

# insert_after FILE ANCHOR TEXT — insert TEXT after the first line containing
# ANCHOR (fixed string). Staged through a temp file + getline, NOT `awk -v`:
# BSD/macOS awk rejects a literal newline inside a -v value.
insert_after() {
  local file="$1" anchor="$2" text="$3"
  grep -qF "$anchor" "$file" 2>/dev/null || return 1
  local insf; insf=$(mktemp) || return 2
  printf '%s\n' "$text" > "$insf"
  local tmp; tmp=$(mktemp "${file}.XXXXXX") || { rm -f "$insf"; return 2; }
  awk -v anchor="$anchor" -v insf="$insf" '
    { print }
    index($0, anchor) && !done {
      while ((getline line < insf) > 0) print line
      close(insf)
      done=1
    }
  ' "$file" > "$tmp"
  local rc=$?
  [ "$rc" -eq 0 ] && mv "$tmp" "$file" || rm -f "$tmp"
  rm -f "$insf"
  return $rc
}

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run the earlier migrations first (via /espalier-migrate)." >&2
  exit 1
fi

if [ ! -d "espalier" ]; then
  echo "ERROR: no espalier/ directory — not an Espalier install." >&2
  echo "Use /espalier-init to set up Espalier in a fresh project." >&2
  exit 1
fi

if [ ! -f "espalier/.merge-hook-decision" ]; then
  echo "ERROR: espalier/.merge-hook-decision missing — install looks incomplete." >&2
  echo "Re-run /espalier-init (or bootstrap-espalier.sh --force) to repair it first." >&2
  exit 1
fi

# Prerequisite: v0.8.2 must already be applied (the pipeline carries the fixpoint
# loop the Stage 4 panel extends). The chain runs in order; guard anyway.
if ! grep -qF "fixpoint loop" espalier/pipeline.md 2>/dev/null; then
  echo "ERROR: espalier/pipeline.md has no 'fixpoint loop' (pre-v0.8.2)." >&2
  echo "Run /espalier-migrate to apply the v0.8.2 patch first." >&2
  exit 1
fi

# Already-v0.9.0 detector — ALL TEN artifacts must be present (security + audit + production), not just the two
# that Step 3 (bootstrap) produces. Checking only panel+agent would report "done"
# after a crash between Step 3 and Step 4, leaving the coder/reviewer/testing
# appends and the gate scan missing — a silently incomplete install that a re-run
# would refuse to finish. The audit-lane artifacts (skill + repo-audit mode) are
# part of the same check so an install migrated before the audit-lane fold-in is
# completed on re-run.
PANEL_DONE=no; AGENT_DONE=no; CODER_DONE=no; REVIEWER_DONE=no; GATE_DONE=no
AUDIT_DONE=no; MODE_DONE=no
grep -qF "review panel" espalier/pipeline.md 2>/dev/null && PANEL_DONE=yes
[ -f "$SECAGENT" ] && AGENT_DONE=yes
grep -qF "## Security-Aware Coding" "$CODER" 2>/dev/null && CODER_DONE=yes
grep -qF "## Security Abuse-Test Coverage" "$REVIEWER" 2>/dev/null && REVIEWER_DONE=yes
grep -qF "Security scan: secrets BLOCK" "$GATE" 2>/dev/null && GATE_DONE=yes
[ -f "$AUDITSKILL" ] && AUDIT_DONE=yes
grep -qF "## Repo-Audit Mode" "$SECAGENT" 2>/dev/null && MODE_DONE=yes
# Production-hardening artifacts (folded into v0.9.0): the always-loaded rule, the
# coder's production section, and the gate's cwd fail-closed guard. Included in
# the already-done check so an install migrated before the fold is completed on re-run.
PROD_DONE=no; PRODCODER_DONE=no; GATECD_DONE=no
[ -f "$PRODRULE" ] && PROD_DONE=yes
grep -qF "## Production-Aware Coding" "$CODER" 2>/dev/null && PRODCODER_DONE=yes
grep -qF "cd defensively too" "$GATE" 2>/dev/null && GATECD_DONE=yes
if [ "$PANEL_DONE" = yes ] && [ "$AGENT_DONE" = yes ] && [ "$CODER_DONE" = yes ] \
   && [ "$REVIEWER_DONE" = yes ] && [ "$GATE_DONE" = yes ] \
   && [ "$AUDIT_DONE" = yes ] && [ "$MODE_DONE" = yes ] \
   && [ "$PROD_DONE" = yes ] && [ "$PRODCODER_DONE" = yes ] && [ "$GATECD_DONE" = yes ]; then
  echo "Already on v0.9.0 (all security + production artifacts present)."
  echo "Nothing to do."
  exit 0
fi

# Locate the plugin root (must contain scripts/bootstrap-espalier.sh).
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/repos/espalier-engineering"; do
    if [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Update the plugin first (/plugin update espalier-engineering), or pass" >&2
  echo "--plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi

BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null)
DOCTOR_CADENCE=$(sed -n 's/^cadence: //p' espalier/.doctor-cadence 2>/dev/null)
[ -z "$DOCTOR_CADENCE" ] && DOCTOR_CADENCE=weekly

# Sanity-check the plugin actually carries the v0.9.0 templates before we touch anything.
if [ ! -f "$PLUGIN_INIT/templates/agents/harness-security.md" ]; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.9.0 (no harness-security template)." >&2
  echo "Update the plugin to v0.9.0+ (or pass --plugin-dir to a v0.9.0 checkout)." >&2
  exit 1
fi
if ! grep -qF "## Repo-Audit Mode" "$PLUGIN_INIT/templates/agents/harness-security.md" \
   || [ ! -f "$PLUGIN_INIT/templates/skills/espalier-audit.md" ]; then
  echo "ERROR: plugin at $PLUGIN_DIR predates the v0.9.0 audit-lane fold-in" >&2
  echo "(no Repo-Audit Mode section / espalier-audit template)." >&2
  echo "Update the plugin (or pass --plugin-dir to a current v0.9.0 checkout)." >&2
  exit 1
fi
if [ ! -f "$PLUGIN_INIT/templates/rules/production-standards.md" ] \
   || [ ! -f "$PLUGIN_INIT/templates/scout-prompts.md" ]; then
  echo "ERROR: plugin at $PLUGIN_DIR predates the v0.9.0 production-hardening fold-in" >&2
  echo "(no production-standards / scout-prompts template)." >&2
  echo "Update the plugin (or pass --plugin-dir to a current v0.9.0 checkout)." >&2
  exit 1
fi

# Derive the project name from the existing coder agent (best-effort; dir name fallback).
PROJECT_NAME=$(sed -n 's/^You are the coding agent for \(.*\)\. You implement.*/\1/p' "$CODER" 2>/dev/null | head -1)
# Fall back to the directory name if extraction failed, or if the coder agent
# itself still carries an unsubstituted placeholder (a broken/partial install).
case "$PROJECT_NAME" in ""|*"{project"*) PROJECT_NAME=$(basename "$PWD") ;; esac

# Detect tools-mode: if the coder has no `tools:` line, the install chose inherit.
AGENT_TOOLS=restricted
grep -qE '^tools:' "$CODER" 2>/dev/null || AGENT_TOOLS=inherit

cat << EOF

Espalier security audit upgrade (v0.8.2 → v0.9.0)

Plan:
  1. Backup-on-diff: any customised pipeline file → <file>.pre-v0.9.0.bak
  2. Create new files (project="$PROJECT_NAME", tools=$AGENT_TOOLS):
       $SECRULE
       $SECAGENT
       $SECSKILL
       $PRODRULE   (production NFR bar — always-loaded)
       (+ append the Repo-Audit Mode section to a pre-fold $SECAGENT)
  3. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → refreshes pure-copy pipelines (sentinel/gate/Stage-9), grill (TTY fix),
         drift-helpers/wrapper/lookup hooks, copies scout-prompts + audit skill,
         symlinks security + production rules; 37-check validation
  4. Append security + production sections to $CODER, $REVIEWER, $TESTING
  5. Insert the secret/dependency scan + cwd fail-closed guard into $GATE
  6. Patch CLAUDE.md + espalier/agent.md to mention /espalier-audit
  7. Verify everything landed

Plugin: $PLUGIN_DIR
EOF

if [ "$DRY_RUN" = "yes" ]; then
  echo "Mode: DRY RUN (no changes will be written)"
elif [ "$SKIP_PROMPT" != "yes" ]; then
  printf 'Apply upgrade? [y/N]: '
  read -r confirm
  case "$confirm" in
    y|Y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

# --- Text to append / insert ---------------------------------------------
# Like the production emitters below, the security sections are EXTRACTED from
# the plugin templates at run time (heading → next fixed heading) rather than
# duplicated here — the migration text can never drift from what a fresh
# install ships. The preflight already verified the plugin carries v0.9.0+
# templates, which is when these sections (and their anchors) appeared.

emit_coder_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/agents/harness-coder.md" \
    "## Security-Aware Coding (do this WHILE writing, not only at review)" \
    "## Production-Aware Coding (do this WHILE writing, not only at review)"
}

emit_reviewer_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/agents/harness-reviewer.md" \
    "## Security Abuse-Test Coverage (Stage 6 — test review)" \
    "## You Must NOT"
}

emit_testing_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/skills/espalier-testing.md" \
    "## Security Abuse Tests (when a security contract is present)" \
    "## Failure-Mode Tests (every NEW external-call path)"
}

# The Repo-Audit Mode section is EXTRACTED from the plugin's harness-security
# template at run time (heading → the line before "## You Must NOT") rather than
# duplicated here — the two can never drift. The preflight sanity check already
# guaranteed the section exists in the template.
emit_repo_audit_section() {
  printf '\n'
  awk '/^## Repo-Audit Mode/{f=1} f && /^## You Must NOT/{exit} f{print}' \
    "$PLUGIN_INIT/templates/agents/harness-security.md"
}

# Extract a "## Heading … up to the next '## '" section from a template file.
# Used for the production sections so the migration text can never drift from the
# templates a fresh install ships.
_extract_section() {   # file, start_heading, end_heading
  awk -v s="$2" -v e="$3" '$0==s{f=1} f && $0==e && $0!=s{exit} f{print}' "$1"
}
emit_prod_coder_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/agents/harness-coder.md" \
    "## Production-Aware Coding (do this WHILE writing, not only at review)" "## __none__"
}
emit_prod_reviewer_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/agents/harness-reviewer.md" \
    "## Production-Readiness Review (enforce espalier/rules/production-standards.md)" \
    "## Security Abuse-Test Coverage (Stage 6 — test review)"
}
emit_prod_testing_section() {
  printf '\n'
  _extract_section "$PLUGIN_INIT/templates/skills/espalier-testing.md" \
    "## Failure-Mode Tests (every NEW external-call path)" "## What NOT to Test"
}

# The VERDICT sentinel + overwrite-per-round contract lives inline in the fresh
# template's Output Format, which bootstrap --force does NOT re-copy to a
# per-project agent. Append it to a migrated agent so the refreshed orchestrator
# (which greps `^VERDICT:`) has a sentinel to read. Fresh installs already carry
# it inline — the Step-4 grep guard (`VERDICT:`) skips them.
emit_reviewer_sentinel_section() {
cat << 'EOF'

## Machine-Readable Verdict (v0.9.0 — required)

OVERWRITE your record each round (do not append across rounds — the orchestrator
snapshots each round's verdict into pipeline-state.md). End the file with this
sentinel as its LAST line — the orchestrator gates the fixpoint loop on it:

```
VERDICT: {PASS|PASS_WITH_FIXES|FAIL|ESCALATION_REQUIRED} p0={n} p1={n} round={n}
```

`p0=` must equal the number of P0 rows in your findings table. A missing or
mismatched sentinel is treated as an incomplete review — you will be re-spawned.
This verdict vocabulary is canonical (supersedes any "PASS WITH FIXES" spelling
in the review skill).
EOF
}
emit_security_sentinel_section() {
cat << 'EOF'

## Machine-Readable Verdict (v0.9.0 — required)

OVERWRITE security-record.md each round. End the file with this sentinel as its
LAST line (after the Security-Sensitive Fields contract when one is emitted) —
the orchestrator gates on it:

```
VERDICT: {PASS|PASS_WITH_FIXES|FAIL} p0={n} p1={n} round={n}
```

A NO SENSITIVE SURFACE self-noop still ends with `VERDICT: PASS p0=0 p1=0 round={n}`.
EOF
}

# Extracted from the plugin's pre-push-gate.sh template at run time (from the
# security-scan marker up to — not including — the build-check section), same
# no-drift rationale. The extracted block is placeholder-free; the {command}
# placeholders live in the sections the extraction stops before.
emit_gate_block() {
  awk '/^# --- Security scan: secrets BLOCK/{f=1}
       f && (/^# Run build check/ || /^# The three \{command\} placeholders/){exit}
       f{print}' "$PLUGIN_INIT/hook-templates/pre-push-gate.sh"
}

# append_section FILE MARKER EMIT_FN — append EMIT_FN's output to FILE unless
# MARKER is already present. Newline-guarded, dry-run aware, idempotent per file.
append_section() {
  local file="$1" marker="$2" emit_fn="$3"
  if [ ! -f "$file" ]; then
    echo "  WARN: $file not found — skipping (run /espalier-init to repair)." >&2; return 0
  fi
  if grep -qF "$marker" "$file"; then log "  already present in $file — skip."; return 0; fi
  if [ "$DRY_RUN" = "yes" ]; then log "  [dry-run] would append to $file"; return 0; fi
  [ -n "$(tail -c1 "$file" 2>/dev/null)" ] && echo >> "$file"
  "$emit_fn" >> "$file"
  log "  appended to $file"
}

# --- Step 1: backup-on-diff for pure-copy pipeline files ---------------------

log "Step 1: backup-on-diff for pure-copy pipeline files"
BACKUPS_MADE=""

backup_if_differs() {
  local current="$1" new_template="$2"
  [ -f "$current" ] || return 0
  if [ ! -f "$new_template" ]; then
    echo "  WARN: plugin template missing: $new_template (skipping backup check)" >&2
    return 0
  fi
  if cmp -s "$current" "$new_template"; then
    echo "  unchanged: $current (no backup needed)"; return 0
  fi
  local backup="${current}.pre-v0.9.0.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"; echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}

backup_if_differs "espalier/pipeline.md"                  "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "espalier/skills/espalier/SKILL.md"     "$PLUGIN_INIT/templates/skills/espalier.md"
backup_if_differs "espalier/skills/espalier-fix/SKILL.md" "$PLUGIN_INIT/templates/skills/espalier-fix.md"

# --- Step 2: create the 3 new per-project files ------------------------------

log "Step 2: create security rule + agent + skill"
create_new() {
  local dest="$1" src="$2" mode="$3"   # mode: raw | project
  if [ -f "$dest" ]; then echo "  exists: $dest (skip)"; return 0; fi
  if [ "$DRY_RUN" = "yes" ]; then echo "  [dry-run] create $dest from $(basename "$src")"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  if [ "$mode" = project ]; then
    sed -e "s/{project_name}/$PROJECT_NAME/g" -e "s/{project}/$PROJECT_NAME/g" "$src" > "$dest"
  else
    cp "$src" "$dest"
  fi
  echo "  created: $dest"
}

create_new "$SECRULE"  "$PLUGIN_INIT/templates/rules/security-standards.md"  raw
create_new "$SECAGENT" "$PLUGIN_INIT/templates/agents/harness-security.md"   project
create_new "$SECSKILL" "$PLUGIN_INIT/templates/skills/espalier-security.md"  project
# Production-hardening: the always-loaded NFR rule (raw — no {project} placeholder).
# MUST exist before Step 3's bootstrap --force (its check 36 requires the file,
# check 35 the symlink; a missing file would abort bootstrap).
create_new "$PRODRULE" "$PLUGIN_INIT/templates/rules/production-standards.md" raw

# inherit mode → strip the `tools:` frontmatter line from the new agent
if [ "$AGENT_TOOLS" = inherit ] && [ "$DRY_RUN" != yes ] && [ -f "$SECAGENT" ]; then
  grep -v '^tools:' "$SECAGENT" > "$SECAGENT.tmp.$$" && mv "$SECAGENT.tmp.$$" "$SECAGENT"
  echo "  tools-mode inherit: stripped 'tools:' from $SECAGENT"
fi

# Pre-fold installs: harness-security.md exists but predates repo-audit mode
# (create_new skips existing files). Fresh Step-2 creations already carry it —
# the grep guard makes this a no-op for them. MUST run before Step 3: bootstrap
# validation check 34 greps the agent for the section.
append_section "$SECAGENT" "## Repo-Audit Mode" emit_repo_audit_section

# --- Step 3: bootstrap --force (refresh pure-copy files + symlink new files) -

log "Step 3: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  if ! bash "$BOOTSTRAP" $BOOT_FLAGS; then
    echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
    exit 1
  fi
fi

# --- Step 4: append the fixed security sections to substitution files --------

log "Step 4: append security + production sections"
append_section "$CODER"    "## Security-Aware Coding"          emit_coder_section
append_section "$REVIEWER" "## Security Abuse-Test Coverage"   emit_reviewer_section
append_section "$TESTING"  "## Security Abuse Tests"           emit_testing_section
# Production-hardening sections (per-project files bootstrap --force cannot reach).
append_section "$CODER"    "## Production-Aware Coding"        emit_prod_coder_section
append_section "$REVIEWER" "## Production-Readiness Review"    emit_prod_reviewer_section
append_section "$TESTING"  "## Failure-Mode Tests"            emit_prod_testing_section
# VERDICT sentinel contract — per-project agents predate it; the refreshed
# orchestrator greps `^VERDICT:`. Guard on the sentinel token so a fresh install
# (carries it inline in Output Format) is a no-op.
append_section "$REVIEWER" "VERDICT:"                         emit_reviewer_sentinel_section
append_section "$SECAGENT" "VERDICT:"                         emit_security_sentinel_section

# --- Step 5: insert the secret/dependency scan into the push gate ------------

log "Step 5: insert the security scan into $GATE"
if [ ! -f "$GATE" ]; then
  echo "  WARN: $GATE not found — skipping (run /espalier-init to repair)." >&2
elif grep -qF "Security scan: secrets BLOCK" "$GATE"; then
  log "  already present — skip."
elif ! grep -qF "# Run build check" "$GATE"; then
  echo "  WARN: anchor '# Run build check' not found in $GATE — looks customised." >&2
  echo "  Add this block manually, immediately before your build check:" >&2
  emit_gate_block | sed 's/^/    | /' >&2
elif [ "$DRY_RUN" = "yes" ]; then
  log "  [dry-run] would insert before '# Run build check'"
else
  _tmp="${GATE}.tmp.$$"
  {
    awk '/^# Run build check/{exit} {print}' "$GATE"
    emit_gate_block
    echo ""
    awk 'f{print} !f && /^# Run build check/{f=1; print}' "$GATE"
  } > "$_tmp"
  mv "$_tmp" "$GATE"
  chmod +x "$GATE"
  log "  inserted."
fi

# --- Step 5b: gate cwd fail-closed guard (per-project pre-push-gate.sh) -------
# The wrapper (pure-copy, refreshed by bootstrap) now cd's to the repo root, but
# the gate is a per-project substitution file bootstrap --force does NOT touch.
# Insert a defensive `cd $(git rev-parse --show-toplevel)` right after the
# shebang so a direct/subdir invocation resolves the relative espalier/ paths
# instead of failing OPEN (the "No Espalier change record found → allow" hole).
log "Step 5b: insert cwd guard into $GATE"
if [ ! -f "$GATE" ]; then
  echo "  WARN: $GATE not found — skipping." >&2
elif grep -qF "cd defensively too" "$GATE"; then
  log "  already present — skip."
elif [ "$DRY_RUN" = "yes" ]; then
  log "  [dry-run] would insert cwd guard after the shebang"
else
  _tmp="${GATE}.cd.$$"
  {
    head -1 "$GATE"                       # the #!/bin/bash shebang
    cat << 'CDGUARD'
# Runs from the repo root: the wrapper cd's here, but cd defensively too so a
# direct invocation from a subdir still resolves the relative espalier/ paths
# below (a wrong cwd would make every -f test miss and fail OPEN).
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$_ROOT" ] && cd "$_ROOT" || true
CDGUARD
    tail -n +2 "$GATE"                    # everything after the shebang
  } > "$_tmp"
  mv "$_tmp" "$GATE"
  chmod +x "$GATE"
  log "  inserted."
fi

# --- Step 6: patch CLAUDE.md + espalier/agent.md ------------------------------
#
# bootstrap's CLAUDE.md writer is append-once (it skips when ## Espalier already
# exists), and it never touches the per-project agent.md — a migrated install
# needs both patched here. Warn-only on a missing anchor (user customisation).

CLAUDE_AUDIT_LINE='**For a repo-wide security audit**, use `/espalier-audit` — inventories trust-boundary defects in the existing code to `espalier/wiki/security-audit.md`; dispatch fixes via `/espalier-fix`.'
AUDIT_ROW='| Audit    | espalier/skills/espalier-audit/ | Repo-wide security audit → wiki/security-audit.md | Via /espalier-audit |'

log "Step 6: patch CLAUDE.md + espalier/agent.md"

if [ -f CLAUDE.md ]; then
  if grep -qF "/espalier-audit" CLAUDE.md; then
    echo "  CLAUDE.md already mentions /espalier-audit — skipping"
  elif ! grep -qF "## Espalier" CLAUDE.md; then
    echo "  CLAUDE.md has no ## Espalier section — skipping (user removed it?)"
  elif [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] insert /espalier-audit bullet into CLAUDE.md"
  else
    # After the /espalier-ask bullet (v0.7+); fall back to the bug-fixes bullet.
    if insert_after CLAUDE.md "**For questions**" "$(printf '\n%s' "$CLAUDE_AUDIT_LINE")" \
       || insert_after CLAUDE.md "**For bug fixes**" "$(printf '\n%s' "$CLAUDE_AUDIT_LINE")"; then
      echo "  patched CLAUDE.md"
    else
      echo "  WARN: no anchor bullet found in CLAUDE.md — patch skipped" >&2
    fi
  fi
else
  echo "  no CLAUDE.md — skipping"
fi

AGENT="espalier/agent.md"
if [ -f "$AGENT" ]; then
  if grep -qF "/espalier-audit" "$AGENT"; then
    echo "  $AGENT already mentions /espalier-audit — skipping"
  elif [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] insert the Audit row into $AGENT config-index table"
  else
    # After the Ask row (v0.7+); fall back to the Fix row.
    if insert_after "$AGENT" "Via /espalier-ask |" "$AUDIT_ROW" \
       || insert_after "$AGENT" "Via /espalier-fix |" "$AUDIT_ROW"; then
      echo "  patched $AGENT"
    else
      echo "  WARN: no anchor row found in $AGENT — patch skipped (table customised?)" >&2
    fi
  fi
else
  echo "  no $AGENT — skipping"
fi

# --- Step 7: verification ----------------------------------------------------

log "Step 7: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0; warn=0
  check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
  warn_check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else warn=$((warn+1)); echo "  ! $1 (warn-only)"; fi; }
  check "pipeline.md has the Stage 4 review panel"    "grep -qF 'review panel' espalier/pipeline.md"
  check "main skill spawns harness-security"          "grep -qF 'harness-security' espalier/skills/espalier/SKILL.md"
  check "security rule present"                        "test -f $SECRULE"
  check "security rule symlinked"                      "[ -e .claude/rules/espalier-security.md ]"
  check "harness-security agent present"               "test -f $SECAGENT"
  check "harness-security agent symlinked"             "[ -e .claude/agents/harness-security.md ]"
  check "espalier-security skill present"              "test -f $SECSKILL"
  check "espalier-security skill symlinked"            "[ -e .claude/skills/espalier-security/SKILL.md ]"
  check "espalier-audit skill present"                 "test -f $AUDITSKILL"
  check "espalier-audit skill symlinked"               "[ -e .claude/skills/espalier-audit/SKILL.md ]"
  check "harness-security has Repo-Audit Mode"         "grep -qF '## Repo-Audit Mode' $SECAGENT"
  check "coder has Security-Aware Coding"              "grep -qF '## Security-Aware Coding' $CODER"
  check "reviewer has abuse-test coverage"             "grep -qF '## Security Abuse-Test Coverage' $REVIEWER"
  check "testing skill has abuse-test convention"      "grep -qF '## Security Abuse Tests' $TESTING"
  check "push gate has the security scan"              "grep -qF 'Security scan: secrets BLOCK' $GATE"
  # production-hardening
  check "production rule present"                       "test -f $PRODRULE"
  check "production rule symlinked"                     "[ -e .claude/rules/espalier-production.md ]"
  check "scout-prompts shipped"                         "test -f espalier/.scout-prompts.md"
  check "coder has Production-Aware Coding"             "grep -qF '## Production-Aware Coding' $CODER"
  check "reviewer has Production-Readiness Review"      "grep -qF '## Production-Readiness Review' $REVIEWER"
  check "testing skill has failure-mode tests"         "grep -qF '## Failure-Mode Tests' $TESTING"
  check "push gate has cwd fail-closed guard"          "grep -qF 'cd defensively too' $GATE"
  check "pipeline Stage 9 is deploy-aware"             "grep -qF 'no-deploy-config' espalier/pipeline.md"
  warn_check "CLAUDE.md mentions /espalier-audit"      "grep -qF '/espalier-audit' CLAUDE.md"
  warn_check "agent.md mentions /espalier-audit"       "grep -qF '/espalier-audit' espalier/agent.md"
  echo ""
  echo "  Verification: $pass passed, $fail failed, $warn warn-only"
  [ "$fail" -eq 0 ] || exit 1
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.9.0 adds a security audit: Stage 4 now runs a two-agent"
echo "panel (harness-reviewer + harness-security) in the same fixpoint loop. The"
echo "auditor hard-blocks any sensitive field the backend trusts from the frontend,"
echo "and emits an abuse-test contract Stage 5 writes and Stage 6 enforces."
echo ""
echo "It also ships /espalier-audit — a repo-wide audit of your EXISTING code (the"
echo "Stage 4 audit only sees new changes). It writes a findings inventory to"
echo "espalier/wiki/security-audit.md and hands fixes to /espalier-fix."
echo ""
echo "Plus a production-readiness bar: an always-loaded production-standards rule"
echo "(resilience / observability / data-safety) the coder writes to and the"
echo "reviewer enforces at tiered severity; per-round VERDICT sentinels; a"
echo "fail-closed push gate; and a deploy-aware Stage 9. Fill the {discovered}"
echo "cells of $PRODRULE from your codebase (or run /espalier-doctor)."
echo ""
echo "NOTE: fill the {discovered} sections of $SECRULE (trust boundary +"
echo "project-specific sensitive fields) from your codebase — run /espalier-doctor"
echo "or edit it by hand. The universal taxonomy/controls are already live."
echo ""

if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo ""
  echo "Diff each backup against the live file to re-apply any customisation:"
  echo "  diff espalier/<file>.pre-v0.9.0.bak espalier/<file>"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.9.0 (security audit)'"
echo "  3. Try it: run /espalier on a change that touches an endpoint — Stage 4 now"
echo "     audits the trust boundary and requires abuse tests for sensitive fields."
echo "  4. Baseline the code that predates the audit: /espalier-audit"
