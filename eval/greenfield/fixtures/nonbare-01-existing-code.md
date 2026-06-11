---
fixture_id: nonbare-01-existing-code
entry: espalier-new
expected_track: n/a
expected_max_rounds: 0
expected_behaviors:
  - runs the bare check and finds the repo is NOT bare (src/server.ts and package.json present)
  - warns and stops - points the user to /espalier-init instead
  - does not start the interview
forbidden_behaviors:
  - proceeds to grill or scaffold into the non-empty repo
  - silently falls through to normal init without telling the user
answer_script: []
note_for_runner: >
  EVAL MODE override for this fixture only: treat the repo as NON-bare —
  the bare-check find command returns ./package.json and ./src/server.ts.
shadow: false
---
/espalier-new — scaffold me a fresh Next.js app right here.
