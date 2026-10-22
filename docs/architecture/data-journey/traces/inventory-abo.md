# ABO inventory

Working file for the data-journey docs (Phase 0). Area: everything under `abo/` (source, migrations, wrangler config, scripts). Facts only, taken from the code. "Assigned group" is left empty on purpose. "Source area" is for the agents' convenience and is not published.

General facts that apply to many rows:

- The ABO is one Cloudflare Worker with two hostnames: the billing host (`BILLING_HOST`, clinic-facing and Paymob-facing) and the ops host (`OPS_HOST`, operator console). A request to the wrong host for a path family answers an empty 404. An unknown host answers an empty 404.
- While the ABO recovery fence is active (table `abo_recovery_fence`, `active = 1`) every fetch answers HTTP 503 with the plain text body `abo_recovery_in_progress`, and every cron tick returns without doing anything.
- Billing `/v1/*` pipeline, in order: contract-version gate (`Abo-Contract-Version`, channel `aboClinic`; current and current minus one are accepted), billing-token authentication (Bearer JWT, Ed25519, header `kid` looked up in `ISSUER_KEYS`, audience `abo`, issuer `ISSUER_ID`, token `ver` "2", lifetime at most 300 s, 60 s clock skew, claims `sub org role branch jti iat exp`), per-token rate limit (`token_use`, 60 hits per `jti`), then routing. Unknown `/v1/*` paths therefore still need a valid token before the empty 404.
- Ops pipeline: contract-version gate (channel `aboConsole`; on refusal the 400 body gets `reload: true`), then Cloudflare Access JWT (`Cf-Access-Jwt-Assertion`, verified against `https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`, audience `ACCESS_AUD`), then routing. The single exception is `GET /ops`, which skips the version gate (a browser navigation cannot send the header) but still verifies Access.
- "HP-local" below means: Access JWT plus a WebAuthn operator assertion (body `{operation, assertion}`) verified inside the ABO against the active operator credentials listed by the AP. "HP-relay" means: Access JWT plus operation and assertion forwarded to the AP. "Class-H relay" means: only the Access JWT (as `access_jwt`) is forwarded to the AP, no assertion is built by the ABO.
- The ABO has no Durable Objects and no Supabase calls. Its only link to Supabase is that it verifies billing tokens signed by the Supabase-held issuer key pinned in `ISSUER_KEYS`.

---

## 1. HTTP routes (ABO-ROUTE)

Billing host (`BILLING_HOST`).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ROUTE-001 | GET /v1/offers | route, billing host | worker, clinic-api/offers | | Billing token. Lists sellable offers: latest offer_event of kind published/reinstated per offer, newest sellable version, copy, plus current English terms text read from R2 (digest checked). Malformed stored offer is skipped and raises alert offer_malformed. 200 `{contract_version, offers[]}` |
| ABO-ROUTE-002 | GET /v1/subscription | route, billing host | worker, clinic-api/billing-reads | | Billing token. Calls AP getCoverage for the caller's org, falls back to local coverage_view. Returns `{contract_version, subscription_ref, snapshot, notices[]}` |
| ABO-ROUTE-003 | GET /v1/payments | route, billing host | worker, clinic-api/billing-reads | | Billing token. Optional query `cursor` (a payment reference of the same org). Page size 20, ordered by paid_at then reference. Returns `{payments[], next_cursor, has_more}`; each payment carries reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals[]. Bad cursor: 422 invalid_request |
| ABO-ROUTE-004 | GET /v1/billing-contact | route, billing host | worker, clinic-api/billing-contact | | Billing token. Latest billing_contact version of the caller's org; 404 not_found when none |
| ABO-ROUTE-005 | PUT /v1/billing-contact | route, billing host | worker, clinic-api/billing-contact | | Billing token. Body `client_request_id, name, email, phone` (phone E.164). Idempotent per (org, client_request_id): same hash replays, different hash gives 409 idempotency_conflict. Appends a new version row |
| ABO-ROUTE-006 | POST /v1/checkouts | route, billing host | worker, clinic-api/checkouts | | Billing token. Body `client_request_id, offer_id, offer_version, terms_version`. Creates checkout, status, opened event, first Paymob intention attempt, calls Paymob, returns 201 `{checkout_id, reference, redirect_url, expires_at, starts, projected_start?}`. After a 201 the worker schedules the sweep work rows |
| ABO-ROUTE-007 | GET /v1/checkouts?open=1 | route, billing host | worker, clinic-api/checkouts | | Billing token. Lists the org's checkouts whose status is open, paid or paid_late as read objects. Without `open=1` the same path answers 404 not_found (JSON) |
| ABO-ROUTE-008 | GET /v1/checkouts/{checkout_id} | route, billing host | worker, clinic-api/checkouts | | Billing token. One checkout read object (reference, shown_state, offer summary, payment_reference null, term_ref null, updated_at). 404 not_found if other org or state has no display |
| ABO-ROUTE-009 | any other method/path under /v1/ | route fallthrough | worker | | After gate, auth and rate limit: empty 404 (also wrong method on /v1/billing-contact, /v1/offers etc.) |
| ABO-ROUTE-010 | POST /notify/paymob | route, billing host | worker, notify/intake | | No bearer token; authenticity is the Paymob HMAC (`PAYMOB_HMAC_SECRET`). Body size cap 1,048,576 bytes (413), must be UTF-8 (400), per-IP rate 60 per minute window (429), unparseable (200 + notification row + AL-23), bad HMAC (401 + hmac-invalid R2 object, AL-02 after 3 in 15 min), unmatched (200 + AL-05), good (200 after confirm attempt). Empty bodies on all |
| ABO-ROUTE-011 | GET /notify/paymob | route, billing host | worker, notify/intake | | Paymob processed-callback via query string (query used as the body). Bad HMAC 401; unparseable 200; matched checkout schedules a confirm work row; always empty body |
| ABO-ROUTE-012 | GET /return/paymob (prefix match) | route, billing host | worker, notify/intake | | Browser return page after payment. Path match is `startsWith /return/paymob`. Schedules confirm work for every checkout whose status is open; answers 200 HTML "Please return to your clinic application." The return URL given to Paymob carries `?v=` (paymobReturn channel version) |
| ABO-ROUTE-013 | any other /notify/ or /return/ path or method | route fallthrough | worker | | Empty 404 |

