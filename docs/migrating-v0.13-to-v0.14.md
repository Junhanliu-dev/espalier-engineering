# Migrating from v0.13.2 to v0.14.0 (Codex Platform Support)

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
bash <plugin>/scripts/migrate-v0.13.2-to-v0.14.0.sh --dry-run                # preview
bash <plugin>/scripts/migrate-v0.13.2-to-v0.14.0.sh --yes                    # wrappers only
bash <plugin>/scripts/migrate-v0.13.2-to-v0.14.0.sh --with-codex --yes       # + wire Codex
```

## What v0.14.0 changes — and why

Espalier's guardrails were always platform-neutral markdown + shell, but the
*wiring* was Claude-Code-only: `.claude/` symlinks, `CLAUDE.md`,
`settings.json` hooks. Teams with Codex users had the rules and no way to load
them. v0.14.0 makes Codex a first-class wiring target — same `espalier/`
source of truth, Codex-native surfaces:

| Espalier artifact | Claude Code wiring | Codex wiring (new) |
|---|---|---|
| 12 skills | `.claude/skills/*` symlinks, `/espalier…` | `.agents/skills/*` symlinks, `$espalier…` |
| 5 always-loaded rules | `.claude/rules/*` symlinks (harness-injected) | `AGENTS.md` `## Espalier` section with an explicit always-read instruction |
| 3 sub-agents | `.claude/agents/*.md` | `.codex/agents/harness-*.toml` (`developer_instructions` → the same `.md` files) |
| 2 quality gates | `.claude/settings.json` hooks | `.codex/config.toml` `[[hooks.*]]` block (same JSON schema, same exit-2 contract, same wrapper scripts) |

Full design + trust model: [`codex-integration.md`](./codex-integration.md).

## What the migration step does

**Always (the actual v0.13.2→v0.14.0 delta on an existing install):** refreshes
the two plugin-owned hook wrappers to their platform-neutral v0.14.0 versions —

- `espalier/hooks/post-edit-wrapper.sh` — also parses Codex `apply_patch`
  payloads (`*** Add|Update File:` lines, argv arrays) and resolves the repo
  root via `git rev-parse` when `$CLAUDE_PROJECT_DIR` is unset. Checks every
  file in a multi-file patch; exit 2 if any violates.
- `espalier/hooks/pre-push-gate-wrapper.sh` — joins argv-array commands before
  the git-push pattern match (a Python-list rendering would have been stripped
  by the quote remover and failed OPEN).

Both changes are inert under Claude Code — same fields, same exit codes.
Backups land at `<file>.pre-v0.14.bak`.

**Only with `--with-codex`** (the `/espalier-migrate` skill asks; declining
changes nothing else): wires Codex additively via
`bootstrap --wire-only --platforms=codex` — `.agents/skills/` symlinks,
`AGENTS.md` section, `.codex/config.toml` hook block, `.codex/agents/*.toml`,
`espalier/.platforms` (unioned to `claude,codex`). Validation grows to 51
checks; claude wiring is never touched. Wire it later at any time with the
same flag, or directly:

```bash
bash <plugin>/scripts/bootstrap-espalier.sh --wire-only --platforms=codex \
  --plugin-dir=<plugin>/skills/espalier-init --yes
```

## After wiring Codex

Three one-time steps inside Codex: restart it in the repo, trust the project
when prompted, and run `/hooks` to trust the two gate commands. Then
`$espalier <requirement>` runs the same 10-stage pipeline.

## Idempotency + rollback

The script is a no-op when the wrappers already carry the v0.14.0 markers
(and, with `--with-codex`, when `espalier/.platforms` already lists codex).
Rollback = restore the two `.pre-v0.14.bak` files; codex wiring is removable
by deleting the marker block in `.codex/config.toml`, the `.agents/skills/`
symlinks, `.codex/agents/harness-*.toml`, and the `## Espalier` section in
`AGENTS.md` (and setting `espalier/.platforms` back to `claude`).
