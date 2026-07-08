---
fixture_id: clean-03-guarded-helper
kind: clean
file: src/document.controller.js
expected_verdict: PASS
expected_surface: sensitive
planted_vulns: []
false_positive_watch:
  - "documentId is loaded by client id BUT assertOwner() re-authorizes against the session actor one hop away in the same file — reading the helper is required; flagging IDOR here is a false positive"
  - "the 404 on a not-owned doc is intentional (no existence oracle) — not a defect"
shadow: false
---
const db = require('./db');

// throws 404 unless the session actor owns the document
async function loadOwned(documentId, sessionUserId) {
  const doc = await db.documents.findById(documentId);
  if (!doc || doc.ownerId !== sessionUserId) {
    const err = new Error('not found');
    err.status = 404;
    throw err;
  }
  return doc;
}

// GET /api/documents/:documentId
async function getDocument(req, res) {
  try {
    const doc = await loadOwned(req.params.documentId, req.session.userId);
    return res.json(doc);
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
}

module.exports = { getDocument };
