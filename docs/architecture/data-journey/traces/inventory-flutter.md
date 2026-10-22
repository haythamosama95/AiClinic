# Flutter inventory (Phase 0, working file)

Scope: the clinic desktop app, the AI folder under the core area, the AI feature folder, the app-shell status provider, the router entries, localization strings, and config. Tests ignored. "Source area" is a convenience hint only and is not published. "Assigned group" is empty on purpose.

Note on scope: the clinic's own patient-invoice billing feature (invoices, visit billing, refunds, payments to the clinic) lives in a separate billing feature folder and is NOT the AI billing flow; it was left out because it does not call the ABO, the AP, or the AI/billing RPCs.

## 1. Call sites (outbound calls)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CALL-001 | RPC `get_ai_status` (param `p_contract_version`) | Supabase RPC | features/ai/availability reader | | Called by the shell status notifier refresh, the host bootstrap when no live status is pushed, the host admin-coverage refresh, and the live-host composer. Reply is a versioned rpc_result. |
| FL-CALL-002 | RPC `issue_ai_token` (param `p_contract_version`) | Supabase RPC | core/ai AAT mint port | | Returns a bare JWS string; client checks the `ver` claim equals "2". Callers: SDK token acquisition, discovery manifest refresh, composer discovery step, host coverage fetch. |
| FL-CALL-003 | RPC `issue_billing_token` (param `p_contract_version`) | Supabase RPC | features/ai/billing token client | | Returns token, abo_base_url, expires_at in rpc_result data. Called on billing page bootstrap and on renewal. |
| FL-CALL-004 | RPC `get_ai_billing_status` (param `p_contract_version`) | Supabase RPC | features/ai/billing subscription summary | | Read together with GET /v1/subscription on each summary load. Notices list inside it is scanned for `ended_reversed`. |
| FL-CALL-005 | RPC `request_ai_status_refresh` (param `p_contract_version`) | Supabase RPC | features/ai/billing administrator page | | Called when a checkout reaches Active (projection pull). Only success flag is used. |
| FL-CALL-006 | RPC `record_ai_acceptance` (params `p_request_reference`, `p_target_key`, `p_target_args`) | Supabase RPC | features/ai/acceptance client | | Client and controller exist. No screen was found that constructs them (see doubts). |
| FL-CALL-007 | RPC `get_visit_chief_complaint` (param `p_visit_id`) | Supabase RPC | core/ai context provider port | | Sole context resolver backend. Reply is rpc_result; no contract-version parameter is sent. |
| FL-CALL-008 | AP `GET {platformBaseUrl}/health` | HTTP | features/ai/availability reachability port | | 5 second timeout; any 2xx is reachable; no token sent. Called by host bootstrap unless probe is skipped. |
| FL-CALL-009 | AP `GET /v1/capabilities` | HTTP | core/ai discovery client | | Bearer AAT, header Aip-Contract-Version, optional If-None-Match. Called by composer and by manifest refresh (self-heal). |
| FL-CALL-010 | AP `GET /v1/coverage` | HTTP | core/ai usage summary client | | Bearer AAT, Aip-Contract-Version. Only for administrators, from the host bootstrap and admin-coverage refresh. |
| FL-CALL-011 | AP `POST /v1/requests` (SSE reply) | HTTP | core/ai https submit port | | Bearer AAT, idempotency, trace, capability-version, accept event-stream, Aip-Contract-Version headers. Body fields listed in FL-HDR section. |
| FL-CALL-012 | ABO `GET /v1/offers` | HTTP | features/ai/billing abo client | | Called by the offers screen on load and retry. |
| FL-CALL-013 | ABO `GET /v1/billing-contact` | HTTP | abo client | | 404 with code `not_found` is read as "contact missing". Called by billing contact form on load. |
| FL-CALL-014 | ABO `PUT /v1/billing-contact` | HTTP | abo client | | Body client_request_id, name, email, phone. Called on Save contact. |
| FL-CALL-015 | ABO `POST /v1/checkouts` | HTTP | abo client | | Body client_request_id, offer_id, offer_version, terms_version. Called on Pay now. |
| FL-CALL-016 | ABO `GET /v1/checkouts/{checkoutId}` | HTTP | abo client | | Polling read; concurrent refreshes for the same id are shared. |
| FL-CALL-017 | ABO `GET /v1/checkouts?open=1` | HTTP | abo client | | Used on billing page bootstrap to resume an open checkout, and by checkout screen when only a reference is known. |
| FL-CALL-018 | ABO `GET /v1/subscription` | HTTP | abo client | | Called by the subscription summary and by the commercial notices widget. |
| FL-CALL-019 | ABO `GET /v1/payments` and `?cursor=` | HTTP | abo client | | Payment history first page and next pages. |
| FL-CALL-020 | Payment page launch (`redirect_url` from checkout create) | External URL open | features/ai/billing checkout screen | | Opens the external application (browser) via the URL launcher; this is the hand-off to Paymob. |
| FL-CALL-021 | Local fixture HTTP for `/v1/coverage` inside the host | Mock client in production file | features/ai/host | | When a network spy is injected, host builds a mock http client that answers /v1/coverage with fixed figures; used by tests/harness. |

