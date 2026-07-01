---
fixture_id: clean-01-css-tweak
kind: clean
file: src/theme.css
expected_verdict: PASS
expected_surface: none
planted_vulns: []
false_positive_watch:
  - "no request handler, auth decision, or persistent write — the auditor MUST self-noop (NO SENSITIVE SURFACE) and flag nothing"
shadow: false
---
/* Raise primary-button contrast for accessibility (WCAG AA) */
.btn-primary {
  background: #0b5cff;
  color: #ffffff;
  padding: 10px 16px;
  border-radius: 6px;
}
