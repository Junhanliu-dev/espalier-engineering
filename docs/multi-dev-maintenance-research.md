# Maintaining Espalier-Generated Artifacts Under Multi-Developer Work — Research & Proposal

**Status:** research / pre-plan. Not implementation-ready — a v2 plan should pick from §5. Implementation plan exists: `docs/multi-dev-maintenance-implementation-plan.md` — note its §3.5 minimalism review, which first **descoped the R1/R2 event-log machinery to a B-minimal** (doctor-run sharing + conventions append conversion) and then (revision 5, 2026-08-03) replaced B-minimal with **B-team**: a weekly gardener rota, a single-line `.doctor-stamp`, and file-per-key conventions (the towncrier structure from §4 finding 2 applied to `.conventions.tsv`), shelving the event-log package itself; that plan supersedes this doc where they differ. A plain-language companion exists: `docs/multi-dev-maintenance-how-it-works.md`.
**Date:** 2026-07-23.
**Scope:** how the per-project `espalier/` knowledge dir (rules, wiki, skills, specs, hooks, changes, sidecars) stays correct, pruned, and mergeable when several developers work the same repo concurrently.
**Inputs:** full template/hook audit of this plugin (verified file:line), `docs/doc-drift-detection-plan.md` (the shipped v0.5.0 drift design), and external prior-art research (fiberplane/drift, Swimm, towncrier/changesets, ADR lifecycle, CODEOWNERS, Mem0/Zep/LangMem memory-pruning literature, TRACE study on LLM drift detection).

---

## 1. Problem

Espalier's maintenance loop (detect → surface → gated refresh) was designed single-clone-first. The shipped design explicitly accepts this (`doc-drift-detection-plan.md` §8.7, §8.9, §9 "Concurrency: accept lost-update for v1"). With N developers:

- each clone holds a **different picture of staleness** (drift state is gitignored, per-clone);
- tracked append-only files (`.conventions.tsv`, `.ask-gaps.tsv`) become **merge-conflict surfaces** with no merge strategy defined;
- whole-file scout regeneration (`/espalier-prune`) on two branches produces **unmergeable prose conflicts**;
- rule edits via Convention Promotion create **branch-local rule canons**;
- nobody owns the garden — doctor cadence is stamped per-clone, so either every dev scans redundantly or (more likely) everyone assumes someone else did.

## 2. What exists today (verified map)

Detection → state → action, as shipped:

| Layer | Mechanism | State written | Tracked? |
|---|---|---|---|
| A. Post-merge file-diff | `hooks/drift-detect.sh` — 10 path-heuristic triggers (new/removed layer dir, cross-layer rename, schema/route/dep/CI/lint/build-config/script changes), runs via unconditional post-merge dispatcher | `mark_stale` → `.drift-state.tsv` (+ `.drift.log`) | ✗ gitignored |
| B. Reviewer judgment | `harness-reviewer.md` Convention Drift blocks (≥2 evidence files) + Convention Observations; parsed at Stage 4 post-review (only after PASS); orchestrator canonicalizes `pattern_key` | `mark_stale` + `append_convention` → `.conventions.tsv` | ✓ tracked, append-only |
| C. Periodic re-scout | `/espalier-doctor` (`--quick/--full/--since`), cadence in tracked `.doctor-cadence`, last-run in gitignored `.doctor-last-run`, activity-gated | `mark_stale` / `clear_stale`; `.drift-report.md` | ✗ per-clone stamp |
| D. Read-side | Stage 0 pre-flight (stale + ≥3-diverges conventions + doctor-due, one AskUserQuestion); coder/reviewer consult sidecar; Stage 8.5 notify-only; pre-push one-line reminder; validation #25 tiers 14/30/60/90d, `expired` fails | — | — |
| E. Refresh | `/espalier-prune` — the only doc editor. Scout re-run (prompts from shipped `.scout-prompts.md`) → two-way diff → per-class gated apply → `clear_stale`. Phantom rows self-heal ("teammate already refreshed" → clear, no prompt). Never silent unattended | doc overwrite + row clear | docs ✓ tracked |
| F. Q&A byproducts | `/espalier-ask` flags contradicted wiki (`ask-verify:` reason) and appends unanswerable questions to `.ask-gaps.tsv` (no dedup — repeat count = demand signal) | sidecar + gaps | gaps ✓ tracked |

Sidecar inventory and tracked/gitignored split: 6 gitignored (`.drift-state.tsv*`, `.drift.log`, `.drift-report.md`, `.doctor-last-run`, `.drift-overrides.log`, `.commit-index.tsv`), everything else tracked — including `.conventions.tsv`, `.ask-gaps.tsv`, `.doctor-cadence`, `.merge-hook-decision`, `.espalier-config`, `.scout-prompts.md`, all rules/wiki/skills/specs/hooks/changes.

**Load-bearing invariant (keep it):** *no automation writes a tracked file outside a deliberate, committed step.* Hooks write only gitignored sidecars; tracked files change only via pipeline Stage 7 commits or explicit prune/promotion commits. Every proposal below honors this.

### What already works well for teams (don't break)

- **Tracked decisions, gitignored stamps** — `.doctor-cadence` / `.merge-hook-decision` inherited by teammates; per-clone stamps stay local.
- **Prune phantom-row self-heal** — a teammate's upstream refresh retires your stale local row via the empty two-way diff.
- **Date-prefixed change slugs** — matches the researched answer to sequential-ID collisions (MADR moved to date-prefixed names for exactly this reason).
- **Dispatcher pattern** for the post-merge slot — logic lives in tracked `espalier/hooks/*.sh`, so plugin updates propagate.
- **Convention promotion as deliberate edit, not scout re-derivation** — a scout over mixed old+new code reports the mix; it can't decide.

## 3. Multi-dev gap analysis

Ordered by (frequency × blast radius). G1–G3 are the ones a 3+-dev team hits in the first month.

**G1. Drift state is per-clone → the team never shares one staleness picture.**
`.drift-state.tsv` is gitignored by design. Consequences: (a) fresh clone starts blind until its own merges re-derive flags; (b) `stale_first_seen` — the input to the 14/30/60/90d tiers and the hard `expired` validation failure — differs per clone, so the same artifact is `fresh` on one machine and `expired` on another; (c) reviewer/ask/Stage-4 flags (LLM-observed, not re-derivable from a diff) exist **only on the clone that ran the review**; (d) rebase-pulls (`pull.rebase=true`) never fire post-merge, and plain-git teammates who skipped bootstrap have no hook at all — for them the sidecar is permanently empty. The doctor is the designed backstop, which leads to G2.