## 2. Providers, state holders and controllers

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-PROV-001 | `aiShellStatusNotifierProvider` (notifier of AiStatusSnapshot) | Riverpod notifier | app/providers | | One status source for the whole app shell; timers: next_change_at timer and 5 minute periodic; resets on identity change or sign-out. |
| FL-PROV-002 | `aiShellStatusReaderProvider` | Riverpod provider | app/providers | | Supplies the get_ai_status reader (Supabase). Override point. |
| FL-PROV-003 | `aiShellStatusRefreshProvider` | Riverpod provider | app/providers | | Exposes the notifier refresh function; shared by app start, resume, AI page host. |
| FL-PROV-004 | `aiStatusIdentityFor` (user id, organization id, role) | Helper | app/providers | | Identity is null when not authenticated or clinic setup is needed. |
| FL-PROV-005 | `AiStatusSnapshot` (identity, availability, updateRequired, refreshFailed) | State object | features/ai/availability | | Published state of the shell notifier. |
| FL-PROV-006 | `AiStatusFetchGate` | Ordering helper | features/ai/availability | | Generation counter so late reads cannot overwrite newer state. |
| FL-PROV-007 | `planAiStatusApply` / `AiStatusApplyPlan` (awaitStatus, updateRequired, noticesOnly, retainDenial, recomposeHost) | Decision function and enum | features/ai/availability | | Decides how an open host reacts to a new status. |
| FL-PROV-008 | `aiStatusContextKey` (update-required, unknown, unavailable, ready|baseUrl) | Helper | features/ai/availability | | Readiness key used to detect recomposition. |
| FL-PROV-009 | App lifecycle hooks in the app root (start, resume, became-ready) | Lifecycle code | app/app.dart | | Triggers shell status refresh; starts periodic refresh once; resume also reloads auth context. |
| FL-PROV-010 | `authSessionProvider` (consumed) | Riverpod provider | app/providers | | Source of identity and administrator role for AI status and AI page. |
| FL-PROV-011 | `supabaseClientProvider` (consumed) | Riverpod provider | core/config | | Client passed into AI composition. |
| FL-PROV-012 | `AiFeatureHostPage` state (mode, resolver, resolverEpoch, contextKey, denialRetained, notices, credits, subscriptionRef, planDisplayName, denial wire code and retry-after, request and bootstrap generations) | Widget state | features/ai/host | | Holds degraded mode, resolver lifetime, administrator commercial fields. |
| FL-PROV-013 | `AiFeatureHostDependencies` | Dependency bundle | features/ai/host | | Reader, reachability port, SDK, context provider, manifest refresh port, visit id, required keys, mint port, usage client, flags (skipReachabilityProbe, autoInvoke, staffIsAdministrator), onStatusRefresh. |
| FL-PROV-014 | `LiveVisitSummaryComposition` and `buildLiveVisitSummaryComposition` / `composeLiveVisitSummaryHost` | Composer | features/ai/presentation ai_page | | Reads status, mints AAT, runs discovery, builds SDK and ports. Flags contractVersionUnsupported and discovery failure code/reference. Default platform base URL placeholder is an example workers.dev address; invalid placeholder `https://ai.invalid` used when no base URL. |
| FL-PROV-015 | `LiveVisitHostIdentity` and `liveVisitHostIdentityFor` | Identity key | ai_page | | Key over user, organization, administrator flag, visit id; changes dispose the host. |
| FL-PROV-016 | `_LiveVisitSummaryHost` state (composition, load generation) | Widget state | ai_page | | Loads composition; watches shell status and passes it as liveStatus only when identity matches. |
| FL-PROV-017 | `FirstAiFeatureSurface` state (phase idle/loading/streaming/completed/failed/localFailed/acknowledged/discarded; provisional text; terminal text; request reference; session) | Widget state | features/ai/surface | | Drives invoke, stream listening, terminal handling. |
| FL-PROV-018 | `AdministratorBillingPage` state (step loading/offers/contact/checkout/appUpdate; selection; resumed checkout; billing generation; projection status idle/pending/pullFailed/caughtUp; epoch; reread count; baseline summary; timer) | Widget state | features/ai/billing | | Owns sibling-read generation and the post-Active projection catch-up chain (pull, then up to 4 rereads 30 seconds apart). |
| FL-PROV-019 | `SubscriptionSummary` state, `CommercialNotices` state, `PaymentHistory` state, `OffersScreen` state, `BillingContactForm` state, `CheckoutScreen` state | Widget state | features/ai/billing | | Each uses a request sequence and generation to drop stale replies. Checkout screen holds poll timer, poll failure count, client request id. |
| FL-PROV-020 | `ClinicalAcceptController` (staged request reference, staged complaint) | Controller | features/ai/acceptance | | Accept calls the port with target key `visit_clinical_notes`; discard clears staging only. |
| FL-PROV-021 | `ConversationLoop` and `ConversationStore` (conversation id, transcript, pending user turn, leg ordinal) | Controller and local state | core/ai | | Conversational legs; no UI caller found (see doubts). Transcript kinds: user, model, context_requested, context_resolved. |
| FL-PROV-022 | `ContextRequiredSelfHeal` | Orchestrator | core/ai | | One refresh, resolve, resubmit round for single-shot capabilities. |
| FL-PROV-023 | `AiClientSdk` and `AiInvokeSession` | SDK class | core/ai | | Token cache, in-flight mint sharing, remint once on unauthenticated, transport retry, idempotency key, trace id, last request reference. |
| FL-PROV-024 | `DiscoveryManifestRefreshPort` (cached manifests, interaction mode lookup) | Port implementation | core/ai | | Keeps manifests in memory; mode conversational vs single-shot. |
| FL-PROV-025 | `InMemoryAiPersistenceProbe`, `InMemoryAiExportProbe`, `InMemoryPlatformNetworkSpy` | Probe classes in production files | features/ai | | Observation helpers; no real persistence. |

