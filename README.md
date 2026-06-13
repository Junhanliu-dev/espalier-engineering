# Espalier Engineering

> An espalier trains a fruit tree to grow flat along a wall — pruned, wired, productive, and impossible to mistake for a wild one. **Espalier does the same thing for your AI coding agents:** it discovers the patterns already in your codebase, then encodes them as constraints so generated code grows along your conventions on the first try, not the fifth.

```text
/plugin marketplace add Junhanliu-dev/espalier-engineering
/plugin install espalier-engineering@espalier-engineering
/espalier-init
```

> **v0.7.0 — read-only ask lane.** New `/espalier-ask <question>` answers "how does X work / where is Y / why is Z built this way / what changed recently" from your `espalier/` wiki, rules, and change history first — verified against the actual code — falling back to a codebase search when the docs are silent. Read-only: it never edits a doc. As byproducts it opportunistically flags a stale wiki it caught mid-answer, and logs a question the docs couldn't answer as a wiki gap. Purely additive — no pipeline change.
>
> **Existing users:** run `/espalier-migrate`. It auto-detects your install version and applies the needed migration chain (… v0.6→v0.7) in order. See [`docs/migrating-v0.6-to-v0.7.md`](./docs/migrating-v0.6-to-v0.7.md).

---

## The Problem

AI coders write plausible-looking code that **doesn't fit your codebase**. They invent helpers when you already have one. They split files the team would keep together. They pick a logging library the project doesn't use. They handle errors with `throw` when your repo standardised on `Result<T>` three years ago.

It's not a model intelligence problem. It's an **unwritten rules** problem — patterns every experienced developer on the team knows but nobody documented. The model can't read your team's Slack history.

## The Solution

Espalier reads your code, extracts those rules, and writes them down as machine-enforceable constraints. The next time the AI codes, it loads your project's rules automatically and follows them. Reviewer agent (different agent, different tool set) checks against the same rules before any commit lands.

Result: **rework cycles drop from 3-5 rounds to typically 1.**

## What It Generates

After running `/espalier-init` on any repo, you get a per-project `espalier/` directory wired into Claude Code:

```
espalier/
├── rules/                  # always-loaded: engineering structure, coding standards, dev process
├── skills/                 # phase-loaded: coding, review, testing, requirements, grill, /espalier, /espalier-fix, /espalier-prune, /espalier-doctor, /espalier-ask
├── agents/                 # delegated: harness-coder, harness-reviewer (separate tool sets)
├── wiki/                   # on-demand: architecture, data models, critical paths, external services
├── hooks/                  # programmatic gates: layer boundary check, pre-push gate, post-merge drift detect + backlink
├── pipeline.md             # 10-stage workflow with explicit gates and rollback rules
└── changes/                # typed audit trail: feat/, fix/, refactor/, docs/ — one dir per requirement
```

Plus symlinks into `.claude/` so Claude Code discovers everything, plus a `.claude/settings.json` hook entry for the quality gates.

## The Two Pipelines

After init, your repo exposes two orchestrators:

### `/espalier <requirement>` — full 10-stage pipeline

For features, refactors, and large fixes. Drives requirement → reqs review → coding (sub-agent) → code review (different sub-agent) → tests → test review → push → CI verify → deploy verify → user confirmation. Every stage has a programmatic gate; failed gates roll back; rollback counters trigger human escalation.

**Stage 1 grilling** (v0.6.0): before any code is written, Stage 1 interrogates the requirement — counting concrete ambiguity signals (undefined terms, unstated actors, missing failure behaviour, unscoped edge cases) and asking only as many questions as the input's vagueness warrants. The resolved answers land in `requirements.md`, so later stages execute a spec they can't misread. On by default; skip an invocation with `--no-grill`, and auto-skipped on a non-interactive (no-TTY) run.

Requirement-prefix routing (the `<slug>` is date-prefixed `YYYY-MM-DD-<name>` so change dirs sort chronologically):

