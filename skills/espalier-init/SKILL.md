---
name: espalier-init
description: Analyze any existing codebase, discover its patterns and best practices, and generate an Espalier structure (rules, skills, wiki, pipeline) so AI coders produce code matching that project's language and conventions
---

# Espalier Init

Discover the actual patterns, conventions, and architecture of an existing codebase, then generate a structured constraint system that ensures AI agents produce code matching those standards.

## When to Use

- "Set up Espalier for this project"
- "Create Espalier structure for my codebase"
- "Make AI code production-ready for this repo"
- "Build agent constraints for this project"
- "/espalier-init"

## Philosophy

> When an agent makes an error, engineer its elimination — not with prompt tweaks, but with files, rules, automated checks, and system structure.

**Core insight:** The problem isn't model intelligence. It's that models don't know the unwritten rules — patterns every experienced developer on the team knows but nobody documented.

This skill **discovers** those rules from the code itself, then encodes them as machine-enforceable constraints. Like an espalier trains a fruit tree to grow along a wall, this skill trains your AI coder to grow along the patterns already in your codebase.

## File Layout of This Skill

```
espalier-init/
├── SKILL.md                       # this file — overview + phase index
├── templates/                     # markdown templates emitted into target project
│   ├── rules/                     # → espalier/rules/ in target
│   ├── skills/                    # → espalier/skills/<name>/SKILL.md
│   ├── agents/                    # → espalier/agents/ in target
│   ├── agent.md                   # → espalier/agent.md (orchestrator)
│   └── pipeline.md                # → espalier/pipeline.md
├── hook-templates/                # shell scripts emitted into espalier/hooks/
└── references/                    # deep-dive content read on demand
    ├── discovery-checklist.md     # Phase 1 detail
    ├── wiring.md                  # Phase 10 detail
    ├── validation.md              # Phase 11 detail
    └── wiki-templates.md          # Phase 6 wiki stubs
```

**Rule:** Every phase below tells you which template/reference to read. Open them with the Read tool when the phase fires — do NOT invent template content from memory.

## Output Structure in Target Project (after full setup)

```
project-root/
├── .claude/
│   ├── rules/                     # symlinks to espalier/rules/*.md
│   ├── skills/                    # symlinks to espalier/skills/*
│   ├── agents/                    # symlinks to espalier/agents/*.md
│   └── settings.json              # hooks for quality gates
├── CLAUDE.md                       # references espalier/agent.md
├── espalier/
│   ├── agent.md                    # orchestrator definition
│   ├── rules/                      # engineering-structure, coding-standards, development-process
│   ├── skills/                     # folder name MUST equal SKILL.md `name:` frontmatter
│   │   ├── espalier-coding/
│   │   │   ├── SKILL.md
│   │   │   └── specs/{layer}.md
│   │   ├── espalier-review/SKILL.md
│   │   ├── espalier-testing/SKILL.md
│   │   ├── espalier-requirements/SKILL.md
│   │   ├── espalier-grill/SKILL.md             # Stage 1 interrogation (invoked by espalier + espalier-fix)
│   │   ├── espalier/SKILL.md                   # main pipeline orchestrator (slash: /espalier)
│   │   ├── espalier-fix/SKILL.md               # bug-fix lane (5-stage; slash: /espalier-fix)
│   │   ├── espalier-prune/SKILL.md             # stale-artifact refresh (slash: /espalier-prune)
│   │   ├── espalier-doctor/SKILL.md            # periodic drift scan (slash: /espalier-doctor)
│   │   └── espalier-ask/SKILL.md               # read-only Q&A lane (slash: /espalier-ask)
│   ├── agents/                     # harness-coder.md, harness-reviewer.md (agent names kept for stability)
│   ├── wiki/                       # architecture, data-models, critical-paths, external-services
│   ├── hooks/                      # check-layer-boundaries.sh, pre-push-gate.sh
│   ├── pipeline.md
│   └── changes/                    # typed: feat/, fix/, refactor/, …
│       ├── _template/              # requirements.md, task-breakdown.md, coding-report.md, review-record.md, pipeline-state.md, ci-result.md
│       ├── feat/{slug}/            # full pipeline outputs   ({slug} = YYYY-MM-DD-<name>, sorts chronologically)
│       ├── fix/{slug}/             # fix-lane outputs (with caused_by frontmatter)
│       └── refactor/{slug}/        # (future)
└── src/  (existing code)
```

---

## Skill Naming Invariant (CRITICAL — read before creating any skill)

