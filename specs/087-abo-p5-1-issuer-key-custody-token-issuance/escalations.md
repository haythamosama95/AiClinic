# P5.1 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Backend issuer-key status and switch signing

**Question:** Which `status` values on `ai_internal.issuer_key` distinguish the kid that signs new tokens, the next kid that is not yet signing, and a kid that no longer signs, and what operation performs the 02 §6 “switch signing” step?

**Assumption:** `status` is `signing`, `next`, or `retired`. Exactly one row is `signing` (that `kid` signs new tokens). At most one row is `next` (generated, not yet signing). `retired` no longer signs. The first `kid` is inserted as `signing`; a later `kid` is inserted as `next`. `auth_internal.switch_issuer_signing_kid(p_kid)` is the switch-signing step: it moves that `next` row to `signing` and the previous `signing` row to `retired`, and it changes nothing unless `p_kid` is `next`. It is not a public RPC, and no clinic role can call it. Platform `active` / `retiring` / `revoked`, and `retireIssuerKey`, stay the verifier-side statuses.

**Why:** 03 §3.2 `active`, `retiring`, and `revoked` say which `kid`s the platform still accepts, and two `active` kids coexist, so those values do not say which backend row signs. K-2 already separates “switch signing” from the later `retireIssuerKey` step. The switch belongs in `auth_internal`, with the other issuer bodies, and stays off the public RPC list that 04 §3.1 already closed to clinic users.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§4 row `ai_internal.issuer_key`); `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§6 row K-2); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P5.1 Implements).

## 2. Full-stack registerIssuerKey without the Vitest clock

**Question:** E2E-P5.1-06 must call the consumed `VendorEntrypoint.registerIssuerKey` from the H-FS harness worker on `wrangler dev`. That method checks an Access JWT by fetching `https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`, and a new operator credential stays `pending` for 24 hours. H-AP satisfies both only inside Vitest (fetch intercept and the test clock). H-FS `wrangler dev` has neither, the test must not sleep, and `TEST_CLOCK` stays off the wrangler envs. How does that call succeed on the local full stack without changing the platform?

**Assumption:** The H-FS runner starts the platform with wrangler's programmatic local worker (`startWorker`), the same local workerd as `wrangler dev`, and passes `dev.mockFetch` so only `GET https://${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs` is answered. The certs document and the Access JWT come from `packages/vendor-contracts` testkit `createAccessTeam`, with wall-clock `iat` and `exp`. The signer is not created by `registerOperatorCredential`. The runner inserts one `operator_credential` row in the local platform D1 with `status = 'active'`, `activates_at` at or before wall-clock now, and `operator_email`, `alg`, and `public_key_cose` matching the Access JWT email and the key that signs the assertion. `issued_at` is wall-clock now. `TEST_CLOCK` is not set. Platform source, wrangler envs, and the 24-hour pending insert stay as they are. The ABO process stays CLI `wrangler dev`.

**Why:** `loadAccessCerts` always fetches that URL, and `registerOperatorCredential` always sets `activates_at` 24 hours ahead. Vitest `fetchMock` and the test clock exist only in H-AP. `startWorker`'s `mockFetch` answers that one fetch in the local dev process, and an already-active D1 row satisfies the HP credential check on wall-clock time, so the test does not sleep and does not turn `TEST_CLOCK` on.

**Amended:** `specs/087-abo-p5-1-issuer-key-custody-token-issuance/spec.md`
