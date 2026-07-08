## Security Audit: getDocument — GET /api/documents/:documentId (round 1)
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| — | — | src/document.controller.js:15 | documentId / GET /api/documents/:documentId | none — ownership enforced in loadOwned before return | n/a |

**Verdict:** PASS

### Summary
- Sensitive surface touched: yes (request handler, owner axis)
- Sensitive fields in scope: 1 (documentId)
- Trust-boundary defects (P0): 0
- Controls confirmed: ownership — loadOwned() rejects with 404 unless doc.ownerId === session.userId (src/document.controller.js:4-12); actor id re-derived from req.session.userId, never from client; single 404 for "not yours" and "not found" — no existence oracle.

## Security-Sensitive Fields
- field: documentId
  endpoint: GET /api/documents/:documentId
  axis: owner
  required_control: session actor must own the document (doc.ownerId == session.userId); 404 for both not-owned and not-found
  abuse_test: "user A requests user B's documentId -> 404, no document data returned"

VERDICT: PASS p0=0 p1=0 round=1