Claude Code's skill loader compares the **folder name** against the SKILL.md `name:` frontmatter. If they differ, the skill emits a warning and may fail to register.

**Rule:** every skill folder MUST be named identically to its `name:` frontmatter value.

```
✅ CORRECT
espalier/skills/espalier-coding/SKILL.md         (name: espalier-coding)
espalier/skills/espalier-review/SKILL.md         (name: espalier-review)
espalier/skills/espalier/SKILL.md                (name: espalier)            ← main pipeline

❌ WRONG (will warn / break)
espalier/skills/coding/SKILL.md                  (name: espalier-coding)
espalier/skills/review/SKILL.md                  (name: espalier-review)
```

When you generate a skill:
1. Choose the `name:` value first (must be globally unique, kebab-case, descriptive — prefix with `espalier-` for child skills inside this install; the main pipeline owns the bare name `espalier`).
2. Use the SAME string as the folder name.
3. Symlinks in `.claude/skills/<name>` then resolve to a same-named source folder — no mismatch possible.

This applies to **all** skill folders generated by this skill: espalier-coding, espalier-review, espalier-testing, espalier-requirements, espalier-grill, espalier (main), espalier-fix, espalier-prune, espalier-doctor, espalier-ask, and any additional ones added later.

---

## Phase Dependency Note (parallel execution)

Phases 0-2 are sequential by necessity (Phase 0 prompt blocks; Phase 1 produces DISCOVERY blob consumed by Phase 2). Within Phase 1 and Phase 2, work is parallel. Phases 3+ are bundled into a single `bootstrap-espalier.sh` invocation.

**Rule:** run Phases 0 → 1 → 2 → 3 in order. Each step batches parallel work to minimize sequential tool calls (~5-7 batched turns total).

---

## Phase 0: Setup Decisions (front-loaded)

Issue ONE `AskUserQuestion` with THREE questions in the multi-question form:

### Q1 — Squash-merge strategy

```
How does this repo merge PRs? Choice affects how /espalier-fix links bug
fixes to causing commits.

  1. Rebase-merge / true merge-commit                   → MERGE_DECISION = not-needed
       SHAs preserved; no special handling needed.
  2. Squash + install post-merge hook (recommended)     → MERGE_DECISION = installed
       Hook records original→squashed SHA so fix lane finds origin via O(1) lookup.
  3. Squash + allow fuzzy match at fix-time             → MERGE_DECISION = fuzzy-allowed
       No hook. Fix lane falls back to file-overlap heuristic. Less safe.
  4. Squash + skip linking when SHA misses (safest)     → MERGE_DECISION = skip-only
       No hook, no fuzzy. Fix proceeds without causal link if SHA unresolvable.
  5. Squash + never ask again, always skip              → MERGE_DECISION = never-ask
       Same as skip-only but suppresses future "what should I do" prompts.
  6. Decide later                                       → MERGE_DECISION = ask-later
       Defer. Fix lane will prompt the first time SHA resolution fails.
```

### Q2 — Sub-agent tool access

```
Generated sub-agents (harness-coder, harness-reviewer) declare a `tools:`
field in their frontmatter that restricts what they can call. Pick the
scope for this install:

  1. Restricted (recommended, default)                  → AGENT_TOOLS = restricted
       Templates' minimal tool list:
         harness-coder    → Read, Write, Edit, Bash, Glob, Grep
         harness-reviewer → Read, Grep, Glob, Bash
       Safest. Sub-agents can't reach MCPs, plugins, web search, Task spawning.
  2. Inherit from parent session                        → AGENT_TOOLS = inherit
       Drop the `tools:` frontmatter field entirely. Sub-agents inherit
       every tool available to the calling Claude Code session — MCPs,
       plugins, custom skills, WebFetch, etc.
       Useful when target project relies on MCPs (e.g., database query,
       internal API access) and review/coding needs them. Broader blast
       radius — reviewer could in principle make external calls.
```

### Q3 — Doctor cadence

```
How often should /espalier-doctor re-scout the codebase for artifact drift?
A doctor scan is activity-gated — an idle repo never triggers one.

  1. Every change                          → DOCTOR_CADENCE = every-change
       Checked at every pipeline Stage 0. Thorough; noisiest.
  2. Weekly (recommended)                  → DOCTOR_CADENCE = weekly
       First pipeline activity after 7 days triggers a scan.
  3. Monthly                               → DOCTOR_CADENCE = monthly
       First pipeline activity after 30 days triggers a scan.
  4. On-demand only                        → DOCTOR_CADENCE = manual
       Never automatic; runs only when you invoke /espalier-doctor.
```

