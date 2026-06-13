---
fixture_id: no-install-01-bare-repo
bucket: no-install
question: where is the HTTP server started
expected_type: where
expect:
  - detects there is NO espalier/ directory
  - answers from the code alone (src/server.ts)
  - writes NO sidecars (no espalier/.drift-state.tsv, no espalier/.ask-gaps.tsv)
  - does not crash or error
expect_drift: false
expect_gap: false
expect_no_espalier: true
---
=== FILE: src/server.ts ===
import express from "express";
const app = express();
// Server boots here.
app.listen(process.env.PORT ?? 3000, () => console.log("up"));
export default app;
=== FILE: package.json ===
{ "name": "bare", "main": "src/server.ts" }
