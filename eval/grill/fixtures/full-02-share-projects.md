---
fixture_id: full-02-share-projects
mode: spec
expected_tier: full
expected_signals: 7
planted_ambiguities:
  - share with whom (specific users, teams, public link)
  - what permissions the recipient gets (view, edit)
  - whether sharing can be revoked
  - whether the recipient is notified
  - "share" is undefined — a copy vs live shared access
  - edge case — a shared-with user is later deleted
  - edge case — the project owner is later deleted
answer_script:
  - asks_about: share with whom
    reply: specific users by email
  - asks_about: permissions
    reply: view-only for now
  - asks_about: revocation
    reply: yes, the owner can revoke at any time
  - asks_about: notification
    reply: email the recipient when first shared
  - asks_about: copy vs live
    reply: live access to the same project
  - asks_about: recipient deleted
    reply: drop the share silently
shadow: false
---
feat: let users share their projects