> Why agent identifiers stay `harness-coder` / `harness-reviewer`: these are internal sub-agent names baked into pipeline orchestration. Renaming them mid-pipeline would break any in-flight changes. The plugin name and slash commands rebranded to Espalier in v0.4.0; agent identifiers remain frozen.

Cache the answers in `$MERGE_DECISION`, `$AGENT_TOOLS`, and `$DOCTOR_CADENCE`. Phase 2's Write batch reads `$AGENT_TOOLS` when emitting `espalier/agents/harness-coder.md` and `espalier/agents/harness-reviewer.md`:

- `restricted` → keep the `tools:` frontmatter line from the template verbatim
- `inherit` → omit the `tools:` line entirely (Claude Code interprets missing `tools:` as "inherit from parent")

Pass `$MERGE_DECISION` and `$DOCTOR_CADENCE` to `bootstrap-espalier.sh` in Phase 3 (`--merge-decision=$MERGE_DECISION --doctor-cadence=$DOCTOR_CADENCE`). `$AGENT_TOOLS` only affects Phase 2 LLM writes, no bootstrap flag needed.

---

## Phase 1: Discovery (parallel — single message)

Issue ONE message with up to 10 parallel tool calls:

1. **Bash batch (1.1 + 1.5):** `tldr tree && tldr arch && tldr structure && ls package.json go.mod pyproject.toml Cargo.toml Gemfile pom.xml 2>/dev/null && ls .github/workflows Jenkinsfile Makefile justfile 2>/dev/null && git log --oneline -20`
2. **scout (1.2 — architecture):** layers, dep directions, boundary table
3. **scout (1.3 — coding patterns):** read 5-8 source files; naming/errors/async/types/logging/validation
4. **scout (1.4 — testing):** read 2-3 test files; framework + mock pattern
5. **scout (1.5 — git + CI):** branch strategy, commit conventions, CI checks (build/lint/test commands)
6. **scout (1.6 — unwritten rules):** compare 3+ files of same type per layer; invariants + anti-patterns
7. **oracle (1.7 — best practices):** ctx7 lookup AND web search fired in parallel for the detected stack. Synthesize both results. Divergence notes.
8. **scout (1.8 — data models, wiki):** schemas, migrations, model classes, relationships
9. **scout (1.9 — critical paths, wiki):** entry points, primary flows, modification hotspots
10. **scout (1.10 — external services, wiki):** SDK imports, env vars, services, timeout/retry patterns

**Read first:** `references/discovery-checklist.md` — exact scout prompts to paste.

Each scout returns:
```json
{ "scout_id": "1.N", "status": "ok"|"no_evidence", "summary": "≤200w", "structured": {...}, "evidence_files": [...] }
```

After all scouts return:
- If any returned `status: no_evidence`, batch into ONE follow-up `AskUserQuestion` (per layer/scout: skip / provide files / mark not-applicable). Don't ask N times.
- Merge all `status: ok` outputs into in-context `DISCOVERY` blob (no disk write).

---

## Phase 2: Substitution Writes (parallel — single message)

Issue ONE message with parallel Write calls, all sourcing from `DISCOVERY`:

**Rules** (3 files):
- `espalier/rules/engineering-structure.md`  ← `templates/rules/engineering-structure.md` + DISCOVERY.layers/.naming
- `espalier/rules/coding-standards.md`       ← `templates/rules/coding-standards.md` + DISCOVERY.{naming,error_handling,…}
- `espalier/rules/development-process.md`    ← `templates/rules/development-process.md` + DISCOVERY.{branch_strategy,commit_conventions,ci_checks}

**Orchestrator + per-stack skills** (4 files):
- `espalier/agent.md`                          ← `templates/agent.md` + project_name + DISCOVERY.{lang,framework,layers}
- `espalier/skills/espalier-coding/SKILL.md`   ← `templates/skills/espalier-coding.md` + DISCOVERY
- `espalier/skills/espalier-testing/SKILL.md`  ← `templates/skills/espalier-testing.md` + DISCOVERY.testing
- `espalier/skills/espalier-review/SKILL.md`   ← `templates/skills/espalier-review.md` (swap `{project}` → project_name)

