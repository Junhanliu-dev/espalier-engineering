---
name: espalier-security
description: Security audit checklist for {project} — trust-boundary review of client-supplied sensitive fields
---

# Security Audit — {project}

The audit answers one question for the change under review: **does the backend
trust any value the frontend sent that affects money, identity, permission, data
ownership, or a persistent write?** If yes, that is a defect. Load
`espalier/rules/security-standards.md` for the taxonomy and controls; this skill
is the *method* and the *test recipe*.

## Audit Method

1. **Find the trust boundary.** Which endpoints / handlers / queue consumers does
   the change touch? (Scope gate: no request-handling, queue/event consumer, auth,
   or persistence surface → NO SENSITIVE SURFACE, PASS. A message consumer receives
   external data just like an HTTP handler.)
2. **Enumerate client inputs** for each: path params, query, body, headers.
3. **Classify** each input on the five risk axes (money / identity / permission /
   owner / state). Skip non-sensitive inputs.
4. **Trace to the sink.** Follow each sensitive input to the authorization decision
   or the persistence call. The bug lives in the gap between "value arrived" and
   "value used" when nothing re-derives / re-authorizes / recomputes it.
5. **Verify the control.** Confirm the required server-side control is present
   (below). Missing or bypassable → P0/P1.
6. **Emit the abuse-test contract** — one entry per sensitive field.

## Control Checklist

- [ ] **Object ownership (BOLA / IDOR).** Every object loaded or mutated by a
      client-supplied id is guarded by an ownership or role check against the
      *session actor*. `id` from the request is a lookup key, never an authorization.
- [ ] **Money recomputation.** No client-supplied `price` / `amount` / `total` is
      persisted or charged. The authoritative value is looked up server-side and the
      total recomputed.
- [ ] **Permission server-decided.** `role` / `isAdmin` / `scope` are never bound
      from the request body. Authorization is read from the session or an authz store.
- [ ] **State machine.** Lifecycle fields (`status` / `approved` / `paid`) change
      only through a server-side transition that checks both legality and actor.
- [ ] **Stock / balance integrity.** Quantities are range-checked and applied
      atomically; no read-then-write race on a client quantity.
- [ ] **No mass assignment.** No raw request body spread into a persistence call;
      an explicit allow-list binds client-settable fields.

## Good vs. Bad (shape, not language)

```
# BAD — trusts the client
cart = db.cart.find(req.params.cartId)          # any id → any cart (IDOR)
order.total = req.body.price * req.body.qty      # client sets the price
user.update({ ...req.body })                     # isAdmin rides in on the body

# GOOD — re-derives / re-authorizes / recomputes
cart = db.cart.find_where(id=req.params.cartId, ownerId=session.userId)  # scoped by owner
if cart is None: return 404                       # 404 for "not yours" AND "not found" — no existence oracle
unit  = catalog.priceOf(req.body.sku)            # source of truth
order.total = unit * clamp(req.body.qty, 1, MAX) # recomputed + range-checked
user.update(pick(req.body, ['displayName']))     # allow-list, isAdmin excluded
```

## Abuse-Test Recipe

For every sensitive field the change touches, there MUST be a negative test. The
shape is always: **tamper → assert rejected → assert store unchanged.**

```
# owner axis — the canonical IDOR test
test "user A cannot read user B's cart":
  login as A
  GET /api/cart/{B_cart_id}
  assert status in (403, 404)
  assert response body contains none of B's cart items

# money axis — price tampering
test "checkout ignores a client-supplied price":
  POST /api/checkout { sku: "X", qty: 1, price: 0.01 }
  assert charged == catalog price of X   (or status 422)
  assert persisted order.total != 0.01

# permission axis — privilege escalation via mass assignment
test "profile update cannot set isAdmin":
  login as a normal user
  PATCH /api/me { displayName: "x", isAdmin: true }
  assert response ok
  assert db user.isAdmin == false        # unchanged

# state axis — illegal transition
test "client cannot force order paid":
  PATCH /api/orders/{id} { status: "paid" }
  assert status in (403, 422)
  assert db order.status != "paid"

# owner × state — the cross-axis IDOR (A must not touch B's object at all)
test "user A cannot change user B's order status":
  login as A
  PATCH /api/orders/{B_order_id} { status: "shipped" }   # even a legal transition
  assert status in (403, 404)
  assert db order(B_order_id).status unchanged
```

A test that only exercises the happy path does NOT satisfy the contract. The
assertion that the **persistent store is unchanged** after a tampered request is
the part that proves the control — do not omit it.

## Verdict

`PASS` (no sensitive surface, or all controls confirmed) / `PASS_WITH_FIXES`
(only P2/P3) / `FAIL` (any P0/P1). A P0 hard-blocks the Stage 4 panel and sends
the change back to `harness-coder`, then the panel re-audits.
