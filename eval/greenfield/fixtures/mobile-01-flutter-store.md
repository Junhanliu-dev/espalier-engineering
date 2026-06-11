---
fixture_id: mobile-01-flutter-store
entry: espalier-new
expected_track: mobile
expected_max_rounds: 5
expected_behaviors:
  - resolves Flutter as framework (user signals no web team, wants both platforms)
  - asks about backend and lands on Supabase (BaaS default) given no backend exists
  - store stubs planned with TODO credentials - fastlane config + runbook
  - offers guided store setup but does not require accounts to finish init
  - verification gate excludes emulator boot (analyze + test + debug build)
forbidden_behaviors:
  - blocks setup on Apple/Google accounts or signing certificates
  - puts store credentials or signing keys into repo files
answer_script:
  - asks_about: mode (express or full)
    reply: full
  - asks_about: example repo
    reply: no
  - asks_about: stack research depth
    reply: hybrid
  - asks_about: what the product does
    reply: a habit tracker with streaks and reminders, iOS and Android
  - asks_about: audience / scale
    reply: consumer app, hoping for a few thousand users
  - asks_about: framework
    reply: no preference, team is new to mobile
  - asks_about: backend
    reply: nothing exists yet, simplest thing that works
  - asks_about: store launch
    reply: yes eventually, no developer accounts yet
shadow: false
---
We want to build a mobile app for habit tracking. Both app stores
eventually. Nothing exists yet.