## 3. Clients, ports and repositories

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CLIENT-001 | `AboClient` | HTTP client | features/ai/billing | | All ABO clinic calls; reserves a billing token per request; one retry on GET after 429 with code rate_limited or token_use_limit. |
| FL-CLIENT-002 | `BillingTokenClient` | Token client | features/ai/billing | | See token section. |
| FL-CLIENT-003 | `SupabaseAiAvailabilityReader` (port `AiAvailabilityReader`) | RPC reader | features/ai/availability | | get_ai_status; null data means not enrolled. |
| FL-CLIENT-004 | `HttpPlatformReachabilityPort` (port `PlatformReachabilityPort`) | HTTP probe | features/ai/availability | | GET /health. |
| FL-CLIENT-005 | `SupabaseAatMintPort` (port `AatMintPort`) | RPC port | core/ai | | issue_ai_token. |
| FL-CLIENT-006 | `PlatformHttpsSubmitPort` (port `HttpsSubmitPort`) | HTTP+SSE port | core/ai | | POST /v1/requests; pre-stream error mapping; SSE connection. |
| FL-CLIENT-007 | `DiscoveryClient` | HTTP client | core/ai | | GET /v1/capabilities; keeps last ETag in memory. |
| FL-CLIENT-008 | `UsageSummaryClient` | HTTP client | core/ai | | GET /v1/coverage. |
| FL-CLIENT-009 | `SupabaseContextProviderPort` (port `ContextProviderPort`) | RPC port | core/ai | | One per visit; get_visit_chief_complaint. |
| FL-CLIENT-010 | `ClinicalAcceptanceClient` (port `ClinicalAcceptancePort`) | RPC client | features/ai/acceptance | | record_ai_acceptance with local error mapping (see errors). |
| FL-CLIENT-011 | `ContextResolver` | Resolver | core/ai | | Key to resolver registry with per-screen cache. |
| FL-CLIENT-012 | `RpcResult` and `RpcFailure` | Shared RPC reply model | core/rpc | | Fields success, data, error_code, error_message, contract_version. |
| FL-CLIENT-013 | Contract version guard (`echoesContractVersion`, `requireEchoedRpcContractVersion`, `isKnownContractVersion`) | Validation helper | core/contract_version_guard | | Accepts sent version only if it is current or current minus 1, and the reply echoes it. |
| FL-CLIENT-014 | Test seams (rpc injection, debugAboContractVersionOverride) | Injection points | various | | Present in production files; listed for completeness. |

## 4. Token handling

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-TOKEN-001 | AI token (AAT) cache in the SDK | Memory cache | core/ai AiClientSdk | | One cached token string; cleared once on `unauthenticated` then reminted; concurrent mints share one in-flight future. Never persisted. |
| FL-TOKEN-002 | AAT `ver` claim check ("2") | Validation | core/ai mint port | | Decodes the JWS payload without verifying the signature; mismatch raises contract-version-unsupported. |
| FL-TOKEN-003 | AAT used as Bearer on AP routes | Header | core/ai | | Used by submit, discovery, coverage. |
| FL-TOKEN-004 | Billing token session (token, abo_base_url, expires_at) | Memory object | features/ai/billing | | In memory only for the page lifetime; disposed with the page. |
| FL-TOKEN-005 | Billing token renewal rule | Logic | billing token client | | Renew when within 30 seconds of expiry. |
| FL-TOKEN-006 | Billing token local use cap | Logic | billing token client | | Max local uses 59 per token; then a new token is minted. Counter reserved before each ABO call. |
| FL-TOKEN-007 | Billing token invalidation on server 429 | Logic | abo client | | GET only: on rate_limited or token_use_limit the session is dropped and one fresh token is used for one retry. |
| FL-TOKEN-008 | Mint error handling for both token RPCs | Logic | both mint paths | | Postgrest message containing CONTRACT_VERSION_UNSUPPORTED becomes contract-version-unsupported; billing mint also validates echoed version, requires data, token, abo_base_url, expires_at. |
| FL-TOKEN-009 | Supabase session / anon key handling | Config and session | core/config | | Not AI-specific; supplies the authenticated session under which the RPCs run. |

## 5. SSE parser and stream grammar

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-SSE-001 | Line parser (UTF-8 stateful decode, line splitting on LF, CRLF, CR) | Parser | core/ai https submit port | | Blank line ends a block; lines starting `event:` and `data:` only; other lines (id:, comments) ignored; multiple data lines are concatenated without separator. |
| FL-SSE-002 | Wire event `accepted` | Event mapping | https submit port | | Needs `request_reference`, else dropped. |
| FL-SSE-003 | Wire event `heartbeat` | Event mapping | https submit port | | Ignored by consumers. |
| FL-SSE-004 | Wire events `text_delta`, `partial_structured`, `usage`, `provider_note` | Event mapping | https submit port | | All become content chunks keeping kind and payload; only `text_delta` text is shown by the surface. |
| FL-SSE-005 | Wire event `completed` | Event mapping | https submit port | | Result is `result` field or whole data. |
| FL-SSE-006 | Wire event `failed` | Event mapping | https submit port | | Fields code, request_reference, trace_id, retry_safe; unknown code becomes internal error. |
| FL-SSE-007 | Wire event `cancelled` | Event mapping | https submit port | | Defensive parse; SDK synthesizes its own cancelled on local cancel. |
| FL-SSE-008 | Wire event `context_requested` | Event mapping | https submit port | | Field `context_request` list; used by conversational loop. |
| FL-SSE-009 | Unknown event type, bad JSON, non-object data | Drop rule | https submit port | | Silently dropped. |
| FL-SSE-010 | Terminal state model (completed, failed, cancelled, stream-dropped, context-requested) | Model | core/ai sse_events and SDK | | Stream end or error without terminal and without local cancel is stream-dropped (retry-safe). Local cancel closes the connection. |
| FL-SSE-011 | Stream response gate (status 2xx and content-type text/event-stream, header Aip-Contract-Version echo) | Check | https submit port | | Non-SSE or non-2xx goes to pre-stream error mapping; missing echo closes the stream unread. |
| FL-SSE-012 | Provisional vs terminal prose extraction (`provisionalChunkText`, `terminalProseText`) | Helpers | features/ai/surface | | Terminal prose read from `final content`.`text` or `text`. |
| FL-SSE-013 | Transport retry policy | Policy | core/ai SDK | | 3 attempts, backoff base 100 ms doubling capped at 800 ms with jitter; same idempotency key; then retry-exhausted. |
| FL-SSE-014 | Event relay (single-subscription source rebroadcast) | Mechanism | core/ai SDK | | Allows surface and terminal consumer to listen together. |

