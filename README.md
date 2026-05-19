# Harness Engineering

> **v0.3.0 is out.** Init speedup — `/harness-engineering` first run is now ~75-80% faster on a fresh repo via parallel discovery scouts + a bundled bootstrap script. Wall clock: 8-12 min → 1.5-2.5 min on a medium codebase. Zero workflow semantic change vs v0.2.x; every artifact in `harness/` is byte-equivalent (modulo discovery-driven substitutions).
> **v0.2.0 features (still in v0.3.0):** `/harness-fix` bug-fix lane, typed `harness/changes/{type}/{slug}/` layout, causal back-links, escalation paths, squash-merge resilience, self-healing reverse-lookup cache.
> **Existing v0.1.0 users:** see [`docs/migrating-v0.1-to-v0.2.md`](./docs/migrating-v0.1-to-v0.2.md). One script handles the mechanical bits — no full regen needed.
> **Existing v0.2.x users:** no migration. v0.3.0 only changes how `/harness-engineering` runs on FRESH repos; existing installs keep working unchanged.

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

> **Heads-up on first run:** `/harness-engineering` does real work to discover your codebase — 10 parallel scouts read source files, tests, CI configs, schemas, entry points, and external dependencies. Expect ~1.5-2.5 min on a medium repo (~150 source files), longer on big ones. **It's a one-time tax.** Once `harness/` is generated, every future `/harness-run` and `/harness-fix` invocation reuses it — and the per-project rules cut rework rounds enough that you'll earn the time back inside the first few requirements.

## When to Use

- "Set up harness for this project"
- "Create harness structure for my codebase"
- "Make AI code production-ready for this repo"
- "Build agent constraints for this project"

Once set up, the harness exposes two orchestrators:
- **`/harness-run <requirement>`** — full 10-stage pipeline for features, refactors, and large fixes.
- **`/harness-fix <bug>`** (v0.2.0+) — 5-stage bug-fix lane with auto-link to the change that introduced the bug, escalation paths for late-discovered scope inflation, and squash-merge resilience.

### Requirement type prefix (controls where state files land)

`/harness-run` parses an optional prefix on the requirement to pick the typed
output directory under `harness/changes/`:

| Prefix | Type | Output dir | Example |
|---|---|---|---|
| `feat:` (or no prefix) | `feat` | `harness/changes/feat/<slug>/` | `/harness-run feat: add stripe checkout` |
| `refactor:` | `refactor` | `harness/changes/refactor/<slug>/` | `/harness-run refactor: extract auth middleware` |
| `docs:` | `docs` | `harness/changes/docs/<slug>/` (created on first use) | `/harness-run docs: rewrite onboarding guide` |
| `fix:` | use `/harness-fix` instead | `harness/changes/fix/<slug>/` | `/harness-fix bug at api/users.ts:42` |

Prefix only affects directory layout — the 10-stage pipeline runs the same way
for `feat`/`refactor`/`docs`. `fix:` routes to the slimmer 5-stage lane.

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

When `/harness-engineering` fires on a fresh repo (v0.3.0+):

- **Phase 0** — one `AskUserQuestion` captures the squash-merge decision (6 options) up front.
- **Phase 1** — Claude issues a single message with ~10 parallel tool calls: bash batch (tldr / manifests / git log) + 6 codebase scouts + 1 best-practices oracle + 3 wiki scouts (data models, critical paths, external services). Each scout returns a structured JSON blob. Failed scouts are batched into ONE follow-up question — never blocks per-scout.
- **Phase 2** — Claude writes ~14 substitution files (rules, agent.md, harness-coding/testing/review SKILL.md, sub-agents, 4 wiki files, 2 placeholder hooks, N per-layer specs) in ONE parallel Write batch from the in-context DISCOVERY blob.
- **Phase 3** — `scripts/bootstrap-harness.sh` runs as a single bash invocation: mkdir + cp pure-copy templates + cp non-substitution hooks + chmod glob + safe symlinks + CLAUDE.md append + atomic `.claude/settings.json` merge (preserves user hooks) + squash-merge decision + post-merge hook install + .gitignore + 24 parallel validation checks.

Total: ~5-7 batched turns (~110-140 sequential tool calls in v0.2.x).

The skill itself never modifies its own source — it only generates content into the project it's invoked from.

### Re-running on existing installs

- **Fully bootstrapped repo** (decision file present) → bootstrap auto-runs validation only (Stage 11), exit 0. Idempotent health check.
- **v0.1.x repo** (wired symlinks but no decision file) → bootstrap exits 1, suggests `/harness-migrate`.
- **Partial install / corrupted state** → use `--force` to redo all stages.

### Debug flags (not used by the normal flow)

Reserved for diagnosing mid-flow failures:

```bash
bash scripts/bootstrap-harness.sh --copy-only      # Stages 1-4 only (dirs + cp templates + hooks)
bash scripts/bootstrap-harness.sh --wire-only      # Stages 5-11 only (symlinks + wiring + validation)
bash scripts/bootstrap-harness.sh --validate-only  # Stage 11 only (24 parallel checks, no changes)
bash scripts/bootstrap-harness.sh --dry-run        # Print actions without executing
```

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

`v0.3.0` — **init speedup.** `/harness-engineering` first run on a fresh repo is ~75-80% faster (8-12 min → 5-10 min on a medium codebase). Achieved via parallel discovery scouts (10 calls per batch), parallel substitution-file writes, and a bundled `scripts/bootstrap-harness.sh` collapsing Phase 8 (Hooks) + Phase 10 (Wiring) + Phase 11 (Validation) into one idempotent invocation. Zero workflow semantic change; every artifact byte-equivalent to v0.2.x output (modulo discovery-driven substitutions). Also ships fixes for latent v0.2.x bugs: missing `pre-push-gate-wrapper.sh` template, undefined `.claude/settings.json` merge behavior, unsafe `ln -sf` overwrite, `realpath` portability on macOS.

`v0.2.0` — bug-fix lane (`/harness-fix`), typed `harness/changes/{type}/{slug}/` layout, causal back-links between fixes and the changes that introduced them, escalation paths (including late-stage), squash-merge resilience with optional post-merge hook, and self-healing reverse-lookup cache.

See [CHANGELOG.md](./CHANGELOG.md) for full release notes, [docs/plan.md](./docs/plan.md) for v0.2.0 phase rationale, and [docs/init-speedup-plan.md](./docs/init-speedup-plan.md) for v0.3.0 design + workflow-preservation audit.

Schema and templates may still change. Please file issues with the harness output you'd expect to see for your stack.

### Optional dependency

The `/harness-fix` slug derivation transliterates Unicode bug descriptions via the Python `unidecode` library. If unavailable, falls back to ASCII-strip (loses CJK/RTL meaning but never crashes). Install with `pip install unidecode` or `uv pip install unidecode`.
