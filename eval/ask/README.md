# Ask Eval Harness

Dev/QA infrastructure for the `espalier-ask` skill. NOT shipped to target
projects — it lives in the espalier-engineering repo and validates the skill
before release.

`espalier-ask` makes three judgment calls that can silently regress: it
classifies the question, it decides whether a doc is stale (drift), and it
decides whether the docs cover the question at all (gap). This harness pins all
three, plus the safety-critical invariant that it never writes a sidecar into a
repo that is not an Espalier install.

## Layout

```
eval/ask/
├── README.md      this file
├── rubric.md      how an ask run is scored (two gates)
├── run.sh         the runner (materialize → run → score)
└── fixtures/      golden Q&A fixtures across five buckets
```

## Run

```bash
bash eval/ask/run.sh
```

Requires the `claude` CLI on PATH. Per fixture the runner:

1. **Materializes** a temp git repo from the fixture's `=== FILE: <path> ===`
   blocks (both `espalier/` docs and source), then `git init` + commit so
   `git rev-parse HEAD` and `--show-toplevel` work.
2. **Runs** `espalier-ask` against it via `claude` headless, cwd = the repo.
3. **Gate 1 (deterministic):** asserts the side effects directly — a `drift`
   fixture must leave an `ask-verify:` row in `.drift-state.tsv`; a `gap`
   fixture must leave a `.ask-gaps.tsv` row; a `no-install` fixture must leave
   no `espalier/` dir; `classify`/`docs-first` must leave no sidecars.
4. **Gate 2 (LLM judge):** scores answer quality against `rubric.md` —
   classification, docs-first ordering, code-verification, sourcing, and
   (for drift) trusting code over the stale doc.

A fixture passes only when BOTH gates pass. The harness exits non-zero if the
pass-rate is below 0.80, or if any `drift`/`no-install` fixture fails Gate 1.

## Buckets

| bucket | what it proves |
|--------|----------------|
| `classify` | the question is routed to the right type (where/how/why/what-changed) |
| `docs-first` | the answer comes from the wiki first, verified against code |
| `drift` | a wiki that contradicts code → answer trusts code + flags the doc |
| `gap` | docs silent → answer from code + a gap-log row |
| `no-install` | no `espalier/` dir → degrade to a code answer, write nothing |

## Fixture format

One `.md` file per fixture. Frontmatter is the answer key; the body is a series
of `=== FILE: <path> ===` blocks materialized into the temp repo.

```yaml
---
fixture_id: drift-01-stale-wiki
bucket: classify | docs-first | drift | gap | no-install
question: how are user sessions stored
expected_type: where | how | why | what-changed
expect:                       # prose bullets the judge checks Gate 2 against
  - ...
expect_drift: true|false      # documents intent; Gate 1 derives from bucket
expect_gap: true|false
expect_no_espalier: true|false
---
=== FILE: espalier/wiki/architecture.md ===
<file contents>
=== FILE: src/session/store.ts ===
<file contents>
```

A `drift` fixture bundles a minimal `espalier/hooks/drift-helpers.sh` stand-in
(just `mark_stale`) so the skill's flag call works inside the sandbox repo
without the full hook set.
