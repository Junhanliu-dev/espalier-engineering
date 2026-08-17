<p align="center">
  <img src="docs/assets/hero.svg" alt="Espalier Engineering — train your AI coding agents to grow along your codebase's conventions, on the first try" width="100%">
</p>

<p align="center">
  <a href="./CHANGELOG.md"><img src="https://img.shields.io/badge/version-v0.21.0-2ea44f" alt="version v0.21.0"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Copilot-8a63d2" alt="works with Claude Code, Codex, and GitHub Copilot">
</p>

An espalier trains a fruit tree to grow flat along a wall — pruned, wired, productive. **Espalier does the same for your AI coding agents:** it reads your codebase, discovers the patterns already in it, and encodes them as machine-enforced guardrails. Generated code grows along *your* conventions on the first try, not the fifth.

## Quick start

```text
/plugin marketplace add Junhanliu-dev/espalier-engineering
/plugin install espalier-engineering@espalier-engineering
/espalier-init
```

That's it. One ~10–15 minute setup per repo, then every future change reuses it.

## The problem

AI coders write plausible code that **doesn't fit your codebase**. They invent helpers you already have, pick libraries you don't use, and `throw` where your repo standardised on `Result<T>` years ago. It's not a model-intelligence problem — it's an **unwritten rules** problem. The model can't read your team's Slack history.

<p align="center">
  <img src="docs/assets/before-after.svg" alt="Without Espalier: 3–5 rework rounds between coder and reviewer. With Espalier: conventions loaded up front, typically 1 round." width="100%">
</p>

## How it works

<p align="center">
  <img src="docs/assets/how-it-works.svg" alt="espalier-init reads your codebase, discovers its patterns, generates an espalier/ directory of rules, skills, agents, wiki and hooks, and every later change runs through a gated pipeline" width="100%">
</p>

1. **`/espalier-init` discovers** — parallel scout agents read your code and extract the conventions nobody wrote down.
2. **It writes them down** — as a per-project `espalier/` directory: always-loaded rules, phase-loaded skills, sub-agent definitions, a wiki, and programmatic hooks.
3. **Every change is gated** — a coder agent writes, a *separate* reviewer agent (different tool set) checks against the same rules, and hooks block pushes that skip the gates.
4. **It stays honest** — drift detection flags docs the code has outgrown; refreshes are gated, never silent.

```
espalier/
├── rules/        # always loaded: coding standards, security, production standards
├── skills/       # the pipelines: /espalier, /espalier-fix, /espalier-ask, …
├── agents/       # harness-coder / harness-reviewer / harness-security
├── wiki/         # architecture, data models, critical paths
├── hooks/        # programmatic gates: layer checks, pre-push, drift detect
├── maps/         # multi-session decision maps
└── changes/      # typed audit trail — one folder per requirement
```

## The commands

| Command | What it does |
|---|---|
| `/espalier-init` | One-time setup: discover conventions, generate + wire the guardrails |
| `/espalier <feature>` | Full 10-stage pipeline: grilled requirements → your approval → code → independent review → tests → gated push |
| `/espalier-fix <bug>` | Slimmer bug-fix lane that auto-links each fix to the change that caused it |
| `/espalier-ask <question>` | Read-only Q&A — answers from your docs, verified against the code, every claim sourced |
| `/espalier-audit` | Repo-wide security audit of *existing* code; findings hand off into fix runs |
| `/espalier-map <idea>` | Plan work bigger than one session (epics, greenfield) as a decision map |
| `/espalier-maprun` | Execute a cleared map: headless workers in isolated worktrees, reviewable slice PRs |
| `/espalier-doctor` / `/espalier-prune` | Detect doc drift / refresh a stale doc (gated) |
| `/espalier-migrate` | Upgrade an existing install to the current version |

Highlights along the way:

- **Grilled requirements** — before any code, Stage 1 interrogates the request exactly as hard as its vagueness warrants, then **stops for your explicit sign-off**. Later stages execute a spec they can't misread.
- **Separate judge** — the reviewer is always a different agent with read-only tools. It can't rubber-stamp its own work, and a security auditor joins it on every change's trust boundary.
- **Causal links** — six months later, "why does this feature have 4 fixes against it?" is answered by the audit trail, automatically.
- **Team-ready** — on multi-dev repos, upkeep collapses to one rotating person's ~15-minute weekly job ([how it works](./docs/multi-dev-maintenance-how-it-works.md)).

