---
fixture_id: light-01-csv-export
mode: spec
expected_tier: light
expected_signals: 3
planted_ambiguities:
  - which of the report types on the page is exported
  - the current visible page vs the full dataset
  - which columns the CSV includes
answer_script:
  - asks_about: which report
    reply: the summary report only
  - asks_about: page vs full dataset
    reply: the full dataset
  - asks_about: columns
    reply: the columns currently visible in the table
shadow: false
---
feat: add a CSV export button to the reports page
