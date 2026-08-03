# GitHub Copilot Integration (v0.15.0)

Espalier's discovered guardrails wire into **GitHub Copilot** as a first-class
target alongside Claude Code and Codex. Same `espalier/` source of truth,
Copilot-native surfaces. This doc covers what lands where, per-surface
behavior, and the known degradations.

## What gets wired where

`bash scripts/bootstrap-espalier.sh --platforms=copilot` (any combination with
`claude`/`codex` works; espalier-init passes this from its platform question)
adds, on top of the platform-neutral `espalier/` tree:

| Artifact | Path | Mechanism |
|---|---|---|
| 12 skills | `.github/skills/<name>` → `../../espalier/skills/<name>` symlinks | Copilot **Agent Skills** — the one repo location ALL Copilot surfaces read (VS Code, Copilot CLI, cloud coding agent). Invoked `/espalier`, `/espalier-fix`, … or auto-loaded by description. Folder name == `name:` frontmatter, same invariant as Claude Code/Codex — so the same source dirs serve every platform. VS Code additionally reads `.claude/skills/` and `.agents/skills/`, so claude/codex wiring already covers VS Code by itself. |
| Always-loaded rules | `## Espalier` section appended to `.github/copilot-instructions.md` (grep-guarded) | Copilot's repository custom instructions load into every chat/agent session; the section carries the explicit "read every file in `espalier/rules/` first" instruction plus the Copilot platform-mapping table. If AGENTS.md (codex wiring) is also present, Copilot reads both — the section says to follow the contract once. |
| Sub-agents | `.github/agents/harness-{coder,reviewer,security}.agent.md` | Copilot **custom agents** (`@harness-coder` etc. in VS Code/CLI; selectable for cloud-agent runs). Frontmatter `name` + `description`; body points at the matching `espalier/agents/*.md`. Write-if-absent — your later `model`/`tools` tuning survives re-runs. Reviewer/security keep their only-my-record-file write contract in the body. |
| Quality gates | `.github/hooks/espalier-gates.json` (own file — user hook files never touched; write-if-absent) | Copilot **hooks**: `preToolUse` matcher `bash\|shell` → push gate; `postToolUse` matcher `edit\|write\|create\|apply_patch\|str_replace_editor` → layer-boundary check. Each dispatches through `espalier/hooks/copilot-hook-adapter.sh`. |
| Platform record | `espalier/.platforms` | tracked; unions on re-run — adding copilot never unwires claude/codex. |

### The adapter: one wrapper set, three platforms

Copilot hooks send a **camelCase** payload — `{"toolName": "bash",
"toolArgs": {...}}` — where Claude Code and Codex send `tool_name` /
`tool_input`. Rather than teach the two shared wrappers a third schema,
`copilot-hook-adapter.sh` translates (including `path`/`filePath` →
`file_path`) and pipes to the wrapper named in its argument. Exit codes pass
through: Copilot treats a non-zero `preToolUse` exit as **DENY (fail-closed)**
— so the wrappers' exit-2-blocks contract carries over unchanged. Without
python the adapter passes the raw payload through: the push-gate wrapper's
grep fast-path and fail-closed python probe still behave correctly.

### Where the gates actually run

| Surface | Skills | Custom agents | Hooks |
|---|---|---|---|
| Copilot CLI | ✓ | ✓ (`/agent`) | ✓ (auto-loaded from repo) |
| Copilot cloud coding agent | ✓ | ✓ (assign/dropdown) | ✓ (sandbox) |
| VS Code Copilot chat | ✓ | ✓ (`@name`) | ✗ — VS Code does not execute repo hooks; the pipeline's in-skill gate checks still apply |

## Install paths

### Fresh init, Copilot included

Run `/espalier-init` (Claude Code) or `/espalier-init` via Copilot / `$espalier-init`
via Codex, and include **GitHub Copilot** in the platform question. Everything
else is unchanged.

### Run espalier-init from Copilot itself

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.copilot/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.copilot/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.copilot/skills/espalier-migrate
# reload VS Code / restart Copilot CLI, then in the target repo: /espalier-init
```

The init skill's platform-fallback table (SKILL.md → "Running under Codex or
Copilot") applies: questions arrive in chat, discovery runs inline or via
custom agents, and the bootstrap command substitutes the skill's own resolved
directory for `${CLAUDE_SKILL_DIR}`.

### Add Copilot to an existing install

Either `/espalier-migrate` (asks about Copilot in its v0.15.0 step), or directly:

```bash
bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --platforms=copilot \
  --plugin-dir=<plugin>/skills/espalier-init --yes
```

`--merge-decision` is reused from `espalier/.merge-hook-decision`; the platform
set unions; validation runs 56 checks (46 base + 5 codex slots + 5 copilot —
codex slots render as skips when codex isn't wired).

## Known degradations vs Claude Code

- **Rules are instruction-loaded.** Copilot loads `copilot-instructions.md`
  automatically, but the espalier rules load because that section says to
  read them — an instruction, not a harness mechanism.
- **Reviewer write restriction is contractual.** Custom agents accept a
  `tools:` allowlist, but the generated agents omit it (the reviewer still
  needs edit access for its record file); the restriction lives in the agent
  body, as on Codex.
- **VS Code chat runs no hooks.** The programmatic gates cover CLI + cloud
  agent only. In VS Code, the pipeline's own stage gates (in-skill sentinel
  checks) are the enforcement.
- **Reload required.** Skills/agents/hooks register at session start — reload
  VS Code or restart the CLI after wiring.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `/espalier` not in the skills picker | wiring predates the session → reload VS Code / restart CLI; `ls .github/skills/` should show 12 entries |
| Duplicate skills in the picker | same-named user-scope copies (`~/.copilot/skills/`, `~/.claude/skills/`, `~/.agents/skills/`) alongside the repo ones — remove the user-scope duplicates |
| Gates never fire in CLI | `.github/hooks/espalier-gates.json` missing or invalid JSON → re-run bootstrap Stage 8e; `python3 -c 'import json;json.load(open(".github/hooks/espalier-gates.json"))'` |
| Gates "fire" in VS Code | they don't — VS Code chat executes no hooks; that's the documented gap, not a regression |
| Every bash call denied in CLI | adapter crash = fail-closed deny → run `printf '{"toolName":"bash","toolArgs":{"command":"ls"}}' \| bash espalier/hooks/copilot-hook-adapter.sh pre-push-gate-wrapper.sh; echo $?` — expect 0 |
