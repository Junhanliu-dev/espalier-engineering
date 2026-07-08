---
fixture_id: sourced-01-checkout-flow
bucket: docs-first
question: how does a checkout order get processed from request to confirmation
expected_type: how
expect:
  - reads espalier/wiki/architecture.md FIRST (before crawling the codebase)
  - traces the flow across ALL of the route, controller, service, payment client, and repository files
  - EVERY step in the answer carries its own file:line source — a prose summary that only cites the wiki (or only one or two of the five files) is unsourced and should score sourced < 2
  - cites the wiki AND each code file it verified
  - no drift flag (doc matches code), no gap row
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/wiki/architecture.md ===
# Architecture

## Checkout

`POST /checkout` is registered in `src/routes.ts` and handled by
`CheckoutController.create()` in `src/checkout/controller.ts`. The controller
delegates to `CheckoutService.process()` in `src/checkout/service.ts`, which
(1) charges the card through `PaymentClient.charge()` in
`src/payment/client.ts`, then (2) persists the order via
`OrderRepo.save()` in `src/checkout/repo.ts`, and finally returns a
confirmation id. A failed charge throws before anything is persisted.
=== FILE: src/routes.ts ===
import { CheckoutController } from "./checkout/controller";
export function registerRoutes(app) {
  app.post("/checkout", CheckoutController.create);
}
=== FILE: src/checkout/controller.ts ===
import { CheckoutService } from "./service";
export class CheckoutController {
  static async create(req, res) {
    const result = await CheckoutService.process(req.body.cart, req.body.card);
    res.json({ confirmationId: result.confirmationId });
  }
}
=== FILE: src/checkout/service.ts ===
import { PaymentClient } from "../payment/client";
import { OrderRepo } from "./repo";
export class CheckoutService {
  static async process(cart, card) {
    const charge = await PaymentClient.charge(card, cartTotal(cart));
    const order = await OrderRepo.save({ cart, chargeId: charge.id });
    return { confirmationId: order.id };
  }
}
=== FILE: src/payment/client.ts ===
export class PaymentClient {
  static async charge(card, amountCents) {
    const res = await stripe.charges.create({ source: card, amount: amountCents });
    if (res.status !== "succeeded") throw new PaymentError(res.status);
    return { id: res.id };
  }
}
=== FILE: src/checkout/repo.ts ===
export class OrderRepo {
  static async save(order) {
    const row = await db.orders.insert({ ...order, createdAt: Date.now() });
    return { id: row.id };
  }
}
