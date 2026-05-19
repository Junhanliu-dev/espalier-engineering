# Plan: `/harness-engineering` Init Speedup (v0.3.0)

> **Status:** Draft for review. Implementation gated on approval.
> **Owner:** Zayhan
> **Estimated effort:** ~6-7 hours single-sitting, or 2 focused sessions.
> **Target version:** harness-engineering v0.3.0
> **Scope:** Tracks A-E (pure speedup via parallelism + batching; Track F dropped to preserve workflow semantics).

---

## 0. Goals & Non-Goals

### Goals
1. Cut first-run wall clock of `/harness-engineering` on a fresh repo from 20+ min to ~10-15 min (~30-50% reduction; fewer round-trips, parallel scouts, bundled bootstrap). Note: earlier draft of this doc claimed ~5x speedup; real-world runs are more modest because discovery scouts and oracle network calls dominate.
2. Preserve every behavior, output file, gate, and decision from v0.2.1. No semantic change — speedup only via parallelism and bash batching.
3. Move from ~110-140 sequential tool calls to ~5-7 batched turns.
4. Bundle Phase 8 + 10 + 11 (Hooks + Wiring + Validation) into one idempotent shell script.
5. Parallelize Phase 1 (Discovery) via 8 scouts + 1 oracle in a single message (5 core + 3 wiki + 1 best-practices).
6. Parallelize Phase 2-7 (Generation) via one `cp` batch (pure-copy templates) plus one parallel-Write batch (substitution templates).
7. Parallelize Phase 3 layer-spec generation via N concurrent scouts (one per detected layer).
8. Front-load the squash-merge decision into a new Phase 0 — per `[[feedback_prompt_timing]]`. All 6 baseline decision values preserved.
9. Keep skill surface flat — no new skills, all changes inside existing `harness-engineering` SKILL.md + new `scripts/`. Per `[[feedback_no_new_skills]]`.

### Non-Goals
- No change to emitted file contents in target project (templates stay byte-identical).
- No new templates, no new phase semantics, no change to skill folder/name parity rule.
- No change to `/harness-fix` or `/harness-migrate` skills.
- No change to v0.2.0 squash-merge resilience semantics — only WHEN the decision is asked.
- No removal of `references/wiring.md` or `references/validation.md` — they remain as manual fallback / debug reference.
- Backward compatibility shim NOT required: this is install-time behavior, no in-the-field state to preserve.

---

## 1. Baseline Inventory (where the calls come from today)

Counting tool calls a fresh-repo invocation of `/harness-engineering` issues against current SKILL.md:

| Phase | Sub-step | Calls (sequential) |
|-------|----------|--------------------|
| 1.1 Lang detect | `tldr tree`, read manifest | 2-3 |
| 1.2 Architecture | `tldr tree --depth 3`, `tldr arch`, `tldr structure` | 3 |
| 1.3 Coding patterns | Read 5-8 source files | 5-8 |
| 1.4 Testing | `tldr search test` + read 2-3 tests | 3-4 |
| 1.5 CI | Read workflows / Makefile | 2-4 |
| 1.6 Unwritten rules | Compare 3+ same-type files | 3-6 |
| 1.7 Best practices | `ctx7` / web research | 1-2 |
| **Phase 1 total** | | **~25-35** |
| 2 Rules | 3 reads (template) + 3 writes | 6 |
| 3 Skills | 6 skill template reads + writes + N layer specs | 12-16 |
| 4 Orchestrator | 1 read + 1 write | 2 |
| 5 Pipeline | 1 read + 1 write | 2 |
| 6 Wiki | 4 reads + 4 writes | 8 |
| 7 Sub-agents | 2 reads + 2 writes | 4 |
| 8 Hooks | cp boundary + pre-push + post-edit + replacements + chmod | 6-8 |
| 10 Wiring | mkdir×7 + ln×11 + CLAUDE.md append + settings.json + heredoc + chmod×6 + AskUserQuestion×1-2 + husky detect + cp×4 + conditional hook install + .gitignore | 25-30 |
| 11 Validation | 24 separate bash checks | 24 |
| **Grand total** | | **~110-140 sequential** |

### Pure-copy templates (no LLM substitution, ~1050 lines)
- `templates/pipeline.md` (90) — `{slug}`/`{type}` braces are runtime placeholders inside the skill, not generation-time
- `templates/skills/harness-run.md` (237) — runtime placeholders only
- `templates/skills/harness-fix.md` (661) — runtime placeholders only
- `templates/skills/harness-requirements.md` (57) — examples inside braces are skill prose, not generation-time
- `templates/skills/harness-coding-spec.md` (20, skeleton only — body filled per-layer)
- `hook-templates/post-edit-wrapper.sh`, `post-merge-backlink.sh`, `lookup-helpers.sh`, `rebuild-commit-index.sh` — no placeholders, pure copy

### Substitution-needed templates (LLM work required — written via parallel Write batch)
- `templates/rules/engineering-structure.md` (28, ~10 placeholders)
- `templates/rules/coding-standards.md` (34, ~12 placeholders)
- `templates/rules/development-process.md` (13, ~4 placeholders)
- `templates/agent.md` (43, ~5 placeholders)
- `templates/agents/harness-coder.md` (61, 1 placeholder: `{project_name}`)
- `templates/agents/harness-reviewer.md` (71, 1 placeholder)
- `templates/skills/harness-coding.md` (26, several)
- `templates/skills/harness-testing.md` (34, several)
- `templates/skills/harness-review.md` (41, has `{project}` placeholder on line 19 — moved here from pure-copy)
- `references/wiki-templates.md` × 4 wiki files (project-specific synthesis — fed by dedicated wiki scouts in §4.1)
- Per-layer specs (N×~20 lines, filled from real files)
- `hook-templates/pre-push-gate.sh` (3 placeholders: `{build_command}`, `{lint_command}`, `{test_command}` — needs DISCOVERY.ci_checks)
- `hook-templates/check-layer-boundaries-{lang}.sh` (case-pattern block — needs DISCOVERY.layers)

---

## 2. Pre-flight (do once, before touching any phase)