**G2. Doctor responsibility diffuses.**
Cadence is tracked (shared choice) but the stamp is per-clone. With N devs on `weekly`: N independent scans of the same repo (wasted ~3–8 min each, duplicated flags), or — the usual social outcome — everyone sees the reminder, assumes someone else handled it, and the backstop never runs. There is no "team last-scan" fact anywhere in git.

**G3. Tracked append-only TSVs have no merge strategy.**
`append_convention()` and `/espalier-ask` append rows to tracked `.conventions.tsv` / `.ask-gaps.tsv` from whatever branch is running. No `.gitattributes` exists (verified: zero hits repo-wide), so two branches appending → ordinary conflict in a machine-written file the developer never edited and doesn't understand. Worse: Convention Promotion **edits status fields in place** (diverges → promoted/rejected/exception), so even a union merge would be wrong today — an in-place edit on branch A and an append on branch B can resurrect superseded rows.

**G4. Prune on two branches → unmergeable regenerated prose.**
`/espalier-prune` overwrites a whole wiki/rule file with merged scout output. Two devs pruning the same flagged file on different branches produce two full-file rewrites of LLM prose — git's text merge yields conflict soup, and hand-merging regenerated content is exactly the anti-pattern the external research warns about ("regenerate, don't merge"). Nothing in the skill says where prune should run relative to branches.

**G5. Convention Promotion creates branch-local rule canons.**
Promotion edits `rules/*.md` on the branch that hit the ≥3 threshold. Until merged, other branches' coders/reviewers enforce the *old* rule — reviewer on branch B may emit P1s against a pattern branch A already blessed. Rules are the **Critical** class (Always-loaded, per the drift plan's own severity table), and there is no ownership gate: any pipeline run can mutate them, no CODEOWNERS anywhere (verified zero hits), no required-reviewer convention documented.

**G6. Cross-branch slug collisions.**
`/espalier-fix` collision check is a local glob; two devs fixing similarly-worded bugs the same day on separate branches each pass locally, then collide on `espalier/changes/fix/<same-slug>/` at merge. Rare, discoverable, but no documented resolution.

**G7. The backstop detector is the weakest class of detector.**
External headline (TRACE, arXiv 2604.03447): LLMs detect doc-side errors well but have a **systematic 7–42pp blind spot when the code silently drifts under a still-plausible doc** — precisely the "silent refactor" case the doctor exists to catch. Espalier's mechanical layer (A) is path-regex heuristics; its semantic layer (C/E) is LLM scout re-read + LLM two-way "materially different" judgment. Both team-scale poorly: heuristics under-flag silently, and the LLM backstop is least reliable exactly where it's most needed. Deterministic content-anchoring (fiberplane/drift-style hash of governed source) is the researched fail-closed answer and exists nowhere in espalier.

**G8. Follow-up-fix backlinks append into *another change's* tracked `pipeline-state.md`.**
Cross-branch, that's an edit to a file another dev's branch may also touch. Idempotency key `(slug, role)` prevents same-clone dupes, not cross-branch conflicts. Low frequency; noted for completeness.

## 4. External findings that shape the answer

Condensed to what's load-bearing for espalier (full agent report has URLs; key ones inline):

1. **Deterministic anchors beat LLM re-reads for drift detection.** fiberplane/drift: doc frontmatter anchors → XxHash3 of the referenced symbol's normalized AST, recorded in a lock file; `drift check` exits 1 in CI when the fingerprint changes. LLM used to *repair*, never to *detect*. (TRACE blind-spot result makes this priority #1.)
2. **File-per-atom + regeneration, not smarter merging.** towncrier/changesets eliminated changelog conflicts structurally: one file per change, compiled later. Monoliths maximize conflict surface; regenerated prose should be re-derived on the target branch, never hand-merged.
3. **`merge=union` works only for genuinely append-only, order-independent lines** — and GitHub's web conflict UI ignores custom attributes, so it's a local/CLI convenience, not a guarantee. In-place status edits disqualify a file from union merging.
4. **Event-log + supersede-not-delete** (Zep bi-temporal facts; ADR lifecycle proposed→accepted→superseded): status changes are *new rows/records*, current state = fold over history. Makes union-merge safe and gives free audit trail. Prune = mark superseded, don't delete.
5. **Ownership is a solved problem: CODEOWNERS + required review** on the knowledge dir's critical subpaths; Backstage-style per-area owner + periodic health scorecard for the gardening role.
6. **Reconcile-at-write** (Mem0): when re-extracting, diff the candidate against what exists and update/supersede rather than duplicate — espalier's prune two-way diff already does this; keep it.
7. **Rule files at scale** (Cursor `.mdc` globs / Copilot `applyTo`): file-per-rule with a `governs:` path-scope in frontmatter — which doubles as the **coupling key** for deterministic drift detection and for "code changed but governing rule didn't" CI checks (Danger.js pattern).

## 5. Proposed maintenance model

> **⚠ Partially superseded.** The implementation plan's minimalism review (plan §3.5) descoped this model: R3/R4/R5 and the compatibility floor ship (Release A); the doctor-run log and conventions conversion ship reduced (B-minimal, plan §4); the R2 checkpoint/tombstone machinery, Stage 7 publishing, rotation, and scheduled R6 anchors are **shelved behind measured triggers**. Phase labels like "ship-next-release" below describe the original full model, not the schedule. The plan wins where they differ.

Three phases. Every item states the gap it closes and how it honors the no-hook-writes-tracked invariant.

### Phase 1 — cheap, ship-next-release (P0)

