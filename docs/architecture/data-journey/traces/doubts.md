
## Flutter inventory (inventory-flutter)

- `ClinicalAcceptController` and `ClinicalAcceptanceClient` (RPC `record_ai_acceptance`) have no constructor call outside their own folder in `frontend/lib`; the surface's Accept button only sets a local "acknowledged" phase. Unsure whether acceptance recording is wired anywhere else (e.g. not yet integrated). Chapter 28 must confirm from the backend side and state exactly what the desktop does today.
- `ConversationLoop` / `ConversationStore` (conversational legs, `context_requested`) have no caller outside `core/ai`. Unsure whether conversational capabilities are reachable from the UI.
- The deployment profile field `ai_service_url` is parsed into `SupabaseConfig.aiServiceUrl`, but no AI code reads it; the AP address comes only from `platform_base_url` in `get_ai_status`. Unsure if this is intentional.
- Localization keys `aiBillingErrorOfferUnavailable` and `aiBillingErrorTermsNotAccepted` exist but are not referenced; offer_unavailable and terms_not_accepted instead navigate back to the offers step with no message.
- No Flutter call to `GET /v1/requests/{ref}` (lookup), billing-token-less ABO routes, or any key enrollment / installation registration was found in `frontend/lib`; no clinic keypair or keystore code exists on the Flutter side. Where keypair enrollment (chapter 3) is triggered must be confirmed from the Supabase / backend inventory.
- The AI page is a hub with a visit-id text field and demo widgets; the only live AI surface is the `clinic.visit_summary` host. Unclear whether it is intended as the production entry point.
- `AiFeatureHostPage` (production file) imports an http mock client and uses it when a network spy is injected; kept as noted in FL-CALL-021.
- AAT `ver` check decodes the JWS payload without verifying the signature (client-side check only).

## Supabase inventory (inventory-supabase agent)

- Contract version acceptance: all public wrappers hard-code accepted versions (0, 1). The app_settings key ai.contract_versions has backendRpc {current 1, minimum 0}, but no function reads backendRpc. Unsure whether the setting is meant to drive the wrappers; only platformFeed.current is read (by the feed puller).
- ai.aat.lifetime_minutes, ai.aat.audience, ai.aat.ver settings still exist in app_settings but the latest issue_ai_token ignores them (fixed 600 s, aud ai-platform, ver 2). Confirm that nothing outside Supabase (other workers) reads them.
- public.issue_ai_token's internal body ignores its p_contract_version argument (the wrapper only validates it). Contrast with billing token, which echoes it in rpc_result.contract_version.
- issue_ai_token builds its header and payload with plain jsonb text (not the canonical RFC 8785 function used by billing and feed tokens). Could matter if the AP verifier requires byte-equal canonical JSON for AI tokens; needs checking against the AP verifier code (not done here).
- public.request_ai_status_refresh is granted to anon as well as authenticated. The body rejects anonymous callers (session check), but a fresh reader may want the reason confirmed.
- ai_internal.launch_state still reports whether set_ai_availability exists, although that function was dropped in 20261007230000. Unclear intent.
- issuer_key.not_after is set (13 months) but no function checks it; switch_issuer_signing_kid has no caller in the migrations (presumably called by the ABO/operator via a direct database connection). Not verified outside Supabase.
- Erasure: no Supabase migration, function or table named for erasure was found. Only delete_clinic_test_fixtures (test helper) clears ai_token_issuance and ai_accepted_output. Erasure appears to live outside Supabase (ABO/AP); not confirmed.
- Acceptance: record_ai_acceptance looks up branch_id from public.visits using the domain record id; this works only for the visit-based target. Fine today (one target), noted for completeness.
- public.ai_accepted_output: the earlier blanket GRANT on all public tables to authenticated (20260516100200) ran before this table existed; the table grant is SELECT only. Whether default privileges give more was not checked.
- pg_net/pg_cron job runs in the same database; the response table net._http_response is read directly. Local-dev URL rewrite to host.docker.internal is applied unconditionally to localhost/127.0.0.1 URLs.

## ABO inventory (inventory-abo agent)