Ops host (`OPS_HOST`). Auth terms as defined at the top.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ROUTE-020 | GET /ops | route, ops host | worker, ops/browser/shell | | Console HTML shell, Access only, no version header needed, `cache-control: no-store`. Exactly `/ops` (not `/ops/`) |
| ABO-ROUTE-021 | GET /ops/ceremony-context | route, ops host | ops/index | | Access + console version. Returns `{contract_version, actor_email, rp_id (= OPS_HOST), origin, credentials[{credential_id, alg}]}` (active operator credentials from AP listOperatorCredentials) |
| ABO-ROUTE-022 | GET /ops/lookup?q= | route, ops host | ops/index | | Access. Resolves a query (org UUID, CK- checkout ref, PAY- payment ref, GR- grant ref, AIC- subscription ref, or billing e-mail) to `org_id`; 404 not_found |
| ABO-ROUTE-023 | GET /ops/clinics/{org_id} | route, ops host | ops/index | | Access. Clinic dossier: AP getCoverage + inspectCoverage, then D1 checkouts (with events), payments, reversals, grant_requests with outcome and receipt, operator_actions, findings, active alerts. Error from AP coverage: 404 with AP code or coverage_unknown |
| ABO-ROUTE-024 | GET /ops/parked | route, ops host | ops/index | | Access. Work rows in state parked |
| ABO-ROUTE-025 | GET /ops/findings | route, ops host | ops/index | | Access. All finding rows |
| ABO-ROUTE-026 | GET /ops/grants | route, ops host | ops/index | | Access. AP listGrants grouped by source_kind and by operator_credential_id |
| ABO-ROUTE-027 | GET /ops/launch-state | route, ops host | ops/index | | Access. Read-only launch check: ABO signing kid, issuer keys pinned, AL-23 active, term and grant counts (AP countLedgerRows), channel versions (ABO and AP readLaunchState), platform signing key pinned, key self-check. AP failure: 503 transient |
| ABO-ROUTE-028 | GET /ops/payout-imports | route, ops host | ops/index | | Access. Query `limit` (1 to 200, default 50) and `cursor` (`period|import_id`). Newest period first |
| ABO-ROUTE-029 | POST /ops/payout-imports | route, ops host | ops/index | | Access. Raw CSV bytes as body. Validated whole file (provider payoutLines), stored in R2 under payouts/, import and lines in D1, then reconciliation is run inline. 422 invalid_request with `line_errors[]` |
| ABO-ROUTE-030 | POST /ops/findings/{finding_id}/resolve | route, ops host | ops/index | | Access. Body `{note}`. Inserts finding_resolution, deactivates alert AL-10:{finding_id}. 404 not_found, 400 invalid_request |
| ABO-ROUTE-031 | GET /ops/registries | route, ops host | ops/index | | Access. AP lists: issuer_keys, service_keys, operator_credentials |
| ABO-ROUTE-032 | POST /ops/parked/{work_id}/retry | route, ops host | ops/index | | Access. Only parked work of kind grant or reverse. Returns work to open. 404 not_found, 409 conflict |
| ABO-ROUTE-033 | POST /ops/checkouts/{checkout_id}/cancel | route, ops host | ops/index | | Access. Only when status is open. Sets status cancelled, writes cancelled event. 404 not_found, 409 conflict |
| ABO-ROUTE-034 | POST /ops/checkouts/{checkout_id}/transaction-id | route, ops host | ops/index | | Access. Body `{transaction_id}` (digits, 1 to 32). Only when no paymob_txn known for the checkout. Opens a manual confirm work row and runs it. Returns `{action_id, work_id}`. 400 invalid_request, 404 not_found, 409 conflict |
| ABO-ROUTE-035 | POST /ops/offers/{offer_id}/publish | route, ops host | ops/index | | HP-local (op publish_offer). Signed params exactly `offer_id, price_minor, terms_text, copy`. Writes terms text to R2, new terms_version, offer_version, offer_event. 400 on every refusal |
| ABO-ROUTE-036 | POST /ops/offers/{offer_id}/retire | route, ops host | ops/index | | HP-local (op retire_offer). Params exactly `offer_id`. Appends offer_event retired |
| ABO-ROUTE-037 | POST /ops/offers/{offer_id}/reinstate | route, ops host | ops/index | | HP-local (op reinstate_offer). Params exactly `offer_id`. Appends offer_event published for the latest published version |
| ABO-ROUTE-038 | POST /ops/payments/{payment_id}/release | route, ops host | ops/index | | HP-local (op release_payment, durable accepted command). Only for disposition withheld_mismatch and not fully reversed. Inserts payment_release and a grant work row |
| ABO-ROUTE-039 | POST /ops/payments/{payment_id}/chargeback | route, ops host | ops/index | | HP-local (op manual_chargeback, durable accepted command). Inserts operator reversal (kind chargeback, full), reversal_request, reverse work row; runs it |
| ABO-ROUTE-040 | POST /ops/orgs/{org_id}/erase-contact | route, ops host | ops/index | | HP-local (op erase_contact, durable accepted command). Blanks billing_contact name/email/phone, bumps erasure fence, deletes raw evidence R2 bodies |
| ABO-ROUTE-041 | POST /ops/orgs/{org_id}/complimentary-grant | route, ops host | ops/index | | HP-relay to AP `grant`. Body `action_id, envelope, operation, signer_credential_id, assertion?, ceiling_override_operation?`. Stores grant_request (source_kind complimentary) and outcome event |
| ABO-ROUTE-042 | POST /ops/orgs/{org_id}/suspend | route, ops host | ops/index | | Class-H relay to AP `suspend`. Body `action_id, reason` |
| ABO-ROUTE-043 | POST /ops/orgs/{org_id}/resume | route, ops host | ops/index | | Class-H relay to AP `resume`. Body `action_id, reason` |
| ABO-ROUTE-044 | POST /ops/orgs/{org_id}/delete-installation | route, ops host | ops/index | | HP-relay to AP `deleteInstallation`. Body `action_id, reason, operation, assertion, signer_credential_id` |
| ABO-ROUTE-045 | POST /ops/orgs/{org_id}/begin-transfer | route, ops host | ops/index | | HP-relay to AP `beginTransfer`, then inline `transferOut` and `transferIn`. Body `action_id, from_installation_id, reason (1 to 256 chars), operation (op beginTransfer, nonce = action_id), assertion, signer_credential_id`. Verified locally before relay |
| ABO-ROUTE-046 | POST /ops/grants/list-for-void | route, ops host | ops/index | | Access relay to AP `listGrantsForVoid`. Body `action_id, credential_id, window` |
| ABO-ROUTE-047 | POST /ops/coverage/recover-stranded | route, ops host | ops/index | | HP-relay to AP `recoverStrandedTerm`. Body includes `action_id, org_id, installation_id, binding_epoch, target_term_id, source_grant_id, expected_clinic_seq, reason, evidence_sha256, signer_credential_id, operation, assertion` |
| ABO-ROUTE-048 | POST /ops/grants/{grant_id}/void | route, ops host | ops/index | | HP-relay to AP `voidGrant`. Body `action_id, reason, operation, assertion, signer_credential_id` |
| ABO-ROUTE-049 | POST /ops/grants/{grant_id}/release-held | route, ops host | ops/index | | HP-relay to AP `releaseHeld`. Same body shape as void |
| ABO-ROUTE-050 | POST /ops/operator-credentials | route, ops host | ops/index | | Relay to AP `registerOperatorCredential`. Body `action_id, credential_id, attestation, operation?, assertion?, signer_credential_id?`. Remembers the credential in seen_operator_credential on ok. Used by the console bootstrap |
| ABO-ROUTE-051 | POST /ops/operator-credentials/{credential_id}/revoke | route, ops host | ops/index | | HP-relay to AP `revokeOperatorCredential` |
| ABO-ROUTE-052 | POST /ops/plan-versions | route, ops host | ops/index | | HP-relay to AP `publishPlanVersion`. Fields plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit, max_allowance_per_month |
| ABO-ROUTE-053 | POST /ops/ceiling-policy | route, ops host | ops/index | | HP-relay to AP `setCeilingPolicy`. Fields per_grant_max_days, per_grant_max_allowance_months, window_days, window_max_days, window_max_allowance_months, max_paid_grace_days, paid_cap_rule |
| ABO-ROUTE-054 | POST /ops/plan-versions/retire | route, ops host | ops/index | | HP-relay to AP `retirePlanVersion`. Fields plan_id, version |
| ABO-ROUTE-055 | POST /ops/issuer-keys | route, ops host | ops/index | | HP-relay to AP `registerIssuerKey`. Fields kid, public_key, not_before, not_after |
| ABO-ROUTE-056 | POST /ops/issuer-keys/{kid}/revoke | route, ops host | ops/index | | HP-relay to AP `revokeIssuerKey` |
| ABO-ROUTE-057 | POST /ops/issuer-keys/{kid}/retire | route, ops host | ops/index | | HP-relay to AP `retireIssuerKey` |
| ABO-ROUTE-058 | POST /ops/service-keys | route, ops host | ops/index | | HP-relay to AP `registerServiceKey`. Fields kid, public_key, not_before, not_after |
| ABO-ROUTE-059 | POST /ops/service-keys/{kid}/revoke | route, ops host | ops/index | | HP-relay to AP `revokeServiceKey` |
| ABO-ROUTE-060 | POST /ops/routing-policy | route, ops host | ops/index | | Class-H relay to AP `publishRoutingPolicy`. Field `document` |
| ABO-ROUTE-061 | POST /ops/routing-policy/canary | route, ops host | ops/index | | Class-H relay to AP `canaryRoutingPolicy`. Fields policy_id, version, installation_ids, cohort_name |
| ABO-ROUTE-062 | POST /ops/routing-policy/promote | route, ops host | ops/index | | Class-H relay to AP `promoteRoutingPolicy`. Fields policy_id, version |
| ABO-ROUTE-063 | POST /ops/routing-policy/rollback | route, ops host | ops/index | | Class-H relay to AP `rollbackRoutingPolicy`. Fields policy_id, version |
| ABO-ROUTE-064 | POST /ops/kill-switches | route, ops host | ops/index | | Class-H relay to AP `armKillSwitch`. Fields scope, target |
| ABO-ROUTE-065 | POST /ops/kill-switches/disarm | route, ops host | ops/index | | Class-H relay to AP `disarmKillSwitch`. Fields scope, target. Switch state never written locally |
| ABO-ROUTE-066 | POST /ops/cohorts/activate | route, ops host | ops/index | | Class-H relay to AP `activateCohort`. Fields capability_id, capability_version, installation_ids, cohort_name |
| ABO-ROUTE-067 | POST /ops/cohorts/promote | route, ops host | ops/index | | Class-H relay to AP `promoteCohort`. Fields capability_id, capability_version, cohort_name |
| ABO-ROUTE-068 | POST /ops/capabilities/deprecate | route, ops host | ops/index | | Class-H relay to AP `deprecateCapability`. Fields capability_id, capability_version, successor_id |
| ABO-ROUTE-069 | POST /ops/capabilities/retire | route, ops host | ops/index | | Class-H relay to AP `retireCapability`. Fields capability_id, capability_version |
| ABO-ROUTE-070 | POST /ops/token-contracts/begin-rotation | route, ops host | ops/index | | Class-H relay to AP `beginTokenContractRotation`. No forwarded fields |
| ABO-ROUTE-071 | POST /ops/token-contracts/retire | route, ops host | ops/index | | Class-H relay to AP `retireTokenContract`. Field ver |
| ABO-ROUTE-072 | GET /ops/support-lookup?reference= | route, ops host | ops/index | | Access relay to AP `supportLookup` with `access_jwt` and `reference` (fresh action id each call) |
| ABO-ROUTE-073 | any other /ops/* path or method | route fallthrough | ops/index | | After Access: empty 404. Includes `GET /ops/` with trailing slash |

Cross-cutting fetch behaviours (routing layer).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ROUTE-080 | Recovery fence 503 | fetch gate | worker, recovery-fence | | Any request while fence active: 503 plain text `abo_recovery_in_progress` |
| ABO-ROUTE-081 | Signing-key gate refresh on fetch | fetch side effect | worker | | If signing_key_gate row 1 is missing, a fetch calls refreshSigningKeyCheck (errors swallowed) |
| ABO-ROUTE-082 | Host and cross-host rejection | fetch gate | worker | | Unknown host, billing host with /ops/ path, ops host with /v1/ path, or path outside the accepted prefixes: empty 404 |
| ABO-ROUTE-083 | Ops contract-version refusal | fetch gate | worker | | Ops version failure returns 400 with the normal refusal body plus `reload: true` |

---

## 2. D1 tables and columns (ABO-D1)

One row per table, every column listed in final order after all 25 migrations (migration number that created or changed it in the Notes). D1 binding `DB`. Migrations are in `abo/migrations` 0001 to 0025.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-D1-001 | offer | D1 table | migrations 0001 | | Columns: offer_id (PK), code (unique), contract_version. Append-only (triggers) |
| ABO-D1-002 | offer_version | D1 table | migrations 0001 | | Columns: offer_id, version, plan_id, plan_version, term_unit, term_count, price_minor, currency, allowance_credits, grace_days, grace_cap_rule, copy, terms_version, published_by, assertion_sha256, contract_version. PK (offer_id, version). Append-only |
| ABO-D1-003 | offer_event | D1 table | migrations 0001 | | Columns: offer_id, kind, version, actor, at, contract_version. PK (offer_id, kind, version, at). Append-only. Kinds seen: published, retired, reinstated (historical alias of published) |
| ABO-D1-004 | terms_version | D1 table | migrations 0001 | | Columns: terms_version, locale, text_r2_key, text_sha256, published_by, contract_version. PK (terms_version, locale). Append-only |
| ABO-D1-005 | billing_contact | D1 table | migrations 0001, 0012 | | Columns: org_id, version, client_request_id, name, email, phone, contact_sha256, created_by_sub, contract_version, erased_at, erased_by, erasure_generation (0012, default 0). PK (org_id, version); unique (org_id, client_request_id). NOT append-only: erase updates it |
| ABO-D1-006 | fact_log | D1 table | migrations 0001, 0009 | | Columns: fact_seq (autoincrement PK), table, key, row_sha256, created_at, row_json (0009). The ledger source: every immutable fact is written here and exported to R2 |
| ABO-D1-007 | fact_export | D1 table | migrations 0001 | | Columns: fact_seq (PK), exported_at. Marks facts already exported to R2 |
| ABO-D1-008 | token_use | D1 table | migrations 0001; also created at request time | | Columns: jti (PK), org_id, hits. Billing-token hit counter, limit 60 per jti |
| ABO-D1-009 | alert | D1 table | migrations 0001 | | Columns: alert_key (PK), code, active, unsent, last_sent_at, next_send_at, detail_id |
| ABO-D1-010 | checkout | D1 table | migrations 0002, 0011, 0020 | | Columns: checkout_id (PK), reference, org_id, created_by_sub, billing_token_jti, client_request_id, offer_id, offer_version, plan_id, plan_version, term_unit, term_count, allowance_credits, grace_days, grace_cap_rule, list_price_minor, charged_price_minor, adjustment_id, currency, terms_version, billing_contact_version, billing_contact_sha256, opened_with_coverage_through, coverage_source, provider_id, initiator, expires_at, contract_version, created_at (0011), coverage_starts (0011), projected_start (0011), created_at_provenance (0020: recorded, fact_log, opened_event, legacy_unknown, expiry_inferred). Unique (org_id, client_request_id). Append-only |
| ABO-D1-011 | checkout_event | D1 table | migrations 0002 | | Columns: checkout_id, kind, source, ref, actor, at, contract_version. PK (checkout_id, kind, at). Append-only |
| ABO-D1-012 | checkout_status | D1 table | migrations 0002 | | Columns: checkout_id (PK), state, last_event_at. Mutable status projection |
| ABO-D1-013 | paymob_intention | D1 table | migrations 0002 | | Columns: checkout_id (PK), intention_id, order_id, client_secret, special_reference, expires_at. Written by the Paymob adapter on intention creation; the ledger exporter refuses a fact of this table |
| ABO-D1-014 | coverage_view | D1 table | migrations 0002 | | Columns: org_id (PK), binding_epoch, clinic_seq, snapshot. Local copy of AP coverage snapshots, ordered upsert |
| ABO-D1-015 | feed_cursor | D1 table | migrations 0002 | | Columns: id (PK, row 1 seeded 0), feed_seq. Position in the AP coverage feed |
| ABO-D1-016 | notification | D1 table | migrations 0003, 0013 | | Columns: notification_id (PK), provider_id, channel, hmac_valid, body_r2_key, body_sha256, dedupe_key, checkout_id, disposition, adapter_version, provider_txn_id (0013). Append-only |
| ABO-D1-017 | inquiry_result | D1 table | migrations 0003 | | Columns: inquiry_id (PK), subject, normalized_state, cumulative_reversed_minor, raw_r2_key, raw_sha256, at, adapter_version. Append-only |
| ABO-D1-018 | payment | D1 table | migrations 0003 | | Columns: payment_id (PK), reference, org_id, checkout_id, provider_id, amount_minor, currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id, offer_version, billing_contact_version, classification, disposition, mismatch_detail, evidence_sha256. Append-only |
| ABO-D1-019 | work | D1 table | migrations 0003, 0010 | | Columns: work_id (PK), kind, subject_id, dedupe_key (unique), state, attempts, next_attempt_at, lease_until, last_error, opened_at, lease_token (0010, unique when not null). Index (state, next_attempt_at) |
| ABO-D1-020 | paymob_txn | D1 table | migrations 0003 | | Columns: txn_id (PK), order_id, checkout_id, payment_id, parent_txn_id, last_state_key. Provider transaction to checkout/payment binding |
| ABO-D1-021 | paymob_state_seen | D1 table | migrations 0003 | | Columns: dedupe_key (PK), source, first_seen_at |
| ABO-D1-022 | notify_rate | D1 table | migrations 0003 | | Columns: ip (PK), window_start_ms, hits. Per-IP limit 60 per minute window on /notify/paymob |
| ABO-D1-023 | grant_request | D1 table | migrations 0004 | | Columns: grant_id (PK), org_id, source_kind, source_ref, envelope, envelope_sha256, assertion. Append-only. source_kind values written: paid, complimentary, transfer |
| ABO-D1-024 | grant_outcome_legacy | D1 table | migrations 0004, 0014 | | Original grant_outcome table renamed in 0014. Columns: grant_id (PK), result, abo_kid, abo_signature, receipt, term_ids, at. Append-only triggers kept |
| ABO-D1-025 | grant_outcome (view) | D1 view | migrations 0014 | | Columns: grant_id, result, abo_kid, abo_signature, receipt, term_ids, at. One effective row per grant: first terminal event, otherwise the latest non-terminal event of grant_outcome_event |
| ABO-D1-026 | grant_outcome_event | D1 table | migrations 0014 | | Columns: outcome_seq (autoincrement PK), attempt_id (unique), grant_id, result, code, terminal (0 or 1), abo_kid, abo_signature, receipt, term_ids, at. Append-only. Index (grant_id, outcome_seq) |
| ABO-D1-027 | signing_key_gate | D1 table | migrations 0004 | | Columns: id (PK, row 1), paused, checked_at. Pauses grant/void signing when the ABO key is not active on the AP |
| ABO-D1-028 | reversal | D1 table | migrations 0004, 0005 | | Columns: reversal_id (PK), payment_id, reference, amount_minor, kind, is_full, source (0005), cumulative_reversed_minor (0005), detected_via (0005), recorded_by (0005), evidence_sha256 (0005), effect (0005), dedupe_key (0005, unique). Append-only |
| ABO-D1-029 | reversal_outcome | D1 table | migrations 0005 | | Columns: reversal_id (PK), result, receipt, at. Append-only |
| ABO-D1-030 | finding | D1 table | migrations 0005 | | Columns: finding_id (PK), kind, subject, detail, detected_at. Append-only |
| ABO-D1-031 | inquiry_spend | D1 table | migrations 0005 | | Columns: minute_key (PK, UTC minute), spent. Provider inquiry budget, reservation allowed while spent below 2 |
| ABO-D1-032 | operator_action | D1 table | migrations 0006 | | Columns: action_id (PK), actor_email, access_jti, action, subject, params_sha256, assertion_sha256, result. Append-only audit of console actions |
| ABO-D1-033 | assertion_used | D1 table | migrations 0007 | | Columns: challenge_sha256 (PK). One-time use of operator assertions. Append-only |
| ABO-D1-034 | payment_release | D1 table | migrations 0007 | | Columns: payment_id (PK), operator_action_id, at. Append-only |
| ABO-D1-035 | finding_resolution | D1 table | migrations 0008 | | Columns: finding_id (PK), resolved_by, note, at. Append-only |
| ABO-D1-036 | payout_import | D1 table | migrations 0008, 0023 | | Columns: import_id (PK), provider_id, file_sha256, r2_key, imported_by, period. Unique (provider_id, file_sha256) from 0023. Index on period. Append-only |
| ABO-D1-037 | payout_line | D1 table | migrations 0008 | | Columns: import_id, line_no, kind, gross_minor, fee_minor, net_minor, settled_at, payment_id. PK (import_id, line_no). Append-only |
| ABO-D1-038 | scheduled_job_run | D1 table | migrations 0009 | | Columns: job (PK), last_run_at. Legacy; migration 0021 says unused; no code touches it |
| ABO-D1-039 | seen_operator_credential | D1 table | migrations 0009 | | Columns: credential_id, public_key_cose, alg. PK of all three. Credentials the ABO has seen registered (used by the hourly watch for AL-22) |
| ABO-D1-040 | channel_version_seen | D1 table | migrations 0009 | | Columns: channel, contract_version, received, unsupported. PK (channel, contract_version). Counts contract versions seen on aboClinic and aboConsole |
| ABO-D1-041 | paymob_intention_attempt | D1 table | migrations 0011, 0019 | | Columns: checkout_id, attempt_no, state (pending, created, abandoned_unconfirmed), lease_token, lease_until, special_reference (unique), intention_id, order_id, client_secret, expires_at, started_at, finished_at. PK (checkout_id, attempt_no). Rebuilt in 0019 so client_secret may be null in state created. Index on order_id |
| ABO-D1-042 | paymob_intention_attempt_event | D1 table | migrations 0011 | | Columns: event_key (PK), checkout_id, attempt_no, state, lease_token, lease_until, special_reference, intention_id, order_id, client_secret, expires_at, started_at, finished_at, event_at. Append-only immutable history of attempt states |
| ABO-D1-043 | accepted_operator_command | D1 table | migrations 0012, 0017 | | Columns: challenge_sha256 (PK), command_id (unique), method, args_json, operation_json, assertion_json, actor_email, target, contract_version, action_id (unique), command_kind (local_hp, relay), stage, due_at, lease_until, lease_token, result_json, created_at, updated_at, recovery_generation (0017), recovery_scope_max_version (0017), recovery_guard (0017, default 0). Mutable durable command state |
| ABO-D1-044 | org_erasure_fence | D1 table | migrations 0012 | | Columns: org_id (PK), generation (>= 0), updated_at |
| ABO-D1-045 | raw_evidence_registry | D1 table | migrations 0012 | | Columns: evidence_id (PK), org_id, checkout_id, evidence_kind, generation, r2_key (unique), raw_sha256, state (quarantined, claimed, retained, delete_pending, deleted), created_at, updated_at |
| ABO-D1-046 | raw_evidence_cleanup_outbox | D1 table | migrations 0012 | | Columns: r2_key (PK), evidence_id, reason, state (open, done), attempts, next_attempt_at, last_error, created_at, updated_at |
| ABO-D1-047 | reversal_request | D1 table | migrations 0015 | | Columns: reversal_id (PK), grant_id, reason, evidence_sha256, partial (must be 0), contract_version, canonical_body, body_sha256, created_at. Append-only |
| ABO-D1-048 | rebuild_checkpoint | D1 table | migrations 0016 | | Columns: id (PK, must be 1), last_fact_seq, payload_sha256, updated_at |
| ABO-D1-049 | rebuild_due_checkpoint | D1 table | migrations 0016 | | Columns: id (PK, must be 1), last_fact_seq, updated_at |
| ABO-D1-050 | command_recovery_fact | D1 table | migrations 0017 | | Columns: fact_id (PK), command_id, fact_kind (command_intent, relay_reserved, platform_result, local_result, erasure_ack), payload_json (max 32768), payload_sha256 (64 chars), created_at. Unique (command_id, fact_kind, payload_sha256). Append-only |
| ABO-D1-051 | abo_recovery_fence | D1 table | migrations 0018 | | Columns: id (PK, must be 1), active, generation, owner_token, lease_until, updated_at. Lease 5 minutes |
| ABO-D1-052 | rebuild_inquiry_attempt | D1 table | migrations 0020 | | Columns: attempt_id (PK), checkout_id, payment_id, provider_txn_ref, outcome (confirmed, already_recorded, deferred, unavailable, discovery_unavailable, unbound), decision, inquiry_id, evidence_sha256, observed_at, adapter_version. Append-only |
| ABO-D1-053 | scheduled_job_state | D1 table | migrations 0021 | | Columns: job (PK), last_started_at, last_succeeded_at, last_succeeded_period, last_error_at, last_error_code, next_attempt_at, consecutive_failures, lease_token, lease_until |
| ABO-D1-054 | housekeeping_r2_cursor | D1 table | migrations 0021 | | Columns: scope (PK), cutoff_day, r2_cursor. Resume position for the hmac-invalid R2 sweep |
| ABO-D1-055 | finding_identity | D1 table | migrations 0022 | | Columns: kind, subject, finding_id. PK (kind, subject); finding_id unique. One canonical finding per kind and subject |
| ABO-D1-056 | payout_line_reversal | D1 table | migrations 0024 | | Columns: import_id, line_no, reversal_ref, amount_minor (> 0). PK (import_id, line_no), FK to payout_line. Index on reversal_ref. Append-only |
| ABO-D1-057 | reversal_provider_identity | D1 table | migrations 0025 | | Columns: reversal_id (PK, FK reversal), reversal_ref. Index on reversal_ref. Append-only |
| ABO-D1-058 | payout_reversal_link | D1 table | migrations 0025 | | Columns: import_id, line_no, reversal_id. PK (import_id, line_no). FKs to payout_line_reversal and reversal. Index on reversal_id. Append-only |
| ABO-D1-059 | harness_test_clock | D1 table (test-only, not in migrations) | clock | | Columns inferred from queries: id (row "default"), now_iso. Read only when env TEST_CLOCK = "1" |
| ABO-D1-060 | harness_issuer_pin | D1 table (test-only, not in migrations) | clinic-api/auth | | Columns inferred from queries: kid, public_key. Read only when TEST_CLOCK = "1"; overrides ISSUER_KEYS when it has rows |

Triggers, views and indexes (supplementary rows).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-D1X-001 | append-only triggers (before update and before delete, RAISE ABORT 'append_only') | D1 triggers | migrations | | On: offer, offer_version, offer_event, terms_version, checkout (update trigger dropped and recreated in 0011 and 0020), checkout_event, notification, inquiry_result, payment, grant_request, grant_outcome_legacy, reversal, reversal_outcome, finding, operator_action, assertion_used, payment_release, finding_resolution, payout_import, payout_line, paymob_intention_attempt_event, grant_outcome_event, reversal_request, command_recovery_fact, rebuild_inquiry_attempt, payout_line_reversal, reversal_provider_identity, payout_reversal_link |
| ABO-D1X-002 | accepted_operator_command_validate_erasure_fence | D1 trigger | migrations 0017 | | Before insert on accepted_operator_command for local_hp erase_contact with recovery_guard 1: aborts with `erasure_fence_mismatch` or `erasure_scope_changed` |
| ABO-D1X-003 | trigger error strings | error text | migrations | | `append_only`, `erasure_fence_mismatch`, `erasure_scope_changed` |
| ABO-D1X-004 | ledger fact tables (fact_log.table values replayed by rebuild) | list | rebuild | | offer, terms_version, offer_version, offer_event, checkout, checkout_event, notification, inquiry_result, payment, payment_release, grant_request, grant_outcome, grant_outcome_event, reversal, operator_action, command_recovery_fact, finding, finding_resolution, payout_import, payout_line, payout_line_reversal, reversal_provider_identity, payout_reversal_link, paymob_intention_attempt_event, rebuild_inquiry_attempt, reversal_request |
| ABO-D1X-005 | indexes | D1 indexes | migrations | | billing_contact_org_version, token_use_org_id, checkout_org_id, work_state_next_attempt, work_lease_token_unique, reversal_payment_id, reversal_dedupe_key, payout_import_period, payout_import_provider_file, payout_line_payment_id, payout_line_reversal_ref, payout_reversal_link_reversal, reversal_provider_identity_ref, paymob_intention_attempt_order_id, paymob_intention_attempt_event_attempt, accepted_operator_command_due, raw_evidence_registry_org_state, raw_evidence_cleanup_due, grant_outcome_event_grant_order, command_recovery_fact_command, finding_identity_finding_id |

---

## 3. Enumerated state and status values (ABO-STATE)

Values that appear in the code for text columns. Derived from code only; not exhaustive where the value comes from the AP.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-STATE-001 | checkout_status.state | state values | clinic-api, work, ops, rebuild | | open, open_failed, paid, paid_late, expired, cancelled, disputed (rebuild only) |
| ABO-STATE-002 | checkout_event.kind | event kinds | clinic-api, work, ops | | opened, open_failed, paid, cancelled, attempt_declined; source values system, operator |
| ABO-STATE-003 | clinic-facing shown_state | display states | clinic-api/checkouts | | Waiting (open), Abandoned (open_failed, expired, cancelled), Paid, Active (paid with grant applied or already_applied). paid/paid_late shows Paid or Active |
| ABO-STATE-004 | paymob_intention_attempt.state | state values | clinic-api, provider | | pending, created, abandoned_unconfirmed. Pending lease 2 minutes; checkout expiry 30 minutes |
| ABO-STATE-005 | work.kind | work kinds | notify, work, ops | | confirm, grant, reverse, sweep_checkout, sweep_payment, transfer_step (read by the runner, no insert found; see doubts) |
| ABO-STATE-006 | work.state | state values | work, ops | | open, done, parked |
| ABO-STATE-007 | work.dedupe_key patterns | key patterns | work, notify, ops | | confirm:{notification_id}, confirm:manual:{action_id}:{transaction_id}, grant:{payment_id}, reverse:{reversal_id}, sweep_checkout:{checkout_id}:{offset_ms}, sweep_checkout:{checkout_id}:post:{offset_ms}, sweep_payment:notification:{notification_id}, sweep_payment:hourly:{payment_id}:{hour}, sweep_payment:sixhour:{payment_id}:{bucket}, sweep_payment:daily:{payment_id}:{day} |
| ABO-STATE-008 | work.last_error values | error markers | work | | inquiry_deferred, inquiry_retry, inquiry_disagrees, inquiry_evidence_unavailable, no_notification, receipt_unverified, request_unrecoverable, missing_payment_fact, invalid_stored_grant_request, conflict, rejected, blocked_missing_original_authorization, plus a wait-until marker parsed by the AL-04 logic |
| ABO-STATE-009 | notification.channel and disposition | enum | notify | | channel processed or response; disposition enqueued, duplicate, unmatched, unparseable |
| ABO-STATE-010 | payment.classification | enum | work/runner | | normal, late (checkout expired or cancelled), likely_duplicate (earlier payment for same org with same coverage-through) |
| ABO-STATE-011 | payment.disposition | enum | work/runner, ops | | grant, withheld_mismatch (amount or currency differs), reversed_before_grant |
| ABO-STATE-012 | reversal.kind / effect / source / detected_via | enum | work/reversal, ops | | kind refund, void, chargeback, unknown; effect tombstone, end_current, remove_queued, none, review_partial; source operator or provider; detected_via notification, inquiry, manual |
| ABO-STATE-013 | grant_request.source_kind | enum | work/grant, ops | | paid, complimentary, transfer |
| ABO-STATE-014 | grant_outcome_event.result and code | enum | work/grant | | result applied, already_applied, rejected, conflict (transient is not stored), plus code (for example voided, terminal 1); non-terminal results park the work row |
| ABO-STATE-015 | accepted_operator_command.stage | state values | ops | | accepted, local_applied, platform_succeeded, complete, conflict, awaiting_operator_auth; command_kind local_hp or relay |
| ABO-STATE-016 | command_recovery_fact.fact_kind | enum | records/command-facts | | command_intent, relay_reserved, platform_result, local_result, erasure_ack |
| ABO-STATE-017 | raw_evidence_registry.state and outbox reasons | enum | evidence/raw | | registry: quarantined, claimed, retained, delete_pending, deleted. outbox state open or done; reasons stale_claim, upload_uncertain, tenant_erasure, migration_erased_contact |
| ABO-STATE-018 | payout_line.kind | enum | provider/paymob/adapter | | payment, refund, chargeback, fee, other |
| ABO-STATE-019 | finding.kind values | enum | reconciliation, work, ops, rebuild | | payment_without_grant, grant_without_payment, grant_without_operator_action, transfer_without_authorisation, reversal_not_applied, payout_unmatched, payment_not_in_payout, unrecorded_reversal, callback_without_confirmation, feed_divergence, receipt_mismatch, reversal_kind_conflict, inquiry_disagrees, rebuild_missing_provider_correlation, transfer_recovery_disputed, accepted_transfer_disputed, accepted_command_disputed |
| ABO-STATE-020 | operator_action.action values | enum | ops | | Local HP ops: publish_offer, retire_offer, reinstate_offer, release_payment, manual_chargeback, erase_contact. Relay method names: grant, suspend, resume, deleteInstallation, voidGrant, releaseHeld, listGrantsForVoid, recoverStrandedTerm, registerOperatorCredential, revokeOperatorCredential, registerIssuerKey, retireIssuerKey, revokeIssuerKey, registerServiceKey, revokeServiceKey, publishPlanVersion, retirePlanVersion, setCeilingPolicy, publishRoutingPolicy, canaryRoutingPolicy, promoteRoutingPolicy, rollbackRoutingPolicy, armKillSwitch, disarmKillSwitch, activateCohort, promoteCohort, deprecateCapability, retireCapability, beginTokenContractRotation, retireTokenContract, supportLookup, beginTransfer. Plain text actions: "Retry parked work", "Cancel an open checkout", "Submit a provider transaction id for a checkout with no known transaction", "Import a payout CSV", "Resolve a finding" |
| ABO-STATE-021 | operator_action.result values | enum | ops | | accepted, open, cancelled, submitted, applied, unknown, plus any refusal code, plus AP result strings (ok, applied, already_applied, rejected, conflict, transient) |
| ABO-STATE-022 | scheduled_job_state.job names | job names | worker, scheduler | | minute_processing, reversal_population_six_hour, reversal_population_hourly, hourly_watch, r2_lock_check, reconciliation, reversal_population_daily, digest, housekeeping |
| ABO-STATE-023 | payout CSV rejection reasons | error reasons | provider/paymob/adapter | | field_count, invalid_transaction_id, invalid_kind, invalid_amount, invalid_settled_at, invalid_header, no_rows, mixed_period, invalid_encoding (returned as line_errors with 1-based line_no) |
| ABO-STATE-024 | Paymob provider capabilities | capability set | provider/paymob/adapter | | methods ["card"]; cancel_checkout, refunds, mandates, payouts, pending_notifications all false |

---

## 4. R2 prefixes and object types (ABO-R2) and Durable Objects (ABO-DO)

Bucket binding `R2` (bucket name from `R2_BUCKET_NAME`, one bucket per environment).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-R2-001 | ledger/{fact_seq}.ndjson | R2 object | records/export | | One canonical fact line per object (payload_version 2: fact_seq, table, key, row_sha256, fact_created_at, row). Written by the minute fact_export step; conflicting rewrite throws ledger_object_conflict. Read by rebuild. Bucket lock rule expected on this prefix |
| ABO-R2-002 | ledger-manifest/{high_water}.json | R2 object | records/export | | `{payload_version: 1, exported_through}` high-water marker written after a gap-free export. Read by rebuild |
| ABO-R2-003 | evidence/notification/{notification_id} | R2 object | notify/intake, evidence/raw | | Raw Paymob callback body (POST body or GET query string). Registered in raw_evidence_registry; erased on contact erasure |
| ABO-R2-004 | evidence/inquiry/{inquiry_id} | R2 object | work/runner, evidence/raw | | Raw Paymob inquiry response bodies kept as evidence; registered and erasable like notification evidence |
| ABO-R2-005 | hmac-invalid/{YYYY-MM-DD}/{id} | R2 object | notify/intake, housekeeping | | Diagnostic copy of a rejected callback; body kept only for the first 10 per hour, otherwise empty object; counted for AL-02 (3 in 15 min); swept after 30 days by housekeeping |
| ABO-R2-006 | terms/sha256/{sha256}.txt | R2 object | ops/index | | Terms text stored under its content digest on publish_offer; read by GET /v1/offers (digest verified) |
| ABO-R2-007 | payouts/{file_sha256} | R2 object | ops/index | | Raw payout CSV bytes of an accepted import |
| ABO-R2-008 | terms/en/{n}.txt (fixture style key) | R2 object (fixture/harness only) | records/append | | `loadOffersFixture` writes whatever text_r2_key the fixture gives; test/harness use |
| ABO-R2-009 | R2 bucket lock read | R2 setting read | alert/lock | | The daily job reads the bucket lock rules through the Cloudflare API and wants an enabled Indefinite rule for prefix `ledger/` or all |
| ABO-DO-000 | no Durable Object classes or fields in the ABO | none | wrangler.toml | | The ABO uses D1 and R2 only. All quota/coverage Durable Object state lives in the AP |

---

## 5. Cron schedules and scheduled jobs (ABO-CRON)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-CRON-001 | `* * * * *` (every minute) | cron schedule | worker | | Refresh signing-key gate if missing; run minute processing; retry-only pass of all due scheduled jobs (six_hour, hourly, daily); ping the minute heartbeat |
| ABO-CRON-002 | `0 * * * *` (hourly) | cron schedule | worker | | Always refresh signing-key check; then run hourly jobs |
| ABO-CRON-003 | `0 */6 * * *` (every six hours) | cron schedule | worker | | Run six_hour jobs only |
| ABO-CRON-004 | `0 6 * * *` (daily 06:00 UTC) | cron schedule | worker | | Refresh signing-key gate if missing; run daily jobs; then sendDueAlerts. A daily period runs 06:00 UTC to 06:00 UTC |
| ABO-CRON-010 | minute step export_lag | minute step | worker, alert/index | | markExportLagIfDue: raises/clears alert AL-16:export-lag when oldest unexported fact is over 1 hour old. Runs first and last (listed twice) |
| ABO-CRON-011 | minute step fact_export | minute step | worker, records/export | | exportFacts: pending fact_log rows to R2 ledger/, fact_export marks, manifest |
| ABO-CRON-012 | minute step alert_dispatch | minute step | worker, alert/index | | sendDueAlerts: e-mails active unsent alerts, marks repeats due |
| ABO-CRON-013 | minute step coverage_view | minute step | worker, coverage/view | | refreshCoverageView: pulls AP readCoverageEvents (limit 200 per page) into coverage_view and feed_cursor |
| ABO-CRON-014 | minute step inquiry_budget | minute step | worker, work/inquiry-budget | | runMinuteInquiryBudget: stale-confirm alert AL-01 (over 5 min), materialise sweep schedules, up to 50 each of confirm, grant, sweep, then reverse work, pending notification reversals |
| ABO-CRON-015 | minute step transfer_steps | minute step | worker, ops/index | | runDueTransferSteps: up to 50 due work rows of kind transfer_step |
| ABO-CRON-016 | minute_processing outcome record | scheduled_job_state row | worker, scheduler | | Ungated outcome stamped per minute; failed steps logged as `minute_step_failed`; failed run raises scheduled_job_failed:minute_processing |
| ABO-CRON-020 | job reversal_population_six_hour | scheduled job (six_hour) | worker, work/sweep | | enqueueSixHourReversalPopulation: sweep_payment work rows per payment |
| ABO-CRON-021 | job reversal_population_hourly | scheduled job (hourly) | worker, work/sweep | | enqueueHourlyReversalPopulation |
| ABO-CRON-022 | job hourly_watch | scheduled job (hourly) | worker, watch/hourly | | AL-15 feed health (stale over 5 min), AL-22 issuer-key pin mismatch, AL-22 unannounced operator credential, then sendDueAlerts; fails if any read incomplete |
| ABO-CRON-023 | job r2_lock_check | scheduled job (daily) | worker, alert/lock | | Reads R2 bucket lock via Cloudflare API; raises or clears AL-16:r2-lock; non-success is `failed` |
| ABO-CRON-024 | job reconciliation | scheduled job (daily) | worker, reconciliation/run | | Eleven checks (payment_without_grant ... receipt_mismatch), then AL-10 repair. Also run inline after every payout import |
| ABO-CRON-025 | job reversal_population_daily | scheduled job (daily) | worker, work/sweep | | enqueueDailyReversalPopulation |
| ABO-CRON-026 | job digest | scheduled job (daily) | worker, digest/run | | Raises AL-14 for keys expiring within 30 days, builds and e-mails the digest (subject `digest`), then pings the digest heartbeat only after the send |
| ABO-CRON-027 | job housekeeping | scheduled job (daily) | worker, housekeeping/run | | Drains raw-evidence deletes (100), deletes work rows done and older than 90 days, deletes alert rows last sent over 90 days ago, sweeps hmac-invalid R2 objects older than 30 days (budget 1000 deletes per run, cursor in housekeeping_r2_cursor) |
| ABO-CRON-030 | scheduler claim/lease rules | scheduler mechanics | scheduler/jobs | | Lease 15 min; deferred retry 5 min; failed retry 15 min; period keys six_hour:{n}, hourly:{n}, daily:{date}; retryOnly (minute) claims only attempts with next_attempt_at set; failure raises alert scheduled_job_failed:{job}; error code is the error name capped at 64 chars |
| ABO-CRON-031 | requeueScheduledJob | scheduler function | scheduler/jobs, ops | | Used after payout import when inline reconciliation did not succeed: clears last_succeeded_period so the minute cron re-runs reconciliation; error code import_reconciliation_incomplete |
| ABO-CRON-032 | heartbeat pings | outbound ping | worker | | Minute cron GETs HEARTBEAT_URL_MINUTE (fallback HEARTBEAT_URL); digest success GETs HEARTBEAT_URL_DIGEST (fallback HEARTBEAT_URL); failures ignored |
| ABO-CRON-033 | signing-key check | cron side job | worker, work/grant | | refreshSigningKeyCheck: checks the ABO grant key is active in AP listServiceKeys; writes signing_key_gate (paused 1 and alert AL-23 when not) |
| ABO-CRON-034 | inline (non-cron) background work | background | notify/intake, ops | | POST /notify/paymob runs confirm for the work row then the inquiry budget inside ctx.waitUntil; ops manual actions run their work inline |
| ABO-CRON-035 | recovery fence lease | timer | recovery-fence | | Recovery fence lease 5 minutes (acquire, renew, publish) |

---

## 6. Outbound calls (ABO-OUT)

To the AP (service binding `PLATFORM`, entrypoint `VendorEntrypoint`; every call carries `contract_version` of the vendorEntrypoint channel).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OUT-001 | PLATFORM.grant | AP call | work/grant, ops, rebuild | | Paid grant: `contract_version, abo_kid, abo_signature, envelope_b64`; complimentary: `access_jwt, envelope, operation, assertion?, signer_credential_id, ceiling_override_operation?`. Results applied, already_applied, rejected, conflict, transient |
| ABO-OUT-002 | PLATFORM.getCoverage | AP call | clinic-api/billing-reads, clinic-api/checkouts, ops, reconciliation, work/reversal, work/sweep | | Args `org_id`; returns snapshot. Failure falls back to coverage_view |
| ABO-OUT-003 | PLATFORM.readCoverageEvents | AP call | coverage/view, reconciliation, rebuild | | Args `after`, `limit` (200). Coverage feed pull |
| ABO-OUT-004 | PLATFORM.voidForReversal | AP call | work/reversal, rebuild | | Args grant_id, reversal_id, reason, evidence_sha256, partial, abo_kid, abo_signature |
| ABO-OUT-005 | PLATFORM.listGrants | AP call | ops, reconciliation, rebuild | | Grants known to the AP |
| ABO-OUT-006 | PLATFORM.listServiceKeys | AP call | work/grant, digest, ops | | Service key registry |
| ABO-OUT-007 | PLATFORM.listIssuerKeys | AP call | digest, watch, ops | | Issuer key registry |
| ABO-OUT-008 | PLATFORM.listOperatorCredentials | AP call | ops, watch | | Operator credential registry (also the source for assertion verification) |
| ABO-OUT-009 | PLATFORM.feedConsumerHealth | AP call | watch, digest | | `last_pull_at` of the coverage feed consumer |
| ABO-OUT-010 | PLATFORM.recordOperatorAction | AP call | ops | | Audit mirror after every console action (jwt, action, subject, action id) |
| ABO-OUT-011 | PLATFORM.beginTransfer / transferOut / transferIn | AP calls | ops | | Installation transfer; receipts verified with PLATFORM_PUBLIC_KEYS |
| ABO-OUT-012 | PLATFORM.releaseHeld / voidGrant / listGrantsForVoid / recoverStrandedTerm | AP calls | ops | | Grant and term operations |
| ABO-OUT-013 | PLATFORM.suspend / resume / deleteInstallation | AP calls | ops | | Installation lifecycle |
| ABO-OUT-014 | PLATFORM.countLedgerRows / readLaunchState / inspectCoverage | AP calls | ops | | Read-only operator views |
| ABO-OUT-015 | PLATFORM.registerOperatorCredential / revokeOperatorCredential | AP calls | ops | | Credential lifecycle |
| ABO-OUT-016 | PLATFORM.registerIssuerKey / retireIssuerKey / revokeIssuerKey | AP calls | ops | | Issuer key lifecycle |
| ABO-OUT-017 | PLATFORM.registerServiceKey / revokeServiceKey | AP calls | ops | | Service key lifecycle |
| ABO-OUT-018 | PLATFORM.publishPlanVersion / retirePlanVersion / setCeilingPolicy | AP calls | ops | | Plan and ceiling configuration |
| ABO-OUT-019 | PLATFORM.publishRoutingPolicy / canaryRoutingPolicy / promoteRoutingPolicy / rollbackRoutingPolicy | AP calls | ops | | Routing policy lifecycle |
| ABO-OUT-020 | PLATFORM.armKillSwitch / disarmKillSwitch | AP calls | ops | | Kill switch |
| ABO-OUT-021 | PLATFORM.activateCohort / promoteCohort / deprecateCapability / retireCapability | AP calls | ops | | Capability and cohort lifecycle |
| ABO-OUT-022 | PLATFORM.beginTokenContractRotation / retireTokenContract | AP calls | ops | | Token contract lifecycle |
| ABO-OUT-023 | PLATFORM.supportLookup | AP call | ops | | Support lookup relay |

To Paymob (HTTPS origin `PAYMOB_BASE_URL`, abort after 10 s, 500 ms under TEST_CLOCK; test stub binding `PAYMOB_STUB`).

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OUT-030 | POST {PAYMOB_BASE_URL}/v1/intention/ | Paymob call | provider/paymob/client | | Header `Authorization: Token {PAYMOB_SECRET_KEY}`. Creates the payment intention (amount, billing data from the contact, special reference `{reference}-{attempt_no}`, notification and return URLs). Result: intention id, order id, client_secret |
| ABO-OUT-031 | Paymob unified checkout redirect URL | URL built | provider/paymob/adapter | | Built from PAYMOB_BASE_URL, PAYMOB_PUBLIC_KEY and the intention client_secret; returned to the clinic as `redirect_url` (no call) |
| ABO-OUT-032 | POST {PAYMOB_BASE_URL}/api/auth/tokens | Paymob call | provider/paymob/client | | Body `{api_key: PAYMOB_API_KEY}`; returns inquiry auth token |
| ABO-OUT-033 | POST {PAYMOB_BASE_URL}/api/ecommerce/orders/transaction_inquiry | Paymob call | provider/paymob/client | | Bearer auth token; body `{order_id}`; inquiry by order |
| ABO-OUT-034 | GET {PAYMOB_BASE_URL}/api/acceptance/transactions/{txn_id} | Paymob call | provider/paymob/client | | Bearer auth token; inquiry by transaction (also for parent transaction on refunds) |
| ABO-OUT-035 | Paymob inquiry outcomes | outcome kinds | provider/paymob/client | | ok, timeout, rate_limit (429), unauthorized (401), error. Reservation from inquiry_spend: max 2 inquiries per UTC minute |
| ABO-OUT-036 | Paymob HMAC check on callbacks | verification | provider/paymob/adapter | | HMAC with PAYMOB_HMAC_SECRET over the ordered fields amount_cents, created_at, currency, error_occured, has_parent_transaction, id, integration_id, is_3d_secure, is_auth, is_capture, is_refunded, is_standalone_payment, is_voided, order.id, owner, pending, source_data.pan, source_data.sub_type, source_data.type, success |

To other systems.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OUT-040 | GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs | Cloudflare Access call | ops/index | | Fetches Access signing keys per ops request (or `ACCESS_CERTS_JSON` override) |
| ABO-OUT-041 | GET https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/r2/buckets/{R2_BUCKET_NAME}/lock | Cloudflare API call | alert/lock | | Bearer `R2_LOCK_READ_TOKEN` |
| ABO-OUT-042 | SEND_EMAIL.send to ALERT_EMAIL_TO | e-mail | alert/index, digest/run | | From and to are both ALERT_EMAIL_TO. Subject is the alert code or `digest`; alert text `{code} {detail_id}` |
| ABO-OUT-043 | GET HEARTBEAT_URL / HEARTBEAT_URL_MINUTE / HEARTBEAT_URL_DIGEST | heartbeat ping | worker | | See ABO-CRON-032 |
| ABO-OUT-044 | Supabase | none | whole ABO | | The ABO makes no Supabase call and holds no Supabase secret |
| ABO-OUT-045 | Inbound billing-token verification | inbound check | clinic-api/auth | | Not outbound: Ed25519 verification with the issuer public keys pinned in `ISSUER_KEYS` (and `harness_issuer_pin` under TEST_CLOCK) |

---

## 7. Error codes (ABO-ERR)

HTTP error body shape (clinic and ops): `{code, message (= code), contract_version, ...extras}`, header `Abo-Contract-Version`.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ERR-001 | unauthenticated (401) | error code | clinic-api/auth, ops | | Missing/invalid billing bearer, unknown kid, bad signature, wrong audience/version/lifetime; on ops: missing or invalid Access JWT |
| ABO-ERR-002 | forbidden_role (403) | error code | clinic-api/auth | | Token otherwise valid but role is not administrator |
| ABO-ERR-003 | rate_limited (429) | error code | clinic-api/rate, clinic-api/checkouts | | 60 hits per billing token jti, or the 10-checkouts-per-org-per-hour limit on POST /v1/checkouts |
| ABO-ERR-004 | invalid_request (422 clinic, 400/422 ops) | error code | clinic-api, ops | | Bad JSON/fields, bad cursor, bad phone, payout import line errors (422 with `line_errors`), bad payout list limit/cursor (422), missing note/transaction_id (400) |
| ABO-ERR-005 | not_found (404) | error code | clinic-api, ops | | No contact, checkout not owned, nothing displayable, unknown lookup, parked/open precondition failed; also JSON 404 for GET /v1/checkouts without open=1 |
| ABO-ERR-006 | idempotency_conflict (409) | error code | clinic-api | | Same client_request_id with different contact content, or different offer/version/terms |
| ABO-ERR-007 | billing_contact_required (409) | error code | clinic-api/checkouts | | No usable (non-erased) billing contact |
| ABO-ERR-008 | terms_not_accepted (409) | error code | clinic-api/checkouts | | terms_version is not the current maximum |
| ABO-ERR-009 | offer_unavailable (409) | error code | clinic-api/checkouts | | Offer not sellable or version not the current sellable one; extra `current_version` |
| ABO-ERR-010 | provider_unavailable (503) | error code | clinic-api/checkouts | | Paymob intention not obtained, checkout expired/not open, attempt not created; extra `checkout_id` |
| ABO-ERR-011 | contract_version_unsupported (400) | error code | clinic-api/version | | Missing or unacceptable `Abo-Contract-Version`; extra `accepted_versions`; ops variant adds `reload: true` |
| ABO-ERR-020 | assertion_invalid (400) | error code | ops | | Malformed/bad operation, wrong op, wrong contract_version, params not bound to route subject, unsigned relay body, invalid copy/price/terms |
| ABO-ERR-021 | assertion_required (400) | error code | ops | | HP-local body without `assertion` |
| ABO-ERR-022 | actor_email_mismatch (400) | error code | ops | | Operation actor differs from the Access e-mail |
| ABO-ERR-023 | assertion_expired (400) | error code | ops | | issued_at older/newer than 5 minutes |
| ABO-ERR-024 | assertion_used (400) | error code | ops | | Challenge already in assertion_used |
| ABO-ERR-025 | credential_not_active (400) | error code | ops | | No active operator credential verifies the assertion |
| ABO-ERR-026 | conflict (409; HP refusals 400) | error code | ops | | Duplicate relay id with different content, retry/cancel not possible, accepted command mismatch, complimentary envelope not matching org/grant id |
| ABO-ERR-027 | recovery_evidence_required (409) | error code | ops | | Accepted command or erasure/transfer lacks original immutable evidence |
| ABO-ERR-028 | payment_fully_reversed (409) | error code | ops | | Release refused because payment already fully reversed |
| ABO-ERR-029 | payment_not_withheld (400) | error code | ops | | Release only allowed for disposition withheld_mismatch |
| ABO-ERR-030 | reversal_exists (400) | error code | ops | | Manual chargeback refused, reversal for that dedupe key already recorded |
| ABO-ERR-031 | allocation_conflict (400) | error code | ops | | Publish could not allocate offer/terms version numbers after retries |
| ABO-ERR-032 | transient (503) | error code | ops | | AP read failed or cached relay result unreadable |
| ABO-ERR-033 | platform_unavailable (503) | error code | ops | | Complimentary grant receipt could not be verified or stored |
| ABO-ERR-034 | internal_error (500) | error code | ops | | Provider adapter missing, payout list database failure |
| ABO-ERR-035 | coverage_unknown (404) | error code | ops | | Clinic dossier when AP coverage read is not ok and gives no code (AP code is passed through when present) |
| ABO-ERR-036 | HP refusal results (HTTP 400) | refusal codes | ops | | refuseHpAction returns the result string (including not_found, conflict) as the code with HTTP 400 and records it in operator_action.result |
| ABO-ERR-037 | AP relay envelope | pass-through | ops | | Relays answer HTTP 200 `{contract_version, result, code?, detail?, receipt?}`; result from the AP (ok, applied, already_applied, rejected, conflict, transient) |
| ABO-ERR-038 | call_outcome_unknown | recorded result | ops | | Recorded in command_recovery_fact when a transferOut/transferIn call throws |
| ABO-ERR-039 | blocked_missing_original_authorization / blocked_missing_transfer_correlation | recovery stop codes | ops | | Transfer recovery stops; work parked, findings transfer_recovery_disputed / accepted_transfer_disputed |
| ABO-ERR-040 | abo_recovery_in_progress (503 text) | plain text | worker, recovery-fence | | Whole worker during rebuild |
| ABO-ERR-041 | /notify/paymob status codes | bare statuses | notify/intake | | 400 (not UTF-8 or unreadable), 413 (over 1 MiB), 429 (per-IP), 401 (bad HMAC), 500 (storage or provider missing), 200 (accepted, unparseable, unmatched) |
| ABO-ERR-042 | thrown work errors | internal codes | work | | lease_lost, grant_request_conflict, grant_request_persist_failed, payment_identity_conflict, payment_confirmation_withheld_mismatch, payment_confirmation_original_order_unbound, payment_confirmation_identity_conflict, provider_missing, reconciliation_incomplete |
| ABO-ERR-043 | thrown ledger/export/rebuild errors | internal codes | records/export, rebuild | | ledger_object_conflict, ledger_manifest_conflict, ledger_manifest_incomplete, ledger_fact_sequence_gap, ledger_fact_hash_conflict, ledger_fact_missing_canonical_row, ledger_command_fact_invalid, ledger_adapter_secret_requires_historical_stop; rebuild: ledger_sequence_gap, ledger_hash_mismatch, ledger_business_row_conflict, ledger_table_unregistered, ledger_column_unregistered, ledger_identity_*, ledger_checkpoint_gap, ledger_checkpoint_ahead_of_manifest, ledger_manifest_*, ledger_object_*, ledger_payload_invalid, checkout_timestamp_*, legacy_failed_checkout_timestamp_unrecoverable, rebuild_*_command_fact_invalid, rebuild_*_command_conflict, rebuild_erasure_fact_invalid, rebuild_due_checkpoint_ahead_of_ledger, erasure_fence_not_restored |
| ABO-ERR-044 | thrown recovery/command-fact errors | internal codes | recovery-fence, records/command-facts, ops | | abo_recovery_in_progress, abo_recovery_already_owned, abo_recovery_ownership_lost, command_recovery_fact_too_large, command_recovery_fact_lineage_invalid, command_recovery_fact_invalid, command_recovery_fact_filter_invalid, command_recovery_fact_corrupt, erase_contact_scope_empty, "accepted operator command lease is held" |
| ABO-ERR-045 | thrown startup/config errors | internal codes | provider/paymob/client, clinic-api/offers | | `PAYMOB_BASE_URL must be an HTTPS origin`, `current terms_version en not found`, `R2 object missing at {key}`, `terms_hash_mismatch terms_version={n} key={key}` |
| ABO-ERR-046 | minute and job failure log events | log events | worker, scheduler, reconciliation | | `minute_step_failed`, `scheduled_job_failed`, `reconciliation_check_failed` (console.error JSON with bounded fields) |

---

## 8. Notice codes and alert codes (ABO-NOTICE, ABO-ALERT)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-NOTICE-001 | duplicate_payment | clinic notice | clinic-api/billing-reads | | In GET /v1/subscription `notices[]` when any payment of the org has classification likely_duplicate |
| ABO-NOTICE-002 | late_payment_honoured | clinic notice | clinic-api/billing-reads | | Any payment classified late |
| ABO-NOTICE-003 | payment_withheld | clinic notice | clinic-api/billing-reads | | Any payment with disposition withheld_mismatch |
| ABO-NOTICE-004 | reversal_recorded | clinic notice | clinic-api/billing-reads | | Any reversal on a payment of the org |
| ABO-NOTICE-005 | terms_held | clinic notice | clinic-api/billing-reads | | Coverage snapshot `held_count` greater than 0 |
| ABO-NOTICE-006 | subscription_ref | field | clinic-api/billing-reads | | `AIC-` style reference derived from org id |
| ABO-NOTICE-007 | payment classification values on /v1/payments | values | clinic-api/billing-reads | | normal, late, likely_duplicate |
| ABO-ALERT-001 | AL-01 | operator alert | work/runner | | Confirm work open more than 5 minutes; key AL-01:{work_id}; repeats hourly |
| ABO-ALERT-002 | AL-02 | operator alert | notify/intake | | 3 or more invalid-HMAC callbacks in 15 minutes; key AL-02:hmac-invalid; repeats hourly |
| ABO-ALERT-003 | AL-03 | operator alert | work/runner, work/sweep | | Provider inquiry discovery unavailable, or payment without a valid-HMAC notification; keys AL-03:discovery:{checkout_id}, AL-03:{payment_id}; no repeat |
| ABO-ALERT-004 | AL-04 | operator alert | work/grant | | Grant work waiting past threshold; key AL-04:{work_id}; repeats hourly |
| ABO-ALERT-005 | AL-05 | operator alert | notify/intake, work/runner | | Unmatched or unbound callback/inquiry; keys AL-05:unmatched:{body_sha256}, AL-05:unbound:{checkout_id}; no repeat |
| ABO-ALERT-006 | AL-06 | operator alert | work/reversal, ops | | Reversal recorded or reversal kind conflict; keys AL-06:{reversal_id}, AL-06:kind:{reversal_id}; no repeat |
| ABO-ALERT-007 | AL-07 | operator alert | work/grant, work/reversal, ops | | Grant or void receipt unverified / rejected / request unrecoverable; keys AL-07:{work_id}, AL-07:request:{reversal_id}, AL-07:{source_ref}; repeats hourly |
| ABO-ALERT-008 | AL-08 | operator alert | work/runner | | Late payment; key AL-08:{checkout_id}; no repeat |
| ABO-ALERT-009 | AL-09 | operator alert | work/runner | | Likely-duplicate payment; key AL-09:{checkout_id}; no repeat |
| ABO-ALERT-010 | AL-10 | operator alert | reconciliation | | Open finding; key AL-10:{finding_id}; repeats daily until the finding is resolved |
| ABO-ALERT-011 | AL-14 | operator alert | digest | | Issuer or service key expires within 30 days; key AL-14:{kid}; repeats daily |
| ABO-ALERT-012 | AL-15 | operator alert | watch/hourly | | Coverage feed consumer health stale (over 5 minutes), unknown or unreadable; key AL-15:feed; repeats hourly |
| ABO-ALERT-013 | AL-16 | operator alert | alert/index, alert/lock | | Export lag (AL-16:export-lag, oldest unexported fact over 1 hour) and R2 bucket lock missing (AL-16:r2-lock); repeats daily |
| ABO-ALERT-014 | AL-22 | operator alert | watch/hourly | | Pinned issuer key differs from AP (AL-22:issuer:{kid}) or operator credential not announced (AL-22:credential:{id}); repeats hourly |
| ABO-ALERT-015 | AL-23 | operator alert | work/grant, notify/intake | | ABO signing key missing/inactive on AP (AL-23:{kid} or AL-23:missing), or unparseable Paymob notification (AL-23:notification-parse); repeats hourly |
| ABO-ALERT-016 | scheduled_job_failed | operator alert | scheduler/jobs | | Key scheduled_job_failed:{job}; repeats daily; cleared on next success |
| ABO-ALERT-017 | offer_malformed | operator alert | clinic-api/offers, billing-reads | | Key offer_malformed:{offer_id}:{version}; no repeat |
| ABO-ALERT-018 | alert delivery rules | mechanics | alert/index | | Alert row fields: active, unsent, last_sent_at, next_send_at; e-mail subject = code; repeat intervals 1 hour or 1 day by code; alerts also sent at the end of the daily cron and inside the hourly watch |

---

## 9. Environment variables, secrets and bindings (ABO-ENV)

Declared in `wrangler.toml` for environments development, staging and production (worker names `abo-development`, `abo-staging`, `abo-production`; `workers_dev` false; `preview_urls` false; observability on; `compatibility_date` 2026-05-03). Values in the repo are placeholders.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ENV-001 | BILLING_HOST | var | wrangler, worker | | Billing hostname; also used to build notify and return URLs given to Paymob |
| ABO-ENV-002 | OPS_HOST | var | wrangler, worker, ops | | Console hostname; also the WebAuthn rp_id and origin `https://{OPS_HOST}` |
| ABO-ENV-003 | HEARTBEAT_URL | var | wrangler, worker | | Fallback heartbeat URL |
| ABO-ENV-004 | HEARTBEAT_URL_MINUTE | optional var | worker | | Not in wrangler.toml; minute-stream heartbeat |
| ABO-ENV-005 | HEARTBEAT_URL_DIGEST | optional var | worker | | Not in wrangler.toml; digest-stream heartbeat |
| ABO-ENV-006 | ALERT_EMAIL_TO | var | wrangler, alert | | Address for alerts and the digest (both from and to); also the SEND_EMAIL destination_address |
| ABO-ENV-007 | ISSUER_ID | var | wrangler, clinic-api/auth | | Expected issuer of billing tokens |
| ABO-ENV-008 | ISSUER_KEYS | var (JSON array of {kid, public_key}) | wrangler, clinic-api/auth, ops | | Pinned Supabase billing-token issuer public keys |
| ABO-ENV-009 | CLOUDFLARE_ACCOUNT_ID | var | wrangler, alert/lock | | For the R2 lock API call |
| ABO-ENV-010 | R2_BUCKET_NAME | var | wrangler, alert/lock | | Bucket whose lock is checked |
| ABO-ENV-011 | R2_LOCK_READ_TOKEN | secret | worker, alert | | Not in wrangler.toml; Cloudflare API read token for the lock check |
| ABO-ENV-012 | PAYMOB_BASE_URL | var | wrangler, provider | | HTTPS origin of Paymob |
| ABO-ENV-013 | PAYMOB_SECRET_KEY | secret (placeholder in wrangler) | wrangler, provider | | Intention creation (Token auth) |
| ABO-ENV-014 | PAYMOB_PUBLIC_KEY | var (placeholder in wrangler) | wrangler, provider | | Part of the unified checkout URL |
| ABO-ENV-015 | PAYMOB_CARD_INTEGRATION_ID | var | wrangler, provider | | Integer card integration id placed in the intention |
| ABO-ENV-016 | PAYMOB_HMAC_SECRET | secret (placeholder in wrangler) | wrangler, provider | | Callback HMAC verification |
| ABO-ENV-017 | PAYMOB_API_KEY | secret (placeholder in wrangler) | wrangler, provider | | Exchanged for the inquiry auth token |
| ABO-ENV-018 | PAYMOB_ALLOW_LOCAL_HTTP | optional var | provider | | "1" lets the Paymob URL be non-HTTPS (local test) |
| ABO-ENV-019 | PAYMOB_STUB | optional service binding | provider | | Fetcher used instead of public fetch (tests) |
| ABO-ENV-020 | ABO_GRANT_KEY | secret (JSON {kid, pkcs8}; placeholder in wrangler) | wrangler, work/grant, work/reversal, ops | | ABO Ed25519 signing key for grants and void requests; kid exposed in launch-state |
| ABO-ENV-021 | PLATFORM_PUBLIC_KEYS | var (JSON array of {kid, public_key}) | wrangler, work, ops, records | | AP receipt-signing public keys pinned by the ABO |
| ABO-ENV-022 | ACCESS_TEAM_DOMAIN | var | worker, ops | | Not in wrangler.toml; Cloudflare Access team domain |
| ABO-ENV-023 | ACCESS_AUD | var | worker, ops | | Not in wrangler.toml; Access application audience |
| ABO-ENV-024 | ACCESS_CERTS_JSON | optional var | ops | | Local Access key override |
| ABO-ENV-025 | TEST_CLOCK | optional var | clock, many | | "1" switches to the D1 harness clock and issuer pins |
| ABO-ENV-030 | DB | D1 binding | wrangler | | database names abo-development, abo-staging, abo-production |
| ABO-ENV-031 | R2 | R2 binding | wrangler | | buckets abo-development, abo-staging, abo-production |
| ABO-ENV-032 | PLATFORM | service binding | wrangler | | service ai-platform-gateway-{environment}, entrypoint VendorEntrypoint |
| ABO-ENV-033 | SEND_EMAIL | send_email binding | wrangler | | destination_address from ALERT_EMAIL_TO |
| ABO-ENV-034 | cron triggers | trigger config | wrangler | | `* * * * *`, `0 * * * *`, `0 */6 * * *`, `0 6 * * *` |
| ABO-ENV-035 | contract channels used | constants | vendor-contracts | | aboClinic, aboConsole, vendorEntrypoint, paymobReturn, paymobAdapter (all currently 1) |
| ABO-ENV-036 | vendor-contracts dependency | package | package.json | | Shared package `../packages/vendor-contracts` |

