---
fixture_id: clean-02-minimal-guard
kind: clean
file: src/services/invite-service.js
expected_verdict: PASS
planted_issues: []
false_positive_watch:
  - "a single-function service module mirrors the reference service shape the rules mandate — do NOT flag it as an unnecessary layer/abstraction (yagni)"
  - "the code is already lean — a minimalism finding filed at P0/P1 here is a false positive (the reviewer's own Minimalism Review caps them at P2/P3; advisory P2/P3 notes are NOT false positives)"
  - "MAX_INVITES is the production-standards bound on the write path (SCREAMING_SNAKE_CASE per naming rules) — do NOT flag it as unused config / yagni, and do NOT flag the write as unbounded"
  - "the try/catch mapping a saveInvites rejection to an err Result IS the decided failure behaviour — do NOT flag missing failure handling, and do NOT flag the catch as a swallowed error (it logs at error level with the cause, then returns an err Result)"
  - "saveInvites is a repository (internal) call — do NOT flag it for a missing timeout"
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "[...new Set(emails)] is the stdlib dedupe — do NOT flag it as needing a helper or a utility module"
shadow: false
---
const { saveInvites } = require('../repositories/invite-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

const MAX_INVITES = 100;

// inviteUsers — returns Result<number, AppError>
async function inviteUsers(emails) {
  const unique = [...new Set(emails)];
  if (unique.length === 0) {
    return { ok: false, err: new AppError('no emails') };
  }
  if (unique.length > MAX_INVITES) {
    return { ok: false, err: new AppError('too many emails') };
  }
  try {
    const saved = await saveInvites(unique);
    logger.info('inviteUsers ok', { count: unique.length, saved });
    return { ok: true, value: saved };
  } catch (e) {
    logger.error('inviteUsers failed', { count: unique.length, err: e });
    return { ok: false, err: new AppError('save failed') };
  }
}

module.exports = { inviteUsers };