## 6. Context resolvers and registration

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CTX-001 | `contextRegistration` map (closed static) | Registry | core/ai context_registration | | Single entry: key `visit.chief_complaint@v1` mapped to chief complaint fetch. |
| FL-CTX-002 | `visit.chief_complaint@v1` | Context key | core/ai | | Resolved through RPC get_visit_chief_complaint with the active visit id. |
| FL-CTX-003 | `ContextResolver.resolve` / `resolveRequests` | Resolver | core/ai | | Unknown key gives failure code `unknown_context_key`; resolver exception gives `resolution_failed`; results cached per resolver instance; disposed resolver throws. |
| FL-CTX-004 | Context requirement extraction from manifests (`requiredContextKeysFromManifests`) | Helper | core/ai discovery client | | Reads Identity capabilityId and Context requirements (key, required flag) by either spelling; default key list used if none found. |
| FL-CTX-005 | Default required keys for the first capability | Constant | features/ai/surface | | List containing only visit.chief_complaint@v1. |
| FL-CTX-006 | Self-heal on `context_required` | Behaviour | core/ai context_required_self_heal | | Only for single-shot capabilities; needs missing_keys; refresh manifests, resolve, resubmit once with same idempotency key and same capability version; second rejection surfaces; unhealable if no missing keys. |
| FL-CTX-007 | Heal abort exception (`ContextHealResolveException`) | Exception | core/ai | | Carries resolve failure and request reference. |
| FL-CTX-008 | Interaction mode lookup (conversational vs single-shot) | Logic | discovery manifest refresh port | | Reads Interaction.interactionMode; default single-shot. |
| FL-CTX-009 | Initial context sent with first invoke | Behaviour | first surface | | Context = visit_id plus resolved payload; resolved before submit; failure shows local failure. |
| FL-CTX-010 | Conversational context loop (`context_requested` handling) | Behaviour | core/ai conversation loop | | Resolves requested keys with arguments, appends transcript turns, submits continuation leg; resolve failure becomes internal-error failed terminal. |
| FL-CTX-011 | Capability constants (id `clinic.visit_summary`, version `1.0.0`, intent `generate`) | Constants | features/ai/surface | | Hard-coded first capability. |