1. **Branch off main:**
   ```bash
   git checkout -b feat/init-speedup
   ```
2. **Capture baseline:**
   ```bash
   git rev-parse HEAD > /tmp/init-speedup-baseline.sha
   ```
3. **Bump version stub** in `.claude-plugin/plugin.json` to `0.3.0-dev`.
4. **Snapshot current SKILL.md** as `SKILL.v0.2.md` (in skill dir, gitignored) for diff reference during edits.

---

## 3. Track A — Bootstrap Script (`scripts/bootstrap-harness.sh`)

**Goal:** collapse Phase 8 + 10 + 11 + pure-copy template emission into one idempotent script.

### 3.1 Interface

```bash
bootstrap-harness.sh \
  --project-dir=<path>           # default: $PWD
  --plugin-dir=<path>            # auto-detect like migrate-v0.1-to-v0.2.sh
  --lang=<ts|py|go|unsupported>  # boundary-check variant; "unsupported" emits no-op hook
  --merge-decision=<val>         # one of: not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later
  [--dry-run]                    # print actions without executing
  [--yes]                        # non-interactive (used by tests + CI smoke)
  [--force]                      # override re-run safety check on existing harness/
  # Debug-only flags (not used by normal /harness-engineering flow per R1):
  [--copy-only]                  # only Stages 1-4 (mkdir + pure-copy + non-substitution hooks)
  [--wire-only]                  # only Stages 5-11 (symlinks + wiring + validation)
  [--validate-only]              # run only Stage 11 (parallel 24-check validation)
```

**Default behavior (R1):** single invocation runs all 11 stages. LLM writes substitution files BEFORE invoking bootstrap; bootstrap's mkdir-p + cp are idempotent against pre-existing parent dirs from LLM Write tool.

Debug flags (`--copy-only` / `--wire-only` / `--validate-only`) retained as fallbacks for mid-flow diagnosis if main path breaks. Not used by SKILL.md's normal Phase 2-7 instruction.

### 3.2 Stages inside script (mirror `migrate-v0.1-to-v0.2.sh` style)

```
Stage 1: Preflight + re-run detection
  - Check $PROJECT_DIR exists and is writable
  - Check $PLUGIN_DIR/hook-templates/ exists
  - Detect existing install state:
      * harness/ missing → proceed (fresh install)
      * harness/ exists + harness/.merge-hook-decision present →
          run Stage 11 (validation) only, exit clean (idempotent re-run)
      * harness/ exists + decision file missing →
          likely v0.1 install. Exit 1, suggest `/harness-migrate`.
      * harness/ exists + --force flag → proceed regardless

Stage 2: Make all directories
  mkdir -p harness/{rules,skills/{harness-coding/specs,harness-review,harness-testing,harness-requirements,harness-run,harness-fix},agents,hooks,wiki,changes/{_template,feat,fix,refactor}}
  mkdir -p .claude/{rules,skills,agents}

Stage 3: Pure-copy templates
  cp $PLUGIN_DIR/templates/pipeline.md                       harness/pipeline.md
  cp $PLUGIN_DIR/templates/skills/harness-run.md             harness/skills/harness-run/SKILL.md
  cp $PLUGIN_DIR/templates/skills/harness-fix.md             harness/skills/harness-fix/SKILL.md
  cp $PLUGIN_DIR/templates/skills/harness-requirements.md    harness/skills/harness-requirements/SKILL.md
  # NOTE: harness-review.md is NOT pure-copy (has {project} placeholder) — LLM Write batch handles it.
  # NOTE: all substitution-needed templates are NOT copied here — LLM writes them.

Stage 4: Hook scripts (copy non-substitution hooks + chmod ALL hooks per R10)
  cp $PLUGIN_DIR/hook-templates/post-edit-wrapper.sh        harness/hooks/post-edit-wrapper.sh
  cp $PLUGIN_DIR/hook-templates/post-merge-backlink.sh      harness/hooks/post-merge-backlink.sh
  cp $PLUGIN_DIR/hook-templates/lookup-helpers.sh           harness/hooks/lookup-helpers.sh
  cp $PLUGIN_DIR/hook-templates/rebuild-commit-index.sh     harness/hooks/rebuild-commit-index.sh
  # NOTE: pre-push-gate.sh and check-layer-boundaries-{lang}.sh are NOT copied here. LLM Write batch
  #       (Phase 2-7 Step 1) wrote them with DISCOVERY substitutions BEFORE this bootstrap fired.
  #
  # R10 — chmod every executable in harness/hooks/ (catches LLM-written hooks too).
  # lookup-helpers.sh is sourced, but `chmod +x` on it is harmless.
  for hook in harness/hooks/*.sh; do
    [ -f "$hook" ] && chmod +x "$hook"
  done

Stage 5: Symlinks into .claude/ (with safe-overwrite pre-flight + R-extra portable abspath)
  # R-extra: portable abspath (no realpath dependency — macOS lacks it by default)
  abspath() {
    if [ -d "$1" ]; then
      ( cd "$1" && pwd )
    else
      ( cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")" )
    fi
  }
  safe_ln() {
    src="$1"; dst="$2"
    # Refuse if dst exists as regular file (not symlink) AND doesn't match our src
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "ERROR: $dst exists as regular file (not symlink). Refusing to overwrite user content." >&2
      echo "Move/remove it manually, then re-run." >&2
      exit 1
    fi
    ln -sf "$src" "$dst"
  }
  safe_ln "$(abspath harness/rules/engineering-structure.md)" .claude/rules/harness-structure.md
  safe_ln "$(abspath harness/rules/coding-standards.md)"      .claude/rules/harness-standards.md
  safe_ln "$(abspath harness/rules/development-process.md)"   .claude/rules/harness-process.md
  for s in harness-coding harness-review harness-testing harness-requirements harness-run harness-fix; do
    safe_ln "$(abspath harness/skills/$s)" ".claude/skills/$s"
  done
  safe_ln "$(abspath harness/agents/harness-coder.md)"    .claude/agents/harness-coder.md
  safe_ln "$(abspath harness/agents/harness-reviewer.md)" .claude/agents/harness-reviewer.md

Stage 6: pipeline-state.md template (heredoc)
  cat > harness/changes/_template/pipeline-state.md << 'EOF'
  ... existing template content ...
  EOF

Stage 7: CLAUDE.md append (idempotent)
  if ! grep -q "## Harness Engineering" CLAUDE.md 2>/dev/null; then
    cat >> CLAUDE.md << 'EOF'
    ... existing harness section ...
    EOF
  fi

Stage 8: .claude/settings.json merge or write
  See Appendix A for full merge algorithm.
  Summary: if missing, write fresh; if present, additively merge hooks
  entries by (matcher + command) tuple — never override user's existing
  hooks, only add ours if not already present. Atomic temp-file write.

Stage 9: Squash-merge decision (use --merge-decision flag from Phase 0)
  - Validate $MERGE_DECISION is one of: not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later
  - Write harness/.merge-hook-decision = $MERGE_DECISION
  - If MERGE_DECISION = installed: install post-merge hook into .husky/ or .git/hooks/
  - Mirror Step 5 in references/wiring.md §10.8 exactly.

Stage 10: .gitignore append (idempotent, guard newline)
  - Append "harness/.commit-index.tsv" if not present
  - Re-use the guard from migrate-v0.1-to-v0.2.sh §6

Stage 11: Validation (R6 — parallelized)
  - Gating:
      * --validate-only       → run Stage 11 only
      * --copy-only           → skip Stage 11
      * --wire-only           → run Stage 11
      * default (full run)    → run Stage 11
  - Run all 24 checks from references/validation.md in PARALLEL via background jobs:
      tmpdir=$(mktemp -d)
      run_check() {
        local n=$1 name=$2 cmd=$3
        if eval "$cmd" >/dev/null 2>&1; then
          echo "[$n/24] ✓ $name" > "$tmpdir/$(printf '%02d' $n)"
        else
          echo "[$n/24] ✗ $name: $(eval $cmd 2>&1 | head -1)" > "$tmpdir/$(printf '%02d' $n)"
        fi
      }
      run_check 1 "rules-load"    "ls .claude/rules/harness-*.md >/dev/null" &
      run_check 2 "skills-load"   "ls -d .claude/skills/harness-* >/dev/null" &
      # ... 22 more &
      wait
      cat "$tmpdir"/* | sort  # numeric-sorted, deterministic output order
      rm -rf "$tmpdir"
  - All 24 checks run regardless of individual failures (parallelism guarantees this).
  - Exit non-zero at end if any check failed (track via tmpfile counts).
```

