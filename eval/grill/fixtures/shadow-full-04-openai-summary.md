---
fixture_id: shadow-full-04-openai-summary
mode: spec
expected_tier: full
expected_signals: 6
planted_ambiguities:
  - '"report summary" is one noun but three separate fields — which is generated?'
  - no trigger or actor — automatic on save, or user-initiated?
  - is generated text persisted directly, or editable before it is saved?
  - no model, temperature, or token cap named — "OpenAI integration" is unmeasured
  - no failure behaviour — what happens when the API errors or the key is missing?
  - scope unstated — does the API key live in env, or is it admin-configurable?
answer_script:
  - asks_about: which summary / what gets generated
    reply: the report has three separate summary fields — Executive Summary, Key Conclusions, Recommendations. Generate one field at a time, not all three at once.
  - asks_about: trigger / actor
    reply: user-initiated. Each of the three cards gets its own Generate button; nothing generates automatically on save or on report creation.
  - asks_about: persisted automatically or editable first
    reply: generation only fills the textarea. The user edits it and clicks Save separately — generating never writes to the database.
  - asks_about: model / generation parameters
    reply: OpenAI gpt-4o-mini, temperature 0.7, max 2000 output tokens. The prompt gets the whole report record — dates, client, insurer, property info, weather, witness interviews, evidence, reviews, plus any existing summary text.
  - asks_about: failure behaviour
    reply: surface it as an error toast and leave the textarea untouched. No retry. Unauthenticated callers are rejected before the API is called.
  - asks_about: scope boundary / API key
    reply: the key is read from the Setting record in the database so an admin can change it, not from an env var. A missing key is an error, not a silent skip. Storage columns become nullable LongText. No PDF or auto-regeneration work.
shadow: true
---
feat: open ai integration for report summary
