# P4.2 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Checkout billing-token jti and the Paymob return `v`

**Question:** 04 §2.2 Rules require the billing token’s `jti` to be stored on the checkout fact, but the 03 §2.4 `checkout` field list names no column for it. The unit row also requires `return_url` with `v`, and the cited spans do not say what value `v` carries.

**Assumption:** The checkout fact stores that `jti` in `billing_token_jti`. On the Paymob return URL, `v` is the browser-return channel's integer contract version, set to the current version when the ABO builds `return_url` (1 at launch).

**Why:** 04 §2.2 already requires the billing token `jti` on the checkout fact, and 02 records that `jti` on every checkout; the missing piece was the column name on the append-only fact. `v` is the same kind of integer contract version §7.1 gives every channel, carried as a query parameter because the browser return is a redirect, and every channel starts at 1.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§2.4); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§7.1).

## 2. R-2 intention expiry without a Paymob test account

**Question:** The R-2 spike must confirm, on the Paymob test integration, that `POST /v1/intention/` with `expiration` = 1800 s is the expiry the API honors, so checkout `expires_at` is creation plus 30 minutes. No Paymob secret key, card integration id, or public key is present in the environment or in `abo` config. OQ-3 says that if that integration is not provisioned, P4.2 stops at the spike step.

**Assumption:** `POST /v1/intention/` with `expiration` = 1800 s is the expiry that call is taken to honor, and checkout `expires_at` is creation plus 30 minutes. P4.2 records that outcome and verifies `expiration` and `expires_at` against the H-PAY stub. A live Paymob test account is not required for this unit.

**Why:** 01 §3.3 already sets checkout expiry explicitly to 30 minutes, and 04 §5.3 already sends `expiration` = 1800 s. The missing piece was whether the API honors that field, which OQ-3 would not let P4.2 assume without a provisioned test integration. No such integration is available here. The stub can check that the adapter sends 1800 s and that `expires_at` is creation plus 30 minutes. The other R-2 items stay with P4.3. P5.2 still stops if the staging Supabase project is missing.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (§2 S6; §6 OQ-3); `docs/architecture/ai-billing-orchestration/01-abo-design-decisions.md` (§7 R-2); `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (§10 Spike-dependent items).
