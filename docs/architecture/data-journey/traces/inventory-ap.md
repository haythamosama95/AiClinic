# Inventory: AP (ai-platform)

Area: `ai-platform/` (src, migrations, manifests, prompts, control, context, wrangler.toml). Compiled from the code only. Assigned group is empty.

## Counts

| Category | Count |
|---|---|
| HTTP routes (public fetch handler of the gateway Worker) | 7 |
| Durable Object RPC kinds and handlers (class GatewayObject) | 26 |
| VendorEntrypoint RPC methods (control plane / operator / ABO surface; reached through service binding, not HTTP) | 54 |
| D1 tables, columns, indexes, triggers (database binding DB) | 501 |
| D1 migration files | 40 |
| R2 prefixes and object types (bucket binding R2) | 5 |
| Durable Object state (class GatewayObject) | 117 |
| Durable Object outbox row kinds (outbox.kind) | 7 |
| Coverage event kinds (coverage_event.kind, feed events) | 10 |
| Platform alert codes (platform_alert.code) | 10 |
| Cron schedules, scheduled jobs and alarms | 19 |
| Manifests, prompt artifacts and bundled control artifacts | 14 |
| Outbound calls (providers, ABO, Supabase, other) | 10 |
| SSE event types (POST /v1/requests response, text/event-stream) | 10 |
| Error codes, result values and reason codes | 265 |
| Environment variables, secrets and bindings | 33 |
| Custom request/response headers and query parameters | 7 |
| Total | 1135 |

## HTTP routes (public fetch handler of the gateway Worker)

The gateway Worker (`ai-platform-gateway`) exposes only the fetch routes below. There is no HTTP control-plane or ops route: the operator/control plane is reached by service binding (see the VendorEntrypoint section). The Worker also has `scheduled` and a Durable Object class.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ROUTE-001 | GET /health | HTTP route (public fetch handler) | worker entry | | No auth. Returns JSON with build (BUILD_SHA) and environment (ENVIRONMENT). |
| AP-ROUTE-002 | GET /v1/capabilities | HTTP route (public fetch handler) | worker entry; discovery; capability | | Auth: Authorization Bearer AI token (AAT, audience ai-platform). Header Aip-Contract-Version required (channel platformClinic; unsupported gives 400 body with code and accepted_versions). Optional If-None-Match; 304 with ETag and Cache-Control private, must-revalidate; 200 body {manifests}. Errors use the taxonomy error body (401 unauthenticated, 403 installation_suspended). |
| AP-ROUTE-003 | GET /v1/feed/coverage | HTTP route (public fetch handler) | worker entry (feed handler) | | Auth: Authorization Bearer JWT, audience ai-platform-feed, signed by an issuer_key row (kid in JWT header), issuer must equal ISSUER_ID; any auth failure is a bare 401. Header Aip-Contract-Version required (channel platformFeed; unsupported gives 400 {contract_version, code, accepted_versions}). Query after (default 0) and limit (1..200, default 200). Reads coverage_event; upserts feed_consumer row 'backend-feed'. Body {contract_version, after, events[], next_after, has_more}. |
| AP-ROUTE-004 | POST /v1/requests | HTTP route (public fetch handler) | worker entry; adapter; pipeline | | Auth: Bearer AAT. Required headers: Aip-Contract-Version, x-idempotency-key, x-capability-version; optional x-trace-id. Body: JSON object up to 1,048,576 bytes (capability_id or capability, user_intent or intent, context object, etc.). Responds as text/event-stream (SSE) after pre-accept guard; pre-accept failures are JSON taxonomy bodies; bare 422 for unparseable body/missing headers; 413 request_too_large. |
| AP-ROUTE-005 | GET /v1/requests/{reference} | HTTP route (public fetch handler) | worker entry; journal | | Auth: Bearer AAT. Header Aip-Contract-Version required. Path suffix is the request reference (normalized once). 404 with empty body when unknown or empty reference. 200 JSON {state:Completed,result?} \| {state,pending:true} \| {state:Failed,terminal_error_code} \| {state:AwaitingContext} \| {state:Cancelled}. Auth failure uses taxonomy body (401 unauthenticated, 403 installation_suspended). |
| AP-ROUTE-006 | GET /v1/coverage | HTTP route (public fetch handler) | worker entry; coverage-read | | Auth: Bearer AAT with role administrator (else bare 403); suspended installations are allowed through. Header Aip-Contract-Version required. Calls DO kind read_coverage. Body {subscription_ref, snapshot, queued_terms, recent_terms}. Errors: 401/403 taxonomy, 503 coverage_unknown (DO contract rejected), 500 internal_error. |
| AP-ROUTE-007 | Any other method/path | HTTP route (public fetch handler) | worker entry | | Falls through to 404 with text body 'Not Found'. No other HTTP routes exist on the gateway Worker (no ops/control-plane HTTP routes). |

## Durable Object RPC kinds and handlers (class GatewayObject)

Every fetch to the Durable Object is POST JSON with an optional contract_version (channel platformDo; missing/unsupported returns 200 body result rejected, code contract_version_unsupported, accepted_versions). Response always carries contract_version. Unknown kind: 400 unknown_kind. Invalid JSON: 400 invalid_json. Recovery building/blocked: 409 result recovery_blocked (except rebuild_clinic_do). Other exceptions: 500 internal_error; ArgValidationError: 400 bad_request. The Durable Object id is derived from the installation id (idFromName).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-DORPC-001 | admission | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch; quota-do | | Request fields jti, installationId, idempotencyKey, requestReference (+ idempotencyBinding, journaledAnswer, journaledConflict, entitlement, quotaWeight, nowIso, ...). Validates args (400 bad_request on ArgValidationError). May hold/throw on harness fault when TEST_CLOCK=1. |
| AP-DORPC-002 | settleFallback | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields installationId, request_id, term_id, weight>=1, outcome consumed\|released. 400 invalid_settle_fallback_args. |
| AP-DORPC-003 | ackUsageReceipt | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields request_id, installationId, term_id, weight>=1. 400 invalid_ack_usage_receipt_args. |
| AP-DORPC-004 | credit | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields installationId, requestId, requestReference, usage, partial, term_id, outcome consumed\|released, idempotencyState failed\|cancelled\|completed, entitlement. |
| AP-DORPC-005 | release | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields installationId, requestId, idempotencyKey, jti. |
| AP-DORPC-006 | inspect | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Read-only snapshot of legacy KV state (key 'state'). |
| AP-DORPC-007 | apply_grant | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Applies a grant; passes PLATFORM_SIGNING_KEY and DB. Used by VendorEntrypoint.grant. |
| AP-DORPC-008 | seal_grant_route | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields installationId, orgId, grantId, envelopeSha256, routeGeneration, bindingEpoch, sealedAt. 400 result conflict on bad args. |
| AP-DORPC-009 | seal_ceiling_claim | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Fields installationId, orgId, grantId, envelopeSha256, routeGeneration, bindingEpoch, nowIso; uses PLATFORM_SIGNING_KEY and DB. |
| AP-DORPC-010 | read_coverage | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Used by GET /v1/coverage and getCoverage. |
| AP-DORPC-011 | suspend | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Shared handler with resume. |
| AP-DORPC-012 | resume | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Shared handler with suspend. |
| AP-DORPC-013 | count_terms | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Used by countLedgerRows. |
| AP-DORPC-014 | inspect_coverage | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Used by inspectCoverage. |
| AP-DORPC-015 | void_for_reversal | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Passes DB. |
| AP-DORPC-016 | release_held | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | |  |
| AP-DORPC-017 | recover_stranded_term | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | |  |
| AP-DORPC-018 | void_grant | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | |  |
| AP-DORPC-019 | open_awaiting_transfer | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | |  |
| AP-DORPC-020 | transfer_out | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Passes DB. |
| AP-DORPC-021 | transfer_in | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Passes DB. |
| AP-DORPC-022 | set_transfer_pending | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | |  |
| AP-DORPC-023 | rebuild_clinic_do | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Passes DB, R2, PLATFORM_SIGNING_KEY. Only kind allowed while recovery_state is building/blocked. |
| AP-DORPC-024 | refresh_coverage_snapshot | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | | Passes DB, R2; persists shipped alerts (AL-11/12/17/19) to platform_alert. |
| AP-DORPC-025 | GatewayObject.drainForHarness() | Durable Object RPC method (not fetch) | worker GatewayObject | | Only when ENVIRONMENT=development and TEST_CLOCK=1; runs alarm, requires empty outbox, deletes alarm. |
| AP-DORPC-026 | GatewayObject.alarm() | Durable Object alarm handler | worker GatewayObject | | Ships coverage outbox (shipCoverageOutboxAlarm); persists shipped alerts; if recovery_state is building/blocked, re-arms alarm 60 s later. |

## VendorEntrypoint RPC methods (control plane / operator / ABO surface; reached through service binding, not HTTP)

Class `VendorEntrypoint extends WorkerEntrypoint`. Every method takes one args object. contract_version is negotiated on channel vendorEntrypoint (accepted current and current-1; missing or unsupported returns result rejected, code contract_version_unsupported, accepted_versions). Result envelopes: {contract_version, result ok|rejected|conflict (grant methods also applied|already_applied|transient), code, detail, receipt?}. Methods are invoked by the ABO and the operator console over a service binding; the AP itself binds VENDOR to its own VendorEntrypoint for the cron-driven dispatchers.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ENTRY-001 | drainDurableObjectsForHarness | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | Internal/harness or cron-only entry (no operator auth). args installation_ids; harness only (error harness_drain_unavailable / harness_drain_invalid_installations). |
| AP-ENTRY-002 | registerOperatorCredential | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, assertion, attestation, credential_id. First credential bootstraps (raiseAl13Bootstrap); later ones need approval. |
| AP-ENTRY-003 | revokeOperatorCredential | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, credential_id. |
| AP-ENTRY-004 | listOperatorCredentials | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns active credentials (credential_id, public_key_cose, alg); promotes due credentials first. |
| AP-ENTRY-005 | registerIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid, public_key, not_before, not_after. |
| AP-ENTRY-006 | listIssuerKeys | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). |
| AP-ENTRY-007 | countLedgerRows | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns {terms, grants, installations}; calls DO count_terms per installation. |
| AP-ENTRY-008 | readLaunchState | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns channel_versions, environment, signing_key public half (kid, public_key) or null. |
| AP-ENTRY-009 | retireIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-010 | revokeIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-011 | registerServiceKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid, public_key, not_before, not_after (service key e.g. ABO). |
| AP-ENTRY-012 | revokeServiceKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-013 | listServiceKeys | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). |
| AP-ENTRY-014 | publishPlanVersion | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit, max_allowance_per_month. |
| AP-ENTRY-015 | retirePlanVersion | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args plan_id, version. |
| AP-ENTRY-016 | setCeilingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args per_grant_max_days, per_grant_max_allowance_months, window_days, window_max_days, window_max_allowance_months, max_paid_grace_days, paid_cap_rule, operation. |
| AP-ENTRY-017 | grant | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Receives ABO-signed grant (envelope / envelope_b64 / envelope_json / grant_rpc_json, abo_kid, abo_signature); optional ceiling_override_operation (HP assertion for complimentary override); accepted_command_dispatch/accepted_command_grant_id used by the 5-minute dispatcher. Applies grant via DO apply_grant; writes grant_claim, grant_ledger, etc. |
| AP-ENTRY-018 | beginTransfer | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args org_id, from_installation_id, reason, operation, signer_credential_id. |
| AP-ENTRY-019 | transferOut | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args transfer_id. |
| AP-ENTRY-020 | transferIn | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args transfer_id. |
| AP-ENTRY-021 | deleteInstallation | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args org_id, reason, operation, signer_credential_id; transient detail deletion_pending. |
| AP-ENTRY-022 | voidForReversal | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). ABO-signed reversal (abo_kid, abo_signature); args reversal_id, grant_id, partial, reason, evidence_sha256. |
| AP-ENTRY-023 | releaseHeld | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args grant_id, reason, operation. |
| AP-ENTRY-024 | recoverStrandedTerm | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args action_id, org_id, installation_id, binding_epoch, target_term_id, source_grant_id, expected_clinic_seq, reason, evidence_sha256, operation, signer_credential_id. |
| AP-ENTRY-025 | voidGrant | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args grant_id, reason, operation. |
| AP-ENTRY-026 | listGrantsForVoid | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args credential_id, window (list helper for voidGrant). |
| AP-ENTRY-027 | suspend | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id, reason; Access JWT required; calls DO suspend then updates installation.status via setInstallationSuspendedAction. |
| AP-ENTRY-028 | resume | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id, reason; calls DO resume then installation.status. |
| AP-ENTRY-029 | inspectCoverage | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id; calls DO inspect_coverage. |
| AP-ENTRY-030 | getCoverage | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args org_id, installation_id; calls DO read_coverage. |
| AP-ENTRY-031 | listGrants | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args org_id, source_kind, applied_from, applied_to, credential_id. |
| AP-ENTRY-032 | readCoverageEvents | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args after, limit; reads coverage_event. |
| AP-ENTRY-033 | publishRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args document; control/routing-policy action (writes R2 + routing_policy). |
| AP-ENTRY-034 | canaryRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, installation_ids, cohort_name. |
| AP-ENTRY-035 | promoteRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, expected_generation. |
| AP-ENTRY-036 | rollbackRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, expected_generation. |
| AP-ENTRY-037 | armKillSwitch | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args scope (global\|capability\|installation\|provider), target; writes AL-19 alert. |
| AP-ENTRY-038 | disarmKillSwitch | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args scope, target; writes AL-19 alert. |
| AP-ENTRY-039 | deprecateCapability | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, successor_id. |
| AP-ENTRY-040 | retireCapability | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version. |
| AP-ENTRY-041 | beginTokenContractRotation | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. No args; adds an accepted AAT ver. |
| AP-ENTRY-042 | retireTokenContract | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args ver. |
| AP-ENTRY-043 | activateCohort | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, cohort_name, installation_ids. |
| AP-ENTRY-044 | promoteCohort | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, cohort_name. |
| AP-ENTRY-045 | rebuildClinicDo | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args installation_id; runs DO rebuild_clinic_do. |
| AP-ENTRY-046 | rebuildGrantLedger | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. Rebuilds grant_ledger rows from R2 grant-ledger objects. |
| AP-ENTRY-047 | refreshCoverageSnapshot | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args installation_id. |
| AP-ENTRY-048 | recordOperatorAction | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args action, subject, action_id; idempotent by action_id; writes control_audit. |
| AP-ENTRY-049 | supportLookup | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args reference \| subscription_ref \| org_id, limit (1..100), cursor; writes control_audit; reads ai_request/ai_attempt/R2 envelope. |
| AP-ENTRY-050 | feedConsumerHealth | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns last_pull_at, last_cursor of feed_consumer 'backend-feed'. |
| AP-ENTRY-051 | dispatchAcceptedGrantCommands | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | Internal/harness or cron-only entry (no operator auth). Called by cron */5; no args; returns count; dispatches grant_claim rows with command_state=accepted, up to 25. |
| AP-ENTRY-052 | dispatchAcceptedTransferPreparations | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | Internal/harness or cron-only entry (no operator auth). Called by cron */5; up to 25. |
| AP-ENTRY-053 | dispatchDeletionCommands | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | Internal/harness or cron-only entry (no operator auth). Called by cron */5; up to 25. |
| AP-ENTRY-054 | shipDueReversalExports | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | | Internal/harness or cron-only entry (no operator auth). Called by cron */5; ships reversal_command export_payload to R2 grant-ledger/{grant_id}.void.ndjson; up to 25. |

## D1 tables, columns, indexes, triggers (database binding DB)

