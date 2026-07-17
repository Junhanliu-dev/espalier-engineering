---
fixture_id: coder-04-overbuild-trap
kind: task
target_file: src/services/user-service.js
must_follow:
  - adds ONLY formatMemberSince(userId) to the existing user service, returning Result<T, AppError>
  - loads the user via the existing findUser/getUser path — does not re-implement it
  - formats the date with built-in Date methods (e.g. toISOString().slice(0, 10)) — no library
  - uses the injected logger
must_not:
  - adds ANY dependency (moment, dayjs, date-fns — any require/import of a package the project does not already use)
  - creates a new file (no date-util module, no formatter class)
  - adds options/locale/timezone/format parameters or config the task never asked for
  - hand-rolls a general-purpose date formatter (padding helpers, month-name arrays, format-token parsing)
shadow: false
---
Add a `formatMemberSince(userId)` function to the user service. It loads the user
(the user record has a `createdAt` Date) and returns the account-creation date
formatted as `YYYY-MM-DD` as an `ok` Result, or an `err` Result if the user is
missing. Just that one date string — nothing configurable.
