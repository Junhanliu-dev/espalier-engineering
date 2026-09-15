---
fixture_id: overspec-01-settings-cache
mode: spec
expected_tier: light
expected_signals: 2
# v0.28 "Over-specified mechanism" signal. The text names HOW (a TTL cache with an
# invalidation endpoint) where the WHAT (no disk read per request) is met by memoizing
# the loader once per process — the wiki says settings never change while the process
# runs. The second signal is the announced hidden quantifier ("stale-safe" / the TTL).
# Coverage test: value is the covering alternative offered WITH its wiki citation and the
# requester's choice landing as a Scope out-line — not the question's artistry.
coverage_only: true
planted_ambiguities:
  - the requirement names a mechanism (TTL cache + invalidation endpoint) the outcome does not need — grill offers the covering alternative (memoize loadSettings() once per process) citing wiki/architecture.md, and the answer lands as a Scope Definition out-line
  - the TTL / staleness bound is unquantified ("stale-safe")
answer_script:
  - asks_about: whether a TTL cache and an invalidation endpoint are needed at all, given settings never change while the process runs — memoize the loader instead
    reply: I did not know they were immutable at runtime — yes, just memoize loadSettings(); no TTL, no invalidation endpoint
  - asks_about: the TTL / staleness bound
    reply: moot after the above — settings only change on deploy
shadow: false
---
feat: add a caching layer for the settings service — a stale-safe TTL cache with an invalidation endpoint so `config/settings.json` is not re-read from disk on every request

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/rules/coding-standards.md

```markdown
# Coding Standards

## Error Handling
Every fallible function returns `Result<T>`; nothing throws across a module boundary.

## Naming
camelCase for functions, PascalCase for types, SCREAMING_SNAKE_CASE for constants.
```

### espalier/wiki/architecture.md

```markdown
# Architecture
A single Node service. Settings come from `config/settings.json`, read by
`loadSettings()` in `src/settings.js` on every request. The file is baked into the
container image at deploy time and never changes while the process runs — a deploy
is the only way settings change, and every deploy restarts the process.
```