Final schema computed by applying all 40 migration files in file order. Column notes show SQLite type and constraints. Also listed: test-harness-only tables and tables dropped by later migrations.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-D1-001 | ai_attempt | table | migrations | | One provider attempt per ai_request (provider, model, outcome, latency, tokens, cost). |
| AP-D1-002 | ai_attempt.attempt_id | column | migrations; ai_attempt | | TEXT, PK1, NOT NULL |
| AP-D1-003 | ai_attempt.request_id | column | migrations; ai_attempt | | TEXT, NOT NULL |
| AP-D1-004 | ai_attempt.attempt_no | column | migrations; ai_attempt | | INTEGER, NOT NULL |
| AP-D1-005 | ai_attempt.provider | column | migrations; ai_attempt | | TEXT, NOT NULL |
| AP-D1-006 | ai_attempt.model | column | migrations; ai_attempt | | TEXT, NOT NULL |
| AP-D1-007 | ai_attempt.outcome | column | migrations; ai_attempt | | TEXT, NOT NULL |
| AP-D1-008 | ai_attempt.latency_ms | column | migrations; ai_attempt | | INTEGER, NOT NULL |
| AP-D1-009 | ai_attempt.tokens_in | column | migrations; ai_attempt | | INTEGER, NOT NULL |
| AP-D1-010 | ai_attempt.tokens_out | column | migrations; ai_attempt | | INTEGER, NOT NULL |
| AP-D1-011 | ai_attempt.cost | column | migrations; ai_attempt | | REAL, NOT NULL |
| AP-D1-012 | ai_attempt.provider_request_id | column | migrations; ai_attempt | | TEXT |
| AP-D1-013 | ai_attempt.error_code | column | migrations; ai_attempt | | TEXT |
| AP-D1-014 | ai_request | table | migrations | | Request journal row; state, identity, capability, routing, payload pointer (R2), accounting fields. |
| AP-D1-015 | ai_request.request_id | column | migrations; ai_request | | TEXT, PK1, NOT NULL |
| AP-D1-016 | ai_request.request_reference | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-017 | ai_request.installation_id | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-018 | ai_request.actor_id | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-019 | ai_request.branch_id | column | migrations; ai_request | | TEXT |
| AP-D1-020 | ai_request.capability_id | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-021 | ai_request.capability_version | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-022 | ai_request.prompt_artifact_hash | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-023 | ai_request.idempotency_key | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-024 | ai_request.state | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-025 | ai_request.created_at | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-026 | ai_request.updated_at | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-027 | ai_request.completed_at | column | migrations; ai_request | | TEXT |
| AP-D1-028 | ai_request.terminal_error_code | column | migrations; ai_request | | TEXT |
| AP-D1-029 | ai_request.trace_id | column | migrations; ai_request | | TEXT, NOT NULL |
| AP-D1-030 | ai_request.payload_pointer | column | migrations; ai_request | | TEXT |
| AP-D1-031 | ai_request.routing_tier | column | migrations; ai_request | | TEXT |
| AP-D1-032 | ai_request.routing_decision | column | migrations; ai_request | | TEXT |
| AP-D1-033 | ai_request.conversation_id | column | migrations; ai_request | | TEXT |
| AP-D1-034 | ai_request.turn_ordinal | column | migrations; ai_request | | INTEGER |
| AP-D1-035 | ai_request.request_fingerprint | column | migrations; ai_request | | TEXT |
| AP-D1-036 | ai_request.accounting_mode | column | migrations; ai_request | | TEXT |
| AP-D1-037 | ai_request.accounting_term_id | column | migrations; ai_request | | TEXT |
| AP-D1-038 | ai_request.accounting_request_id | column | migrations; ai_request | | TEXT |
| AP-D1-039 | ai_request.accounting_quota_weight | column | migrations; ai_request | | INTEGER |
| AP-D1-040 | ai_request.accounting_outcome | column | migrations; ai_request | | TEXT |
| AP-D1-041 | ai_request.accounting_state | column | migrations; ai_request | | TEXT |
| AP-D1-042 | ai_request.accounting_receipt_acknowledged | column | migrations; ai_request | | INTEGER, NOT NULL, default 0 |
| AP-D1-043 | assertion_used | table | migrations | | Replay guard: WebAuthn operator challenge hashes already consumed. |
| AP-D1-044 | assertion_used.challenge_sha256 | column | migrations; assertion_used | | TEXT, PK1, NOT NULL |
| AP-D1-045 | assertion_used.credential_id | column | migrations; assertion_used | | TEXT, NOT NULL |
| AP-D1-046 | assertion_used.used_at | column | migrations; assertion_used | | TEXT, NOT NULL |
| AP-D1-047 | capability_grant | table | migrations | | Capability grants and global-scope lifecycle overlay (deprecate/retire/cohort). |
| AP-D1-048 | capability_grant.grant_id | column | migrations; capability_grant | | TEXT, PK1, NOT NULL |
| AP-D1-049 | capability_grant.scope | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-050 | capability_grant.capability_id | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-051 | capability_grant.capability_version | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-052 | capability_grant.granted_at | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-053 | capability_grant.revoked_at | column | migrations; capability_grant | | TEXT |
| AP-D1-054 | capability_grant.changed_at | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-055 | capability_grant.changed_by | column | migrations; capability_grant | | TEXT, NOT NULL |
| AP-D1-056 | capability_grant.lifecycle_state | column | migrations; capability_grant | | TEXT |
| AP-D1-057 | capability_grant.successor_id | column | migrations; capability_grant | | TEXT |
| AP-D1-058 | capability_grant.deprecated_at | column | migrations; capability_grant | | TEXT |
| AP-D1-059 | capability_grant.retire_after | column | migrations; capability_grant | | TEXT |
| AP-D1-060 | ceiling_policy | table | migrations | | Versioned ceiling numbers for complimentary/paid grants. |
| AP-D1-061 | ceiling_policy.version | column | migrations; ceiling_policy | | INTEGER, PK1, NOT NULL |
| AP-D1-062 | ceiling_policy.per_grant_max_days | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-063 | ceiling_policy.per_grant_max_allowance_months | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-064 | ceiling_policy.window_days | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-065 | ceiling_policy.window_max_days | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-066 | ceiling_policy.window_max_allowance_months | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-067 | ceiling_policy.max_paid_grace_days | column | migrations; ceiling_policy | | INTEGER, NOT NULL |
| AP-D1-068 | ceiling_policy.paid_cap_rule | column | migrations; ceiling_policy | | TEXT, NOT NULL |
| AP-D1-069 | ceiling_policy.set_by | column | migrations; ceiling_policy | | TEXT, NOT NULL |
| AP-D1-070 | ceiling_policy.assertion_sha256 | column | migrations; ceiling_policy | | TEXT, NOT NULL |
| AP-D1-071 | ceiling_policy_command | table | migrations | | Accepted ceiling-policy commands keyed by challenge hash (immutable). |
| AP-D1-072 | ceiling_policy_command.challenge_sha256 | column | migrations; ceiling_policy_command | | TEXT, PK1, NOT NULL |
| AP-D1-073 | ceiling_policy_command.policy_version | column | migrations; ceiling_policy_command | | INTEGER, NOT NULL |
| AP-D1-074 | ceiling_policy_command.actor | column | migrations; ceiling_policy_command | | TEXT, NOT NULL |
| AP-D1-075 | ceiling_policy_command.operation_json | column | migrations; ceiling_policy_command | | TEXT, NOT NULL |
| AP-D1-076 | ceiling_policy_command.contract_version | column | migrations; ceiling_policy_command | | INTEGER, NOT NULL |
| AP-D1-077 | ceiling_policy_command.result_json | column | migrations; ceiling_policy_command | | TEXT, NOT NULL |
| AP-D1-078 | ceiling_policy_command.created_at | column | migrations; ceiling_policy_command | | TEXT, NOT NULL |
| AP-D1-079 | complimentary_ceiling_claim | table | migrations | | Per-grant reservation against the ceiling policy; status pending\|applied\|sealed_no_effect. |
| AP-D1-080 | complimentary_ceiling_claim.grant_id | column | migrations; complimentary_ceiling_claim | | TEXT, PK1, NOT NULL |
| AP-D1-081 | complimentary_ceiling_claim.org_id | column | migrations; complimentary_ceiling_claim | | TEXT, NOT NULL |
| AP-D1-082 | complimentary_ceiling_claim.envelope_sha256 | column | migrations; complimentary_ceiling_claim | | TEXT, NOT NULL |
| AP-D1-083 | complimentary_ceiling_claim.plan_id | column | migrations; complimentary_ceiling_claim | | TEXT, NOT NULL |
| AP-D1-084 | complimentary_ceiling_claim.plan_version | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL |
| AP-D1-085 | complimentary_ceiling_claim.allowance_denominator | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL |
| AP-D1-086 | complimentary_ceiling_claim.day_contribution | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL |
| AP-D1-087 | complimentary_ceiling_claim.allowance_contribution | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL |
| AP-D1-088 | complimentary_ceiling_claim.apply_per_grant_caps | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL |
| AP-D1-089 | complimentary_ceiling_claim.source_reconciled | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL, default 0 |
| AP-D1-090 | complimentary_ceiling_claim.override_authorized | column | migrations; complimentary_ceiling_claim | | INTEGER, NOT NULL, default 0 |
| AP-D1-091 | complimentary_ceiling_claim.status | column | migrations; complimentary_ceiling_claim | | TEXT, NOT NULL |
| AP-D1-092 | complimentary_ceiling_claim.receipt | column | migrations; complimentary_ceiling_claim | | TEXT |
| AP-D1-093 | complimentary_ceiling_claim.applied_at | column | migrations; complimentary_ceiling_claim | | TEXT |
| AP-D1-094 | complimentary_ceiling_claim.created_at | column | migrations; complimentary_ceiling_claim | | TEXT, NOT NULL |
| AP-D1-095 | complimentary_ceiling_claim_backfill | table | migrations | | Marker that an org's historical claims were reconciled. |
| AP-D1-096 | complimentary_ceiling_claim_backfill.org_id | column | migrations; complimentary_ceiling_claim_backfill | | TEXT, PK1, NOT NULL |
| AP-D1-097 | complimentary_ceiling_claim_backfill.completed_at | column | migrations; complimentary_ceiling_claim_backfill | | TEXT, NOT NULL |
| AP-D1-098 | control_audit | table | migrations | | Operator/control action audit log. |
| AP-D1-099 | control_audit.audit_id | column | migrations; control_audit | | TEXT, PK1, NOT NULL |
| AP-D1-100 | control_audit.operator_id | column | migrations; control_audit | | TEXT, NOT NULL |
| AP-D1-101 | control_audit.action | column | migrations; control_audit | | TEXT, NOT NULL |
| AP-D1-102 | control_audit.target | column | migrations; control_audit | | TEXT, NOT NULL |
| AP-D1-103 | control_audit.before_pointer | column | migrations; control_audit | | TEXT |
| AP-D1-104 | control_audit.after_pointer | column | migrations; control_audit | | TEXT |
| AP-D1-105 | control_audit.recorded_at | column | migrations; control_audit | | TEXT, NOT NULL |
| AP-D1-106 | control_audit.actor | column | migrations; control_audit | | TEXT |
| AP-D1-107 | control_audit.assertion_sha256 | column | migrations; control_audit | | TEXT |
| AP-D1-108 | coverage_event | table | migrations | | Ordered coverage events shipped from the Durable Object; source of GET /v1/feed/coverage (feed_seq autoincrement; no update/delete). |
| AP-D1-109 | coverage_event.feed_seq | column | migrations; coverage_event | | INTEGER, PK1, NOT NULL |
| AP-D1-110 | coverage_event.event_id | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-111 | coverage_event.org_id | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-112 | coverage_event.installation_id | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-113 | coverage_event.binding_epoch | column | migrations; coverage_event | | INTEGER, NOT NULL |
| AP-D1-114 | coverage_event.clinic_seq | column | migrations; coverage_event | | INTEGER, NOT NULL |
| AP-D1-115 | coverage_event.kind | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-116 | coverage_event.snapshot | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-117 | coverage_event.at | column | migrations; coverage_event | | TEXT, NOT NULL |
| AP-D1-118 | coverage_mirror | table | migrations | | Per-installation mirror of Durable Object coverage state. |
| AP-D1-119 | coverage_mirror.installation_id | column | migrations; coverage_mirror | | TEXT, PK1, NOT NULL |
| AP-D1-120 | coverage_mirror.org_id | column | migrations; coverage_mirror | | TEXT, NOT NULL |
| AP-D1-121 | coverage_mirror.binding_epoch | column | migrations; coverage_mirror | | INTEGER, NOT NULL |
| AP-D1-122 | coverage_mirror.clinic_seq | column | migrations; coverage_mirror | | INTEGER, NOT NULL |
| AP-D1-123 | coverage_mirror.state | column | migrations; coverage_mirror | | TEXT, NOT NULL |
| AP-D1-124 | coverage_mirror.suspended | column | migrations; coverage_mirror | | INTEGER, NOT NULL |
| AP-D1-125 | coverage_mirror.hard_stop_at | column | migrations; coverage_mirror | | TEXT |
| AP-D1-126 | coverage_mirror.term_snapshot | column | migrations; coverage_mirror | | TEXT, NOT NULL |
| AP-D1-127 | deletion_command | table | migrations | | Accepted installation-deletion commands and their phases (accepted\|frozen\|completed). |
| AP-D1-128 | deletion_command.assertion_sha256 | column | migrations; deletion_command | | TEXT, PK1, NOT NULL |
| AP-D1-129 | deletion_command.freeze_id | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-130 | deletion_command.org_id | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-131 | deletion_command.installation_id | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-132 | deletion_command.binding_epoch | column | migrations; deletion_command | | INTEGER, NOT NULL |
| AP-D1-133 | deletion_command.reason | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-134 | deletion_command.accepted_actor | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-135 | deletion_command.signer_credential_id | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-136 | deletion_command.accepted_command | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-137 | deletion_command.phase | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-138 | deletion_command.freeze_inventory | column | migrations; deletion_command | | TEXT |
| AP-D1-139 | deletion_command.freeze_ack_at | column | migrations; deletion_command | | TEXT |
| AP-D1-140 | deletion_command.retained_term_ids | column | migrations; deletion_command | | TEXT |
| AP-D1-141 | deletion_command.held | column | migrations; deletion_command | | INTEGER |
| AP-D1-142 | deletion_command.alert_due | column | migrations; deletion_command | | INTEGER, NOT NULL, default 0 |
| AP-D1-143 | deletion_command.purge_state | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-144 | deletion_command.completion_detail | column | migrations; deletion_command | | TEXT |
| AP-D1-145 | deletion_command.due_at | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-146 | deletion_command.lease_until | column | migrations; deletion_command | | TEXT |
| AP-D1-147 | deletion_command.created_at | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-148 | deletion_command.updated_at | column | migrations; deletion_command | | TEXT, NOT NULL |
| AP-D1-149 | fallback_admission | table | migrations | | Durable record of admissions made while the Durable Object was unavailable (outage fallback). |
| AP-D1-150 | fallback_admission.installation_id | column | migrations; fallback_admission | | TEXT, PK1, NOT NULL |
| AP-D1-151 | fallback_admission.idempotency_key | column | migrations; fallback_admission | | TEXT, PK2, NOT NULL |
| AP-D1-152 | fallback_admission.term_id | column | migrations; fallback_admission | | TEXT, NOT NULL |
| AP-D1-153 | fallback_admission.request_id | column | migrations; fallback_admission | | TEXT, NOT NULL |
| AP-D1-154 | fallback_admission.weight | column | migrations; fallback_admission | | INTEGER, NOT NULL |
| AP-D1-155 | fallback_admission.admitted_at | column | migrations; fallback_admission | | TEXT, NOT NULL |
| AP-D1-156 | fallback_admission.state | column | migrations; fallback_admission | | TEXT, NOT NULL |
| AP-D1-157 | fallback_admission.jti | column | migrations; fallback_admission | | TEXT |
| AP-D1-158 | fallback_admission.actor_id | column | migrations; fallback_admission | | TEXT |
| AP-D1-159 | fallback_admission.branch_id | column | migrations; fallback_admission | | TEXT |
| AP-D1-160 | fallback_admission.capability_id | column | migrations; fallback_admission | | TEXT |
| AP-D1-161 | fallback_admission.request_fingerprint | column | migrations; fallback_admission | | TEXT |
| AP-D1-162 | fallback_admission.plan_snapshot | column | migrations; fallback_admission | | TEXT |
| AP-D1-163 | feed_consumer | table | migrations | | Last pull time and cursor of the coverage feed consumer (consumer 'backend-feed'). |
| AP-D1-164 | feed_consumer.consumer | column | migrations; feed_consumer | | TEXT, PK1, NOT NULL |
| AP-D1-165 | feed_consumer.last_pull_at | column | migrations; feed_consumer | | TEXT |
| AP-D1-166 | feed_consumer.last_cursor | column | migrations; feed_consumer | | INTEGER |
| AP-D1-167 | grant_claim | table | migrations | | Global grant identity, route, accepted command and lease state (state pending\|completed\|disputed; command_state none\|accepted\|completed\|rejected). |
| AP-D1-168 | grant_claim.grant_id | column | migrations; grant_claim | | TEXT, PK1, NOT NULL |
| AP-D1-169 | grant_claim.org_id | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-170 | grant_claim.source_kind | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-171 | grant_claim.envelope | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-172 | grant_claim.envelope_sha256 | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-173 | grant_claim.installation_id | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-174 | grant_claim.binding_epoch | column | migrations; grant_claim | | INTEGER, NOT NULL |
| AP-D1-175 | grant_claim.route_generation | column | migrations; grant_claim | | INTEGER, NOT NULL |
| AP-D1-176 | grant_claim.state | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-177 | grant_claim.receipt | column | migrations; grant_claim | | TEXT |
| AP-D1-178 | grant_claim.created_at | column | migrations; grant_claim | | TEXT, NOT NULL |
| AP-D1-179 | grant_claim.completed_at | column | migrations; grant_claim | | TEXT |
| AP-D1-180 | grant_claim.accepted_command | column | migrations; grant_claim | | TEXT |
| AP-D1-181 | grant_claim.accepted_actor | column | migrations; grant_claim | | TEXT |
| AP-D1-182 | grant_claim.signer_credential_id | column | migrations; grant_claim | | TEXT |
| AP-D1-183 | grant_claim.assertion_sha256 | column | migrations; grant_claim | | TEXT |
| AP-D1-184 | grant_claim.override_assertion_sha256 | column | migrations; grant_claim | | TEXT |
| AP-D1-185 | grant_claim.accepted_contract_version | column | migrations; grant_claim | | INTEGER |
| AP-D1-186 | grant_claim.accepted_ceiling_policy_version | column | migrations; grant_claim | | INTEGER |
| AP-D1-187 | grant_claim.plan_snapshot | column | migrations; grant_claim | | TEXT |
| AP-D1-188 | grant_claim.accepted_at | column | migrations; grant_claim | | TEXT |
| AP-D1-189 | grant_claim.due_at | column | migrations; grant_claim | | TEXT |
| AP-D1-190 | grant_claim.lease_token | column | migrations; grant_claim | | TEXT |
| AP-D1-191 | grant_claim.lease_until | column | migrations; grant_claim | | TEXT |
| AP-D1-192 | grant_claim.dispatch_attempts | column | migrations; grant_claim | | INTEGER, NOT NULL, default 0 |
| AP-D1-193 | grant_claim.command_state | column | migrations; grant_claim | | TEXT, NOT NULL, default 'none' |
| AP-D1-194 | grant_claim.terminal_code | column | migrations; grant_claim | | TEXT |
| AP-D1-195 | grant_claim.terminal_detail | column | migrations; grant_claim | | TEXT |
| AP-D1-196 | grant_claim_backfill | table | migrations | | Marker that an org's grant claims were reconciled. |
| AP-D1-197 | grant_claim_backfill.org_id | column | migrations; grant_claim_backfill | | TEXT, PK1, NOT NULL |
| AP-D1-198 | grant_claim_backfill.completed_at | column | migrations; grant_claim_backfill | | TEXT, NOT NULL |
| AP-D1-199 | grant_claim_dispute | table | migrations | | Counter of disputed claims per grant. |
| AP-D1-200 | grant_claim_dispute.grant_id | column | migrations; grant_claim_dispute | | TEXT, PK1, NOT NULL |
| AP-D1-201 | grant_claim_dispute.org_id | column | migrations; grant_claim_dispute | | TEXT, NOT NULL |
| AP-D1-202 | grant_claim_dispute.reason | column | migrations; grant_claim_dispute | | TEXT, NOT NULL |
| AP-D1-203 | grant_claim_dispute.first_at | column | migrations; grant_claim_dispute | | TEXT, NOT NULL |
| AP-D1-204 | grant_claim_dispute.last_at | column | migrations; grant_claim_dispute | | TEXT, NOT NULL |
| AP-D1-205 | grant_claim_dispute.count | column | migrations; grant_claim_dispute | | INTEGER, NOT NULL |
| AP-D1-206 | grant_ledger | table | migrations | | Applied-grant ledger shipped from the Durable Object (no update/delete). |
| AP-D1-207 | grant_ledger.grant_id | column | migrations; grant_ledger | | TEXT, PK1, NOT NULL |
| AP-D1-208 | grant_ledger.origin_grant_id | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-209 | grant_ledger.org_id | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-210 | grant_ledger.installation_id | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-211 | grant_ledger.kind | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-212 | grant_ledger.source_kind | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-213 | grant_ledger.operator_credential_id | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-214 | grant_ledger.envelope_sha256 | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-215 | grant_ledger.receipt | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-216 | grant_ledger.applied_at | column | migrations; grant_ledger | | TEXT, NOT NULL |
| AP-D1-217 | grant_ledger.operator_email | column | migrations; grant_ledger | | TEXT |
| AP-D1-218 | grant_tombstone | table | migrations | | Tombstone and export payload for a reversed grant (no update/delete). |
| AP-D1-219 | grant_tombstone.grant_id | column | migrations; grant_tombstone | | TEXT, PK1, NOT NULL |
| AP-D1-220 | grant_tombstone.reversal_id | column | migrations; grant_tombstone | | TEXT, NOT NULL |
| AP-D1-221 | grant_tombstone.request_sha256 | column | migrations; grant_tombstone | | TEXT, NOT NULL |
| AP-D1-222 | grant_tombstone.receipt | column | migrations; grant_tombstone | | TEXT, NOT NULL |
| AP-D1-223 | grant_tombstone.export_payload | column | migrations; grant_tombstone | | TEXT, NOT NULL |
| AP-D1-224 | grant_tombstone.created_at | column | migrations; grant_tombstone | | TEXT, NOT NULL |
| AP-D1-225 | grant_void | table | migrations | | Void records for grants (no update/delete). |
| AP-D1-226 | grant_void.grant_id | column | migrations; grant_void | | TEXT, PK1, NOT NULL |
| AP-D1-227 | grant_void.reason | column | migrations; grant_void | | TEXT, NOT NULL |
| AP-D1-228 | grant_void.source | column | migrations; grant_void | | TEXT, NOT NULL |
| AP-D1-229 | grant_void.evidence_sha256 | column | migrations; grant_void | | TEXT, NOT NULL |
| AP-D1-230 | grant_void.at | column | migrations; grant_void | | TEXT, NOT NULL |
| AP-D1-231 | installation | table | migrations | | Enrolled installation (created lazily on first valid AI token for an org, or by control plane). |
| AP-D1-232 | installation.installation_id | column | migrations; installation | | TEXT, PK1, NOT NULL |
| AP-D1-233 | installation.org_id | column | migrations; installation | | TEXT, NOT NULL |
| AP-D1-234 | installation.display_name | column | migrations; installation | | TEXT, NOT NULL |
| AP-D1-235 | installation.status | column | migrations; installation | | TEXT, NOT NULL |
| AP-D1-236 | installation.region | column | migrations; installation | | TEXT, NOT NULL |
| AP-D1-237 | installation.enrolled_at | column | migrations; installation | | TEXT, NOT NULL |
| AP-D1-238 | issuer_key | table | migrations | | Public keys (kid) used to verify AI tokens and feed JWTs; status active\|retiring\|revoked. |
| AP-D1-239 | issuer_key.kid | column | migrations; issuer_key | | TEXT, PK1, NOT NULL |
| AP-D1-240 | issuer_key.issuer | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-241 | issuer_key.public_key | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-242 | issuer_key.status | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-243 | issuer_key.not_before | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-244 | issuer_key.not_after | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-245 | issuer_key.registered_by | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-246 | issuer_key.assertion_sha256 | column | migrations; issuer_key | | TEXT, NOT NULL |
| AP-D1-247 | kill_switch | table | migrations | | Kill switch rows keyed by scope (global\|capability\|installation\|provider) and target. |
| AP-D1-248 | kill_switch.scope | column | migrations; kill_switch | | TEXT, PK1, NOT NULL |
| AP-D1-249 | kill_switch.target | column | migrations; kill_switch | | TEXT, PK2, NOT NULL |
| AP-D1-250 | kill_switch.active | column | migrations; kill_switch | | INTEGER, NOT NULL |
| AP-D1-251 | kill_switch.changed_at | column | migrations; kill_switch | | TEXT, NOT NULL |
| AP-D1-252 | kill_switch.changed_by | column | migrations; kill_switch | | TEXT, NOT NULL |
| AP-D1-253 | live_value_route | table | migrations | | Current route state of a grant's value: stable\|moving\|voiding\|retired. |
| AP-D1-254 | live_value_route.grant_id | column | migrations; live_value_route | | TEXT, PK1, NOT NULL |
| AP-D1-255 | live_value_route.org_id | column | migrations; live_value_route | | TEXT, NOT NULL |
| AP-D1-256 | live_value_route.installation_id | column | migrations; live_value_route | | TEXT, NOT NULL |
| AP-D1-257 | live_value_route.binding_epoch | column | migrations; live_value_route | | INTEGER, NOT NULL |
| AP-D1-258 | live_value_route.generation | column | migrations; live_value_route | | INTEGER, NOT NULL |
| AP-D1-259 | live_value_route.state | column | migrations; live_value_route | | TEXT, NOT NULL |
| AP-D1-260 | live_value_route.transfer_id | column | migrations; live_value_route | | TEXT |
| AP-D1-261 | live_value_route.reversal_id | column | migrations; live_value_route | | TEXT |
| AP-D1-262 | live_value_route.updated_at | column | migrations; live_value_route | | TEXT, NOT NULL |
| AP-D1-263 | operator_credential | table | migrations | | Operator WebAuthn credentials (public_key_cose, status, activation). |
| AP-D1-264 | operator_credential.credential_id | column | migrations; operator_credential | | TEXT, PK1, NOT NULL |
| AP-D1-265 | operator_credential.operator_email | column | migrations; operator_credential | | TEXT, NOT NULL |
| AP-D1-266 | operator_credential.public_key_cose | column | migrations; operator_credential | | TEXT, NOT NULL |
| AP-D1-267 | operator_credential.alg | column | migrations; operator_credential | | TEXT, NOT NULL |
| AP-D1-268 | operator_credential.status | column | migrations; operator_credential | | TEXT, NOT NULL |
| AP-D1-269 | operator_credential.activates_at | column | migrations; operator_credential | | TEXT, NOT NULL |
| AP-D1-270 | operator_credential.approved_by | column | migrations; operator_credential | | TEXT |
| AP-D1-271 | operator_credential.revoked_by | column | migrations; operator_credential | | TEXT |
| AP-D1-272 | plan_version | table | migrations | | Published plan versions (capabilities, limits, status). |
| AP-D1-273 | plan_version.plan_id | column | migrations; plan_version | | TEXT, PK1, NOT NULL |
| AP-D1-274 | plan_version.version | column | migrations; plan_version | | INTEGER, PK2, NOT NULL |
| AP-D1-275 | plan_version.display_name | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-276 | plan_version.capabilities | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-277 | plan_version.max_cost_class | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-278 | plan_version.concurrency_limit | column | migrations; plan_version | | INTEGER, NOT NULL |
| AP-D1-279 | plan_version.max_allowance_per_month | column | migrations; plan_version | | INTEGER, NOT NULL |
| AP-D1-280 | plan_version.status | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-281 | plan_version.published_by | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-282 | plan_version.assertion_sha256 | column | migrations; plan_version | | TEXT, NOT NULL |
| AP-D1-283 | platform_alert | table | migrations | | Durable platform alerts with leased email delivery and backoff state. |
| AP-D1-284 | platform_alert.alert_key | column | migrations; platform_alert | | TEXT, PK1, NOT NULL |
| AP-D1-285 | platform_alert.code | column | migrations; platform_alert | | TEXT, NOT NULL |
| AP-D1-286 | platform_alert.severity | column | migrations; platform_alert | | TEXT, NOT NULL |
| AP-D1-287 | platform_alert.first_at | column | migrations; platform_alert | | TEXT, NOT NULL |
| AP-D1-288 | platform_alert.last_at | column | migrations; platform_alert | | TEXT, NOT NULL |
| AP-D1-289 | platform_alert.count | column | migrations; platform_alert | | INTEGER, NOT NULL |
| AP-D1-290 | platform_alert.send_state | column | migrations; platform_alert | | TEXT, NOT NULL |
| AP-D1-291 | platform_alert.next_send_at | column | migrations; platform_alert | | TEXT |
| AP-D1-292 | platform_alert.resolved_at | column | migrations; platform_alert | | TEXT |
| AP-D1-293 | platform_alert.body_json | column | migrations; platform_alert | | TEXT |
| AP-D1-294 | platform_alert.body_state | column | migrations; platform_alert | | TEXT, NOT NULL, default 'incomplete' |
| AP-D1-295 | platform_alert.channel_version | column | migrations; platform_alert | | INTEGER |
| AP-D1-296 | platform_alert.origin_event_id | column | migrations; platform_alert | | TEXT |
| AP-D1-297 | platform_alert.attempts | column | migrations; platform_alert | | INTEGER, NOT NULL, default 0 |
| AP-D1-298 | platform_alert.lease_token | column | migrations; platform_alert | | TEXT |
| AP-D1-299 | platform_alert.lease_expires_at | column | migrations; platform_alert | | TEXT |
| AP-D1-300 | platform_counter | table | migrations | | Guard rejection counters per time bucket and dimension set. |
| AP-D1-301 | platform_counter.counter_id | column | migrations; platform_counter | | TEXT, PK1, NOT NULL |
| AP-D1-302 | platform_counter.dimension_set | column | migrations; platform_counter | | TEXT, NOT NULL |
| AP-D1-303 | platform_counter.time_bucket | column | migrations; platform_counter | | TEXT, NOT NULL |
| AP-D1-304 | platform_counter.count | column | migrations; platform_counter | | INTEGER, NOT NULL |
| AP-D1-305 | reversal_command | table | migrations | | Idempotent reversal commands, receipt and R2 export state (state due\|terminal). |
| AP-D1-306 | reversal_command.reversal_id | column | migrations; reversal_command | | TEXT, PK1, NOT NULL |
| AP-D1-307 | reversal_command.grant_id | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-308 | reversal_command.request_sha256 | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-309 | reversal_command.request_body | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-310 | reversal_command.route_installation_id | column | migrations; reversal_command | | TEXT |
| AP-D1-311 | reversal_command.route_epoch | column | migrations; reversal_command | | INTEGER |
| AP-D1-312 | reversal_command.route_generation | column | migrations; reversal_command | | INTEGER |
| AP-D1-313 | reversal_command.state | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-314 | reversal_command.receipt | column | migrations; reversal_command | | TEXT |
| AP-D1-315 | reversal_command.export_payload | column | migrations; reversal_command | | TEXT |
| AP-D1-316 | reversal_command.export_state | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-317 | reversal_command.created_at | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-318 | reversal_command.updated_at | column | migrations; reversal_command | | TEXT, NOT NULL |
| AP-D1-319 | routing_policy | table | migrations | | Routing policy versions; content in R2; status published\|canary\|active\|superseded |
| AP-D1-320 | routing_policy.policy_id | column | migrations; routing_policy | | TEXT, PK1, NOT NULL |
| AP-D1-321 | routing_policy.version | column | migrations; routing_policy | | TEXT, PK2, NOT NULL |
| AP-D1-322 | routing_policy.content_pointer | column | migrations; routing_policy | | TEXT, NOT NULL |
| AP-D1-323 | routing_policy.active_from | column | migrations; routing_policy | | TEXT, NOT NULL |
| AP-D1-324 | routing_policy.activated_by | column | migrations; routing_policy | | TEXT, NOT NULL |
| AP-D1-325 | routing_policy.canary_installation_ids | column | migrations; routing_policy | | TEXT |
| AP-D1-326 | routing_policy.status | column | migrations; routing_policy | | TEXT, NOT NULL, default 'published' |
| AP-D1-327 | routing_policy.content_sha256 | column | migrations; routing_policy | | TEXT |
| AP-D1-328 | routing_policy_activation | table | migrations | | Activation generation and predecessor per policy_id. |
| AP-D1-329 | routing_policy_activation.policy_id | column | migrations; routing_policy_activation | | TEXT, PK1 |
| AP-D1-330 | routing_policy_activation.generation | column | migrations; routing_policy_activation | | INTEGER, NOT NULL, default 0 |
| AP-D1-331 | routing_policy_activation.active_version | column | migrations; routing_policy_activation | | TEXT |
| AP-D1-332 | routing_policy_activation.predecessor_version | column | migrations; routing_policy_activation | | TEXT |
| AP-D1-333 | routing_policy_activation.predecessor_state | column | migrations; routing_policy_activation | | TEXT, NOT NULL, default 'unknown' |
| AP-D1-334 | service_key | table | migrations | | Public keys for service callers (e.g. the ABO); status and validity window. |
| AP-D1-335 | service_key.kid | column | migrations; service_key | | TEXT, PK1, NOT NULL |
| AP-D1-336 | service_key.service | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-337 | service_key.public_key | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-338 | service_key.status | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-339 | service_key.not_before | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-340 | service_key.not_after | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-341 | service_key.registered_by | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-342 | service_key.assertion_sha256 | column | migrations; service_key | | TEXT, NOT NULL |
| AP-D1-343 | sqlite_sequence | table | migrations | | SQLite internal AUTOINCREMENT bookkeeping (not application schema). |
| AP-D1-344 | sqlite_sequence.name | column | migrations; sqlite_sequence | | untyped |
| AP-D1-345 | sqlite_sequence.seq | column | migrations; sqlite_sequence | | untyped |
| AP-D1-346 | stranded_term_recovery | table | migrations | | D1 copy of stranded-term recovery actions (also mirrored in the Durable Object). |
| AP-D1-347 | stranded_term_recovery.action_id | column | migrations; stranded_term_recovery | | TEXT, PK1, NOT NULL |
| AP-D1-348 | stranded_term_recovery.org_id | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-349 | stranded_term_recovery.installation_id | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-350 | stranded_term_recovery.binding_epoch | column | migrations; stranded_term_recovery | | INTEGER, NOT NULL |
| AP-D1-351 | stranded_term_recovery.target_term_id | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-352 | stranded_term_recovery.source_grant_id | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-353 | stranded_term_recovery.expected_clinic_seq | column | migrations; stranded_term_recovery | | INTEGER, NOT NULL |
| AP-D1-354 | stranded_term_recovery.reason | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-355 | stranded_term_recovery.request_sha256 | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-356 | stranded_term_recovery.evidence_sha256 | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-357 | stranded_term_recovery.actor_email | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-358 | stranded_term_recovery.credential_id | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-359 | stranded_term_recovery.assertion_sha256 | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-360 | stranded_term_recovery.recovered_at | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-361 | stranded_term_recovery.result_json | column | migrations; stranded_term_recovery | | TEXT, NOT NULL |
| AP-D1-362 | tenant_binding | table | migrations | | Org to installation binding by epoch; status active\|held_for_transfer\|retired; first-tenant (epoch 1) creation capped by trigger. |
| AP-D1-363 | tenant_binding.org_id | column | migrations; tenant_binding | | TEXT, PK1, NOT NULL |
| AP-D1-364 | tenant_binding.installation_id | column | migrations; tenant_binding | | TEXT, NOT NULL |
| AP-D1-365 | tenant_binding.epoch | column | migrations; tenant_binding | | INTEGER, PK2, NOT NULL |
| AP-D1-366 | tenant_binding.status | column | migrations; tenant_binding | | TEXT, NOT NULL |
| AP-D1-367 | tenant_binding.retired_at | column | migrations; tenant_binding | | TEXT |
| AP-D1-368 | tenant_binding.reason | column | migrations; tenant_binding | | TEXT |
| AP-D1-369 | tenant_binding.created_at | column | migrations; tenant_binding | | TEXT, NOT NULL |
| AP-D1-370 | token_contract | table | migrations | | Accepted AAT 'ver' values; retired_at marks retired. |
| AP-D1-371 | token_contract.ver | column | migrations; token_contract | | TEXT, PK1, NOT NULL |
| AP-D1-372 | token_contract.added_at | column | migrations; token_contract | | TEXT, NOT NULL |
| AP-D1-373 | token_contract.retired_at | column | migrations; token_contract | | TEXT |
| AP-D1-374 | token_contract.changed_by | column | migrations; token_contract | | TEXT, NOT NULL |
| AP-D1-375 | transfer | table | migrations | | Installation transfer record with package. |
| AP-D1-376 | transfer.transfer_id | column | migrations; transfer | | TEXT, PK1, NOT NULL |
| AP-D1-377 | transfer.org_id | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-378 | transfer.from_installation_id | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-379 | transfer.to_installation_id | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-380 | transfer.reason | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-381 | transfer.assertion_sha256 | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-382 | transfer.package | column | migrations; transfer | | TEXT |
| AP-D1-383 | transfer.created_at | column | migrations; transfer | | TEXT, NOT NULL |
| AP-D1-384 | transfer_preparation | table | migrations | | Transfer preparation phases accepted\|destination_ready\|source_frozen\|published\|completed. |
| AP-D1-385 | transfer_preparation.transfer_id | column | migrations; transfer_preparation | | TEXT, PK1, NOT NULL |
| AP-D1-386 | transfer_preparation.org_id | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-387 | transfer_preparation.from_installation_id | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-388 | transfer_preparation.source_epoch | column | migrations; transfer_preparation | | INTEGER, NOT NULL |
| AP-D1-389 | transfer_preparation.to_installation_id | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-390 | transfer_preparation.destination_epoch | column | migrations; transfer_preparation | | INTEGER, NOT NULL |
| AP-D1-391 | transfer_preparation.reason | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-392 | transfer_preparation.assertion_sha256 | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-393 | transfer_preparation.accepted_actor | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-394 | transfer_preparation.accepted_signer_credential_id | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-395 | transfer_preparation.accepted_command | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-396 | transfer_preparation.phase | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-397 | transfer_preparation.due_at | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-398 | transfer_preparation.lease_token | column | migrations; transfer_preparation | | TEXT |
| AP-D1-399 | transfer_preparation.lease_until | column | migrations; transfer_preparation | | TEXT |
| AP-D1-400 | transfer_preparation.created_at | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-401 | transfer_preparation.updated_at | column | migrations; transfer_preparation | | TEXT, NOT NULL |
| AP-D1-402 | transfer_route_manifest | table | migrations | | Pinned source epoch/generation per grant in a transfer export. |
| AP-D1-403 | transfer_route_manifest.transfer_id | column | migrations; transfer_route_manifest | | TEXT, PK1, NOT NULL |
| AP-D1-404 | transfer_route_manifest.grant_id | column | migrations; transfer_route_manifest | | TEXT, PK2, NOT NULL |
| AP-D1-405 | transfer_route_manifest.source_epoch | column | migrations; transfer_route_manifest | | INTEGER, NOT NULL |
| AP-D1-406 | transfer_route_manifest.source_generation | column | migrations; transfer_route_manifest | | INTEGER, NOT NULL |
| AP-D1-407 | transfer_route_quarantine | table | migrations | | Quarantined transfer routes with bounded reason. |
| AP-D1-408 | transfer_route_quarantine.transfer_id | column | migrations; transfer_route_quarantine | | TEXT, PK1, NOT NULL |
| AP-D1-409 | transfer_route_quarantine.grant_id | column | migrations; transfer_route_quarantine | | TEXT, PK2, NOT NULL, default '' |
| AP-D1-410 | transfer_route_quarantine.reason | column | migrations; transfer_route_quarantine | | TEXT, NOT NULL |
| AP-D1-411 | transfer_route_quarantine.created_at | column | migrations; transfer_route_quarantine | | TEXT, NOT NULL |
| AP-D1-412 | transfer_step | table | migrations | | Transfer step receipts keyed by (transfer_id, step). |
| AP-D1-413 | transfer_step.transfer_id | column | migrations; transfer_step | | TEXT, PK1, NOT NULL |
| AP-D1-414 | transfer_step.step | column | migrations; transfer_step | | TEXT, PK2, NOT NULL |
| AP-D1-415 | transfer_step.receipt | column | migrations; transfer_step | | TEXT, NOT NULL |
| AP-D1-416 | transfer_step.applied_at | column | migrations; transfer_step | | TEXT, NOT NULL |
| AP-D1-417 | usage_event | table | migrations | | Usage ledger events per term (quota_weight, tokens, cost, accounting_seq). |
| AP-D1-418 | usage_event.usage_event_id | column | migrations; usage_event | | TEXT, PK1, NOT NULL |
| AP-D1-419 | usage_event.installation_id | column | migrations; usage_event | | TEXT, NOT NULL |
| AP-D1-420 | usage_event.term_id | column | migrations; usage_event | | TEXT, NOT NULL |
| AP-D1-421 | usage_event.request_id | column | migrations; usage_event | | TEXT |
| AP-D1-422 | usage_event.quota_weight | column | migrations; usage_event | | INTEGER, NOT NULL |
| AP-D1-423 | usage_event.tokens | column | migrations; usage_event | | INTEGER, NOT NULL |
| AP-D1-424 | usage_event.cost | column | migrations; usage_event | | REAL, NOT NULL |
| AP-D1-425 | usage_event.recorded_at | column | migrations; usage_event | | TEXT, NOT NULL |
| AP-D1-426 | usage_event.origin_request_id | column | migrations; usage_event | | TEXT |
| AP-D1-427 | usage_event.accounting_seq | column | migrations; usage_event | | INTEGER |
| AP-D1-428 | usage_rollup | table | migrations | | Usage rollup rows keyed by dimensions JSON (period, term, capability...). |
| AP-D1-429 | usage_rollup.rollup_id | column | migrations; usage_rollup | | TEXT, PK1, NOT NULL |
| AP-D1-430 | usage_rollup.dimensions | column | migrations; usage_rollup | | TEXT, NOT NULL |
| AP-D1-431 | usage_rollup.request_count | column | migrations; usage_rollup | | INTEGER, NOT NULL |
| AP-D1-432 | usage_rollup.tokens | column | migrations; usage_rollup | | INTEGER, NOT NULL |
| AP-D1-433 | usage_rollup.cost | column | migrations; usage_rollup | | REAL, NOT NULL |
| AP-D1-434 | usage_rollup.quota_weight | column | migrations; usage_rollup | | INTEGER, NOT NULL, default 0 |
| AP-D1-435 | usage_term_retention | table | migrations | | Per-term state checkpoint used to decide usage_event retention. |
| AP-D1-436 | usage_term_retention.installation_id | column | migrations; usage_term_retention | | TEXT, PK1, NOT NULL |
| AP-D1-437 | usage_term_retention.term_id | column | migrations; usage_term_retention | | TEXT, PK2, NOT NULL |
| AP-D1-438 | usage_term_retention.term_state | column | migrations; usage_term_retention | | TEXT, NOT NULL |
| AP-D1-439 | usage_term_retention.ended_at | column | migrations; usage_term_retention | | TEXT |
| AP-D1-440 | usage_term_retention.clinic_seq | column | migrations; usage_term_retention | | INTEGER, NOT NULL |
| AP-D1-441 | usage_term_retention.snapshot_sha256 | column | migrations; usage_term_retention | | TEXT, NOT NULL |
| AP-D1-442 | idx_ai_attempt_request_id | index | migrations; ai_attempt | | Index on ai_attempt |
| AP-D1-443 | ai_request_pending_accounting | index | migrations; ai_request | | Index on ai_request |
| AP-D1-444 | idx_ai_request_conversation | index | migrations; ai_request | | Index on ai_request |
| AP-D1-445 | idx_ai_request_created_at | index | migrations; ai_request | | Index on ai_request |
| AP-D1-446 | idx_ai_request_installation_id | index | migrations; ai_request | | Index on ai_request |
| AP-D1-447 | idx_ai_request_request_reference | index | migrations; ai_request | | Index on ai_request |
| AP-D1-448 | idx_capability_grant_live_installation | index | migrations; capability_grant | | Index on capability_grant |
| AP-D1-449 | idx_capability_grant_live_plan | index | migrations; capability_grant | | Index on capability_grant |
| AP-D1-450 | complimentary_ceiling_claim_org_status_time | index | migrations; complimentary_ceiling_claim | | Index on complimentary_ceiling_claim |
| AP-D1-451 | deletion_command_due | index | migrations; deletion_command | | Index on deletion_command |
| AP-D1-452 | deletion_command_open_org | index | migrations; deletion_command | | Index on deletion_command |
| AP-D1-453 | fallback_admission_installation_jti | index | migrations; fallback_admission | | Index on fallback_admission |
| AP-D1-454 | fallback_admission_installation_state | index | migrations; fallback_admission | | Index on fallback_admission |
| AP-D1-455 | fallback_admission_request_id | index | migrations; fallback_admission | | Index on fallback_admission |
| AP-D1-456 | fallback_admission_state | index | migrations; fallback_admission | | Index on fallback_admission |
| AP-D1-457 | grant_claim_due_commands | index | migrations; grant_claim | | Index on grant_claim |
| AP-D1-458 | grant_claim_org_route | index | migrations; grant_claim | | Index on grant_claim |
| AP-D1-459 | grant_ledger_operator_applied_at | index | migrations; grant_ledger | | Index on grant_ledger |
| AP-D1-460 | grant_ledger_org_applied_at | index | migrations; grant_ledger | | Index on grant_ledger |
| AP-D1-461 | grant_ledger_origin_grant_id | index | migrations; grant_ledger | | Index on grant_ledger |
| AP-D1-462 | live_value_route_installation | index | migrations; live_value_route | | Index on live_value_route |
| AP-D1-463 | platform_alert_due_idx | index | migrations; platform_alert | | Index on platform_alert |
| AP-D1-464 | idx_platform_counter_installation | index | migrations; platform_counter | | Index on platform_counter |
| AP-D1-465 | tenant_binding_one_live_org | index | migrations; tenant_binding | | Index on tenant_binding |
| AP-D1-466 | transfer_preparation_due | index | migrations; transfer_preparation | | Index on transfer_preparation |
| AP-D1-467 | transfer_preparation_open_source_epoch | index | migrations; transfer_preparation | | Index on transfer_preparation |
| AP-D1-468 | transfer_preparation_reserved_epoch | index | migrations; transfer_preparation | | Index on transfer_preparation |
| AP-D1-469 | idx_usage_event_accounting_seq | index | migrations; usage_event | | Index on usage_event |
| AP-D1-470 | idx_usage_event_installation_id | index | migrations; usage_event | | Index on usage_event |
| AP-D1-471 | idx_usage_event_origin_request | index | migrations; usage_event | | Index on usage_event |
| AP-D1-472 | idx_usage_event_request_id | index | migrations; usage_event | | Index on usage_event |
| AP-D1-473 | idx_usage_rollup_term_id | index | migrations; usage_rollup | | Index on usage_rollup |
| AP-D1-474 | ceiling_policy_command_immutable | trigger | migrations; ceiling_policy_command | | Trigger on ceiling_policy_command |
| AP-D1-475 | ceiling_policy_command_no_delete | trigger | migrations; ceiling_policy_command | | Trigger on ceiling_policy_command |
| AP-D1-476 | complimentary_ceiling_claim_identity_immutable | trigger | migrations; complimentary_ceiling_claim | | Trigger on complimentary_ceiling_claim |
| AP-D1-477 | complimentary_ceiling_claim_no_delete_guard | trigger | migrations; complimentary_ceiling_claim | | Trigger on complimentary_ceiling_claim |
| AP-D1-478 | complimentary_ceiling_claim_reserve_guard | trigger | migrations; complimentary_ceiling_claim | | Trigger on complimentary_ceiling_claim |
| AP-D1-479 | coverage_event_no_delete | trigger | migrations; coverage_event | | Trigger on coverage_event |
| AP-D1-480 | coverage_event_no_update | trigger | migrations; coverage_event | | Trigger on coverage_event |
| AP-D1-481 | grant_claim_identity_immutable | trigger | migrations; grant_claim | | Trigger on grant_claim |
| AP-D1-482 | grant_claim_no_delete | trigger | migrations; grant_claim | | Trigger on grant_claim |
| AP-D1-483 | grant_ledger_no_delete | trigger | migrations; grant_ledger | | Trigger on grant_ledger |
| AP-D1-484 | grant_ledger_no_update | trigger | migrations; grant_ledger | | Trigger on grant_ledger |
| AP-D1-485 | grant_tombstone_no_delete | trigger | migrations; grant_tombstone | | Trigger on grant_tombstone |
| AP-D1-486 | grant_tombstone_no_update | trigger | migrations; grant_tombstone | | Trigger on grant_tombstone |
| AP-D1-487 | grant_void_no_delete | trigger | migrations; grant_void | | Trigger on grant_void |
| AP-D1-488 | grant_void_no_update | trigger | migrations; grant_void | | Trigger on grant_void |
| AP-D1-489 | live_value_route_identity_immutable | trigger | migrations; live_value_route | | Trigger on live_value_route |
| AP-D1-490 | live_value_route_no_delete | trigger | migrations; live_value_route | | Trigger on live_value_route |
| AP-D1-491 | reversal_command_identity_immutable | trigger | migrations; reversal_command | | Trigger on reversal_command |
| AP-D1-492 | reversal_command_no_delete | trigger | migrations; reversal_command | | Trigger on reversal_command |
| AP-D1-493 | tenant_creation_cap_guard | trigger | migrations; tenant_binding | | Trigger on tenant_binding |
| AP-D1-494 | harness_test_clock | table (not in migrations) | clock | | Read only when TEST_CLOCK=1: column now_iso, row id 'default'; absent in production schema. |
| AP-D1-495 | harness_admission_fault | table (not in migrations) | worker | | Read only when TEST_CLOCK=1: columns id, mode (throw\|hold), hold_until; absent in production schema. |
| AP-D1-496 | grace_admission_queue | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-497 | invoice | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-498 | credit_price | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-499 | plan | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-500 | entitlement | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-501 | installation_key | dropped table | migrations | | Created by an earlier migration and dropped by a later one; not in the final schema. |