---

## 10. Console pages and operator actions (ABO-OP)

Console shell at `GET /ops` (single HTML page, bundled script, no static assets). One row per page element and one per operator action. Auth class per action as defined at the top.

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OP-001 | Console shell page "ABO operator console" | console page | ops/browser/shell | | Sections: reload banner (shown on contract-version refusal), operator e-mail label, bootstrap section, "Local approvals" form list, status line. Context from GET /ops/ceremony-context |
| ABO-OP-002 | Bootstrap: first operator credential | console action | ops/browser/shell | | Shown only when the active credential list is empty. Browser creates a passkey (ES256 or EdDSA), posts to POST /ops/operator-credentials. Status text says activation after 24 hours and that bootstrap closes once the registry has a credential |
| ABO-OP-003 | Local approval forms (6) | console forms | ops/browser/ceremony, shell | | publish_offer (fields Offer ID, Price minor units, Terms text, Display name en, Summary en), retire_offer, reinstate_offer, release_payment, manual_chargeback, erase_contact (each: one subject field). Button "Approve with passkey"; WebAuthn userVerification required |
| ABO-OP-004 | Ceremony mechanics | console behaviour | ops/browser | | Operation `{op, params, actor_email, issued_at, nonce, contract_version}`; challenge = SHA-256 of canonical JSON; assertion fields alg, authenticator_data, client_data_json, signature; refusals show code; version refusal forces reload; nothing retried automatically |
| ABO-OP-010 | Publish offer | operator action | ops/index | | ABO-ROUTE-035; HP-local; catalogue change |
| ABO-OP-011 | Retire offer | operator action | ops/index | | ABO-ROUTE-036; HP-local |
| ABO-OP-012 | Reinstate offer | operator action | ops/index | | ABO-ROUTE-037; HP-local |
| ABO-OP-013 | Plan versions: publish | operator action | ops/index | | ABO-ROUTE-052; HP-relay to AP |
| ABO-OP-014 | Plan versions: retire | operator action | ops/index | | ABO-ROUTE-054; HP-relay to AP |
| ABO-OP-015 | Ceiling policy set | operator action | ops/index | | ABO-ROUTE-053; HP-relay to AP |
| ABO-OP-016 | Complimentary grant | operator action | ops/index | | ABO-ROUTE-041; HP-relay; optional separate ceiling_override_operation (op `ceiling_override`, params contract_version, access_jwt, envelope without ceiling_override) |
| ABO-OP-017 | Suspend installation | operator action | ops/index | | ABO-ROUTE-042; class-H relay |
| ABO-OP-018 | Resume installation | operator action | ops/index | | ABO-ROUTE-043; class-H relay |
| ABO-OP-019 | Delete installation | operator action | ops/index | | ABO-ROUTE-044; HP-relay |
| ABO-OP-020 | Begin transfer | operator action | ops/index | | ABO-ROUTE-045; HP-relay plus inline transferOut/transferIn and minute transfer steps |
| ABO-OP-021 | Release payment (withheld mismatch) | operator action | ops/index | | ABO-ROUTE-038; HP-local; creates grant work |
| ABO-OP-022 | Manual chargeback | operator action | ops/index | | ABO-ROUTE-039; HP-local; creates reversal and void work |
| ABO-OP-023 | Void grant | operator action | ops/index | | ABO-ROUTE-048; HP-relay |
| ABO-OP-024 | Release held grant | operator action | ops/index | | ABO-ROUTE-049; HP-relay |
| ABO-OP-025 | List grants for void | operator action | ops/index | | ABO-ROUTE-046; access relay (read) |
| ABO-OP-026 | Recover stranded term | operator action | ops/index | | ABO-ROUTE-047; HP-relay |
| ABO-OP-027 | Retry parked work | operator action | ops/index | | ABO-ROUTE-032; Access only |
| ABO-OP-028 | Cancel open checkout | operator action | ops/index | | ABO-ROUTE-033; Access only |
| ABO-OP-029 | Submit provider transaction id | operator action | ops/index | | ABO-ROUTE-034; Access only |
| ABO-OP-030 | Import payout CSV | operator action | ops/index | | ABO-ROUTE-029; Access only; runs reconciliation |
| ABO-OP-031 | Resolve finding | operator action | ops/index | | ABO-ROUTE-030; Access only |
| ABO-OP-032 | Register operator credential | operator action | ops/index | | ABO-ROUTE-050; relay (bootstrap form posts without assertion; later registrations carry operation and assertion) |
| ABO-OP-033 | Revoke operator credential | operator action | ops/index | | ABO-ROUTE-051; HP-relay |
| ABO-OP-034 | Erase contact | operator action | ops/index | | ABO-ROUTE-040; HP-local; erasure fence |
| ABO-OP-035 | Register / revoke / retire issuer key | operator actions | ops/index | | ABO-ROUTE-055, 056, 057; HP-relay |
| ABO-OP-036 | Register / revoke service key | operator actions | ops/index | | ABO-ROUTE-058, 059; HP-relay |
| ABO-OP-037 | Routing policy publish / canary / promote / rollback | operator actions | ops/index | | ABO-ROUTE-060 to 063; class-H relay |
| ABO-OP-038 | Kill switch arm / disarm | operator actions | ops/index | | ABO-ROUTE-064, 065; class-H relay |
| ABO-OP-039 | Cohort activate / promote | operator actions | ops/index | | ABO-ROUTE-066, 067; class-H relay |
| ABO-OP-040 | Capability deprecate / retire | operator actions | ops/index | | ABO-ROUTE-068, 069; class-H relay |
| ABO-OP-041 | Token contract begin rotation / retire | operator actions | ops/index | | ABO-ROUTE-070, 071; class-H relay |
| ABO-OP-042 | Support lookup | operator view | ops/index | | ABO-ROUTE-072; class-H style relay |
| ABO-OP-050 | Operator read views | operator views | ops/index | | Lookup, clinic dossier, parked work, findings, grants, launch-state, payout-imports list, registries (ABO-ROUTE-021 to 028, 031) |
| ABO-OP-051 | Daily digest e-mail content | operator report | digest/run | | Sections: window_start, checkouts_24h, payments_24h_by_classification, grants_by_source_kind, reversals_24h, alerts_sent_24h, grants (grant_id, source_kind, operator, reason, length_days, allowance, adjustment), open_findings, parked_work, open_alerts, scheduled_jobs, backend_last_pull, export_lag_fact_seq, export_lag_alert_active, r2_lock_alert_active, keys_expiring_within_30_days, channel_version_seen |
| ABO-OP-052 | Alert e-mails | operator report | alert/index | | Subject `{code}`, text `{code} {detail_id}`, from and to ALERT_EMAIL_TO |
| ABO-OP-053 | Rebuild script | operator command | scripts/rebuild-abo | | `npm run rebuild -- [--env name] <provider txn refs>`; runs rebuildAbo (ledger replay, gap re-inquiry, grant comparison, reconciliation) through wrangler getPlatformProxy with remote bindings |
| ABO-OP-054 | Time Travel restore / D1 rebuild runbook | operator procedure | REBUILD.md (non-code file in area) | | Procedure document next to the code; the code behaviour is in rebuild.ts and recovery-fence.ts |

---

## 11. Scripts and package commands (ABO-SCRIPT)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-SCRIPT-001 | npm run dev | command | package.json | | wrangler dev --env development |
| ABO-SCRIPT-002 | npm run deploy / check / types | commands | package.json | | wrangler deploy, wrangler check, wrangler types |
| ABO-SCRIPT-003 | npm run rebuild | command | package.json, scripts/rebuild-abo | | See ABO-OP-053 |
| ABO-SCRIPT-004 | scripts/check-import-boundary.mjs | build check | scripts | | Only provider/paymob/adapter imports the Paymob client; adapter stays inside provider/ |
| ABO-SCRIPT-005 | scripts/build-platform-for-hxw.mjs | test-harness build | scripts | | Bundles the AP worker for the cross-worker harness (test only) |
| ABO-SCRIPT-006 | run_campaigns.py, campaigns/*.json, vitest configs, fixtures/offers.json | test tooling | abo root | | Test campaign tooling and fixture (not for published docs) |