### 3.2.1 Flag → stages matrix

| Flag | Stages run | Use case |
|------|-----------|----------|
| (none, default) | 1-11 (full) | **Normal /harness-engineering flow (R1)** — single invocation after LLM Write batch completes |
| `--copy-only` | 1, 2, 3, 4 | Debug — partial install for diagnosis |
| `--wire-only` | 1 (preflight only — no re-run abort), 5-11 | Debug — re-wire after manual file edits |
| `--validate-only` | 1 (preflight only), 11 | Debug — re-run health check |

Normal `/harness-engineering` flow (per R1): LLM writes substitution files FIRST (parallel Write batch creates parent dirs implicitly via Write tool), THEN bootstrap fires ONCE with no flags. Stage 2 mkdir-p is idempotent against pre-existing dirs; Stage 3 cps non-conflicting files; Stage 4 chmods every `*.sh` in `harness/hooks/` (including LLM-written ones); Stage 5 symlinks against all-present files. End state byte-identical to two-invocation approach.

### 3.3 Idempotency rules
- All `mkdir` use `-p`.
- All `ln -sf` overwrite safely.
- `cp` overwrites pure-copy templates (they're under harness/ — user shouldn't edit).
  - EXCEPTION: if a substitution-needed file already exists, do NOT cp. This script never touches those.
- `CLAUDE.md` append uses grep-guard.
- `.gitignore` append uses `grep -qxF`.
- `.claude/settings.json` merge: read existing, deep-merge hooks array, write atomically via temp file.
- Post-merge hook install: check `grep HARNESS_BACKLINK_HOOK` before appending.

### 3.4 Smoke tests
Drop a `scripts/test-bootstrap.sh` that:
1. Creates `/tmp/harness-smoke-{ts,py,go}` empty repos + `git init`
2. Runs `bootstrap-harness.sh --dry-run --lang=<lang>` and asserts dry-run output count
3. Writes minimal placeholders for substitution files (simulates LLM Write batch)
4. Runs `bootstrap-harness.sh --lang=<lang> --yes --merge-decision=ask-later` (R1 — single full invocation)
5. Asserts all 24 parallel validation checks pass (R6 — Stage 11 output sorted deterministically)
6. Asserts `chmod +x` applied to all hooks including LLM-written ones (R10)
7. Asserts symlinks created with absolute paths (R-extra — verify `readlink` resolves to expected `/abs/path/...`)
8. Re-runs full bootstrap on populated repo → detects complete install via `.merge-hook-decision` → runs Stage 11 only, exit 0
9. Tests `--force` overrides re-run detection
10. Tests `--copy-only` debug flag still works (Stages 1-4 only)
11. Tests `--wire-only` debug flag still works (Stages 5-11 only)
12. Tests safe-symlink: pre-create regular file at `.claude/rules/harness-structure.md` → bootstrap exits 1 with clear error
13. Tests settings.json merge: pre-populate with user hook → assert user hook survives + harness hooks added
14. Tests portable `abspath`: run on a path with no `realpath` binary (mock PATH) → still produces correct symlink targets
15. Cleans up

### 3.5 Files added/modified
| File | Change |
|------|--------|
| `scripts/bootstrap-harness.sh` | NEW |
| `scripts/test-bootstrap.sh` | NEW |
| `.claude-plugin/plugin.json` | version bump |

---

## 4. Track B — Parallel Discovery (Phase 1)

**Goal:** Run Phase 1 sub-phases concurrently as scout/oracle agents in a single message.

### 4.1 New Phase 1 instruction block (replaces current Phase 1)