| Prefix | Type | Output dir |
|---|---|---|
| `feat:` (or no prefix) | `feat` | `espalier/changes/feat/<slug>/` |
| `refactor:` | `refactor` | `espalier/changes/refactor/<slug>/` |
| `docs:` | `docs` | `espalier/changes/docs/<slug>/` |
| `fix:` | use `/espalier-fix` instead | — |

### `/espalier-fix <bug>` — 5-stage bug-fix lane

For real bug fixes. Slimmer than full pipeline but adds **Stage 0 auto-link discovery** — the bug-fix gets linked back to the feature change that introduced it (via git blame + reverse-lookup cache + squash-merge mapping). The causing change's `pipeline-state.md` gains a `## Follow-up Fixes` row. Six months later, when someone wonders "why does this feature have 4 fixes against it", the audit trail is right there.

Includes scope-creep escalation gates (predictive + reactive + test-scope + reviewer-flagged) — fix-lane work that exceeds its scope gets cleanly migrated to the full pipeline mid-flight without losing the causal link. Stage 1 grilling (v0.6.0) runs here too, in `diagnosis` mode: it pressure-tests the bug's *root cause* and reproduction before any fix is coded, so the lane isn't patching a symptom on an unconfirmed theory.

### `/espalier-ask <question>` — read-only Q&A (v0.7.0)

For "how does X work", "where is Y handled", "why is Z built this way", "what changed recently in X". Instead of exploring the codebase from scratch, it reads your `espalier/` docs first — the wiki for *how/where*, the change history (`requirements.md`, `review-record.md`) for *why* — then **verifies every doc claim against the actual code** before answering, and falls back to a codebase search when the docs come up short. Every claim is sourced (doc path and/or `file:line`).

It is strictly read-only and not a pipeline lane — no stages, no gates, no `changes/` folder. Its only writes are two notify-only sidecars: if a doc it read contradicts the code, it flags that doc stale (the same signal `/espalier-doctor` produces) and points you at `/espalier-prune`; if the docs couldn't answer at all, it logs the question to `espalier/.ask-gaps.tsv` (git-tracked) as evidence of what the wiki should cover next.

### Keeping the guardrails in sync

The artifacts `/espalier-init` generates describe your codebase on init day. As the code evolves, Espalier keeps them honest (since v0.5.0): a post-merge hook flags drifted docs into a gitignored sidecar, the reviewer reports convention shifts a file diff cannot see, and the pipeline surfaces all of it in one Stage 0 pre-flight. `/espalier-ask` (v0.7.0) chips in opportunistically — a stale doc it trips over while answering a question gets flagged the same way, and a question the docs can't answer is logged to `espalier/.ask-gaps.tsv` as a wiki-gap backlog. To refresh a flagged artifact, run `/espalier-prune <path>`; to scan for drift no diff caught, run `/espalier-doctor`. Nothing is ever auto-overwritten — every refresh is gated.

## Install

### Marketplace (recommended)

```text
/plugin marketplace add Junhanliu-dev/espalier-engineering
/plugin install espalier-engineering@espalier-engineering
```

Then in any project:

```text
/espalier-init
```

Updates later:

```text
/plugin update espalier-engineering
```

### Manual git clone + symlink

