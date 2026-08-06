# Multi-Dev Maintenance — Implementation Plan

**Status:** revision 5 — implementation-ready for Release A + B-team (§4); event-log B-minimal moved to shelf (§5); full B/C shelved (§5–§6).
**Date:** 2026-08-03 (revision 5); 2026-07-24 (revisions 1–4).
**Design source:** `docs/multi-dev-maintenance-research.md` (R1–R10, twice adversarially reviewed — §9/§10 there). Where this plan and the research doc disagree, this plan wins (newer and narrower); each supersession is called out inline.
**Verification:** three external audit rounds (Codex, gpt-5.6-sol, xhigh, full repo read): revision 1 → 23 findings; revision 3 (minimalism descope) → 15 findings, including one cut-too-deep (shared-stamp semantics) and one cut-not-deep-enough (checkpoint residue in A). All folded in (§9 log). Revision 5: re-verified against the v0.15.0 tree + team-scale (10-dev) simplification review (§9).
**Current plugin version:** v0.15.0 (`.claude-plugin/plugin.json`). **Version rebase (revision 5):** the plan's original targets v0.14.0/v0.15.0 were consumed by the unrelated Codex and Copilot platform releases. Release A now targets **v0.16.0**; Release B-team targets **v0.17.0**. `scripts/migrate-v0.13.2-to-v0.14.0.sh` already exists (it is the Codex migration) — A8's migration is `migrate-v0.15.0-to-v0.16.0.sh`. All `file:line` references below were computed against the v0.13.2 tree; `bootstrap-espalier.sh` has since grown ~870 → ~1474 lines (e.g. `stage_gitignore` 679 → 1191, config heredoc 531 → 1049, `HOOK_DST` 583 → 1091) — anchor on function names and markers, re-grep line numbers at build time. Validation check IDs 47–51 (codex) and 52–56 (copilot) are now shipped and stable — see A9.
**Companion:** `docs/multi-dev-maintenance-how-it-works.md` — plain-language description of the shipped model for team members.

---

## 0. The idea, briefly

Espalier extracts a knowledge base from a codebase — rules, wiki, skills, an audit trail — and today maintains it with a *single-developer* loop: each clone privately detects drift (gitignored sidecar), and one human runs `/espalier-prune` or `/espalier-doctor` to refresh. With several developers on one repo, that loop breaks in four ways: every clone sees a different staleness picture; nobody owns the shared upkeep (everyone assumes someone else scanned); the shared bookkeeping files merge with conflicts because nothing was designed for concurrent writers; and rule changes made on one branch silently diverge from every other branch's.

This plan makes the maintenance loop **team-shaped** without breaking espalier's core safety rule (no hook ever writes a git-tracked file; every refresh is human-gated):

