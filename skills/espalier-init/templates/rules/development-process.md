# Development Process

## Branch Strategy
{detected from git or CI config}

## Commit Conventions
{detected from git log}

## CI Checks
{existing checks + what they verify}

## Deploy & Verification
{from DISCOVERY.deploy — mechanism, exact command (or "automatic on merge"),
health check, and which environment a merged change reaches. This is what
pipeline Stage 9 runs/verifies. If DISCOVERY.deploy was null, write exactly:
"No deploy configuration discovered — Stage 9 records SKIPPED: no-deploy-config."}

## Quality Bar
{what must pass before merge — derived from CI + project conventions}

## Maintenance Commits
<!-- ESPALIER MAINTENANCE COMMITS v1 — managed anchor; fixed policy text (not scout-discovered), keep this comment -->

- Espalier maintenance is lane-based: doctor scans and routine prune refreshes
  ride ONE weekly maintenance PR on the canonical branch (`canonical-branch`
  in `espalier/.espalier-config`); a prune for your OWN critical/expired flag
  may ride your feature branch as its own isolated `docs:` commit; convention
  promotions may ride the deciding feature branch as their own isolated
  commit. Maintenance commits are never folded into feature commits.
- Rule-canon gate: every PR touching `espalier/rules/` gets the rule owner's
  review. CODEOWNERS routes it automatically ONLY when "Require review from
  Code Owners" branch protection is on — without protection the file is
  advisory; turn protection on. Rule owners: before approving a rules PR,
  fetch canonical state and check for concurrent open rule PRs — no automated
  detector can see two PRs that are both still open.
- Union-merge caveat: GitHub's web conflict editor ignores custom merge
  drivers (including `merge=union` on `espalier/.ask-gaps.tsv`) — resolve
  union-file conflicts locally, never in the web UI.
