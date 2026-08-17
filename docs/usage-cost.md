# Usage Cost

`/espalier-init` is a heavy one-time tax. Every subsequent `/espalier <req>` or `/espalier-fix <bug>` reuses what's generated.

## Why the one-time tax pays off

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

## Token volume per full `/espalier-init` run

| Phase | Main agent | Sub-agents (10 scouts + oracle) |
|---|---|---|
| 0 (prompts) | ~0.5K in / 0.2K out | — |
| 1 (discovery, parallel) | ~10K in / 15K out | ~300-400K in / ~15K out |
| 2 (substitution writes, parallel) | ~25K in / 25K out | ~60-100K in / ~5K out |
| 3 (bootstrap bash) | ~3K in / 5K out | — |
| **Total** | **~40K in / 45K out** | **~400-500K in / ~20K out** |

Combined wire volume: **~500K-1M tokens** for a medium repo (~150 source files).

## Cost (USD)

| Setup | Per `/espalier-init` run |
|---|---|
| Opus everywhere (no cache) | $10-20 |
| Opus main + Sonnet scouts (no cache) | $4-8 |
| Opus main + Sonnet scouts + cache hits (typical) | **$2-5** |
| Sonnet everywhere + cache | $1-3 |

Prompt cache (5-min TTL) saves ~50-70% on repeated context loads — kicks in across the 5-7 batched turns.

## Claude Max plan budget

| Plan | Estimated full `/espalier-init` runs per 5-hour window |
|---|---|
| Pro ($20/mo) | <1 (may not complete one full run) |
| Max 5x ($100/mo) | 1-3 |
| Max 20x ($200/mo) | 5-15 |

Plan limits are message-window based + opaque budget for sub-agent fan-out. Verify against current Anthropic dashboard before committing.

## Per-pipeline cost (after init)

| Command | Cost class |
|---|---|
| `/espalier <req>` (full 10-stage pipeline) | MEDIUM — pipeline stages + coding/review sub-agents |
| `/espalier-fix <bug>` (7 stages (0–7, no Stage 2)) | LIGHT-MEDIUM |
| `/espalier-prune <path>` (refresh a stale artifact) | LIGHT — one scout per file + a gated diff |
| `/espalier-doctor` (periodic drift scan) | LIGHT-MEDIUM — re-scouts a handful of artifacts |
| `/espalier-ask <question>` (read-only Q&A) | LIGHT — reads a few docs + verifies against code; no sub-agents |
| `/espalier-audit [path]` (repo-wide security audit) | LIGHT-MEDIUM — 1-4 read-only auditors over the security surface + one wiki write |
| `/espalier-map` (chart or one-ticket session) | LIGHT-MEDIUM — one grill conversation or a few research scouts per session; no coding agents |
| `/espalier-maprun` (one master pass) | LIGHT master + HEAVY workers — the pass itself is a few state reads + question relays; each dispatched worker is a full headless `/espalier` run (budget ≈ N × pipeline cost, spread over hours) |
| `/espalier-migrate` | LIGHT — script-driven, low LLM usage |
| Re-run `/espalier-init` (already bootstrapped) | TRIVIAL — validate-only, ~few K tokens |

## Scaling factors

- Small repo (~50 files): **-30 to -50%** cost
- Large repo (500+ files): **+50 to +200%** cost (scouts read more)
- Oracle WebSearch-heavy stack: **+20-40%**
- Per-layer specs many (5+ layers detected): **+20-30%**

## Check actuals

After a run: `/cost` in Claude Code, or the `caveman-stats` skill (reads session log directly — no AI estimation).
