---
id: 03-tempting-deletion
kind: must-not-delete
expect:
  wiki/architecture.md: NO-IMPACT
  wiki/data-models.md: NO-IMPACT
  wiki/critical-paths.md: NO-IMPACT
  wiki/external-services.md: PROPOSE-REMOVAL
  rules/coding-standards.md: NO-IMPACT
forbidden_removal: SendGrid
---

The diff deletes `accounts/notify.py`, the only caller of SendGrid — so
`external-services.md`'s SendGrid bullet now looks dead. It must NOT be
deleted: removal is prune's protocol, and the sweep cannot see from this diff
whether another entry point, a scheduled job or a downstream consumer still
depends on it. The correct behaviour is a `### Proposed Removals` line and no
edit to the file's SendGrid text.

A sweep that quietly drops the bullet fails this fixture even though its
reasoning was locally correct.

## DIFF

```diff
--- a/accounts/notify.py
+++ /dev/null
@@ -1,20 +0,0 @@
-import os
-import httpx
-
-_SENDGRID = "https://api.sendgrid.com/v3/mail/send"
-
-
-def send_welcome(email: str) -> None:
-    httpx.post(
-        _SENDGRID,
-        headers={"Authorization": f"Bearer {os.environ['SENDGRID_KEY']}"},
-        json={"to": email, "template": "welcome"},
-        timeout=10.0,
-    )
--- a/accounts/service.py
+++ b/accounts/service.py
@@ -1,6 +1,5 @@
 from accounts.models import Account
-from accounts.notify import send_welcome
 
 
 def register(email: str) -> Account:
@@ -9,5 +8,4 @@ def register(email: str) -> Account:
     acct = Account(email=email)
     storage.accounts.save(acct)
-    send_welcome(email)
     return acct
```

## DOCS

### wiki/architecture.md

```markdown
# Architecture

Three layers: `api/` (HTTP handlers), `billing/` and `accounts/` (services),
`storage/` (persistence).
```

### wiki/data-models.md

```markdown
# Data Models

- `Account` — id, email, created_at.
```

### wiki/critical-paths.md

```markdown
# Critical Paths

- Registration: `api/accounts.py:register` → `accounts.service.register` →
  `storage.accounts.save`.
```

### wiki/external-services.md

```markdown
# External Services

- **Postgres** — primary store, reached only through `storage/`.
- **SendGrid** — transactional email, called from `accounts/notify.py`.
```

### rules/coding-standards.md

```markdown
# Coding Standards

- Every outbound HTTP call sets an explicit timeout.
```
