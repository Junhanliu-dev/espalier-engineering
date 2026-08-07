# Espalier Engineering

> An espalier trains a fruit tree to grow flat along a wall — pruned, wired, productive, and impossible to mistake for a wild one. **Espalier does the same thing for your AI coding agents:** it discovers the patterns already in your codebase, then encodes them as constraints so generated code grows along your conventions on the first try, not the fifth.

```text
/plugin marketplace add Junhanliu-dev/espalier-engineering
/plugin install espalier-engineering@espalier-engineering
/espalier-init
```

> **v0.18.0 — the map lane: planning above one session, and a road into greenfield.** Espalier gains a third altitude. `/espalier <feature>` plans one session's work; **`/espalier-map <idea>`** now plans the work *above* that — an epic, a product on a boilerplate, a greenfield build — as a **decision map** under `espalier/maps/`: a named destination, decision tickets (grilling / research / prototype / task), a fog-of-war section for what can't be phrased yet, and a frontier you work **one ticket per session**. Adapted from Matt Pocock's `wayfinder` (MIT) with Espalier-grade enforcement bolted on: a **map-guard hook** machine-blocks writes outside the map while a session is active (the "agent started building mid-plan" failure structurally removed), a `max-open-tickets` cap stops waterfall over-charting, and every decision runs the grill's rules/wiki cross-check before it locks. A cleared map hands back FILED change skeletons the normal pipeline adopts one at a time — decision → ticket → change → commit stays one audit chain. And `/espalier-init` learns **greenfield**: a near-empty repo takes the two-pass *Decide, Then Bind* path (skeleton install → chart the conventions as decisions → init binds them as rules citing `decided_in:` tickets); boilerplate repos run init first, then map the product against the discovered conventions. Lane quality is measured, not asserted: a shipped read-only **stats hook** (`bash espalier/hooks/espalier-stats.sh`) reports review-round/rollback distributions, the grill-verdict mix, per-map ticket/fog state, and the charted-vs-uncharted cohort comparison (including the fix echo via `caused_by` links), while a new **`eval/map/` harness** (grill-harness pattern: planted decisions, simulated users, LLM judge, 0.80 catch-rate gate) validates the lane itself before release. Validation grows to 50/55/60; migration #25. Suites: bootstrap 197/197, hooks 146/146. Design: [`docs/map-lane-plan.md`](./docs/map-lane-plan.md); migration: [`docs/migrating-v0.17-to-v0.18.md`](./docs/migrating-v0.17-to-v0.18.md).