## 7. Error and code mappings (code to what the code does / UI shows)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-ERR-001 | Taxonomy set: unauthenticated, installation_suspended, forbidden_capability, rate_limited, quota_exhausted, request_too_large, context_required, context_invalid, conversation_budget_exhausted, capability_unknown, capability_retired, capability_disabled, provider_unavailable, provider_rejected, validation_failed, cancelled, timeout, internal_error, allowance_exhausted, coverage_lapsed, coverage_unknown, suspended, concurrency_limited, contract_version_unsupported, status_stale | Wire code enum (25) | core/ai taxonomy | | Unknown wire code maps to internal_error. |
| FL-ERR-002 | Pre-stream denial rules: allowance_exhausted (403), coverage_lapsed (403, coverage_reason), coverage_unknown (503, retry_after), suspended (403), concurrency_limited (429, retry_after), rate_limited (429, retry_after), contract_version_unsupported (400, accepted_versions) | Status+code pairing | core/ai taxonomy | | A code with a non-matching status is not treated as denial and falls to the generic mapping. |
| FL-ERR-003 | Pre-stream generic error body mapping | Mapping | https submit port | | Reads code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id; unparsable body becomes transport failure (retried). |
| FL-ERR-004 | `unauthenticated` at submit | Behaviour | core/ai SDK | | One remint and retry; second surfaces. |
| FL-ERR-005 | `contract_version_unsupported` (platform, 400 or missing header echo) | Behaviour | https submit port, discovery, coverage | | Raises contract-version-unsupported exception; host shows app-update mode. |
| FL-ERR-006 | Transport failure / retries exhausted | Behaviour | SDK and surface | | Surface reports coverage_unknown with network-failure flag, giving "unreachable" mode, plus failure view. |
| FL-ERR-007 | Discovery auth failure (taxonomy code and body) | Behaviour | discovery client, composer | | Composer stores failure code and request reference; `installation_suspended` shows suspended view; reference shown otherwise; autoInvoke is off. |
| FL-ERR-008 | Coverage auth failure | Behaviour | usage summary client, host | | Returns null silently; no gauge. |
| FL-ERR-009 | Coverage response shape errors (not object, missing snapshot, term not object, used/allowance not numeric) | Format errors | usage summary client | | Raise format error; host swallows and logs. |
| FL-ERR-010 | Terminal failure to degraded mode mapping | Mapping | features/ai/degraded ai_degraded_mode | | installation_suspended and suspended to installationSuspended; forbidden_capability to forbiddenCapability; quota_exhausted, allowance_exhausted, coverage_lapsed to quotaExhausted; coverage_unknown and status_stale to unreachable; concurrency_limited and rate_limited to safetyLimited; contract_version_unsupported, capability_unknown, capability_retired to appUpdate; provider_unavailable to providerUnavailable; capability_disabled to aiUnavailable; network failure to unreachable; other codes leave mode unchanged. |
| FL-ERR-011 | Coverage denial wire codes that trigger a status refresh: allowance_exhausted, coverage_lapsed, coverage_unknown | Set | features/ai/availability | | Host calls onStatusRefresh and retains denial when status-fed. |
| FL-ERR-012 | Stream failed terminal handling in surface | Behaviour | first surface | | Notifies host with code and wire code, shows request reference or "No request reference" text. |
| FL-ERR-013 | Stream dropped terminal handling | Behaviour | first surface | | Reports internal_error to host, shows failure with last reference. |
| FL-ERR-014 | Local failures (resolve failure, unexpected exception, unexpected context_requested terminal) | Behaviour | first surface | | Shows "could not be started on this device" text with any real reference. |
| FL-ERR-015 | Cancelled / invoke cancelled | Behaviour | first surface | | Returns to idle. |
| FL-ERR-016 | ABO error codes: offer_unavailable (with current_version), idempotency_conflict, billing_contact_required, terms_not_accepted, provider_unavailable (with checkout_id), rate_limited, contract_version_unsupported (with accepted_versions), invalid_request, other/unknown (code or `abo_error`) | Exception classes | abo client | | Mapped from body `code` on any non-2xx; each carries contract_version. |
| FL-ERR-017 | ABO 2xx version echo failure | Behaviour | abo client | | Header Abo-Contract-Version and body contract_version must echo; else contract-version-unsupported with accepted versions [current-1, current]. |
| FL-ERR-018 | ABO 404 `not_found` on billing contact | Behaviour | abo client | | Read as "no contact yet". |
| FL-ERR-019 | Checkout screen reactions | UI mapping | checkout_screen | | offer_unavailable returns to offers; billing_contact_required returns to contact step; terms_not_accepted returns to offers; provider_unavailable shows provider-unavailable message and keeps checkout id; rate_limited shows rate-limited message (and in polling backs off); contract_version_unsupported shows app-update view; any other shows raw error text. |
| FL-ERR-020 | Offers screen reactions | UI mapping | offers_screen | | contract_version_unsupported calls parent to app-update; terms_not_accepted unchecks terms; other error shows "plans could not be loaded" with retry. |
| FL-ERR-021 | Billing contact form reactions | UI mapping | billing_contact_form | | billing_contact_required shows message; contract_version_unsupported goes to app-update; other error shows raw text. |
| FL-ERR-022 | Billing page bootstrap reactions | UI mapping | administrator_billing_page | | Version errors give app-update step; other errors give offers step with load error. |
| FL-ERR-023 | Summary / notices / payment-history failure reactions | UI mapping | billing widgets | | Summary: "coverage details could not be loaded" with retry; notices: raw error text with retry; history: "payment history could not be loaded" with retry. |
| FL-ERR-024 | Payment launch failure | UI mapping | checkout_screen | | Shows hard-coded English text "Could not open payment page". |
| FL-ERR-025 | Checkout poll backoff | Behaviour | checkout_screen | | Poll every 1 second normally; on failures 2 to 15 seconds (power of two clamp); polls while Waiting, Paid or Failed; stops on Active or Abandoned. |
| FL-ERR-026 | RPC failure codes: `CONTRACT_VERSION_UNSUPPORTED` (error_code) and echoed-version mismatch | Mapping | RPC readers | | Becomes contract-version-unsupported exception; other failures raise RpcFailure with code and message. |
| FL-ERR-027 | Acceptance client local codes: `AUTH_ERROR`, `RPC_NOT_APPLIED` (PGRST202 or function missing), `RPC_NOT_CONFIGURED` (42501 or permission denied), passthrough postgrest code or `POSTGREST_ERROR` | Mapping | acceptance client | | Wrapped into RpcResult with failure flag. |
| FL-ERR-028 | Context provider failures: `EMPTY_DATA`, RpcFailure | Mapping | context provider port | | Resolver turns any throw into resolution_failed. |
| FL-ERR-029 | Shell status failure handling | Behaviour | ai_shell_status_provider | | Contract-version-unsupported sets updateRequired; other failures keep last valid data and set refreshFailed. |
| FL-ERR-030 | Host bootstrap failure handling | Behaviour | host | | Contract-version-unsupported gives app-update mode; any other error is fail-closed to not-enrolled (no AI chrome). |
| FL-ERR-031 | Enum parse errors (checkout shown_state unknown, payment classification unknown, reversal kind unknown, expires_at/datetime invalid) | Format errors | abo client | | Raise format error; shown as generic failure. |
| FL-ERR-032 | Billing mint format errors (no data, incomplete session, invalid expires_at) | Errors | billing token client | | State/format errors. |