1. **Make maintenance a scheduled singleton, not a concurrent free-for-all** — one rotating gardener runs doctor + prune once per interval in a single weekly maintenance PR on the integration branch. Concurrency mostly can't happen because only one person maintains at a time; the "everyone assumes someone else scanned" failure dies by rota, not by merge machinery. (Revision 5 — this replaces revision 4's approach of making *any-dev-anytime* maintenance merge-safe via event logs.)
2. **Share the two facts that matter as ordinary tracked files, shaped so git merges them naturally** — the doctor stamp becomes a single-line tracked file with clean/dirty semantics (one writer per interval by construction — the gardener); convention state moves to **one small file per pattern key** (the towncrier/changesets structure the research doc cites as prior art #2), so two branches touching different keys can never conflict, and a same-key race surfaces as an ordinary five-line git conflict — detection by git itself, no fold algorithm.
3. **Make detection deterministic where it matters** (shelved) — content-hash anchors tie each doc to the source files it describes, so "this doc is stale" comes from a hash mismatch any clone can reproduce, not from an LLM re-read.

Shipped in two scheduled releases plus a shelf: **A** = discipline, guards, and the compatibility floor (docs/config/one helper — safe immediately); **B-team** = the gardener workflow + the two shared-state files above; the **event-log machinery (revision 4's B-minimal), full checkpoint design, and hash anchors stay shelved** — already-reviewed specs to be built only against measured need, not on schedule.

---

## 1. Release strategy

| Release | Contents | Why this order |
|---|---|---|
| **A — v0.16.0** | Discipline + guards + compatibility floor: per-mechanism maintenance lanes incl. promotion (R3, gardener-shaped), CODEOWNERS (R4), slug-collision recipe (R5), `.gitattributes` for `.ask-gaps.tsv`, executable width-tolerant conventions reader (`conv_fold`), unattended Stage 0 gate, worktree-correct hook install + validation, migrate barrier | Docs/config/one-bash-helper work; no new state files; the reader ships before B's per-key writer exists, so B lands against an already-tolerant reader. |
| **B-team — v0.17.0** | §4: weekly gardener rota + Stage 0 defaults; `.doctor-stamp` single-line tracked file with clean/dirty semantics; conventions → file-per-key under `espalier/conventions/` (same row format as today); tracked-doctor lane discipline | The smallest increment that closes G2 (doctor diffusion) and G3 (conventions merge unsafety) — structurally, via singleton scheduling + per-key isolation, instead of via event-log machinery. |
| **Shelf (unscheduled)** | Revision 4's B-minimal event-log package (8-col schema, union conversion, format marker, event `conv_fold` API); §5 full event-log machinery (checkpoint, tombstones, Stage 7 publish, rotation, basis ids); §6 anchors (R6/R7); R8/R9 (incl. `verified` rows)/R10 | Built only against the measured triggers in §3.5 — not on schedule. |

Binding invariants: **no hook writes a tracked file**; **refresh is never silent**; **bash-3.2 safe**; BSD/GNU portability via the existing `uname` branch idiom; every shipped mechanism gets a deterministic red-first test.

---

## 2. Release A (v0.16.0) — components

### A1. `.gitattributes` union entry — one file, genuinely append-only

Extend `stage_gitignore()` (`bootstrap-espalier.sh`, `stage_gitignore` — was :679, now ~:1191) with the same per-line idempotency pattern (`grep -qxF` + newline guard) against `.gitattributes`. Stage log becomes `Stage 10: .gitignore/.gitattributes/CODEOWNERS append` (A4 folds in here — no stage renumbering anywhere; verified against v0.15.0: Stage 10 is still the gitignore append, Codex/Copilot landed as 7b/8b/8c/7c/8d/8e). Entry in A:

```gitattributes
espalier/.ask-gaps.tsv merge=union
```

**That is the only union attribute in the shipped scope** (revision 5 — narrowed from two):
- **`.conventions.tsv` is deliberately NOT here.** Its writer still edits status fields in place (`espalier.md:95,101-102`); union-merging an in-place-edited file is the exact resurrection bug the research doc §3 G3 describes. B-team never unions it either — the file becomes read-only legacy and new state moves to per-key files merged by ordinary 3-way merge (§4 B-3).
- **`.doctor-runs.tsv` is gone from A** — revision 5 replaced the append-only run log with a **single-line** `.doctor-stamp` file (§4 B-1). Union on a single-line last-writer-wins file would *corrupt* it (both lines survive), so no attribute may ever be added for it.
- **`.drift-checkpoint.tsv` is not here either** — that file belongs to the shelved full-B design; carrying a mandatory attribute (and migration/validation requirements) for an unscheduled feature is dead configuration.

The generated `development-process.md` paragraph (A3) carries the research doc's caveat: GitHub's web conflict UI ignores custom merge drivers — resolve union-file conflicts locally.

**Acceptance:** re-run adds nothing twice; pre-existing `.gitattributes` content untouched outside appended lines; `--dry-run` truthful.

### A2. Canonical-ref config keys + executable conventions reader

**No format-version marker (revision 5 — deleted).** Revision 4 shipped `espalier-format: 1` to gate the B-minimal schema conversion. B-team changes **no on-disk row format anywhere** — per-key files reuse the existing 5/6-col row schema (§4 B-3), the legacy `.conventions.tsv` is never rewritten, and the doctor stamp is a new file no old writer touches. With nothing for a marker to gate, shipping one is the same dead configuration this plan refuses to carry for the shelved checkpoint (A1's own argument). If the shelved event-log package is ever built, the marker ships *with* it — writers first, then their guard.

**Config keys.** The `.espalier-config` heredoc (`bootstrap-espalier.sh`, `ESPALIERCFG` heredoc — was :531, now ~:1049) is `<<'ESPALIERCFG'`-quoted — no interpolation — and the v0.9 migration extracts its text literally (`migrate-v0.9.0-to-v0.9.1.sh:96-100`). So the two dynamic canonical-ref keys (A3: `canonical-remote`, `canonical-branch`) are appended after the heredoc with newline-guarded `printf`. The preserve-if-exists branch gains append-missing-key for both. Both config-doc mirrors updated: `templates/agent.md` (config index) and `references/wiring.md`.

**Reader helper — executable, not prose.** New function `conv_fold` in `drift-helpers.sh` (single source of truth for reading convention state; prose instructions can't be tested red-first):

- Reads the legacy `espalier/.conventions.tsv` when present: `NF==5 || NF==6` → key=`$3`, status=`$5` (`diverges` rows count as observations); any other width → skipped, never fatal.
- Reads every `espalier/conventions/*.tsv` when the dir exists (§4 B-3 — **same 5/6-col row format**), summing with legacy rows per key. Must be empty-glob safe (bash 3.2 iterates the literal `*.tsv` pattern when nothing matches — guard with an existence test).
- **Read-time observation dedupe on `(slug, key, location)` across BOTH sources** — writer-side dedupe (B-3) can't prevent the cross-branch double: branch X's new-plugin append lands in the key file while branch Y's old-plugin append of the same observation lands in the legacy file; both merge, and without read-time dedupe the promotion count inflates.
- **Status precedence, deterministic without clocks:** if the key's per-key file contains any status row (non-`diverges`), that status wins; the legacy file's status is consulted only when the key file has none. Rationale: v0.17+ writers never touch the legacy file, so a legacy status can only be an *old* decision (pre-conversion) or an old-plugin branch's flip — honored exactly until a per-key decision exists, never after. No timestamp ordering needed.
- Emits `key<TAB>diverges_count<TAB>current_status` per key; a `conv_observations <key>` accessor returns the evidence rows (the promotion prompt needs rows, not counts). Callers stop parsing files themselves.
- In A the per-key dir doesn't exist yet — the helper simply folds the legacy file. That's the readers-first contract, achieved with one reader that never changes when B lands, and no version marker.

**Call-site inventory (all become `conv_fold` consumers):** Stage 0 promotion-candidate scan (prose block, `espalier.md`, "Stage 0 Pre-Flight") and its `espalier-fix.md` mirror; the Convention Promotion section (`espalier.md`, "Convention Promotion"); the Stage-4 existing-key reader (`cut -f3`, `espalier.md` ~:442 region) **and its `espalier-fix.md` duplicate**; validation **check #27** (conventions-shape check) gains the per-key-dir case: dir absent → pass; dir present → every file passes the same width guard.

**Acceptance:** `test-hooks.sh` fixture — a mixed 5/6-col + malformed-row legacy file, with and without a per-key dir alongside, folds to the right counts (red-first).

### A3. Branch discipline (incl. promotion), canonical ref, race guard, unattended gate (R3)

**Canonical ref.** Detection (in the config-writing stage, values `printf`-appended per A2):

```bash
git remote | grep -qx upstream && R=upstream || R=origin
REF=$(git symbolic-ref --short "refs/remotes/$R/HEAD" 2>/dev/null)   # e.g. origin/release/1.x
B=${REF#"$R"/}; [ -n "$B" ] || B=main    # strip exactly the remote prefix — a blanket 's|.*/||' would destroy release/1.x
```

**Discipline text — per-mechanism lanes, gardener-first (revision 5 rewrite).** The integration-branch rule is not uniform; each mechanism gets the lane its failure mode actually needs:

| Mechanism | Lane | Why |
|---|---|---|
| **Doctor** | Weekly maintenance PR only (gardener, §4 B-2) | The shared stamp's whole value is team visibility; a stamp on a feature branch strands until merge — G2 returns "wearing an 'it's in git' costume" (research §5 R3). |
| **Prune** | Weekly maintenance PR by default; **feature-branch escape hatch** when the dev's own flag is critical/expired — as its own isolated `docs:` commit, covered by the conflict recipe | One prune per interval makes cross-branch prune conflicts (G4) ~impossible by scheduling; the escape hatch keeps a blocked dev unblocked, and `checkout --theirs` + re-prune makes the residual recoverable. |
| **Promotion** | **Feature branch is fine** — own isolated commit; CODEOWNERS routes the rules-touching PR to the owner either way | The deciding dev has the context; the ownership gate binds at merge regardless of source branch; the same-key race is caught structurally by the per-key file conflict (§4 B-3) plus the fetch guard below. Revision 4's "defer to integration branch" default is dropped. |

This text goes into `espalier-prune.md`, `espalier-doctor.md`, **and the Convention Promotion sections of `espalier.md` + `espalier-fix.md`**, plus the maintenance-PR path for contributors without push access. In A the doctor part ships as forward-reference prose only (in A it still writes no tracked file — `espalier-doctor.md` is report-only with a local stamp); the enforceable lane lands with the tracked stamp in B-team (§4).

**No writer-side format guard (revision 5 — deleted with the format marker).** A-era and B-era writers coexist safely without one: B never rewrites the legacy `.conventions.tsv`, so an old-plugin branch that appends or in-place-flips legacy rows stays readable forever — `conv_fold` folds legacy statuses with the same weight as per-key statuses. Old branches degrade gracefully instead of being refused. Residual: two *old-plugin* branches can still conflict on the legacy file exactly as today; accepted — that population only shrinks.

**Conflict recipe.** As revision 1 (inspect both sides → `checkout --theirs` → re-prune; modify/delete resolves as deletion) — into `espalier-prune.md` + one paragraph in `pipeline.md`.

**Ergonomics — the discipline should be done FOR the user, not BY the user.** The worktree flow is the gardener's tool and the escape-hatch fallback: *"run in a temporary worktree of `<canonical-branch>` and push the maintenance commit?"* — mechanically: `git worktree add <tmpdir> <canonical-branch>` → doctor/prune there (normal gates) → commit/push (or open the maintenance PR when the branch is protected — at 10 devs assume it is) → `git worktree remove` → suggest `git rebase` when the user wants the fresh doc. No stash, no branch switch, feature checkout untouched. Skill-text only, no new machinery. Revision 5 note: revision 4 listed "batch-weekly gardening" as an unbuilt documentation rung — it is now the **core of §4 B-2**, not a footnote. The remaining future rung stays future: a scheduled CI job running doctor/prune-report and opening the maintenance PR itself (the PR is the human gate, so "never silent" holds — needs LLM-in-CI, revisit when a team asks).

**Race guard (corrected).**

```bash
R=$(grep '^canonical-remote:' espalier/.espalier-config | awk '{print $2}')
B=$(grep '^canonical-branch:' espalier/.espalier-config | awk '{print $2}')
if git fetch --quiet "$R" "$B" 2>/dev/null; then
  git show "FETCH_HEAD:espalier/.conventions.tsv" 2>/dev/null \
    | awk -F'\t' -v k="$KEY" '(NF==5||NF==6) && $3==k && $5!="diverges" {found=1} END{exit !found}' \
    && SKIP_PROMPT=yes    # surface the existing canon decision instead of prompting
else
  echo "WARN: cannot fetch $R/$B — race guard skipped"   # and do NOT read a stale tracking ref
fi
```

(FETCH_HEAD, not `$R/$B` — a source-only fetch doesn't update the tracking ref; a fetch failure must skip the check, not consult stale state. Width guard so a malformed row can't satisfy `$5!="diverges"` vacuously. In B-team the check gains the per-key file: `git show "FETCH_HEAD:espalier/conventions/k-$(conv_slug "$KEY").tsv"` first — the same slugify helper the writer uses (B-3), a single-file read, simpler than the legacy scan — falling back to the legacy awk for pre-conversion keys. The guard stays a courtesy pre-check, not the race defense: the structural defense is that a same-key concurrent promotion becomes an ordinary git conflict in that key's file, §4 B-3.)

**Unattended Stage 0 gate — per-lane continuation.** Both Stage 0 blocks: `interactivity_mode` = `unattended` → write the three-signal summary to `.drift-report.md`, print one line, and continue — `/espalier` to Stage 1, **`/espalier-fix` to its own Stage 0 Auto-Link Discovery** (`espalier-fix.md:266-290`; "proceed to Stage 1" is wrong for the fix lane). Never prompt, never prune, never promote.

**Process rule.** `templates/rules/development-process.md` "Maintenance commits" paragraph (discipline + rules-PR review expectation + the union web-UI caveat), inserted as its own `## Maintenance Commits` section with a stable HTML marker comment for the A8 surgical append.

### A4. CODEOWNERS generation (R4)

Folded into Stage 10 (A1) — no new stage number. Revision 5, team-scale note: at ~10 devs CODEOWNERS + "Require review from Code Owners" branch protection is **the** rule-canon gate (promotion now legitimately rides feature PRs, A3) — the generated `development-process.md` text and the how-it-works doc state plainly that without branch protection the file is advisory and the team should turn protection on. Wiring, fully specified:
- **Inputs:** two bootstrap flags `--codeowners-rules=<handle>` `--codeowners-wiki=<handle>`, parsed in the arg block (`bootstrap-espalier.sh:68-92` region); both empty → sub-step no-ops with a log line. Dispatch: runs wherever `stage_gitignore` already runs (full init and any mode that reaches Stage 10) — the `main` dispatch at `bootstrap-espalier.sh:841-868` needs no new entry.
- **Question:** `skills/espalier-init/SKILL.md` Phase 0 (currently three questions, `:123-198`) gains skippable Q4 collecting both handles; the bootstrap invocation block (`:281-295`) passes them through. Handles normalized (`@` prefixed if missing); no placeholders — unanswered handle → line omitted.
- **Target file:** first existing of `.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS` — **GitHub's search order** (revision 1 had root-first, which would edit a file GitHub ignores when `.github/` exists); none → create `.github/CODEOWNERS`.
- Marker block (`# >>> ESPALIER OWNERS v1 >>> … <<<`), replace-within-markers on re-run; `--dry-run` line; log: enforcement is advisory until branch protection is confirmed — not verified here.

**Acceptance:** run twice → one block; content outside markers untouched; skip path writes nothing; dry-run truthful.

### A5. Slug-collision recipe + forward-link rewrite (R5)

Unchanged from revision 1: `espalier-fix.md` Step 11 (~:173-217) cross-branch note + `pipeline.md` recipe (rename dir, `rebuild-commit-index.sh`, **grep-and-rewrite old slug in every `## Follow-up Fixes` table in the same commit**).

### A6. Worktree-correct hook install — AND validation

- Install: replace the hardcoded `HOOK_DST=".git/hooks/post-merge"` branch (`bootstrap-espalier.sh:583-586`) with `HOOK_DST="$(git rev-parse --git-path hooks)/post-merge"`; parent-check adjusted. The husky and `core.hooksPath` branches (580-616) untouched — `--git-path` is only reached when neither applies.
- **Validation check #20 (`bootstrap-espalier.sh:792`) resolves the hook path the same way** — otherwise a linked-worktree bootstrap installs correctly and then fails its own validation.

**Acceptance:** `test-bootstrap.sh` case — `git worktree add`, wire from the linked worktree, assert dispatcher installed **and** full validation passes there.

### A7. Migrate barrier (enforced, not recommended)

`skills/espalier-migrate/SKILL.md` pre-flight, before any apply: `git status --porcelain` clean (abort otherwise); scan `espalier/changes/*/*/pipeline-state.md` — a change is in-flight unless `- Status:` matches the **terminal-status regex reused from `pre-push-gate.sh:25-52`** (missing/unrecognized status = active — fail closed) → abort with "finish or abandon first"; current branch must equal `canonical-branch` (or the user passes an explicit acknowledge flag) — enforced, not recommended (research §5 rollout item 3). Replace `git add -A` (`SKILL.md:660`) with "stage exactly the files each script reports".

### A8. Migration step `v0.15.0 → v0.16.0`

New `scripts/migrate-v0.15.0-to-v0.16.0.sh`, appended to the chain **after the shipped `migrate-v0.14.0-to-v0.15.0.sh`**. (Revision 5: the revision-4 filename `migrate-v0.13.2-to-v0.14.0.sh` is unusable — it already exists as the Codex platform migration.)
- **Detect — every mandatory marker, not a proxy subset:** the `.gitattributes` line AND both canonical keys AND the `## Maintenance Commits` marker in `espalier/rules/development-process.md` AND the current prune/doctor/espalier/espalier-fix/pipeline text markers. Rationale: earlier chain steps run the *current* bootstrap with `--force` (`migrate-v0.9.1-to-v0.9.2.sh:188-199`), which after a plugin upgrade can pre-install the config/attribute artifacts — a two-marker detector would then skip the still-missing surgical rule edit. Alternative accepted: a dedicated completion marker written only after all non-optional operations verify.
- **Apply (idempotent, `--dry-run`/`--yes`, prints every touched path incl. side-effects):** append missing attribute line + config keys (canonical detection per A3); re-copy the changed pure-copy files **with backup-on-diff** (`<file>.pre-v0.16.bak` — the established migration convention, `migrate-v0.9.1-to-v0.9.2.sh:161-186`; revision 1's "no backup needed" contradicted it); surgical append of the Maintenance Commits section to `development-process.md` — **anchor: end-of-file append with the marker comment; skip if marker present; abort-with-notice if the file is missing** — backup `<file>.pre-v0.16.bak`; re-wire hooks via `--wire-only` **passing the required `--merge-decision` flag** read back from `espalier/.merge-hook-decision`, and list the settings-backup side-effect in the report.
- **CODEOWNERS:** the migration **skill** collects the two handles up front (interactive step in SKILL.md, before apply) and passes `--codeowners-*` flags into the script — the runner invokes every script `--yes` (`espalier-migrate/SKILL.md:590-628`), so the script itself must never prompt. Unattended: skipped.

### A9. Validation checks — two new base checks as IDs 57–58 (revision 5 rewrite)

Revision 4's "new checks 47–49" is dead: **IDs 47–51 (codex) and 52–56 (copilot) shipped in v0.14.0/v0.15.0** (`bootstrap-espalier.sh:1380-1398`) and the total is now platform-dependent (`TOTAL_CHECKS=46` base + 5 + 5, `:1218-1221`; banner strings say `46/51/56`). Shipped IDs stay stable — the plan's own principle — so the new **base** checks append *after* the platform blocks with fixed IDs:

- **57** gitattributes-union (the one A-scoped `.ask-gaps.tsv` line)
- **58** canonical-ref keys non-empty

(The revision-4 `espalier-format` check is deleted with the marker, A2. CODEOWNERS: no check — optional feature.) Base IDs become non-contiguous (1–46, 57–58) — cosmetic; stability wins. Checks 57–58 run unconditionally (base), regardless of `--platforms`.

Totals become `48/53/58`; update via a grep sweep for the literal totals and banner strings (`46`, `46/51/56`) in `bootstrap-espalier.sh` — known sites at v0.15.0: `:30`, `:64`, the `TOTAL_CHECKS` block `:1218-1221` — plus any output-range labels, and `test-bootstrap.sh` denominators, all in the same commit. Keep the `38-46` Phase-2 subgroup label. (The revision-4 `4[0-6]` output-glob site no longer exists — re-grep rather than trusting this list; the greps are normative.)

### A10. Tests (red-first)

Baselines measured now, not quoted from changelog: `test-bootstrap.sh` ≈ 64 top-level assertions, `test-hooks.sh` ≈ 55 (incl. `run_count_case` and wrapper-case expansions) — re-grep at build time; the numbers in this doc are informative, the greps are normative.

- `test-hooks.sh` adds: `conv_fold` matrix (legacy widths, malformed, mixed; with and without a per-key dir alongside) — the executable-helper decision (A2) is what makes red-first possible here.
- `test-bootstrap.sh` adds: gitattributes idempotency (2), config keys present + preserved + printf-appended after quoted heredoc (3), CODEOWNERS write/skip/idempotent (3), worktree install + validation (2), totals say 48/53/58 per platform set (1).
- **Migration test (PR-template requirement — synthetic fixture is mandatory, `.github/PULL_REQUEST_TEMPLATE.md:25-30`):** build a synthetic v0.15.0 tree, run the migration `--dry-run` (assert no writes), apply (assert every marker), re-run (assert no-op), and a partial-apply case (pre-seed the config keys, assert the surgical rule edit still lands).
- A3's prompt-flow behavior (race guard, unattended continuation) can't be unit-tested mechanically: covered by grep-assertions on generated skill text (the six insertion points) + one manual unattended sim in the release checklist. Recorded as a deliberate exception to the deterministic-test invariant.

### A11. Release chores

CHANGELOG; README; `espalier-migrate` frontmatter description; init SKILL.md Output Structure notes if touched; version bumps in `.claude-plugin/plugin.json` + `marketplace.json`.

---

## 3. Release A build order

1. A10 red tests → 2. A2 `conv_fold` + config keys → 3. A1 gitattributes → 4. A6 hook fix + check #20 → 5. A3 six insertion points + snippets → 6. A4 CODEOWNERS sub-step → 7. A5 recipe → 8. A9 checks 57–58 + totals sweep → 9. A7 migrate barrier → 10. A8 migration script + fixture test → 11. A11 chores.

---

## 3.5 Minimalism review (revisions 3–4)

A deliberate simplicity pass over the accumulated spec (adversarial rounds only ever *added* machinery; this pass deletes), itself externally audited (15 findings — §9). Verdict: **Release A is proportionate; the full Release B event-log design is over-engineered for the real workload** (2–10 devs, a few drift flags a week, weekly doctor, occasional prune — the failures it prevents are soft: a duplicated 3-minute scan, a 30-second TSV conflict, a wrong tier for a few days). The repeated correctness bugs found *in the B machinery itself* across reviews are the tell.

Existing coverage, stated precisely (the revision-3 wording overstated both): **hook-enabled, merge-based pulls** re-derive the mechanical flags from the same merged diffs (rebase-pullers and unbootstrapped clones do not — known, accepted since v0.5.0); a teammate's committed prune leaves phantom local rows that clear **on that clone's next explicit prune** (the empty two-way diff path), not automatically on pull.

**What the shipped B keeps and why:** the two failures with no existing mitigation at all are doctor diffusion (G2 — no shared "a scan happened, and was it clean" fact) and the union-unsafety of `.conventions.tsv`'s in-place status writer. §4 ships exactly those two fixes.

**Revision 5 — the minimalism pass applied to B-minimal itself (2026-08-03, targeting ~10 devs).** Revision 4's B-minimal still solved G2/G3 with merge machinery — event schemas, union folds, tie-breaks, skew rejection, a format marker with writer guards — so that *any dev could maintain at any time, concurrently*. At 10 devs that generality is the wrong target: prune collisions grow with active branch count, docs regenerate from ten diverging feature trees, and the machinery's own audit history kept producing correctness bugs (the §3.5 tell, again). The simpler stance: **make concurrency mostly impossible by scheduling (one weekly gardener), and make the residual concurrency resolve as ordinary small git conflicts by structure (file-per-key)**. Two substitutions follow: the append-only `.doctor-runs.tsv` + fold becomes a single-line `.doctor-stamp` (one writer per interval by construction); the 8-col event conversion becomes file-per-key under `espalier/conventions/` with the *existing* row format (the towncrier/changesets structure the research doc itself cites as prior art #2 but never applied here). The format marker and writer guards die with the schema change that motivated them. Same trade the revision-3 descope made — soft failures accepted, machinery deleted — taken one step further. Revision 4's B-minimal spec is preserved on the shelf (§5.0) as the escalation path.

**Shelved as one dependent package** (each piece only makes sense with the others): `.drift-checkpoint.tsv` flag events, causal tombstones, `event_at`/`first_seen_at`, Stage 7 flag publishing, generation rotation, basis-id race reconciliation. Accepted residuals while shelved: clone-divergent tier ages; reviewer/ask flags stay clone-local (a deleted worktree loses them; the weekly doctor is the imperfect backstop); the promotion race is **detection-only — CODEOWNERS review is NOT a race guard** (it's optional, advisory without branch protection, and cannot expose a concurrent open PR); detection is the fetch guard plus, from revision 5, the structural per-key conflict (§4 B-3 — two same-key decisions collide in one small file at merge); the rule-owner checklist still includes "fetch canonical state and check for concurrent rule PRs before approving" because neither detector sees two PRs that are both still open. **Activation triggers, measurable not vibes:** revisit the checkpoint package if clone-divergent staleness causes a wrong merge/approval twice in a quarter; revisit anchors (§6) on a quarterly sample — compare doctor/prune discoveries against hook-flag coverage, and escalate after a defined false-negative count or one material incident (silent misses never self-report, so the sample is scheduled even though the build isn't). Generation rotation is deleted outright — ~52 doctor stamps/year and <100 convention rows/year need no log maintenance at all.

## 4. Release B-team (v0.17.0) — normative (revision 5)

**B-1. `.doctor-stamp` — shared doctor stamp, single line, honest completion semantics.**
Tracked, **one line**, last-writer-wins whole-file — deliberately NOT append-only, NOT union (union on a single-line file corrupts it into two lines; no `.gitattributes` entry may ever be added for it). Line: `ts<TAB>sha<TAB>writer<TAB>result` where `result` = `clean` or `dirty:<N>` (flag count at scan end — the doctor knows it, `stale_files` is in hand). Written only by the doctor, as its own commit, in the weekly maintenance PR lane (A3) — tracked-doctor discipline lands HERE, the release where the doctor first has something to commit. Semantics kept from revision 4 (the one cut-too-deep lesson): `doctor_due()` v2 is satisfied team-wide only by a `clean` stamp; a `dirty` stamp satisfies only the writing clone (via its existing gitignored local stamp, which the doctor keeps writing) — **a shared stamp must never mean "scan complete" while the findings sit untracked on one clone.** Reject-and-warn a `ts` beyond now + 25h skew (kept — one awk line; a future-dated stamp must not stay permanently freshest; a rejected stamp reads as absent → due). **The stamp records the state at the end of the maintenance session, not the first scan:** if the same session's prune clears every finding, the gardener re-runs the doctor (fast on a now-clean tree) and the PR carries a `clean` stamp — otherwise a `dirty:N` stamp whose N findings were already fixed in the same PR would keep `doctor_due()` firing team-wide forever (deadlock: maintenance done, nag never stops). The doctor stays the stamp's only writer. Conflict story: two doctors in one interval is a rota failure, rare by construction; if it happens the conflict is one line vs one line — documented resolution: keep the newer line (or either `clean`). No fold algorithm, no event ids, no tie-breaks, no rotation.

**B-2. Weekly gardener rota + Stage 0 defaults — the workflow that makes B-1/B-3 sufficient.**
- **The rota (social, documented — the `## Maintenance Commits` section from A3/A8 gains this text in B):** one rotating dev per cadence interval is the gardener. Their loop, ~15 min: worktree of `canonical-branch` (A3 ergonomics flow) → `/espalier-doctor` → `/espalier-prune` over flagged files → **if prune cleared every finding, re-run `/espalier-doctor` so the stamp says `clean`** (B-1 end-of-session rule) → one maintenance PR (`docs: weekly espalier maintenance`) containing the stamp commit + refresh commits. CODEOWNERS routes any rules-touching part to the owner automatically. On protected integration branches (assume protected at ~10 devs) the PR *is* the lane — required-review settings mean any teammate approves the routine parts (documented friction, ~1 min of someone's week); with direct-push rights the worktree flow pushes straight.
- **Stage 0 defaults flip (both `espalier.md` and `espalier-fix.md` blocks):** for non-gardeners the pre-flight default becomes **"Proceed"** with a one-line pointer — "weekly maintenance handles this (gardener rota)". "Handle now" remains available and stays the default only when the dev's **own** flag is critical/expired (the A3 escape hatch). Unattended behavior unchanged from A3 (write summary, continue per lane, never prompt/prune/promote).
- Payoff: nine of ten devs stop seeing maintenance pressure entirely; exactly one scan and at most one prune sweep per interval; "someone else surely ran it" dies because the rota names who.

**B-3. Conventions — file-per-key under `espalier/conventions/`** (one release unit with its skill-text edits):
- **Structure:** one `espalier/conventions/k-<key-slug>.tsv` per `pattern_key`; `key-slug` = the canonicalized `pattern_key` with `/`, whitespace, and any non-`[A-Za-z0-9._-]` mapped to `_` (empty result → `_`). The fixed `k-` prefix is load-bearing: it keeps a key like `aux`, `con`, or `nul` from producing a Windows-reserved filename that breaks every Windows checkout of the repo, and rules out leading-dot/dash surprises. Filename is routing only — rows carry the real `pattern_key` in column 3 and `conv_fold` folds by column value, so two keys that sanitize to the same slug merely share a file (cosmetic, counts stay correct). Rows keep the **existing 5/6-col format** (`date, slug, pattern_key, location, status[, coupled_with]`) — A2's `conv_fold` already reads the dir; no new schema, no format marker.
- **Writer:** `append_convention` v2 targets the key's file (creates dir/file on first write — no `.gitkeep`, no migration artifact); filename via a shared `conv_slug` helper in `drift-helpers.sh` (one implementation — writer, race guard, and any future reader all call it); dedupe on `(slug,key,location)` checks the key file AND the legacy file. Status transitions (Promote/Reject/Exception) edit rows **in that key file in place** — now safe: the file is small, single-concern, ordinary 3-way merged; the in-place-flip text moves from "edit `.conventions.tsv`" to "edit the key's file". Concurrent same-key promotion on two branches = a visible git conflict in a ~5-line file — **that conflict is the race detection** (better than the fetch guard: git can't skip it when the fetch fails). **Honest cost, stated:** concurrent same-key *observation appends* also conflict (both sides add a line at EOF of the same small file — git cannot auto-merge adjacent adds; `merge=union` is NOT the fix, because the same file receives in-place status flips, the §3 G3 resurrection combination). Resolution is one documented line in the conflict playbook: *keep both lines*. Accepted as soft — different-key traffic (most of it) never conflicts at all, and a flip on one branch vs an append on the other merges clean (non-overlapping hunks). Escalation if same-key append conflicts recur in practice: split each key into a pure-append observations file (union-safe) plus a single-line status file — shelved, not shipped.
- **Legacy `.conventions.tsv`:** read forever (`conv_fold` sums it), **written never** by v0.17+ writers; no data migration, no rewrite of history. Old-plugin branches keep appending/flipping it and stay honored (A3 coexistence note). Two branches touching *different* keys can no longer conflict at all — that is most real concurrency at 10 devs.

**B-4. Migration `v0.16.0 → v0.17.0`:** re-copy changed pure-copy skills (backup-on-diff, `<file>.pre-v0.17.bak`); no config change, no attribute change, no data migration (per-key dir and stamp file appear on first write). Verify `.gitignore`: the tracked `.doctor-stamp` must NOT match any ignore line — verified against `stage_gitignore()` at v0.15.0 (`bootstrap-espalier.sh:1199-1206`): all six entries are exact strings except `espalier/.drift-state.tsv*`, and none matches `.doctor-stamp`; the gitignored local stamp is the distinctly-named `espalier/.doctor-last-run`. Migration still asserts it at run time (`git check-ignore espalier/.doctor-stamp` must fail) — target repos can carry hand-added ignore lines the template never wrote.

**B-5. Tests (red-first):** `doctor_due` v2 clean-vs-dirty (tracked stamp + local stamp interplay); future-skew rejection (rejected stamp reads as absent); restamp-clean — a session that scans `dirty:N`, prunes all N, re-scans must end with a `clean` stamp (the B-1 deadlock case); one-line conflict-resolution recipe asserted in generated text; `conv_slug` matrix (reserved names `aux`/`con` → `k-` prefixed, `/`/space/UTF-8 mapping, empty → `_`, two keys sharing a slug fold correctly by column value); `append_convention` v2 create/append/dedupe-across-both-files; in-place flip in key file; `conv_fold` legacy-only / dir-only / mixed / malformed / **empty-dir (glob-safety)** / **cross-source duplicate observation counted once** / **precedence: key-file status beats legacy status, legacy status honored when key file has none**; two-clone sim — clone A `dirty` scan does not satisfy clone B's `doctor_due`, clone A `clean` does; two-clone same-key promotion produces a git conflict in exactly that key file and nothing else; different-key concurrent writes merge clean; cross-branch flip-vs-append on one key auto-merges to decided-plus-one-fresh-observation.

**B-6. Acceptance:** all B-5 green (red first); scratch two-clone sim passes; Stage 0 default text present in both lanes; gardener loop executable end-to-end in a scratch repo (worktree → doctor → prune → PR branch with stamp + refresh commits only).

## 5. Shelf — full Release B spec (unscheduled; see §3.5 triggers) — deltas vs revision 1

### §5.0 First rung — revision 4's B-minimal (event-log lite), preserved verbatim-in-substance

Shelved by revision 5 in favor of §4's gardener + file-per-key model. **Un-shelve triggers:** the rota proves socially unenforceable (doctor gap > 2 intervals twice in a quarter); or `.doctor-stamp` one-line conflicts recur despite the rota; or per-key files hit a real scale/tooling wall. It was, twice-audited:

- **`.doctor-runs.tsv`** — tracked, append-only, `merge=union`. Row `event_id, ts, writer, sha, result(clean|dirty:<N>)`; doctor's own commit on the integration branch. Fold: team-wide satisfaction only on `clean`; `dirty` satisfies only the writer clone. Reject-and-warn `ts` beyond now + 25h skew (never `min(ts,now)` clamp — a clamped future stamp stays permanently freshest); equal-`ts` tie-break by `event_id`.
- **Conventions 8-col event conversion** (one release unit — union before writer conversion is the resurrection bug): schema `event_id, ts, writer, kind(observation|promoted|rejected|exception), pattern_key, rule_file, location, slug`; new append helper (observation-only dedupe on `(slug,key,location)`); all status transitions append; in-place flip text deleted; `espalier-format` bumped to 2 in the same commit as `espalier/.conventions.tsv merge=union` (paired with an A-era writer-side guard: refuse in-place flips when the marker exceeds what the writer knows). `conv_fold` event API: file **or stdin** (`git show FETCH_HEAD:… | conv_fold -`), equal-`ts` tie-break by `event_id`, `conv_observations` accessor. Legacy 5/6-col rows read forever (`diverges` → observation). Tests included union-shuffle determinism (`cat ours theirs | sort -R` invariance). Full B (below) adds the ninth `basis` column; readers must then accept mixed 8/9-col history.

All of revision 1's B1–B7 stand, plus these corrections from verification:

- **B0 (new): `.conventions.tsv` conversion package** — writer converted to events, `merge=union` attribute added, `conv_fold` extended, all in one release unit (union before writer conversion = resurrection bug).
- **B3 schema: nine columns, not eight** — `event_id, ts, writer, kind, pattern_key, rule_file, location, slug, basis`; `basis` = comma-joined observation event-ids for status events, empty for observations (the 8-col schema physically couldn't record the decision basis the race-detection contract requires).
- **B2 read-site inventory corrected:** add `harness-security.md:23-26` (direct sidecar read) and the `pipeline.md:171-180` Stage 8.5 mirror; `pre-push-gate.sh:20-23` reclassified — it calls `doctor_due()`, a helper consumer, not a direct read (it upgrades automatically when the helper does).
- **B gains explicit caller units:** doctor/prune checkpoint-publish integration (research R2 makes them the writers — helpers alone ship dead code) and a **writer-side `espalier-format` gate** in every new writer (refuse to append when the marker is newer than the writer knows — the rollout contract's enforcement half).
- **B6 CI policy — recorded supersession:** default stays `warn` (this plan deliberately supersedes the research doc's fail-by-default; rationale: a surprise team-wide CI freeze on upgrade is a worse failure than a warned drift, and `fail` is one config line away). Acceptance criteria updated accordingly; CHANGELOG must state both the change and the opt-in.

## 6. Shelf — anchors (was Release C) — spec delta

- **C3 pending-clear queue defined:** anchor revalidation's "queue a tombstone" writes to a **gitignored `espalier/.pending-clears.tsv`** (`event_id`s + file + reason), consumed and published by the next deliberate step (Stage 7 / doctor / prune). `clear_stale` alone can't carry event-ids (`drift-helpers.sh:48-55` — file/reason only).

## 7. Risks

Revision 1 table stands, plus: partial-apply migration states (mitigated by A8 all-marker detection + the partial-apply test); prompt-flow behavior untestable mechanically (A10 exception, manual sim gated in checklist).

Revision 5 additions:
- **The rota is social, not mechanical.** A skipped gardener week self-corrects (the stamp ages, `doctor_due()` starts nagging everyone again — the pre-rota behavior is the fallback, not a new failure); two intervals skipped twice in a quarter is a §5.0 un-shelve trigger.
- **Feature-branch prune escape hatch regenerates docs from a feature tree** (merged code + the dev's unmerged diff). Usually benign — becomes true at merge; abandoned PR → refresh lost, flag persists, self-heals on next prune. Accepted as soft.
- **Squash-merge safety:** both shared facts are *file contents* (`.doctor-stamp`, per-key files), so any merge style — squash, rebase, merge — carries them. (This is why the stamp is a file, not a `git log --grep` convention — a considered-and-rejected alternative, §9.)
- **Legacy-file conflicts between two old-plugin branches** remain possible until those branches die out; accepted, shrinking population.
- **Same-key concurrent observation appends conflict** (adjacent EOF adds in one small file); resolution "keep both lines" is in the playbook; escalation path (split observations/status per key) shelved in B-3. Different-key traffic — most of it — cannot conflict.
- **B-5's flip-vs-append auto-merge expectation** is an empirical claim about hunk adjacency — the two-clone sim asserts it; if git's merge heuristics disagree on some version, the case degrades to the same keep-both-lines playbook, not to data loss.

## 8. Acceptance checklist (Release A ships when…)

- [ ] All new assertions green, and were red first (incl. `conv_fold` matrix + migration fixture with partial-apply case)
- [ ] Scratch init (claude-only): 48/48; with codex 53/53; with both 58/58; re-run idempotent; output shows checks 57–58
- [ ] Linked-worktree init: dispatcher installed AND full validation passes there
- [ ] Migration (`migrate-v0.15.0-to-v0.16.0.sh`): dry-run truthful, apply complete, re-run no-op, partial-apply completes the surgical edit
- [ ] Six A3 insertion points present in generated skills (per-mechanism lane table incl. promotion-in-feature-branch); manual unattended sim proceeds without prompting (both lanes, correct next stage)
- [ ] CHANGELOG/README/migrate-frontmatter/version bumps done (v0.16.0)

B-team (v0.17.0) ships when: all B-5 green (red first); two-clone sim passes (dirty/clean stamp semantics, same-key promotion conflict, different-key clean merge); Stage 0 "Proceed" default + rota text present in both lanes; gardener loop runs end-to-end in a scratch repo; how-it-works doc updated if behavior drifted.

## 9. Verification log

**Revision 4 → 5 (2026-08-03)** was driven by two forces. (1) **Repo drift:** re-verification against the v0.15.0 tree found the plan's target versions consumed by the unrelated Codex (v0.14.0) and Copilot (v0.15.0) releases — A8's migration filename already exists as the Codex migration, validation IDs 47–56 are shipped platform checks (A9's "checks 47–49" collided head-on), totals are now platform-dependent (46/51/56), the `4[0-6]` output glob is gone, and every `bootstrap-espalier.sh` line reference shifted (~870 → ~1474 lines). Fixed by version rebase (A → v0.16.0, B → v0.17.0), A8/A9 rewrites, and an anchor-on-names-not-lines note. Verified unchanged: Stage 10/11 numbering, the worktree hook bug (`HOOK_DST=".git/hooks/post-merge"` + parent check), the in-place flip text, `git add -A` in the migrate skill, single shared template set across platforms. (2) **Team-scale simplification review (~10 devs):** B-minimal replaced by B-team — maintenance becomes a scheduled singleton (weekly gardener rota + Stage 0 "Proceed" defaults) instead of merge-safe-for-everyone; `.doctor-runs.tsv` (append log + union + fold + tie-breaks) becomes single-line `.doctor-stamp` last-writer-wins, keeping clean/dirty semantics and skew rejection; the conventions 8-col event conversion becomes file-per-key with the existing row format (same-key race surfaces as a git conflict — structural detection replacing fold machinery); the `espalier-format` marker + writer guards die with the schema change that motivated them (A1's dead-configuration argument applied to A2 itself); promotion's "defer to integration branch" default dropped (feature-branch promotion with own commit + CODEOWNERS gate); prune gains a critical/expired escape hatch; the doctor stays integration-branch-only (stamp visibility is the feature). Considered and rejected: `git log --grep` as the doctor stamp (dies under squash-merge; file content survives all merge styles). Revision 4's B-minimal spec preserved at §5.0 with measurable un-shelve triggers. Companion plain-language doc added (`multi-dev-maintenance-how-it-works.md`).

**Revision 5 self-review pass (2026-08-03, same day)** — an adversarial pass over revision 5's own changes before any build. Nine findings, all folded in: (1) **dirty-stamp deadlock** — a session that scans `dirty:N` and prunes all N in the same PR would leave a dirty stamp firing `doctor_due()` team-wide forever; fixed by the B-1 end-of-session rule + gardener-loop restamp step. (2) `conv_fold` lacked **read-time observation dedupe across legacy + per-key sources** (an old-plugin branch and a new-plugin branch can land the same observation in both files — writer-side dedupe can't see across branches). (3) No **status precedence** between a legacy status and a per-key status; fixed clock-free: key-file status wins, legacy honored only when the key file has no decision. (4) Per-key **filenames could hit Windows-reserved names** (`aux.tsv` breaks every Windows checkout) — fixed `k-` prefix + shared `conv_slug` helper; slug collisions declared cosmetic (fold is by column value). (5) Race-guard snippet used the raw key in the `git show` path instead of the slug. (6) Same-key concurrent observation appends **do conflict** (adjacent EOF adds; union is not the fix — same file takes in-place flips, the G3 resurrection combination); stated honestly with the keep-both-lines playbook line and a shelved observations/status split as escalation. (7) Empty-glob unsafety in the per-key reader (bash 3.2 literal-pattern iteration). (8) B-4's gitignore-safety claim was asserted before being verified — now verified against `stage_gitignore()` (`bootstrap-espalier.sh:1199-1206`, exact-string entries, nothing matches `.doctor-stamp`) and additionally asserted at migration run time via `git check-ignore`. (9) Research doc §7 still narrated revision 4's event-log machinery as "the shipped scope" — rewritten to the gardener/per-key model (with the gardener added to the cast), and its Carol checklist + §8 banner updated. B-5's flip-vs-append clean-merge expectation is recorded in §7 risks as an empirical hunk-adjacency claim the two-clone sim must confirm.

**Revision 3 → 4** was driven by a third external audit of the minimalism descope (15 findings, no P0s, none refuted). The cut direction survived (explicit agreement on shelving anchors, basis-ids, and the tombstone package). Material corrections: shared doctor stamps gained clean/dirty semantics (a shared stamp with unshared findings would falsely satisfy the whole team — the one cut-too-deep); the shelved `.drift-checkpoint.tsv` attribute was removed from A1/A8/A9 (the one cut-not-deep-enough); B-minimal was rewritten from a scope note into the normative §4 (8-col schema, `conv_fold` file/stdin API + observations accessor + tie-break, remote-guard replacement as an explicit deliverable, migration, tests, acceptance); the writer-side format guard moved into A so pre-B branches can't in-place-flip a union-merged file; `min(ts,now)` was replaced by reject-beyond-skew (a clamped future stamp would stay permanently freshest); doctor branch discipline moved out of A (nothing tracked to commit there until B-minimal); §3.5's fallback claims were made precise (phantom rows clear on next prune, not on pull; only hook-enabled merge-pulls re-derive flags); the CODEOWNERS-as-race-guard claim was retracted (optional, advisory, blind to concurrent open PRs) in favor of an owner checklist plus documented residual; the anchor trigger became a scheduled quarterly measurement (silent misses never self-report); and the misattributed v0.5 trim precedent was dropped.

**Revision 1 → 2** was driven by an external audit (Codex gpt-5.6-sol, xhigh, read-only repo access; 23 findings, ~279k tokens) plus self-review (3 findings). Every finding was validated against the code before adoption; none were refuted. Material corrections: `.conventions.tsv` union deferred to B (in-place writer); tolerant reader replaced by an executable `conv_fold` that actually understands B's `kind`-based schema; promotion gained the discipline path, not just the guard; race-guard snippet fixed (branch-prefix strip, FETCH_HEAD, fetch-failure skip, width guard); fix-lane unattended continuation corrected to Stage 0 Auto-Link; canonical config values moved out of the quoted heredoc; CODEOWNERS target order corrected to GitHub's actual precedence and wiring fully specified; check #20 made worktree-aware; migrate barrier enforced with the pre-push terminal-status vocabulary; A8 detection hardened against `--force` partial-applies and its interactive step moved into the skill (scripts run `--yes`); validation renumber sweep extended (incl. the `4[0-6]` output glob that would have hidden the new checks); test baselines corrected (64/55, measured); migration fixture test added per the PR template; B2/B3/B6/C3 spec deltas recorded above.