## D1 migration files

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-MIG-001 | 20260731120000_platform_schema.sql | D1 migration | migrations | | Platform D1 schema (§7.3): forward-only additive migration for slice A5. |
| AP-MIG-002 | 20260802100000_capability_grant_lifecycle.sql | D1 migration | migrations | | J1: additive lifecycle overlay columns on capability_grant (global-scope overlay rows). |
| AP-MIG-003 | 20260803100000_routing_policy_canary.sql | D1 migration | migrations | | J3: additive canary_installation_ids on routing_policy for cohort-scoped policy activation. |
| AP-MIG-004 | 20260803120000_token_contract.sql | D1 migration | migrations | | J4: platform-global accepted AAT ver set (token_contract). |
| AP-MIG-005 | 20260805120000_f3_retention_indexes.sql | D1 migration | migrations | | F3: detach ledger FK so journal purge can expire ai_request + ai_attempt at 90d |
| AP-MIG-006 | 20260805180000_h3_conversation_index.sql | D1 migration | migrations | | A5 follow-up (H3-R4): index for one ordered conversation query (§7.3). |
| AP-MIG-007 | 20260805190000_routing_policy_status.sql | D1 migration | migrations | | J3 review: explicit routing-policy activation status so publish is non-serving, |
| AP-MIG-008 | 20260807120000_kill_switch.sql | D1 migration | migrations | | I2: durable kill-switch rows (§7.3). |
| AP-MIG-009 | 20260821120000_grace_admission_queue.sql | D1 migration | migrations | | Durable grace-admission queue + cap (audit 1.4). Same D1 as the platform |
| AP-MIG-010 | 20260821130000_entitlement_installation_unique.sql | D1 migration | migrations | | One entitlement row per installation (audit 5.9). |
| AP-MIG-011 | 20260911120000_plan_catalogue.sql | D1 migration | migrations | | CREATE TABLE plan ( |
| AP-MIG-012 | 20260911180000_usage_rollup_quota_weight.sql | D1 migration | migrations | | ALTER TABLE usage_rollup ADD COLUMN quota_weight INTEGER NOT NULL DEFAULT 0; |
| AP-MIG-013 | 20260911200000_invoice.sql | D1 migration | migrations | | CREATE TABLE invoice ( |
| AP-MIG-014 | 20261003120000_operator_credential_and_platform_alert.sql | D1 migration | migrations | | P3.1: operator credentials, assertion replay guard, platform alerts, control_audit extensions. |
| AP-MIG-015 | 20261003130000_issuer_key_tenant_binding.sql | D1 migration | migrations | | CREATE TABLE issuer_key ( |
| AP-MIG-016 | 20261003140000_plan_version_paid_grant_coverage.sql | D1 migration | migrations | | CREATE TABLE service_key ( |
| AP-MIG-017 | 20261006120000_usage_term.sql | D1 migration | migrations | | P3.4: usage_event.term_id replaces period; rollup keyed by term_id. |
| AP-MIG-018 | 20261006130000_ceiling_policy.sql | D1 migration | migrations | | CREATE TABLE ceiling_policy ( |
| AP-MIG-019 | 20261006140000_grant_void.sql | D1 migration | migrations | | CREATE TABLE grant_void ( |
| AP-MIG-020 | 20261006150000_transfer.sql | D1 migration | migrations | | CREATE TABLE transfer ( |
| AP-MIG-021 | 20261006160000_fallback_admission_feed.sql | D1 migration | migrations | | P3.9: mirror fallback admission + coverage feed consumer; drop grace queue. |
| AP-MIG-022 | 20261006170000_drop_invoicing.sql | D1 migration | migrations | | DROP TABLE IF EXISTS invoice; |
| AP-MIG-023 | 20261006170100_drop_plan_entitlement.sql | D1 migration | migrations | | P3.10: drop transitional plan catalogue and entitlement rows. |
| AP-MIG-024 | 20261014120000_ai_request_idempotency_fingerprint.sql | D1 migration | migrations | | Bind durable request idempotency to the validated request shape. |
| AP-MIG-025 | 20261018120000_r1_c3_malformed_issuer_key_cleanup.sql | D1 migration | migrations | | R1-C3: legacy issuer keys whose validity bounds are malformed (unparseable |
| AP-MIG-026 | 20261018120100_r1_c2_tenant_creation_cap_trigger.sql | D1 migration | migrations | | R1-C2: the authoritative first-tenant-creation cap (50 epoch-1 bindings in |
| AP-MIG-027 | 20261019120000_r4_pg1_global_grant_claims.sql | D1 migration | migrations | | R4-PG1: global, immutable grant identity and mutable route metadata. |
| AP-MIG-028 | 20261019130000_r4_pg3_accepted_grant_commands.sql | D1 migration | migrations | | R4-PG3: persist a verified complimentary command with its assertion claims. |
| AP-MIG-029 | 20261019140000_rm18_complimentary_ceiling_claims.sql | D1 migration | migrations | | RM18: durable, org-scoped complimentary ceiling reservations and accepted |
| AP-MIG-030 | 20261019150000_r6_pt1_reversal_routes.sql | D1 migration | migrations | | R6-PT1: durable routing/idempotency control records. |
| AP-MIG-031 | 20261019160000_r6_pt1_transfer_route_manifest.sql | D1 migration | migrations | | R6-PT1: pin the exact source route generation and epoch included in an export. |
| AP-MIG-032 | 20261019170000_r4_d2_stranded_recovery.sql | D1 migration | migrations | | CREATE TABLE IF NOT EXISTS stranded_term_recovery ( |
| AP-MIG-033 | 20261020120000_rm24_fallback_admission_identity.sql | D1 migration | migrations | | RM24: durable fallback JTI and request binding for outage admissions. |
| AP-MIG-034 | 20261020130000_rm25_fallback_settlement.sql | D1 migration | migrations | | RM25: retain the original settlement intent until the DO and D1 usage fact agree. |
| AP-MIG-035 | 20261020140000_r6_rm26_transfer_preparation.sql | D1 migration | migrations | | Upgrade procedure for transfers accepted before this table existed: |
| AP-MIG-036 | 20261020150000_rm27_durable_deletion.sql | D1 migration | migrations | | CREATE TABLE deletion_command ( |
| AP-MIG-037 | 20261021120000_rm30_usage_accounting_identity.sql | D1 migration | migrations | | RM30: keep usage identity across snapshot recovery and journal erasure. |
| AP-MIG-038 | 20261021130000_rm31_alert_delivery.sql | D1 migration | migrations | | RM31 (R9-PAL1): durable alert bodies, leased delivery and bounded retry state. |
| AP-MIG-039 | 20261021140000_rm33_routing_configuration_integrity.sql | D1 migration | migrations | | RM33 (R8-ROUTE1): routing policy content integrity. |
| AP-MIG-040 | 20261021150000_rm33_routing_activation_generation.sql | D1 migration | migrations | | RM33 (R8-ROLLBACK1): routing activation generation and predecessor record. |

## R2 prefixes and object types (bucket binding R2)

Bucket per environment: ai-platform-development, ai-platform-staging, ai-platform-production. Only one R2.list call exists (prefix grant-ledger/ during ledger rebuild).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-R2-001 | request/{request_id}/envelope | R2 object prefix (JSON envelope) | journal; retention; support | | Written by journal (writePostResponseDetail) with context, prompt, attempts raw bodies; ai_request.payload_pointer holds the key; deleted by retention (diagnostic horizon, 90 d journal purge, installation purge); read by support lookup. |
| AP-R2-002 | grant-ledger/{grant_id}.ndjson | R2 object (one NDJSON line) | quota-do/coverage outbox ship; vendor entrypoint | | Grant ledger copy (grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, operator_email, envelope_sha256, applied_at, receipt). Written on outbox ship if absent (head check); read by rebuildGrantLedger / recovery. |
| AP-R2-003 | grant-ledger/{grant_id}.void.ndjson | R2 object (one NDJSON line) | quota-do/coverage; vendor entrypoint reversal export | | Void proof line (grant_id, reason, source, evidence_sha256, at, receipt). Written on grant_void outbox ship and by shipDueReversalExports; read during rebuild_clinic_do recovery. |
| AP-R2-004 | grant-ledger/{grant_id}.recovery-v1.ndjson | R2 object (one NDJSON line) | quota-do/coverage | | Grant recovery capsule (canonical JSON) written when a grant ledger row ships; compared byte-for-byte on rewrite (conflict throws grant_recovery_capsule_conflict); skipped when listing in rebuild. |
| AP-R2-005 | control/routing-policy/{policy_id}/{version}/sha256-{digest}.json | R2 object (application/json) | control/routing-policy | | Immutable routing policy document published by publishRoutingPolicy; routing_policy.content_pointer and content_sha256 point at it; read and digest-verified by the config cache and promote/canary/rollback. |

## Durable Object state (class GatewayObject)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-DO-001 | hot | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Singleton row of per-clinic hot state. |
| AP-DO-002 | hot.suspended | Durable Object SQLite column | quota-do/index.ts | | suspended INTEGER NN default 0 |
| AP-DO-003 | hot.transferred_out_to | Durable Object SQLite column | quota-do/index.ts | | transferred_out_to TEXT |
| AP-DO-004 | hot.awaiting_transfer | Durable Object SQLite column | quota-do/index.ts | | awaiting_transfer INTEGER NN default 0 |
| AP-DO-005 | hot.awaiting_transfer_id | Durable Object SQLite column | quota-do/index.ts | | awaiting_transfer_id TEXT |
| AP-DO-006 | hot.transfer_pending | Durable Object SQLite column | quota-do/index.ts | | transfer_pending INTEGER NN default 0 |
| AP-DO-007 | hot.transfer_pending_id | Durable Object SQLite column | quota-do/index.ts | | transfer_pending_id TEXT |
| AP-DO-008 | hot.active_term_id | Durable Object SQLite column | quota-do/index.ts | | active_term_id TEXT |
| AP-DO-009 | hot.used | Durable Object SQLite column | quota-do/index.ts | | used INTEGER NN default 0 |
| AP-DO-010 | hot.reserved | Durable Object SQLite column | quota-do/index.ts | | reserved INTEGER NN default 0 |
| AP-DO-011 | hot.grace_base_used | Durable Object SQLite column | quota-do/index.ts | | grace_base_used INTEGER NN default 0 |
| AP-DO-012 | hot.reservations | Durable Object SQLite column | quota-do/index.ts | | reservations TEXT NN default '[]' |
| AP-DO-013 | hot.replay | Durable Object SQLite column | quota-do/index.ts | | replay TEXT NN default '{}' |
| AP-DO-014 | hot.idempotency | Durable Object SQLite column | quota-do/index.ts | | idempotency TEXT NN default '{}' |
| AP-DO-015 | hot.band_emitted | Durable Object SQLite column | quota-do/index.ts | | band_emitted TEXT NN default '{}' |
| AP-DO-016 | hot.binding_epoch | Durable Object SQLite column | quota-do/index.ts | | binding_epoch INTEGER NN default 0 |
| AP-DO-017 | hot.clinic_seq | Durable Object SQLite column | quota-do/index.ts | | clinic_seq INTEGER NN default 0 |
| AP-DO-018 | hot.accounting_seq | Durable Object SQLite column | quota-do/index.ts | | accounting_seq INTEGER NN default 0 |
| AP-DO-019 | hot.next_alarm_at | Durable Object SQLite column | quota-do/index.ts | | next_alarm_at TEXT |
| AP-DO-020 | term | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Coverage terms. |
| AP-DO-021 | term.term_id | Durable Object SQLite column | quota-do/index.ts | | term_id TEXT PK |
| AP-DO-022 | term.grant_id | Durable Object SQLite column | quota-do/index.ts | | grant_id TEXT NN |
| AP-DO-023 | term.origin_grant_id | Durable Object SQLite column | quota-do/index.ts | | origin_grant_id TEXT NN |
| AP-DO-024 | term.position | Durable Object SQLite column | quota-do/index.ts | | position INTEGER NN |
| AP-DO-025 | term.state | Durable Object SQLite column | quota-do/index.ts | | state TEXT NN |
| AP-DO-026 | term.end_reason | Durable Object SQLite column | quota-do/index.ts | | end_reason TEXT |
| AP-DO-027 | term.plan_snapshot | Durable Object SQLite column | quota-do/index.ts | | plan_snapshot TEXT |
| AP-DO-028 | term.allowance | Durable Object SQLite column | quota-do/index.ts | | allowance INTEGER |
| AP-DO-029 | term.used_final | Durable Object SQLite column | quota-do/index.ts | | used_final INTEGER |
| AP-DO-030 | term.duration_unit | Durable Object SQLite column | quota-do/index.ts | | duration_unit TEXT |
| AP-DO-031 | term.duration_count | Durable Object SQLite column | quota-do/index.ts | | duration_count INTEGER |
| AP-DO-032 | term.grace_days | Durable Object SQLite column | quota-do/index.ts | | grace_days INTEGER |
| AP-DO-033 | term.grace_cap | Durable Object SQLite column | quota-do/index.ts | | grace_cap TEXT |
| AP-DO-034 | term.calendar_start | Durable Object SQLite column | quota-do/index.ts | | calendar_start TEXT |
| AP-DO-035 | term.starts_at | Durable Object SQLite column | quota-do/index.ts | | starts_at TEXT |
| AP-DO-036 | term.ends_at | Durable Object SQLite column | quota-do/index.ts | | ends_at TEXT |
| AP-DO-037 | term.grace_ends_at | Durable Object SQLite column | quota-do/index.ts | | grace_ends_at TEXT |
| AP-DO-038 | term.ended_at | Durable Object SQLite column | quota-do/index.ts | | ended_at TEXT |
| AP-DO-039 | grant | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Applied grants held in the Durable Object. |
| AP-DO-040 | grant.grant_id | Durable Object SQLite column | quota-do/index.ts | | grant_id TEXT PK |
| AP-DO-041 | grant.kind | Durable Object SQLite column | quota-do/index.ts | | kind TEXT NN |
| AP-DO-042 | grant.source_kind | Durable Object SQLite column | quota-do/index.ts | | source_kind TEXT NN |
| AP-DO-043 | grant.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | | envelope_sha256 TEXT NN |
| AP-DO-044 | grant.envelope | Durable Object SQLite column | quota-do/index.ts | | envelope TEXT NN |
| AP-DO-045 | grant.evidence | Durable Object SQLite column | quota-do/index.ts | | evidence TEXT NN |
| AP-DO-046 | grant.receipt | Durable Object SQLite column | quota-do/index.ts | | receipt TEXT |
| AP-DO-047 | grant.applied_at | Durable Object SQLite column | quota-do/index.ts | | applied_at TEXT NN |
| AP-DO-048 | grant.voided_at | Durable Object SQLite column | quota-do/index.ts | | voided_at TEXT |
| AP-DO-049 | grant.void_reason | Durable Object SQLite column | quota-do/index.ts | | void_reason TEXT |
| AP-DO-050 | outbox | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Pending rows to ship to D1/R2 by alarm. |
| AP-DO-051 | outbox.seq | Durable Object SQLite column | quota-do/index.ts | | seq INTEGER PK AUTOINCREMENT |
| AP-DO-052 | outbox.kind | Durable Object SQLite column | quota-do/index.ts | | kind TEXT NN |
| AP-DO-053 | outbox.payload | Durable Object SQLite column | quota-do/index.ts | | payload TEXT NN |
| AP-DO-054 | grant_route_seal | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Route seal per grant. |
| AP-DO-055 | grant_route_seal.grant_id | Durable Object SQLite column | quota-do/index.ts | | grant_id TEXT PK |
| AP-DO-056 | grant_route_seal.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | | envelope_sha256 TEXT NN |
| AP-DO-057 | grant_route_seal.route_generation | Durable Object SQLite column | quota-do/index.ts | | route_generation INTEGER NN |
| AP-DO-058 | grant_route_seal.sealed_at | Durable Object SQLite column | quota-do/index.ts | | sealed_at TEXT NN |
| AP-DO-059 | transfer_replay | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Replay store per transfer step. |
| AP-DO-060 | transfer_replay.transfer_id | Durable Object SQLite column | quota-do/index.ts | | transfer_id TEXT NN |
| AP-DO-061 | transfer_replay.step | Durable Object SQLite column | quota-do/index.ts | | step TEXT NN CHECK transfer_out\|transfer_in |
| AP-DO-062 | transfer_replay.request_sha256 | Durable Object SQLite column | quota-do/index.ts | | request_sha256 TEXT NN |
| AP-DO-063 | transfer_replay.response_json | Durable Object SQLite column | quota-do/index.ts | | response_json TEXT NN |
| AP-DO-064 | transfer_replay.created_at | Durable Object SQLite column | quota-do/index.ts | | created_at TEXT NN |
| AP-DO-065 | transfer_replay.PK(transfer_id, | Durable Object SQLite column | quota-do/index.ts | | PK(transfer_id, step) |
| AP-DO-066 | grant_ceiling_claim | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Ceiling claim per grant. |
| AP-DO-067 | grant_ceiling_claim.grant_id | Durable Object SQLite column | quota-do/index.ts | | grant_id TEXT PK |
| AP-DO-068 | grant_ceiling_claim.org_id | Durable Object SQLite column | quota-do/index.ts | | org_id TEXT NN |
| AP-DO-069 | grant_ceiling_claim.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | | envelope_sha256 TEXT NN |
| AP-DO-070 | grant_ceiling_claim.plan_id | Durable Object SQLite column | quota-do/index.ts | | plan_id TEXT NN |
| AP-DO-071 | grant_ceiling_claim.plan_version | Durable Object SQLite column | quota-do/index.ts | | plan_version INTEGER NN |
| AP-DO-072 | grant_ceiling_claim.allowance_denominator | Durable Object SQLite column | quota-do/index.ts | | allowance_denominator INTEGER NN |
| AP-DO-073 | grant_ceiling_claim.day_contribution | Durable Object SQLite column | quota-do/index.ts | | day_contribution INTEGER NN |
| AP-DO-074 | grant_ceiling_claim.allowance_contribution | Durable Object SQLite column | quota-do/index.ts | | allowance_contribution INTEGER NN |
| AP-DO-075 | grant_ceiling_no_effect_seal | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | No-effect seal for a ceiling claim. |
| AP-DO-076 | grant_ceiling_no_effect_seal.grant_id | Durable Object SQLite column | quota-do/index.ts | | grant_id TEXT PK |
| AP-DO-077 | grant_ceiling_no_effect_seal.org_id | Durable Object SQLite column | quota-do/index.ts | | org_id TEXT NN |
| AP-DO-078 | grant_ceiling_no_effect_seal.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | | envelope_sha256 TEXT NN |
| AP-DO-079 | grant_ceiling_no_effect_seal.route_generation | Durable Object SQLite column | quota-do/index.ts | | route_generation INTEGER NN |
| AP-DO-080 | grant_ceiling_no_effect_seal.sealed_at | Durable Object SQLite column | quota-do/index.ts | | sealed_at TEXT NN |
| AP-DO-081 | grant_ceiling_no_effect_seal.receipt | Durable Object SQLite column | quota-do/index.ts | | receipt TEXT NN |
| AP-DO-082 | stranded_term_recovery | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Recovery actions applied to stranded terms. |
| AP-DO-083 | stranded_term_recovery.action_id | Durable Object SQLite column | quota-do/index.ts | | action_id TEXT PK |
| AP-DO-084 | stranded_term_recovery.target_term_id | Durable Object SQLite column | quota-do/index.ts | | target_term_id TEXT NN UNIQUE |
| AP-DO-085 | stranded_term_recovery.reason | Durable Object SQLite column | quota-do/index.ts | | reason TEXT NN |
| AP-DO-086 | stranded_term_recovery.request_sha256 | Durable Object SQLite column | quota-do/index.ts | | request_sha256 TEXT NN |
| AP-DO-087 | stranded_term_recovery.result_json | Durable Object SQLite column | quota-do/index.ts | | result_json TEXT NN |
| AP-DO-088 | stranded_term_recovery.recorded_at | Durable Object SQLite column | quota-do/index.ts | | recorded_at TEXT NN |
| AP-DO-089 | usage_settlement_receipt | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Usage settlement receipts per request. |
| AP-DO-090 | usage_settlement_receipt.request_id | Durable Object SQLite column | quota-do/index.ts | | request_id TEXT PK |
| AP-DO-091 | usage_settlement_receipt.installation_id | Durable Object SQLite column | quota-do/index.ts | | installation_id TEXT NN |
| AP-DO-092 | usage_settlement_receipt.term_id | Durable Object SQLite column | quota-do/index.ts | | term_id TEXT NN |
| AP-DO-093 | usage_settlement_receipt.weight | Durable Object SQLite column | quota-do/index.ts | | weight INTEGER NN |
| AP-DO-094 | usage_settlement_receipt.outcome | Durable Object SQLite column | quota-do/index.ts | | outcome TEXT NN CHECK consumed\|released |
| AP-DO-095 | usage_settlement_receipt.charged_weight | Durable Object SQLite column | quota-do/index.ts | | charged_weight INTEGER NN >=0 |
| AP-DO-096 | usage_settlement_receipt.acknowledged | Durable Object SQLite column | quota-do/index.ts | | acknowledged INTEGER NN default 0 (0\|1) |
| AP-DO-097 | usage_settlement_receipt.accounting_seq | Durable Object SQLite column | quota-do/index.ts | | accounting_seq INTEGER |
| AP-DO-098 | usage_settlement_receipt.recorded_at | Durable Object SQLite column | quota-do/index.ts | | recorded_at TEXT NN |
| AP-DO-099 | recovery_state | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | | Singleton recovery marker. |
| AP-DO-100 | recovery_state.singleton | Durable Object SQLite column | quota-do/index.ts | | singleton INTEGER PK CHECK =1 |
| AP-DO-101 | recovery_state.generation | Durable Object SQLite column | quota-do/index.ts | | generation TEXT NN |
| AP-DO-102 | recovery_state.installation_id | Durable Object SQLite column | quota-do/index.ts | | installation_id TEXT NN |
| AP-DO-103 | recovery_state.org_id | Durable Object SQLite column | quota-do/index.ts | | org_id TEXT NN |
| AP-DO-104 | recovery_state.binding_epoch | Durable Object SQLite column | quota-do/index.ts | | binding_epoch INTEGER NN |
| AP-DO-105 | recovery_state.anchor_event_id | Durable Object SQLite column | quota-do/index.ts | | anchor_event_id TEXT NN |
| AP-DO-106 | recovery_state.status | Durable Object SQLite column | quota-do/index.ts | | status TEXT NN CHECK building\|blocked\|complete |
| AP-DO-107 | recovery_state.updated_at | Durable Object SQLite column | quota-do/index.ts | | updated_at TEXT NN |
| AP-DO-108 | GatewayObject | Durable Object class (SQLite-backed) | worker; wrangler.toml | | Binding DO; migration tag v1 new_sqlite_classes GatewayObject; one object per installation id (idFromName). Tables created on every fetch with CREATE TABLE IF NOT EXISTS plus ALTER TABLE ADD COLUMN for hot.awaiting_transfer_id, hot.transfer_pending_id, hot.accounting_seq and usage_settlement_receipt.accounting_seq. |
| AP-DO-109 | state (storage key) | Durable Object KV storage key | quota-do/index.ts | | Legacy key-value record QuotaDoState. |
| AP-DO-110 | state.periodCounters | Durable Object KV state field | quota-do/index.ts QuotaDoState | | requestsUsed, tokensUsed, costUsed, creditsUsed, inFlight |
| AP-DO-111 | state.periodBounds | Durable Object KV state field | quota-do/index.ts QuotaDoState | | optional {period_start, period_end} |
| AP-DO-112 | state.jtiReplay | Durable Object KV state field | quota-do/index.ts QuotaDoState | | map jti to {expiresAt} |
| AP-DO-113 | state.idempotency | Durable Object KV state field | quota-do/index.ts QuotaDoState | | map key to {expiresAt, requestReference, state admitted\|completed\|failed\|cancelled, requestId, terminalErrorCode?, binding?, traceId?} |
| AP-DO-114 | state.creditedRequests | Durable Object KV state field | quota-do/index.ts QuotaDoState | | map requestId to {expiresAt} |
| AP-DO-115 | state.admittedRequests | Durable Object KV state field | quota-do/index.ts QuotaDoState | | map to {requestReference, admittedAt, entitlement snapshot} |
| AP-DO-116 | state.boundInstallationId | Durable Object KV state field | quota-do/index.ts QuotaDoState | | optional string |
| AP-DO-117 | DO alarm | Durable Object alarm | quota-do/coverage.ts | | Single alarm: earliest of active term ends_at, grace term grace_ends_at, or now when outbox is non-empty (scaled/delayed by physicalAlarmAt, min 5 s ahead); handler ships outbox. |

## Durable Object outbox row kinds (outbox.kind)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-OUTBOX-001 | coverage_event | outbox kind | quota-do/coverage | | Shipped to D1 coverage_event (INSERT OR IGNORE) then coverage_mirror updated. |
| AP-OUTBOX-002 | grant_ledger | outbox kind | quota-do/coverage | | Shipped to D1 grant_ledger, R2 grant-ledger/{id}.ndjson and recovery capsule. |
| AP-OUTBOX-003 | grant_void | outbox kind | quota-do/coverage | | Shipped to D1 grant_void and R2 grant-ledger/{id}.void.ndjson. |
| AP-OUTBOX-004 | stranded_term_recovery | outbox kind | quota-do/coverage | | Shipped to D1 stranded_term_recovery (INSERT OR IGNORE). |
| AP-OUTBOX-005 | usage_adjustment | outbox kind | quota-do/coverage | | Shipped to D1 usage_event (id installation:accounting_seq); mismatch throws usage_accounting_identity_conflict. |
| AP-OUTBOX-006 | alert | outbox kind | quota-do/coverage | | Persisted to D1 platform_alert via persistCommittedAlertBody then delivered. |
| AP-OUTBOX-007 | paid_velocity_observation | outbox kind | quota-do/coverage | | Counts paid grants in last hour; if more than 20 globally raises AL-17 (alert_key AL-17:global). |

## Coverage event kinds (coverage_event.kind, feed events)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-EVENT-001 | term_activated | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-002 | grace_started | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-003 | term_ended | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-004 | term_held | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-005 | term_released | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-006 | grant_applied | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-007 | grant_voided | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-008 | transfer | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-009 | suspension_changed | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-010 | snapshot | coverage event kind | quota-do/coverage | | Emitted into outbox as coverage_event; snapshot attached. |

## Platform alert codes (platform_alert.code)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ALERT-001 | AL-10 | alert code | vendor/entrypoint | | Grant claim dispute (alert_key AL-10:grant-claim:{grant_id}). |
| AP-ALERT-002 | AL-11 | alert code | alert; quota-do/coverage | | Grant/transfer related (keys AL-11:{grant_id}, AL-11:transfer:{transfer_id}). |
| AP-ALERT-003 | AL-12 | alert code | alert; quota-do/coverage | | Grant related (key AL-12:{grant_id}). |
| AP-ALERT-004 | AL-13 | alert code | alert; vendor/entrypoint | | Credential/key lifecycle: operator credential bootstrap\|register\|revoke; issuer key register\|retire\|revoke; service key register\|revoke. |
| AP-ALERT-005 | AL-17 | alert code | alert; quota-do/coverage | | Paid-grant velocity (keys AL-17:clinic:{org_id}, AL-17:global); retried by five-minute cron. |
| AP-ALERT-006 | AL-18 | alert code | alert | | Held binding (key AL-18:{installation_id}); sent daily by 03:00 cron. |
| AP-ALERT-007 | AL-19 | alert code | alert; kill-switch; quota-do/coverage | | Kill switch arm/disarm and suspension toggles. |
| AP-ALERT-008 | AL-20 | alert code | alert; identity | | First-tenant creation cap reached (50 epoch-1 bindings per 24 h); key AL-20; retried by five-minute cron. |
| AP-ALERT-009 | do_rebuild_mismatch | alert code | alert | | Durable Object rebuild mismatch (key do-rebuild:{installation_id}[:{reason}]). |
| AP-ALERT-010 | scheduled_job_failed | alert code | alert | | Five-minute cron job failure for job alert_retry or heartbeat (key scheduled_job_failed:{job}). |

## Cron schedules, scheduled jobs and alarms

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-CRON-001 | 0 3 * * * | cron schedule | wrangler.toml; worker.scheduled | | Daily 03:00 UTC: flush rejection counters, then runRetentionPurge, then sendDailyAl18ForHeldBindings. |
| AP-CRON-002 | 0 4 * * * | cron schedule | wrangler.toml; worker.scheduled | | Daily 04:00 UTC: flush rejection counters, then runRollupAndReconciliation (usage_rollup + reconciliation report). |
| AP-CRON-003 | */5 * * * * | cron schedule | wrangler.toml; worker.scheduled | | Every 5 minutes: flush counters, then the jobs listed below in order. |
| AP-CRON-004 | flushRejectionCounters | scheduled job (every cron) | rate-limit | | Writes in-isolate guard rejection tallies to platform_counter (lower bound). |
| AP-CRON-005 | runRetentionPurge | scheduled job (03:00) | retention | | Checkpoints usage_term_retention from latest coverage_event; deletes diagnostic R2 envelopes by capability retention class (baseline 7 d, band 1..90 d); journal ai_request/ai_attempt and R2 envelopes at 90 d; usage_event/usage_rollup/control_audit/capability_grant at 2555 d; platform_counter at 90 d. |
| AP-CRON-006 | sendDailyAl18ForHeldBindings | scheduled job (03:00) | alert | | Raises/sends AL-18 for held bindings. |
| AP-CRON-007 | runRollupAndReconciliation | scheduled job (04:00) | rollup | | Writes usage_rollup; reconciliation of missing attempt rows / missing usage credit over a window; logs report (no alert row). |
| AP-CRON-008 | dispatchAcceptedGrantCommands | scheduled job (5-min) | vendor/entrypoint via VENDOR binding | | Dispatches accepted grant_claim commands (due_at, lease, up to 25). |
| AP-CRON-009 | dispatchAcceptedTransferPreparations | scheduled job (5-min) | coverage/transfer via VENDOR | | Advances transfer_preparation phases (up to 25). |
| AP-CRON-010 | dispatchDeletionCommands | scheduled job (5-min) | coverage/transfer via VENDOR | | Advances deletion_command phases and purge (up to 25). |
| AP-CRON-011 | shipDueReversalExports | scheduled job (5-min) | vendor/entrypoint via VENDOR | | Ships reversal_command exports to R2 (up to 25). |
| AP-CRON-012 | reconcileGraceUsage | scheduled job (5-min) | credit | | Drains pending fallback_admission rows (outage-time admissions) by settling and acknowledging usage with the Durable Object (settleFallback / ackUsageReceipt). |
| AP-CRON-013 | runFiveMinuteCron: alert_retry | scheduled job (5-min) | alert | | retryUnsentPlatformAlerts, retryDueAl20Alerts, retryDueAl17Alerts; on failure writes scheduled_job_failed alert. |
| AP-CRON-014 | runFiveMinuteCron: heartbeat | scheduled job (5-min) | alert | | pingPlatformHeartbeat: GET HEARTBEAT_URL_PLATFORM (or HEARTBEAT_URL fallback); non-OK throws and raises scheduled_job_failed. |
| AP-CRON-015 | Durable Object alarm (coverage boundary and outbox) | Durable Object alarm | quota-do/coverage | | One alarm per installation object; see AP-DO. |
| AP-CRON-016 | Alert delivery lease/backoff | timing constant | alert | | Lease 2 minutes; backoff base 5 min, doubling, cap 60 min. |
| AP-CRON-017 | Rate-limit windows | platform rate limit bindings | wrangler.toml | | RATE_LIMITER_INSTALLATION 600/60 s; RATE_LIMITER_INSTALLATION_ACTOR 120/60 s; RATE_LIMITER_INSTALLATION_CAPABILITY 300/60 s. |
| AP-CRON-018 | Heartbeat cadence of SSE stream | timing constant | worker; stream | | HEARTBEAT_INTERVAL_MS = 15 000 ms. |
| AP-CRON-019 | Config cache TTL | timing constant | config-cache | | CONFIG_CACHE_TTL_MS (30 000 staging/production, 100 development). |

## Manifests, prompt artifacts and bundled control artifacts

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-MANIFEST-001 | manifests/published/clinic.visit_summary@1.0.0.json | published capability manifest | manifests | | capabilityId clinic.visit_summary v1.0.0, lifecycleState active, scope ai.visit_summary, minimumPlanTier standard, roles administrator\|clinician\|nurse, single_shot, prose output, maxChars 8000, en, context requirement visit.chief_complaint@v1 (max 4096), routing ref routing/standard, maxInputTokens 8000, maxOutputTokens 1024, quotaWeight 1, acceptanceMode advisory_display, retentionClass diagnostic_30d, evalSuiteRef evals/visit-summary@v1. Bundled at build into worker. |
| AP-MANIFEST-002 | manifest sections (Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance) | manifest structure | manifest/index.ts | | Sections validated by manifest load(). |
| AP-MANIFEST-003 | manifests/published-registry.json | manifest hash pin registry | manifests | | Maps clinic.visit_summary@1.0.0 to a SHA-256 hash. |
| AP-MANIFEST-004 | prompts/clinic.visit_summary/system.md | prompt artifact | prompts; prompt/registry | | Ref clinic.visit_summary/system@v1. |
| AP-MANIFEST-005 | prompts/clinic.visit_summary/rules-visit-summary.md | prompt artifact | prompts; prompt/registry | | Ref clinic.visit_summary/rules-visit-summary@v1 (business rule fragment). |
| AP-MANIFEST-006 | prompts/clinic.visit_summary/template-visit-summary.md | prompt artifact | prompts; prompt/registry | | Ref clinic.visit_summary/template-visit-summary@v1 (context rendering template with {{visit.chief_complaint@v1}}). |
| AP-MANIFEST-007 | prompts/clinic.visit_summary/registry.json | prompt hash pin registry | prompts | | Maps the three artifact refs to short hashes (8 hex chars each). |
| AP-MANIFEST-008 | context/shapes/published/visit.chief_complaint@v1.json | context shape | context | | Fields visit_id (string, required, uuid), complaint (string, max length 10000), recorded_at (string, optional, iso8601). |
| AP-MANIFEST-009 | control/routing-policy/platform-default/1.json | bundled default routing policy | control | | policy_id standard, version 1, one rule platform-default-fallback; targets deepseek/deepseek-v4-flash then gemini/gemini-3.5-flash, max_attempts 2, timeout 30000 ms each. |
| AP-MANIFEST-010 | control/pricing/platform-default/1.json | bundled pricing table | control; pricing/index.ts | | per_1k_tokens price for deepseek-v4-flash, gemini-3.5-flash, fake-v1 and a default. |
| AP-MANIFEST-011 | Capability registry (installed at boot) | in-memory registry | worker boot; capability/index.ts | | Created from visitSummaryPublished; setCapabilityRegistry at module init. |
| AP-MANIFEST-012 | Config cache entity kinds | cache kinds | config-cache/index.ts | | installations, issuer_keys, tenant_bindings, entitlements, grants, kill_switches, active_routing_policy, token_contracts, plans (read from D1/R2). |
| AP-MANIFEST-013 | PLAN_TIERS | vocabulary | platform-vocabulary.ts | | starter, standard, professional, enterprise. |
| AP-MANIFEST-014 | Routing policy status values | vocabulary | control/routing-policy | | published (after publish), canary, active (after promote), superseded (prior active/canary). |

## Outbound calls (providers, ABO, Supabase, other)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-OUT-001 | DeepSeek chat completions: POST https://api.deepseek.com/chat/completions | outbound HTTPS (provider) | provider/deepseek.ts | | Authorization Bearer DEEPSEEK_API_KEY; default model deepseek-v4-flash; streaming and non-streaming. |
| AP-OUT-002 | Gemini: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent or :streamGenerateContent?alt=sse | outbound HTTPS (provider) | provider/gemini.ts | | Header x-goog-api-key from GEMINI_API_KEY; default model gemini-3.5-flash. |
| AP-OUT-003 | Cloudflare Access certs: GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs | outbound HTTPS | vendor/entrypoint | | Fetched per Access JWT verification unless ACCESS_CERTS_JSON is set. |
| AP-OUT-004 | Heartbeat ping: GET HEARTBEAT_URL_PLATFORM (fallback HEARTBEAT_URL) | outbound HTTPS | alert/index.ts | | Every 5 minutes; non-OK response throws. |
| AP-OUT-005 | SEND_EMAIL.send({from,to,subject,text}) | outbound email binding | alert/email.ts | | from and to both ALERT_EMAIL_TO; subject is alert code; text is alert body JSON. |
| AP-OUT-006 | Durable Object stub fetch: POST https://quota-do.internal/rpc | internal binding call | pipeline; admission; credit; coverage-read; coverage/transfer; vendor/entrypoint; quota-do/coverage | | Callers use env.DO.get(idFromName(installationId)); see AP-DORPC. |
| AP-OUT-007 | VENDOR service binding (self): dispatchAcceptedGrantCommands, dispatchAcceptedTransferPreparations, dispatchDeletionCommands, shipDueReversalExports | internal service binding call | worker.scheduled | | Binding VENDOR points to this same Worker's VendorEntrypoint (per-environment service name). |
| AP-OUT-008 | R2 reads/writes | internal binding | see AP-R2 | |  |
| AP-OUT-009 | D1 reads/writes | internal binding | see AP-D1 | |  |
| AP-OUT-010 | Calls to ABO or Supabase | none found | whole ai-platform/src | | The AP code makes no outbound call to the ABO or Supabase; the ABO calls the AP (VendorEntrypoint methods via service binding, GET /v1/feed/coverage over HTTP); Supabase issues the AI/feed tokens that the AP verifies against issuer_key rows. |

## SSE event types (POST /v1/requests response, text/event-stream)

Wire format: 'event: {type}' line then 'data: {json}' then blank line. Terminal types: completed, failed, cancelled, context_requested (stream closes after the first terminal). Response headers content-type text/event-stream, cache-control no-cache, connection keep-alive.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-SSE-001 | accepted | SSE event | adapter | | First event. data: request_reference, trace_id, degraded_notice (true only when set). |
| AP-SSE-002 | heartbeat | SSE event | stream/index.ts; stream/structured.ts | | Every 15 s (and reset on activity). data: trace_id. |
| AP-SSE-003 | text_delta | SSE event | stream/index.ts | | Prose mode. data: text, sequence, provisional true. |
| AP-SSE-004 | regenerating | SSE event | stream/index.ts; stream/structured.ts | | Discards prior assembled text. data: trace_id. |
| AP-SSE-005 | progress | SSE event | stream/structured.ts | | structured_atomic mode. data: trace_id, bytesReceived. |
| AP-SSE-006 | partial_structured | SSE event | stream/structured.ts | | structured mode. data: sequence, provisional true, document, committed false, committable false. |
| AP-SSE-007 | completed | SSE event (terminal) | adapter; stream; worker | | data: result (prose: finalContent {text, authoritative true}), trace_id. |
| AP-SSE-008 | failed | SSE event (terminal) | adapter; stream; worker | | data: taxonomy error body {code, request_reference, trace_id, retry_safe}. |
| AP-SSE-009 | cancelled | SSE event (terminal) | adapter; stream | | data: trace_id. |
| AP-SSE-010 | context_requested | SSE event (terminal; conversational only) | adapter | | data: context_request, trace_id. Throws if emitted for non-conversational capability. |

## Error codes, result values and reason codes

Includes the 24 taxonomy codes (HTTP/SSE), channel negotiation, control-plane, VendorEntrypoint, Durable Object, transfer, recovery and internal reason codes. Codes returned by the shared vendor-contracts package validators (grant envelope, operation, assertion, receipt) are not enumerated here (outside ai-platform/).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ERR-001 | unauthenticated | taxonomy error code (errors.ts) | errors.ts | | HTTP 401; retryable: After re-mint; consumes quota: No. |
| AP-ERR-002 | installation_suspended | taxonomy error code (errors.ts) | errors.ts | | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-003 | suspended | taxonomy error code (errors.ts) | errors.ts | | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-004 | forbidden_capability | taxonomy error code (errors.ts) | errors.ts | | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-005 | rate_limited | taxonomy error code (errors.ts) | errors.ts | | HTTP 429; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-006 | quota_exhausted | taxonomy error code (errors.ts) | errors.ts | | HTTP 429; retryable: Not until period reset; consumes quota: No. Supplementary field period_reset. |
| AP-ERR-007 | allowance_exhausted | taxonomy error code (errors.ts) | errors.ts | | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-008 | coverage_lapsed | taxonomy error code (errors.ts) | errors.ts | | HTTP 403; retryable: No; consumes quota: No. Supplementary field coverage_reason. |
| AP-ERR-009 | concurrency_limited | taxonomy error code (errors.ts) | errors.ts | | HTTP 429; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-010 | coverage_unknown | taxonomy error code (errors.ts) | errors.ts | | HTTP 503; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-011 | request_too_large | taxonomy error code (errors.ts) | errors.ts | | HTTP 413; retryable: No; consumes quota: No. |
| AP-ERR-012 | context_required | taxonomy error code (errors.ts) | errors.ts | | HTTP 422; retryable: Yes, after resolving; consumes quota: No. Body adds missing_keys, shapes, manifest_version, manifest_capability_id. |
| AP-ERR-013 | context_invalid | taxonomy error code (errors.ts) | errors.ts | | HTTP 422; retryable: No; consumes quota: No. |
| AP-ERR-014 | conversation_budget_exhausted | taxonomy error code (errors.ts) | errors.ts | | HTTP 409; retryable: No, within this conversation; consumes quota: No. |
| AP-ERR-015 | idempotency_conflict | taxonomy error code (errors.ts) | errors.ts | | HTTP 409; retryable: No; consumes quota: No. |
| AP-ERR-016 | capability_unknown | taxonomy error code (errors.ts) | errors.ts | | HTTP 404; retryable: No; consumes quota: No. |
| AP-ERR-017 | capability_retired | taxonomy error code (errors.ts) | errors.ts | | HTTP 404; retryable: No; consumes quota: No. |
| AP-ERR-018 | capability_disabled | taxonomy error code (errors.ts) | errors.ts | | HTTP 503; retryable: Later; consumes quota: No. |
| AP-ERR-019 | provider_unavailable | taxonomy error code (errors.ts) | errors.ts | | HTTP 503; retryable: Yes; consumes quota: Partially, recorded. |
| AP-ERR-020 | provider_rejected | taxonomy error code (errors.ts) | errors.ts | | HTTP 422; retryable: No; consumes quota: Yes. |
| AP-ERR-021 | validation_failed | taxonomy error code (errors.ts) | errors.ts | | HTTP 422; retryable: Yes, at user discretion; consumes quota: Yes. |
| AP-ERR-022 | cancelled | taxonomy error code (errors.ts) | errors.ts | | HTTP 499; retryable: -; consumes quota: Partially, recorded. cancelled has no live HTTP status (SSE only). |
| AP-ERR-023 | timeout | taxonomy error code (errors.ts) | errors.ts | | HTTP 504; retryable: Yes; consumes quota: Partially, recorded. |
| AP-ERR-024 | internal_error | taxonomy error code (errors.ts) | errors.ts | | HTTP 500; retryable: Yes; consumes quota: No. |
| AP-ERR-025 | coverage_reason: none | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-026 | coverage_reason: expired | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-027 | coverage_reason: grace_exhausted | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-028 | coverage_reason: reversed | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-029 | coverage_reason: transferred | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-030 | coverage_reason: transfer_pending | coverage_lapsed coverage_reason value | errors.ts | | Supplementary field on coverage_lapsed body. |
| AP-ERR-031 | contract_version_unsupported | channel negotiation code | vendor-contracts negotiate; vendor/contract-version.ts; worker | | Returned with accepted_versions on Aip-Contract-Version, feed, DO and VendorEntrypoint negotiation failures (HTTP 400 on HTTP routes; result rejected on RPC). |
| AP-ERR-032 | unauthorized | support-lookup HTTP handler error (control/index.ts) | control/index.ts | | HTTP 401. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-033 | missing_reference | support-lookup HTTP handler error (control/index.ts) | control/index.ts | | HTTP 400. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-034 | invalid_reference | support-lookup HTTP handler error (control/index.ts) | control/index.ts | | HTTP 400. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-035 | not_found | support-lookup HTTP handler error (control/index.ts) | control/index.ts | | HTTP 404. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-036 | storage_error | support-lookup HTTP handler error (control/index.ts) | control/index.ts | | HTTP 500. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-037 | invalid_payload | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-038 | invalid_policy_identity | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-039 | invalid_ver | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-040 | missing_installation_ids | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-041 | missing_successor_id | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-042 | not_deprecated | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-043 | overlap_window_active | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-044 | unknown_successor | control-plane action error (ControlActionResult) | control/*.ts | | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-045 | capability_not_found | control-plane action error (ControlActionResult) | control/*.ts | | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-046 | installation_not_found | control-plane action error (ControlActionResult) | control/*.ts | | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-047 | policy_version_not_found | control-plane action error (ControlActionResult) | control/*.ts | | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-048 | ver_not_found | control-plane action error (ControlActionResult) | control/*.ts | | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-049 | activation_state_missing | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-050 | already_deprecated | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-051 | already_published | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-052 | already_retired | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-053 | generation_conflict | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-054 | illegal_installation_transition | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-055 | illegal_kill_switch_transition | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-056 | illegal_policy_transition | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-057 | no_rotation_open | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-058 | not_deprecated | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-059 | rollback_predecessor_unknown | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-060 | rotation_already_open | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-061 | ver_already_exists | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-062 | ver_already_retired | control-plane action error (ControlActionResult) | control/*.ts | | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-063 | invalid_policy_document | control-plane action error (ControlActionResult) | control/*.ts | | Status 422 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-064 | missing_r2_binding | control-plane action error (ControlActionResult) | control/*.ts | | Status 500 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-065 | storage_error | control-plane action error (ControlActionResult) | control/*.ts | | Status 500 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-066 | actor_email_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-067 | approvals_required | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-068 | assertion_expired | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-069 | assertion_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-070 | assertion_required | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-071 | assertion_used | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-072 | bad_assertion | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-073 | bad_request | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-074 | bad_signature | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-075 | binding_route_pending | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-076 | coverage_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-077 | coverage_unknown | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-078 | credential_not_active | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-079 | credential_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-080 | credential_revoked | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-081 | exceeds_ceiling | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-082 | exceeds_plan_bound | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-083 | grant_route_claim_race | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-084 | grant_voided | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-085 | kid_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-086 | kid_revoked | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-087 | limit_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-088 | missing_document | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-089 | missing_installation_id | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-090 | missing_installation_ids | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-091 | missing_lookup_key | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-092 | not_found | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-093 | partial_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-094 | partial_void | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-095 | placement_not_supported | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-096 | plan_not_published | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-097 | plan_version_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-098 | plan_version_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-099 | public_key_cose_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-100 | public_key_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-101 | public_key_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-102 | recovery_audit_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-103 | recovery_blocked | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-104 | recovery_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-105 | recovery_evidence_required | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-106 | recovery_history_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-107 | recovery_identity_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-108 | reversal_commit_pending | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-109 | reversal_due | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-110 | reversal_receipt_unavailable | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-111 | storage_error | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-112 | transfer_pending | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-113 | transfer_route_quarantined | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-114 | unauthenticated | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-115 | unavailable | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-116 | unit_not_allowed | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-117 | unknown_kid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-118 | voided | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-119 | window_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | | Code in rejected/conflict/transient envelope. |
| AP-ERR-120 | deletion_pending | VendorEntrypoint transient detail | vendor/entrypoint.ts | | Appears as detail with result transient and empty code. |
| AP-ERR-121 | transfer_preparation_pending | VendorEntrypoint transient detail | vendor/entrypoint.ts | | Appears as detail with result transient and empty code. |
| AP-ERR-122 | harness_drain_unavailable | harness-only error | vendor/entrypoint.ts | | Raised only by drainDurableObjectsForHarness. |
| AP-ERR-123 | harness_drain_invalid_installations | harness-only error | vendor/entrypoint.ts | | Raised only by drainDurableObjectsForHarness. |
| AP-ERR-124 | awaiting_transfer_out | transfer workflow code | coverage/transfer.ts | | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-125 | reversal_or_transfer_in_progress | transfer workflow code | coverage/transfer.ts | | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-126 | transfer_accounting_pending | transfer workflow code | coverage/transfer.ts | | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-127 | value_route_manifest_pending | transfer workflow code | coverage/transfer.ts | | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-128 | value_route_publish_pending | transfer workflow code | coverage/transfer.ts | | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-129 | result: ok | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-130 | result: rejected | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-131 | result: conflict | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-132 | result: applied | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-133 | result: already_applied | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-134 | result: transient | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-135 | result: blocked | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-136 | result: sealed | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-137 | result: sealed_no_effect | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-138 | result: not_found | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-139 | result: bad_request | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-140 | result: exceeds_ceiling | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-141 | result: accepted | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-142 | result: drained | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | | Top-level result field value. |
| AP-ERR-143 | DO: invalid_json | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-144 | DO: unknown_kind | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-145 | DO: internal_error | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-146 | DO: bad_request | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-147 | DO: recovery_blocked | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-148 | DO: invalid_settle_fallback_args | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-149 | DO: invalid_ack_usage_receipt_args | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-150 | DO: invalid_admission_args | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-151 | DO: invalid_admission_binding | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-152 | DO: invalid_journaled_answer | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-153 | DO: invalid_journaled_conflict | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-154 | DO: invalid_credit_args | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-155 | DO: invalid_release_args | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-156 | DO: installation_id_mismatch | Durable Object RPC error/result | worker GatewayObject.fetch | | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-157 | DO outcome: admitted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-158 | DO outcome: idempotent | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-159 | DO outcome: replay | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-160 | DO outcome: deferred | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-161 | DO outcome: concurrency_exhausted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-162 | DO outcome: coverage_lapsed | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-163 | DO outcome: quota_exhausted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-164 | DO outcome: forbidden_capability | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-165 | DO outcome: idempotency_conflict | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-166 | DO outcome: suspended | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-167 | DO outcome: conflict | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-168 | DO outcome: settled | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-169 | DO outcome: already_accounted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-170 | DO outcome: consumed | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-171 | DO outcome: acknowledged | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-172 | DO outcome: already_acknowledged | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-173 | DO outcome: unknown_request | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | | Outcome field value. |
| AP-ERR-174 | admission/credit result: allowance_exhausted | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-175 | admission/credit result: client_error | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-176 | admission/credit result: concurrency_limited | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-177 | admission/credit result: contract_rejected | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-178 | admission/credit result: coverage_lapsed | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-179 | admission/credit result: coverage_unknown | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-180 | admission/credit result: forbidden_capability | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-181 | admission/credit result: idempotency_conflict | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-182 | admission/credit result: internal_error | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-183 | admission/credit result: suspended | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-184 | admission/credit result: unauthenticated | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-185 | admission/credit result: unavailable | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-186 | admission/credit result: unknown_request | admission/credit module result code | admission/index.ts; credit/index.ts | | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-187 | router exclusion: context_window_too_small | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-188 | router exclusion: cost_class_excluded | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-189 | router exclusion: feature_unsupported | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-190 | router exclusion: installation_excluded | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-191 | router exclusion: kill_switch | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-192 | router exclusion: language_unsupported | routing candidate exclusion reason | router/index.ts | | Reason a provider/model target is excluded. |
| AP-ERR-193 | context_request invalid: element_not_object | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-194 | context_request invalid: invalid_arguments_type | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-195 | context_request invalid: invalid_key_type | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-196 | context_request invalid: missing_arguments | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-197 | context_request invalid: missing_key | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-198 | context_request invalid: root_not_list | context_requested payload validation reason | context/context-request.ts | | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-199 | coverage_mirror_miss | capability guard reason | capability/index.ts | | Internal reason in capability/entitlement check. |
| AP-ERR-200 | no_reask_port | validation reason | validate/index.ts | | Internal validation reason. |
| AP-ERR-201 | grant_recovery_capsule_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-202 | grant_recovery_capsule_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-203 | grant_recovery_capsule_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-204 | grant_recovery_capsule_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-205 | grant_recovery_capsule_schema_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-206 | grant_recovery_ceiling_claim_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-207 | grant_recovery_ceiling_claim_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-208 | grant_recovery_ceiling_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-209 | grant_recovery_claim_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-210 | grant_recovery_claim_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-211 | grant_recovery_command_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-212 | grant_recovery_command_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-213 | grant_recovery_command_metadata_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-214 | grant_recovery_command_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-215 | grant_recovery_command_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-216 | grant_recovery_command_provenance_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-217 | grant_recovery_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-218 | grant_recovery_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-219 | grant_recovery_evidence_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-220 | grant_recovery_identity_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-221 | grant_recovery_override_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-222 | grant_recovery_override_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-223 | grant_recovery_paid_metadata_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-224 | grant_recovery_plan_snapshot_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-225 | grant_recovery_receipt_identity_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-226 | grant_recovery_receipt_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-227 | grant_recovery_route_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-228 | grant_recovery_signing_key_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-229 | grant_recovery_signing_key_unavailable | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-230 | grant_recovery_signing_key_unknown | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-231 | grant_recovery_source_kind_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-232 | grant_recovery_transfer_claim_fields_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-233 | grant_recovery_transfer_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-234 | grant_recovery_transfer_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-235 | grant_recovery_transfer_evidence_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-236 | grant_recovery_transfer_request_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-237 | grant_void_recovery_command_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-238 | grant_void_recovery_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-239 | grant_void_recovery_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-240 | grant_void_recovery_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-241 | grant_void_recovery_evidence_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-242 | grant_void_recovery_grant_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-243 | grant_void_recovery_ledger_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-244 | grant_void_recovery_receipt_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-245 | grant_void_recovery_source_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-246 | grant_route_seal_evidence_missing | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-247 | transfer_replay_evidence_missing | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-248 | usage_accounting_identity_conflict | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-249 | usage_accounting_identity_unknown | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-250 | usage_accounting_sequence_gap | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-251 | usage_accounting_snapshot_invalid | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-252 | usage_accounting_term_identity_conflict | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-253 | ceiling_claim_sealed | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-254 | route_sealed | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-255 | complimentary_ceiling_claim_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-256 | complimentary_ceiling_claim_required | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-257 | complimentary_ceiling_claim_route_mismatch | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-258 | grant_ceiling_claim_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-259 | grant_term_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-260 | reservation_state_unknown | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-261 | reservations_pending | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-262 | coverage_outbox_ship_failed | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-263 | grant_storage_unavailable | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-264 | invalid_platform_signing_key | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-265 | complimentary_ceiling_exceeded | Durable Object coverage code/reason | quota-do/coverage.ts | | Reason/code string in coverage RPC results or thrown errors. |

## Environment variables, secrets and bindings

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ENV-001 | DB | D1 database binding | wrangler.toml | | ai-platform-development / -staging / -production; required at boot (assertRequiredBindings). |
| AP-ENV-002 | R2 | R2 bucket binding | wrangler.toml | | ai-platform-{development,staging,production}; required at boot. |
| AP-ENV-003 | DO | Durable Object namespace binding | wrangler.toml | | class GatewayObject; required at boot. |
| AP-ENV-004 | VENDOR | service binding | wrangler.toml | | Service ai-platform-gateway[-env], entrypoint VendorEntrypoint (self-binding; top-level and per env). |
| AP-ENV-005 | SEND_EMAIL | send_email binding | wrangler.toml | | destination_address alerts@clinic.invalid in every env. |
| AP-ENV-006 | RATE_LIMITER_INSTALLATION | rate limit binding | wrangler.toml | | limit 600 per 60 s; namespace 1001/2001/3001. Falls back to allow-all if unbound. |
| AP-ENV-007 | RATE_LIMITER_INSTALLATION_ACTOR | rate limit binding | wrangler.toml | | limit 120 per 60 s; namespace 1002/2002/3002. |
| AP-ENV-008 | RATE_LIMITER_INSTALLATION_CAPABILITY | rate limit binding | wrangler.toml | | limit 300 per 60 s; namespace 1003/2003/3003. |
| AP-ENV-009 | BUILD_SHA | environment var | wrangler.toml | | 'local' in every env; returned by /health. |
| AP-ENV-010 | ENVIRONMENT | environment var | wrangler.toml | | development \| staging \| production; also gates harness paths and signing-key checks. |
| AP-ENV-011 | LOG_VERBOSITY | environment var | wrangler.toml | | development 2, staging 1, production 0; default 2 in development else 0. |
| AP-ENV-012 | CONFIG_CACHE_TTL_MS | environment var | wrangler.toml | | 100 development, 30000 staging/production. |
| AP-ENV-013 | ISSUER_ID | environment var | wrangler.toml | | 'issuer-test' in all envs; expected iss of AI tokens and feed JWTs. |
| AP-ENV-014 | ACCESS_TEAM_DOMAIN | environment var | wrangler.toml | | 'access.test' in all envs (placeholder); Cloudflare Access issuer domain. |
| AP-ENV-015 | ACCESS_AUD | environment var | wrangler.toml | | 'vendor-access-aud' in all envs; Access JWT audience. |
| AP-ENV-016 | WEBAUTHN_RP_ID | environment var | wrangler.toml | | 'ops.vendor.test' in all envs; relying-party id for operator assertions. |
| AP-ENV-017 | WEBAUTHN_ORIGIN | environment var | wrangler.toml | | 'https://ops.vendor.test' in all envs. |
| AP-ENV-018 | HEARTBEAT_URL | environment var | wrangler.toml | | 'https://heartbeat.test/ping' in all envs; fallback heartbeat URL. |
| AP-ENV-019 | ALERT_EMAIL_TO | environment var | wrangler.toml | | 'alerts@clinic.invalid' in all envs; sender and recipient of alert emails. |
| AP-ENV-020 | DURATION_SCALE | environment var | wrangler.toml | | Set to 'staging' only in env.staging; scales term durations when equal to 'staging'. |
| AP-ENV-021 | PLATFORM_SIGNING_KEY | secret / var | wrangler.toml; vendor entrypoint; quota-do | | JSON {kid, pkcs8, public_key}. A development fixture is in env.development vars; staging/production values not in wrangler.toml (secret). Rejected if missing, malformed or the published development key (outside development). |
| AP-ENV-022 | DEEPSEEK_API_KEY | secret (dynamic binding) | provider/deepseek.ts; worker resolveProviderPort | | Looked up by name from env at call time; not declared in wrangler.toml. |
| AP-ENV-023 | GEMINI_API_KEY | secret (dynamic binding) | provider/gemini.ts; worker resolveProviderPort | | Looked up by name from env at call time; not declared in wrangler.toml. |
| AP-ENV-024 | HEARTBEAT_URL_PLATFORM | optional environment var | alert/index.ts | | Overrides HEARTBEAT_URL for the platform 5-minute stream; not set in wrangler.toml. |
| AP-ENV-025 | ACCESS_CERTS_JSON | optional environment var | vendor/entrypoint.ts | | Local test override of Access certificates JSON; when set, no network fetch. |
| AP-ENV-026 | TEST_CLOCK | optional environment var (harness) | clock.ts; worker | | '1' enables D1 harness clock (harness_test_clock) and harness DO hooks; not set in wrangler.toml. |
| AP-ENV-027 | TEST_DO_ALARM_DELIVERY_DELAY_MS | optional environment var (harness) | quota-do/coverage.ts | | Delays alarm delivery for tests (capped); not set in wrangler.toml. |
| AP-ENV-028 | OPERATOR_BEARER_TOKEN | local dev var file only | ai-platform/.dev.vars, .dev.vars.development | | Present in local dev vars files; not read by any file under src. |
| AP-ENV-029 | [triggers] crons | wrangler trigger config | wrangler.toml | | 0 3 * * *, 0 4 * * *, */5 * * * * (declared once at top level, not repeated per environment). |
| AP-ENV-030 | [[migrations]] tag v1 | Durable Object migration | wrangler.toml | | new_sqlite_classes = [GatewayObject]. |
| AP-ENV-031 | [[rules]] Text **/prompts/**/*.md | bundler rule | wrangler.toml | | Markdown prompt files imported as text. |
| AP-ENV-032 | compatibility_date 2026-05-03; observability enabled; workers_dev false; preview_urls false | worker settings | wrangler.toml | | Worker name ai-platform-gateway; per-env names -development, -staging, -production. |
| AP-ENV-033 | Environments | wrangler environments | wrangler.toml | | development, staging, production, each with own vars, D1, R2, DO binding, rate limiters, VENDOR service binding. |

## Custom request/response headers and query parameters

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-HDR-001 | Aip-Contract-Version (request and response) | HTTP header | vendor/contract-version.ts; worker | | Required on /v1/capabilities, /v1/requests (POST and GET), /v1/coverage, /v1/feed/coverage. Response echoes negotiated version; JSON object bodies gain contract_version. |
| AP-HDR-002 | Authorization: Bearer | HTTP header | identity; worker | | AI token (AAT) or feed JWT. |
| AP-HDR-003 | x-idempotency-key | HTTP request header | adapter | | Required on POST /v1/requests. |
| AP-HDR-004 | x-capability-version | HTTP request header | adapter | | Required on POST /v1/requests. |
| AP-HDR-005 | x-trace-id | HTTP request header | adapter; trace.ts | | Optional; any non-empty value accepted; otherwise ULID generated. |
| AP-HDR-006 | If-None-Match / ETag / Cache-Control | HTTP headers | capability/index.ts | | Capability discovery caching (private, must-revalidate). |
| AP-HDR-007 | query after, limit | query parameters | worker feed handler | | Feed cursor and page size on /v1/feed/coverage. |
