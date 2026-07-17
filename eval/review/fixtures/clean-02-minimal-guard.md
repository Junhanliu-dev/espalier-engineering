---
fixture_id: clean-02-minimal-guard
kind: clean
file: src/services/invite-service.js
expected_verdict: PASS
planted_issues: []
false_positive_watch:
  - "a single-function service module mirrors the reference service shape the rules mandate — do NOT flag it as an unnecessary layer/abstraction (yagni)"
  - "the code is already lean — a minimalism finding filed at P0/P1 here is a false positive (the reviewer's own Minimalism Review caps them at P2/P3; advisory P2/P3 notes are NOT false positives)"
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "saveInvites is a repository (internal) call — do NOT flag it for a missing timeout"
  - "[...new Set(emails)] is the stdlib dedupe — do NOT flag it as needing a helper or a utility module"
shadow: false
---
const { saveInvites } = require('../repositories/invite-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

// inviteUsers — returns Result<number, AppError>
async function inviteUsers(emails) {
  logger.info('inviteUsers', { count: emails.length });
  const unique = [...new Set(emails)];
  if (unique.length === 0) {
    return { ok: false, err: new AppError('no emails') };
  }
  const saved = await saveInvites(unique);
  return { ok: true, value: saved };
}

module.exports = { inviteUsers };
