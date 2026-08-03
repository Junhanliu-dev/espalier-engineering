# Migrating from v0.14.0 to v0.15.0 (Copilot Platform Support)

## TL;DR

```bash
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

Or run the script directly:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.14.0-to-v0.15.0.sh --dry-run                  # preview
bash <plugin>/scripts/migrate-v0.14.0-to-v0.15.0.sh --yes                      # adapter only
bash <plugin>/scripts/migrate-v0.14.0-to-v0.15.0.sh --with-copilot --yes       # + wire Copilot
```

## What v0.15.0 changes — and why

v0.14.0 made the wiring layer multi-platform (Claude Code + Codex). v0.15.0
adds the third major agent: **GitHub Copilot** — same `espalier/` source of
truth, Copilot-native surfaces:

| Espalier artifact | Copilot wiring (new) |
|---|---|
| 12 skills | `.github/skills/*` symlinks — Agent Skills read by VS Code, Copilot CLI, AND the cloud coding agent; invoked `/espalier…` |
| 5 always-loaded rules | `## Espalier` section in `.github/copilot-instructions.md` with an explicit always-read instruction |
| 3 sub-agents | `.github/agents/harness-*.agent.md` custom agents (`@harness-coder` …) |
| 2 quality gates | `.github/hooks/espalier-gates.json` → `copilot-hook-adapter.sh` → the same shared wrappers (Copilot sends camelCase `toolName`/`toolArgs`; the adapter translates; non-zero `preToolUse` exits deny, so the exit-2 contract carries over). Hooks run in CLI + cloud agent; VS Code chat runs no hooks. |

Full design + per-surface matrix: [`copilot-integration.md`](./copilot-integration.md).

## What the migration step does

**Always (the actual v0.14.0→v0.15.0 delta on an existing install):** installs
one NEW plugin-owned file — `espalier/hooks/copilot-hook-adapter.sh`. Nothing
is modified, so there are no backups; the adapter is inert until Copilot hooks
reference it.

**Only with `--with-copilot`** (the `/espalier-migrate` skill asks; declining
changes nothing else): wires Copilot additively via
`bootstrap --wire-only --platforms=copilot` — `.github/skills/` symlinks,
`copilot-instructions.md` section, `.github/agents/*.agent.md`,
`.github/hooks/espalier-gates.json`, `espalier/.platforms` unioned. Validation
becomes 56 checks. Claude/Codex wiring is never touched. Wire later anytime:

```bash
bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --platforms=copilot \
  --plugin-dir=<plugin>/skills/espalier-init --yes
```

## After wiring Copilot

Reload VS Code (or restart Copilot CLI) so the skills/agents/hooks register.
Then `/espalier <requirement>` in Copilot chat/CLI runs the same 10-stage
pipeline; sub-agents are `@harness-coder` / `@harness-reviewer` /
`@harness-security`.

## Idempotency + rollback

No-op when the adapter exists (and, with `--with-copilot`, when
`espalier/.platforms` already lists copilot). Rollback = delete
`espalier/hooks/copilot-hook-adapter.sh`; copilot wiring is removable by
deleting `.github/hooks/espalier-gates.json`, the `.github/skills/` symlinks,
`.github/agents/harness-*.agent.md`, the `## Espalier` section in
`.github/copilot-instructions.md`, and dropping `copilot` from
`espalier/.platforms`.