**R1. Make the shared TSVs an append-only event log + union-mergeable.** *(G3)*
- All three transitions — Promote, Reject, Exception — **append a status event**; nothing edits in place. The conventions file moves to an explicit event schema: `event_id, timestamp, writer, kind(observation|promoted|rejected|exception), pattern_key, rule_file, location, slug`. `event_id` = hash of `(writer, timestamp, seq)` — an immutable identity per row (needed by R2's tombstones and R3's race detection). `rule_file` is carried through from the reviewer's Observation (today Stage 4 discards it, appending only slug/key/location — without it the doctor cannot reconcile a folded decision with the rule file it changed). Timestamp is full second-granularity UTC (`_ds_now()` — the current column is day-only, leaving same-day rows unordered) and `writer` = `git config user.email`.
- Readers compute current status = status event with **max timestamp** per `pattern_key` — never file position: `merge=union` output order is unspecified, so any "last row wins" rule is undefined after a merge. Threshold counts `observation` events newer than the latest status event, deduped on `(slug, key, location)` at read time.
- Dedupe applies to **observation events only**. This cannot be a `status` parameter bolted onto `append_convention()` — its existing early dedupe on `(slug,key,location)` would silently no-op a second status change for the same key. New helper, observation-only dedupe.
- Clock sanity: fold clamps any timestamp to `min(timestamp, now)` at read time. (Not "clamp to the carrying commit's authored date": that needs `git blame` per row on every Stage-0/pre-push read, breaks on uncommitted rows and shallow clones — and the authored date comes from the same workstation clock anyway. `min(ts, now)` kills future-skew dominance cheaply; ordering disputes are settled by event-set references, not clocks.)
- `.gitattributes` gets `merge=union` for **all four** shared logs — `.conventions.tsv`, `.ask-gaps.tsv`, and R2's `.drift-checkpoint.tsv` + `.doctor-runs.tsv` (the first draft listed only the first two while asserting union behavior for the others).
- `.ask-gaps.tsv` stays pure-append (dup rows are the demand signal — union-safe by design; lifecycle in R10).
- Bootstrap Stage 10 (or a new stage) writes `.gitattributes` entries:
  ```gitattributes
  espalier/.conventions.tsv merge=union
  espalier/.ask-gaps.tsv    merge=union
  ```
  Document the GitHub-web-UI caveat (resolve locally). Reader-side dedupe on exact row makes double-landed lines harmless.
- Invariant: unchanged — these files are still written only by pipeline/deliberate steps; only the merge behavior changes.

**R2. Team drift checkpoint — share state without letting hooks touch tracked files.** *(G1, G2)*
- Two new tracked files, both **pure-append event logs** — explicitly NOT the sidecar's schema or write pattern: `mark_stale()` is a delete-then-append upsert, which is exactly the in-place-edit pattern that disqualifies a file from union merging. A distinct append-only helper writes these; both are **written only by `/espalier-doctor` and `/espalier-prune`** as part of the commits they already suggest. Hooks keep writing the gitignored sidecar exactly as today.
  - `espalier/.drift-checkpoint.tsv` — `event_id, event_at, first_seen_at, writer, event(flag|cleared), file, stale_since_sha, reason`. Two timestamps because they answer different questions: `event_at` orders the log; `first_seen_at` preserves the *original* local observation time when a sidecar flag is published (a single-timestamp schema silently resets tier age on publish — dev A could see `expired` while every teammate and CI folds `fresh` forever). A `cleared` tombstone **enumerates the `event_id`s it retires** — the exact active flag events the prune/doctor observed and validated against. Not sha-keyed: doctor and ask both stamp flags with the *current* HEAD at scan time, so one sha neither identifies a flag occurrence nor distinguishes a pre-prune flag from an identical post-prune re-flag. Event-id enumeration gives real causality: a re-flag appended after the prune has an id the tombstone doesn't list and survives; every flag the prune actually saw is retired, whatever its sha.
  - `espalier/.doctor-runs.tsv` — `timestamp, sha, writer` per doctor run, plus optional per-artifact `verified <file>` rows (see R9); `doctor_due()` reads the max (clock-clamped per R1).
