# Scheduled Releases

Releases can run unattended on GitHub's runners — no developer machine
involved — via [`.github/workflows/scheduled-release.yml`](../.github/workflows/scheduled-release.yml).

## Release a version at the next 9 pm slot

1. Push a branch whose PR into `main` is titled `vX.Y.Z — <tagline>` and
   already contains the `## X.Y.Z` CHANGELOG section plus the
   plugin/marketplace version bumps (the normal release-lane commit).
2. Label the PR **`scheduled-release`**.
3. Done. The daily run (cron 10:40 UTC, then an in-job wait until 11:00 UTC =
   21:00 AEST) validates the title and CHANGELOG, merges with the repo's
   `Merge PR #N: vX.Y.Z — …` subject pattern, pushes the annotated tag, and
   publishes the GitHub release with the CHANGELOG section as notes.

No labeled PR → the daily run exits in seconds. Two labeled PRs → it refuses
and fails loudly (unlabel one). Tag already exists → it refuses before merging.

## Release NOW instead

Actions → `scheduled-release` → **Run workflow** (or
`gh workflow run scheduled-release`). Same job, skips the wait.

## Gotchas

- **DST is not tracked.** The slot is fixed at 11:00 UTC. During AEDT
  (Oct–Apr) that is 22:00 Sydney — edit the cron and `RELEASE_AT_UTC`
  together to move it.
- **Repo inactivity.** GitHub suspends scheduled workflows after ~60 days
  without activity; re-enable from the Actions tab.
- **Authorship.** The merge commit, tag, and release are created by
  `github-actions[bot]`; the commits inside the PR remain yours.
- **The PR must be mergeable** at slot time (no conflicts with `main`).