## 8. Notice codes

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-NOTICE-001 | Status notices from `get_ai_status` `notices[]` (fields code, audience, channel, grace_days_left) | Notice record | features/ai/availability | | Rendered by the host banner list. |
| FL-NOTICE-002 | `ends_soon` | Status notice code | host banner | | Separate wording for administrator and staff. |
| FL-NOTICE-003 | `in_grace` (uses grace_days_left; zero shows "less than one day"; missing or negative gives neutral text) | Status notice code | host banner | | Plural-aware localized text; administrator and staff variants. |
| FL-NOTICE-004 | `allowance_low` | Status notice code | host banner | | Admin and staff variants. |
| FL-NOTICE-005 | `allowance_exhausted` | Status notice code | host banner | | Admin and staff variants. |
| FL-NOTICE-006 | `lapsed` | Status notice code | host banner | | Admin and staff variants. |
| FL-NOTICE-007 | `ended_reversed` | Status notice code | host banner and commercial notices and summary | | Admin and staff variants in banner; admin text in commercial notices; summary shows a separate "recent plan ending reversed" line. |
| FL-NOTICE-008 | `suspended` | Status notice code | host banner | | Admin and staff variants. |
| FL-NOTICE-009 | `status_stale` | Status notice code | host banner | | Admin and staff variants. |
| FL-NOTICE-010 | Unknown status code | Fallback | host banner | | Neutral "status information is unavailable" text; wire code never printed. |
| FL-NOTICE-011 | Banner audience behaviour | UI rule | host banner | | Administrator banner has a Renew button to the billing page (hard-coded English "Renew"); staff banner appends "ask your administrator". The notice's audience and channel fields are parsed but not used to choose text. |
| FL-NOTICE-012 | Commercial notices from `GET /v1/subscription` `notices` (list of strings): `duplicate_payment` | Commercial notice code | features/ai/billing commercial_notices | | Shown only on the administrator billing page. |
| FL-NOTICE-013 | `late_payment_honoured` | Commercial notice code | commercial_notices | | |
| FL-NOTICE-014 | `payment_withheld` | Commercial notice code | commercial_notices | | |
| FL-NOTICE-015 | `reversal_recorded` | Commercial notice code | commercial_notices | | |
| FL-NOTICE-016 | `terms_held` | Commercial notice code | commercial_notices | | |
| FL-NOTICE-017 | `ended_reversed` in commercial notices; unknown commercial code fallback to neutral text | Commercial notice rule | commercial_notices | | |
| FL-NOTICE-018 | `notices` inside RPC `get_ai_billing_status` (only `ended_reversed` is read) | Notice use | subscription_summary | | Others ignored. |
| FL-NOTICE-019 | Projection notices: pending ("coverage update requested ...") and pull-failed | UI notice | administrator_billing_page | | Shown after checkout reaches Active. |
| FL-NOTICE-020 | Starts-after-current-term notice | UI notice | checkout_screen | | Shown when create response `starts` is `after_current`; user presses Pay to continue. |
| FL-NOTICE-021 | Localization keys defined but not referenced: `aiBillingErrorOfferUnavailable`, `aiBillingErrorTermsNotAccepted` | Unused strings | l10n | | See doubts. |

## 9. Degraded and denied UI states

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-DEG-001 | Mode `nonEnrolled` | Degraded mode | ai_degraded_mode / view | | No AI chrome; only status notices if any. Also the fail-closed outcome of bootstrap errors and when available is false. |
| FL-DEG-002 | Mode `unreachable` | Degraded mode | degraded view | | Text "AI service unreachable". Triggered by health probe failure, network failure, coverage_unknown, status_stale. |
| FL-DEG-003 | Mode `quotaExhausted` | Degraded mode | degraded view | | Text depends on wire code: allowance_exhausted or coverage_lapsed show "AI not available, contact your administrator"; otherwise "AI quota exhausted. Contact your administrator." |
| FL-DEG-004 | Mode `aiUnavailable` | Degraded mode | degraded view | | "AI temporarily unavailable" (capability_disabled). |
| FL-DEG-005 | Mode `appUpdate` | Degraded mode | degraded view | | "Update the app to use AI". Triggers: contract-version failures, capability_unknown or retired, shell updateRequired, billing page version errors. |
| FL-DEG-006 | Mode `providerUnavailable` | Degraded mode | degraded view | | "AI temporarily unavailable" with Retry button that re-enables the surface. |
| FL-DEG-007 | Mode `installationSuspended` | Degraded mode | degraded view | | wire `suspended`: "AI not available, contact your administrator"; otherwise "AI features are suspended for this installation." Administrator with `suspended` also sees "Contact support" plus the subscription reference. |
| FL-DEG-008 | Mode `forbiddenCapability` | Degraded mode | degraded view | | "Not included in your clinic's AI plan"; administrator may also see plan display name. |
| FL-DEG-009 | Mode `safetyLimited` | Degraded mode | degraded view | | "AI busy, try again shortly" plus retry_after text when present. |
| FL-DEG-010 | Mode `ready` | Normal mode | degraded view | | Wraps the child surface. |
| FL-DEG-011 | "Renew or buy" button for administrators on allowance_exhausted or coverage_lapsed | Action | degraded view | | Navigates to the administrator billing route. |
| FL-DEG-012 | Surface-hiding rule (all modes except ready hide the surface and show "Clinical workflows remain available.") | Rule | host | | Resolver disposed when hidden. |
| FL-DEG-013 | Denial retention (coverage denial stays until fresh status shows recovery) | Rule | host and snapshot plan | | Only for status-fed hosts. |
| FL-DEG-014 | Status-driven recomposition never auto-invokes | Rule | host | | User must press to run again. |
| FL-DEG-015 | Discovery-failure views (installation_suspended view; request reference line for other discovery failures) | Pre-host states | ai_page liveVisitSummaryHostBody | | Contract-version failure at compose time shows app-update view. |
| FL-DEG-016 | Administrator-only usage gauge hidden for non-administrators; commercial fields masked at render for non-administrators | Rule | host | | Role loss clears credits, plan name and subscription reference immediately. |
| FL-DEG-017 | Surface phases: loading text, streaming provisional prose, completed, failed (with/without reference), local failure, acknowledged, discarded, idle | Surface states | first surface | | Texts are hard-coded English. |
| FL-DEG-018 | Billing page app-update step | Degraded state | administrator_billing_page | | Replaces page body with app-update view. |
| FL-DEG-019 | Billing widgets' loading/refreshing/error/empty states | UI states | billing widgets | | Offers: loading, error, empty, list; summary: no active plan vs active plan; history: empty, error, load more. |
| FL-DEG-020 | Route redirect for non-administrators on billing route | Access rule | router | | Non-administrator is sent to home. |