- **One fold algorithm, defined once, implemented inside the helpers** (`classify_tier`/`stale_files` in drift-helpers.sh), not bolted onto one call site: per file, latest un-retired `flag` event wins; `stale_first_seen` = min `first_seen_at` across local sidecar + checkpoint; tier from that age. This placement is load-bearing — `tier_counts()` calls `classify_tier()` per file, and `classify_tier` today reads only `$DRIFT_STATE`, so a checkpoint-only flag (a teammate's) would be listed by a patched `stale_files()` yet silently vanish from tier counts. And helpers alone don't finish the job: the coder `cut`s the sidecar directly, the reviewer greps it, Stage 8.5 reads the local reason column, and validation #25 has its own parser — so the helpers must also grow `stale_records`/`stale_reason` accessor functions and **every direct sidecar read is replaced with them** (enumerated: Stage 0 pre-flight, harness-coder pre-code check, harness-reviewer pre-flight, Stage 8.5, pre-push reminder, check #25).
- **Reviewer/ask flags need an explicit publish step — they do not propagate for free.** Only doctor/prune write the checkpoint, but Stage-4 reviewer flags and `/espalier-ask` flags land in the gitignored sidecar; without a publish path, "LLM-observed flags propagate" is false — a `git clean` or deleted worktree loses the only copy. Fix inside the invariant: Stage 7 (already a deliberate, committed step that stages `.conventions.tsv`) also **publishes the pipeline run's own pending sidecar flag events** into the checkpoint. Ask stays read-only; its flags remain local until the next pipeline/doctor/prune publishes them — stated as a documented latency, not a hole.
- **CI behavior change, stated loudly:** today a fresh CI clone has an empty gitignored sidecar, so validation #25 effectively never fires in CI. A tracked checkpoint changes that: one team flag older than 90 days hard-fails `--validate-only` on **every PR**. This is kept as a deliberate forcing function, but the rollout must say so and ship the playbook: the remediation is a standalone prune PR on main; `--ignore-drift` (audited) is the documented temporary override when branch protection would otherwise deadlock the remediation PR against the failing check itself.
- Stage 7 gains a staging line for `.drift-checkpoint.tsv` beside the existing `.conventions.tsv` one, so a doctor/prune landing mid-pipeline can't leave the Stage 7 clean-tree gate facing an unexplained dirty file.
- **No in-place compaction — union merge makes even delete-only rewrites unsafe.** Mock: base `old1,old2`; compactor side deletes `old2`; a concurrent branch appends `new` → union output `old1,old2,new` — the deletion loses and the compacted row resurrects, with a race window as long as the oldest live branch, not the final-push interval. Instead: **generation rotation** — when a log grows past a threshold, a deliberate commit renames it to `.drift-checkpoint.1.tsv` (archived, read-only) and starts a fresh file carrying a single `watermark` row (fold state as of rotation). Old branches merging afterwards append to a path that no longer folds into current state; their events surface via the watermark mismatch and re-flag naturally. Rotation is rare (years at expected row rates) and announced, not silent.
- Validation: new sibling structural check for the checkpoint schema — check #26 hardcodes `NF==4` for the local sidecar and must not be widened.
- Payoff: fresh clones and rebase-pullers inherit the team's staleness picture; LLM-observed flags (reviewer/ask) finally propagate; one dev's doctor scan satisfies the whole team. Checkpoint reads are point-in-time as of last pull — eventual consistency, accepted.

**R3. Branch discipline for every tracked-state writer — prune, doctor, AND promotion — plus a promotion race guard.** *(G4, G5)*
Add to `espalier-prune.md`, `espalier-doctor.md`, and the promotion section:
- Prune, doctor, and promotion commits run **from the long-lived integration branch the work targets** — main for trunk work, `release/1.x` for backport maintenance — **never inside a short-lived feature branch's pipeline run**. This is deliberately *not* "main only": a supported release branch's `espalier/` docs describe release code, and since the checkpoint is an ordinary tracked file, each long-lived branch naturally carries its own; a main-only rule would leave release docs unrefreshable through any sanctioned path while main's doctor stamp falsely certified the release tree. Stage 0's "Handle now" path: refresh on the integration branch, rebase/merge back, resume the feature. A doctor triggered from a feature branch's Stage 0 runs **report-only** (local sidecar + `.drift-report.md`) and defers its checkpoint/stamp commit — otherwise the team's "scan happened" fact strands on an abandonable branch and the diffusion-of-responsibility failure returns wearing an "it's in git" costume.
- **Canonical ref, persisted at init:** bootstrap records the canonical remote + default ref (e.g. `upstream/main`) in `.espalier-config`. The race guard and "refresh on the integration branch" resolve against it — in a fork-based workflow `origin` is the contributor's fork, so hardcoding `origin/main` reads stale or contributor-controlled state. A contributor without push access lands maintenance as a **PR against the canonical ref** (the no-access path is a maintenance PR, not a rule they can't follow). Guard degrades to warn-and-continue when the fetch fails (offline, CI without credentials).
- **Promotion race guard — honest scope: detection, not prevention.** Before prompting, Stage 0 fetches the canonical ref and reads its `.conventions.tsv` for an existing status event on that `pattern_key`; if found, surface it instead of prompting. This closes the common case but is a check, not a lock — two devs can both fetch a no-decision state and decide opposite ways concurrently. So each status event also records the **basis**: the observation `event_id`s the decision was made on. The doctor's reconciliation pass then detects two status events for one key with disjoint bases (or folded status disagreeing with rule-file text) and surfaces it as an explicit conflict for the rule owner — merge-order accident becomes a visible dispute. Residual race window accepted and documented.
- **Unattended Stage 0, defined semantics:** the current pre-flight prompt has no `interactivity_mode` gate of its own. Under this proposal, unattended runs never prompt, never prune, never promote — they write the pre-flight summary to `.drift-report.md`, then proceed (or fail, only if the repo's CI policy opts into hard-fail via validation). No invented defaults, no hangs, no report-only loops that reduce nothing.
- On any merge conflict inside `espalier/wiki/*` or a rule file: **do not hand-merge.** First inspect both sides (`git diff` the conflict stages) to confirm the side being discarded holds nothing hand-written that prune can't re-derive; then take either side (`git checkout --theirs <file>` for determinism), complete the merge, re-run `/espalier-prune <file>` over the merged tree. Scout regeneration over the merged codebase is the merge. A modify/delete conflict resolves as the deletion — never resurrect a deliberately-removed file via re-prune.

**R4. Ownership: generated CODEOWNERS entries + rules-review convention.** *(G5)*
Init Phase 0 gains an optional question ("who owns the rule canon?") and bootstrap offers to append:
```
# CODEOWNERS
espalier/rules/   @<arch-owner>
espalier/agents/  @<arch-owner>
espalier/wiki/    @<team>
```
Plus one documented convention in `development-process.md`: *a PR that changes `espalier/rules/*` (promotion or prune-applied) requires the owner's review; enable "Require review from Code Owners" if on GitHub.* The write itself needs a real spec, not "append": pick the target path (existing `CODEOWNERS` > `.github/CODEOWNERS` > create `.github/CODEOWNERS`), merge with an existing file idempotently (the `stage_gitignore` pattern), collect every referenced owner handle (rules owner AND wiki team) at init rather than emitting placeholders, and report enforcement as **unverified** unless the user confirms branch protection is on — the file alone is advisory. Espalier can't enforce platform settings — but it can generate the file and write the convention socially (its own Stage-4 reviewer can *remind* when a diff touches `espalier/rules/`; it runs pre-PR and cannot see platform review state, so detection of an actually-skipped review is out of reach).

**R5. Slug-collision resolution.** *(G6)* On a `changes/` path conflict at merge, the later branch renames its dir (`-b2` suffix or re-slug) and updates its own `pipeline-state.md`. The reverse cache self-heals (`rebuild-commit-index.sh` re-keys from folder paths) — **but the forward links do not**: a `## Follow-up Fixes` row written into another change's `pipeline-state.md` embeds the old slug as a literal cell, `rebuild-commit-index.sh` never parses that heading, and the append's idempotency grep keys on the *current* slug (so a re-run after rename would also duplicate the row). The rename recipe therefore includes: grep the old slug across `espalier/changes/*/*/pipeline-state.md` `## Follow-up Fixes` tables and rewrite it in the same commit. G8 (cross-branch appends into another change's `pipeline-state.md`) remains **explicitly deferred** — same family, no R-item yet.

### Phase 2 — deterministic drift anchors (P1, the structural fix)

**R6. `governs:` + content-hash anchors make wiki/rule staleness fail-closed.** *(G7, and shrinks G1's re-derivation problem)*
- At init Phase 2 and at every prune apply, each wiki/rule file gains frontmatter: `governs:` (globs of the source paths the scout derived it from) and an `anchors:` list of `(path, content-hash)` for the specific files that ground its claims. Anchors are derived from the scouts' **structured `evidence_files` output** — the JSON array every discovery scout already returns — not by grepping `file:line` citations out of doc prose (only the security scout emits per-claim `file:line`; the wiki scouts don't, so the prose-grep version would yield empty anchor lists for most docs). Existence-check each path before recording; a recorded anchor whose file later disappears hashes as `absent` (a defined value, not an error). Anchors live in **per-file frontmatter, not a shared `.anchors.tsv`** — a shared TSV would re-create the concurrent-update conflict surface R1/R2 just paid to remove, while per-file anchors ride the same `--theirs` + re-prune conflict recipe as their doc and conflict only when the doc itself does. Written only at init/prune/promotion time → invariant preserved.
- **Both** `drift-detect.sh` **and** `pre-push-gate.sh` gain the deterministic pass (not "and/or" — post-merge alone stays blind to rebase-pulls and locally-authored revert commits, the two known per-clone detection holes): recompute hashes for anchored paths touched; mismatch → `mark_stale <doc> <sha> "anchor: <path> changed"`. This replaces guess-the-regex as the *primary* detector; the 10 heuristics remain as the net for un-anchored ground.
- **Anchor revalidation clears false flags, not just raises true ones.** A revert can restore anchored sources to exactly their recorded hashes while an earlier flag lives on, ages, and (post-R2) eventually fails CI for drift that no longer exists. The same pass therefore also checks *flagged* docs whose anchors all match again: suppress the flag locally (sidecar clear — gitignored, hook-safe) and queue a checkpoint tombstone for the next deliberate publish (Stage 7/doctor/prune). Detection stays deterministic in both directions.
- Demote LLM re-scout (doctor/prune) to what the research says it's good at: **repairing** flagged files and judging "materially different", not detecting silent drift. v1 hash = whole-file content hash of anchored sources (cheap, over-flags on any edit — same false-positive class as today's heuristics but precise per-doc); v2 = tree-sitter span/AST hash (fiberplane/drift-style) where a parser exists.
- Implementation constraints inherited from the hook layer: bash-3.2 safe (no associative arrays — path→hash lookup via TSV+awk, the `classify_tier` pattern); hash portability via the codebase's existing `uname`-branch idiom (`sha256sum` on Linux, `shasum -a 256` on stock macOS, which ships no `sha256sum`); batch one hash invocation over all touched anchored paths (never one subprocess per file — `drift-detect.sh` is deliberately whole-list greps to stay cheap on every pull); in `pre-push-gate.sh`, wrap in the existing `timeout` warn-only pattern — missing tooling or slow hashing must never fail a push.
- Payoff for teams: detection becomes clone-independent and rebase-proof — any clone that runs the check on the same tree derives the same flags, which also shrinks the shared-state problem R2 patches.

**R7. Coupling check in the push gate (Danger pattern).** *(G7 corollary)* Non-blocking pre-push line: commits touch paths inside some rule's `governs:` glob, and neither that rule changed nor a drift flag exists → "code governed by `<rule>` changed with no doc signal — consider `/espalier-doctor --since <sha>`". Warn-only; it's a net, not a gate.

### Phase 3 — pruning & long-horizon hygiene (P2)

**R8. Supersede-not-delete lifecycle for rules — file-level status for whole-file replacement only.** Rules gain `status: active | superseded-by <file> | deprecated` in frontmatter; prune/promotion set it. "Loaders skip non-active" needs a real mechanism — rules load via `.claude/rules/*` symlinks, a file-presence system with no frontmatter parsing — so the bootstrap symlink stage (and prune, on a status change) filters: only `status: active` files get or keep a symlink. Two hard scope limits: (a) espalier's rule files are multi-convention canons — `coding-standards.md` holds many independent rules — so file-level status applies **only when a whole file is replaced by a successor**; retiring one convention stays an in-body edit (move it under the file's `## Deprecated`/`## Exceptions` section via the normal promotion path). (b) bootstrap validation hard-requires the standard rule symlinks today, so those checks become **status-aware** in the same change — otherwise the first legitimately superseded file fails validation forever. Git keeps history; nothing is deleted.