```markdown
## Phase 1: Discovery (Parallel)

Issue ONE message with up to 10 tool calls in parallel:

1. **Bash batch (1.1+1.5):** tldr tree, tldr arch, tldr structure, ls manifests, ls CI configs, git log.
   Combine into one bash call separated by `&&` or `;`.

2. **scout (1.2 — architecture):** Read tldr output context, identify layers, dep directions.
   Return: { layers: [{name, dir, deps}], boundary_table: [...] }

3. **scout (1.3 — coding patterns):** Read 5-8 representative source files.
   Return: { naming: {files, fns, types, consts}, error_handling, async_pattern, type_usage, logging, validation }

4. **scout (1.4 — testing):** Read 2-3 test files.
   Return: { framework, assertion_style, mock_pattern, file_template }

5. **scout (1.5 — git + CI):** Read git log, CI configs, Makefile/justfile.
   Return: { branch_strategy, commit_conventions, ci_checks: {build, lint, test} }

6. **scout (1.6 — unwritten rules):** Compare 3+ files of same type per layer.
   Return: { invariants: [...], anti_patterns: [...] }

7. **oracle (1.7 — best practices):** ctx7 lookup for detected stack.
   Return divergence notes only. Always runs to preserve baseline workflow.

8. **scout (1.8 — data models, wiki):** Find schema files (Prisma/SQLAlchemy/Mongoose/JPA/Gorm/etc.), migration dirs, model classes.
   Return: { entities: [{name, file, fields_sample}], schema_location, migration_pattern, relationships: [...] }

9. **scout (1.9 — critical paths, wiki):** Trace entry points → key flows. Find request handlers / CLI entries / cron jobs / main functions.
   Return: { entry_points: [...], primary_flows: [{name, files_touched, layers}], modification_hotspots: [...] }

10. **scout (1.10 — external services, wiki):** Grep for external SDK imports (stripe, aws, postgres, redis, kafka, etc.), env vars, config files.
    Return: { services: [{name, purpose, config_location}], env_vars: [...], timeout_retry_patterns: [...] }
```

Scouts 8/9/10 feed Phase 6 wiki files (data-models, critical-paths, external-services). Scout 2 covers architecture.md. All 4 wiki files get populated content — never stubs.

### 4.2 Scout output schema (enforce)
Each scout returns exactly this shape (JSON in their text response):
```json
{
  "scout_id": "1.3",
  "status": "ok" | "no_evidence",
  "summary": "≤200 word prose summary",
  "structured": { ... per-scout schema above ... },
  "evidence_files": ["src/x.ts", "src/y.ts", ...]
}
```

`status: no_evidence` means scout found nothing to report (e.g., no test files exist, no external services detected). Orchestrator collects ALL `no_evidence` scouts across the parallel batch and surfaces them in ONE follow-up `AskUserQuestion` after the batch completes — never blocks per-scout. For each no-evidence scout, user picks: (a) skip (write minimal stub), (b) provide hints/file paths, (c) mark not-applicable (note in relevant rule file).

Schema enforcement lives in the scout-prompt block in `references/discovery-checklist.md`. LLM merges all `status: ok` scouts into one `DISCOVERY` context blob (in-memory, no file write needed). Same batching rule applies to Track D layer-spec scouts (§6.3).

### 4.3 Files added/modified
| File | Change |
|------|--------|
| `skills/harness-engineering/SKILL.md` | Rewrite Phase 1 (~30 lines) |
| `skills/harness-engineering/references/discovery-checklist.md` | Add Section "Parallel Execution Recipe" with copy-pasteable scout prompts |

---

## 5. Track C — Parallel Template Generation (Phase 2-7)

**Goal:** Collapse Phases 2-7 into:
1. One bash call (`bootstrap-harness.sh --copy-only`) for pure copies.
2. One parallel-Write batch for substitution-needed files.

### 5.1 New Phase 2-7 instruction block (R1 — single bootstrap invocation)

