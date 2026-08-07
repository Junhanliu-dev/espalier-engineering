---
fixture_id: shadow-01-team-doc-garden
mode: chart
max_open_tickets: 7
# Shadow fixture: planted decisions are drawn from a real multi-session epic
# (multi-dev maintenance of a generated docs dir), reframed as a generic
# project. The answer_script deliberately does NOT cover the rule-ownership /
# review-gate question the branch-protection task tends to raise — a correct
# run records an Open Question with a named conservative default instead of
# inventing the user's answer.
planted_decisions:
  - id: scan-ownership
    text: who runs the periodic doc-health scan — every dev redundantly, a shared run-record any dev can satisfy, or one named rotating owner — decides whether the backstop ever actually runs
    expected_placement: ticket
    expected_type: grilling
  - id: shared-vs-perclone-state
    text: which staleness/maintenance state is shared through git vs kept per-clone — today a fresh clone starts blind and the same doc reads fresh on one machine and expired on another
    expected_placement: ticket
    expected_type: grilling
  - id: append-file-merge-behavior
    text: how tracked machine-appended log files actually behave under concurrent-branch merges (union-merge attribute semantics, web-UI conflict handling, prior art like changelog-fragment tools) — needs facts from outside the repo
    expected_placement: ticket
    expected_type: research
  - id: branch-protection-prereq
    text: before any rule-ownership/review gate can even be judged, someone must confirm whether the host repo has (or can get) branch protection with required reviewers — a platform setting no repo file can enforce
    expected_placement: ticket
    expected_type: task
  - id: deterministic-drift-anchors
    text: deterministic content-anchoring of docs to the source they describe (hash-based detection instead of LLM re-reads) is suspected to be needed for silent drift — but not phrasable as a sharp question until the shared-state and ownership decisions land
    expected_placement: fog
  - id: doc-lifecycle-hygiene
    text: long-horizon hygiene — superseding rather than deleting rules, freshness metadata, retiring doc-demand once coverage lands — wanted, but nobody can yet say what it needs
    expected_placement: fog
answer_script:
  - asks_about: destination / what DONE looks like for this map
    reply: a locked maintenance model for the shared docs dir under ~10 concurrent devs — ownership, shared-vs-local state, and merge behavior decided, ready to slice into tooling changes; rewriting the doc-generation pipeline itself is explicitly out of scope
  - asks_about: team size / workflow
    reply: about 10 devs, trunk-based with short feature branches; a mix of merge-based and rebase pulls; a couple of teammates never installed the repo's git hooks
  - asks_about: who should run the periodic scan
    reply: one rotating owner per week — we tried "whoever notices the reminder" and the scan simply never ran
  - asks_about: what state may be committed / automation writing files
    reply: hard constraint — automation and hooks never commit; anything shared through git must be written by a deliberate, human-gated step
shadow: true
---
Idea: our repo has a generated knowledge directory (rules, a wiki, and a
machine-appended conventions log) kept fresh by an AI maintenance pipeline
that was designed for a single developer. Ten of us now work the repo
concurrently and it's breaking down: every clone has a different picture of
which docs are stale, two branches appending to the same tracked log file
merge-conflict, and nobody actually runs the periodic health scan because
everyone assumes someone else did. Too many interlocking decisions to just
start patching; chart it.