**Sub-agents** (2 files — `tools:` field branches on `$AGENT_TOOLS` from Phase 0 Q2):
- `espalier/agents/harness-coder.md`          ← `templates/agents/harness-coder.md` + project_name. If `$AGENT_TOOLS == restricted` (default): keep `tools: Read, Write, Edit, Bash, Glob, Grep` line. If `$AGENT_TOOLS == inherit`: omit the `tools:` line entirely so the agent inherits from parent session.
- `espalier/agents/harness-reviewer.md`       ← `templates/agents/harness-reviewer.md` + project_name. Same branching: keep `tools: Read, Grep, Glob, Bash` for restricted; omit for inherit.

**Wiki** (4 files — all populated from DISCOVERY scouts 1.2/1.8/1.9/1.10, never stubs):
- `espalier/wiki/architecture.md`             ← DISCOVERY.architecture (scout 1.2)
- `espalier/wiki/data-models.md`              ← DISCOVERY.data_models (scout 1.8)
- `espalier/wiki/critical-paths.md`           ← DISCOVERY.critical_paths (scout 1.9)
- `espalier/wiki/external-services.md`        ← DISCOVERY.external_services (scout 1.10)

**Hooks with placeholders** (2 files):
- `espalier/hooks/pre-push-gate.sh`           ← `hook-templates/pre-push-gate.sh`, swap `{build_command}`/`{lint_command}`/`{test_command}` from DISCOVERY.ci_checks
- `espalier/hooks/check-layer-boundaries.sh`  ← `hook-templates/check-layer-boundaries-${LANG}.sh`, rewrite `case` block from DISCOVERY.layers. If LANG ∉ {ts,py,go}, emit a no-op script (`#!/bin/bash\nexit 0`).

**Then per-layer specs (parallel scout batch + Write batch):**

For each layer in DISCOVERY.layers where a spec is warranted (non-trivial file template, distinct import rules, or layer-specific anti-patterns):

Issue ONE message with N parallel scout calls:
```
scout("Read 2-3 representative files in <layer.dir>. Return JSON:
       { layer_name, template_skeleton: <10-15 line code skeleton>,
         allowed_imports: [...], forbidden_imports: [...], example_file_path }")
```

After all scouts return, issue ONE parallel Write batch for `espalier/skills/espalier-coding/specs/{layer}.md` files. Skip layers flagged trivial (e.g., bare `index.ts` re-export barrel).

Spec template (`templates/skills/espalier-coding-spec.md`) has **no frontmatter** — specs are sub-pages of `espalier-coding`, not registered skills.

---

## Phase 3: Bootstrap (one bash invocation)

Run:
```bash
# ${CLAUDE_SKILL_DIR} is this skill's directory (<plugin>/skills/espalier-init).
# bootstrap-espalier.sh sits at the plugin root (../../scripts/); its
# --plugin-dir wants the dir holding hook-templates/ + templates/ — which is
# this skill's own directory. Resolves the installed plugin in any layout.
bash "${CLAUDE_SKILL_DIR}/../../scripts/bootstrap-espalier.sh" \
  --project-dir=. \
  --plugin-dir="${CLAUDE_SKILL_DIR}" \
  --lang=$LANG \
  --merge-decision=$MERGE_DECISION \
  --doctor-cadence=$DOCTOR_CADENCE
```

Bootstrap runs all 11 internal stages in one shell process:

