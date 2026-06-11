# Greenfield Flow — Bare Folder to Production-Ready Project

**Read this when** the Entry Gate (SKILL.md Phase −1) classified the repo as
`bare`, or the user invoked `/espalier-new`. The normal init flow discovers
conventions *from code* — a bare folder has none, so this flow first creates
a production-grade project (adaptive grill → scaffold → verify → deploy-ready),
then converges into the standard discovery pipeline.

Plan & locked decisions: `docs/greenfield-v2-plan.md` in the plugin repo.

---

## 0. Preconditions

- **TTY required.** If the session is non-interactive (`[ -t 0 ]` false), stop
  with: `Greenfield setup needs an interactive session — it interviews you
  before scaffolding. Re-run /espalier-new (or /espalier-init) in a terminal.`
  There is no no-questions fallback: scaffolding blind produces the wrong
  project.
- **Bare means bare.** README, LICENSE, `.git*`, editor/IDE config, and
  docs-only files are fine. If the Entry Gate misfired (manifest or source
  files exist), do NOT scaffold — return to the normal init flow.
- **Read source ≠ write target.** `DISCOVERY_DIR` is what scouts READ.
  Outputs are ALWAYS written to the current project (`.`).

## 1. Flow overview

```
Round 0 (mode + inputs) ─► [example has espalier/?] ─► copy & adapt (§8) ─► converge (§9)
   │                                │ declined / no espalier
   ▼                                ▼
Round 1 (product brief) ─► Round 2 (track + shape) ─► read greenfield/<track>.md
   ▼
Track rounds (≤3, from track file) ─► resolve stack (§4) ─► proposal + confirm (§5)
   ▼
Scaffold ─► VERIFICATION GATE (§6) ─► offer guided first deploy (§7)
   ▼
Initial commit (ask) ─► converge into standard Phase 0 → 1 → 2 → 3 (§9)
```

## 2. The greenfield grill

Methodology ported from `espalier-grill` (that skill is generated *into*
target projects — it does not exist yet on a bare repo, so the rules live
here):

- **Sequential rounds.** Each round is ONE `AskUserQuestion` (≤ 4 questions).
  Later rounds are shaped by earlier answers.
- **Adaptive depth.** Before each round, check what the user already answered
  (invocation arguments, product description, example repo, prior rounds).
  Never re-ask an answered or inferable point. A precise user ("Next.js +
  Postgres + Vercel + GitHub Actions") skips straight to the proposal.
- **Discriminate, don't enumerate.** Before asking, silently sample 3–5
  divergent stacks the answers so far still permit; ask the question whose
  answer best discriminates between them.
- **Every question carries a recommended default** so "don't know" never
  blocks. Defaults applied are still logged in `stack-decisions.md`.
- **Hard caps:** ≤ 4 questions per round; ≤ 3 track-specific rounds. Stop the
  moment remaining ambiguity would not change the scaffold.

### Round 0 — Mode + inputs (ONE AskUserQuestion)

1. **Mode:** `Full grill (recommended)` — adaptive interview, best scaffold ·
   `Express` — minimal questions, best-practice defaults for everything else.
2. **Example product?** "Got an existing product/repo you like — local path
   or git URL? Espalier can learn from it." `No` · `Yes` (path/URL via Other).
3. **Stack research depth:** `Hybrid (recommended)` — curated candidates +
   one live verify pass for the chosen stack · `Full live research` — research
   the current production standard from scratch (slower, costlier, freshest).

**If an example was given**, resolve it now (§3). If it contains `espalier/`,
offer the copy & adapt fast-path (§8) before any further grilling.

### Round 1 — Product brief

If the user hasn't already described the product, ask **in prose** (not
AskUserQuestion): "One or two sentences — what does this product do, and for
whom?" Then ONE AskUserQuestion covering whichever of these the description
left open:

- **Audience:** internal tool · public consumer · B2B · developer tool
- **Scale expectation:** prototype/validation · small steady userbase ·
  serious scale from day one
- **Auth:** none · email+OAuth social login · enterprise SSO · unsure
  (default: track-appropriate recommendation)
- **Needs** (multiSelect): realtime · payments · email sending · file
  uploads · AI/LLM calls · none of these

Answers feed both stack choice (e.g. realtime → websocket-capable host;
payments → never roll your own) and `wiki/product-brief.md` (§9).

**Express mode:** prose one-liner only; defaults for the rest.

### Round 2 — Track + shape

**2a.** Primary interface: `Web UI` · `Mobile` · `Desktop` · `No UI (API /
CLI / library)`.

**2b.** Branch on 2a (one follow-up AskUserQuestion; include language where
the track needs it — TS/JS · Python · Go · Other):