## Works with your agent — whichever it is

The `espalier/` directory is platform-neutral; init wires it into any subset of:

- **Claude Code** — auto-loaded via `.claude/` symlinks + settings hooks
- **OpenAI Codex** — repo skills, `AGENTS.md` section, `.codex/` agents + hooks ([guide](./docs/codex-integration.md))
- **GitHub Copilot** — Agent Skills, `copilot-instructions.md`, `.github/` agents + hooks ([guide](./docs/copilot-integration.md))

Same rules, same gates, on all three. Add a platform later with one re-wire — nothing is ever unwired.

<details>
<summary><b>Manual / per-project / Codex / Copilot install commands</b></summary>

### Manual git clone + symlink (Claude Code)

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
ln -sfn ~/repos/espalier-engineering/skills/espalier-init ~/.claude/skills/espalier-init
```

Restart Claude Code; update later with `git pull`.

### Project-scoped install

```bash
mkdir -p .claude/skills
ln -sfn /path/to/espalier-engineering/skills/espalier-init .claude/skills/espalier-init
```

### Codex (OpenAI)

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.agents/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.agents/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.agents/skills/espalier-migrate
```

Restart Codex, run `$espalier-init`, pick **Codex** (or **Both**) at the platform question. After init: restart Codex, trust the project, run `/hooks` once to trust the two quality gates. Pipelines are `$espalier`, `$espalier-fix`, `$espalier-ask`, `$espalier-audit`.

Already ran init from Claude Code? Add Codex wiring without redoing discovery:

```bash
bash ~/repos/espalier-engineering/scripts/bootstrap-espalier.sh \
  --wire-only --platforms=codex \
  --plugin-dir=~/repos/espalier-engineering/skills/espalier-init --yes
```

### GitHub Copilot

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.copilot/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.copilot/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.copilot/skills/espalier-migrate
```

Reload VS Code (or restart Copilot CLI), run `/espalier-init`, include **GitHub Copilot** at the platform question. Sub-agents are `@harness-coder` / `@harness-reviewer` / `@harness-security`. Add Copilot to an existing install with `--wire-only --platforms=copilot` as above.

</details>

## What it costs

Init is a one-time ~$2–5 on a medium repo (Opus main + Sonnet scouts + cache). Without Espalier, *every* request re-discovers your conventions and burns 3–5 review rounds — you typically earn the init cost back within 5–10 feature requests. Full token/cost breakdown, plan budgets, and per-command cost classes: [docs/usage-cost.md](./docs/usage-cost.md).

**Skip Espalier for:** throwaway prototypes, single-file scripts, solo projects where consistency doesn't matter. For anything you'll iterate on for weeks, it pays back fast.

## Philosophy

> When an agent makes an error, engineer its elimination — not with prompt tweaks, but with files, rules, automated checks, and system structure.

1. **Discover, don't prescribe** — extract patterns from the actual code; never impose templates.
2. **Quality gates must be programmatic** — `ci_status == 'success'`, not "check if CI passes".
3. **Separate execution from judgment** — coder and reviewer are different agents with different tool sets.
4. **Context layering** — rules always loaded; skills per phase; wiki on demand.
5. **Every rule has a reason** — an observed pattern, or a known failure mode it prevents.

## Latest release

**v0.21.0 — pipeline speed, same gates.** The pipeline's quality machinery is untouched (separate coder/reviewer/security agents, fresh panel round after every fix, programmatic gates); what shrinks is the redundant work: a per-change **context pack** assembled once and reused by every sub-agent spawn, **delta-scoped re-review rounds** (required reads = fix + prior findings + dependents; expandable on any suspicion), **parallel dispatch** for disjoint sub-tasks, **push-target pre-authorization** at the approval gate, and light-tier grill questions batched when provably independent. Details in the [CHANGELOG](./CHANGELOG.md).

Full history and migration guides: [CHANGELOG.md](./CHANGELOG.md) · upgrade any install with `/espalier-migrate`.

## License

MIT — see [LICENSE](./LICENSE).
