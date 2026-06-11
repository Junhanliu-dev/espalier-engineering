# Greenfield v2 Plan — espalier-engineering

**Status:** 📝 Planned
**Target version:** v0.7.0
**Type:** Feature, non-breaking (additive — fires only on bare repos / explicit `/espalier-new`)

## 1. Goal

Give Espalier a first-class **greenfield mode**: starting from an empty folder, interview the user (adaptive grill), recommend a current production-grade stack, scaffold it with the ecosystem's own tools, wire deploy/CI/test/release infrastructure, verify the skeleton actually builds and boots, then converge into the standard `/espalier-init` discovery pipeline — so a brand-new project is born with both a working production path *and* an Espalier harness.

The existing draft (`references/greenfield.md`, untracked) covers only a thin slice: a 3-question interview, a single-app scaffolder lookup table, no architecture dimension, no persistence, no deploy story, no verification, and an Entry Gate that doesn't exist in `SKILL.md`. v2 replaces it.

**Scope of "production":** every scaffold ships **deploy-ready config** (Dockerfile where applicable, CI with deploy stage, env templates, runbook). A **guided first deploy** (login → provision → secrets → deploy → verify live URL) is *offered* as an opt-in step, never forced.

## 2. Scope

**In:**
- Entry Gate in `/espalier-init` (auto-detect bare repo) **and** a new dedicated `/espalier-new` command. Both route into one merged flow.
- One merged flow (old Path A / Path B split removed). An example repo the user likes becomes an *optional grill input*; the copy-&-adapt fast-path (example already has `espalier/`) is kept as a branch.
- Inline **adaptive greenfield grill** — stack questions + product brief. Express mode for users who want defaults.
- **Nine tracks**, each a self-contained reference file: pure frontend, pure backend, fullstack monorepo, mobile (Flutter/Expo), Next.js + headless CMS, microservices, CLI/library, desktop (Tauri/Electron), BYO-stack (live research).
- Stack recommendation source chosen by user per run: **hybrid** (curated candidates + one live verify pass) or **full live research**.
- Deploy layer: deploy-ready config always; guided first deploy offered (curated targets: Vercel, Fly.io, Railway, Cloudflare, Docker/VPS — plus research-per-run for anything else).
- CI provider asked in grill; GitHub Actions gets curated templates, others researched live.
- Per-track release process (changesets/twine/cargo for libraries; tag-triggered deploy for apps; version-bump + store stubs for mobile).
- **Verification gate**: install → build → lint → test → boot must pass before convergence.
- Artifacts: `espalier/wiki/product-brief.md` + `espalier/wiki/stack-decisions.md` + a first `espalier/changes/feat/<date>-greenfield-scaffold/` entry.
- `eval/greenfield/` harness (scenario fixtures + scaffold assertions).

**Out (deferred — see §12):**
- Guided store *submission* for mobile (signing + store-connect walked live) — offered as a question, but the guided implementation beyond config stubs is best-effort v1, full support deferred.
- IaC beyond stubs (full Terraform/Pulumi modules).
- Non-GitHub CI curated templates (researched live instead).

## 3. Locked decisions (from grill session 2026-06-11 — do not relitigate without cause)