- **Stages 1-2:** preflight + `mkdir -p` (idempotent — Phase 2 Writes already created some dirs).
- **Stage 3:** `cp` pure-copy templates → `espalier/pipeline.md`, `espalier/skills/{espalier,espalier-fix,espalier-requirements,espalier-grill,espalier-prune,espalier-doctor,espalier-ask}/SKILL.md`. (No conflict with Phase 2 outputs — different files.)
- **Stage 4:** `cp` non-substitution hooks (post-edit-wrapper, post-merge-backlink, lookup-helpers, rebuild-commit-index, drift-detect, drift-helpers, parse-drift-blocks.py) + `chmod +x espalier/hooks/*.sh` (also chmods Phase 2's pre-push-gate.sh + check-layer-boundaries.sh).
- **Stage 5:** safe symlinks `.claude/{rules,skills,agents}/*` → `espalier/...` (refuses if target is regular file; uses portable `abspath`).
- **Stage 6:** heredoc `espalier/changes/_template/pipeline-state.md`.
- **Stage 7:** append `## Espalier` to `CLAUDE.md` (grep-guarded).
- **Stage 8:** merge `.claude/settings.json` hooks (additive by `(matcher, command)` tuple — never clobbers user hooks; atomic temp-file write + backup).
- **Stage 9:** persist `$MERGE_DECISION` to `espalier/.merge-hook-decision` and the Phase 0 Q3 cadence to `espalier/.doctor-cadence` (written once, never auto-rewritten). Install the post-merge dispatcher (`.husky/post-merge` or `.git/hooks/post-merge`) unconditionally — it runs `drift-detect.sh` on every merge and `post-merge-backlink.sh` only when the decision is `installed`.
- **Stage 10:** append `espalier/.commit-index.tsv` + the drift sidecars (`.drift-state.tsv*`, `.drift.log`, `.drift-report.md`, `.doctor-last-run`, `.drift-overrides.log`) to `.gitignore` (newline-guarded).
- **Stage 11:** run 29 validation checks (28 in parallel, #25 serial for its tier table); print sorted output; non-zero exit if any failed.

**Re-run safety:** if `espalier/.merge-hook-decision` exists, bootstrap auto-runs Stage 11 only (idempotent re-run = health check). `--force` overrides.

**Debug flags** (NOT used by normal flow): `--copy-only`, `--wire-only`, `--validate-only`, `--dry-run`.

**Read first (only if debugging):** `references/wiring.md`, `references/validation.md`. Bootstrap subsumes both in normal flow.

---

## Phase 4: Completion message (always print, last thing you say)

After Phase 3's bootstrap exits 0, your final response to the user MUST end with the block below — verbatim, no rewording, no summary above replacing it. If bootstrap exited non-zero, skip this block and surface the failure instead.

```
Espalier installed. Wired N skills, M rules, K agents.

If this saved you time, a ⭐ helps the next person find it:
  https://github.com/Junhanliu-dev/espalier-engineering

Hit a snag or have a suggestion? An issue is the most useful thing you can send:
  https://github.com/Junhanliu-dev/espalier-engineering/issues/new

Either way — thanks for trying it.
```

Fill `N`, `M`, `K` from the counts bootstrap printed (skills wired in Stage 5, rules + agents likewise). If a count is unavailable, drop that clause rather than guess.

**Rule:** this is the ONLY end-of-install ask. No telemetry, no follow-up nag, no second prompt on re-runs — bootstrap's idempotent re-run path (`espalier/.merge-hook-decision` already present → validate-only) skips Phase 4 entirely.

---

## Key Principles

### 1. Discover, Don't Prescribe
Read the code. Extract patterns. Don't impose templates from other projects.

### 2. Quality Gates Must Be Programmatic
```
BAD:  "Check if CI passes"
GOOD: "ci_status == 'success' AND total_tests > 0 AND tests_passed == total_tests"
```
If a constraint can't be machine-verified, the agent WILL drift from it.

### 3. Separate Execution from Judgment
The agent that writes code NEVER reviews its own code. Different `.claude/agents/` with different tool sets (coder has Write/Edit; reviewer has only Read).

### 4. Context Layering
| Layer | Content | Mechanism | When |
|-------|---------|-----------|------|
| Always | rules/ | `.claude/rules/` symlinks | Every session |
| Stage | skills/ | `/espalier-*` invocation | During that phase |
| Delegated | agents/ | Agent tool prompt | Sub-agent scope |
| On-demand | wiki/ | Read tool | Agent queries as needed |

### 5. Every Rule Has a Reason
Don't add rules speculatively. Each rule should either:
- Reflect an observed consistent pattern in the codebase, OR
- Prevent a known failure mode

### 6. Living System
After each real task:
1. Did the agent make a new kind of error? → Add rule/constraint
2. Is a rule blocking valid code? → Remove or refine it
3. Did the pipeline get stuck? → Adjust stage gates or limits

---

## Quick Start (Minimum Viable Espalier)

If the full structure is too much, start with 3 files + wiring:

```bash
# 1. Create minimum espalier
mkdir -p espalier
# Write coding-standards.md (Phase 2 output)
# Write review-skill.md (Phase 3 review output)
# Write ci-gates.md (programmatic conditions)

# 2. Wire it
mkdir -p .claude/rules
ln -sfn "$(pwd)/espalier/coding-standards.md" .claude/rules/espalier-standards.md

# 3. Reference in CLAUDE.md
cat >> CLAUDE.md << 'EOF'

## Espalier (Minimum)
Before writing code: Read espalier/coding-standards.md
Before marking done: Run review checklist in espalier/review-skill.md
Before pushing: Verify conditions in espalier/ci-gates.md
EOF
```

This alone reduces rework cycles from 3-5 rounds to typically 1.