## 10. Screens, pages and widgets

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-UI-001 | AI page (`/ai`) | Screen | features/ai/presentation/pages/ai_page | | Hub: administrator billing entry card, live visit-summary host (visit id field + Load surface), surface primitives demo, degraded-mode demo, and design-system demos (mode toggle, thinking indicator, message bubbles, inline suggestion, proposed action, AI panel). |
| FL-UI-002 | Administrator billing page (`/ai/administrator-billing`) | Screen | features/ai/billing | | Steps offers, contact, checkout; siblings summary, notices, history; Refresh billing button. Administrator-only via redirect. |
| FL-UI-003 | Offers screen | Widget | billing | | Offer cards (localized name/summary, price), terms text, accept checkbox, Continue; empty/error states. |
| FL-UI-004 | Billing contact form | Widget | billing | | Name, email, phone, Save contact; idempotency id per payload. |
| FL-UI-005 | Checkout screen | Widget | billing | | Reference, price, shown state label (Waiting, Failed, Paid, Active, Abandoned), Pay now, queued-term line. |
| FL-UI-006 | Subscription summary | Widget | billing | | Plan name, started, ends, grace ends, credits included/used, clinic support reference, ended-reversed line. Also parsed (queued_count, held_count) but not displayed. |
| FL-UI-007 | Commercial notices | Widget | billing | | List of localized commercial notice lines. |
| FL-UI-008 | Payment history | Widget | billing | | Plan name, date, reference, raw amount minor + currency, Load more. Reversals and classification are parsed but not displayed. |
| FL-UI-009 | Billing money formatter | Helper | billing | | Minor units divided by 100 with 2 decimals. |
| FL-UI-010 | AI feature host page (`/ai/feature-host`, route extra) | Screen | features/ai/host | | Standalone host requiring dependencies via route extra; otherwise a text message. Also used embedded in AI page. |
| FL-UI-011 | First AI feature surface | Widget | features/ai/surface | | Auto-invokes on mount; Accept (local acknowledgement only) and Discard. |
| FL-UI-012 | Provisional prose view | Widget | surface | | Draft styling with semantics label "AI draft content". |
| FL-UI-013 | Request reference view | Widget | surface | | "Reference: <id>". |
| FL-UI-014 | Usage gauge, gate marker, unreachable marker | Widgets | surface | | Credits used vs budget bar. |
| FL-UI-015 | AI degraded view | Widget | degraded | | See degraded section; keyed widgets per mode. |
| FL-UI-016 | Status notice banner list | Widget | host | | Admin Renew button or staff note. |
| FL-UI-017 | Shell nav entry `ai` and route meta text | Navigation | app/shell navigation | | Route `/ai` in shell nav config. |
| FL-UI-018 | Routes: `/ai`, `/ai/administrator-billing`, `/ai/feature-host` | Route constants | app/app_routes, router | | Billing route has administrator redirect. |
| FL-UI-019 | Design-system AI showcase and core UI components (AI panel, message bubble, suggestion, thinking indicator, proposed action card, mode toggle) | Components | core/ui and design_system | | Visual demos; no backend calls found. |
| FL-UI-020 | Localization strings with prefix `aiBilling` and `aiNotice` (English and Arabic) | Strings | l10n | | Count of English keys with these prefixes is 74 in each of English and Arabic; hard-coded English strings also exist in degraded view and surface. |

## 11. Local storage and key store

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-STORE-001 | No AI or billing data is written to local storage, secure storage or key store | Finding of absence | whole frontend/lib | | Searched for shared preferences, secure storage and key store use: only unrelated settings, setup draft, workspace mode, idle timeout, deployment profile. No clinic keypair or private key handling found in the Flutter code. |
| FL-STORE-002 | AI token and billing token are memory-only | Fact | core/ai, billing | | See token section. |
| FL-STORE-003 | Conversation transcript is memory-only and cleared on close | Fact | core/ai conversation store | | |
| FL-STORE-004 | ETag for discovery is memory-only | Fact | discovery client | | Kept per client instance. |
| FL-STORE-005 | Deployment profile file/store (contains optional `ai_service_url`) | Config store | core/config | | `ai_service_url` is parsed into the config but no AI code reads it (platform base URL comes from get_ai_status). |

## 12. Environment, config and constants

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CFG-001 | `ABO_CONTRACT_VERSION_OVERRIDE` | Process environment variable | abo client | | Overrides the Abo-Contract-Version header value (desktop platforms). |
| FL-CFG-002 | `ABO_BILLING_HOST` | Process environment variable | abo client | | Overrides the Host header sent to the ABO. |
| FL-CFG-003 | Local billing host constant `billing.vendor.test` | Constant | abo client | | Host header used when the ABO base URL host is 127.0.0.1 or localhost. |
| FL-CFG-004 | Contract version constants: aboClinic 1, aboConsole 1, backendRpc 1, platformClinic 1, platformFeed 1, vendorEntrypoint 1, platformDo 1, paymobReturn 1, paymobAdapter 1 | Constants | core/contract_versions | | backendRpc sent as `p_contract_version`; platformClinic as Aip-Contract-Version; aboClinic as Abo-Contract-Version; the rest are not used by Flutter AI code. |
| FL-CFG-005 | `expectedTokenVer` "2" | Constant | mint port | | AAT `ver` claim. |
| FL-CFG-006 | `kDefaultMaxTransportAttempts` 3 and backoff constants | Constant | SDK | | |
| FL-CFG-007 | Billing token constants: renew-before-expiry 30 seconds, max local uses 59 | Constants | billing token client | | |
| FL-CFG-008 | Projection constants: reread interval 30 seconds, max rereads 4 | Constants | billing page | | |
| FL-CFG-009 | Shell status constants: periodic interval 5 minutes | Constant | shell notifier | | Also next_change_at timer. |
| FL-CFG-010 | Health probe timeout 5 seconds | Constant | reachability port | | |
| FL-CFG-011 | Checkout poll interval 1 second and backoff cap 15 seconds | Constants | checkout screen | | |
| FL-CFG-012 | Default platform base URL placeholder (example workers.dev) and invalid placeholder `https://ai.invalid` | Constants | ai_page composer | | Placeholder when no real base URL is known. |
| FL-CFG-013 | Platform base URL source: `platform_base_url` field of `get_ai_status` | Config source | availability model | | The only runtime source of the AP address. |
| FL-CFG-014 | ABO base URL source: `abo_base_url` field of `issue_billing_token` | Config source | billing token client | | |
| FL-CFG-015 | Deployment profile keys: `deployment_mode`, `supabase_url`, `supabase_anon_key`, `ai_service_url`, `source_device_role` | Config keys | core/config | | Only `ai_service_url` is AI-related and appears unused. |
| FL-CFG-016 | Client request id format (`billing-checkout-<microseconds>`, `billing-contact-<microseconds>`) | Generated id | checkout screen, contact form | | Reused across retries until contact payload changes; checkout id stable per screen. |
| FL-CFG-017 | SDK idempotency key and trace id generation (32 hex chars, secure random) | Generated id | SDK and self-heal | | Self-heal pins one key across both submits; conversation legs pass an optional key factory. |