| 2a answer | 2b asks | Resolved track |
|---|---|---|
| Web UI | own backend? content-heavy/CMS? team-split services? | `frontend` · `fullstack` · `cms` · `microservices` |
| Mobile | — (framework choice lives in track file) | `mobile` |
| Desktop | — (Tauri/Electron choice lives in track file) | `desktop` |
| No UI | long-running service? CLI? distributable library? multiple services? | `backend` · `cli-library` · `microservices` |

If the user names a stack outside the curated set ("Phoenix/Elixir",
"Ktor"), route to **BYO** (§4.3) — never refuse, never hand-roll.

### Track rounds

Read `references/greenfield/<track>.md` (sibling `greenfield/` directory).
Each track file opens with its **grill question bank** — persistence, deploy
target, CI provider, test depth, release shape, track extras. Ask only what
the brief + prior answers leave open. ≤ 3 rounds, then move to stack
resolution. **Express mode:** skip track rounds entirely; use the track
file's recommended defaults.

## 3. Example repo resolution

- **Local path:** verify it exists and is a directory. Use as-is — it is the
  user's own checkout; NEVER modify or delete it.
- **Git URL** (`https://…`, `git@…`, `*.git`): shallow-clone read-only:

  ```bash
  TMP_EXAMPLE="$(mktemp -d)"
  git clone --depth 1 "$URL" "$TMP_EXAMPLE"
  ```

  Record `$TMP_EXAMPLE`; remove after the flow completes (confirm before
  `rm -rf`, per the deletion-safety rule). Clone failure (private/auth/
  network) → report, continue without the example.
- **Security:** Espalier only READS examples. Never run an example's build,
  tests, or scripts.
