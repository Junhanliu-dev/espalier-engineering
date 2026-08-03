# Codex Integration (v0.14.0)

Espalier's discovered guardrails are platform-neutral markdown + shell. Since
v0.14.0, `espalier-init` wires them into **OpenAI Codex** as a first-class
target alongside (or instead of) Claude Code. This doc covers what lands
where, why, the trust steps Codex requires, and the known degradations.

## Requirements

A Codex CLI / IDE build recent enough to have all three of:

| Feature | Espalier uses it for | Codex surface |
|---|---|---|
| Repo skills (`.agents/skills/`, `SKILL.md`) | the 12 espalier skills, incl. the `$espalier` / `$espalier-fix` orchestrators | skills discovery walks `.agents/skills/` from cwd up to the repo root |
| Lifecycle hooks (`PreToolUse` / `PostToolUse`) | the push gate + layer-boundary check | `[[hooks.*]]` tables in `.codex/config.toml` (project layer) |
| Subagents (`.codex/agents/*.toml`) | coder / reviewer / security separation | spawned by name from the pipeline skills |

Older Codex builds degrade in order: without subagents the pipeline runs the
roles inline in strict sequence (the AGENTS.md mapping section instructs how);
without hooks the gates don't fire (the pipeline's in-skill gate checks still
run — you lose only the programmatic backstop); without skills there is no
`$espalier` entry point and Codex support is effectively unavailable.

## What gets wired where

`bash scripts/bootstrap-espalier.sh --platforms=codex` (or `claude,codex`;
espalier-init passes this from its platform question) adds, on top of the
platform-neutral `espalier/` tree:

| Artifact | Path | Mechanism |
|---|---|---|
| 12 skills | `.agents/skills/<name>` → `../../espalier/skills/<name>` symlinks | Codex repo-skill discovery; folder name == `name:` frontmatter (same invariant as Claude Code, so the same source dirs serve both) |
| Always-loaded rules | `## Espalier` section appended to `AGENTS.md` (grep-guarded, one per repo) | Codex has **no auto-loaded rules dir** (`.codex/rules/` holds command-approval `prefix_rule()` policies, not instructions) — the AGENTS.md section carries an explicit "read every file in `espalier/rules/` before writing or reviewing code" instruction, plus the platform-mapping table below |
| Sub-agents | `.codex/agents/harness-{coder,reviewer,security}.toml` | each sets `name`, `description`, `sandbox_mode = "workspace-write"`, and `developer_instructions` pointing at the matching `espalier/agents/*.md`. Write-if-absent: your later `model` / `model_reasoning_effort` tuning survives re-runs. Reviewer/security keep their only-my-record-file write contract in the instructions (Codex has no per-tool allowlist for subagents) |
| Quality gates | marker-guarded block in `.codex/config.toml` (`# >>> ESPALIER HOOKS v1 >>>` … `<<<`) | `PostToolUse` matcher `^(apply_patch\|Edit\|Write)$` → `espalier/hooks/post-edit-wrapper.sh`; `PreToolUse` matcher `^(Bash\|shell\|local_shell)$` → `espalier/hooks/pre-push-gate-wrapper.sh`. Backup of any pre-existing config.toml is taken first; appending `[[hooks.*]]` tables at EOF is always valid top-level TOML |
| Platform record | `espalier/.platforms` | tracked; re-runs union (`--wire-only --platforms=codex` on a claude install → `claude,codex`, never unwires) |

Git-level pieces (post-merge drift dispatcher, commit-index cache, `.gitignore`
entries) are platform-independent and identical on both targets.

### One wrapper set, two platforms

Codex adopted Claude Code's hook contract: same stdin JSON (`tool_name`,
`tool_input`, …), same **exit 2 + stderr = block/feedback** semantics. The two
wrappers are shared, with v0.14.0 hardening for the Codex payload shapes:

- `post-edit-wrapper.sh` — uses `tool_input.file_path` when present (Claude
  Write/Edit); otherwise extracts every `*** Add File:` / `*** Update File:`
  path from the `apply_patch` patch body (`tool_input.command` or `.input`),
  checks each, and exits 2 if any violates. Repo root comes from
  `$CLAUDE_PROJECT_DIR` when set, else `git rev-parse --show-toplevel`.