For users not on the plugin path, or while iterating:

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
ln -sfn ~/repos/espalier-engineering/skills/espalier-init ~/.claude/skills/espalier-init
```

Restart Claude Code. The skill is now discoverable.

Update with `cd ~/repos/espalier-engineering && git pull`.

### Project-scoped install

Drop the skill inside a single project rather than installing globally:

```bash
mkdir -p .claude/skills
ln -sfn /path/to/espalier-engineering/skills/espalier-init .claude/skills/espalier-init
```

## How `/espalier-init` Works

On a fresh repo (~150 source files, medium size), expect **10-15 minutes**. It's a one-time tax — every future `/espalier` and `/espalier-fix` reuses the generated structure. You earn the time back inside the first few requirements via dropped rework rounds.

- **Phase 0 (front-loaded prompts)** — one `AskUserQuestion` captures squash-merge strategy, sub-agent tool scope, and doctor-scan cadence.
- **Phase 1 (parallel discovery)** — single message fires ~10 concurrent tool calls: bash batch (tldr / manifests / git log), 6 scouts (architecture, coding patterns, testing, CI, unwritten rules, layer specs), 1 oracle (ctx7 + WebSearch in parallel), 3 wiki scouts (data models, critical paths, external services).
- **Phase 2 (parallel writes)** — one Write batch produces ~14 substitution files from the in-context DISCOVERY blob.
- **Phase 3 (bootstrap)** — `scripts/bootstrap-espalier.sh` runs as one bash invocation: mkdir + copies + chmod + safe symlinks + atomic `.claude/settings.json` merge (preserves user hooks) + squash-merge decision + post-merge dispatcher install + .gitignore + 29 validation checks.

Total: ~5-7 batched turns, ~25-35 raw tool calls.

The skill never modifies its own source — it only writes content into the project it's invoked from.

### Re-running on existing installs

- **Fully bootstrapped repo** (`espalier/.merge-hook-decision` present) → bootstrap auto-runs validation only (Stage 11), exit 0. Idempotent health check.
- **v0.3.x repo** (`harness/.merge-hook-decision` present, no `espalier/` dir) → bootstrap exits 1, suggests `/espalier-migrate`.
- **v0.1.x repo** (wired symlinks, no decision file) → bootstrap exits 1, suggests `/espalier-migrate`.
- **Partial install / corrupted state** → `--force` redoes all stages.

### Debug flags (not used by normal flow)

```bash
bash scripts/bootstrap-espalier.sh --copy-only      # Stages 1-4 only (dirs + cp templates + hooks)
bash scripts/bootstrap-espalier.sh --wire-only      # Stages 5-11 only (symlinks + wiring + validation)
bash scripts/bootstrap-espalier.sh --validate-only  # Stage 11 only (29 checks, no changes)
bash scripts/bootstrap-espalier.sh --dry-run        # Print actions without executing
```

## Usage Cost

`/espalier-init` is a heavy one-time tax. Every subsequent `/espalier <req>` or `/espalier-fix <bug>` reuses what's generated.

### Why the one-time tax pays off

The cost compares **once-per-repo** against **every-request-forever**:

| Without Espalier | With Espalier |
|---|---|
| Every request: agent re-discovers conventions from scratch by reading source files into context — burns tokens on the same exploration each time | Conventions loaded once from `espalier/rules/*` (~3K tokens, always cached) |
| Every request: 3-5 review rounds (agent writes code that doesn't fit, reviewer flags it, agent retries) | Typically 1 review round — code lands inside conventions on first attempt |
| Every request: human catches "this doesn't match our patterns" and explains them again | Patterns enforced by `harness-reviewer` agent automatically; human reviews business logic only |
| Implicit/forgotten unwritten rules cause silent drift across the codebase | Rules encoded in `coding-standards.md`, enforced by reviewer + pre-push hook |

**Math:** A typical feature request without Espalier consumes 2-4× the tokens of a single `/espalier` invocation (because the agent re-loads the codebase into context per round, and there are 3-5 rounds). Across ~5-10 feature requests, you earn back the `/espalier-init` cost. Across a quarter of work, the savings compound substantially.

**Side benefits beyond cost:**
- **Convention consistency** — codebase doesn't drift toward whatever-the-model-felt-like-today
- **Audit trail** — every change has `pipeline-state.md` with stages, gates, sub-agent outputs, commit SHAs
- **Causal links** — `/espalier-fix` auto-links bugs to the feature that introduced them (catches "this feature has 4 fixes against it" patterns)
- **Hand-off ready** — a new dev (or new AI session) reads `espalier/rules/` + `espalier/wiki/` and is productive without re-onboarding
- **Programmatic gates** — pre-push hook blocks pushes at wrong pipeline stage; reviewer can't approve P0 violations

**When NOT to run `/espalier-init`:**
- Throwaway / prototype project that won't see 5+ feature requests
- Solo project where you don't care about consistency (just write the code yourself)
- Project too small to have meaningful conventions (single-file script)

For everything else — anything you'll iterate on for weeks+ — the tax pays back fast.



### Token volume per full `/espalier-init` run

| Phase | Main agent | Sub-agents (10 scouts + oracle) |
|---|---|---|
| 0 (prompts) | ~0.5K in / 0.2K out | — |
| 1 (discovery, parallel) | ~10K in / 15K out | ~300-400K in / ~15K out |
| 2 (substitution writes, parallel) | ~25K in / 25K out | ~60-100K in / ~5K out |
| 3 (bootstrap bash) | ~3K in / 5K out | — |
| **Total** | **~40K in / 45K out** | **~400-500K in / ~20K out** |

Combined wire volume: **~500K-1M tokens** for a medium repo (~150 source files).

### Cost (USD)

| Setup | Per `/espalier-init` run |
|---|---|
| Opus everywhere (no cache) | $10-20 |
| Opus main + Sonnet scouts (no cache) | $4-8 |
| Opus main + Sonnet scouts + cache hits (typical) | **$2-5** |
| Sonnet everywhere + cache | $1-3 |

Prompt cache (5-min TTL) saves ~50-70% on repeated context loads — kicks in across the 5-7 batched turns.

### Claude Max plan budget

| Plan | Estimated full `/espalier-init` runs per 5-hour window |
|---|---|
| Pro ($20/mo) | <1 (may not complete one full run) |
| Max 5x ($100/mo) | 1-3 |
| Max 20x ($200/mo) | 5-15 |

Plan limits are message-window based + opaque budget for sub-agent fan-out. Verify against current Anthropic dashboard before committing.

### Per-pipeline cost (after init)

| Command | Cost class |
|---|---|
| `/espalier <req>` (full 10-stage pipeline) | MEDIUM — pipeline stages + coding/review sub-agents |
| `/espalier-fix <bug>` (5-stage lane) | LIGHT-MEDIUM |
| `/espalier-prune <path>` (refresh a stale artifact) | LIGHT — one scout per file + a gated diff |
| `/espalier-doctor` (periodic drift scan) | LIGHT-MEDIUM — re-scouts a handful of artifacts |
| `/espalier-ask <question>` (read-only Q&A) | LIGHT — reads a few docs + verifies against code; no sub-agents |
| `/espalier-migrate` | LIGHT — script-driven, low LLM usage |
| Re-run `/espalier-init` (already bootstrapped) | TRIVIAL — validate-only, ~few K tokens |

### Scaling factors

- Small repo (~50 files): **-30 to -50%** cost
- Large repo (500+ files): **+50 to +200%** cost (scouts read more)
- Oracle WebSearch-heavy stack: **+20-40%**
- Per-layer specs many (5+ layers detected): **+20-30%**

### Check actuals

After a run: `/cost` in Claude Code, or the `caveman-stats` skill (reads session log directly — no AI estimation).

## Philosophy

> When an agent makes an error, engineer its elimination — not with prompt tweaks, but with files, rules, automated checks, and system structure.

Five guiding principles:

1. **Discover, don't prescribe** — read the actual code, extract patterns; never impose templates from other projects.
2. **Quality gates must be programmatic** — `ci_status == 'success' AND tests_passed == total_tests`, not "check if CI passes".
3. **Separate execution from judgment** — coder agent and reviewer agent are always different invocations with different tool sets (coder has Write/Edit; reviewer has only Read/Grep/Glob/Bash).
4. **Context layering** — rules always loaded; skills loaded per phase; agents see only their scope; wiki on demand.
5. **Every rule has a reason** — either reflects an observed pattern, or prevents a known failure mode.

## License

MIT — see [LICENSE](./LICENSE).

## Status

`v0.7.0` — **read-only ask lane.** A new `espalier-ask` skill answers questions about the codebase from the `espalier/` wiki, rules, and change history first — classifying the question (where/how/why/what-changed), verifying every doc claim against the actual code, and falling back to a codebase search when the docs are silent. Read-only: it never edits a doc. Two notify-only byproducts — it flags a stale wiki it caught mid-answer (the `/espalier-doctor` signal) and logs an unanswerable question to a git-tracked `espalier/.ask-gaps.tsv` wiki-gap backlog. Purely additive — no pipeline change. New `migrate-v0.6-to-v0.7.sh` and an `eval/ask/` harness.

`v0.6.0` — **Stage 1 grilling.** A new `espalier-grill` skill interrogates the Stage 1 input before any code is written — adaptive sequential questioning that scores ambiguity signals and resolves them into `requirements.md`, in `spec` mode for `/espalier` and `diagnosis` mode for `/espalier-fix`. On by default, `--no-grill` to skip, auto-skipped without a TTY. Change folders are now date-prefixed (`YYYY-MM-DD-<slug>`) so they sort chronologically. Additive and interactive-only — non-breaking. New `migrate-v0.5-to-v0.6.sh` and an `eval/grill/` harness.

`v0.5.0` — **doc-drift detection.** Generated rules/wiki/specs/hooks are kept in sync with the codebase as it evolves: a post-merge drift detector writing a gitignored sidecar, reviewer convention-drift capture, a cross-PR convention index, the gated `/espalier-prune` refresh skill, a periodic `/espalier-doctor` re-scout, a consolidated Stage 0 pre-flight, a notify-only Stage 8.5, and validation checks 25–28. Non-breaking — drift detection is additive. New `migrate-v0.4-to-v0.5.sh` and a three-stage `/espalier-migrate` chain.

`v0.4.0` — **the rebrand.** Plugin renamed `harness-engineering` → `espalier-engineering`. Target-project directory `harness/` → `espalier/`. Slash commands collapsed: full pipeline is now `/espalier` (was `/harness-run`), bug-fix lane is `/espalier-fix` (was `/harness-fix`), init is `/espalier-init` (was `/harness-engineering`), migration is `/espalier-migrate`. Sub-agent identifiers `harness-coder` / `harness-reviewer` kept for in-flight stability. New `/espalier-migrate` shim detects v0.1.x or v0.3.x installs and dispatches to the right migration script. GitHub repo renamed `harness-engineering` → `espalier-engineering` (GitHub maintains redirects). README now documents per-run token cost + Claude Max plan budget.

`v0.3.0` — init speedup. `/harness-engineering` first run on a fresh repo ~30-50% faster (20+ min → 10-15 min on a medium codebase). Parallel discovery scouts, parallel substitution writes, bundled bootstrap script collapsing Phase 8 (Hooks) + Phase 10 (Wiring) + Phase 11 (Validation) into one idempotent invocation. Plus fixes for several latent v0.2.x bugs.

`v0.2.0` — bug-fix lane (`/harness-fix`), typed `harness/changes/{type}/{slug}/` layout, causal back-links between fixes and the changes that introduced them, escalation paths (including late-stage), squash-merge resilience with optional post-merge hook, and self-healing reverse-lookup cache.

See [CHANGELOG.md](./CHANGELOG.md) for full release notes, [docs/migrating-v0.5-to-v0.6.md](./docs/migrating-v0.5-to-v0.6.md) for the v0.6 Stage 1 grill upgrade, [docs/migrating-v0.4-to-v0.5.md](./docs/migrating-v0.4-to-v0.5.md) for the v0.5 doc-drift upgrade, [docs/migrating-v0.3-to-v0.4.md](./docs/migrating-v0.3-to-v0.4.md) for the v0.4 rebrand migration, and [docs/migrating-v0.1-to-v0.2.md](./docs/migrating-v0.1-to-v0.2.md) for the older typed-changes migration.

Schema and templates may still change. Please file issues with the Espalier output you'd expect to see for your stack.

### Optional dependency

The `/espalier-fix` slug derivation transliterates Unicode bug descriptions via the Python `unidecode` library. If unavailable, falls back to ASCII-strip (loses CJK/RTL meaning but never crashes). Install with `pip install unidecode` or `uv pip install unidecode`.