- `[ -d "$EXAMPLE/espalier" ]` → offer copy & adapt (§8). Otherwise the
  example informs stack choice (grill mentions it: "your example uses X —
  same here?") and may serve as `DISCOVERY_DIR` at convergence (§9).

## 4. Stack resolution

### 4.1 Hybrid (default)

The track file's **stack candidates** table maps the brief to a
recommendation. After the user accepts a candidate, run ONE verification
pass — oracle/`find-docs`/ctx7 + web search in parallel:

1. Is this still the current production standard for the use case? (If the
   ecosystem moved, surface that and let the user re-decide.)
2. The **exact, current scaffolder invocation** — commands drift; NEVER run
   a remembered command. The curated tables are candidates, not gospel.

### 4.2 Full live research

Oracle researches the recommendation itself ("current production-standard
stack for <brief summary> in <track>"), using the track file only as a
structural checklist (what a complete answer must cover: scaffolder,
add-ons, persistence, deploy, tests, release). Present findings as the
candidate set, then proceed as in 4.1 step 2.

### 4.3 BYO-stack protocol

User named a stack the curated files don't cover:

1. Full live research: current scaffolder, prod add-ons (lint/format/test),
   deploy norms, release conventions for that ecosystem.
2. Follow the closest track file's **section contract** ad hoc (scaffold
   sequence → deploy-ready config → test pyramid → release → verification).
3. Record findings + sources in `stack-decisions.md` so the next similar run
   is cheaper.

Never hand-roll a skeleton when the ecosystem has an official scaffolder —
that defeats "discover, don't prescribe."

## 5. Proposal + scaffold

1. Present the full plan in plain text: stack + why (tied to brief answers),
   scaffolder command(s), prod add-ons, persistence, deploy target + CI
   provider, test tooling, release shape. One block, scannable.
2. **Confirm before running** — the scaffolder writes into `.`. Surface that
   many scaffolders refuse a non-empty directory (`.git`/README usually
   fine; if the scaffolder balks, scaffold into a temp dir and move contents
   in, preserving `.git`).
3. Run, in order: scaffolder → prod add-ons → persistence wiring (compose
   dev db + migrations where the track calls for it) → deploy-ready config
   (Dockerfile where applicable, CI workflow incl. deploy stage,
   `.env.example`, `docs/runbook.md`) → release wiring. The track file's
   **scaffold sequence** section is the checklist.
4. **Secrets rule (hard):** never write a real secret to any file.
   `.env.example` holds placeholder names only; real values go through the
   provider's CLI/secret store at deploy time.

## 6. Verification gate

Run the track file's **verification commands**: install → build → lint →
test → boot. Boot = track-appropriate liveness (dev server answers on an
ephemeral port / health endpoint 200 / CLI `--help` exits 0 / desktop dev
window opens). Bounded timeouts — no infinite waits.

- **Green** → proceed.
- **Red** → diagnose and fix, **≤ 2 attempts** (typical: add-on version
  conflicts, lockfile drift).
- **Still red** → stop. Report exactly what fails, then offer:
  (a) hand over as-is with a written known-issues note in the runbook, or
  (b) rollback — list every file/dir the scaffold created (the repo was
  bare, so this list is the complete inventory), confirm with the user,
  then delete. Never silently `rm -rf`.

Never hand the user a broken skeleton without saying so.

## 7. Guided first deploy (opt-in)

After the gate is green, ask ONCE: "Deploy-ready config is in place. Want a
guided first deploy now (login → provision → secrets → deploy → verify live
URL), or do it yourself later with `docs/runbook.md`?"

If yes → read `references/greenfield/deploy-targets.md` and follow the flow
for the chosen target. Every step is user-driven and abortable; an abort
loses nothing — the deploy-ready config stays. Mobile/desktop tracks offer
their analogue here (guided store setup / signing setup) per their track
files — config stubs are already written either way.

## 8. Copy & adapt fast-path (example already has `espalier/`)

The example curated a harness — offer to reuse it instead of re-deriving.
User picks: **copy & adapt** (fast, inherits the example's curation) or
**decline** (continue the normal grill; the example remains a stack hint).

If copying:

1. Run **Round 1 (product brief)** if not already done — the wiki brief must
   describe THIS product, not the example's.
2. Run Phase 0 **Q1 only** (squash-merge strategy → `$MERGE_DECISION`);
   Q2/Q3 take defaults (`restricted`, `weekly`) unless the user objects.
3. `cp -R "$EXAMPLE/espalier" ./espalier`
4. Adapt: swap the example's project name (grep it across `espalier/agent.md`,
   `espalier/rules/*.md`, `espalier/skills/*/SKILL.md`); relativize absolute
   paths pointing into the example's checkout; delete carried-over runtime
   state — `.commit-index.tsv`, `.drift-state.tsv*`, `.drift.log`,
   `.drift-report.md`, `.doctor-last-run`, `.drift-overrides.log`,
   `.merge-hook-decision`, `.doctor-cadence` (bootstrap regenerates these
   for THIS repo).
5. Wire: `bash "${CLAUDE_SKILL_DIR}/../../scripts/bootstrap-espalier.sh"
   --project-dir=. --plugin-dir="${CLAUDE_SKILL_DIR}"
   --merge-decision=$MERGE_DECISION --doctor-cadence=weekly --wire-only`
6. Write `wiki/product-brief.md` + `stack-decisions.md` (decisions =
   "inherited from example <name/url>") + the changes entry (§9).
7. Skip Phase 1/2 (no discovery). Tell the user the copied wiki/specs
   describe the example's code — `/espalier-doctor` reconciles them once this
   project has its own code. Go to the Phase 4 completion message.

Note: copy & adapt skips scaffolding — the user gets a harness, not code. If
they ALSO want a scaffold, run the normal flow first (scaffold + verify),
then copy & adapt instead of discovery.

## 9. Artifacts + convergence

### Artifacts (greenfield additions to the standard set)

| Artifact | When written | Content |
|---|---|---|
| `espalier/wiki/product-brief.md` | Phase 2 writes | Round 1 answers: what/who/scale/auth/needs. Seeds future `/espalier` Stage 1 grills. |
| `espalier/wiki/stack-decisions.md` | Phase 2 writes | Every choice: what, why, alternatives rejected, decided-by (user / express default / research), verify date + sources. |
| `espalier/changes/feat/<YYYY-MM-DD>-greenfield-scaffold/` | after bootstrap | `requirements.md` (brief summary + chosen stack) + `pipeline-state.md` (scaffold steps, verification results, deploy status, initial commit SHA). Audit trail starts at birth. |

Both wiki files participate in drift detection like any other artifact.

### Convergence

1. **Initial commit (ask first):** offer to commit the verified scaffold —
   gives Phase 1's git-log scout something to read.
2. Set `DISCOVERY_DIR`:
   - Default `.` — discovery reads the fresh scaffold; Espalier encodes the
     scaffolder's + add-ons' real conventions.
   - If an example (without `espalier/`) was provided, ask once: discover
     conventions from the scaffold (recommended) or from the example? The
     latter sets `DISCOVERY_DIR=<example>`; tell the user the generated wiki
     then describes the example until `/espalier-doctor` reconciles it.
3. Run the standard pipeline: **Phase 0 (Setup Decisions, full Q1–Q3) →
   Phase 1 (discovery, scouts read `DISCOVERY_DIR`) → Phase 2 (writes, plus
   the two wiki artifacts above) → Phase 3 (bootstrap, full)**.
4. After bootstrap exits 0: write the changes entry, then end with the
   **Phase 4 completion message** verbatim (SKILL.md).

### Convergence summary

| Route | DISCOVERY_DIR | Setup Decisions | Phase 1/2 | Phase 3 |
|---|---|---|---|---|
| Scaffold (default) | `.` | full Q1–Q3 | yes | full |
| Scaffold + example conventions | `<example>` | full Q1–Q3 | yes (reads example) | full |
| Copy & adapt | n/a | Q1 only (+ defaults) | skipped | `--wire-only` |
