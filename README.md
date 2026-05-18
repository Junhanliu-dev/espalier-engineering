# Harness Engineering

> **v0.2.0 is out.** Adds `/harness-fix` bug-fix lane, typed `harness/changes/{type}/{slug}/` layout, causal back-links, escalation paths, squash-merge resilience, and a self-healing reverse-lookup cache.
> **Existing v0.1.0 users:** see [`docs/migrating-v0.1-to-v0.2.md`](./docs/migrating-v0.1-to-v0.2.md). One script handles the mechanical bits — no full regen needed.

A Claude Code skill that **discovers** an existing codebase's patterns, conventions, and architecture, then **generates** a structured constraint system (rules, skills, agents, hooks, pipeline) so AI coders produce code matching that project's standards.

> When an agent makes an error, engineer its elimination — not with prompt tweaks, but with files, rules, automated checks, and system structure.

## What This Skill Does

Given any existing repo, the skill:

1. **Discovers** language, framework, layers, conventions, test patterns, CI checks, and unwritten rules — by reading actual files.
2. **Generates** a `harness/` directory in the target project containing:
   - `rules/` — engineering structure, coding standards, development process
   - `skills/` — coding, review, testing, requirements, run (pipeline orchestrator)
   - `agents/` — coder and reviewer sub-agent definitions
   - `wiki/` — architecture, data models, critical paths, external services
   - `hooks/` — programmatic quality gates (layer boundary checks, pre-push gate)
   - `pipeline.md` — 10-stage workflow with gates and rollback rules
3. **Wires** everything into Claude Code via `.claude/` symlinks and `settings.json` hook entries.
4. **Validates** the wired harness end-to-end.

The result: a per-project constraint system that AI coders pick up automatically. Reduces rework cycles from 3-5 rounds to typically 1.

## When to Use

- "Set up harness for this project"
- "Create harness structure for my codebase"
- "Make AI code production-ready for this repo"
- "Build agent constraints for this project"

Once set up, the harness exposes two orchestrators:
- **`/harness-run <requirement>`** — full 10-stage pipeline for features, refactors, and large fixes.
- **`/harness-fix <bug>`** (v0.2.0+) — 5-stage bug-fix lane with auto-link to the change that introduced the bug, escalation paths for late-discovered scope inflation, and squash-merge resilience.

## Install

### Option A — Plugin marketplace (recommended)

```text
/plugin marketplace add Junhanliu-dev/harness-engineering
/plugin install harness-engineering@harness-engineering
```

Then in any project, invoke:

```text
/harness-engineering
```

To update later:

```text
/plugin update harness-engineering
```

### Option B — Manual git clone + symlink

For users not on the plugin path, or while iterating:

```bash
git clone https://github.com/Junhanliu-dev/harness-engineering ~/repos/harness-engineering
ln -sf ~/repos/harness-engineering/skills/harness-engineering ~/.claude/skills/harness-engineering
```

Restart Claude Code. The skill is now discoverable.

To update: `cd ~/repos/harness-engineering && git pull`.

### Option C — Project-scoped install

Drop the skill inside a single project rather than installing globally:

```bash
mkdir -p .claude/skills
ln -sf /path/to/harness-engineering/skills/harness-engineering .claude/skills/harness-engineering
```

## Repo Layout

```
harness-engineering/
├── .claude-plugin/
│   ├── plugin.json              # Plugin metadata
│   └── marketplace.json         # Marketplace manifest (for /plugin install)
├── skills/
│   └── harness-engineering/
│       ├── SKILL.md             # Lean entry — phases + pointers
│       ├── templates/           # Markdown templates emitted into target project
│       │   ├── rules/
│       │   ├── skills/
│       │   ├── agents/
│       │   ├── agent.md
│       │   └── pipeline.md
│       ├── hook-templates/      # Shell-script templates emitted into target harness/hooks/
│       └── references/          # Deep-dive content read on demand by the skill
├── README.md
└── LICENSE
```

## How It Works Inside Claude Code

When `/harness-engineering` fires:

- Claude reads `SKILL.md` (lean — ~290 lines)
- For each phase, the skill instructs Claude to `Read` a specific template or reference file
- Templates carry placeholders (e.g. `{detected_language}`); Claude substitutes from Phase 1 discovery
- Outputs are written into the target project's `harness/` directory
- Phase 10 wires them into `.claude/` via symlinks + `settings.json` hooks

The skill itself never modifies its own source — it only generates content into the project it's invoked from.

## Philosophy

> The problem isn't model intelligence. It's that models don't know the unwritten rules — patterns every experienced developer on the team knows but nobody documented.

This skill discovers those rules from the code itself and encodes them as machine-enforceable constraints.

Five guiding principles:

1. **Discover, don't prescribe** — read the actual code, extract patterns; never impose templates from other projects.
2. **Quality gates must be programmatic** — `ci_status == 'success' AND tests_passed == total_tests`, not "check if CI passes".
3. **Separate execution from judgment** — coder agent and reviewer agent are always different invocations with different tool sets.
4. **Context layering** — rules always loaded; skills loaded per phase; agents see only their scope; wiki on demand.
5. **Every rule has a reason** — either reflects an observed pattern, or prevents a known failure mode.

## License

MIT — see [LICENSE](./LICENSE).

## Status

`v0.2.0` — bug-fix lane (`/harness-fix`), typed `harness/changes/{type}/{slug}/` layout, causal back-links between fixes and the changes that introduced them, escalation paths (including late-stage), squash-merge resilience with optional post-merge hook, and self-healing reverse-lookup cache.

See [CHANGELOG.md](./CHANGELOG.md) for the full release notes and [docs/plan.md](./docs/plan.md) for the implementation rationale per phase.

Schema and templates may still change. Please file issues with the harness output you'd expect to see for your stack.

### Optional dependency

The `/harness-fix` slug derivation transliterates Unicode bug descriptions via the Python `unidecode` library. If unavailable, falls back to ASCII-strip (loses CJK/RTL meaning but never crashes). Install with `pip install unidecode` or `uv pip install unidecode`.