**R9. `last_refreshed` freshness metadata — advisory only, never a hard gate.** Each generated doc gets `last_refreshed:` (honest name — it records when the content was last *rewritten*, by init or a prune apply; both already gated, committed steps, so **the doctor stays a non-editor** and "prune is the only doc editor" survives intact). Verification is recorded separately and invariant-safely: a doctor scan that confirms an artifact current appends a `verified <file>` row to `.doctor-runs.tsv` in its own commit — so "last verified" comes from the append-only run log, not from editing the doc, and a healthy unchanged file doesn't report ever-staler metadata despite passing every scan. Validation and Stage 0 *report* freshness from it (tracked, team-shared, clone-independent), but the **hard-fail `expired` gate stays tied to the age of an active flag**, exactly as today. Two reasons: (a) the default `--quick` cadence never re-scouts `security-standards.md`, `production-standards.md`, or layer specs — aging them on a fixed clock guarantees false `expired` failures ~90 days after init on a perfectly healthy repo; (b) check #25's early-exit ("no sidecar file → all clean") would otherwise false-pass docs that aged out with no flag ever written. Tier precedence is therefore unambiguous: flag-age is the single tier source at every phase; `last_verified` is reporting. Optional: every Nth doctor run escalates to `--full` so never-flagged files get periodic re-scout coverage.

**R10. Demand-driven wiki growth — with a resolution lifecycle.** `.ask-gaps.tsv` repeat-count ranks missing coverage; wire it into doctor output ("3 asks unanswered about payment flow — consider a wiki page") and into prune as an optional "add coverage" mode. But demand must be retirable: gaps are never deduped or updated by design, so without a resolution event the doctor reports "3 unanswered asks" forever after the page ships, and repeat prune runs propose duplicate coverage. Fix in the house style: a normalized gap key per row, and when coverage lands, the same deliberate commit appends a `resolved-by <doc#section>` event; readers fold and count **unresolved** demand only. Usage-count-based *decay* (dropping unread rules) stays out — speculative without agent-usage instrumentation.

### Rollout & compatibility (new — second-review findings)

The mechanisms above change on-disk formats a running team is already writing. Rollout is its own spec:

1. **Two-release sequence: readers first, writers second.** Release N ships `.gitattributes` (its own first commit — branches forked earlier merge without union once), schema-tolerant readers (old 5/6-col conventions rows fold with a day-date fallback and no writer id), and a tracked format-version marker in `.espalier-config`. Release N+1 enables the new writers. Writers check the format version and refuse to append a schema the marker doesn't cover — an old plugin's `bootstrap --force` otherwise recopies old helpers over an upgraded repo and silently downgrades the log.
2. **Migration baseline.** The migration that enables R2/R6 runs one full `--full` doctor as its baseline (the checkpoint starts empty on upgrade — "fresh clone inherits team state" is false until someone publishes state) and backfills anchors for every supported artifact from a fresh scout evidence pass (anchors otherwise exist only for docs that happen to get pruned later, leaving the "deterministic detection is primary" claim hollow for months).
3. **Migration barrier.** `/espalier-migrate` gains what it lacks today: require a clean tree, refuse while any local `pipeline-state.md` is non-terminal, run on the integration branch, and stage its own file list explicitly — never `git add -A` (the current instruction, which can bundle unrelated work into the migration commit).
4. **Worktree-correct hook install.** Bootstrap resolves the hooks dir via `git rev-parse --git-path hooks` instead of the hardcoded `.git/hooks` — in a linked worktree `.git` is a *file*, so the current parent-dir check concludes ".git/hooks does not exist" and silently skips installing the dispatcher.
5. **Shallow clones.** All fold logic works from file content + `min(ts, now)` clamping — no history walks — so shallow CI clones are safe by construction; anything needing commit ancestry (compaction-era audits) runs only in deliberate maintenance steps that can deepen.

