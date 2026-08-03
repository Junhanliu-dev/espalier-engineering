# Phase 10: Wiring (Connect Espalier to the Agent Runtime)

> **v0.5.0 note:** `scripts/bootstrap-espalier.sh` is the source of truth for wiring — it bundles all of Phase 10 (Stages 5-11) and is kept current. The manual steps below are a **v0.4-era illustration** of *what* wiring does; they do NOT include the v0.5 doc-drift components — the `drift-detect.sh` / `drift-helpers.sh` / `parse-drift-blocks.py` hooks, the `espalier-prune` + `espalier-doctor` skills, the post-merge dispatcher, the drift sidecars in `.gitignore`, and `espalier/.doctor-cadence`. For real manual recovery after a failed wiring, re-run `bash scripts/bootstrap-espalier.sh --wire-only` (or `--force`) — do not hand-replay the steps below.
>
> **v0.14.0 note (Codex platform):** with `--platforms=codex` (or `claude,codex`) bootstrap additionally wires the Codex runtime — none of it is illustrated in the Claude-era steps below:
> - `.agents/skills/<name>` → `../../espalier/skills/<name>` symlinks (Codex repo-skill discovery probes `.agents/skills/`; same folder-name == `name:` frontmatter invariant, invoked as `$espalier`, `$espalier-fix`, …).
> - `AGENTS.md` `## Espalier` section (grep-guarded append) — carries the always-read-rules instruction (Codex has no auto-loaded rules dir) plus the Codex platform-mapping table (AskUserQuestion → chat, sub-agent spawn → `.codex/agents/`, `/cmd` → `$skill`).
> - `.codex/config.toml` marker-guarded hook block (`# >>> ESPALIER HOOKS v1 >>>` … `# <<<`): PostToolUse matcher `^(apply_patch|Edit|Write)$` → `post-edit-wrapper.sh`; PreToolUse matcher `^(Bash|shell|local_shell)$` → `pre-push-gate-wrapper.sh`. Same stdin JSON schema and exit-2-blocks contract as Claude Code, so the SAME wrapper scripts serve both platforms. Project hooks require the project to be trusted AND `/hooks` trust once inside Codex.
> - `.codex/agents/harness-{coder,reviewer,security}.toml` sub-agents (write-if-absent — user model/effort tuning survives re-runs), each pointing `developer_instructions` at the matching `espalier/agents/*.md`.
> - `espalier/.platforms` records the wired platform set; re-runs are additive (a later `--wire-only --platforms=codex` on a claude install unions to `claude,codex` and never unwires anything).
>
> **v0.15.0 note (Copilot platform):** with `copilot` in `--platforms` bootstrap additionally wires GitHub Copilot:
> - `.github/skills/<name>` → `../../espalier/skills/<name>` symlinks (Copilot Agent Skills — the one location ALL Copilot surfaces read: VS Code, CLI, cloud coding agent; VS Code alone also reads `.claude/skills/` and `.agents/skills/`). Invoked `/espalier`, `/espalier-fix`, … Same folder-name == `name:` invariant.
> - `.github/copilot-instructions.md` `## Espalier` section (grep-guarded append) — always-read-rules instruction + the Copilot platform-mapping table (`@harness-*` custom agents, hook surface caveats).
> - `.github/agents/harness-{coder,reviewer,security}.agent.md` custom agents (write-if-absent; body points at the matching `espalier/agents/*.md`; invoked `@harness-coder` etc.).
> - `.github/hooks/espalier-gates.json` (write-if-absent, own file — user hook files untouched): `preToolUse` matcher `bash|shell` and `postToolUse` matcher `edit|write|create|apply_patch|str_replace_editor`, each dispatching through `espalier/hooks/copilot-hook-adapter.sh`, which translates Copilot's camelCase payload (`toolName`/`toolArgs`) into the Claude/Codex shape (`tool_name`/`tool_input`) and passes exit codes through — Copilot treats a non-zero `preToolUse` exit as DENY (fail-closed), so the shared wrappers' exit-2 contract carries over. Hooks run in Copilot CLI + cloud agent; VS Code chat does not execute hooks.
> - Validation checks 52-56; totals become 56 (47-51 render as skip lines when codex isn't also targeted, keeping numbering contiguous).

Generated files are inert until wired into the execution environment. Run these steps in order.

## 10.1 Wire Rules → Auto-loaded Context

```bash
# Create .claude/rules/ if it doesn't exist
mkdir -p .claude/rules

# Symlink Espalier rules (auto-loaded every session)
ln -sfn "$(pwd)/espalier/rules/engineering-structure.md" .claude/rules/espalier-structure.md
ln -sfn "$(pwd)/espalier/rules/coding-standards.md" .claude/rules/espalier-standards.md
ln -sfn "$(pwd)/espalier/rules/development-process.md" .claude/rules/espalier-process.md
```

## 10.2 Wire Skills → Discoverable Slash Commands

```bash
mkdir -p .claude/skills

# Symlink Espalier skills
ln -sfn "$(pwd)/espalier/skills/espalier-coding" .claude/skills/espalier-coding
ln -sfn "$(pwd)/espalier/skills/espalier-review" .claude/skills/espalier-review
ln -sfn "$(pwd)/espalier/skills/espalier-testing" .claude/skills/espalier-testing
ln -sfn "$(pwd)/espalier/skills/espalier-requirements" .claude/skills/espalier-requirements
ln -sfn "$(pwd)/espalier/skills/espalier" .claude/skills/espalier
ln -sfn "$(pwd)/espalier/skills/espalier-fix" .claude/skills/espalier-fix
```

## 10.3 Wire Sub-Agents → Agent Definitions

```bash
mkdir -p .claude/agents

# Symlink Espalier agent definitions
# (Identifier names kept as harness-coder/harness-reviewer for stability across v0.4 rename.)
ln -sfn "$(pwd)/espalier/agents/harness-coder.md" .claude/agents/harness-coder.md
ln -sfn "$(pwd)/espalier/agents/harness-reviewer.md" .claude/agents/harness-reviewer.md
```

These agents are now available for the Agent tool to reference.

## 10.4 Wire Agent Definition → CLAUDE.md

Append to the project's CLAUDE.md:

```markdown
## Espalier

This project uses Espalier for AI code quality — auto-discovered, project-specific guardrails.

**Always-loaded rules** are symlinked in .claude/rules/espalier-*.md

**For any implementation work**, use `/espalier <requirement>` to execute the full pipeline.

**For bug fixes**, use `/espalier-fix <bug>` for the slim lane — 7 stages (0–7, no Stage 2).

**Agent definition:** Read `espalier/agent.md` for your operating instructions.

**Key principle:** The coder agent and reviewer agent are ALWAYS separate.
Never review your own code in the same invocation that wrote it.
```

## 10.5 Wire Quality Gates → Hooks

Add to `.claude/settings.json` (project-level, create if needed):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/espalier/hooks/post-edit-wrapper.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/espalier/hooks/pre-push-gate-wrapper.sh\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Note on `$HOOK_FILE_PATH`:** The PostToolUse hook receives `tool_input.file_path` in its JSON input. The hook script must parse this from stdin. Espalier generates a wrapper that extracts it:

```bash
# espalier/hooks/post-edit-wrapper.sh
#!/bin/bash
# Reads hook input JSON from stdin, extracts file_path, runs boundary check
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
  exec bash "$CLAUDE_PROJECT_DIR/espalier/hooks/check-layer-boundaries.sh" "$FILE_PATH"
fi
exit 0
```

**IMPORTANT:** All hook commands in `.claude/settings.json` MUST use `$CLAUDE_PROJECT_DIR` to build absolute paths. Hook subprocesses do NOT inherit the project root as cwd — relative paths like `bash espalier/hooks/foo.sh` will fail with `No such file or directory` at fire time. Same rule applies inside wrapper scripts when they `exec` other scripts.

## 10.6 Wire Change Tracking

```bash
# Ensure template + typed parent dirs exist
# (per-slug subdirs are created lazily by the skill at invocation time)
mkdir -p espalier/changes/_template
mkdir -p espalier/changes/feat
mkdir -p espalier/changes/fix
mkdir -p espalier/changes/refactor

# The pipeline-state.md template for session resumption (used by both /espalier and /espalier-fix)
cat > espalier/changes/_template/pipeline-state.md << 'EOF'
# Pipeline State: {requirement}

## Status
- Current Stage: 0
- Started: {timestamp}
- Last Updated: {timestamp}
- Total Rollbacks: 0
- Review Rounds: req=0/{max-req-rounds}, code=0/{max-code-rounds}, test=0/{max-test-rounds}

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
EOF
```

State files live at `espalier/changes/{type}/{slug}/pipeline-state.md` (depth 3 from `espalier/changes/`). All scans (session resumption, pre-push gate) use `find -mindepth 3 -maxdepth 3 -name pipeline-state.md`.

The `{max-req-rounds}` / `{max-code-rounds}` / `{max-test-rounds}` denominators are the review-round escalation caps, read from `espalier/.espalier-config` (a tracked key-value file written once by bootstrap, default `3` each). The orchestrator substitutes them when it instantiates a change's state file, and reads them at the Stage 2/4/6 gates via `grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'` (falling back to 3 if absent). The same file also holds `max-rollbacks` (default 3) — the total cross-stage rollbacks allowed before human takeover, read the same way at the rollback gate. `#` comment lines and blanks in the file are ignored. Edit any value to tune; it survives re-bootstrap.

## 10.7 Make Hooks Executable

```bash
chmod +x espalier/hooks/check-layer-boundaries.sh
chmod +x espalier/hooks/pre-push-gate.sh
chmod +x espalier/hooks/post-edit-wrapper.sh
chmod +x espalier/hooks/pre-push-gate-wrapper.sh
chmod +x espalier/hooks/post-merge-backlink.sh
chmod +x espalier/hooks/rebuild-commit-index.sh
# lookup-helpers.sh is sourced, not executed — no chmod needed
```

## 10.8 Wire Squash-Merge Resilience (and reverse-lookup cache)

Front-loaded decision so `/espalier-fix` Stage 0 never interrupts users mid-bug.

### Step 1: Detect environment hints

```bash
HUSKY_PRESENT=no
# Detect husky v8 (.husky/_/husky.sh or install.mjs) AND v9 (just .husky/ dir managed by `husky` CLI)
if [ -d ".husky" ]; then
  if [ -f ".husky/_/husky.sh" ] || [ -f ".husky/install.mjs" ]; then
    HUSKY_PRESENT=yes   # v8 or earlier
  elif grep -q '"husky"' package.json 2>/dev/null; then
    HUSKY_PRESENT=yes   # v9+ — managed via package.json `husky` script + .husky/ dir
  fi
fi
```

### Step 2: Prompt user about merge strategy

Use `AskUserQuestion`. Outer choice:

```
How does this repo merge PRs?

  1. Rebase-merge or true merge-commit
       → DECISION = not-needed
  2. Squash-merge (GitHub default)
       → Follow-up question follows
  3. Mixed / unknown / decide later
       → DECISION = ask-later
```

If user picks 2 (squash), follow up:

```
For squash-merge, how should Espalier handle SHA drift?

  1. Install post-merge git hook (recommended) → DECISION = installed
  2. Allow fuzzy file-overlap match at fix-time → DECISION = fuzzy-allowed
  3. Skip linking when SHA misses (safest)     → DECISION = skip-only
  4. Never ask, always skip                    → DECISION = never-ask
```

### Step 3: Persist decision

```bash
echo "$DECISION" > espalier/.merge-hook-decision
git add espalier/.merge-hook-decision
# Intentionally NOT in .gitignore — teammates inherit the repo's decision.
```

### Step 4: Copy hook + helper templates to espalier/hooks/

Regardless of decision (so users can switch later without re-installing the plugin):

```bash
cp skills/espalier-init/hook-templates/post-merge-backlink.sh espalier/hooks/post-merge-backlink.sh
cp skills/espalier-init/hook-templates/lookup-helpers.sh      espalier/hooks/lookup-helpers.sh
cp skills/espalier-init/hook-templates/rebuild-commit-index.sh espalier/hooks/rebuild-commit-index.sh
chmod +x espalier/hooks/post-merge-backlink.sh
chmod +x espalier/hooks/rebuild-commit-index.sh
# lookup-helpers.sh is sourced, not executed
```

### Step 5: Install hook (only if DECISION = installed)

```bash
if [ "$DECISION" = "installed" ]; then
  if [ "$HUSKY_PRESENT" = "yes" ]; then
    HOOK_DST=".husky/post-merge"
  else
    HOOK_DST=".git/hooks/post-merge"
  fi

  HOOK_SRC="espalier/hooks/post-merge-backlink.sh"

  if [ -f "$HOOK_DST" ] && ! grep -qE "(ESPALIER|HARNESS)_BACKLINK_HOOK" "$HOOK_DST"; then
    # Pre-existing hook from another tool — append the Espalier section
    echo "" >> "$HOOK_DST"
    cat "$HOOK_SRC" >> "$HOOK_DST"
  elif [ ! -f "$HOOK_DST" ]; then
    cp "$HOOK_SRC" "$HOOK_DST"
  fi
  chmod +x "$HOOK_DST"
fi
```

### Step 6: Add reverse-lookup cache to .gitignore

```bash
# Cache is regenerable; teammates rebuild on first slow scan.
# Guard against missing trailing newline in existing .gitignore.
if ! grep -qxF "espalier/.commit-index.tsv" .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  echo "espalier/.commit-index.tsv" >> .gitignore
fi
```