## 13. Wire headers and fields (client side)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-HDR-001 | `Authorization: Bearer <AAT>` on AP routes | Header | core/ai | | |
| FL-HDR-002 | `Aip-Contract-Version` (sent 1; response must echo) | Header | core/ai | | Checked on submit, discovery (including 304) and coverage. |
| FL-HDR-003 | `x-idempotency-key`, `x-trace-id`, `x-capability-version`, `accept: text/event-stream`, `content-type: application/json` | Headers | https submit port | | |
| FL-HDR-004 | Submit body: capability_id, capability_version, user_intent, context, conversation_id, turn_ordinal, transcript | Body fields | https submit port | | The last three only for conversational legs. |
| FL-HDR-005 | `if-none-match` and response `etag` | Headers | discovery client | | 304 requires version echo, keeps cached manifests. |
| FL-HDR-006 | `Authorization: Bearer <billing token>` on ABO routes | Header | abo client | | |
| FL-HDR-007 | `Abo-Contract-Version` (sent 1; response header and body field contract_version must echo) | Header | abo client | | |
| FL-HDR-008 | `Host` header override on ABO calls | Header | abo client | | See FL-CFG-002 and FL-CFG-003. |
| FL-HDR-009 | `content-type: application/json` on PUT/POST to ABO | Header | abo client | | |
| FL-HDR-010 | RPC param `p_contract_version` | RPC field | all versioned RPCs | | |

## 14. Wire DTOs parsed by Flutter

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-DTO-001 | `get_ai_status` data: available (or enrolled), state, reason, days_left, band, notices[], next_change_at, as_of, stale, platform_base_url | DTO | availability model | | `enrolled` kept as legacy gate; `state`, `band`, `days_left`, `as_of`, `stale` are parsed and kept but not read by UI. `reason` is compared with coverage denial codes. |
| FL-DTO-002 | `issue_billing_token` data: token, abo_base_url, expires_at | DTO | billing token client | | |
| FL-DTO-003 | Offers: contract_version, offers[] (offer_id, version, plan_display_name, term_unit, term_count, price_minor, currency, allowance_credits, grace_days, copy{locale:{name,summary}}, terms{version,text}) | DTO | abo client | | Locale picks device language then `en` then plan name. |
| FL-DTO-004 | Billing contact: contract_version, version, name, email, phone | DTO | abo client | | |
| FL-DTO-005 | Checkout create: contract_version, checkout_id, reference, redirect_url, expires_at, starts (`now` or `after_current`), projected_start | DTO | abo client | | projected_start kept only for after_current; not displayed. |
| FL-DTO-006 | Checkout read: contract_version, reference, shown_state (Waiting, Failed, Paid, Active, Abandoned), offer{offer_id, version, term_unit, term_count, charged_price_minor, currency}, updated_at | DTO | abo client | | |
| FL-DTO-007 | Open checkouts: contract_version, checkouts[] | DTO | abo client | | First open checkout is resumed. |
| FL-DTO-008 | Payments: contract_version, payments[] (reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification normal/likely_duplicate/late, reversals[] reference/amount_minor/kind refund/void/chargeback/unknown/is_full), next_cursor, has_more | DTO | abo client | | |
| FL-DTO-009 | Subscription: contract_version, subscription_ref, snapshot (free map), notices[] | DTO | abo client | | Snapshot is kept as a raw map; the summary widget does not read it (display fields come from get_ai_billing_status). |
| FL-DTO-010 | `get_ai_billing_status` data: plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, queued_count, held_count, subscription_ref, notices[{code}] | DTO | subscription_summary | | |
| FL-DTO-011 | Coverage: subscription_ref, snapshot{term{used, allowance, plan_display_name}}, queued_terms, recent_terms | DTO | usage_summary_client | | Only subscription_ref and term used/allowance/plan name are read. |
| FL-DTO-012 | Capabilities: manifests[] (Identity, Context requirements, Interaction), response contract_version | DTO | discovery client | | Keys read by two spellings (capitalised phrase or snake case). |
| FL-DTO-013 | `get_visit_chief_complaint` data (map passed through as context value) | DTO | context provider port | | |
| FL-DTO-014 | `record_ai_acceptance` target args for key `visit_clinical_notes`: p_visit_id, p_complaint, p_history, p_examination, p_diagnosis, p_plan, p_expected_updated_at | DTO | acceptance controller | | |
| FL-DTO-015 | Failed event / pre-stream error body: code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id, retry_after, coverage_reason, accepted_versions | DTO | https submit port | | |