- `pre-push-gate-wrapper.sh` — joins argv-array commands
  (`["bash","-lc","git push"]`) into a plain string before the git-push
  pattern match, so the quote-stripping heuristic can't be blinded by list
  quoting (which would have failed OPEN).

## Trust model (why the gates need two yeses)

Codex refuses project-supplied config by default:

1. **Project trust** — `.codex/` layers (config, hooks, project rules) load
   only for a trusted project. Codex prompts on first open; accept it.
2. **Hook trust** — non-managed hooks additionally require a one-time
   `/hooks` approval inside Codex before they execute.

Until both are given, the pipeline still works but the two programmatic gates
are silent. `espalier-init`'s completion message repeats these steps whenever
codex was wired.

## Install paths

### Fresh init from Codex

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.agents/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.agents/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.agents/skills/espalier-migrate
# restart Codex, then in the target repo:
#   $espalier-init
```

The init skill carries a Codex fallback table (SKILL.md → "Running under
Codex"): setup questions arrive in chat instead of `AskUserQuestion`,
discovery scouts run as Codex subagents or inline, and the bootstrap command
substitutes the skill's own resolved directory for `${CLAUDE_SKILL_DIR}`.

### Fresh init from Claude Code, Codex included

Run `/espalier-init` as usual and answer **Both** at the platform question
(Q4). Everything else is unchanged.

### Add Codex to an existing install

Either `/espalier-migrate` (asks about Codex in its v0.14.0 step), or directly:

```bash
bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --platforms=codex \
  --plugin-dir=<plugin>/skills/espalier-init --yes
```

`--merge-decision` is reused from `espalier/.merge-hook-decision`; the
platform set unions; validation runs the full 51 checks (46 base + 5 codex).

## Using the pipelines in Codex

| Claude Code | Codex |
|---|---|
| `/espalier <requirement>` | `$espalier <requirement>` |
| `/espalier-fix <bug>` | `$espalier-fix <bug>` |
| `/espalier-ask <question>` | `$espalier-ask <question>` |
| `/espalier-audit`, `/espalier-prune`, `/espalier-doctor` | `$espalier-audit`, `$espalier-prune`, `$espalier-doctor` |

The generated `AGENTS.md` section carries the full mapping the skills rely on:
`AskUserQuestion` → ask in chat and wait (and "can I ask in chat" is the
interactivity test the approval gates key on); "spawn harness-coder with
prompt X" → spawn the `.codex/agents/harness-coder.toml` subagent with the
same prompt, or — if spawning is unavailable — run the roles inline in strict
sequence, never letting the pass that wrote code approve it;
`$CLAUDE_PROJECT_DIR` → the repo root.

## Known degradations vs Claude Code

- **Rules are instruction-loaded, not harness-loaded.** Claude Code injects
  `.claude/rules/*` unconditionally; Codex loads the rules because AGENTS.md
  says to. Same trust level as any other AGENTS.md instruction — in practice
  Codex follows it, but it is an instruction, not a mechanism.
- **Reviewer write restriction is contractual.** Claude Code narrows the
  reviewer's toolset via `tools:` frontmatter; Codex subagents get
  `sandbox_mode` only, so "write nothing but your record file" lives in
  `developer_instructions` (as it already does in the agent .md body).
- **`AGENTS.override.md` wins.** If someone adds a local
  `AGENTS.override.md`, Codex prefers it over `AGENTS.md` — the Espalier
  section (and its rules instruction) silently drops out. Copy the section
  into the override file if you use one.
- **Skill loading needs a restart.** Codex scans skills/config at startup;
  after init or migrate, restart the session.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `$espalier` not recognized | Codex started before wiring, or repo skills not discovered → restart Codex in the repo root; `ls .agents/skills/` should show 12 entries |
| Gates never fire | project untrusted, or hooks untrusted → trust the project, run `/hooks`, retry; verify the block exists: `grep 'ESPALIER HOOKS' .codex/config.toml` |
| Push slipped through the gate | hook trust missing (above), or `ESPALIER_SKIP_GATE=1` exported |
| Rules ignored | `AGENTS.override.md` shadowing, or the `## Espalier` section missing → `grep '## Espalier' AGENTS.md`; re-run bootstrap Stage 7b via `--wire-only` |
| Wrong/duplicate skills in the picker | a same-named user-scope skill also installed (`~/.agents/skills/espalier-*`) — Codex lists both; remove the user-scope copy in project contexts |