### Deliberate non-recommendations

- **LLM/embedding semantic comparison as a primary detector** — contraindicated by the TRACE blind-spot result; keep LLMs on repair/judgment.
- **`flock` on sidecars** — per-clone files, lost update self-heals on next merge; complexity buys nothing (matches the shipped v1 decision).
- **Hook-written shared state** (hooks committing, git-notes plumbing) — breaks the clean-tree invariant or adds push/fetch machinery teammates won't have; the R2 checkpoint gets ~90% of the value inside the existing "deliberate committed step" doctrine.
- **Auto-apply refresh in CI** — "refresh is never silent" is a good invariant; keep humans on the apply gate.

## 6. Priority summary

> **⚠ Superseded by plan §1/§3.5** — R2/R6 rows below are shelved, not scheduled.

| # | Item | Gap | Effort | Risk |
|---|---|---|---|---|
| R1 | Event-log TSVs + `merge=union` | G3 | S | low |
| R2 | Tracked drift checkpoint + shared doctor stamp | G1, G2 | M | low-med (merge fold logic) |
| R3 | Branch discipline (prune/doctor/promotion) + promotion race guard + regenerate-over-merge recipe | G4, G5 | S (docs only) | low |
| R4 | CODEOWNERS generation + rules-review convention | G5 | S | low |
| R5 | Slug-collision resolution note | G6 | XS | low |
| R6 | `governs:`/anchor hashes, deterministic detection | G7, G1 | L | med (anchor emission quality) |
| R7 | Pre-push coupling warn | G7 | S | low |
| R8 | Rule supersede lifecycle | pruning | M | low |
| R9 | `last_verified` advisory freshness metadata | G1(b) | M | low |
| R10 | Ask-gap-driven coverage | growth | S | low |

## 7. Team workflow walkthrough (A + B-team — the shipped scope, plan revision 5)

This narrates the workflow as it actually ships (plan §2 + §4: weekly gardener rota, single-line `.doctor-stamp`, file-per-key conventions, worktree ergonomics). Earlier versions of this walkthrough described first the full checkpoint machinery, then revision 4's event-log B-minimal (`.doctor-runs.tsv`, 8-column events, `espalier-format` guards) — both now shelved; see plan §5–§6.

Cast: **Alice** and **Bob** (feature devs), **Carol** (rule-canon owner via generated CODEOWNERS), **Dana** (this week's gardener, rotating). Doctor cadence: `weekly`.

**1. Alice ships a feature.** `/espalier <req>` on `feat/x`. Stage 0 pre-flight reads her **local** sidecar (drift tiers are per-clone — shared flag state is shelved), folds convention state via `conv_fold` (legacy `.conventions.tsv` + the `espalier/conventions/` per-key files, observations deduped across both), and checks `doctor_due()` against the tracked one-line `.doctor-stamp` (satisfied team-wide only by a `clean` stamp). Default answer: **Proceed** — the rota handles maintenance. Her Stage 4 reviewer emits a Convention Observation ("controllers return `Result<T,E>`"); the orchestrator appends one 5/6-col row to `espalier/conventions/k-controllers_result_type.tsv`. Stage 7 commits the change dir + that key file. PR merges. All her change paperwork rode her feature branch.

**2. Bob pulls main.** On a hook-enabled clone doing a merge-based pull, the post-merge dispatcher runs `drift-detect.sh`: Alice's merge touched `migrations/`, so his local sidecar flags `wiki/data-models.md`. His tiers are his own (per-clone); what he *inherits* through git is the tracked state — Alice's observation file and the doctor stamp.

**3. Bob runs his own pipeline.** Stage 0 shows one fresh-tier local flag and one convention at 1× — below thresholds, proceeds (an unattended run would write the summary to `.drift-report.md` and continue per lane; the fix lane goes to its own Stage 0 Auto-Link Discovery, not Stage 1). His reviewer independently observes the same pattern → a second row appends to the same key file. If his PR and Alice's next PR both append to that key concurrently, the merge shows a two-line conflict in that one small file — playbook: *keep both lines* (30 seconds). Different keys — most traffic — live in different files and cannot conflict at all.

**4. Gardener day.** Dana's turn this week. In a temp worktree of `canonical-branch` (her feature checkout untouched): `/espalier-doctor --quick` → it finds 2 stale docs, writes `dirty:2` → `/espalier-prune` over both, gated diffs accepted → doctor re-run on the now-clean tree restamps **`clean`** (the stamp records the session's end state — a `dirty` stamp whose findings were fixed in the same PR would nag the team forever) → one maintenance PR: `docs: weekly espalier maintenance`, containing the stamp + the two refreshes, nothing else. **A `clean` stamp satisfies the whole team's `doctor_due()`; a `dirty` stamp (findings she couldn't fix today) satisfies only her clone** — the tracked stamp never says "handled" while findings sit unresolved on one machine. One scan per team per interval, and "someone else surely ran it" dies because the rota names Dana.

**5. Between gardener days.** Bob's own flag ages toward critical while he actively needs that doc? The escape hatch: prune on his feature branch as its own isolated `docs:` commit — recoverable by the regenerate-over-merge recipe if it ever collides with Dana's sweep. Phantom rows on other clones clear on each clone's next explicit prune (empty two-way diff → cleared, no prompt), not automatically on pull.

**6. Promotion.** A third observation lands on the `Result<T,E>` key — `conv_fold` on whichever clone folds it first crosses the threshold and prompts. Before prompting, the orchestrator fetches the canonical ref and reads that key's file from `FETCH_HEAD` (plus the legacy file for pre-conversion keys): an existing decision → surfaced, no prompt. On Promote — right there on the feature branch, as its own commit: the rule file is edited AND the key file's rows flip `diverges → promoted` in place (safe now: the file is small, single-key, ordinary 3-way merged). The PR touches `espalier/rules/`, so CODEOWNERS — enforcing only with branch protection; advisory otherwise — routes it to Carol. If two branches promote the same key differently, the key file itself conflicts at merge — the race surfaces as a git conflict even when the fetch guard was skipped. Once merged, every clone enforces the new rule on next pull; the divergence window is PR latency, and visible.