> **v0.17.0 — the gardener takes over (multi-dev maintenance, Release B-team).** Maintenance becomes a **scheduled singleton**: one rotating gardener runs doctor + prune once per interval in a single weekly maintenance PR, and everyone else's pre-flight defaults to "Proceed". Two small shared files carry the facts that matter through git: the tracked one-line **`espalier/.doctor-stamp`** (only a `clean` stamp satisfies the team; a `dirty:N` stamp satisfies just its writer; skewed stamps rejected; the doctor restamps `clean` when the session's prune cleared everything) and **conventions file-per-key** under `espalier/conventions/` (the towncrier trick: different keys can't conflict at all; a same-key double decision surfaces as an ordinary 5-line git conflict — the conflict *is* the race detection; append collisions resolve by keeping both lines, deduped at read time). No event logs, no fold algorithms, no format markers. Migration #24 is pure-copy only. Suites: bootstrap 177/177, hooks 127/127 with two-clone git sims. Plain-language tour: [`docs/multi-dev-maintenance-how-it-works.md`](./docs/multi-dev-maintenance-how-it-works.md); migration: [`docs/migrating-v0.16-to-v0.17.md`](./docs/migrating-v0.16-to-v0.17.md).

> **v0.16.0 — maintenance goes team-shaped (Release A: the compatibility floor).** With several developers on one repo, the single-dev maintenance loop breaks four ways: every clone sees a different staleness picture, nobody owns the shared upkeep, the bookkeeping files merge with conflicts, and rule changes diverge silently across branches. v0.16.0 ships the floor that fixes the last two and prepares the first two: an executable conventions reader (`conv_fold` — folds the legacy `.conventions.tsv` and the upcoming per-key `espalier/conventions/` files, width-tolerant, deduped, with clock-free status precedence), per-mechanism **maintenance lanes** (doctor and routine prunes ride one weekly maintenance PR; promotions ride the deciding feature branch as their own isolated commit behind a CODEOWNERS merge gate), a corrected promotion **race guard**, canonical-ref config keys, the one `.gitattributes` union entry (`.ask-gaps.tsv`), optional **CODEOWNERS generation**, worktree-correct hook install, an enforced migrate barrier, and conflict/slug-collision recipes. Validation grows to 48/53/58 checks (57-58). Suites: bootstrap 161/161, hooks 99/99. Design: [`docs/multi-dev-maintenance-implementation-plan.md`](./docs/multi-dev-maintenance-implementation-plan.md); plain-language tour: [`docs/multi-dev-maintenance-how-it-works.md`](./docs/multi-dev-maintenance-how-it-works.md).
>
> **Existing users:** run `/espalier-migrate` — the v0.16 step refreshes the pipeline files, appends the Maintenance Commits policy, and re-wires (optionally asking for CODEOWNERS handles). See [`docs/migrating-v0.15-to-v0.16.md`](./docs/migrating-v0.15-to-v0.16.md).

> **v0.15.0 — Espalier learns Copilot; the wiring layer goes three-platform.** `/espalier-init` now targets any subset of **Claude Code, Codex, and GitHub Copilot**. For Copilot the same `espalier/` tree wires through Copilot-native surfaces: the 12 skills as **Agent Skills** in `.github/skills/` (read by VS Code, Copilot CLI, and the cloud coding agent; invoked `/espalier…`), the always-loaded rules via a generated `.github/copilot-instructions.md` section, coder/reviewer/security separation as `@harness-*` **custom agents** (`.github/agents/*.agent.md`), and the two quality gates as **Copilot hooks** (`.github/hooks/espalier-gates.json`) — a small adapter translates Copilot's camelCase hook payload into the Claude/Codex shape, so the *same* two wrapper scripts now gate all three platforms (Copilot fails non-zero `preToolUse` exits closed, matching the exit-2 contract). Wiring stays additive (`espalier/.platforms` unions; nothing ever unwires) and claude-only output stays byte-stable. Suites: bootstrap 117/117, hooks 86/86; validation is 46/51/56 checks by platform set. Setup guide: [`docs/copilot-integration.md`](./docs/copilot-integration.md).
>
> **Existing users:** run `/espalier-migrate` — the v0.15 step installs the one new adapter file and asks whether to wire Copilot. See [`docs/migrating-v0.14-to-v0.15.md`](./docs/migrating-v0.14-to-v0.15.md).

> **v0.14.0 — Espalier learns Codex.** The same discovered guardrails now wire into **OpenAI Codex** as first-class output: `/espalier-init` asks which platform(s) to target (Claude Code, Codex, or both) and, for Codex, wires the very same `espalier/` content through Codex-native surfaces — the 12 skills as repo skills in `.agents/skills/` (invoked `$espalier`, `$espalier-fix`, …), the always-loaded rules via a generated `AGENTS.md` section, the coder/reviewer/security separation as `.codex/agents/harness-*.toml` subagents, and the two quality gates as `PreToolUse`/`PostToolUse` hooks in `.codex/config.toml` (Codex shares Claude Code's hook JSON schema and exit-2-blocks contract, so the *same* wrapper scripts serve both — now hardened to parse `apply_patch` patch bodies and argv-array commands). You can even run `$espalier-init` from inside Codex itself: the skill carries a platform-fallback table (chat questions instead of `AskUserQuestion`, inline discovery instead of scout spawns). Wiring is additive and re-runnable — a claude-only install adds codex later with one `--wire-only --platforms=codex` run (or `/espalier-migrate`), never unwiring anything. Suites extended and green: bootstrap 97/97, hooks 73/73, validation grows to 51 checks on codex installs while claude-only output stays byte-stable at 46. Setup guide: [`docs/codex-integration.md`](./docs/codex-integration.md).
>
> **Existing users:** run `/espalier-migrate`. It applies the chain (… v0.12.0→v0.13.0→v0.13.1→v0.13.2→v0.14.0) in order; the v0.14 step refreshes the two hook wrappers (backups at `<file>.pre-v0.14.bak`) and asks whether to wire Codex — declining changes nothing else. See [`docs/migrating-v0.13-to-v0.14.md`](./docs/migrating-v0.13-to-v0.14.md).

> **v0.13.0 — the coder gets a laziness ladder; the reviewer gets a minimalism lens.** Espalier enforced *fit* — conventions, layers, production seeds — but had no notion of *size*: a convention-perfect 200-line date-picker component passed every gate while `<input type="date">` was never considered. Now the coder climbs a **Solution Selection Ladder** before choosing a change's shape (reuse what the project has → the convention-named mechanism → stdlib/native/installed dep → the leanest compliant implementation; a NEW dependency needs a `requirements.md` line), and the reviewer runs an **advisory Minimalism Review** — `delete:`/`stdlib:`/`native:`/`yagni:` findings capped at **P2/P3** so they can never re-open the Stage 4 fixpoint loop, with ONE objectively-checkable P1: a new dependency covering what stdlib or an installed dep already provides. The governing rule everywhere: **conventions first, correctness within them, brevity only breaks ties** — a construct your rules mandate is never "over-build", and "the convention itself is bloat" routes to the human promotion path, never a blocking finding. Idea adapted from [ponytail](https://github.com/DietrichGebert/ponytail) (MIT), re-grounded convention-first. Gated on both eval suites (coder **4/4** incl. a new overbuild-trap fixture; review **8/8**, catch-rate 1.00, FP 0 — incl. a planted new-dependency P1 and a severity-inflation guard) and quality-scored by independent agents on the darwin 8-dimension rubric: **avg 82.3 → 85.9** after the scorer-finding fix round (reviewer 91.0, coder 88.6). Full report: [`docs/quality-report-v0.13.0.md`](./docs/quality-report-v0.13.0.md).
>
> **Existing users:** run `/espalier-migrate`. It auto-detects your install version and applies the needed migration chain (… v0.10.0→v0.11.0→v0.12.0→v0.13.0) in order. The v0.12→v0.13 step is surgical (anchored section inserts into the four per-project coder/reviewer files — never a template overwrite, backups at `<file>.pre-v0.13.bak`). See [`docs/migrating-v0.12-to-v0.13.md`](./docs/migrating-v0.12-to-v0.13.md).

---

## The Problem

AI coders write plausible-looking code that **doesn't fit your codebase**. They invent helpers when you already have one. They split files the team would keep together. They pick a logging library the project doesn't use. They handle errors with `throw` when your repo standardised on `Result<T>` three years ago.

It's not a model intelligence problem. It's an **unwritten rules** problem — patterns every experienced developer on the team knows but nobody documented. The model can't read your team's Slack history.

## The Solution

Espalier reads your code, extracts those rules, and writes them down as machine-enforceable constraints. The next time the AI codes, it loads your project's rules automatically and follows them. Reviewer agent (different agent, different tool set) checks against the same rules before any commit lands.

Result: **rework cycles drop from 3-5 rounds to typically 1.**

## What It Generates

After running `/espalier-init` on any repo, you get a per-project `espalier/` directory wired into your agent platform(s) — Claude Code, Codex, or both:

```
espalier/
├── rules/                  # always-loaded: engineering structure, coding standards, dev process, security standards, production standards
├── skills/                 # phase-loaded: coding, review, security, testing, requirements, grill, /espalier, /espalier-fix, /espalier-prune, /espalier-doctor, /espalier-ask, /espalier-audit, /espalier-map
├── agents/                 # delegated: harness-coder, harness-reviewer, harness-security (separate tool sets)
├── wiki/                   # on-demand: architecture, data models, critical paths, external services
├── hooks/                  # programmatic gates: layer boundary check, pre-push gate, post-merge drift detect + backlink, map-guard
├── pipeline.md             # 10-stage workflow with explicit gates and rollback rules
├── maps/                   # decision maps (v0.18.0): multi-session planning — /espalier-map
└── changes/                # typed audit trail: feat/, fix/, refactor/, docs/ — one dir per requirement
```

Plus platform wiring for whichever agent(s) you target (`--platforms`, asked at init):

- **Claude Code** — symlinks into `.claude/{rules,skills,agents}` so everything auto-loads, plus a `.claude/settings.json` hook entry for the quality gates.
- **Codex** (v0.14.0) — symlinks into `.agents/skills/` (repo-skill discovery; invoke `$espalier` etc.), an `## Espalier` section in `AGENTS.md` (always-read rules instruction + platform mapping), `.codex/agents/harness-*.toml` subagents, and the same two quality-gate hooks in `.codex/config.toml`. See [`docs/codex-integration.md`](./docs/codex-integration.md).
- **GitHub Copilot** (v0.15.0) — symlinks into `.github/skills/` (Agent Skills for VS Code, Copilot CLI, and the cloud coding agent; invoke `/espalier` etc.), an `## Espalier` section in `.github/copilot-instructions.md`, `@harness-*` custom agents in `.github/agents/`, and the same two gates as Copilot hooks in `.github/hooks/espalier-gates.json` (CLI + cloud agent). See [`docs/copilot-integration.md`](./docs/copilot-integration.md).

The `espalier/` directory itself is platform-neutral — one source of truth however many agents read it.

## The Two Pipelines

After init, your repo exposes two orchestrators:

### `/espalier <requirement>` — full 10-stage pipeline

For features, refactors, and large fixes. Drives requirement → reqs review → coding (sub-agent) → code review (different sub-agent) → tests → test review → push → CI verify → deploy verify → user confirmation. Every stage has a programmatic gate; failed gates roll back; rollback counters trigger human escalation.

**Stage 1 grilling** (v0.6.0): before any code is written, Stage 1 interrogates the requirement — counting concrete ambiguity signals (undefined terms, unstated actors, missing failure behaviour, unscoped edge cases) and asking only as many questions as the input's vagueness warrants. The resolved answers land in `requirements.md`, so later stages execute a spec they can't misread. On by default; skip an invocation with `--no-grill`, and auto-skipped on a non-interactive (no-TTY) run.

**Requirements approval gate** (v0.8.0): after the requirement is written (Stage 1) and reviewed (Stage 2), the pipeline STOPS and waits for your explicit sign-off — Approve / Edit / Abort — before Stage 3 (coding) starts. A Stage 2 PASS no longer authorizes coding on its own. Interactive-only: a no-TTY run auto-approves so unattended pipelines never hang.

Requirement-prefix routing (the `<slug>` is date-prefixed `YYYY-MM-DD-<name>` so change dirs sort chronologically):

| Prefix | Type | Output dir |
|---|---|---|
| `feat:` (or no prefix) | `feat` | `espalier/changes/feat/<slug>/` |
| `refactor:` | `refactor` | `espalier/changes/refactor/<slug>/` |
| `docs:` | `docs` | `espalier/changes/docs/<slug>/` |
| `fix:` | `fix` — full pipeline, for LARGE fixes only (>5 files / multi-layer / schema); a typical single bug belongs in `/espalier-fix`, which adds causal linking | `espalier/changes/fix/<slug>/` |

### `/espalier-fix <bug>` — bug-fix lane, 7 stages (0–7, no Stage 2)

For real bug fixes. Slimmer than full pipeline but adds **Stage 0 auto-link discovery** — the bug-fix gets linked back to the feature change that introduced it (via git blame + reverse-lookup cache + squash-merge mapping). The causing change's `pipeline-state.md` gains a `## Follow-up Fixes` row. Six months later, when someone wonders "why does this feature have 4 fixes against it", the audit trail is right there.

Includes scope-creep escalation gates (predictive + reactive + test-scope + reviewer-flagged) — fix-lane work that exceeds its scope gets cleanly migrated to the full pipeline mid-flight without losing the causal link. Stage 1 grilling (v0.6.0) runs here too, in `diagnosis` mode: it pressure-tests the bug's *root cause* and reproduction before any fix is coded, so the lane isn't patching a symptom on an unconfirmed theory. The v0.8.0 requirements approval gate applies here as well — after the bug requirements + diagnosis are written, the lane stops for your sign-off before coding (it fires after the Stage 1 escalation gate, so only an in-lane fix reaches it).

### `/espalier-ask <question>` — read-only Q&A (v0.7.0)

For "how does X work", "where is Y handled", "why is Z built this way", "what changed recently in X". Instead of exploring the codebase from scratch, it reads your `espalier/` docs first — the wiki for *how/where*, the change history (`requirements.md`, `review-record.md`) for *why* — then **verifies every doc claim against the actual code** before answering, and falls back to a codebase search when the docs come up short. Every claim is sourced (doc path and/or `file:line`).

It is strictly read-only and not a pipeline lane — no stages, no gates, no `changes/` folder. Its only writes are two notify-only sidecars: if a doc it read contradicts the code, it flags that doc stale (the same signal `/espalier-doctor` produces) and points you at `/espalier-prune`; if the docs couldn't answer at all, it logs the question to `espalier/.ask-gaps.tsv` (git-tracked) as evidence of what the wiki should cover next.

### `/espalier-audit` — repo-wide security audit (v0.9.0)

The Stage 4 security audit is change-scoped: it guards code the pipeline writes, not the code you already had. `/espalier-audit` closes that gap — it enumerates the project's security surface (from the discovered trust boundary + wiki critical paths), runs `harness-security` in repo-audit mode over the **existing** handlers/consumers, and writes a point-in-time findings inventory to `espalier/wiki/security-audit.md` (priority, defect, required control, abuse test — per finding). It never edits code and never blocks anything; for each P0/P1 you select, it dispatches a `/espalier-fix` run, so every fix still gets its own approval gate, review panel (with a fresh security re-audit), and contracted abuse test. Optional `scope-path` argument bounds the audit on large repos. Typical uses: baselining a codebase that predates v0.9.0, or a periodic sweep.

### `/espalier-map <idea>` — multi-session planning lane (v0.18.0)

The split is **session count, not project size**: whatever fits one session goes
straight to `/espalier` (Stage 1 grill is the single-session planner). An
effort too big for that — an epic, a greenfield build, a product on a
boilerplate — gets charted as a **decision map** under `espalier/maps/`: a
named destination, decision tickets (`grilling` / `research` / `prototype` /
`task`), a fog-of-war section for what can't be phrased sharply yet, and a
frontier worked **one ticket per session** until nothing is left to decide.
Concept adapted from [Matt Pocock's `wayfinder`](https://github.com/mattpocock/skills)
(MIT), with the enforcement his field reports asked for: the **map-guard
hook** blocks writes outside `espalier/maps/` while a map session is active
(plan-don't-do, machine-verified), `max-open-tickets` caps waterfall
over-charting, and grilling tickets run `espalier-grill` in `decision` mode —
so every decision is cross-checked against your own `rules/` and `wiki/`
before it locks. A cleared map hands back `Status: FILED` change skeletons
(with `charted_from:` frontmatter) that `/espalier` adopts one at a time —
the audit chain reads decision → ticket → change → commit. It plans only; it
never writes product code.

### Greenfield & boilerplate (v0.18.0)

Brownfield espalier discovers rules from code. A **greenfield** repo has no
code to discover — so `/espalier-init` takes the two-pass *Decide, Then Bind*
path: Pass 1 installs the espalier skeleton (`--greenfield` — validation
renders the not-yet-bindable checks as pending-skips) and routes you to
`/espalier-map greenfield: <idea>` to DECIDE stack, architecture, and
conventions as tickets; once the map clears, Pass 2 re-runs init and binds
the decisions as rules — each citing `decided_in: maps/…/tickets/NNN` where a
brownfield rule would cite `file:line`. A **boilerplate** repo is not
greenfield: it has code, so run init normally (the scouts discover the
boilerplate's real conventions), *then* map the product — init-first makes the
grill's cross-check live, so product decisions collide with the boilerplate's
own documented capabilities instead of being decided blind.

### Keeping the guardrails in sync

The artifacts `/espalier-init` generates describe your codebase on init day. As the code evolves, Espalier keeps them honest (since v0.5.0): a post-merge hook flags drifted docs into a gitignored sidecar, the reviewer reports convention shifts a file diff cannot see, and the pipeline surfaces all of it in one Stage 0 pre-flight. `/espalier-ask` (v0.7.0) chips in opportunistically — a stale doc it trips over while answering a question gets flagged the same way, and a question the docs can't answer is logged to `espalier/.ask-gaps.tsv` as a wiki-gap backlog. To refresh a flagged artifact, run `/espalier-prune <path>`; to scan for drift no diff caught, run `/espalier-doctor`. Nothing is ever auto-overwritten — every refresh is gated.

### Multi-developer maintenance (v0.16–v0.17): the weekly gardener

On a team, that upkeep loop stops being everyone's job-in-theory and becomes **one rotating person's ~15-minute job per week** — the gardener. Everyone else answers "Proceed" at the Stage 0 pre-flight and never thinks about maintenance; two small tracked files carry the team-wide facts through git:

- `espalier/.doctor-stamp` — one line, written only by the doctor: when the last scan ran and whether it was `clean` or `dirty:N`. Only a `clean` stamp silences the team-wide "doctor due" reminder; a `dirty` stamp satisfies nobody but its writer.
- `espalier/conventions/k-<key>.tsv` — one tiny file per convention pattern (the towncrier trick). Observations about *different* patterns touch *different* files, so they merge without a human; a same-key double decision surfaces as an ordinary five-line git conflict, which *is* the race detection.

The gardener's week, end to end (espalier runs these for you — shown expanded so you can see there's no magic):

```bash
# 1. Temporary worktree of the canonical branch — your feature branch stays untouched.
B=$(grep '^canonical-branch:' espalier/.espalier-config | awk '{print $2}')
WT=$(mktemp -d) && git worktree add "$WT" "$B" && cd "$WT"

# 2. /espalier-doctor         — the weekly scan; flags drifted docs.
# 3. /espalier-prune <file>   — regenerate each flagged doc; you approve/reject each one.
# 4. If the prune cleared every finding: re-run /espalier-doctor (fast on a clean
#    tree) so the shared stamp records `clean` — a dirty stamp whose findings were
#    fixed in the same PR would keep nagging the whole team forever.
#    The doctor writes + commits espalier/.doctor-stamp as its own commit.

# 5. One PR carrying the stamp + the refreshes, nothing else.
git push origin HEAD:espalier-maintenance   # then open PR: "docs: weekly espalier maintenance"
cd - && git worktree remove "$WT"
```

A skipped week self-corrects: the stamp ages out and `doctor_due()` starts nagging everyone again — the rota is a convenience, not a single point of failure. Promotions (rule changes) stay on the deciding feature branch as their own isolated commit; the generated CODEOWNERS block routes any `espalier/rules/` PR to the rule owner (enforced once "Require review from Code Owners" branch protection is on). Full plain-language tour, conflict playbook included: [`docs/multi-dev-maintenance-how-it-works.md`](./docs/multi-dev-maintenance-how-it-works.md).

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

### Codex (OpenAI) install

Codex has no Claude plugin system — install the init skill as a user-scoped
Codex skill instead:

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.agents/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.agents/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.agents/skills/espalier-migrate
```

Restart Codex, then in your project:

```text
$espalier-init
```

Pick **Codex** (or **Both**) at the platform question. After init: restart
Codex, trust the project when prompted, and run `/hooks` once to trust the two
Espalier quality gates. Pipelines are then `$espalier <requirement>`,
`$espalier-fix <bug>`, `$espalier-ask <question>`, `$espalier-audit`.

Already ran init from Claude Code? Add Codex wiring to the same repo without
redoing discovery:

```bash
bash ~/repos/espalier-engineering/scripts/bootstrap-espalier.sh \
  --wire-only --platforms=codex \
  --plugin-dir=~/repos/espalier-engineering/skills/espalier-init --yes
```

Full guide (what lands where, trust model, degradations): [`docs/codex-integration.md`](./docs/codex-integration.md).

### GitHub Copilot install

Copilot reads Agent Skills from user scope too — link the init skill there:

```bash
git clone https://github.com/Junhanliu-dev/espalier-engineering ~/repos/espalier-engineering
mkdir -p ~/.copilot/skills
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.copilot/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.copilot/skills/espalier-migrate
```

Reload VS Code (or restart Copilot CLI), then in your project run
`/espalier-init` and include **GitHub Copilot** at the platform question.
After init, pipelines are `/espalier <requirement>`, `/espalier-fix <bug>`,
etc., and sub-agents are `@harness-coder` / `@harness-reviewer` /
`@harness-security`. Add Copilot to an existing install without redoing
discovery:

```bash
bash ~/repos/espalier-engineering/scripts/bootstrap-espalier.sh \
  --wire-only --platforms=copilot \
  --plugin-dir=~/repos/espalier-engineering/skills/espalier-init --yes
```

Full guide (per-surface matrix, adapter, degradations): [`docs/copilot-integration.md`](./docs/copilot-integration.md).

## How `/espalier-init` Works

On a fresh repo (~150 source files, medium size), expect **10-15 minutes**. It's a one-time tax — every future `/espalier` and `/espalier-fix` reuses the generated structure. You earn the time back inside the first few requirements via dropped rework rounds.

- **Phase 0 (front-loaded prompts)** — one `AskUserQuestion` captures squash-merge strategy, sub-agent tool scope, and doctor-scan cadence.
- **Phase 1 (parallel discovery)** — single message fires ~11 concurrent tool calls: bash batch (tldr / manifests / git log), 6 scouts (architecture, coding patterns, testing, git+CI, unwritten rules, security surface), 1 oracle (ctx7 + WebSearch in parallel), 3 wiki scouts (data models, critical paths, external services).
- **Phase 2 (parallel writes)** — one Write batch produces ~14 substitution files from the in-context DISCOVERY blob.
- **Phase 3 (bootstrap)** — `scripts/bootstrap-espalier.sh` runs as one bash invocation: mkdir + copies + chmod + safe symlinks + atomic `.claude/settings.json` merge (preserves user hooks) + codex wiring when targeted (AGENTS.md section, `.codex/config.toml` hooks, `.codex/agents/*.toml`) + copilot wiring when targeted (`.github/copilot-instructions.md` section, `.github/skills/` links, `.github/agents/*.agent.md`, `.github/hooks/espalier-gates.json`) + squash-merge decision + post-merge dispatcher install + .gitignore/.gitattributes/CODEOWNERS + 48 validation checks (53 with codex, 58 with copilot).

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
bash scripts/bootstrap-espalier.sh --validate-only  # Stage 11 only (48/53/58 checks by platform set — no changes)
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
| `/espalier-fix <bug>` (7 stages (0–7, no Stage 2)) | LIGHT-MEDIUM |
| `/espalier-prune <path>` (refresh a stale artifact) | LIGHT — one scout per file + a gated diff |
| `/espalier-doctor` (periodic drift scan) | LIGHT-MEDIUM — re-scouts a handful of artifacts |
| `/espalier-ask <question>` (read-only Q&A) | LIGHT — reads a few docs + verifies against code; no sub-agents |
| `/espalier-audit [path]` (repo-wide security audit) | LIGHT-MEDIUM — 1-4 read-only auditors over the security surface + one wiki write |
| `/espalier-map` (chart or one-ticket session) | LIGHT-MEDIUM — one grill conversation or a few research scouts per session; no coding agents |
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

`v0.9.2` — **correctness patch.** A full-repo audit surfaced a cluster of defects concentrated in bash embedded in skill markdown — code no interpreter had ever run end-to-end — plus gate and doc inconsistencies. Fixed and regression-tested: the fix lane's late-escalation gates no longer call a helper that was never shipped, its back-link records the real bug title, and its regression verification is scoped + dependency-linked so a test that *couldn't run* at `Base-Ref` can never be certified as *catching the bug*. The push gate now gates the **active** change — a completed pipeline change no longer blocks every later manual push with its stale certificate — and understands mocha/rspec/go test-count output. `/espalier-audit`'s fix handoff and `/espalier-prune`'s unattended path key off `interactivity_mode` (the TTY test is always false inside Claude Code). Scout 1.11 ships in `.scout-prompts.md`, so prune/doctor can finally refresh `security-standards.md` / `production-standards.md` — the files three other lanes point users at. `ci_checks` discovery gains a null convention (no more invented lint commands blocking pushes). New `scripts/test-hooks.sh` regression suite (28 assertions, written red-first against these bugs) plus a phantom-helper lint. Existing installs: `/espalier-migrate` (new `migrate-v0.9.1-to-v0.9.2.sh` — surgical, preserves your substituted commands and customisations via `.pre-v0.9.2.bak` backups).

`v0.9.1` — **configurable escalation caps.** The review-round and rollback hard stops — how many coder↔reviewer rounds run before the pipeline stops and asks a human — were hardcoded prose scattered across the pipeline templates. They now live in a single tracked config file, `espalier/.espalier-config` (`max-req-rounds`, `max-code-rounds`, `max-test-rounds`, `max-rollbacks`), that the orchestrator reads at runtime — greppable with an integer parse, comment-annotated, and preserved across re-bootstrap (the `.doctor-cadence` precedent). Every gate falls back to 3 when a key is absent, so a missing file never blocks. Defaults unify to **3** across the board (code and test caps rise 2→3; requirements and rollback stay 3). Non-breaking; existing installs run `/espalier-migrate` (v0.9.0 → v0.9.1 writes the config and refreshes the pure-copy pipeline prose). New `migrate-v0.9.0-to-v0.9.1.sh`.

`v0.9.0` — **security audit + repo-wide audit lane + production hardening.** Stage 4 is a two-agent review panel: a new `harness-security` auditor joins the correctness reviewer in the same fixpoint loop, auditing the change's trust boundary on one axiom — *never trust data the frontend sent.* It classifies every client-supplied value on five risk axes (money / identity / permission / owner / state) and hard-blocks any sensitive field the backend fails to re-derive, re-authorize, or recompute (IDOR/BOLA, price tampering, mass assignment, illegal state transitions). Each flagged field becomes an abuse-test contract Stage 5 must satisfy and Stage 6 enforces; `harness-coder` reads the same always-loaded `security-standards.md` at write-time. The push gate gains a secret scan (blocks) + dependency audit (warns). A new `/espalier-audit` lane runs the same auditor repo-wide over existing code, writing a findings inventory to `espalier/wiki/security-audit.md` with per-finding handoff into `/espalier-fix`.

The same release folds in a **production-readiness pass**: a new always-loaded `production-standards.md` rule (resilience — timeouts / bounded queries / atomic state; observability — structured logs, no swallowed errors; data-safety — expand-migrate-contract, idempotent consumers) enforced by the reviewer at tiered severity (P0 for the data-loss class), with failure-mode tests required for new external calls. Plus the gate-integrity fixes a full-system audit surfaced: a **fail-closed push gate** (was fail-open from a subdirectory), a **programmatic build/lint gate** at Stage 3 (no longer trusts the coder's self-report), per-round `VERDICT:` sentinels with dual-record freshness (closes stale-verdict certification), the human-gate interactivity fix (bash TTY checks always read "non-interactive" inside Claude Code), an inlined fix-lane blame procedure + `Base-Ref` regression verification, and a deploy-aware Stage 9. Validation grows to 37 checks; `eval/security/` gates the auditor in both modes. New `migrate-v0.8.2-to-v0.9.0.sh`.

`v0.8.2` — **re-review fixpoint loop + push-gate certificate.** Code review is now a loop, not a single pass: when the reviewer files a P0 and the coder fixes it, the fix is re-reviewed — the only way out of Stage 4 (and Stage 6) is a fresh review of the *current* code returning zero P0, so the coder is never the last actor before the gate, a reviewer always is. A new push-gate certificate binds the verdict to a content fingerprint of the reviewed source (`git hash-object` of the source diff vs a Stage-3 `Base-Ref`, with `espalier/` bookkeeping excluded), so a fix that skips re-review fails closed at push time. Closes the gap where a NEW bug introduced by a fix could ship unreviewed. Non-breaking — in-flight changes without a certificate fall through the gate with a warning. New `migrate-v0.8.1-to-v0.8.2.sh`.

`v0.8.1` — **change-impact / runtime-surface agent guidance.** The coder and reviewer sub-agents now reason about *every* surface a change touches — admin/CRUD UIs, API validation, client forms, persisted data, other callers — not just the programmatic happy path. Closes a class of avoidable fix-round: a value made system-derived (auto-generated/defaulted/computed) but left user-required on a UI, so server-side generation succeeds while the UI still blocks the user before the hook runs. The coder gains a `## Change Impact Analysis` section (map the blast radius before coding); the reviewer gains a `## Runtime-Surface Review` section (a leftover required-on-derived constraint is a P1 defect). Purely additive agent guidance — non-breaking. New `migrate-v0.8-to-v0.8.1.sh` (the two agent files are per-project, so a plugin update can't reach them).

`v0.8.0` — **requirements approval gate.** Both pipelines now stop after the requirement is written and reviewed and wait for explicit user sign-off (Approve / Edit / Abort) before any code is written — closing the old behaviour where Stage 1 → Stage 2 → Stage 3 chained automatically and coding began the moment the requirement doc existed. The full pipeline gates between Stage 2 (review) and Stage 3 (coding); the fix lane gates after Stage 1 (after its escalation gate). Interactive-only — a no-TTY run auto-approves so unattended pipelines never hang. No new skill or stage — a refresh of the three pipeline templates. New `migrate-v0.7-to-v0.8.sh`.

`v0.7.0` — **read-only ask lane.** A new `espalier-ask` skill answers questions about the codebase from the `espalier/` wiki, rules, and change history first — classifying the question (where/how/why/what-changed), verifying every doc claim against the actual code, and falling back to a codebase search when the docs are silent. Read-only: it never edits a doc. Two notify-only byproducts — it flags a stale wiki it caught mid-answer (the `/espalier-doctor` signal) and logs an unanswerable question to a git-tracked `espalier/.ask-gaps.tsv` wiki-gap backlog. Purely additive — no pipeline change. New `migrate-v0.6-to-v0.7.sh` and an `eval/ask/` harness.

`v0.6.0` — **Stage 1 grilling.** A new `espalier-grill` skill interrogates the Stage 1 input before any code is written — adaptive sequential questioning that scores ambiguity signals and resolves them into `requirements.md`, in `spec` mode for `/espalier` and `diagnosis` mode for `/espalier-fix`. On by default, `--no-grill` to skip, auto-skipped without a TTY. Change folders are now date-prefixed (`YYYY-MM-DD-<slug>`) so they sort chronologically. Additive and interactive-only — non-breaking. New `migrate-v0.5-to-v0.6.sh` and an `eval/grill/` harness.

`v0.5.0` — **doc-drift detection.** Generated rules/wiki/specs/hooks are kept in sync with the codebase as it evolves: a post-merge drift detector writing a gitignored sidecar, reviewer convention-drift capture, a cross-PR convention index, the gated `/espalier-prune` refresh skill, a periodic `/espalier-doctor` re-scout, a consolidated Stage 0 pre-flight, a notify-only Stage 8.5, and validation checks 25–28. Non-breaking — drift detection is additive. New `migrate-v0.4-to-v0.5.sh` and a three-stage `/espalier-migrate` chain.

`v0.4.0` — **the rebrand.** Plugin renamed `harness-engineering` → `espalier-engineering`. Target-project directory `harness/` → `espalier/`. Slash commands collapsed: full pipeline is now `/espalier` (was `/harness-run`), bug-fix lane is `/espalier-fix` (was `/harness-fix`), init is `/espalier-init` (was `/harness-engineering`), migration is `/espalier-migrate`. Sub-agent identifiers `harness-coder` / `harness-reviewer` kept for in-flight stability. New `/espalier-migrate` shim detects v0.1.x or v0.3.x installs and dispatches to the right migration script. GitHub repo renamed `harness-engineering` → `espalier-engineering` (GitHub maintains redirects). README now documents per-run token cost + Claude Max plan budget.

`v0.3.0` — init speedup. `/harness-engineering` first run on a fresh repo ~30-50% faster (20+ min → 10-15 min on a medium codebase). Parallel discovery scouts, parallel substitution writes, bundled bootstrap script collapsing Phase 8 (Hooks) + Phase 10 (Wiring) + Phase 11 (Validation) into one idempotent invocation. Plus fixes for several latent v0.2.x bugs.

`v0.2.0` — bug-fix lane (`/harness-fix`), typed `harness/changes/{type}/{slug}/` layout, causal back-links between fixes and the changes that introduced them, escalation paths (including late-stage), squash-merge resilience with optional post-merge hook, and self-healing reverse-lookup cache.

See [CHANGELOG.md](./CHANGELOG.md) for full release notes, [docs/migrating-v0.7-to-v0.8.md](./docs/migrating-v0.7-to-v0.8.md) for the v0.8 requirements approval gate upgrade, [docs/migrating-v0.6-to-v0.7.md](./docs/migrating-v0.6-to-v0.7.md) for the v0.7 read-only ask lane, [docs/migrating-v0.5-to-v0.6.md](./docs/migrating-v0.5-to-v0.6.md) for the v0.6 Stage 1 grill upgrade, [docs/migrating-v0.4-to-v0.5.md](./docs/migrating-v0.4-to-v0.5.md) for the v0.5 doc-drift upgrade, [docs/migrating-v0.3-to-v0.4.md](./docs/migrating-v0.3-to-v0.4.md) for the v0.4 rebrand migration, and [docs/migrating-v0.1-to-v0.2.md](./docs/migrating-v0.1-to-v0.2.md) for the older typed-changes migration.

Schema and templates may still change. Please file issues with the Espalier output you'd expect to see for your stack.

### Optional dependency

The `/espalier-fix` slug derivation transliterates Unicode bug descriptions via the Python `unidecode` library. If unavailable, falls back to ASCII-strip (loses CJK/RTL meaning but never crashes). Install with `pip install unidecode` or `uv pip install unidecode`.