| # | Decision | Rationale |
|---|---|---|
| 1 | Deploy scope = **deploy-ready config always; guided first deploy offered** | "Usable production environment" without forcing credentials mid-init |
| 2 | **All 9 tracks** in v1, incl. desktop and BYO-stack via live research | User explicitly wants coverage beyond webapps (Flutter, desktop, pure backend/frontend, etc.) |
| 3 | Stack source = **user picks hybrid or full live research** per run | Hardcoded tables drift (`create-nest` already stale); research costs tokens — user's tradeoff |
| 4 | Entry = **both** `/espalier-new` + Entry Gate in `/espalier-init` | Discoverable intent + safety net for bare-repo init runs |
| 5 | Interview = **adaptive grill, inline** in greenfield references | Generated `espalier-grill` skill lives in target projects — unavailable on a bare repo; methodology is ported, not invoked |
| 6 | Grill covers **stack + product brief** | Product answers (scale, auth, realtime) drive stack choice; brief seeds future `/espalier` requirements |
| 7 | **Per-track reference files** | One big file = ~1500+ lines loaded every run; per-track = read only what's chosen |
| 8 | Verification = **build + test + boot** before convergence | Never hand the user a broken skeleton; prod add-ons layered on scaffolds can break silently |
| 9 | **Express mode** offered upfront | "Just build me a best-practice X" users exist; all defaulted choices still logged |
| 10 | Mobile = **config + stubs** default; guided store setup *offered* | Store pipelines need accounts/signing; never block init on Apple review |
| 11 | Microservices shape = **grill decides** (capped, see §5.6) | Most tailored; cap prevents over-building before product exists |
| 12 | Artifacts = **wiki + changes entry** | Brief/decisions as on-demand context; audit trail starts at project birth |
| 13 | **Merged flow** — example repo is optional grill input | A/B split forced a premature decision; example + grill compose naturally |
| 14 | Copy-&-adapt fast-path **kept as a branch** | Free curation when example has `espalier/`; user picks copy vs fresh grill |
| 15 | Deploy targets = **curated recommendations + research-per-run option** | Tested guided flows for the common 90%; live research for the rest |
| 16 | CI provider = **asked in grill** | GH Actions curated; others live-researched |
| 17 | Releases = **per-track default** | Library ≠ app ≠ mobile release shapes |
| 18 | Ship = **one release (v0.7.0), phased commits, thorough testing per phase** | User preference; each phase is independently testable |
| 19 | Eval = **`eval/greenfield/`** following `eval/grill/` precedent | Keeps adaptive grill honest across model changes |

## 4. Architecture

### 4.1 Entry points

**Entry Gate (Phase −1 of `/espalier-init`).** Before Phase 0, classify the repo:

- `bare` = **no package manifest** (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pubspec.yaml`, `*.csproj`, `Gemfile`, `pom.xml`, `build.gradle*`) **and no source files** (`*.{ts,tsx,js,jsx,py,go,rs,dart,swift,kt,java,rb,cs,php,vue,svelte}` outside dotted dirs). README/LICENSE/.git/.gitignore/editor configs/docs-only do **not** disqualify bare.
- `bare` → read `references/greenfield.md`, enter greenfield flow.
- not bare → normal init, zero behavior change (non-breaking guarantee).

**`/espalier-new`** — thin plugin skill (~40 lines): states purpose, runs the same bare check. Bare → jump straight into greenfield flow. **Not bare → warn** ("this repo has code; `/espalier-init` discovers from it — scaffolding into a non-empty repo is unsupported") and stop unless the user explicitly insists (most scaffolders refuse non-empty dirs anyway).

**Non-interactive runs:** greenfield **requires** a TTY. No TTY → fail fast with a clear message (cannot scaffold blind; unlike pipeline grilling there is no meaningful no-questions fallback).

### 4.2 Merged flow

```
Entry (gate or /espalier-new, repo = bare)
  │
  ├─ Round 0: mode + inputs
  │    • Express or full grill?
  │    • "Got an example product/repo you like?" (optional — local path or git URL)
  │    • Stack source: hybrid (curated + verify) or full live research?
  │
  ├─ [example has espalier/] ──► offer COPY & ADAPT fast-path (§4.8)
  │                              (user may decline → continue grilling, example
  │                               stays as a discovery/convention input)
  │
  ├─ Grill (adaptive, §4.3): product brief → track → track-specific rounds
  │
  ├─ Read references/greenfield/<track>.md
  │
  ├─ Resolve stack (curated candidates → ONE live verify pass, or full research)
  │
  ├─ Present scaffold proposal (commands + add-ons + deploy plan) → confirm
  │
  ├─ Scaffold: ecosystem scaffolder → prod add-ons → persistence → deploy-ready
  │   config → CI/CD → release wiring → env templates → runbook
  │
  ├─ VERIFICATION GATE: install → build → lint → test → boot (§4.6)
  │
  ├─ Offer guided first deploy (§4.5) — opt-in
  │
  ├─ Write artifacts: wiki/product-brief.md, wiki/stack-decisions.md,
  │   changes/feat/<date>-greenfield-scaffold/ (§4.7)
  │
  └─ Converge: DISCOVERY_DIR=. (or example, if user chose to learn conventions
      from it) → standard Phase 0 → 1 → 2 → 3 → Phase 4 completion message
```

`DISCOVERY_DIR` semantics from the draft survive: scouts READ from it; outputs always WRITE to `.`.

### 4.3 Adaptive greenfield grill

Methodology ported from `espalier-grill` (signal counting, divergent-interpretation sampling, sequential rounds, hard question caps) but inlined in `greenfield.md` because the generated skill doesn't exist yet on a bare repo.

**Round structure** (each round = one `AskUserQuestion`, ≤ 4 questions; later rounds shaped by earlier answers):

| Round | Covers | Source |
|---|---|---|
| 0 | express/full · example repo? · stack source (hybrid/live) | `greenfield.md` |
| 1 | product brief: what it does, who uses it, expected scale, auth?, realtime?, key integrations | `greenfield.md` |
| 2 | track + language (+ architecture shape where ambiguous: monolith vs services, monorepo vs single app) | `greenfield.md` |
| 3+ | track-specific: persistence/ORM, deploy target, CI provider, test depth, release shape, track extras | `greenfield/<track>.md` question bank |

**Adaptive depth:** precise answers collapse later rounds (a user who says "Next.js + Postgres + Vercel + GitHub Actions" skips straight to confirmation). Vague answers expand them — but every track file declares a hard cap (≤ 3 rounds of track questions). Every question carries a **recommended default** so "don't know" never blocks.

**Express mode:** Round 0 + (track, language, product one-liner). Everything else = recommended defaults. All defaulted decisions still logged in `stack-decisions.md` marked `(default — express mode)`.

### 4.4 Track system

`greenfield.md` shrinks to: Entry Gate definition + Round 0–2 grill + routing + shared protocol (verification, artifacts, convergence). Each track lives in `references/greenfield/<track>.md` and is **read only after the track is chosen**.

**Track file contract** — every track file contains exactly these sections:

1. **Grill question bank** — track-specific rounds + recommended defaults.
2. **Stack candidates** — curated table: candidate stacks, when to pick each, rationale, rejected-alternative notes. *Candidates, not gospel*: under hybrid mode, after the user picks, ONE oracle/ctx7 pass verifies the choice is still the current production standard and fetches the **exact scaffolder invocation** (commands drift — never run a remembered command). Under full-research mode, the whole recommendation is researched live and the table is only a fallback.
3. **Scaffold sequence** — scaffolder → prod add-ons (lint/format/test) → persistence wiring → structure adjustments.
4. **Deploy-ready config** — what gets written: Dockerfile/compose (where applicable), CI workflow incl. deploy stage, `.env.example`, `docs/runbook.md`.
5. **Test pyramid** — unit + integration + e2e tooling for the track, wired into CI.
6. **Release process** — per-track default (§3 #17).
7. **Verification commands** — exact install/build/lint/test/boot checks for the gate.

### 4.5 Deploy layer

**Always (deploy-ready config):** Dockerfile + compose where the track calls for it, CI deploy stage (gated on the chosen provider), `.env.example` (placeholders only — **secrets are never written to files**; provider CLI auth + provider secret stores), `docs/runbook.md` covering first deploy, env promotion (staging/prod), rollback.

**Guided first deploy (opt-in question after verification passes):**

- Curated targets with tested guided flows: **Vercel** (frontend/fullstack), **Fly.io** (backend/fullstack/containers), **Railway** (backend + db), **Cloudflare** (Pages/Workers), **Docker/VPS generic** (build → run locally → push to registry + VPS runbook).
- Anything else → research-per-run: oracle fetches the provider's current CLI flow, guide from live docs.
- Guided flow shape: CLI login (user-driven) → provision app + db → set secrets via provider CLI → deploy → verify live URL/health endpoint. Each step confirmable, abortable; an abort leaves deploy-ready config intact.

**CI provider:** asked in grill. GitHub Actions → curated workflow templates per track. GitLab/Bitbucket/other → researched live, assembled from the same stage contract (build → lint → test → deploy).

### 4.6 Verification gate

After scaffolding, before convergence — run the track's verification commands:

```
install → build → lint → test → boot
```

Boot = track-appropriate liveness: dev server responds / health endpoint 200 / `flutter analyze` + test runner green / CLI `--help` exits 0. Use ephemeral ports and a bounded timeout to avoid false reds.

- **Green** → proceed.
- **Red** → fix loop, ≤ 2 attempts (typical causes: add-on version conflicts, lockfile drift).
- **Still red** → stop, report exactly what fails, offer: (a) hand over as-is with a written known-issues note, or (b) rollback. Rollback = list every file/dir the scaffold created, confirm with the user, then delete (per the deletion-safety rule — never silent `rm -rf`). The repo was bare, so the created-file list is the complete inventory.

### 4.7 Artifacts

| Artifact | Location | Content |
|---|---|---|
| Product brief | `espalier/wiki/product-brief.md` | Domain, users, scale expectations, auth/realtime/integration answers — seeds future `/espalier` Stage 1 grills |
| Stack decision record | `espalier/wiki/stack-decisions.md` | Every choice: what, why, alternatives rejected, who decided (user / express default / research), verify-pass date |
| Scaffold change entry | `espalier/changes/feat/<YYYY-MM-DD>-greenfield-scaffold/` | `requirements.md` (brief summary + chosen stack) + `pipeline-state.md` (scaffold steps, verification results, deploy status, commit SHA) — audit trail starts at birth |

Both wiki files participate in v0.5 drift detection like any other wiki artifact (`/espalier-prune`, `/espalier-doctor` refresh them as the product diverges from its brief).

### 4.8 Copy-&-adapt fast-path (kept from draft B.3b)

If the user's example repo contains `espalier/`: offer copy & adapt (cp tree → swap project name → relativize absolute paths → strip runtime state files → `bootstrap --wire-only` → validation) vs fresh grill. Mechanics unchanged from the draft, including: read-only treatment of examples (never execute example code), shallow clone to temp dir for URLs, confirm-before-delete cleanup. The fast-path now *also* runs Round 1 (product brief) — cheap, and the wiki brief shouldn't describe the example's product.

### 4.9 Convergence

All routes end in standard **Phase 0 (Setup Decisions) → 1 → 2 → 3 → Phase 4 completion message**. Greenfield-specific additions to convergence:

- `DISCOVERY_DIR=.` normally; `DISCOVERY_DIR=<example>` only if the user explicitly chose to learn conventions from the example rather than the fresh scaffold.
- Phase 2 writes the two extra wiki files (§4.7) alongside the standard wiki set.
- Initial commit offered (gives Phase 1's git-log scout something to read) — ask first, per git-safety rule.
- `bootstrap-espalier.sh` is **unchanged** — greenfield converges into the existing contract.

## 5. Track specs (curated candidates — verify live before running)

Per-track defaults; each track file holds the full table + question bank.

### 5.1 Pure frontend (`greenfield/frontend.md`)
Vite (React/Vue/Svelte/Solid) or Astro (content-heavy). Add-ons: eslint+prettier (or biome), vitest + Testing Library, Playwright (e2e), optional Storybook, MSW for API mocking. Deploy: Cloudflare Pages / Vercel / Netlify. Release: tag-deploy + CHANGELOG.

### 5.2 Pure backend (`greenfield/backend.md`)
Shape question first: REST / GraphQL / gRPC / event-driven. TS: Fastify or NestJS; Python: FastAPI (uv); Go: chi/std; Rust: axum. Persistence round: Postgres default, ORM per language (Drizzle/Prisma, SQLAlchemy+Alembic, sqlc, sqlx), docker-compose dev db, migrations wired. Optional queue/worker. OpenAPI generation. Health endpoint, structured logging, config validation, graceful shutdown — **prod-grade means these, not just lint**. Deploy: Fly/Railway/Docker-VPS. Release: tag-deploy.

### 5.3 Fullstack monorepo (`greenfield/fullstack.md`)
Two shapes: single-app fullstack (Next.js, default for solo/small) vs monorepo split (Turborepo/pnpm workspace: `apps/web` + `apps/api` + `packages/shared`). Contract: tRPC (TS-only) or OpenAPI-generated client. Per-workspace CI with affected-only builds. Deploy: Vercel (web) + Fly/Railway (api), or single-target.

### 5.4 Mobile (`greenfield/mobile.md`)
Flutter vs Expo (vs native — researched live if insisted). Flavors/schemes dev·staging·prod. State management choice (riverpod/bloc; zustand/RQ). Tests: unit + widget/component + integration (patrol / maestro). CI: lint + test + debug & release artifact builds. Store pipeline: fastlane / EAS config files with TODO credential placeholders + submission runbook — **guided store setup offered** but never blocks init. Companion question: "backend exists, need one too (spawn backend track), or BaaS (Supabase/Firebase)?"

### 5.5 Next.js + CMS (`greenfield/cms.md`)
CMS choice: Payload (TS-native, self-host, default), Strapi, Sanity, Directus — hosted vs self-hosted question. Content modeling stub from product brief. Preview environment wiring. Deploy: Vercel (front) + CMS host per choice.

### 5.6 Microservices (`greenfield/microservices.md`)
Grill decides shape (services, domains, languages) — **capped at 3 services initially** + a copyable service template dir; more services = post-init work. Always: docker-compose dev env, gateway/BFF, shared contracts package (OpenAPI or proto), per-service CI jobs, db-per-service. Honest gate question first: "microservices on day one is usually wrong — confirm the constraint that forces it" (team boundaries, independent scaling, polyglot need). Recommend modular monolith if no constraint named; record the answer in stack-decisions.

### 5.7 CLI / Library (`greenfield/cli-library.md`)
Existing draft rows survive here (Go+cobra, Rust+cargo, Python uv+typer, TS tsup). Library adds publish pipeline: changesets→npm / build+twine→PyPI / cargo publish, release workflow on tag, provenance where supported.

### 5.8 Desktop (`greenfield/desktop.md`)
Tauri (default — Rust core, small binaries, system webview) vs Electron (Node ecosystem, maximum maturity) — choice question, researched live if user names another (Wails, Neutralino). Inner frontend: Vite (React/Svelte/Vue) per the frontend track's candidates. Add-ons: lint/format/test per language pair (clippy+rustfmt / eslint+prettier, vitest). E2e: Playwright (Electron) / WebDriver via tauri-driver. **Distribution is this track's "deploy"**: installer packaging (Tauri bundler / electron-builder) for macOS/Windows/Linux, CI matrix builds producing artifacts per OS, auto-update wiring (Tauri updater / electron-updater) with signing-key TODO stubs, code-signing + notarization config as TODO placeholders + runbook (same pattern as mobile store stubs — never block init on certificates). Release: tag-triggered GitHub Release with attached installers + update manifest.

### 5.9 BYO-stack (protocol section in `greenfield.md`)
User names a stack outside the curated set (or curated candidates don't fit) → full live research: oracle (WebSearch + ctx7) establishes current scaffolder, prod add-ons, deploy norms for that ecosystem; then the standard track-file contract is followed ad hoc. Findings recorded in stack-decisions so the next run on a similar request is cheaper.

## 6. File inventory

### New
| File | Purpose |
|---|---|
| `skills/espalier-init/references/greenfield.md` | **Rewrite of draft**: Entry Gate, merged flow, grill rounds 0–2, routing, shared protocol (verification, artifacts, convergence, BYO) |
| `skills/espalier-init/references/greenfield/frontend.md` | Track file (§4.4 contract) |
| `skills/espalier-init/references/greenfield/backend.md` | Track file |
| `skills/espalier-init/references/greenfield/fullstack.md` | Track file |
| `skills/espalier-init/references/greenfield/mobile.md` | Track file |
| `skills/espalier-init/references/greenfield/cms.md` | Track file |
| `skills/espalier-init/references/greenfield/microservices.md` | Track file |
| `skills/espalier-init/references/greenfield/cli-library.md` | Track file |
| `skills/espalier-init/references/greenfield/desktop.md` | Track file |
| `skills/espalier-init/references/greenfield/deploy-targets.md` | Curated guided-deploy flows (Vercel/Fly/Railway/Cloudflare/Docker-VPS) + research-per-run protocol + secrets rules |
| `skills/espalier-new/SKILL.md` | Thin entry skill: bare check → greenfield flow; warn on non-bare |
| `eval/greenfield/` | Scenario fixtures + assertions (§9) |

### Modified
| File | Change |
|---|---|
| `skills/espalier-init/SKILL.md` | Phase −1 Entry Gate (bare detection + route), file-layout listing, reference index |
| `skills/espalier-init/references/wiki-templates.md` | Add product-brief + stack-decisions stubs |
| `README.md` | Greenfield section, `/espalier-new`, v0.7.0 callout |
| `CHANGELOG.md` | v0.7.0 entry |
| `index.html` | Landing-page version/feature update |
| `eval/README.md` / `eval/run.sh` | Register greenfield suite |

**Unchanged on purpose:** `scripts/bootstrap-espalier.sh` (greenfield converges into the existing contract), all migration scripts (no target-project schema change — see §8), generated-skill templates.

## 7. Implementation phases (one release, commit-per-phase, test each before next)

| Phase | Delivers | Test gate |
|---|---|---|
| **P1 — Flow core** | `greenfield.md` rewrite (Entry Gate, merged flow, grill framework, express, routing, BYO protocol), `SKILL.md` wiring, `skills/espalier-new/SKILL.md` | Bare detection correct on fixture dirs (bare, README-only, has-manifest, has-src); `/espalier-new` warns on non-bare; non-TTY fails fast; existing non-bare init behavior unchanged |
| **P2 — Core 4 tracks** | `frontend.md`, `backend.md`, `fullstack.md`, `mobile.md` | Per track: live run in a temp dir → scaffold → verification gate green; track-file contract sections all present |
| **P3 — Extended tracks** | `cms.md`, `microservices.md`, `cli-library.md`, `desktop.md` | Same live-run gate; microservices capped at 3 services; CLI/lib publish workflow lints clean; desktop verification = build + test + dev-window boot (packaging/signing stubs lint-checked only, not executed) |
| **P4 — Deploy layer** | `deploy-targets.md`, guided-first-deploy flow, guided store-setup offer (mobile), CI-provider grill question + non-GH research path | Deploy-ready config validates (`docker build` succeeds, workflow YAML lints); one real guided deploy exercised per PaaS where feasible; secrets-never-in-files audit |
| **P5 — Artifacts + convergence** | wiki-template additions, changes-entry creation, convergence wiring (`DISCOVERY_DIR`, Phase 2 extra writes, initial-commit offer), copy-&-adapt branch updated for merged flow | End-to-end: bare dir → scaffold → verify → converge → bootstrap → 28 validation checks pass; wiki has brief + decisions; changes entry exists |
| **P6 — Eval + docs + release** | `eval/greenfield/`, README/CHANGELOG/index.html, version bump | Eval suite passes; docs review; full clean-room run of the flagship scenario (bare → live-deployable fullstack repo) |

## 8. Migration

**None required.** All changes are plugin-side; the generated target-project schema is untouched. Existing installs see zero behavioral change (Entry Gate only fires on bare repos, where init previously had no defined behavior). `/espalier-migrate` chain unchanged. The README "Existing users" callout states: nothing to migrate.

## 9. Eval harness (`eval/greenfield/`)

Follows `eval/grill/` precedent. Two layers:

**Interview-behavior scenarios** (fixture = scripted user persona + expected interview shape):
- *Vague user* — "I want an app" → grill expands, ends with concrete stack + brief.
- *Precise user* — full stack named upfront → ≤ 2 rounds, straight to confirmation.
- *Express* — defaults applied, all logged as express defaults.
- *BYO-stack* — uncurated stack → research protocol invoked, no hand-rolled skeleton.
- *Example repo (no espalier/)* — example becomes convention input.
- *Example repo (has espalier/)* — copy-&-adapt offered.
- *Non-bare repo via /espalier-new* — warns, stops.

**Scaffold assertions** (per core track, scripted run in temp dir): expected files exist (scaffolder output + Dockerfile/CI/env/runbook), CI YAML valid, verification gate commands green, wiki artifacts + changes entry written, no secrets in any written file.

## 10. Risks & mitigations (pre-mortem)

| Risk | Mitigation |
|---|---|
| Scaffolder commands drift (already observed: `create-nest`) | Curated tables are *candidates only*; exact invocation always live-verified via ctx7/find-docs before running — hard rule in every track file |
| Scaffolders refuse non-empty dirs | Entry Gate's bare definition tolerates README/.git; pre-check before running; surface to user (draft already did this — keep) |
| Token/cost blowup (grill + research + scaffold + verify + full init in one session) | Express mode; hybrid default (one verify pass, not open-ended research); per-round question caps; cost table in README updated with greenfield cost class |
| Adaptive grill over-asks / rambles | Hard caps (≤ 4 questions/round, ≤ 3 track rounds); recommended default on every question; eval scenarios assert round counts |
| Verification boot check flaky (ports, timeouts) | Ephemeral ports, bounded timeouts, boot check failure ≤ 2 fix attempts then explicit hand-over choice — never infinite loop |
| Guided deploy stalls on auth / provider UI changes | Every guided step user-driven and abortable; abort leaves deploy-ready config intact; non-curated providers researched live rather than from stale templates |
| Secrets leak into scaffolded files | Hard rule: `.env.example` placeholders only, provider CLI auth, provider secret stores; eval asserts no secret-shaped strings in written files |
| Microservices track over-builds | 3-service cap + template dir; "confirm the forcing constraint" gate question; modular-monolith recommendation recorded |
| Example repo executes untrusted code | Preserved draft rule: examples are read-only; never run example build/test/scripts |
| Plugin grows beyond skill-loader comfort | `/espalier-new` stays thin (~40 lines); all logic in references loaded on demand |
| Rollback deletes user files | Impossible-by-construction: repo was bare, scaffold inventory = complete created-file list; deletion always user-confirmed |

## 11. Success criteria

1. From an empty folder, one session produces: working scaffold (verification gate green) + deploy-ready config + wired Espalier harness (28 validation checks pass) for **each core-4 track**.
2. Flagship scenario: bare dir → grilled fullstack app → guided deploy → **live URL** → converged harness, in one session.
3. Express mode reaches a green scaffold with ≤ 6 total questions.
4. Non-bare repos: byte-identical init behavior vs v0.6.0.
5. `eval/greenfield/` suite passes.
6. No secrets in any scaffold-written file (eval-asserted).

## 12. Out of scope / future

- Full guided store submission (Apple/Google) — config + stubs + runbook v1; live walkthrough best-effort.
- Desktop code signing / notarization walked live — config stubs + runbook only in v1 (same rationale as mobile stores: requires paid certs, blocks on external approval).
- IaC modules (Terraform/Pulumi) beyond stubs.
- Curated CI templates for GitLab/Bitbucket (live research covers them meanwhile).
- Greenfield for non-bare repos ("add a new app to this monorepo") — different problem, different gate.

## 13. Reversibility / kill switch

Feature is additive and plugin-side only. To disable: remove `skills/espalier-new/` and the Phase −1 Entry Gate block in `SKILL.md` — init reverts exactly to v0.6.0 behavior. Projects already scaffolded by greenfield are ordinary Espalier projects; nothing references greenfield at runtime after convergence.

## 14. Status / next step

Plan written 2026-06-11 from grill session (5 rounds, 19 locked decisions). Next: **P1 — Flow core**.