- Work rows of kind `transfer_step` are read by the minute cron step `transfer_steps` (`runDueTransferSteps`), but no INSERT of such a row was found anywhere in `abo/src`. Unsure whether the inline transfer path (`continueTransferInline`) fully replaces them or whether they are written elsewhere (for example restored by rebuild). The transfer chapter must confirm.
- The tables `harness_test_clock` and `harness_issuer_pin` are read by the code when `TEST_CLOCK` is "1" but no migration creates them (only a test harness can). Their column names were inferred from the queries (`id`, `now_iso`; `kid`, `public_key`). They are listed as test-only.
- Table `token_use` is both created by migration 0001 and created again at request time by `CREATE TABLE IF NOT EXISTS` in the rate limiter. Unsure why; harmless but noted.
- Table `scheduled_job_run` (migration 0009) is declared unused by migration 0021 comments; no code reads or writes it. `paymob_intention` is still written by the Paymob adapter (when an intention is created) and also treated as a forbidden legacy summary by the ledger exporter; unclear if it is still intended to be live.
- `fact_log.table` value `paymob_intention_attempt_event` is replayable but rows carrying `client_secret` are refused by the exporter; the order in which a secret could land in fact_log vs. be stripped was not traced.
- The error code `assertion_required` is returned with HTTP 400 for local HP actions, but the console shell text also mentions `approval_required` for operator-credential bootstrap. No ABO code emits `approval_required` itself; it presumably comes from the AP relay result. Unconfirmed.
- Local HP refusals (including `not_found`, `conflict`-like results such as `payment_not_withheld`, `reversal_exists`, `allocation_conflict`) are all returned as HTTP 400 with the result string as the code, while the same code `not_found` elsewhere in the ops API is HTTP 404. Recorded as-is in the inventory; the operator chapters should state both.
- `GET /return/paymob` is matched by a prefix test, so any path beginning with `/return/paymob` on the billing host reaches the handler. Intent not confirmed.
- Alert codes AL-11, AL-12, AL-13, AL-17 to AL-21 are not defined in ABO source (the AlertCode type skips them); presumably AP-owned or unused.

## AP inventory (inventory-ap agent)

- There is no HTTP control-plane or ops route on the AP. Control and operator actions exist only as methods on the service-binding entrypoint (VendorEntrypoint). `handleSupportLookup` (an HTTP-style handler with errors unauthorized, missing_reference, invalid_reference, not_found, storage_error) is exported from the control module but no route in the Worker entry calls it. Unsure whether it is dead code or used outside `ai-platform/src`.
- The `dashboards` module (latency, cost, quota rejection queries) is not referenced by the Worker entry or any route; treated as unwired.
- `OPERATOR_BEARER_TOKEN` appears only in the local dev vars files, not in any source file under `src`. Unsure whether it is leftover from an older HTTP control plane.
- Two tables are read by code but absent from all migrations: `harness_test_clock` and `harness_admission_fault`. They are read only when `TEST_CLOCK=1`. Presumed test-harness-only.
- `wrangler.toml` carries placeholder values (Access team domain `access.test`, issuer `issuer-test`, WebAuthn host `ops.vendor.test`, heartbeat `heartbeat.test`, alert address `alerts@clinic.invalid`) in the production block as well; real values must be supplied at deploy time by something not visible in the repository. `PLATFORM_SIGNING_KEY` has a development fixture only in the development block. `DEEPSEEK_API_KEY`, `GEMINI_API_KEY` and `HEARTBEAT_URL_PLATFORM` are not declared anywhere in `wrangler.toml`.
- The shared package `packages/vendor-contracts` (outside the AP area) defines CHANNEL_VERSIONS (all channels currently 1), `negotiate` (a missing requested version is refused as `contract_version_unsupported`; the current and current-minus-one versions are accepted), and the grant, operation, assertion and receipt validators. Error codes returned by those validators were not enumerated in the AP inventory.
- Resolved from AP code (answers a Supabase-inventory doubt): the AP verifies the AI token signature over the raw "header.payload" text exactly as received (Ed25519, header alg EdDSA, kid looked up in `issuer_key`), then checks `aud`, `iss` equal to ISSUER_ID, lifetime at most 600 s with 60 s clock skew, and `ver` against `token_contract`. It does not require canonical JSON. A first valid token for an organization with no live `tenant_binding` makes the AP create the `installation` and `tenant_binding` rows itself (epoch 1, capped at 50 per 24 h by a trigger, otherwise AL-20 and 401). This is relevant to the "installation registered on the AP" chapter.
- The request ingress accepts both `capability_id` and `capability`, and both `user_intent` and `intent`, in the POST body. Unsure whether the aliases are used by any caller.
- Error code lists for transfer, recovery and the Durable Object were extracted by pattern from string literals; dynamic or composed codes (for example a code with a suffix appended) may be missing.
