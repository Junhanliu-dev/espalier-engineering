# /espalier — Stage 1–2 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 1–2
> starts (requirements written and grilled; requirements reviewed). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 1 and Stage 2 — loads

Stage 1: read `espalier/skills/espalier-requirements/SKILL.md` (it invokes
`espalier-grill`) and write `requirements.md` — the contract sections; the
grill's Q&A goes to `requirements-notes.md`. Stage 2: review it per
`espalier/skills/espalier-review/SKILL.md` (a heading outside the contract
set is a P2 → `requirements-notes.md`). Then the gate below. Everything the
grill reads lands in THIS context — the gate's session-boundary preference
(step 3d) is what releases it.

### Requirements Approval Gate (BLOCKING — before Stage 3 Coding)

MANDATORY. Must NOT be skipped on a PASS. Stages 1 (requirements written +
grilled) and 2 (requirements review) finish WITHOUT writing any code. Do NOT
chain Stage 1 → 2 → 3 automatically — that is the bug this gate closes. After
Stage 2's gate passes (no P0/P1 reqs findings), HALT and get explicit user
sign-off on `requirements.md` before Stage 3.

1. Present a concise summary of the final `requirements.md` — in THIS order,
   the decisions most likely to change first, so the human's attention lands
   where an edit is cheapest:
   - the decisions the code will freeze: the data-model, interface, and
     user-facing lines of `## Technical Considerations`, and every
     `## Open Questions` entry with its conservative default — the human
     ratifies each default here (a rejected default is an **Edit**; an
     `approach:` entry is the grill saying talking could not settle it —
     offer `/espalier-map` in the same breath);
   - the one-line goal and the acceptance criteria;
   - scope in / out, `## References` when present, and what the grill
     resolved.
   The mechanical part (task decomposition) is not read out.
2. In the SAME turn as this prompt, write the context pack —
   `stages/3-coding.md` → "Stage 3 Entry: Context Pack" holds the format
   (read that section now; paths and facts only, approval-independent). Then
   ask with `AskUserQuestion`:

   ```
   Requirements are written and reviewed. Nothing has been coded yet.
   Approve to start Stage 3 (Coding)?

   Options:
     1. Approve — proceed to coding.
     2. Edit    — tell me what to change; I revise requirements.md and re-ask.
     3. Abort   — stop here; leave requirements.md as a draft (Status: ABORTED).
   ```

3. In the SAME `AskUserQuestion` call, add a second question collecting the
   Stage 7 push authorization — so a run whose gates all pass later doesn't
   stall waiting for a human who has walked away:

   ```
   When Stage 7 (push) is reached and every gate passes, push to:
     1. {current branch} → {default remote}   (pre-authorize)
     2. Somewhere else — specify
     3. Ask me again at Stage 7
   ```

   Record the choice as `- Push-Target: {branch → remote | ASK}` in
   pipeline-state.md. Stage 7 then pushes a pre-authorized target without
   re-prompting — the programmatic gates (clean tree, branch convention,
   pre-push hook, certificate) still apply in full; only the redundant wait
   is removed. `ASK` or a missing line → prompt at Stage 7 as before. This
   pre-authorization NEVER extends to Stage 10 — delivery acceptance stays a
   human act.

3b. If Stage 0 recorded a `deferred-to-approval-gate` pre-flight summary,
   add a THIRD question to the SAME `AskUserQuestion` call:

   ```
   Pre-flight noted: {N} stale doc(s) ({tiers}), {M} convention promotion
   candidate(s), doctor {due|not due}.
     1. Handle after this change (default — gardener rota covers it)
     2. Pause & handle now — run /espalier-prune + convention decisions,
        then continue to Stage 3
     3. Ignore this run
   ```

   "Pause & handle now" runs the SAME mechanics as the Stage 0 prompt's
   "Handle now" (Convention Promotion's race guard, per-key status flip,
   isolated `docs:` commit) — relocated, not altered, and still before any
   code is written.

3c. ONLY when the discovered `## Deploy & Verification` section of
   `espalier/rules/development-process.md` is configured (it does NOT read
   "No deploy configuration discovered"), add a deploy question to the same
   call:

   ```
   When Stage 9 (deploy verify) is reached and CI is green, deploy with the
   discovered command to:
     1. {discovered target/environment}   (pre-authorize)
     2. Somewhere else — specify
     3. Ask me again at Stage 9
   ```

   Record `- Deploy-Target: {target | ASK}` in pipeline-state.md. Stage 9
   honors it (see pipeline.md Stage 9): a pre-authorized target deploys and
   health-checks without re-prompting; `ASK`/missing prompts at Stage 9 as
   today. The health-check gate, its rollback path, and the Stage 10 human
   acceptance are untouched — like the push pre-auth, this removes only the
   redundant wait, and it NEVER extends to Stage 10.

3d. In the SAME `AskUserQuestion` call — when it still has a slot (the
   tool takes four questions; with 3b AND 3c both present, ask this one
   right after) — collect the session-boundary preference, first option
   default:

   ```
   Session boundaries — state is on disk at each; nothing depends on this:
     1. Continue here at both (default)
     2. Stop after approval — a fresh session runs from Stage 3
     3. Stop after the Stage 4 PASS — a fresh session runs from Stage 5
     4. Stop at both
   (Everything Stage 1 read into this context — code, docs, the grill's
   answers — stays resident on "continue"; a fresh session starts from
   requirements.md, the context pack, and the stage's procedure. The
   `Continue in a fresh session` path of v0.25, chosen once, here.)
   ```

   Record it as `- Session-Boundary: none | after-2 | after-4 | both` in
   pipeline-state.md. Skip the question on an unattended run
   (`interactivity_mode` returns `unattended`) exactly as the Completion's
   BUILT offer is skipped — no line, every boundary continues.

4. Advance to Stage 3 ONLY on **Approve**. On **Edit**, revise `requirements.md`
   per the feedback, re-run the Stage 2 gate, and re-present this gate. On
   **Abort**, write Status: ABORTED to pipeline-state.md and stop.

5. **Stage boundary (read, never asked).** After **Approve** — the
   `| 2 | PASSED |` row, `- Push-Target:`, `- Session-Boundary:`, and the
   context pack are on disk — read the preference: `after-2` or `both` →
   write `- Current Stage: 3` (Session Resumption resumes by this line),
   print `run /clear, then /espalier with no argument: Session Resumption
   picks this change up at Stage 3 from pipeline-state.md`, and stop. Any
   other value or a missing line → continue here. Nothing forces the reset;
   Session Resumption is unchanged.

**Non-interactive exception:** auto-approve ONLY when the run is EXPLICITLY
unattended — `interactivity_mode` (in `drift-helpers.sh`) returns `unattended`,
i.e. one of `CI` / `ESPALIER_UNATTENDED` / `ESPALIER_LOOP` / `ESPALIER_HEADLESS`
is set. Do NOT key this off a bash TTY test: stdin has no TTY inside Claude Code
even when the user is present, so a TTY check would silently auto-approve every
interactive run — defeating the gate. If you (the orchestrator) can call
`AskUserQuestion`, you ARE interactive and MUST prompt. Only on a genuinely
headless run, record `requirements auto-approved (non-interactive)` in the Stage
History and proceed.

Record the outcome in pipeline-state.md Stage History (e.g.
`| 2 | PASSED | … | Requirements approved by user |`).
