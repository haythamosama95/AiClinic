# R2 — Contracts, service perimeter and human approval

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. 2026-10-16 Africa/Cairo. GPT-6.1 Sol source reviewers, with coordinator source verification and synthesis.

**Complete with findings: 0 P0, 4 P1, 3 P2.** This is the canonical R2 diagnosis, severity and remedy record; delegated reports preserve evidence, not additional finding counts. All 3,885 assigned primary lines and necessary caller/receiver seams are closed in [aggregate coverage](R2-coverage.md). Later business-phase coverage is not claimed. Findings are static source conclusions, not runtime reproductions. Application source remains unchanged; no tests, testkit, fixtures, vectors, harnesses, campaigns or viewer implementation reviewed, and no tests/builds/lint/services executed.

## Established contracts and authority

Canonical JWS helpers verify the original signed segments and compare their canonical payload to the supplied grant/receipt. SQL billing/feed producers emit the restricted canonical profile expected by their actual shared verifier. **R1-C1 remains canonical:** both billing/feed callers omit current-time validation. Its required clock/skew remedy must reach both callers. The custom AI verifier must retain SQL `jsonb::text` compatibility; replacing it with the strict canonical shared verifier would reject legitimate AI tokens. AI currently accepts equality at `exp+skew`; deliberately align it to R1-C1's strict expiry predicate if sharing clock logic. Unknown-key/`typ` profile differences are not independently established authority bypasses.

The service binding is the platform machine perimeter; public HTTP dispatch does not expose VendorEntrypoint. Human methods independently verify Access at the platform. Ordinary HP checks bind actor to the same Access email, verify RP/origin/get/UP+UV and active passkey, enforce ±5-minute freshness, and record replay. Credential owner email is recorded but the amended contract does not require owner-email equality. Pending credentials promote only after 24 hours. ABO refetches the active registry for each local HP request; absent pending/revoked/unknown IDs intentionally collapse to credential_not_active (082:1).

