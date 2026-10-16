# Research: P4.2 checkout and Paymob intention

## 1. R-2 intention expiry default

**Decision:** `POST /v1/intention/` with `expiration` = 1800 is the expiry that call is taken to honor. Checkout `expires_at` is the ABO clock at creation plus 30 minutes. This unit verifies both against the H-PAY stub. A live Paymob test account is not used.

**Rationale:** 04 §5.3 already sends `expiration` = 1800 s on `createCheckout`. E2E-P4.2-01 expects `expires_at` = +30 min. OQ-3, as amended, binds that outcome when no Paymob test integration is provisioned. The adapter sends `expiration: 1800`. The ABO sets `expires_at` from `clockNowMs` plus 1 800 000 ms. E2E-P4.2-01 reads the stub's captured intention body and the checkout response. The remaining R-2 items (redelivery, a second success on one intention, order listing, rate limits) stay with P4.3.

**Named fallback:** 05 §10 names inquiry sweeps for R-2. That fallback is not taken. The bound outcome holds, so expiry stays 30 minutes and is not left to a later sweep.

**Alternatives considered:** Calling the Paymob sandbox was not possible here. OQ-3 says this unit does not stop for that, and does not require a live account.