```markdown
## Phase 2-7: Generation (One parallel write batch + One bash invocation)

Per R1, the LLM writes substitution files FIRST, then bootstrap runs ONCE with no flags
(performs all 11 stages). Order matters: LLM Write tool auto-creates parent dirs, so
bootstrap's `mkdir -p` finds them existing (idempotent). Bootstrap's `cp` of pure
templates doesn't conflict with LLM-written substitution files (different filenames).

### Step 1: Parallel Write batch (LLM writes substitution files)
Issue ONE message with parallel Write calls, all reading from the DISCOVERY blob:

Rules:
- harness/rules/engineering-structure.md   (templates/rules/engineering-structure.md + DISCOVERY.layers/.naming)
- harness/rules/coding-standards.md        (templates/rules/coding-standards.md + DISCOVERY.{naming,error_handling,...})
- harness/rules/development-process.md     (templates/rules/development-process.md + DISCOVERY.{branch_strategy,commit_conventions,ci_checks})

Orchestrator + skills:
- harness/agent.md                          (templates/agent.md + project_name + DISCOVERY.{lang,framework,layers})
- harness/skills/harness-coding/SKILL.md    (templates/skills/harness-coding.md + DISCOVERY)
- harness/skills/harness-testing/SKILL.md   (templates/skills/harness-testing.md + DISCOVERY.testing)
- harness/skills/harness-review/SKILL.md    (templates/skills/harness-review.md, swap {project} → project_name)

Sub-agents:
- harness/agents/harness-coder.md           (templates/agents/harness-coder.md + project_name)
- harness/agents/harness-reviewer.md        (templates/agents/harness-reviewer.md + project_name)

Wiki (all populated from DISCOVERY scouts 1.2/1.8/1.9/1.10 — never stubs):
- harness/wiki/architecture.md              (DISCOVERY.architecture, scout 1.2)
- harness/wiki/data-models.md               (DISCOVERY.data_models, scout 1.8)
- harness/wiki/critical-paths.md            (DISCOVERY.critical_paths, scout 1.9)
- harness/wiki/external-services.md         (DISCOVERY.external_services, scout 1.10)

Hooks (need DISCOVERY substitution — NOT pure copies):
- harness/hooks/pre-push-gate.sh            (templates/hook-templates/pre-push-gate.sh, swap {build_command}/{lint_command}/{test_command} from DISCOVERY.ci_checks)
- harness/hooks/check-layer-boundaries.sh   (templates/hook-templates/check-layer-boundaries-${LANG}.sh, rewrite case block from DISCOVERY.layers)

### Step 2: Layer specs (parallel scout batch + Write batch)
Per Track D / §6: spawn N scouts for layer specs in parallel, then Write all specs.
Detail in §6.

### Step 3: Single bootstrap invocation (R1)
Run: `bash $PLUGIN_DIR/scripts/bootstrap-harness.sh --project-dir=. --plugin-dir=$PLUGIN_DIR --lang=$LANG --merge-decision=$MERGE_DECISION`

Bootstrap runs all 11 Stages:
- Stages 1-3: preflight + mkdir-p (idempotent on already-existing dirs from LLM Writes) + cp pure-copy templates (pipeline.md, harness-run/harness-fix/harness-requirements SKILL.md, no conflict with LLM-written substitution files)
- Stage 4: cp non-substitution hooks + chmod ALL `harness/hooks/*.sh` (R10 — catches LLM-written pre-push-gate.sh and check-layer-boundaries.sh too)
- Stage 5: symlinks (all target files now exist on disk)
- Stages 6-10: heredocs, CLAUDE.md append, settings.json merge, decision write, .gitignore
- Stage 11: 24 parallel validation checks (R6)

No separate LLM chmod step needed (R10 folds it into Stage 4).
No two-invocation gymnastics (R1).
```

### 5.2 Pre-read templates step (optional optimization)
Before Step 2, issue ONE parallel Read batch for the 8 substitution templates. This eliminates "Read template → Write" round-trips.

Saves another ~8 Reads → 1 turn.

### 5.3 Files added/modified
| File | Change |
|------|--------|
| `skills/harness-engineering/SKILL.md` | Rewrite Phases 2-7 (~40 lines collapsed) |

---

## 6. Track D — Parallel Layer Specs (Phase 3, sub-step)

**Goal:** N layer specs in parallel (N typically 2-5).

### 6.1 New instruction (inside Phase 3)

```markdown
### Per-Layer Specs (parallel)

After DISCOVERY produced DISCOVERY.layers = [layer_a, layer_b, ...]:

Issue ONE message with N parallel scout calls, one per layer:

  scout("Read 2-3 files in <layer.dir>. Return:
        { layer_name, template_skeleton (10-15 line code skeleton from common patterns),
          allowed_imports: [...], forbidden_imports: [...],
          example_file_path }")

After all scouts return, issue ONE parallel Write batch:

  harness/skills/harness-coding/specs/{layer_a}.md
  harness/skills/harness-coding/specs/{layer_b}.md
  ...
```

### 6.2 Trivial-layer skip (baseline behavior preserved)
If DISCOVERY reports a layer has only trivial wrapper files (e.g., `index.ts` re-exports), skip spec generation for that layer. Main `harness-coding/SKILL.md` is sufficient. This is NOT a new optimization — it's already documented in current SKILL.md §3 "Create a spec for a layer if any of these are true". Plan preserves this rule verbatim.

### 6.3 Scout failure handling (per §13.5)
If a per-layer scout returns "no representative files found":

1. Collect ALL such layers across the parallel batch (don't ask N times).
2. Issue ONE `AskUserQuestion` listing each failed layer:
   ```
   Scout couldn't find files for: {layer_a}, {layer_b}, ...

   For each, pick:
     - Skip (no spec, use main harness-coding)
     - Provide file paths (paste 1-2 representative files)
     - Mark trivial (record in engineering-structure.md, no spec)
   ```
3. Apply user choices, then resume Write batch.

Same handling pattern applies to Phase 1 discovery scouts (§4) — collect failures into a single follow-up prompt rather than blocking per-scout.

### 6.3 Files added/modified
| File | Change |
|------|--------|
| `skills/harness-engineering/SKILL.md` | Update Phase 3 §"per-layer spec" with parallel recipe |

---

## 7. Track E — Front-loaded Phase 0 Decisions

**Goal:** Ask config questions at start, not mid-pipeline. Per memory `[[feedback_prompt_timing]]`.

### 7.1 New Phase 0 block

Insert before current Phase 1. Q1 preserves all 6 decision values from current `references/wiring.md` §10.8. Q2 is a new opt-in that controls the `tools:` frontmatter of generated sub-agents.

```markdown
## Phase 0: Setup Decisions (Front-loaded)

Issue ONE `AskUserQuestion` in multi-question form (2 questions).

Q1 (Header: "Merge strategy"):
  How does this repo merge PRs? Choice affects how /harness-fix links bug fixes to causing commits.

  1. Rebase-merge / true merge-commit       → MERGE_DECISION = not-needed
       SHAs preserved; no special handling needed.
  2. Squash + install post-merge hook (recommended) → MERGE_DECISION = installed
       Hook records original→squashed SHA so fix lane finds origin via O(1) lookup.
  3. Squash + allow fuzzy match at fix-time → MERGE_DECISION = fuzzy-allowed
       No hook. Fix lane falls back to file-overlap heuristic. Less safe.
  4. Squash + skip linking when SHA misses (safest) → MERGE_DECISION = skip-only
       No hook, no fuzzy. Fix proceeds without causal link if SHA can't be resolved.
  5. Squash + never ask again, always skip  → MERGE_DECISION = never-ask
       Same as skip-only but suppresses any future "what should I do" prompts.
  6. Decide later                           → MERGE_DECISION = ask-later
       Defer. Fix lane will prompt the first time SHA resolution fails.

Q2 (Header: "Sub-agent tool access"):
  Generated sub-agents declare a `tools:` field in their frontmatter that
  restricts what they can call. Pick the scope for this install:

  1. Restricted (recommended, default)      → AGENT_TOOLS = restricted
       Templates' minimal tool list — coder gets Read/Write/Edit/Bash/Glob/Grep;
       reviewer gets Read/Grep/Glob/Bash. Sub-agents cannot reach MCPs,
       plugins, web search, or spawn other agents. Safest.
  2. Inherit from parent session            → AGENT_TOOLS = inherit
       Drop the `tools:` frontmatter field entirely. Sub-agents inherit
       every tool the calling Claude Code session has — MCPs, plugins,
       custom skills, WebFetch. Useful for projects that depend on MCPs
       (e.g., DB query, internal API tools). Broader blast radius.

Cache decisions in shell vars $MERGE_DECISION + $AGENT_TOOLS.
Pass $MERGE_DECISION to bootstrap-harness.sh later via --merge-decision=$MERGE_DECISION.
$AGENT_TOOLS only affects Phase 2 LLM writes (no bootstrap flag).
```

### 7.2 Rationale for the 2 Phase 0 questions
Memory `[[feedback_prompt_timing]]` warns against decision fatigue. We cap Phase 0 at 2 questions that are BOTH front-loaded by intent:

- **Q1 (merge strategy)**: Already asked at install time in baseline v0.2.x (Phase 10). Moving from Phase 10 to Phase 0 is pure timing relocation — same question, same 6 options.
- **Q2 (sub-agent tool access)**: New in v0.3.0. Surfaces a real config knob that was previously hardcoded. Default = "restricted" preserves v0.2.x behavior (template tools list verbatim). User opts in to "inherit" only when they want MCP/plugin access from sub-agents.

All other config (skill folder naming, hook timeouts, web research, etc.) stays defaulted.

### 7.3 Phase 2 Write batch substitution rule for `tools:` field
When emitting `harness/agents/harness-coder.md` and `harness/agents/harness-reviewer.md`, branch on `$AGENT_TOOLS`:

- `restricted` (default) → preserve the `tools: Read, ...` line from the template verbatim.
- `inherit` → omit the `tools:` line entirely. Claude Code's agent loader interprets a missing `tools:` field as "inherit from parent session".

### 7.4 Files added/modified
| File | Change |
|------|--------|
| `skills/harness-engineering/SKILL.md` | Insert Phase 0 block (~50 lines, 2 questions) |
| `references/wiring.md` | Add note: "Phase 10 squash-merge prompt is now Phase 0. This section retained for reference." |

---

## 8. Track F — DROPPED

Originally proposed small-repo skip-list (`<50 files` → skip per-layer specs + 2 wiki files).

**Removed during workflow-preservation audit.** Track F violates the "speedup only via parallelism + batching" constraint by skipping content the baseline would produce. Even with user notification + opt-out, it changes baseline output.

Trivial-per-layer skip (§6.2) is unrelated and preserved — it's baseline behavior from current SKILL.md §3, not a new optimization.

---

## 9. Updated SKILL.md Structure (target)

After all tracks applied, SKILL.md layout:

```
# Harness Engineering

## When to Use
... (unchanged) ...

## Philosophy
... (unchanged) ...

## File Layout of This Skill
... (unchanged) ...

## Output Structure in Target Project
... (unchanged) ...

## Skill Naming Invariant
... (unchanged) ...

## Phase Dependency Note
... (rewrite to reflect parallel batches) ...

## Phase 0: Setup Decisions (NEW)
Ask 1 question via AskUserQuestion (6 squash-merge options). Cache $MERGE_DECISION.

## Phase 1: Discovery (Parallel)
One message, up to 10 parallel calls (5 core scouts + 3 wiki scouts + 1 oracle + 1 bash batch).
Synthesize results into DISCOVERY blob (in-context, no disk write).
Batch any `no_evidence` scouts into ONE follow-up AskUserQuestion.
Reference: references/discovery-checklist.md for scout prompts.

## Phase 2-7: Generation (R1 — LLM writes first, then ONE bootstrap call)
Step 1: Parallel Read batch for substitution templates
Step 2: Parallel Write batch (rules + agent + harness-coding/testing/review SKILL.md + sub-agents + 4 wiki files + pre-push-gate.sh + check-layer-boundaries.sh)
Step 3: Parallel scout batch for per-layer specs (Track D), then Write batch for specs

## Phase 8+10+11: Wiring + Validation (ONE bootstrap invocation per R1)
Run: bash bootstrap-harness.sh --merge-decision=$MERGE_DECISION
Single invocation runs all 11 Stages (preflight + mkdir + cp + chmod-glob + symlinks + heredocs + CLAUDE.md + settings.json + decision + .gitignore + parallel validation).

Script handles symlinks, CLAUDE.md, settings.json, hooks, validation.
Reference: references/wiring.md + references/validation.md for debug only.

## Key Principles
... (unchanged) ...

## Quick Start (Minimum Viable Harness)
... (unchanged) ...
```

**Net diff:** SKILL.md drops from 318 lines to ~200 lines.

---

## 10. Test Plan

### 10.1 Unit tests
- `scripts/test-bootstrap.sh` runs on `/tmp/harness-smoke-{ts,py,go}` empty repos. All 24 validation checks pass.
- Idempotency test: re-run bootstrap twice, no errors, no diff in output dir.
- `--dry-run` test: assert no actual changes made.

### 10.2 Integration tests (real repos)
Run `/harness-engineering` against three reference targets and assert:
- Total elapsed wall-clock < 3 min (medium repo, ~200 files).
- All Phase 11 validation checks pass.
- Generated files byte-identical to v0.2.1 output (modulo expected DISCOVERY-driven substitutions).

Targets:
- A small TypeScript repo (~50 files)
- A medium Python/FastAPI repo (~150 files)
- A larger Go service (~400 files)

Compare against v0.2.1 baseline run on same repos (capture pre-merge artifacts).

### 10.3 Regression test
- Verify `/harness-fix` and `/harness-run` still work end-to-end against a freshly-bootstrapped repo.
- Verify `/harness-migrate` v0.1 → v0.2 still works (orthogonal but adjacent code).

### 10.4 Failure injection
- Bootstrap with missing PLUGIN_DIR: should exit 1 with clear message.
- Bootstrap with read-only PROJECT_DIR: should fail at Stage 2 with clear message.
- Discovery scout returns malformed JSON: LLM re-prompts up to 1 retry per scout, then surfaces parse error to user.
- Discovery scout returns `status: no_evidence`: orchestrator batches with other no-evidence scouts into one `AskUserQuestion` (per §4.2).
- Phase 1 oracle (best-practices, ctx7) times out >60s: orchestrator drops it, continues without best-practices notes. Logs to validation output.
- Pre-existing regular file at symlink target (e.g., user already has `.claude/rules/harness-structure.md`): bootstrap Stage 5 exits 1 with manual-removal instructions.
- Pre-existing `.claude/settings.json` with conflicting matcher patterns: bootstrap merges additively per Appendix A; verify user's hooks survive.
- Re-run on already-bootstrapped repo (decision file present): bootstrap runs Stage 11 only, exits 0.
- Re-run on v0.1 install (harness/ exists but no decision file): bootstrap exits 1 with `/harness-migrate` suggestion.
- Unsupported `--lang` (e.g., `rust`, `java`): bootstrap emits no-op `check-layer-boundaries.sh` (immediate `exit 0`) and logs warning. Validation Check 6 (hooks executable) still passes since no-op script is valid bash.

---

## 11. Rollout

### 11.1 Plan order
1. Write `scripts/bootstrap-harness.sh` (Track A) — mirror migrate script style. Include all 11 stages + flag matrix + safe-symlink + settings.json merge per Appendix A.
2. Write `scripts/test-bootstrap.sh` smoke tests (fresh + re-run + --dry-run + --force).
3. Update SKILL.md Phases 0/1/2-7/8+10+11 (Tracks B, C, E).
4. Update `references/discovery-checklist.md` with scout prompts for all 10 parallel calls (Track B).
5. Add parallel-spec instruction in Phase 3 (Track D).
6. Run integration tests on 3 reference repos (TS, Python, Go).
7. Bump version in `.claude-plugin/plugin.json` to 0.3.0.
8. Update CHANGELOG.md.

### 11.2 Migration concern
None for in-the-field installs — bootstrap script is install-time only. v0.2.0 installs keep working untouched.

### 11.3 Documentation update
- `references/wiring.md`: add note at top "Phase 10 is now bundled in `scripts/bootstrap-harness.sh`. Manual steps below remain as debug fallback."
- `references/validation.md`: add note at top "Validation now runs via `bootstrap-harness.sh --validate-only`. Per-check list below for manual debug."

### 11.4 Version bump
`.claude-plugin/plugin.json`: `0.2.1` → `0.3.0` (minor — new behavior, backward-compatible templates).

---

## 12. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|------------|--------|------------|
| 1 | Bootstrap script idempotency bug corrupts existing harness/ | Low | High | Mirror migrate-v0.1 idempotency (proven). Add `--force` guard. Smoke test re-runs. |
| 2 | Parallel scouts return conflicting layer detection | Medium | Medium | Each scout has narrow scope, structured output. LLM merge step is deterministic (no judgment). |
| 3 | Web research scout times out, blocks Phase 1 | Low | Medium | Scout runs last in parallel batch so others finish first. ctx7 has internal timeout (~30s). If scout exceeds 60s, orchestrator drops it and continues without best-practices notes. |
| 4 | Phase 0 decision fatigue annoys users | Very Low | Low | Only 1 question (squash-merge). Memory `[[feedback_prompt_timing]]` confirms this is preferred. Baseline already asks the same question — just relocated. |
| 5 | Bootstrap script `cp` overwrites a user-customized template | Low | High | Pure-copy targets are skill plumbing files (`harness-run`, `harness-fix`, `harness-requirements` SKILL.md, pipeline.md) — users shouldn't edit these. Substitution-needed files (rules, agent.md, harness-review SKILL.md, hooks with placeholders) are NEVER touched by bootstrap. |
| 6 | Validation script exits early on first failure, hides later issues | Medium | Low | Run all 24 checks regardless of individual failures, exit non-zero at end if any failed. Print all results. |
| 7 | Parallel writes hit Claude Code's file-write rate limit | Low | Low | Currently 4-12 parallel writes per turn is well under any limit. |
| 8 | Per-layer scouts return inconsistent skeleton style | Medium | Low | Scout prompt enforces format: "exactly 10-15 line code skeleton". LLM normalizes on Write. |
| 9 | `.claude/settings.json` merge corrupts existing user hooks | Medium | High | Algorithm in Appendix A: idempotent additive merge by (matcher, command) tuple. Atomic temp-file write. Test against repos with pre-existing settings.json. |
| 10 | `realpath` not portable to all systems | Resolved by R-extra | — | `abspath()` helper uses `cd && pwd` — no `realpath` binary required. See Stage 5. |
| 11 | Symlinks break on Windows | Medium | Medium | Out of scope for this version — harness-engineering already requires Unix-like. Document. |
| 12 | `safe_ln` blocks fresh install when user has unrelated `.claude/rules/` content | Low | Medium | Refuses only on name-collision with regular file (not symlink). Most users don't have `harness-*.md` regular files in `.claude/rules/`. Error message instructs manual removal + re-run. |
| 13 | Re-run on broken/partial install | Medium | Medium | Stage 1 re-run detection: if decision file missing, suggest `/harness-migrate`. `--force` flag available as escape hatch (logs warning). |

---

## 13. Open Questions (resolve before implementation)

1. **Q:** Should the bootstrap script live in `scripts/` (current pattern) or `skills/harness-engineering/scripts/`?
   **Resolved:** `scripts/bootstrap-harness.sh`. Matches `migrate-v0.1-to-v0.2.sh`. Reuses plugin path detection logic from migrate skill.

2. **Q:** Should DISCOVERY blob be written to disk (e.g., `harness/.discovery.json`) or kept in-context only?
   **Resolved:** In-context only. No disk write, no readback complexity. Resume mid-init not supported in v0.3.0 — fresh-repo init is single-session by design.

3. **Q:** When --skip-web=yes, should we still inject ecosystem best-practices from a baked-in static reference?
   **Resolved (revised):** The skip-web opt-out was dropped during the workflow-preservation audit. Phase 1.7 (best-practices oracle) now always runs, preserving baseline behavior. It runs in the parallel batch so latency cost is hidden behind other scouts. If the oracle times out (>60s), orchestrator drops it without blocking. No baked-in static reference; no user opt-out — matches baseline workflow exactly.

4. **Q:** Should we expose `bootstrap-harness.sh` as a user-facing CLI (e.g., `/harness-bootstrap`)?
   **Resolved:** No new skill (per `[[feedback_no_new_skills]]`). It's a private impl detail of `/harness-engineering`.

5. **Q:** What's the failure mode if a scout returns "I couldn't find files in layer X"?
   **Resolved:** Block + ask user via `AskUserQuestion`. Options: (a) skip this layer's spec, (b) user provides representative file paths, (c) mark layer trivial (no spec needed). Init pauses until user picks. Slower but explicit — prevents silent gaps in spec coverage. Same handling for any scout that returns insufficient evidence.

---

## 14. Estimated Effort

| Track | Effort | Notes |
|-------|--------|-------|
| A — bootstrap script + smoke tests | 3-4h | 11 stages, 7 flags (3 debug-only per R1), idempotency, flag-stages matrix, safe-symlink helper, portable abspath (R-extra), parallel validation (R6), chmod-glob (R10), settings.json merge (Appendix A), re-run detection, --force escape hatch |
| B — Phase 1 parallel discovery (10 calls inc. wiki scouts) | 1h | SKILL.md rewrite + discovery-checklist.md scout prompts + scout schema with no_evidence handling |
| C — Phase 2-7 parallel generation (R1 — single bootstrap call) | 45m | SKILL.md edit + Write batch list (12 substitution files inc. harness-review.md + 2 hooks) |
| D — parallel layer specs + failure batching | 30m | SKILL.md + reference example + scout-failure prompt |
| E — Phase 0 (single 6-option prompt) | 20m | AskUserQuestion block + wiring.md cross-ref note |
| Integration tests + version bump | 1h | 3 reference repos (TS/Py/Go), regression against /harness-fix and /harness-run |
| **Total** | **~6.5-7.5h** | **One long sitting or two focused sessions** |

Track F dropped (workflow-preservation audit). R1/R6/R10/R-extra refinements folded into Track A.

---

## 15. Success Metrics

After landing v0.3.0:
- ✓ Fresh-repo wall clock: 20+ min → 10-15 min (~30-50% reduction)
- ✓ Tool call count: ~110-140 → ~25-35 raw calls across ~5-7 batched turns
- ✓ All 24 Phase 11 validation checks pass on 3 reference repos (parallel exec via R6)
- ✓ Generated files byte-identical to v0.2.1 (modulo discovery-driven substitutions)
- ✓ `/harness-fix` + `/harness-run` regression-test green (workflows untouched)
- ✓ Idempotency: re-running bootstrap on a complete install produces no diff (runs Stage 11 only)
- ✓ Single bootstrap invocation per init (R1) — `--copy-only`/`--wire-only` retained as debug flags
- ✓ Portable on macOS without coreutils (R-extra — abspath fallback)
- ✓ No new skill folders (memory `[[feedback_no_new_skills]]` honored)
- ✓ Squash-merge decision front-loaded into Phase 0 with all 6 baseline values preserved (memory `[[feedback_prompt_timing]]` honored)
- ✓ All 4 wiki files populated from DISCOVERY scouts (no stub regression vs baseline)
- ✓ No content-skip optimizations (Track F dropped) — pure speedup via parallelism + batching only

---

## Appendix A — `.claude/settings.json` Merge Algorithm

Bootstrap Stage 8 must add harness hooks to `.claude/settings.json` without clobbering user's existing hooks.

### Inputs
- `existing` — current contents of `.claude/settings.json` (may be empty, may be missing entirely, may have arbitrary user hooks)
- `harness_block` — the exact hooks block bootstrap wants to add (from `references/wiring.md` §10.5)

### Algorithm

```python
import json
import os
import tempfile

def merge(existing_path, harness_block):
    if not os.path.exists(existing_path):
        # Case A: file missing → write fresh
        write_atomic(existing_path, {"hooks": harness_block["hooks"]})
        return "wrote-fresh"

    with open(existing_path) as f:
        data = json.load(f)

    if "hooks" not in data:
        data["hooks"] = {}

    for event in harness_block["hooks"]:               # e.g., PostToolUse, PreToolUse
        existing_entries = data["hooks"].setdefault(event, [])
        for new_entry in harness_block["hooks"][event]:
            # new_entry is {"matcher": "...", "hooks": [{"type": ..., "command": ...}]}
            if any(
                e.get("matcher") == new_entry["matcher"] and
                any(h.get("command") == new_h.get("command")
                    for h in e.get("hooks", [])
                    for new_h in new_entry.get("hooks", []))
                for e in existing_entries
            ):
                # (matcher, command) tuple already present → skip (idempotent)
                continue
            existing_entries.append(new_entry)

    write_atomic(existing_path, data)
    return "merged"

def write_atomic(path, data):
    # Atomic write: temp file in same dir, then rename
    dirname = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=dirname, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        os.unlink(tmp)
        raise
```

### Rules
1. **Never delete or rewrite** existing user hooks under different matchers.
2. **Idempotent**: re-running emits same final file. (matcher, command) tuple check prevents duplicates.
3. **Atomic**: write to temp file in same dir, then `os.replace` (atomic on POSIX). Never half-write.
4. **Preserve formatting**: load + dump with 2-space indent. (Users editing this file by hand may lose comments — out of scope.)
5. **Validation after write**: re-parse the result; if JSON broken, restore from backup and exit non-zero.

### Edge cases
| Case | Behavior |
|------|----------|
| File missing | Write fresh with harness block only |
| File present, empty `{}` | Add `hooks` key with harness block |
| File present, has `hooks` but no `PostToolUse`/`PreToolUse` | Create those keys, add our entries |
| File present, has matching (matcher, command) tuple already | Skip (idempotent) |
| File present, has different matcher with our command | Add as new entry under our matcher |
| File present, has our matcher with different command | Add new entry to same matcher's `hooks` array |
| File present, JSON broken | Exit non-zero with clear error; refuse to clobber |

### Backup
Before write, copy current `.claude/settings.json` → `.claude/settings.json.harness-backup-<timestamp>` so user can restore if needed. Cap at 5 backups (rotate oldest).