A unique challenge insertion before local mutation prevents two completed ABO mutations using the same challenge. It is separate from audit and mutation, so no transactional recovery claim follows. Platform methods use different consume/execute/receipt orderings; the precise [method-authority and replay matrix](R2-platform-coverage.md#method-authority--replay-matrix) records them. Required classes below describe **actual guards**, not the stale descriptive METHOD_CLASS constant.

| Class | Actual method map |
| --- | --- |
| M | Paid grant plus registered ABO signature; voidForReversal plus exact signed mutation; transferOut/transferIn against an already authorized transfer; listOperatorCredentials/listIssuerKeys/listServiceKeys/getCoverage/listGrants/readCoverageEvents/feedConsumerHealth. |
| H | suspend/resume/inspectCoverage/listGrantsForVoid; routing publish/canary/promote/rollback; kill-switch arm/disarm; capability deprecate/retire; cohort activate/promote; token-contract rotation/retire; supportLookup; recordOperatorAction; rebuildClinicDo/rebuildGrantLedger/refreshCoverageSnapshot. |
| HP | Operator/issuer/service key register/revoke and issuer retire; plan publish/retire; setCeilingPolicy; complimentary/adjustment grant and extra ceiling approval; beginTransfer/deleteInstallation/releaseHeld/voidGrant. First operator registration has the bounded H bootstrap exception. |
| ABO local HP | publish_offer/retire_offer/reinstate_offer/release_payment/manual_chargeback/erase_contact; local Access/passkey verification and platform active registry. |

| Channel | Wire/current accepted versions at T | Order/output qualification |
| --- | --- | --- |
| Desktop→ABO clinic; browser→ABO ops | Abo-Contract-Version; independent channels N=1, `[0,1]` | Host/path isolation precedes version/auth; unsupported response current=1 + accepted list; accepted Access refusal has C2 defect. No browser ceremony producer exists (P4). |
| Desktop→backend five RPCs | p_contract_version; `[0,1]` | Public gate precedes internal authorization; AI unsupported raises, composite RPCs return unsupported envelope; final billing refusals lose version (C2). |
| Desktop→platform clinic | Aip-Contract-Version; `[0,1]` | Gate before route auth; accepted header echoed, JSON body metadata incomplete (C2); clients do not validate replies (C3). |
| Backend→feed | Aip-Contract-Version; `[0,1]` | Separate platformFeed gate; page header/body echoed; SQL checks both plus requested cursor before applying. Authentication still has R1-C1. |
| ABO→VendorEntrypoint | contract_version; `[0,1]` | Per-method gate before Access/domain dispatch; unsupported envelope has current version but no accepted_versions field. See C2 contract reconciliation. |
| Worker→DO | contract_version; `[0,1]` | Gate before table setup/mutation; supported success echoes request; accepted error branches omit it (C2), several actual consumers trust unknown/rejection bodies (C3). N Worker→N+1 DO is accepted in N per 095:1. |
| Provider return/notify | Return v=1 query; provider adapter version=1 | Deliberately outside clinic/console header gate; return is UX/inquiry scheduling, not payment authority. Full intake/payment review remains R3. |
| Tokens/stored signed payloads | Token ver="2"; stored original contract_version | Token channels have distinct profiles; never rewrite a signed stored version. R4/R6/R9 own durable replay of stored payloads. |

ABO starts its signing-key refresh before host rejection and records version telemetry even on unsupported requests. Therefore “no write” is established for gated domain dispatch, not literally every bookkeeping write. R9 must reconcile startup/telemetry behavior with the stronger reference wording; no anonymous value mutation was established.

## Findings and ordered fixes

### R2-P1 — P1: local passkey authorization can be retargeted by URL

**High confidence; implementation-ready.** `abo/src/ops/index.ts:624–749` receives a route subject but never compares it with signed params; `handleHpPost:1372–1403` sends the independently chosen subject to execution. Release `1079–1159,3411–3421` releases that URL payment and queues grant work. Chargeback `1161–1294,3424–3434`, erase `1323–1370,3437–3447` and catalogue `882–1077,3366–3409` similarly use route-selected targets. This violates exact action-input binding in 04 §1.5.

Preconditions: valid same-actor Access session, fresh unused legitimate assertion, first-use URL substitution before consumption. An assertion for A can authorize B without changing signed bytes. No forged key, replay or second touch is assumed. No shipped browser producer exists, so this is a verified receiver defect for a correctly formed external submission, not a reproduced UI journey. [Detailed evidence](R2-abo-review.md#r2-abo-01--p1-local-hp-actions-do-not-bind-the-signed-target-to-the-url).

**Fix steps**

1. Add a signed-param validator in verifyHpRequest before replay consumption. Freeze maps: publish_offer `{offer_id,price_minor,terms_text,copy}`; retire/reinstate `{offer_id}`; release/manual chargeback `{payment_id}`; erase `{org_id}`. Require the exact key set and ID equal to the route subject; return assertion_invalid for mismatch.
2. Derive execution values only from that validated signed map; keep existing content/state checks. The missing producer in P4 must adopt these chosen field names before signing, with no post-signature injection or legacy unbound fallback.
3. Preserve unique replay reservation before mutation. Completion: A approval submitted to B rejects without B changes or challenge consumption; bound A succeeds once; wrong actor/action/version and concurrent reuse remain refused.

### R2-P2 — P1: ceiling override accepts an unrelated or stale second approval

**High confidence; implementation-ready.** `ai-platform/src/vendor/entrypoint.ts:1369–1399,1445–1449` accepts a supplied ceiling_override_operation with generic shape/op/signature/actor checks but no current envelope/args/version/freshness binding. ABO forwards it unchanged (`abo/src/ops/index.ts:2685–2686`). Success enables skipCeilingCheck (`entrypoint.ts:3346–3363,3483`; `quota-do/coverage.ts:1354–1368,1512–1526`). A compromised relay holding an unused old override and a fresh main grant approval can substitute the exception across tenant/amount/envelope. The fresh first touch is still required; the separately approved ceiling exception is bypassed. [Evidence](R2-platform-review.md#r2-pf1--p1-second-ceiling-assertion-is-not-bound-to-the-granted-operation).

**Fix steps**

1. In verifyCeilingOverrideAssertion require canonical params equality to `{contract_version:version,access_jwt:verifiedJwt,envelope:currentEnvelopeWithoutCeilingOverride}`, top-level negotiated version, op=ceiling_override and same verified Access actor. Permit independent nonce/issued_at for the separate ceremony, but apply assertionIssuedAtFresh and active-signer verification.
2. For absent explicit operation derive only the exact existing grant-metadata form; remove timestamp-search fallback `1400–1442`. Invalid clientDataJSON returns assertion_invalid. The P4 producer must send the explicit operation for separate-time ceremonies.
3. Verify replay against the actually verified digest, require it differ from the first digest, then insert **both** claims in one atomic D1 batch before dispatch. Keep duplicate rejection and AL-12 behavior; no main-only claim on second-claim failure.
4. Completion: changed org/envelope/actor/version or stale second approval never reaches coverage dispatch; correctly bound sequential touches work once; either digest's reuse fails or returns the exact completed result.

### R2-P3 — P1: concurrent bootstrap admits multiple unapproved passkeys

**High confidence; implementation-ready.** `entrypoint.ts:1947–1962` checks registry count before bootstrap's separately awaited plain INSERT `1903–1910`. Registry schema `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql:3–12` only uniquely constrains credential_id. Concurrent distinct IDs both see empty and both insert without an approving assertion. A valid Access identity is required. During first setup, a stolen Access session can race legitimate registration; extra credentials activate after 24h without subsequent-credential approval. Delay and AL-13 remain, so this is P1, not anonymous immediate compromise.

**Fix steps**

1. In bootstrapRegister replace plain INSERT with `INSERT ... SELECT ... WHERE NOT EXISTS (SELECT 1 FROM operator_credential)`. Decide from the statement's meta.changes, making emptiness and insertion one SQLite/D1 atomic statement; retain early count only as a fast refusal.
2. Zero changes returns assertion_required and no success alert; only the inserted winner receives bootstrap success audit/AL-13. Pending/revoked rows must also close bootstrap permanently. Preserve pending+24h and normal HP registration/idempotency.
3. Completion: simultaneous distinct no-assertion registrations create exactly one row; every later new credential requires HP, including while all credentials are pending or revoked.

### R2-P4 — P1: production operator approval has no browser ceremony

**High confidence; remedy not implementation-ready pending the explicit architecture decision.** Spec 082 FR-001 requires console WebAuthn get. Production source has no navigator.credentials/credentials.get caller; package operationChallenge is used only by verification. Complete ops dispatch (`abo/src/ops/index.ts:3303–3825`) returns JSON/404, worker has only version-gated ops API routing (`worker.ts:193–206,294–359`), and wrangler has no served browser asset/page. Thus backend assertion verification exists but a real operator has no shipped console entry point to obtain approvals. Full R8 forms remain outside this review. [Evidence and bounded design](R2-abo-review.md#r2-abo-03--p1-the-browser-passkey-ceremony-has-no-production-entry-point-or-producer).

**Fix steps / stop point**

1. **Maintainer/architecture owner must approve the bootstrap contract before routing changes.** Recommend an exact Access-gated GET /ops HTML shell exception while all JSON APIs retain mandatory version headers. Ordinary initial navigation cannot send the current custom header. Amend 04 §§2.3/7 and spec082 explicitly, or supply an approved alternative bootstrap contract. Stop before implementing any exception; no approval is implied here.
2. After that decision add `abo/src/ops/browser/shell.ts` and `ceremony.ts`, wire the approved exact shell route after host and Access checks, and add versioned authenticated `/ops/ceremony-context` returning verified actor, RP/origin/version and active `{credential_id,alg}` only. Define initial empty-registry registration separately through the existing registration relay.
3. Build the frozen P1 maps with package operationChallenge, exact actor/target/content, fresh issued_at/nonce; run navigator.credentials.get with required user verification; serialize authenticatorData/clientDataJSON/signature base64url plus matching alg for decodeAssertion. Submit the identical operation and signed bytes with the JSON version header.
4. Provide reusable platform-HP preparation using the platform's exact method maps and vendor version (including explicit override operation from P2); R8 supplies full forms/policy. Completion: an actual authenticated browser can obtain and submit each local approval; cancellation/inactive key/expired Access cause no mutation; shell handling never creates a JSON API version/auth bypass.

### R2-C1 — P2: exact HP binding depends on JSON insertion order

**High confidence; implementation-ready.** stableJson is JSON.stringify (`entrypoint.ts:914–916`); operationParamsMatch compares it at `999`. Canonical challenge hashing ignores property order, but canonical-wire params beginning access_jwt before contract_version differ from expected insertion order and are refused. Nested equivalent maps also fail. This is a supported-client interoperability defect.

**Fix steps:** (1) Replace that comparison with byte equality of canonicalize(params)/canonicalize(expected), treating canonicalization errors as failed match. (2) Reuse it in P2, preserving complete field equality. Completion: reordered identical maps accept; changed/extra/missing fields reject.

### R2-C2 — P2: receivers lose negotiated response metadata

**High confidence; implementation-ready; bounded compatibility impact.** Final billing errors omit rpc_error's version argument (`backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql:107,112,123,139,149,158,243`); actual helper defaults NULL (`20261007180000_issuer_key_custody.sql:210–221`). A doctor receives FORBIDDEN_ROLE with NULL version even for current 1. ABO verifyOpsAccess hardcodes 1 (`ops/index.ts:262–296`), losing accepted 0. DO accepted errors (`ai-platform/src/worker.ts:1809–1813,2014–2022`) omit version; HTTP wrapper `vendor/contract-version.ts:38–49` sets only headers, leaving coverage JSON `coverage-read/index.ts:139–145` and other public JSON unversioned. Vendor unsupported envelopes omit accepted_versions, while 04 §1.2's closed envelope and §7.2's accepted-list rule conflict.

**Fix steps**

1. Forward-override final issue_billing_token(integer), passing p_contract_version to every rpc_error including exception branches; do not alter canonical signing/authorization/throttle. Pass handleOps's negotiated version into verifyOpsAccess instead of hardcoding 1.
2. In Worker DO dispatch use a response helper carrying negotiated contractVersion on all post-negotiation success/error branches. Keep pre-parse malformed requests distinct. Extend withAipContractVersion to version application/json bodies as well as headers, including unsupported replies using current channel version. Preserve 304/empty bodies and SSE bytes; stream header must precede reading.
3. Reconcile the vendor contract additively: permit optional accepted_versions only on contract_version_unsupported, update VendorResultEnvelope/GrantResultEnvelope in `ai-platform/src/vendor/entrypoint.ts` and `packages/vendor-contracts/src/result-envelope.ts.validateResultEnvelope`, and have all entrypoint negotiation refusals fill `[N-1,N]`. Amend 04 §1.2 to permit this named optional field; do not change stored signed objects or accepted versions.
4. Completion: both accepted versions are echoed on all listed success/refusal/error paths; unsupported gates return current version and accepted list before domain/auth writes; ordinary forbidden-role/current-version errors are non-NULL; streams/304 remain valid. Deploy receiver fixes before C3 strict consumers.

### R2-C3 — P2: several senders interpret unrecognized replies as current protocol

**High confidence; implementation-ready after C2.** Actual DO transports cast HTTP-200 JSON without checking response version: entrypoint.callCoverageDo `603–625`, transfer.callCoverageDo `92–114`, coverage-read.callReadCoverage `42–65`, credit transports `105–109,143–146`, admission.callAdmissionDo `313–318`, rebuild/refresh `quota-do/coverage.ts:4140,4311`. A DO version refusal itself is HTTP200; coverage-read treats it as success and emits a 200 body missing snapshot fields (`124–145`) instead of coverage_unknown. This occurs with unsupported Worker/DO deployment skew; N→N+1 remains accepted. Desktop submit/discovery/usage likewise parse headers/JSON/SSE without checking response versions (`https_submit_port.dart:53–61`, `discovery_client.dart:62–80`, `usage_summary_client.dart:60–80`); ABO client only stores DTO versions, and RpcResult discards it. Safe evolution therefore depends on every receiver behaving perfectly rather than the required sender guard.

**Fix steps**

1. Add a shared DO response decoder requiring object, integer version equal to the sent version and a non-version-refusal result before any business cast. Use it at every listed transport, including rebuild/refresh. On unknown/refused versions return null in entrypoint/transfer/settle-fallback transports, `{ok:false,reason:'contract_rejected'}` in admission, `{ok:false,reason:'unavailable'}` in credit, and the existing not_found failure forms in rebuild/refresh. Make coverage-read explicitly emit taxonomy coverage_unknown with negotiated public metadata instead of a partial 200. Do not advance mutation/outcome/projection from an invalid response.
2. Add Dart response-version validation at versioned channel adapters before DTO/cache/SSE construction: platform HTTP header plus JSON body where present; ABO header/body; `frontend/lib/core/rpc/rpc_result.dart` retains the optional version, required at `core/ai/supabase_aat_mint_port.dart`, `features/ai/billing/billing_token_client.dart`, `features/ai/availability/ai_availability_reader.dart`, `features/ai/billing/subscription_summary.dart` and `features/ai/billing/checkout_screen.dart` (all beneath `frontend/lib/`). Leave unrelated legacy RPC callers compatible. Require the sent known version, route unsupported failures through existing typed update exceptions, and close an incompatible stream without consuming events.
3. Keep the feed puller's existing strict body/header/cursor checks. Completion: supported echoed previous/current versions succeed; missing/unknown/mismatched/refusal replies never update cached manifests, expose a coverage-success body or drive durable success; N Worker→N+1 DO still works. R4/R6/R7/R9 must verify their business failure propagation after decoder integration.

## Escalation closure, handoffs and limits

All 33 routed IDs have a bounded disposition in [coverage/escalations](R2-coverage.md#escalation-dispositions). Reference-only entries were dispositioned without opening their excluded implementation. R1-C1/C2/C3 and SQL findings are retained under their canonical IDs, not counted again.

R4 must establish receipt org/installation/grant/hash/result equality and durable outcome linkage, paid approval exact semantics, and recovery after a consumed complimentary approval with no DO apply. No automatic durable HP retry was established in the actual inline ABO relay. R6 must finish partial/tombstone/transfer business effects, old-assertion shortcut binding, and delete's dynamic binding across epochs; DO receipt replay and unique live-binding constraints are supporting facts, not full concurrency proof. R8 owns full forms and per-method policy/audit; P4 blocks usable approval until its bootstrap decision is resolved. R9 owns deploy Access/service binding/secret settings, startup telemetry writes, replay/audit/mutation crash recovery and stored-version rebuild support. R7 owns refresh throttle concurrency/error UX and the already inherited usage term-versus-snapshot consumer seam.

Static review cannot attest deployed account permissions, Access sessions/MFA settings, key ceremonies, actual environment overrides or provider behavior. **Only unresolved R2 remedy decision:** P4's initial browser-shell version/auth bootstrap contract, owned by maintainer/architecture; implementation stops before routing changes. This does not leave source coverage incomplete. Overall review remains in progress; R0/R1 preserved and R3–R10 not started.
