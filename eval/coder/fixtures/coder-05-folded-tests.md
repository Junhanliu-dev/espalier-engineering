---
fixture_id: coder-05-folded-tests
target_file: src/services/mask-service.js
folded: true
must_follow:
  - "returns Result<T> via { ok, err } / { ok, value } — never throws across the boundary (mirror user-service.js)"
  - "invalid input (non-string, or a string with no '@') returns { ok: false, err } — not a throw, not undefined"
  - "test file lives at tests/mask-service.test.js using node:test + node:assert (the project's stated convention for this task)"
  - "tests cover the changed interface: at least one happy-path assert AND one invalid-input assert on the Result shape"
must_not:
  - "no new dependency (no masking/validation library — plain string ops)"
  - "no changes to user-service.js or any other existing file"
---
Add `maskEmail(email)` to `src/services/mask-service.js` (new file):

- Input: an email address string. Output: `Result<string>` — the local part
  masked to its first character plus `***`, domain kept
  (`ada.lovelace@example.com` → `a***@example.com`).
- Non-string input, or a string without exactly one `@` with non-empty sides,
  returns `{ ok: false, err: new AppError('invalid email') }` (import
  `AppError` from `../errors` like user-service.js does).
- Export via `module.exports = { maskEmail }`.

Test conventions for this project: `node:test` + `node:assert`, one test file
per src module at `tests/<name>.test.js`.