**7. Conflict playbook.**
- Same-key concurrent observation appends → two-line conflict in that key's file → keep both lines.
- Same-key concurrent *decisions* → conflict in that key's file → a real dispute; Carol tie-breaks, then the file records one status.
- Doctor-stamp conflict (two scans in one interval — rota mix-up) → one line vs one line → keep the newer (or either `clean`).
- Both devs pruned the same file on different branches → visible conflict; inspect both sides for hand-written content prune can't re-derive, `git checkout --theirs <file>`, finish the merge, re-run `/espalier-prune <file>` over the merged tree. Regeneration *is* the merge. Modify/delete: the deletion is the resolution.
- Same-day `changes/fix/` slug collision → later brancher renames its dir, reruns `rebuild-commit-index.sh`, and rewrites the old slug in any `## Follow-up Fixes` tables in the same commit.

**8. Edge developers — accepted residuals.** A plain-git teammate without bootstrap has no local detection but inherits everything tracked (conventions, stamp, refreshed docs). A `pull.rebase=true` dev misses post-merge firing — no local mechanical flags; the weekly gardener scan is the backstop for both. Reviewer/ask flags stay clone-local until someone prunes (a deleted worktree can lose them — accepted; the doctor re-finds real drift). Tier ages differ per clone — warning-level noise, accepted. A skipped gardener week self-corrects: the stamp ages out and `doctor_due()` resumes nagging everyone (the pre-rota behavior is the fallback). These residuals are the price of shelving the checkpoint machinery; §3.5 of the plan defines the measured triggers that would un-shelve it.

Role summary: every dev is a passive detector on their own clone and answers "Proceed" at Stage 0; gardener duty = one rotating dev per interval, via the worktree flow, ending in one maintenance PR whose stamp is `clean` only when the tree really is; prune outside the rota = escape hatch, own commit, behind the existing gate; promotion = the observing dev, own commit, owner-reviewed; rules = owner-reviewed.

### The rule-canon owner's duties (Carol)

One-time: be named in the generated CODEOWNERS (`espalier/rules/`, `espalier/agents/`), and enable the platform setting espalier cannot — branch protection with "Require review from Code Owners" (without it, CODEOWNERS is advisory).

Per rules-touching PR (promotions and prune-applied rule refreshes — few per month):
- **fetch the canonical branch and glance for a concurrent open rule PR first** — the fetch guard is detection, not a lock, and Carol is the only vantage point that sees both sides of a promotion race;
- promoted pattern is real team consensus, not one dev's habit that reached 3 observation events on their own branches;
- the new rule contradicts no existing rule (reconcile-at-write);
- universal seed sections / severity tiers are untouched (prune must never rewrite them);
- supersede-not-delete followed in the rule file — old convention moved under `## Deprecated`/`## Exceptions`, never silently removed; the key file's rows read `promoted` (the flip is the record — git history keeps the before-state);
- phrasing stays machine-enforceable (concrete, greppable) — reviewer agents judge against it verbatim.

Occasional: tie-break disputed promotions and "the convention itself is bloat" escalations (the human promotion path).

Explicit non-duties: running detection (hooks), running the doctor (first dev to hit the interval), running every prune (anyone, gated), tending sidecars (self-healing). The owner is a gate, not a bottleneck.

## 8. Open questions — resolved recommendations

> **⚠ Historical record.** Item 1's sha-carrying tombstones and delete-only compaction were later corrected (event-id tombstones, no compaction — §10) and then the whole checkpoint package was shelved (plan §3.5). Item 3's union-merge discussion likewise predates plan revision 5, which dropped union for the conventions files entirely (file-per-key, plan §4 B-3 — only `.ask-gaps.tsv` keeps `merge=union`). Kept for the reasoning trail, not as current spec.

1. **Checkpoint granularity → two tracked files, both append-only event logs; never fold into `.conventions.tsv`.**
   `.drift-checkpoint.tsv` holds flag events plus sha-carrying tombstone `cleared` events; readers fold on max **clamped timestamp** per file with causal tombstones — one algorithm, defined in R2, never file position (`merge=union` output order is unspecified). Go straight to append+tombstone rather than in-place row deletion — same event-log pattern R1 adopts, and deletion is the predictable conflict source. `.doctor-runs.tsv` gets one `timestamp\tsha\twriter` row per doctor run; `doctor_due()` reads the max, so concurrent runs on two branches union-merge cleanly where a one-line stamp file would conflict every time. Keep signals in separate files — "one writer, one reader, one fixed schema" is the original sidecar principle and it holds here. Growth is bounded by delete-only compaction (surviving rows byte-identical — a reformatting rewrite would let union merge resurrect removed rows) in the doctor's own commit, re-pulled immediately before push.

2. **Anchor emission → extract anchors from citations mechanically; don't add a recall task.**
   Scouts and `/espalier-ask` already require per-claim `file:line` sourcing. A deterministic post-pass greps cited paths out of the written doc, drops any that fail an existence check (hallucination filter), and writes the survivors as anchors — emission becomes extraction, so there is no new prompt-quality surface. Eval rubric: **recall against a golden source list is the gate; precision is advisory** — a missing anchor is a silent blind spot (the exact failure R6 exists to kill), an extra anchor is one spurious flag, same cost class as today's heuristics. Roll out wiki-first (`data-models.md`, `external-services.md` have crisp source sets); `architecture.md` last.

3. **Union-merge on GitHub web → accept the caveat; no custom merge driver.**
   Driver config (`git config merge.X.driver`) does not clone with the repo — the same per-clone-install weakness as the hooks (known limit §8.9). Bootstrap could wire it, but after R1's event-log conversion every "conflict" on these files resolves as "keep both sides", which is trivially correct by hand even in the web UI. One documented line beats shipped machinery. Revisit only if a team demonstrably resolves merges primarily in the GitHub web UI.

4. **Post-merge regeneration → codify the conservative recipe; cap automation below CI enforcement.**
   v1 (ship with R3): on a conflict in `espalier/wiki/*` or a rule file, first inspect both sides to confirm the discarded one holds nothing hand-written that prune can't re-derive, then take either side (`git checkout --theirs <file>` for determinism), complete the merge, run `/espalier-prune <file>` over the merged tree; a modify/delete conflict resolves as the deletion — never resurrect via re-prune. Do **not** set `merge=ours`/`merge=theirs` in `.gitattributes` — silently discarding a side can lose hand-edits; the visible conflict is the feature. v2 (if demand appears): post-merge hook notices a resolved conflict touched a generated file and drops a `mark_stale` reason "merged regenerated file — re-prune" (notify-only, invariant-safe). v3 — CI regeneration guard (`git diff --exit-code` after re-extract) — is a deliberate non-goal: it requires byte-deterministic generation, and LLM scouts are not deterministic (model/temperature drift would make the guard flap). Regenerate-over-merge works in espalier precisely because prune's human gate absorbs nondeterminism; that is the principled stop line.

## 9. Adversarial review log (2026-07-23)

Two independent review passes ran over this document before it stabilized: a proposal-logic reviewer (git semantics, races, human-process failure modes) and an implementation-constraint reviewer (every integration claim checked against the actual templates, hooks, and bootstrap, with file:line evidence). 33 findings; all P0/P1s are folded into the R-texts above rather than kept as an errata list. The shared root cause of the serious ones: **treating file position or an unqualified wall clock as an ordering authority in union-merged logs.**

What changed as a result:
- **R1/R2** — event rows gained full timestamps + writer ids with commit-date clamping; fold = max clamped timestamp, never file position; tombstones carry the `stale_since_sha` they retire (causal dominance — a stale tombstone can't swallow re-flagged drift); one fold algorithm defined once, inside `classify_tier`/`stale_files`, because `tier_counts()` and every other read site consume those helpers (a call-site-only patch would silently drop checkpoint-only rows from tier counts); the checkpoint gets its own pure-append helper (the sidecar's `mark_stale` is an upsert — union-unsafe); delete-only compaction; a Stage 7 staging line; `append_convention()` gains a `status` parameter; read-time dedupe on `(slug,key,location)`.
- **R3** — branch discipline extended to the doctor (feature-branch runs are report-only; the stamp commit lands on main or not at all); promotion gained a fetch-main race guard plus a doctor-side rule-text/status reconciliation check; the conflict recipe gained a look-at-both-sides-first step and a modify/delete branch.
- **R4** — reviewer "flags un-reviewed rule edits" corrected to "reminds" (it runs pre-PR; platform review state is invisible to it).
- **R5** — the "backlink caches self-heal" claim was falsified by reading `rebuild-commit-index.sh`: it re-keys only the reverse cache; `## Follow-up Fixes` forward links dangle and a re-run would duplicate rows. The rename recipe now rewrites forward links in the same commit. G8 is explicitly deferred.
- **R6** — anchors moved to per-file frontmatter (a shared anchors TSV would recreate the conflict surface R1/R2 remove); bash-3.2 / `shasum` portability / batched hashing / warn-only timeout constraints recorded.
- **R8** — the loader mechanism is named (bootstrap symlink stage filters on `status: active`); frontmatter alone changes nothing.
- **R9** — demoted to advisory: hard-fail expiry stays flag-age-based at every phase, because the default `--quick` cadence never re-scouts security/production/spec files (fixed-clock expiry would guarantee false validation failures ~90 days after init on a healthy repo) and an empty sidecar must not read as all-clean; the doctor stays a non-editor, preserving "prune is the only doc editor".

Accepted residue: checkpoint reads are point-in-time between pulls (eventual consistency); G8 has no R-item; per-clone detection gaps for rebase-pullers and no-bootstrap teammates persist until Phase 2's anchor pass.

## 10. Second adversarial pass — fresh-eye mock-run + external cross-check (2026-07-23)

A second round ran after §9: an independent fresh-eye scenario mock-run (15 scenarios: release branches, forks, CI, reverts, worktrees, migration mid-flight, unattended runs, deleted artifacts, partial adoption, shallow clones, …) cross-checked by an external reviewer (OpenAI Codex, gpt-5.6-sol, xhigh reasoning, full repo read access) that produced 24 findings. Every adopted external finding was validated against the actual code first; four were re-verified by direct file reads (worktree hook-install failure, migrate's unguarded `git add -A`, Stage 0's missing interactivity gate, scouts returning `evidence_files` arrays rather than per-claim `file:line`), and the union-merge compaction counterexample was re-derived independently before acting on it. None were rejected outright.

Spec changes this round:
- **R1** — full event schema (`event_id`, `kind`, `rule_file` carried through from Observations) replacing the "add a status param" patch, whose `(slug,key,location)` dedupe would have no-op'd a second status change for the same key; `.gitattributes` extended to all four union logs (the draft asserted union behavior for two files it never listed); clock clamp re-specified as `min(ts, now)` at read — the commit-authored-date clamp needed per-row blame on hot paths, broke on uncommitted rows and shallow clones, and trusted the same workstation clock it distrusted.
- **R2** — tombstones enumerate retired `event_id`s instead of carrying a sha (doctor and ask stamp flags with scan-time HEAD, so shas neither identify flag occurrences nor separate pre-prune flags from identical re-flags); schema splits `event_at` from `first_seen_at` (single-timestamp publish silently reset tier age team-wide); in-place compaction dropped entirely — union merge resurrects even delete-only rewrites (counterexample in-text) — replaced by generation rotation; helper accessor APIs replace every direct sidecar read; Stage 7 gains a publish step for reviewer-observed flags (the propagation claim was false without it — only doctor/prune wrote the checkpoint); the CI hard-fail behavior change is now stated with its remediation playbook.
- **R3** — "main only" corrected to "the long-lived integration branch the work targets" (release branches maintain their own docs; the checkpoint being an ordinary tracked file already does the right thing per branch); canonical remote/ref persisted at init (fork workflows: `origin/main` is the fork); race guard honestly scoped as detection — status events record their basis event-ids, doctor surfaces concurrent divergent decisions as explicit conflicts; unattended Stage 0 semantics defined (report, proceed, never prompt/prune/promote).
- **R4** — CODEOWNERS write fully specified (path selection, idempotent merge, real handles, enforcement reported unverified without branch protection).
- **R6** — anchors derived from scouts' structured `evidence_files` (the prose-citation grep would return empty for most wiki docs); the deterministic pass is mandatory at both post-merge AND pre-push (rebase/revert blindness); revalidation added — anchors matching again clears/suppresses a false flag, so a revert can't leave immortal drift that blocks CI.
- **R8** — file-level status restricted to whole-file replacement (rule files are multi-convention canons; one frontmatter flag must not unlink a whole standards file to retire one rule); bootstrap symlink validation becomes status-aware in the same change.
- **R9** — renamed `last_refreshed`; verification recorded as append-only `verified` rows in the doctor-run log (the doctor stays a non-editor).
- **R10** — gap keys + `resolved-by` events so satisfied demand retires.
- **New "Rollout & compatibility" section** — two-release readers-then-writers sequence with a tracked format version; migration baseline (full doctor + anchor backfill — the checkpoint and anchors start empty on upgrade); migration barrier (clean tree, no active pipelines, no `git add -A`); worktree-correct hook install via `git rev-parse --git-path hooks`; shallow-clone safety by construction.

External reviewer's residual readiness verdict, post-fix: R5 was safe as written; all others needed exactly the spec changes now folded in above. Remaining accepted risks unchanged from §9, plus: the promotion race is detected, not prevented; ask-flag propagation has publish latency.
