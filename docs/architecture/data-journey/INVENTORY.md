# INVENTORY

Merged from traces/inventory-*.md (Phase 0). Source area is for convenience only and is not published. Assigned group follows PLAN 16.6 (keyword assignment by the coordinator; refine per group at trace time).

## ABO-ROUTE (71)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ROUTE-001 | GET /v1/offers | route, billing host | worker, clinic-api/offers | G03 | Billing token. Lists sellable offers: latest offer_event of kind published/reinstated per offer, newest sellable version, copy, plus current English terms text read from R2 (digest checked). Malformed stored offer is skipped and raises alert offer_malformed. 200 `{contract_version, offers[]}` |
| ABO-ROUTE-002 | GET /v1/subscription | route, billing host | worker, clinic-api/billing-reads | G07 | Billing token. Calls AP getCoverage for the caller's org, falls back to local coverage_view. Returns `{contract_version, subscription_ref, snapshot, notices[]}` |
| ABO-ROUTE-003 | GET /v1/payments | route, billing host | worker, clinic-api/billing-reads | G07 | Billing token. Optional query `cursor` (a payment reference of the same org). Page size 20, ordered by paid_at then reference. Returns `{payments[], next_cursor, has_more}`; each payment carries reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification, reversals[]. Bad cursor: 422 invalid_request |
| ABO-ROUTE-004 | GET /v1/billing-contact | route, billing host | worker, clinic-api/billing-contact | G04 | Billing token. Latest billing_contact version of the caller's org; 404 not_found when none |
| ABO-ROUTE-005 | PUT /v1/billing-contact | route, billing host | worker, clinic-api/billing-contact | G04 | Billing token. Body `client_request_id, name, email, phone` (phone E.164). Idempotent per (org, client_request_id): same hash replays, different hash gives 409 idempotency_conflict. Appends a new version row |
| ABO-ROUTE-006 | POST /v1/checkouts | route, billing host | worker, clinic-api/checkouts | G04 | Billing token. Body `client_request_id, offer_id, offer_version, terms_version`. Creates checkout, status, opened event, first Paymob intention attempt, calls Paymob, returns 201 `{checkout_id, reference, redirect_url, expires_at, starts, projected_start?}`. After a 201 the worker schedules the sweep work rows |
| ABO-ROUTE-007 | GET /v1/checkouts?open=1 | route, billing host | worker, clinic-api/checkouts | G05 | Billing token. Lists the org's checkouts whose status is open, paid or paid_late as read objects. Without `open=1` the same path answers 404 not_found (JSON) |
| ABO-ROUTE-008 | GET /v1/checkouts/{checkout_id} | route, billing host | worker, clinic-api/checkouts | G05 | Billing token. One checkout read object (reference, shown_state, offer summary, payment_reference null, term_ref null, updated_at). 404 not_found if other org or state has no display |
| ABO-ROUTE-009 | any other method/path under /v1/ | route fallthrough | worker | G03 | After gate, auth and rate limit: empty 404 (also wrong method on /v1/billing-contact, /v1/offers etc.) |
| ABO-ROUTE-010 | POST /notify/paymob | route, billing host | worker, notify/intake | G05 | No bearer token; authenticity is the Paymob HMAC (`PAYMOB_HMAC_SECRET`). Body size cap 1,048,576 bytes (413), must be UTF-8 (400), per-IP rate 60 per minute window (429), unparseable (200 + notification row + AL-23), bad HMAC (401 + hmac-invalid R2 object, AL-02 after 3 in 15 min), unmatched (200 + AL-05), good (200 after confirm attempt). Empty bodies on all |
| ABO-ROUTE-011 | GET /notify/paymob | route, billing host | worker, notify/intake | G05 | Paymob processed-callback via query string (query used as the body). Bad HMAC 401; unparseable 200; matched checkout schedules a confirm work row; always empty body |
| ABO-ROUTE-012 | GET /return/paymob (prefix match) | route, billing host | worker, notify/intake | G05 | Browser return page after payment. Path match is `startsWith /return/paymob`. Schedules confirm work for every checkout whose status is open; answers 200 HTML "Please return to your clinic application." The return URL given to Paymob carries `?v=` (paymobReturn channel version) |
| ABO-ROUTE-013 | any other /notify/ or /return/ path or method | route fallthrough | worker | G05 | Empty 404 |
| ABO-ROUTE-020 | GET /ops | route, ops host | worker, ops/browser/shell | G19 | Console HTML shell, Access only, no version header needed, `cache-control: no-store`. Exactly `/ops` (not `/ops/`) |
| ABO-ROUTE-021 | GET /ops/ceremony-context | route, ops host | ops/index | G19 | Access + console version. Returns `{contract_version, actor_email, rp_id (= OPS_HOST), origin, credentials[{credential_id, alg}]}` (active operator credentials from AP listOperatorCredentials) |
| ABO-ROUTE-022 | GET /ops/lookup?q= | route, ops host | ops/index | G19 | Access. Resolves a query (org UUID, CK- checkout ref, PAY- payment ref, GR- grant ref, AIC- subscription ref, or billing e-mail) to `org_id`; 404 not_found |
| ABO-ROUTE-023 | GET /ops/clinics/{org_id} | route, ops host | ops/index | G19 | Access. Clinic dossier: AP getCoverage + inspectCoverage, then D1 checkouts (with events), payments, reversals, grant_requests with outcome and receipt, operator_actions, findings, active alerts. Error from AP coverage: 404 with AP code or coverage_unknown |
| ABO-ROUTE-024 | GET /ops/parked | route, ops host | ops/index | G22 | Access. Work rows in state parked |
| ABO-ROUTE-025 | GET /ops/findings | route, ops host | ops/index | G22 | Access. All finding rows |
| ABO-ROUTE-026 | GET /ops/grants | route, ops host | ops/index | G21 | Access. AP listGrants grouped by source_kind and by operator_credential_id |
| ABO-ROUTE-027 | GET /ops/launch-state | route, ops host | ops/index | G19 | Access. Read-only launch check: ABO signing kid, issuer keys pinned, AL-23 active, term and grant counts (AP countLedgerRows), channel versions (ABO and AP readLaunchState), platform signing key pinned, key self-check. AP failure: 503 transient |
| ABO-ROUTE-028 | GET /ops/payout-imports | route, ops host | ops/index | G22 | Access. Query `limit` (1 to 200, default 50) and `cursor` (`period|import_id`). Newest period first |
| ABO-ROUTE-029 | POST /ops/payout-imports | route, ops host | ops/index | G22 | Access. Raw CSV bytes as body. Validated whole file (provider payoutLines), stored in R2 under payouts/, import and lines in D1, then reconciliation is run inline. 422 invalid_request with `line_errors[]` |
| ABO-ROUTE-030 | POST /ops/findings/{finding_id}/resolve | route, ops host | ops/index | G22 | Access. Body `{note}`. Inserts finding_resolution, deactivates alert AL-10:{finding_id}. 404 not_found, 400 invalid_request |
| ABO-ROUTE-031 | GET /ops/registries | route, ops host | ops/index | G22 | Access. AP lists: issuer_keys, service_keys, operator_credentials |
| ABO-ROUTE-032 | POST /ops/parked/{work_id}/retry | route, ops host | ops/index | G22 | Access. Only parked work of kind grant or reverse. Returns work to open. 404 not_found, 409 conflict |
| ABO-ROUTE-033 | POST /ops/checkouts/{checkout_id}/cancel | route, ops host | ops/index | G22 | Access. Only when status is open. Sets status cancelled, writes cancelled event. 404 not_found, 409 conflict |
| ABO-ROUTE-034 | POST /ops/checkouts/{checkout_id}/transaction-id | route, ops host | ops/index | G22 | Access. Body `{transaction_id}` (digits, 1 to 32). Only when no paymob_txn known for the checkout. Opens a manual confirm work row and runs it. Returns `{action_id, work_id}`. 400 invalid_request, 404 not_found, 409 conflict |
| ABO-ROUTE-035 | POST /ops/offers/{offer_id}/publish | route, ops host | ops/index | G19 | HP-local (op publish_offer). Signed params exactly `offer_id, price_minor, terms_text, copy`. Writes terms text to R2, new terms_version, offer_version, offer_event. 400 on every refusal |
| ABO-ROUTE-036 | POST /ops/offers/{offer_id}/retire | route, ops host | ops/index | G19 | HP-local (op retire_offer). Params exactly `offer_id`. Appends offer_event retired |
| ABO-ROUTE-037 | POST /ops/offers/{offer_id}/reinstate | route, ops host | ops/index | G19 | HP-local (op reinstate_offer). Params exactly `offer_id`. Appends offer_event published for the latest published version |
| ABO-ROUTE-038 | POST /ops/payments/{payment_id}/release | route, ops host | ops/index | G21 | HP-local (op release_payment, durable accepted command). Only for disposition withheld_mismatch and not fully reversed. Inserts payment_release and a grant work row |
| ABO-ROUTE-039 | POST /ops/payments/{payment_id}/chargeback | route, ops host | ops/index | G21 | HP-local (op manual_chargeback, durable accepted command). Inserts operator reversal (kind chargeback, full), reversal_request, reverse work row; runs it |
| ABO-ROUTE-040 | POST /ops/orgs/{org_id}/erase-contact | route, ops host | ops/index | G18 | HP-local (op erase_contact, durable accepted command). Blanks billing_contact name/email/phone, bumps erasure fence, deletes raw evidence R2 bodies |
| ABO-ROUTE-041 | POST /ops/orgs/{org_id}/complimentary-grant | route, ops host | ops/index | G20 | HP-relay to AP `grant`. Body `action_id, envelope, operation, signer_credential_id, assertion?, ceiling_override_operation?`. Stores grant_request (source_kind complimentary) and outcome event |
| ABO-ROUTE-042 | POST /ops/orgs/{org_id}/suspend | route, ops host | ops/index | G20 | Class-H relay to AP `suspend`. Body `action_id, reason` |
| ABO-ROUTE-043 | POST /ops/orgs/{org_id}/resume | route, ops host | ops/index | G20 | Class-H relay to AP `resume`. Body `action_id, reason` |
| ABO-ROUTE-044 | POST /ops/orgs/{org_id}/delete-installation | route, ops host | ops/index | G20 | HP-relay to AP `deleteInstallation`. Body `action_id, reason, operation, assertion, signer_credential_id` |
| ABO-ROUTE-045 | POST /ops/orgs/{org_id}/begin-transfer | route, ops host | ops/index | G20 | HP-relay to AP `beginTransfer`, then inline `transferOut` and `transferIn`. Body `action_id, from_installation_id, reason (1 to 256 chars), operation (op beginTransfer, nonce = action_id), assertion, signer_credential_id`. Verified locally before relay |
| ABO-ROUTE-046 | POST /ops/grants/list-for-void | route, ops host | ops/index | G21 | Access relay to AP `listGrantsForVoid`. Body `action_id, credential_id, window` |
| ABO-ROUTE-047 | POST /ops/coverage/recover-stranded | route, ops host | ops/index | G21 | HP-relay to AP `recoverStrandedTerm`. Body includes `action_id, org_id, installation_id, binding_epoch, target_term_id, source_grant_id, expected_clinic_seq, reason, evidence_sha256, signer_credential_id, operation, assertion` |
| ABO-ROUTE-048 | POST /ops/grants/{grant_id}/void | route, ops host | ops/index | G21 | HP-relay to AP `voidGrant`. Body `action_id, reason, operation, assertion, signer_credential_id` |
| ABO-ROUTE-049 | POST /ops/grants/{grant_id}/release-held | route, ops host | ops/index | G21 | HP-relay to AP `releaseHeld`. Same body shape as void |
| ABO-ROUTE-050 | POST /ops/operator-credentials | route, ops host | ops/index | G22 | Relay to AP `registerOperatorCredential`. Body `action_id, credential_id, attestation, operation?, assertion?, signer_credential_id?`. Remembers the credential in seen_operator_credential on ok. Used by the console bootstrap |
| ABO-ROUTE-051 | POST /ops/operator-credentials/{credential_id}/revoke | route, ops host | ops/index | G22 | HP-relay to AP `revokeOperatorCredential` |
| ABO-ROUTE-052 | POST /ops/plan-versions | route, ops host | ops/index | G19 | HP-relay to AP `publishPlanVersion`. Fields plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit, max_allowance_per_month |
| ABO-ROUTE-053 | POST /ops/ceiling-policy | route, ops host | ops/index | G19 | HP-relay to AP `setCeilingPolicy`. Fields per_grant_max_days, per_grant_max_allowance_months, window_days, window_max_days, window_max_allowance_months, max_paid_grace_days, paid_cap_rule |
| ABO-ROUTE-054 | POST /ops/plan-versions/retire | route, ops host | ops/index | G19 | HP-relay to AP `retirePlanVersion`. Fields plan_id, version |
| ABO-ROUTE-055 | POST /ops/issuer-keys | route, ops host | ops/index | G17 | HP-relay to AP `registerIssuerKey`. Fields kid, public_key, not_before, not_after |
| ABO-ROUTE-056 | POST /ops/issuer-keys/{kid}/revoke | route, ops host | ops/index | G17 | HP-relay to AP `revokeIssuerKey` |
| ABO-ROUTE-057 | POST /ops/issuer-keys/{kid}/retire | route, ops host | ops/index | G17 | HP-relay to AP `retireIssuerKey` |
| ABO-ROUTE-058 | POST /ops/service-keys | route, ops host | ops/index | G17 | HP-relay to AP `registerServiceKey`. Fields kid, public_key, not_before, not_after |
| ABO-ROUTE-059 | POST /ops/service-keys/{kid}/revoke | route, ops host | ops/index | G17 | HP-relay to AP `revokeServiceKey` |
| ABO-ROUTE-060 | POST /ops/routing-policy | route, ops host | ops/index | G24 | Class-H relay to AP `publishRoutingPolicy`. Field `document` |
| ABO-ROUTE-061 | POST /ops/routing-policy/canary | route, ops host | ops/index | G24 | Class-H relay to AP `canaryRoutingPolicy`. Fields policy_id, version, installation_ids, cohort_name |
| ABO-ROUTE-062 | POST /ops/routing-policy/promote | route, ops host | ops/index | G24 | Class-H relay to AP `promoteRoutingPolicy`. Fields policy_id, version |
| ABO-ROUTE-063 | POST /ops/routing-policy/rollback | route, ops host | ops/index | G24 | Class-H relay to AP `rollbackRoutingPolicy`. Fields policy_id, version |
| ABO-ROUTE-064 | POST /ops/kill-switches | route, ops host | ops/index | G23 | Class-H relay to AP `armKillSwitch`. Fields scope, target |
| ABO-ROUTE-065 | POST /ops/kill-switches/disarm | route, ops host | ops/index | G23 | Class-H relay to AP `disarmKillSwitch`. Fields scope, target. Switch state never written locally |
| ABO-ROUTE-066 | POST /ops/cohorts/activate | route, ops host | ops/index | G23 | Class-H relay to AP `activateCohort`. Fields capability_id, capability_version, installation_ids, cohort_name |
| ABO-ROUTE-067 | POST /ops/cohorts/promote | route, ops host | ops/index | G23 | Class-H relay to AP `promoteCohort`. Fields capability_id, capability_version, cohort_name |
| ABO-ROUTE-068 | POST /ops/capabilities/deprecate | route, ops host | ops/index | G23 | Class-H relay to AP `deprecateCapability`. Fields capability_id, capability_version, successor_id |
| ABO-ROUTE-069 | POST /ops/capabilities/retire | route, ops host | ops/index | G23 | Class-H relay to AP `retireCapability`. Fields capability_id, capability_version |
| ABO-ROUTE-070 | POST /ops/token-contracts/begin-rotation | route, ops host | ops/index | G17 | Class-H relay to AP `beginTokenContractRotation`. No forwarded fields |
| ABO-ROUTE-071 | POST /ops/token-contracts/retire | route, ops host | ops/index | G19 | Class-H relay to AP `retireTokenContract`. Field ver |
| ABO-ROUTE-072 | GET /ops/support-lookup?reference= | route, ops host | ops/index | G19 | Access relay to AP `supportLookup` with `access_jwt` and `reference` (fresh action id each call) |
| ABO-ROUTE-073 | any other /ops/* path or method | route fallthrough | ops/index | G19 | After Access: empty 404. Includes `GET /ops/` with trailing slash |
| ABO-ROUTE-080 | Recovery fence 503 | fetch gate | worker, recovery-fence | G18 | Any request while fence active: 503 plain text `abo_recovery_in_progress` |
| ABO-ROUTE-081 | Signing-key gate refresh on fetch | fetch side effect | worker | G17 | If signing_key_gate row 1 is missing, a fetch calls refreshSigningKeyCheck (errors swallowed) |
| ABO-ROUTE-082 | Host and cross-host rejection | fetch gate | worker | G19 | Unknown host, billing host with /ops/ path, ops host with /v1/ path, or path outside the accepted prefixes: empty 404 |
| ABO-ROUTE-083 | Ops contract-version refusal | fetch gate | worker | G03 | Ops version failure returns 400 with the normal refusal body plus `reload: true` |

## ABO-D1 (60)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-D1-001 | offer | D1 table | migrations 0001 | G03 | Columns: offer_id (PK), code (unique), contract_version. Append-only (triggers) |
| ABO-D1-002 | offer_version | D1 table | migrations 0001 | G19 | Columns: offer_id, version, plan_id, plan_version, term_unit, term_count, price_minor, currency, allowance_credits, grace_days, grace_cap_rule, copy, terms_version, published_by, assertion_sha256, contract_version. PK (offer_id, version). Append-only |
| ABO-D1-003 | offer_event | D1 table | migrations 0001 | G19 | Columns: offer_id, kind, version, actor, at, contract_version. PK (offer_id, kind, version, at). Append-only. Kinds seen: published, retired, reinstated (historical alias of published) |
| ABO-D1-004 | terms_version | D1 table | migrations 0001 | G07 | Columns: terms_version, locale, text_r2_key, text_sha256, published_by, contract_version. PK (terms_version, locale). Append-only |
| ABO-D1-005 | billing_contact | D1 table | migrations 0001, 0012 | G18 | Columns: org_id, version, client_request_id, name, email, phone, contact_sha256, created_by_sub, contract_version, erased_at, erased_by, erasure_generation (0012, default 0). PK (org_id, version); unique (org_id, client_request_id). NOT append-only: erase updates it |
| ABO-D1-006 | fact_log | D1 table | migrations 0001, 0009 | G07 | Columns: fact_seq (autoincrement PK), table, key, row_sha256, created_at, row_json (0009). The ledger source: every immutable fact is written here and exported to R2 |
| ABO-D1-007 | fact_export | D1 table | migrations 0001 | G07 | Columns: fact_seq (PK), exported_at. Marks facts already exported to R2 |
| ABO-D1-008 | token_use | D1 table | migrations 0001; also created at request time | G03 | Columns: jti (PK), org_id, hits. Billing-token hit counter, limit 60 per jti |
| ABO-D1-009 | alert | D1 table | migrations 0001 | G15 | Columns: alert_key (PK), code, active, unsent, last_sent_at, next_send_at, detail_id |
| ABO-D1-010 | checkout | D1 table | migrations 0002, 0011, 0020 | G19 | Columns: checkout_id (PK), reference, org_id, created_by_sub, billing_token_jti, client_request_id, offer_id, offer_version, plan_id, plan_version, term_unit, term_count, allowance_credits, grace_days, grace_cap_rule, list_price_minor, charged_price_minor, adjustment_id, currency, terms_version, billing_contact_version, billing_contact_sha256, opened_with_coverage_through, coverage_source, provider_id, initiator, expires_at, contract_version, created_at (0011), coverage_starts (0011), projected_start (0011), created_at_provenance (0020: recorded, fact_log, opened_event, legacy_unknown, expiry_inferred). Unique (org_id, client_request_id). Append-only |
| ABO-D1-011 | checkout_event | D1 table | migrations 0002 | G05 | Columns: checkout_id, kind, source, ref, actor, at, contract_version. PK (checkout_id, kind, at). Append-only |
| ABO-D1-012 | checkout_status | D1 table | migrations 0002 | G05 | Columns: checkout_id (PK), state, last_event_at. Mutable status projection |
| ABO-D1-013 | paymob_intention | D1 table | migrations 0002 | G04 | Columns: checkout_id (PK), intention_id, order_id, client_secret, special_reference, expires_at. Written by the Paymob adapter on intention creation; the ledger exporter refuses a fact of this table |
| ABO-D1-014 | coverage_view | D1 table | migrations 0002 | G07 | Columns: org_id (PK), binding_epoch, clinic_seq, snapshot. Local copy of AP coverage snapshots, ordered upsert |
| ABO-D1-015 | feed_cursor | D1 table | migrations 0002 | G07 | Columns: id (PK, row 1 seeded 0), feed_seq. Position in the AP coverage feed |
| ABO-D1-016 | notification | D1 table | migrations 0003, 0013 | G05 | Columns: notification_id (PK), provider_id, channel, hmac_valid, body_r2_key, body_sha256, dedupe_key, checkout_id, disposition, adapter_version, provider_txn_id (0013). Append-only |
| ABO-D1-017 | inquiry_result | D1 table | migrations 0003 | G16 | Columns: inquiry_id (PK), subject, normalized_state, cumulative_reversed_minor, raw_r2_key, raw_sha256, at, adapter_version. Append-only |
| ABO-D1-018 | payment | D1 table | migrations 0003 | G19 | Columns: payment_id (PK), reference, org_id, checkout_id, provider_id, amount_minor, currency, paid_at, confirmed_at, confirmation_inquiry_id, offer_id, offer_version, billing_contact_version, classification, disposition, mismatch_detail, evidence_sha256. Append-only |
| ABO-D1-019 | work | D1 table | migrations 0003, 0010 | G06 | Columns: work_id (PK), kind, subject_id, dedupe_key (unique), state, attempts, next_attempt_at, lease_until, last_error, opened_at, lease_token (0010, unique when not null). Index (state, next_attempt_at) |
| ABO-D1-020 | paymob_txn | D1 table | migrations 0003 | G05 | Columns: txn_id (PK), order_id, checkout_id, payment_id, parent_txn_id, last_state_key. Provider transaction to checkout/payment binding |
| ABO-D1-021 | paymob_state_seen | D1 table | migrations 0003 | G05 | Columns: dedupe_key (PK), source, first_seen_at |
| ABO-D1-022 | notify_rate | D1 table | migrations 0003 | G05 | Columns: ip (PK), window_start_ms, hits. Per-IP limit 60 per minute window on /notify/paymob |
| ABO-D1-023 | grant_request | D1 table | migrations 0004 | G20 | Columns: grant_id (PK), org_id, source_kind, source_ref, envelope, envelope_sha256, assertion. Append-only. source_kind values written: paid, complimentary, transfer |
| ABO-D1-024 | grant_outcome_legacy | D1 table | migrations 0004, 0014 | G06 | Original grant_outcome table renamed in 0014. Columns: grant_id (PK), result, abo_kid, abo_signature, receipt, term_ids, at. Append-only triggers kept |
| ABO-D1-025 | grant_outcome (view) | D1 view | migrations 0014 | G06 | Columns: grant_id, result, abo_kid, abo_signature, receipt, term_ids, at. One effective row per grant: first terminal event, otherwise the latest non-terminal event of grant_outcome_event |
| ABO-D1-026 | grant_outcome_event | D1 table | migrations 0014 | G06 | Columns: outcome_seq (autoincrement PK), attempt_id (unique), grant_id, result, code, terminal (0 or 1), abo_kid, abo_signature, receipt, term_ids, at. Append-only. Index (grant_id, outcome_seq) |
| ABO-D1-027 | signing_key_gate | D1 table | migrations 0004 | G06 | Columns: id (PK, row 1), paused, checked_at. Pauses grant/void signing when the ABO key is not active on the AP |
| ABO-D1-028 | reversal | D1 table | migrations 0004, 0005 | G16 | Columns: reversal_id (PK), payment_id, reference, amount_minor, kind, is_full, source (0005), cumulative_reversed_minor (0005), detected_via (0005), recorded_by (0005), evidence_sha256 (0005), effect (0005), dedupe_key (0005, unique). Append-only |
| ABO-D1-029 | reversal_outcome | D1 table | migrations 0005 | G16 | Columns: reversal_id (PK), result, receipt, at. Append-only |
| ABO-D1-030 | finding | D1 table | migrations 0005 | G22 | Columns: finding_id (PK), kind, subject, detail, detected_at. Append-only |
| ABO-D1-031 | inquiry_spend | D1 table | migrations 0005 | G05 | Columns: minute_key (PK, UTC minute), spent. Provider inquiry budget, reservation allowed while spent below 2 |
| ABO-D1-032 | operator_action | D1 table | migrations 0006 | G19 | Columns: action_id (PK), actor_email, access_jti, action, subject, params_sha256, assertion_sha256, result. Append-only audit of console actions |
| ABO-D1-033 | assertion_used | D1 table | migrations 0007 | G19 | Columns: challenge_sha256 (PK). One-time use of operator assertions. Append-only |
| ABO-D1-034 | payment_release | D1 table | migrations 0007 | G21 | Columns: payment_id (PK), operator_action_id, at. Append-only |
| ABO-D1-035 | finding_resolution | D1 table | migrations 0008 | G22 | Columns: finding_id (PK), resolved_by, note, at. Append-only |
| ABO-D1-036 | payout_import | D1 table | migrations 0008, 0023 | G22 | Columns: import_id (PK), provider_id, file_sha256, r2_key, imported_by, period. Unique (provider_id, file_sha256) from 0023. Index on period. Append-only |
| ABO-D1-037 | payout_line | D1 table | migrations 0008 | G22 | Columns: import_id, line_no, kind, gross_minor, fee_minor, net_minor, settled_at, payment_id. PK (import_id, line_no). Append-only |
| ABO-D1-038 | scheduled_job_run | D1 table | migrations 0009 | G15 | Columns: job (PK), last_run_at. Legacy; migration 0021 says unused; no code touches it |
| ABO-D1-039 | seen_operator_credential | D1 table | migrations 0009 | G17 | Columns: credential_id, public_key_cose, alg. PK of all three. Credentials the ABO has seen registered (used by the hourly watch for AL-22) |
| ABO-D1-040 | channel_version_seen | D1 table | migrations 0009 | G03 | Columns: channel, contract_version, received, unsupported. PK (channel, contract_version). Counts contract versions seen on aboClinic and aboConsole |
| ABO-D1-041 | paymob_intention_attempt | D1 table | migrations 0011, 0019 | G04 | Columns: checkout_id, attempt_no, state (pending, created, abandoned_unconfirmed), lease_token, lease_until, special_reference (unique), intention_id, order_id, client_secret, expires_at, started_at, finished_at. PK (checkout_id, attempt_no). Rebuilt in 0019 so client_secret may be null in state created. Index on order_id |
| ABO-D1-042 | paymob_intention_attempt_event | D1 table | migrations 0011 | G04 | Columns: event_key (PK), checkout_id, attempt_no, state, lease_token, lease_until, special_reference, intention_id, order_id, client_secret, expires_at, started_at, finished_at, event_at. Append-only immutable history of attempt states |
| ABO-D1-043 | accepted_operator_command | D1 table | migrations 0012, 0017 | G19 | Columns: challenge_sha256 (PK), command_id (unique), method, args_json, operation_json, assertion_json, actor_email, target, contract_version, action_id (unique), command_kind (local_hp, relay), stage, due_at, lease_until, lease_token, result_json, created_at, updated_at, recovery_generation (0017), recovery_scope_max_version (0017), recovery_guard (0017, default 0). Mutable durable command state |
| ABO-D1-044 | org_erasure_fence | D1 table | migrations 0012 | G18 | Columns: org_id (PK), generation (>= 0), updated_at |
| ABO-D1-045 | raw_evidence_registry | D1 table | migrations 0012 | G05 | Columns: evidence_id (PK), org_id, checkout_id, evidence_kind, generation, r2_key (unique), raw_sha256, state (quarantined, claimed, retained, delete_pending, deleted), created_at, updated_at |
| ABO-D1-046 | raw_evidence_cleanup_outbox | D1 table | migrations 0012 | G05 | Columns: r2_key (PK), evidence_id, reason, state (open, done), attempts, next_attempt_at, last_error, created_at, updated_at |
| ABO-D1-047 | reversal_request | D1 table | migrations 0015 | G16 | Columns: reversal_id (PK), grant_id, reason, evidence_sha256, partial (must be 0), contract_version, canonical_body, body_sha256, created_at. Append-only |
| ABO-D1-048 | rebuild_checkpoint | D1 table | migrations 0016 | G18 | Columns: id (PK, must be 1), last_fact_seq, payload_sha256, updated_at |
| ABO-D1-049 | rebuild_due_checkpoint | D1 table | migrations 0016 | G18 | Columns: id (PK, must be 1), last_fact_seq, updated_at |
| ABO-D1-050 | command_recovery_fact | D1 table | migrations 0017 | G18 | Columns: fact_id (PK), command_id, fact_kind (command_intent, relay_reserved, platform_result, local_result, erasure_ack), payload_json (max 32768), payload_sha256 (64 chars), created_at. Unique (command_id, fact_kind, payload_sha256). Append-only |
| ABO-D1-051 | abo_recovery_fence | D1 table | migrations 0018 | G18 | Columns: id (PK, must be 1), active, generation, owner_token, lease_until, updated_at. Lease 5 minutes |
| ABO-D1-052 | rebuild_inquiry_attempt | D1 table | migrations 0020 | G18 | Columns: attempt_id (PK), checkout_id, payment_id, provider_txn_ref, outcome (confirmed, already_recorded, deferred, unavailable, discovery_unavailable, unbound), decision, inquiry_id, evidence_sha256, observed_at, adapter_version. Append-only |
| ABO-D1-053 | scheduled_job_state | D1 table | migrations 0021 | G06 | Columns: job (PK), last_started_at, last_succeeded_at, last_succeeded_period, last_error_at, last_error_code, next_attempt_at, consecutive_failures, lease_token, lease_until |
| ABO-D1-054 | housekeeping_r2_cursor | D1 table | migrations 0021 | G20 | Columns: scope (PK), cutoff_day, r2_cursor. Resume position for the hmac-invalid R2 sweep |
| ABO-D1-055 | finding_identity | D1 table | migrations 0022 | G22 | Columns: kind, subject, finding_id. PK (kind, subject); finding_id unique. One canonical finding per kind and subject |
| ABO-D1-056 | payout_line_reversal | D1 table | migrations 0024 | G16 | Columns: import_id, line_no, reversal_ref, amount_minor (> 0). PK (import_id, line_no), FK to payout_line. Index on reversal_ref. Append-only |
| ABO-D1-057 | reversal_provider_identity | D1 table | migrations 0025 | G16 | Columns: reversal_id (PK, FK reversal), reversal_ref. Index on reversal_ref. Append-only |
| ABO-D1-058 | payout_reversal_link | D1 table | migrations 0025 | G16 | Columns: import_id, line_no, reversal_id. PK (import_id, line_no). FKs to payout_line_reversal and reversal. Index on reversal_id. Append-only |
| ABO-D1-059 | harness_test_clock | D1 table (test-only, not in migrations) | clock | G06 | Columns inferred from queries: id (row "default"), now_iso. Read only when env TEST_CLOCK = "1" |
| ABO-D1-060 | harness_issuer_pin | D1 table (test-only, not in migrations) | clinic-api/auth | G17 | Columns inferred from queries: kid, public_key. Read only when TEST_CLOCK = "1"; overrides ISSUER_KEYS when it has rows |

## ABO-D1X (5)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-D1X-001 | append-only triggers (before update and before delete, RAISE ABORT 'append_only') | D1 triggers | migrations | G21 | On: offer, offer_version, offer_event, terms_version, checkout (update trigger dropped and recreated in 0011 and 0020), checkout_event, notification, inquiry_result, payment, grant_request, grant_outcome_legacy, reversal, reversal_outcome, finding, operator_action, assertion_used, payment_release, finding_resolution, payout_import, payout_line, paymob_intention_attempt_event, grant_outcome_event, reversal_request, command_recovery_fact, rebuild_inquiry_attempt, payout_line_reversal, reversal_provider_identity, payout_reversal_link |
| ABO-D1X-002 | accepted_operator_command_validate_erasure_fence | D1 trigger | migrations 0017 | G18 | Before insert on accepted_operator_command for local_hp erase_contact with recovery_guard 1: aborts with `erasure_fence_mismatch` or `erasure_scope_changed` |
| ABO-D1X-003 | trigger error strings | error text | migrations | G18 | `append_only`, `erasure_fence_mismatch`, `erasure_scope_changed` |
| ABO-D1X-004 | ledger fact tables (fact_log.table values replayed by rebuild) | list | rebuild | G21 | offer, terms_version, offer_version, offer_event, checkout, checkout_event, notification, inquiry_result, payment, payment_release, grant_request, grant_outcome, grant_outcome_event, reversal, operator_action, command_recovery_fact, finding, finding_resolution, payout_import, payout_line, payout_line_reversal, reversal_provider_identity, payout_reversal_link, paymob_intention_attempt_event, rebuild_inquiry_attempt, reversal_request |
| ABO-D1X-005 | indexes | D1 indexes | migrations | G16 | billing_contact_org_version, token_use_org_id, checkout_org_id, work_state_next_attempt, work_lease_token_unique, reversal_payment_id, reversal_dedupe_key, payout_import_period, payout_import_provider_file, payout_line_payment_id, payout_line_reversal_ref, payout_reversal_link_reversal, reversal_provider_identity_ref, paymob_intention_attempt_order_id, paymob_intention_attempt_event_attempt, accepted_operator_command_due, raw_evidence_registry_org_state, raw_evidence_cleanup_due, grant_outcome_event_grant_order, command_recovery_fact_command, finding_identity_finding_id |

## ABO-STATE (24)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-STATE-001 | checkout_status.state | state values | clinic-api, work, ops, rebuild | G18 | open, open_failed, paid, paid_late, expired, cancelled, disputed (rebuild only) |
| ABO-STATE-002 | checkout_event.kind | event kinds | clinic-api, work, ops | G05 | opened, open_failed, paid, cancelled, attempt_declined; source values system, operator |
| ABO-STATE-003 | clinic-facing shown_state | display states | clinic-api/checkouts | G06 | Waiting (open), Abandoned (open_failed, expired, cancelled), Paid, Active (paid with grant applied or already_applied). paid/paid_late shows Paid or Active |
| ABO-STATE-004 | paymob_intention_attempt.state | state values | clinic-api, provider | G04 | pending, created, abandoned_unconfirmed. Pending lease 2 minutes; checkout expiry 30 minutes |
| ABO-STATE-005 | work.kind | work kinds | notify, work, ops | G17 | confirm, grant, reverse, sweep_checkout, sweep_payment, transfer_step (read by the runner, no insert found; see doubts) |
| ABO-STATE-006 | work.state | state values | work, ops | G06 | open, done, parked |
| ABO-STATE-007 | work.dedupe_key patterns | key patterns | work, notify, ops | G16 | confirm:{notification_id}, confirm:manual:{action_id}:{transaction_id}, grant:{payment_id}, reverse:{reversal_id}, sweep_checkout:{checkout_id}:{offset_ms}, sweep_checkout:{checkout_id}:post:{offset_ms}, sweep_payment:notification:{notification_id}, sweep_payment:hourly:{payment_id}:{hour}, sweep_payment:sixhour:{payment_id}:{bucket}, sweep_payment:daily:{payment_id}:{day} |
| ABO-STATE-008 | work.last_error values | error markers | work | G05 | inquiry_deferred, inquiry_retry, inquiry_disagrees, inquiry_evidence_unavailable, no_notification, receipt_unverified, request_unrecoverable, missing_payment_fact, invalid_stored_grant_request, conflict, rejected, blocked_missing_original_authorization, plus a wait-until marker parsed by the AL-04 logic |
| ABO-STATE-009 | notification.channel and disposition | enum | notify | G11 | channel processed or response; disposition enqueued, duplicate, unmatched, unparseable |
| ABO-STATE-010 | payment.classification | enum | work/runner | G05 | normal, late (checkout expired or cancelled), likely_duplicate (earlier payment for same org with same coverage-through) |
| ABO-STATE-011 | payment.disposition | enum | work/runner, ops | G16 | grant, withheld_mismatch (amount or currency differs), reversed_before_grant |
| ABO-STATE-012 | reversal.kind / effect / source / detected_via | enum | work/reversal, ops | G21 | kind refund, void, chargeback, unknown; effect tombstone, end_current, remove_queued, none, review_partial; source operator or provider; detected_via notification, inquiry, manual |
| ABO-STATE-013 | grant_request.source_kind | enum | work/grant, ops | G20 | paid, complimentary, transfer |
| ABO-STATE-014 | grant_outcome_event.result and code | enum | work/grant | G06 | result applied, already_applied, rejected, conflict (transient is not stored), plus code (for example voided, terminal 1); non-terminal results park the work row |
| ABO-STATE-015 | accepted_operator_command.stage | state values | ops | G13 | accepted, local_applied, platform_succeeded, complete, conflict, awaiting_operator_auth; command_kind local_hp or relay |
| ABO-STATE-016 | command_recovery_fact.fact_kind | enum | records/command-facts | G18 | command_intent, relay_reserved, platform_result, local_result, erasure_ack |
| ABO-STATE-017 | raw_evidence_registry.state and outbox reasons | enum | evidence/raw | G18 | registry: quarantined, claimed, retained, delete_pending, deleted. outbox state open or done; reasons stale_claim, upload_uncertain, tenant_erasure, migration_erased_contact |
| ABO-STATE-018 | payout_line.kind | enum | provider/paymob/adapter | G21 | payment, refund, chargeback, fee, other |
| ABO-STATE-019 | finding.kind values | enum | reconciliation, work, ops, rebuild | G18 | payment_without_grant, grant_without_payment, grant_without_operator_action, transfer_without_authorisation, reversal_not_applied, payout_unmatched, payment_not_in_payout, unrecorded_reversal, callback_without_confirmation, feed_divergence, receipt_mismatch, reversal_kind_conflict, inquiry_disagrees, rebuild_missing_provider_correlation, transfer_recovery_disputed, accepted_transfer_disputed, accepted_command_disputed |
| ABO-STATE-020 | operator_action.action values | enum | ops | G20 | Local HP ops: publish_offer, retire_offer, reinstate_offer, release_payment, manual_chargeback, erase_contact. Relay method names: grant, suspend, resume, deleteInstallation, voidGrant, releaseHeld, listGrantsForVoid, recoverStrandedTerm, registerOperatorCredential, revokeOperatorCredential, registerIssuerKey, retireIssuerKey, revokeIssuerKey, registerServiceKey, revokeServiceKey, publishPlanVersion, retirePlanVersion, setCeilingPolicy, publishRoutingPolicy, canaryRoutingPolicy, promoteRoutingPolicy, rollbackRoutingPolicy, armKillSwitch, disarmKillSwitch, activateCohort, promoteCohort, deprecateCapability, retireCapability, beginTokenContractRotation, retireTokenContract, supportLookup, beginTransfer. Plain text actions: "Retry parked work", "Cancel an open checkout", "Submit a provider transaction id for a checkout with no known transaction", "Import a payout CSV", "Resolve a finding" |
| ABO-STATE-021 | operator_action.result values | enum | ops | G13 | accepted, open, cancelled, submitted, applied, unknown, plus any refusal code, plus AP result strings (ok, applied, already_applied, rejected, conflict, transient) |
| ABO-STATE-022 | scheduled_job_state.job names | job names | worker, scheduler | G16 | minute_processing, reversal_population_six_hour, reversal_population_hourly, hourly_watch, r2_lock_check, reconciliation, reversal_population_daily, digest, housekeeping |
| ABO-STATE-023 | payout CSV rejection reasons | error reasons | provider/paymob/adapter | G22 | field_count, invalid_transaction_id, invalid_kind, invalid_amount, invalid_settled_at, invalid_header, no_rows, mixed_period, invalid_encoding (returned as line_errors with 1-based line_no) |
| ABO-STATE-024 | Paymob provider capabilities | capability set | provider/paymob/adapter | G16 | methods ["card"]; cancel_checkout, refunds, mandates, payouts, pending_notifications all false |

## ABO-R2 (9)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-R2-001 | ledger/{fact_seq}.ndjson | R2 object | records/export | G18 | One canonical fact line per object (payload_version 2: fact_seq, table, key, row_sha256, fact_created_at, row). Written by the minute fact_export step; conflicting rewrite throws ledger_object_conflict. Read by rebuild. Bucket lock rule expected on this prefix |
| ABO-R2-002 | ledger-manifest/{high_water}.json | R2 object | records/export | G18 | `{payload_version: 1, exported_through}` high-water marker written after a gap-free export. Read by rebuild |
| ABO-R2-003 | evidence/notification/{notification_id} | R2 object | notify/intake, evidence/raw | G18 | Raw Paymob callback body (POST body or GET query string). Registered in raw_evidence_registry; erased on contact erasure |
| ABO-R2-004 | evidence/inquiry/{inquiry_id} | R2 object | work/runner, evidence/raw | G05 | Raw Paymob inquiry response bodies kept as evidence; registered and erasable like notification evidence |
| ABO-R2-005 | hmac-invalid/{YYYY-MM-DD}/{id} | R2 object | notify/intake, housekeeping | G05 | Diagnostic copy of a rejected callback; body kept only for the first 10 per hour, otherwise empty object; counted for AL-02 (3 in 15 min); swept after 30 days by housekeeping |
| ABO-R2-006 | terms/sha256/{sha256}.txt | R2 object | ops/index | G19 | Terms text stored under its content digest on publish_offer; read by GET /v1/offers (digest verified) |
| ABO-R2-007 | payouts/{file_sha256} | R2 object | ops/index | G22 | Raw payout CSV bytes of an accepted import |
| ABO-R2-008 | terms/en/{n}.txt (fixture style key) | R2 object (fixture/harness only) | records/append | G03 | `loadOffersFixture` writes whatever text_r2_key the fixture gives; test/harness use |
| ABO-R2-009 | R2 bucket lock read | R2 setting read | alert/lock | G07 | The daily job reads the bucket lock rules through the Cloudflare API and wants an enabled Indefinite rule for prefix `ledger/` or all |

## ABO-DO (1)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-DO-000 | no Durable Object classes or fields in the ABO | none | wrangler.toml | G07 | The ABO uses D1 and R2 only. All quota/coverage Durable Object state lives in the AP |

## ABO-CRON (25)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-CRON-001 | `* * * * *` (every minute) | cron schedule | worker | G15 | Refresh signing-key gate if missing; run minute processing; retry-only pass of all due scheduled jobs (six_hour, hourly, daily); ping the minute heartbeat |
| ABO-CRON-002 | `0 * * * *` (hourly) | cron schedule | worker | G15 | Always refresh signing-key check; then run hourly jobs |
| ABO-CRON-003 | `0 */6 * * *` (every six hours) | cron schedule | worker | G15 | Run six_hour jobs only |
| ABO-CRON-004 | `0 6 * * *` (daily 06:00 UTC) | cron schedule | worker | G15 | Refresh signing-key gate if missing; run daily jobs; then sendDueAlerts. A daily period runs 06:00 UTC to 06:00 UTC |
| ABO-CRON-010 | minute step export_lag | minute step | worker, alert/index | G15 | markExportLagIfDue: raises/clears alert AL-16:export-lag when oldest unexported fact is over 1 hour old. Runs first and last (listed twice) |
| ABO-CRON-011 | minute step fact_export | minute step | worker, records/export | G07 | exportFacts: pending fact_log rows to R2 ledger/, fact_export marks, manifest |
| ABO-CRON-012 | minute step alert_dispatch | minute step | worker, alert/index | G15 | sendDueAlerts: e-mails active unsent alerts, marks repeats due |
| ABO-CRON-013 | minute step coverage_view | minute step | worker, coverage/view | G07 | refreshCoverageView: pulls AP readCoverageEvents (limit 200 per page) into coverage_view and feed_cursor |
| ABO-CRON-014 | minute step inquiry_budget | minute step | worker, work/inquiry-budget | G16 | runMinuteInquiryBudget: stale-confirm alert AL-01 (over 5 min), materialise sweep schedules, up to 50 each of confirm, grant, sweep, then reverse work, pending notification reversals |
| ABO-CRON-015 | minute step transfer_steps | minute step | worker, ops/index | G17 | runDueTransferSteps: up to 50 due work rows of kind transfer_step |
| ABO-CRON-016 | minute_processing outcome record | scheduled_job_state row | worker, scheduler | G15 | Ungated outcome stamped per minute; failed steps logged as `minute_step_failed`; failed run raises scheduled_job_failed:minute_processing |
| ABO-CRON-020 | job reversal_population_six_hour | scheduled job (six_hour) | worker, work/sweep | G16 | enqueueSixHourReversalPopulation: sweep_payment work rows per payment |
| ABO-CRON-021 | job reversal_population_hourly | scheduled job (hourly) | worker, work/sweep | G16 | enqueueHourlyReversalPopulation |
| ABO-CRON-022 | job hourly_watch | scheduled job (hourly) | worker, watch/hourly | G17 | AL-15 feed health (stale over 5 min), AL-22 issuer-key pin mismatch, AL-22 unannounced operator credential, then sendDueAlerts; fails if any read incomplete |
| ABO-CRON-023 | job r2_lock_check | scheduled job (daily) | worker, alert/lock | G07 | Reads R2 bucket lock via Cloudflare API; raises or clears AL-16:r2-lock; non-success is `failed` |
| ABO-CRON-024 | job reconciliation | scheduled job (daily) | worker, reconciliation/run | G22 | Eleven checks (payment_without_grant ... receipt_mismatch), then AL-10 repair. Also run inline after every payout import |
| ABO-CRON-025 | job reversal_population_daily | scheduled job (daily) | worker, work/sweep | G16 | enqueueDailyReversalPopulation |
| ABO-CRON-026 | job digest | scheduled job (daily) | worker, digest/run | G15 | Raises AL-14 for keys expiring within 30 days, builds and e-mails the digest (subject `digest`), then pings the digest heartbeat only after the send |
| ABO-CRON-027 | job housekeeping | scheduled job (daily) | worker, housekeeping/run | G05 | Drains raw-evidence deletes (100), deletes work rows done and older than 90 days, deletes alert rows last sent over 90 days ago, sweeps hmac-invalid R2 objects older than 30 days (budget 1000 deletes per run, cursor in housekeeping_r2_cursor) |
| ABO-CRON-030 | scheduler claim/lease rules | scheduler mechanics | scheduler/jobs | G06 | Lease 15 min; deferred retry 5 min; failed retry 15 min; period keys six_hour:{n}, hourly:{n}, daily:{date}; retryOnly (minute) claims only attempts with next_attempt_at set; failure raises alert scheduled_job_failed:{job}; error code is the error name capped at 64 chars |
| ABO-CRON-031 | requeueScheduledJob | scheduler function | scheduler/jobs, ops | G22 | Used after payout import when inline reconciliation did not succeed: clears last_succeeded_period so the minute cron re-runs reconciliation; error code import_reconciliation_incomplete |
| ABO-CRON-032 | heartbeat pings | outbound ping | worker | G15 | Minute cron GETs HEARTBEAT_URL_MINUTE (fallback HEARTBEAT_URL); digest success GETs HEARTBEAT_URL_DIGEST (fallback HEARTBEAT_URL); failures ignored |
| ABO-CRON-033 | signing-key check | cron side job | worker, work/grant | G17 | refreshSigningKeyCheck: checks the ABO grant key is active in AP listServiceKeys; writes signing_key_gate (paused 1 and alert AL-23 when not) |
| ABO-CRON-034 | inline (non-cron) background work | background | notify/intake, ops | G05 | POST /notify/paymob runs confirm for the work row then the inquiry budget inside ctx.waitUntil; ops manual actions run their work inline |
| ABO-CRON-035 | recovery fence lease | timer | recovery-fence | G18 | Recovery fence lease 5 minutes (acquire, renew, publish) |

## ABO-OUT (36)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OUT-001 | PLATFORM.grant | AP call | work/grant, ops, rebuild | G20 | Paid grant: `contract_version, abo_kid, abo_signature, envelope_b64`; complimentary: `access_jwt, envelope, operation, assertion?, signer_credential_id, ceiling_override_operation?`. Results applied, already_applied, rejected, conflict, transient |
| ABO-OUT-002 | PLATFORM.getCoverage | AP call | clinic-api/billing-reads, clinic-api/checkouts, ops, reconciliation, work/reversal, work/sweep | G07 | Args `org_id`; returns snapshot. Failure falls back to coverage_view |
| ABO-OUT-003 | PLATFORM.readCoverageEvents | AP call | coverage/view, reconciliation, rebuild | G07 | Args `after`, `limit` (200). Coverage feed pull |
| ABO-OUT-004 | PLATFORM.voidForReversal | AP call | work/reversal, rebuild | G16 | Args grant_id, reversal_id, reason, evidence_sha256, partial, abo_kid, abo_signature |
| ABO-OUT-005 | PLATFORM.listGrants | AP call | ops, reconciliation, rebuild | G06 | Grants known to the AP |
| ABO-OUT-006 | PLATFORM.listServiceKeys | AP call | work/grant, digest, ops | G17 | Service key registry |
| ABO-OUT-007 | PLATFORM.listIssuerKeys | AP call | digest, watch, ops | G17 | Issuer key registry |
| ABO-OUT-008 | PLATFORM.listOperatorCredentials | AP call | ops, watch | G17 | Operator credential registry (also the source for assertion verification) |
| ABO-OUT-009 | PLATFORM.feedConsumerHealth | AP call | watch, digest | G07 | `last_pull_at` of the coverage feed consumer |
| ABO-OUT-010 | PLATFORM.recordOperatorAction | AP call | ops | G06 | Audit mirror after every console action (jwt, action, subject, action id) |
| ABO-OUT-011 | PLATFORM.beginTransfer / transferOut / transferIn | AP calls | ops | G20 | Installation transfer; receipts verified with PLATFORM_PUBLIC_KEYS |
| ABO-OUT-012 | PLATFORM.releaseHeld / voidGrant / listGrantsForVoid / recoverStrandedTerm | AP calls | ops | G21 | Grant and term operations |
| ABO-OUT-013 | PLATFORM.suspend / resume / deleteInstallation | AP calls | ops | G20 | Installation lifecycle |
| ABO-OUT-014 | PLATFORM.countLedgerRows / readLaunchState / inspectCoverage | AP calls | ops | G07 | Read-only operator views |
| ABO-OUT-015 | PLATFORM.registerOperatorCredential / revokeOperatorCredential | AP calls | ops | G17 | Credential lifecycle |
| ABO-OUT-016 | PLATFORM.registerIssuerKey / retireIssuerKey / revokeIssuerKey | AP calls | ops | G17 | Issuer key lifecycle |
| ABO-OUT-017 | PLATFORM.registerServiceKey / revokeServiceKey | AP calls | ops | G17 | Service key lifecycle |
| ABO-OUT-018 | PLATFORM.publishPlanVersion / retirePlanVersion / setCeilingPolicy | AP calls | ops | G19 | Plan and ceiling configuration |
| ABO-OUT-019 | PLATFORM.publishRoutingPolicy / canaryRoutingPolicy / promoteRoutingPolicy / rollbackRoutingPolicy | AP calls | ops | G24 | Routing policy lifecycle |
| ABO-OUT-020 | PLATFORM.armKillSwitch / disarmKillSwitch | AP calls | ops | G23 | Kill switch |
| ABO-OUT-021 | PLATFORM.activateCohort / promoteCohort / deprecateCapability / retireCapability | AP calls | ops | G23 | Capability and cohort lifecycle |
| ABO-OUT-022 | PLATFORM.beginTokenContractRotation / retireTokenContract | AP calls | ops | G17 | Token contract lifecycle |
| ABO-OUT-023 | PLATFORM.supportLookup | AP call | ops | G12 | Support lookup relay |
| ABO-OUT-030 | POST {PAYMOB_BASE_URL}/v1/intention/ | Paymob call | provider/paymob/client | G04 | Header `Authorization: Token {PAYMOB_SECRET_KEY}`. Creates the payment intention (amount, billing data from the contact, special reference `{reference}-{attempt_no}`, notification and return URLs). Result: intention id, order id, client_secret |
| ABO-OUT-031 | Paymob unified checkout redirect URL | URL built | provider/paymob/adapter | G04 | Built from PAYMOB_BASE_URL, PAYMOB_PUBLIC_KEY and the intention client_secret; returned to the clinic as `redirect_url` (no call) |
| ABO-OUT-032 | POST {PAYMOB_BASE_URL}/api/auth/tokens | Paymob call | provider/paymob/client | G05 | Body `{api_key: PAYMOB_API_KEY}`; returns inquiry auth token |
| ABO-OUT-033 | POST {PAYMOB_BASE_URL}/api/ecommerce/orders/transaction_inquiry | Paymob call | provider/paymob/client | G05 | Bearer auth token; body `{order_id}`; inquiry by order |
| ABO-OUT-034 | GET {PAYMOB_BASE_URL}/api/acceptance/transactions/{txn_id} | Paymob call | provider/paymob/client | G16 | Bearer auth token; inquiry by transaction (also for parent transaction on refunds) |
| ABO-OUT-035 | Paymob inquiry outcomes | outcome kinds | provider/paymob/client | G05 | ok, timeout, rate_limit (429), unauthorized (401), error. Reservation from inquiry_spend: max 2 inquiries per UTC minute |
| ABO-OUT-036 | Paymob HMAC check on callbacks | verification | provider/paymob/adapter | G16 | HMAC with PAYMOB_HMAC_SECRET over the ordered fields amount_cents, created_at, currency, error_occured, has_parent_transaction, id, integration_id, is_3d_secure, is_auth, is_capture, is_refunded, is_standalone_payment, is_voided, order.id, owner, pending, source_data.pan, source_data.sub_type, source_data.type, success |
| ABO-OUT-040 | GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs | Cloudflare Access call | ops/index | G06 | Fetches Access signing keys per ops request (or `ACCESS_CERTS_JSON` override) |
| ABO-OUT-041 | GET https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/r2/buckets/{R2_BUCKET_NAME}/lock | Cloudflare API call | alert/lock | G07 | Bearer `R2_LOCK_READ_TOKEN` |
| ABO-OUT-042 | SEND_EMAIL.send to ALERT_EMAIL_TO | e-mail | alert/index, digest/run | G15 | From and to are both ALERT_EMAIL_TO. Subject is the alert code or `digest`; alert text `{code} {detail_id}` |
| ABO-OUT-043 | GET HEARTBEAT_URL / HEARTBEAT_URL_MINUTE / HEARTBEAT_URL_DIGEST | heartbeat ping | worker | G15 | See ABO-CRON-032 |
| ABO-OUT-044 | Supabase | none | whole ABO | G06 | The ABO makes no Supabase call and holds no Supabase secret |
| ABO-OUT-045 | Inbound billing-token verification | inbound check | clinic-api/auth | G17 | Not outbound: Ed25519 verification with the issuer public keys pinned in `ISSUER_KEYS` (and `harness_issuer_pin` under TEST_CLOCK) |

## ABO-ERR (38)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ERR-001 | unauthenticated (401) | error code | clinic-api/auth, ops | G19 | Missing/invalid billing bearer, unknown kid, bad signature, wrong audience/version/lifetime; on ops: missing or invalid Access JWT |
| ABO-ERR-002 | forbidden_role (403) | error code | clinic-api/auth | G01 | Token otherwise valid but role is not administrator |
| ABO-ERR-003 | rate_limited (429) | error code | clinic-api/rate, clinic-api/checkouts | G04 | 60 hits per billing token jti, or the 10-checkouts-per-org-per-hour limit on POST /v1/checkouts |
| ABO-ERR-004 | invalid_request (422 clinic, 400/422 ops) | error code | clinic-api, ops | G22 | Bad JSON/fields, bad cursor, bad phone, payout import line errors (422 with `line_errors`), bad payout list limit/cursor (422), missing note/transaction_id (400) |
| ABO-ERR-005 | not_found (404) | error code | clinic-api, ops | G05 | No contact, checkout not owned, nothing displayable, unknown lookup, parked/open precondition failed; also JSON 404 for GET /v1/checkouts without open=1 |
| ABO-ERR-006 | idempotency_conflict (409) | error code | clinic-api | G03 | Same client_request_id with different contact content, or different offer/version/terms |
| ABO-ERR-007 | billing_contact_required (409) | error code | clinic-api/checkouts | G18 | No usable (non-erased) billing contact |
| ABO-ERR-008 | terms_not_accepted (409) | error code | clinic-api/checkouts | G13 | terms_version is not the current maximum |
| ABO-ERR-009 | offer_unavailable (409) | error code | clinic-api/checkouts | G03 | Offer not sellable or version not the current sellable one; extra `current_version` |
| ABO-ERR-010 | provider_unavailable (503) | error code | clinic-api/checkouts | G04 | Paymob intention not obtained, checkout expired/not open, attempt not created; extra `checkout_id` |
| ABO-ERR-011 | contract_version_unsupported (400) | error code | clinic-api/version | G03 | Missing or unacceptable `Abo-Contract-Version`; extra `accepted_versions`; ops variant adds `reload: true` |
| ABO-ERR-020 | assertion_invalid (400) | error code | ops | G19 | Malformed/bad operation, wrong op, wrong contract_version, params not bound to route subject, unsigned relay body, invalid copy/price/terms |
| ABO-ERR-021 | assertion_required (400) | error code | ops | G19 | HP-local body without `assertion` |
| ABO-ERR-022 | actor_email_mismatch (400) | error code | ops | G01 | Operation actor differs from the Access e-mail |
| ABO-ERR-023 | assertion_expired (400) | error code | ops | G19 | issued_at older/newer than 5 minutes |
| ABO-ERR-024 | assertion_used (400) | error code | ops | G19 | Challenge already in assertion_used |
| ABO-ERR-025 | credential_not_active (400) | error code | ops | G17 | No active operator credential verifies the assertion |
| ABO-ERR-026 | conflict (409; HP refusals 400) | error code | ops | G20 | Duplicate relay id with different content, retry/cancel not possible, accepted command mismatch, complimentary envelope not matching org/grant id |
| ABO-ERR-027 | recovery_evidence_required (409) | error code | ops | G18 | Accepted command or erasure/transfer lacks original immutable evidence |
| ABO-ERR-028 | payment_fully_reversed (409) | error code | ops | G16 | Release refused because payment already fully reversed |
| ABO-ERR-029 | payment_not_withheld (400) | error code | ops | G06 | Release only allowed for disposition withheld_mismatch |
| ABO-ERR-030 | reversal_exists (400) | error code | ops | G21 | Manual chargeback refused, reversal for that dedupe key already recorded |
| ABO-ERR-031 | allocation_conflict (400) | error code | ops | G03 | Publish could not allocate offer/terms version numbers after retries |
| ABO-ERR-032 | transient (503) | error code | ops | G03 | AP read failed or cached relay result unreadable |
| ABO-ERR-033 | platform_unavailable (503) | error code | ops | G20 | Complimentary grant receipt could not be verified or stored |
| ABO-ERR-034 | internal_error (500) | error code | ops | G22 | Provider adapter missing, payout list database failure |
| ABO-ERR-035 | coverage_unknown (404) | error code | ops | G11 | Clinic dossier when AP coverage read is not ok and gives no code (AP code is passed through when present) |
| ABO-ERR-036 | HP refusal results (HTTP 400) | refusal codes | ops | G03 | refuseHpAction returns the result string (including not_found, conflict) as the code with HTTP 400 and records it in operator_action.result |
| ABO-ERR-037 | AP relay envelope | pass-through | ops | G06 | Relays answer HTTP 200 `{contract_version, result, code?, detail?, receipt?}`; result from the AP (ok, applied, already_applied, rejected, conflict, transient) |
| ABO-ERR-038 | call_outcome_unknown | recorded result | ops | G17 | Recorded in command_recovery_fact when a transferOut/transferIn call throws |
| ABO-ERR-039 | blocked_missing_original_authorization / blocked_missing_transfer_correlation | recovery stop codes | ops | G17 | Transfer recovery stops; work parked, findings transfer_recovery_disputed / accepted_transfer_disputed |
| ABO-ERR-040 | abo_recovery_in_progress (503 text) | plain text | worker, recovery-fence | G18 | Whole worker during rebuild |
| ABO-ERR-041 | /notify/paymob status codes | bare statuses | notify/intake | G05 | 400 (not UTF-8 or unreadable), 413 (over 1 MiB), 429 (per-IP), 401 (bad HMAC), 500 (storage or provider missing), 200 (accepted, unparseable, unmatched) |
| ABO-ERR-042 | thrown work errors | internal codes | work | G06 | lease_lost, grant_request_conflict, grant_request_persist_failed, payment_identity_conflict, payment_confirmation_withheld_mismatch, payment_confirmation_original_order_unbound, payment_confirmation_identity_conflict, provider_missing, reconciliation_incomplete |
| ABO-ERR-043 | thrown ledger/export/rebuild errors | internal codes | records/export, rebuild | G18 | ledger_object_conflict, ledger_manifest_conflict, ledger_manifest_incomplete, ledger_fact_sequence_gap, ledger_fact_hash_conflict, ledger_fact_missing_canonical_row, ledger_command_fact_invalid, ledger_adapter_secret_requires_historical_stop; rebuild: ledger_sequence_gap, ledger_hash_mismatch, ledger_business_row_conflict, ledger_table_unregistered, ledger_column_unregistered, ledger_identity_*, ledger_checkpoint_gap, ledger_checkpoint_ahead_of_manifest, ledger_manifest_*, ledger_object_*, ledger_payload_invalid, checkout_timestamp_*, legacy_failed_checkout_timestamp_unrecoverable, rebuild_*_command_fact_invalid, rebuild_*_command_conflict, rebuild_erasure_fact_invalid, rebuild_due_checkpoint_ahead_of_ledger, erasure_fence_not_restored |
| ABO-ERR-044 | thrown recovery/command-fact errors | internal codes | recovery-fence, records/command-facts, ops | G18 | abo_recovery_in_progress, abo_recovery_already_owned, abo_recovery_ownership_lost, command_recovery_fact_too_large, command_recovery_fact_lineage_invalid, command_recovery_fact_invalid, command_recovery_fact_filter_invalid, command_recovery_fact_corrupt, erase_contact_scope_empty, "accepted operator command lease is held" |
| ABO-ERR-045 | thrown startup/config errors | internal codes | provider/paymob/client, clinic-api/offers | G05 | `PAYMOB_BASE_URL must be an HTTPS origin`, `current terms_version en not found`, `R2 object missing at {key}`, `terms_hash_mismatch terms_version={n} key={key}` |
| ABO-ERR-046 | minute and job failure log events | log events | worker, scheduler, reconciliation | G15 | `minute_step_failed`, `scheduled_job_failed`, `reconciliation_check_failed` (console.error JSON with bounded fields) |

## ABO-NOTICE (7)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-NOTICE-001 | duplicate_payment | clinic notice | clinic-api/billing-reads | G07 | In GET /v1/subscription `notices[]` when any payment of the org has classification likely_duplicate |
| ABO-NOTICE-002 | late_payment_honoured | clinic notice | clinic-api/billing-reads | G07 | Any payment classified late |
| ABO-NOTICE-003 | payment_withheld | clinic notice | clinic-api/billing-reads | G07 | Any payment with disposition withheld_mismatch |
| ABO-NOTICE-004 | reversal_recorded | clinic notice | clinic-api/billing-reads | G16 | Any reversal on a payment of the org |
| ABO-NOTICE-005 | terms_held | clinic notice | clinic-api/billing-reads | G07 | Coverage snapshot `held_count` greater than 0 |
| ABO-NOTICE-006 | subscription_ref | field | clinic-api/billing-reads | G07 | `AIC-` style reference derived from org id |
| ABO-NOTICE-007 | payment classification values on /v1/payments | values | clinic-api/billing-reads | G07 | normal, late, likely_duplicate |

## ABO-ALERT (18)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ALERT-001 | AL-01 | operator alert | work/runner | G06 | Confirm work open more than 5 minutes; key AL-01:{work_id}; repeats hourly |
| ABO-ALERT-002 | AL-02 | operator alert | notify/intake | G05 | 3 or more invalid-HMAC callbacks in 15 minutes; key AL-02:hmac-invalid; repeats hourly |
| ABO-ALERT-003 | AL-03 | operator alert | work/runner, work/sweep | G05 | Provider inquiry discovery unavailable, or payment without a valid-HMAC notification; keys AL-03:discovery:{checkout_id}, AL-03:{payment_id}; no repeat |
| ABO-ALERT-004 | AL-04 | operator alert | work/grant | G06 | Grant work waiting past threshold; key AL-04:{work_id}; repeats hourly |
| ABO-ALERT-005 | AL-05 | operator alert | notify/intake, work/runner | G05 | Unmatched or unbound callback/inquiry; keys AL-05:unmatched:{body_sha256}, AL-05:unbound:{checkout_id}; no repeat |
| ABO-ALERT-006 | AL-06 | operator alert | work/reversal, ops | G16 | Reversal recorded or reversal kind conflict; keys AL-06:{reversal_id}, AL-06:kind:{reversal_id}; no repeat |
| ABO-ALERT-007 | AL-07 | operator alert | work/grant, work/reversal, ops | G16 | Grant or void receipt unverified / rejected / request unrecoverable; keys AL-07:{work_id}, AL-07:request:{reversal_id}, AL-07:{source_ref}; repeats hourly |
| ABO-ALERT-008 | AL-08 | operator alert | work/runner | G05 | Late payment; key AL-08:{checkout_id}; no repeat |
| ABO-ALERT-009 | AL-09 | operator alert | work/runner | G05 | Likely-duplicate payment; key AL-09:{checkout_id}; no repeat |
| ABO-ALERT-010 | AL-10 | operator alert | reconciliation | G22 | Open finding; key AL-10:{finding_id}; repeats daily until the finding is resolved |
| ABO-ALERT-011 | AL-14 | operator alert | digest | G17 | Issuer or service key expires within 30 days; key AL-14:{kid}; repeats daily |
| ABO-ALERT-012 | AL-15 | operator alert | watch/hourly | G07 | Coverage feed consumer health stale (over 5 minutes), unknown or unreadable; key AL-15:feed; repeats hourly |
| ABO-ALERT-013 | AL-16 | operator alert | alert/index, alert/lock | G07 | Export lag (AL-16:export-lag, oldest unexported fact over 1 hour) and R2 bucket lock missing (AL-16:r2-lock); repeats daily |
| ABO-ALERT-014 | AL-22 | operator alert | watch/hourly | G17 | Pinned issuer key differs from AP (AL-22:issuer:{kid}) or operator credential not announced (AL-22:credential:{id}); repeats hourly |
| ABO-ALERT-015 | AL-23 | operator alert | work/grant, notify/intake | G05 | ABO signing key missing/inactive on AP (AL-23:{kid} or AL-23:missing), or unparseable Paymob notification (AL-23:notification-parse); repeats hourly |
| ABO-ALERT-016 | scheduled_job_failed | operator alert | scheduler/jobs | G15 | Key scheduled_job_failed:{job}; repeats daily; cleared on next success |
| ABO-ALERT-017 | offer_malformed | operator alert | clinic-api/offers, billing-reads | G03 | Key offer_malformed:{offer_id}:{version}; no repeat |
| ABO-ALERT-018 | alert delivery rules | mechanics | alert/index | G15 | Alert row fields: active, unsent, last_sent_at, next_send_at; e-mail subject = code; repeat intervals 1 hour or 1 day by code; alerts also sent at the end of the daily cron and inside the hourly watch |

## ABO-ENV (32)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-ENV-001 | BILLING_HOST | var | wrangler, worker | G05 | Billing hostname; also used to build notify and return URLs given to Paymob |
| ABO-ENV-002 | OPS_HOST | var | wrangler, worker, ops | G19 | Console hostname; also the WebAuthn rp_id and origin `https://{OPS_HOST}` |
| ABO-ENV-003 | HEARTBEAT_URL | var | wrangler, worker | G11 | Fallback heartbeat URL |
| ABO-ENV-004 | HEARTBEAT_URL_MINUTE | optional var | worker | G11 | Not in wrangler.toml; minute-stream heartbeat |
| ABO-ENV-005 | HEARTBEAT_URL_DIGEST | optional var | worker | G15 | Not in wrangler.toml; digest-stream heartbeat |
| ABO-ENV-006 | ALERT_EMAIL_TO | var | wrangler, alert | G15 | Address for alerts and the digest (both from and to); also the SEND_EMAIL destination_address |
| ABO-ENV-007 | ISSUER_ID | var | wrangler, clinic-api/auth | G03 | Expected issuer of billing tokens |
| ABO-ENV-008 | ISSUER_KEYS | var (JSON array of {kid, public_key}) | wrangler, clinic-api/auth, ops | G17 | Pinned Supabase billing-token issuer public keys |
| ABO-ENV-009 | CLOUDFLARE_ACCOUNT_ID | var | wrangler, alert/lock | G07 | For the R2 lock API call |
| ABO-ENV-010 | R2_BUCKET_NAME | var | wrangler, alert/lock | G07 | Bucket whose lock is checked |
| ABO-ENV-011 | R2_LOCK_READ_TOKEN | secret | worker, alert | G07 | Not in wrangler.toml; Cloudflare API read token for the lock check |
| ABO-ENV-012 | PAYMOB_BASE_URL | var | wrangler, provider | G05 | HTTPS origin of Paymob |
| ABO-ENV-013 | PAYMOB_SECRET_KEY | secret (placeholder in wrangler) | wrangler, provider | G04 | Intention creation (Token auth) |
| ABO-ENV-014 | PAYMOB_PUBLIC_KEY | var (placeholder in wrangler) | wrangler, provider | G05 | Part of the unified checkout URL |
| ABO-ENV-015 | PAYMOB_CARD_INTEGRATION_ID | var | wrangler, provider | G04 | Integer card integration id placed in the intention |
| ABO-ENV-016 | PAYMOB_HMAC_SECRET | secret (placeholder in wrangler) | wrangler, provider | G05 | Callback HMAC verification |
| ABO-ENV-017 | PAYMOB_API_KEY | secret (placeholder in wrangler) | wrangler, provider | G05 | Exchanged for the inquiry auth token |
| ABO-ENV-018 | PAYMOB_ALLOW_LOCAL_HTTP | optional var | provider | G05 | "1" lets the Paymob URL be non-HTTPS (local test) |
| ABO-ENV-019 | PAYMOB_STUB | optional service binding | provider | G05 | Fetcher used instead of public fetch (tests) |
| ABO-ENV-020 | ABO_GRANT_KEY | secret (JSON {kid, pkcs8}; placeholder in wrangler) | wrangler, work/grant, work/reversal, ops | G06 | ABO Ed25519 signing key for grants and void requests; kid exposed in launch-state |
| ABO-ENV-021 | PLATFORM_PUBLIC_KEYS | var (JSON array of {kid, public_key}) | wrangler, work, ops, records | G17 | AP receipt-signing public keys pinned by the ABO |
| ABO-ENV-022 | ACCESS_TEAM_DOMAIN | var | worker, ops | G00 | Not in wrangler.toml; Cloudflare Access team domain |
| ABO-ENV-023 | ACCESS_AUD | var | worker, ops | G00 | Not in wrangler.toml; Access application audience |
| ABO-ENV-024 | ACCESS_CERTS_JSON | optional var | ops | G00 | Local Access key override |
| ABO-ENV-025 | TEST_CLOCK | optional var | clock, many | G00 | "1" switches to the D1 harness clock and issuer pins |
| ABO-ENV-030 | DB | D1 binding | wrangler | G00 | database names abo-development, abo-staging, abo-production |
| ABO-ENV-031 | R2 | R2 binding | wrangler | G07 | buckets abo-development, abo-staging, abo-production |
| ABO-ENV-032 | PLATFORM | service binding | wrangler | G00 | service ai-platform-gateway-{environment}, entrypoint VendorEntrypoint |
| ABO-ENV-033 | SEND_EMAIL | send_email binding | wrangler | G15 | destination_address from ALERT_EMAIL_TO |
| ABO-ENV-034 | cron triggers | trigger config | wrangler | G15 | `* * * * *`, `0 * * * *`, `0 */6 * * *`, `0 6 * * *` |
| ABO-ENV-035 | contract channels used | constants | vendor-contracts | G05 | aboClinic, aboConsole, vendorEntrypoint, paymobReturn, paymobAdapter (all currently 1) |
| ABO-ENV-036 | vendor-contracts dependency | package | package.json | G00 | Shared package `../packages/vendor-contracts` |

## ABO-OP (42)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-OP-001 | Console shell page "ABO operator console" | console page | ops/browser/shell | G19 | Sections: reload banner (shown on contract-version refusal), operator e-mail label, bootstrap section, "Local approvals" form list, status line. Context from GET /ops/ceremony-context |
| ABO-OP-002 | Bootstrap: first operator credential | console action | ops/browser/shell | G17 | Shown only when the active credential list is empty. Browser creates a passkey (ES256 or EdDSA), posts to POST /ops/operator-credentials. Status text says activation after 24 hours and that bootstrap closes once the registry has a credential |
| ABO-OP-003 | Local approval forms (6) | console forms | ops/browser/ceremony, shell | G21 | publish_offer (fields Offer ID, Price minor units, Terms text, Display name en, Summary en), retire_offer, reinstate_offer, release_payment, manual_chargeback, erase_contact (each: one subject field). Button "Approve with passkey"; WebAuthn userVerification required |
| ABO-OP-004 | Ceremony mechanics | console behaviour | ops/browser | G19 | Operation `{op, params, actor_email, issued_at, nonce, contract_version}`; challenge = SHA-256 of canonical JSON; assertion fields alg, authenticator_data, client_data_json, signature; refusals show code; version refusal forces reload; nothing retried automatically |
| ABO-OP-010 | Publish offer | operator action | ops/index | G19 | ABO-ROUTE-035; HP-local; catalogue change |
| ABO-OP-011 | Retire offer | operator action | ops/index | G19 | ABO-ROUTE-036; HP-local |
| ABO-OP-012 | Reinstate offer | operator action | ops/index | G19 | ABO-ROUTE-037; HP-local |
| ABO-OP-013 | Plan versions: publish | operator action | ops/index | G19 | ABO-ROUTE-052; HP-relay to AP |
| ABO-OP-014 | Plan versions: retire | operator action | ops/index | G19 | ABO-ROUTE-054; HP-relay to AP |
| ABO-OP-015 | Ceiling policy set | operator action | ops/index | G19 | ABO-ROUTE-053; HP-relay to AP |
| ABO-OP-016 | Complimentary grant | operator action | ops/index | G20 | ABO-ROUTE-041; HP-relay; optional separate ceiling_override_operation (op `ceiling_override`, params contract_version, access_jwt, envelope without ceiling_override) |
| ABO-OP-017 | Suspend installation | operator action | ops/index | G20 | ABO-ROUTE-042; class-H relay |
| ABO-OP-018 | Resume installation | operator action | ops/index | G20 | ABO-ROUTE-043; class-H relay |
| ABO-OP-019 | Delete installation | operator action | ops/index | G20 | ABO-ROUTE-044; HP-relay |
| ABO-OP-020 | Begin transfer | operator action | ops/index | G20 | ABO-ROUTE-045; HP-relay plus inline transferOut/transferIn and minute transfer steps |
| ABO-OP-021 | Release payment (withheld mismatch) | operator action | ops/index | G21 | ABO-ROUTE-038; HP-local; creates grant work |
| ABO-OP-022 | Manual chargeback | operator action | ops/index | G21 | ABO-ROUTE-039; HP-local; creates reversal and void work |
| ABO-OP-023 | Void grant | operator action | ops/index | G21 | ABO-ROUTE-048; HP-relay |
| ABO-OP-024 | Release held grant | operator action | ops/index | G21 | ABO-ROUTE-049; HP-relay |
| ABO-OP-025 | List grants for void | operator action | ops/index | G06 | ABO-ROUTE-046; access relay (read) |
| ABO-OP-026 | Recover stranded term | operator action | ops/index | G21 | ABO-ROUTE-047; HP-relay |
| ABO-OP-027 | Retry parked work | operator action | ops/index | G06 | ABO-ROUTE-032; Access only |
| ABO-OP-028 | Cancel open checkout | operator action | ops/index | G22 | ABO-ROUTE-033; Access only |
| ABO-OP-029 | Submit provider transaction id | operator action | ops/index | G11 | ABO-ROUTE-034; Access only |
| ABO-OP-030 | Import payout CSV | operator action | ops/index | G22 | ABO-ROUTE-029; Access only; runs reconciliation |
| ABO-OP-031 | Resolve finding | operator action | ops/index | G22 | ABO-ROUTE-030; Access only |
| ABO-OP-032 | Register operator credential | operator action | ops/index | G17 | ABO-ROUTE-050; relay (bootstrap form posts without assertion; later registrations carry operation and assertion) |
| ABO-OP-033 | Revoke operator credential | operator action | ops/index | G17 | ABO-ROUTE-051; HP-relay |
| ABO-OP-034 | Erase contact | operator action | ops/index | G18 | ABO-ROUTE-040; HP-local; erasure fence |
| ABO-OP-035 | Register / revoke / retire issuer key | operator actions | ops/index | G17 | ABO-ROUTE-055, 056, 057; HP-relay |
| ABO-OP-036 | Register / revoke service key | operator actions | ops/index | G17 | ABO-ROUTE-058, 059; HP-relay |
| ABO-OP-037 | Routing policy publish / canary / promote / rollback | operator actions | ops/index | G24 | ABO-ROUTE-060 to 063; class-H relay |
| ABO-OP-038 | Kill switch arm / disarm | operator actions | ops/index | G23 | ABO-ROUTE-064, 065; class-H relay |
| ABO-OP-039 | Cohort activate / promote | operator actions | ops/index | G23 | ABO-ROUTE-066, 067; class-H relay |
| ABO-OP-040 | Capability deprecate / retire | operator actions | ops/index | G08 | ABO-ROUTE-068, 069; class-H relay |
| ABO-OP-041 | Token contract begin rotation / retire | operator actions | ops/index | G17 | ABO-ROUTE-070, 071; class-H relay |
| ABO-OP-042 | Support lookup | operator view | ops/index | G11 | ABO-ROUTE-072; class-H style relay |
| ABO-OP-050 | Operator read views | operator views | ops/index | G22 | Lookup, clinic dossier, parked work, findings, grants, launch-state, payout-imports list, registries (ABO-ROUTE-021 to 028, 031) |
| ABO-OP-051 | Daily digest e-mail content | operator report | digest/run | G16 | Sections: window_start, checkouts_24h, payments_24h_by_classification, grants_by_source_kind, reversals_24h, alerts_sent_24h, grants (grant_id, source_kind, operator, reason, length_days, allowance, adjustment), open_findings, parked_work, open_alerts, scheduled_jobs, backend_last_pull, export_lag_fact_seq, export_lag_alert_active, r2_lock_alert_active, keys_expiring_within_30_days, channel_version_seen |
| ABO-OP-052 | Alert e-mails | operator report | alert/index | G15 | Subject `{code}`, text `{code} {detail_id}`, from and to ALERT_EMAIL_TO |
| ABO-OP-053 | Rebuild script | operator command | scripts/rebuild-abo | G18 | `npm run rebuild -- [--env name] <provider txn refs>`; runs rebuildAbo (ledger replay, gap re-inquiry, grant comparison, reconciliation) through wrangler getPlatformProxy with remote bindings |
| ABO-OP-054 | Time Travel restore / D1 rebuild runbook | operator procedure | REBUILD.md (non-code file in area) | G18 | Procedure document next to the code; the code behaviour is in rebuild.ts and recovery-fence.ts |

## ABO-SCRIPT (6)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| ABO-SCRIPT-001 | npm run dev | command | package.json | G18 | wrangler dev --env development |
| ABO-SCRIPT-002 | npm run deploy / check / types | commands | package.json | G18 | wrangler deploy, wrangler check, wrangler types |
| ABO-SCRIPT-003 | npm run rebuild | command | package.json, scripts/rebuild-abo | G18 | See ABO-OP-053 |
| ABO-SCRIPT-004 | scripts/check-import-boundary.mjs | build check | scripts | G05 | Only provider/paymob/adapter imports the Paymob client; adapter stays inside provider/ |
| ABO-SCRIPT-005 | scripts/build-platform-for-hxw.mjs | test-harness build | scripts | G18 | Bundles the AP worker for the cross-worker harness (test only) |
| ABO-SCRIPT-006 | run_campaigns.py, campaigns/*.json, vitest configs, fixtures/offers.json | test tooling | abo root | G03 | Test campaign tooling and fixture (not for published docs) |

## AP-ROUTE (7)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ROUTE-001 | GET /health | HTTP route (public fetch handler) | worker entry | G11 | No auth. Returns JSON with build (BUILD_SHA) and environment (ENVIRONMENT). |
| AP-ROUTE-002 | GET /v1/capabilities | HTTP route (public fetch handler) | worker entry; discovery; capability | G20 | Auth: Authorization Bearer AI token (AAT, audience ai-platform). Header Aip-Contract-Version required (channel platformClinic; unsupported gives 400 body with code and accepted_versions). Optional If-None-Match; 304 with ETag and Cache-Control private, must-revalidate; 200 body {manifests}. Errors use the taxonomy error body (401 unauthenticated, 403 installation_suspended). |
| AP-ROUTE-003 | GET /v1/feed/coverage | HTTP route (public fetch handler) | worker entry (feed handler) | G17 | Auth: Authorization Bearer JWT, audience ai-platform-feed, signed by an issuer_key row (kid in JWT header), issuer must equal ISSUER_ID; any auth failure is a bare 401. Header Aip-Contract-Version required (channel platformFeed; unsupported gives 400 {contract_version, code, accepted_versions}). Query after (default 0) and limit (1..200, default 200). Reads coverage_event; upserts feed_consumer row 'backend-feed'. Body {contract_version, after, events[], next_after, has_more}. |
| AP-ROUTE-004 | POST /v1/requests | HTTP route (public fetch handler) | worker entry; adapter; pipeline | G04 | Auth: Bearer AAT. Required headers: Aip-Contract-Version, x-idempotency-key, x-capability-version; optional x-trace-id. Body: JSON object up to 1,048,576 bytes (capability_id or capability, user_intent or intent, context object, etc.). Responds as text/event-stream (SSE) after pre-accept guard; pre-accept failures are JSON taxonomy bodies; bare 422 for unparseable body/missing headers; 413 request_too_large. |
| AP-ROUTE-005 | GET /v1/requests/{reference} | HTTP route (public fetch handler) | worker entry; journal | G20 | Auth: Bearer AAT. Header Aip-Contract-Version required. Path suffix is the request reference (normalized once). 404 with empty body when unknown or empty reference. 200 JSON {state:Completed,result?} \|{state,pending:true} \|{state:Failed,terminal_error_code} \|{state:AwaitingContext} \|{state:Cancelled}. Auth failure uses taxonomy body (401 unauthenticated, 403 installation_suspended). |
| AP-ROUTE-006 | GET /v1/coverage | HTTP route (public fetch handler) | worker entry; coverage-read | G20 | Auth: Bearer AAT with role administrator (else bare 403); suspended installations are allowed through. Header Aip-Contract-Version required. Calls DO kind read_coverage. Body {subscription_ref, snapshot, queued_terms, recent_terms}. Errors: 401/403 taxonomy, 503 coverage_unknown (DO contract rejected), 500 internal_error. |
| AP-ROUTE-007 | Any other method/path | HTTP route (public fetch handler) | worker entry | G11 | Falls through to 404 with text body 'Not Found'. No other HTTP routes exist on the gateway Worker (no ops/control-plane HTTP routes). |

## AP-DORPC (26)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-DORPC-001 | admission | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch; quota-do | G04 | Request fields jti, installationId, idempotencyKey, requestReference (+ idempotencyBinding, journaledAnswer, journaledConflict, entitlement, quotaWeight, nowIso, ...). Validates args (400 bad_request on ArgValidationError). May hold/throw on harness fault when TEST_CLOCK=1. |
| AP-DORPC-002 | settleFallback | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G06 | Fields installationId, request_id, term_id, weight>=1, outcome consumed\|released. 400 invalid_settle_fallback_args. |
| AP-DORPC-003 | ackUsageReceipt | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G06 | Fields request_id, installationId, term_id, weight>=1. 400 invalid_ack_usage_receipt_args. |
| AP-DORPC-004 | credit | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G04 | Fields installationId, requestId, requestReference, usage, partial, term_id, outcome consumed\|released, idempotencyState failed\|cancelled\|completed, entitlement. |
| AP-DORPC-005 | release | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G04 | Fields installationId, requestId, idempotencyKey, jti. |
| AP-DORPC-006 | inspect | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G12 | Read-only snapshot of legacy KV state (key 'state'). |
| AP-DORPC-007 | apply_grant | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G06 | Applies a grant; passes PLATFORM_SIGNING_KEY and DB. Used by VendorEntrypoint.grant. |
| AP-DORPC-008 | seal_grant_route | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G06 | Fields installationId, orgId, grantId, envelopeSha256, routeGeneration, bindingEpoch, sealedAt. 400 result conflict on bad args. |
| AP-DORPC-009 | seal_ceiling_claim | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G19 | Fields installationId, orgId, grantId, envelopeSha256, routeGeneration, bindingEpoch, nowIso; uses PLATFORM_SIGNING_KEY and DB. |
| AP-DORPC-010 | read_coverage | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G12 | Used by GET /v1/coverage and getCoverage. |
| AP-DORPC-011 | suspend | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G20 | Shared handler with resume. |
| AP-DORPC-012 | resume | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G20 | Shared handler with suspend. |
| AP-DORPC-013 | count_terms | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G07 | Used by countLedgerRows. |
| AP-DORPC-014 | inspect_coverage | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G12 | Used by inspectCoverage. |
| AP-DORPC-015 | void_for_reversal | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G16 | Passes DB. |
| AP-DORPC-016 | release_held | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G21 |  |
| AP-DORPC-017 | recover_stranded_term | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G21 |  |
| AP-DORPC-018 | void_grant | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G21 |  |
| AP-DORPC-019 | open_awaiting_transfer | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G17 |  |
| AP-DORPC-020 | transfer_out | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G17 | Passes DB. |
| AP-DORPC-021 | transfer_in | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G17 | Passes DB. |
| AP-DORPC-022 | set_transfer_pending | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G17 |  |
| AP-DORPC-023 | rebuild_clinic_do | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G18 | Passes DB, R2, PLATFORM_SIGNING_KEY. Only kind allowed while recovery_state is building/blocked. |
| AP-DORPC-024 | refresh_coverage_snapshot | Durable Object RPC (POST https://quota-do.internal/rpc, kind field) | worker GatewayObject.fetch | G07 | Passes DB, R2; persists shipped alerts (AL-11/12/17/19) to platform_alert. |
| AP-DORPC-025 | GatewayObject.drainForHarness() | Durable Object RPC method (not fetch) | worker GatewayObject | G15 | Only when ENVIRONMENT=development and TEST_CLOCK=1; runs alarm, requires empty outbox, deletes alarm. |
| AP-DORPC-026 | GatewayObject.alarm() | Durable Object alarm handler | worker GatewayObject | G15 | Ships coverage outbox (shipCoverageOutboxAlarm); persists shipped alerts; if recovery_state is building/blocked, re-arms alarm 60 s later. |

## AP-ENTRY (54)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ENTRY-001 | drainDurableObjectsForHarness | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G15 | Internal/harness or cron-only entry (no operator auth). args installation_ids; harness only (error harness_drain_unavailable / harness_drain_invalid_installations). |
| AP-ENTRY-002 | registerOperatorCredential | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, assertion, attestation, credential_id. First credential bootstraps (raiseAl13Bootstrap); later ones need approval. |
| AP-ENTRY-003 | revokeOperatorCredential | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, credential_id. |
| AP-ENTRY-004 | listOperatorCredentials | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns active credentials (credential_id, public_key_cose, alg); promotes due credentials first. |
| AP-ENTRY-005 | registerIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid, public_key, not_before, not_after. |
| AP-ENTRY-006 | listIssuerKeys | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). |
| AP-ENTRY-007 | countLedgerRows | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns {terms, grants, installations}; calls DO count_terms per installation. |
| AP-ENTRY-008 | readLaunchState | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns channel_versions, environment, signing_key public half (kid, public_key) or null. |
| AP-ENTRY-009 | retireIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-010 | revokeIssuerKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-011 | registerServiceKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid, public_key, not_before, not_after (service key e.g. ABO). |
| AP-ENTRY-012 | revokeServiceKey | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args access_jwt, kid. |
| AP-ENTRY-013 | listServiceKeys | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). |
| AP-ENTRY-014 | publishPlanVersion | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args plan_id, version, display_name, capabilities, max_cost_class, concurrency_limit, max_allowance_per_month. |
| AP-ENTRY-015 | retirePlanVersion | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args plan_id, version. |
| AP-ENTRY-016 | setCeilingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args per_grant_max_days, per_grant_max_allowance_months, window_days, window_max_days, window_max_allowance_months, max_paid_grace_days, paid_cap_rule, operation. |
| AP-ENTRY-017 | grant | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G20 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Receives ABO-signed grant (envelope / envelope_b64 / envelope_json / grant_rpc_json, abo_kid, abo_signature); optional ceiling_override_operation (HP assertion for complimentary override); accepted_command_dispatch/accepted_command_grant_id used by the 5-minute dispatcher. Applies grant via DO apply_grant; writes grant_claim, grant_ledger, etc. |
| AP-ENTRY-018 | beginTransfer | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G20 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args org_id, from_installation_id, reason, operation, signer_credential_id. |
| AP-ENTRY-019 | transferOut | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args transfer_id. |
| AP-ENTRY-020 | transferIn | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args transfer_id. |
| AP-ENTRY-021 | deleteInstallation | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G20 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args org_id, reason, operation, signer_credential_id; transient detail deletion_pending. |
| AP-ENTRY-022 | voidForReversal | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). ABO-signed reversal (abo_kid, abo_signature); args reversal_id, grant_id, partial, reason, evidence_sha256. |
| AP-ENTRY-023 | releaseHeld | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G21 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args grant_id, reason, operation. |
| AP-ENTRY-024 | recoverStrandedTerm | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G21 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args action_id, org_id, installation_id, binding_epoch, target_term_id, source_grant_id, expected_clinic_seq, reason, evidence_sha256, operation, signer_credential_id. |
| AP-ENTRY-025 | voidGrant | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G21 | METHOD_CLASS HP: Cloudflare Access JWT (args.access_jwt) plus WebAuthn operator assertion (assertion, operation, signer_credential_id). args grant_id, reason, operation. |
| AP-ENTRY-026 | listGrantsForVoid | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G21 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args credential_id, window (list helper for voidGrant). |
| AP-ENTRY-027 | suspend | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G20 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id, reason; Access JWT required; calls DO suspend then updates installation.status via setInstallationSuspendedAction. |
| AP-ENTRY-028 | resume | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G20 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id, reason; calls DO resume then installation.status. |
| AP-ENTRY-029 | inspectCoverage | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. (not in METHOD_CLASS) args access_jwt, org_id; calls DO inspect_coverage. |
| AP-ENTRY-030 | getCoverage | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args org_id, installation_id; calls DO read_coverage. |
| AP-ENTRY-031 | listGrants | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args org_id, source_kind, applied_from, applied_to, credential_id. |
| AP-ENTRY-032 | readCoverageEvents | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). args after, limit; reads coverage_event. |
| AP-ENTRY-033 | publishRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args document; control/routing-policy action (writes R2 + routing_policy). |
| AP-ENTRY-034 | canaryRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, installation_ids, cohort_name. |
| AP-ENTRY-035 | promoteRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, expected_generation. |
| AP-ENTRY-036 | rollbackRoutingPolicy | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args policy_id, version, expected_generation. |
| AP-ENTRY-037 | armKillSwitch | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args scope (global\|capability\|installation\|provider), target; writes AL-19 alert. |
| AP-ENTRY-038 | disarmKillSwitch | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args scope, target; writes AL-19 alert. |
| AP-ENTRY-039 | deprecateCapability | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, successor_id. |
| AP-ENTRY-040 | retireCapability | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version. |
| AP-ENTRY-041 | beginTokenContractRotation | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. No args; adds an accepted AAT ver. |
| AP-ENTRY-042 | retireTokenContract | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args ver. |
| AP-ENTRY-043 | activateCohort | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, cohort_name, installation_ids. |
| AP-ENTRY-044 | promoteCohort | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args capability_id, capability_version, cohort_name. |
| AP-ENTRY-045 | rebuildClinicDo | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G18 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args installation_id; runs DO rebuild_clinic_do. |
| AP-ENTRY-046 | rebuildGrantLedger | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G18 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. Rebuilds grant_ledger rows from R2 grant-ledger objects. |
| AP-ENTRY-047 | refreshCoverageSnapshot | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args installation_id. |
| AP-ENTRY-048 | recordOperatorAction | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args action, subject, action_id; idempotent by action_id; writes control_audit. |
| AP-ENTRY-049 | supportLookup | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G19 | METHOD_CLASS H: Cloudflare Access JWT (args.access_jwt) only. args reference \|subscription_ref \|org_id, limit (1..100), cursor; writes control_audit; reads ai_request/ai_attempt/R2 envelope. |
| AP-ENTRY-050 | feedConsumerHealth | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | METHOD_CLASS M: machine caller over the service binding; no per-call operator credential (access_jwt/assertion not required unless noted). Returns last_pull_at, last_cursor of feed_consumer 'backend-feed'. |
| AP-ENTRY-051 | dispatchAcceptedGrantCommands | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G06 | Internal/harness or cron-only entry (no operator auth). Called by cron */5; no args; returns count; dispatches grant_claim rows with command_state=accepted, up to 25. |
| AP-ENTRY-052 | dispatchAcceptedTransferPreparations | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G17 | Internal/harness or cron-only entry (no operator auth). Called by cron */5; up to 25. |
| AP-ENTRY-053 | dispatchDeletionCommands | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G15 | Internal/harness or cron-only entry (no operator auth). Called by cron */5; up to 25. |
| AP-ENTRY-054 | shipDueReversalExports | Service-binding RPC method (VendorEntrypoint) | vendor/entrypoint | G16 | Internal/harness or cron-only entry (no operator auth). Called by cron */5; ships reversal_command export_payload to R2 grant-ledger/{grant_id}.void.ndjson; up to 25. |

## AP-D1 (501)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-D1-001 | ai_attempt | table | migrations | G11 | One provider attempt per ai_request (provider, model, outcome, latency, tokens, cost). |
| AP-D1-002 | ai_attempt.attempt_id | column | migrations; ai_attempt | G08 | TEXT, PK1, NOT NULL |
| AP-D1-003 | ai_attempt.request_id | column | migrations; ai_attempt | G08 | TEXT, NOT NULL |
| AP-D1-004 | ai_attempt.attempt_no | column | migrations; ai_attempt | G08 | INTEGER, NOT NULL |
| AP-D1-005 | ai_attempt.provider | column | migrations; ai_attempt | G11 | TEXT, NOT NULL |
| AP-D1-006 | ai_attempt.model | column | migrations; ai_attempt | G08 | TEXT, NOT NULL |
| AP-D1-007 | ai_attempt.outcome | column | migrations; ai_attempt | G08 | TEXT, NOT NULL |
| AP-D1-008 | ai_attempt.latency_ms | column | migrations; ai_attempt | G08 | INTEGER, NOT NULL |
| AP-D1-009 | ai_attempt.tokens_in | column | migrations; ai_attempt | G08 | INTEGER, NOT NULL |
| AP-D1-010 | ai_attempt.tokens_out | column | migrations; ai_attempt | G08 | INTEGER, NOT NULL |
| AP-D1-011 | ai_attempt.cost | column | migrations; ai_attempt | G10 | REAL, NOT NULL |
| AP-D1-012 | ai_attempt.provider_request_id | column | migrations; ai_attempt | G11 | TEXT |
| AP-D1-013 | ai_attempt.error_code | column | migrations; ai_attempt | G08 | TEXT |
| AP-D1-014 | ai_request | table | migrations | G07 | Request journal row; state, identity, capability, routing, payload pointer (R2), accounting fields. |
| AP-D1-015 | ai_request.request_id | column | migrations; ai_request | G08 | TEXT, PK1, NOT NULL |
| AP-D1-016 | ai_request.request_reference | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-017 | ai_request.installation_id | column | migrations; ai_request | G02 | TEXT, NOT NULL |
| AP-D1-018 | ai_request.actor_id | column | migrations; ai_request | G01 | TEXT, NOT NULL |
| AP-D1-019 | ai_request.branch_id | column | migrations; ai_request | G01 | TEXT |
| AP-D1-020 | ai_request.capability_id | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-021 | ai_request.capability_version | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-022 | ai_request.prompt_artifact_hash | column | migrations; ai_request | G10 | TEXT, NOT NULL |
| AP-D1-023 | ai_request.idempotency_key | column | migrations; ai_request | G04 | TEXT, NOT NULL |
| AP-D1-024 | ai_request.state | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-025 | ai_request.created_at | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-026 | ai_request.updated_at | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-027 | ai_request.completed_at | column | migrations; ai_request | G08 | TEXT |
| AP-D1-028 | ai_request.terminal_error_code | column | migrations; ai_request | G08 | TEXT |
| AP-D1-029 | ai_request.trace_id | column | migrations; ai_request | G08 | TEXT, NOT NULL |
| AP-D1-030 | ai_request.payload_pointer | column | migrations; ai_request | G08 | TEXT |
| AP-D1-031 | ai_request.routing_tier | column | migrations; ai_request | G08 | TEXT |
| AP-D1-032 | ai_request.routing_decision | column | migrations; ai_request | G08 | TEXT |
| AP-D1-033 | ai_request.conversation_id | column | migrations; ai_request | G08 | TEXT |
| AP-D1-034 | ai_request.turn_ordinal | column | migrations; ai_request | G08 | INTEGER |
| AP-D1-035 | ai_request.request_fingerprint | column | migrations; ai_request | G08 | TEXT |
| AP-D1-036 | ai_request.accounting_mode | column | migrations; ai_request | G08 | TEXT |
| AP-D1-037 | ai_request.accounting_term_id | column | migrations; ai_request | G08 | TEXT |
| AP-D1-038 | ai_request.accounting_request_id | column | migrations; ai_request | G08 | TEXT |
| AP-D1-039 | ai_request.accounting_quota_weight | column | migrations; ai_request | G12 | INTEGER |
| AP-D1-040 | ai_request.accounting_outcome | column | migrations; ai_request | G08 | TEXT |
| AP-D1-041 | ai_request.accounting_state | column | migrations; ai_request | G08 | TEXT |
| AP-D1-042 | ai_request.accounting_receipt_acknowledged | column | migrations; ai_request | G06 | INTEGER, NOT NULL, default 0 |
| AP-D1-043 | assertion_used | table | migrations | G19 | Replay guard: WebAuthn operator challenge hashes already consumed. |
| AP-D1-044 | assertion_used.challenge_sha256 | column | migrations; assertion_used | G19 | TEXT, PK1, NOT NULL |
| AP-D1-045 | assertion_used.credential_id | column | migrations; assertion_used | G19 | TEXT, NOT NULL |
| AP-D1-046 | assertion_used.used_at | column | migrations; assertion_used | G19 | TEXT, NOT NULL |
| AP-D1-047 | capability_grant | table | migrations | G23 | Capability grants and global-scope lifecycle overlay (deprecate/retire/cohort). |
| AP-D1-048 | capability_grant.grant_id | column | migrations; capability_grant | G06 | TEXT, PK1, NOT NULL |
| AP-D1-049 | capability_grant.scope | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-050 | capability_grant.capability_id | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-051 | capability_grant.capability_version | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-052 | capability_grant.granted_at | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-053 | capability_grant.revoked_at | column | migrations; capability_grant | G06 | TEXT |
| AP-D1-054 | capability_grant.changed_at | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-055 | capability_grant.changed_by | column | migrations; capability_grant | G06 | TEXT, NOT NULL |
| AP-D1-056 | capability_grant.lifecycle_state | column | migrations; capability_grant | G06 | TEXT |
| AP-D1-057 | capability_grant.successor_id | column | migrations; capability_grant | G06 | TEXT |
| AP-D1-058 | capability_grant.deprecated_at | column | migrations; capability_grant | G06 | TEXT |
| AP-D1-059 | capability_grant.retire_after | column | migrations; capability_grant | G06 | TEXT |
| AP-D1-060 | ceiling_policy | table | migrations | G20 | Versioned ceiling numbers for complimentary/paid grants. |
| AP-D1-061 | ceiling_policy.version | column | migrations; ceiling_policy | G19 | INTEGER, PK1, NOT NULL |
| AP-D1-062 | ceiling_policy.per_grant_max_days | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-063 | ceiling_policy.per_grant_max_allowance_months | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-064 | ceiling_policy.window_days | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-065 | ceiling_policy.window_max_days | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-066 | ceiling_policy.window_max_allowance_months | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-067 | ceiling_policy.max_paid_grace_days | column | migrations; ceiling_policy | G19 | INTEGER, NOT NULL |
| AP-D1-068 | ceiling_policy.paid_cap_rule | column | migrations; ceiling_policy | G19 | TEXT, NOT NULL |
| AP-D1-069 | ceiling_policy.set_by | column | migrations; ceiling_policy | G19 | TEXT, NOT NULL |
| AP-D1-070 | ceiling_policy.assertion_sha256 | column | migrations; ceiling_policy | G19 | TEXT, NOT NULL |
| AP-D1-071 | ceiling_policy_command | table | migrations | G19 | Accepted ceiling-policy commands keyed by challenge hash (immutable). |
| AP-D1-072 | ceiling_policy_command.challenge_sha256 | column | migrations; ceiling_policy_command | G19 | TEXT, PK1, NOT NULL |
| AP-D1-073 | ceiling_policy_command.policy_version | column | migrations; ceiling_policy_command | G19 | INTEGER, NOT NULL |
| AP-D1-074 | ceiling_policy_command.actor | column | migrations; ceiling_policy_command | G19 | TEXT, NOT NULL |
| AP-D1-075 | ceiling_policy_command.operation_json | column | migrations; ceiling_policy_command | G19 | TEXT, NOT NULL |
| AP-D1-076 | ceiling_policy_command.contract_version | column | migrations; ceiling_policy_command | G19 | INTEGER, NOT NULL |
| AP-D1-077 | ceiling_policy_command.result_json | column | migrations; ceiling_policy_command | G19 | TEXT, NOT NULL |
| AP-D1-078 | ceiling_policy_command.created_at | column | migrations; ceiling_policy_command | G19 | TEXT, NOT NULL |
| AP-D1-079 | complimentary_ceiling_claim | table | migrations | G20 | Per-grant reservation against the ceiling policy; status pending\|applied\|sealed_no_effect. |
| AP-D1-080 | complimentary_ceiling_claim.grant_id | column | migrations; complimentary_ceiling_claim | G20 | TEXT, PK1, NOT NULL |
| AP-D1-081 | complimentary_ceiling_claim.org_id | column | migrations; complimentary_ceiling_claim | G20 | TEXT, NOT NULL |
| AP-D1-082 | complimentary_ceiling_claim.envelope_sha256 | column | migrations; complimentary_ceiling_claim | G20 | TEXT, NOT NULL |
| AP-D1-083 | complimentary_ceiling_claim.plan_id | column | migrations; complimentary_ceiling_claim | G20 | TEXT, NOT NULL |
| AP-D1-084 | complimentary_ceiling_claim.plan_version | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL |
| AP-D1-085 | complimentary_ceiling_claim.allowance_denominator | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL |
| AP-D1-086 | complimentary_ceiling_claim.day_contribution | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL |
| AP-D1-087 | complimentary_ceiling_claim.allowance_contribution | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL |
| AP-D1-088 | complimentary_ceiling_claim.apply_per_grant_caps | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL |
| AP-D1-089 | complimentary_ceiling_claim.source_reconciled | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL, default 0 |
| AP-D1-090 | complimentary_ceiling_claim.override_authorized | column | migrations; complimentary_ceiling_claim | G20 | INTEGER, NOT NULL, default 0 |
| AP-D1-091 | complimentary_ceiling_claim.status | column | migrations; complimentary_ceiling_claim | G20 | TEXT, NOT NULL |
| AP-D1-092 | complimentary_ceiling_claim.receipt | column | migrations; complimentary_ceiling_claim | G20 | TEXT |
| AP-D1-093 | complimentary_ceiling_claim.applied_at | column | migrations; complimentary_ceiling_claim | G20 | TEXT |
| AP-D1-094 | complimentary_ceiling_claim.created_at | column | migrations; complimentary_ceiling_claim | G20 | TEXT, NOT NULL |
| AP-D1-095 | complimentary_ceiling_claim_backfill | table | migrations | G20 | Marker that an org's historical claims were reconciled. |
| AP-D1-096 | complimentary_ceiling_claim_backfill.org_id | column | migrations; complimentary_ceiling_claim_backfill | G20 | TEXT, PK1, NOT NULL |
| AP-D1-097 | complimentary_ceiling_claim_backfill.completed_at | column | migrations; complimentary_ceiling_claim_backfill | G20 | TEXT, NOT NULL |
| AP-D1-098 | control_audit | table | migrations | G08 | Operator/control action audit log. |
| AP-D1-099 | control_audit.audit_id | column | migrations; control_audit | G08 | TEXT, PK1, NOT NULL |
| AP-D1-100 | control_audit.operator_id | column | migrations; control_audit | G08 | TEXT, NOT NULL |
| AP-D1-101 | control_audit.action | column | migrations; control_audit | G08 | TEXT, NOT NULL |
| AP-D1-102 | control_audit.target | column | migrations; control_audit | G08 | TEXT, NOT NULL |
| AP-D1-103 | control_audit.before_pointer | column | migrations; control_audit | G08 | TEXT |
| AP-D1-104 | control_audit.after_pointer | column | migrations; control_audit | G08 | TEXT |
| AP-D1-105 | control_audit.recorded_at | column | migrations; control_audit | G08 | TEXT, NOT NULL |
| AP-D1-106 | control_audit.actor | column | migrations; control_audit | G01 | TEXT |
| AP-D1-107 | control_audit.assertion_sha256 | column | migrations; control_audit | G19 | TEXT |
| AP-D1-108 | coverage_event | table | migrations | G07 | Ordered coverage events shipped from the Durable Object; source of GET /v1/feed/coverage (feed_seq autoincrement; no update/delete). |
| AP-D1-109 | coverage_event.feed_seq | column | migrations; coverage_event | G08 | INTEGER, PK1, NOT NULL |
| AP-D1-110 | coverage_event.event_id | column | migrations; coverage_event | G08 | TEXT, NOT NULL |
| AP-D1-111 | coverage_event.org_id | column | migrations; coverage_event | G08 | TEXT, NOT NULL |
| AP-D1-112 | coverage_event.installation_id | column | migrations; coverage_event | G02 | TEXT, NOT NULL |
| AP-D1-113 | coverage_event.binding_epoch | column | migrations; coverage_event | G08 | INTEGER, NOT NULL |
| AP-D1-114 | coverage_event.clinic_seq | column | migrations; coverage_event | G08 | INTEGER, NOT NULL |
| AP-D1-115 | coverage_event.kind | column | migrations; coverage_event | G08 | TEXT, NOT NULL |
| AP-D1-116 | coverage_event.snapshot | column | migrations; coverage_event | G08 | TEXT, NOT NULL |
| AP-D1-117 | coverage_event.at | column | migrations; coverage_event | G08 | TEXT, NOT NULL |
| AP-D1-118 | coverage_mirror | table | migrations | G02 | Per-installation mirror of Durable Object coverage state. |
| AP-D1-119 | coverage_mirror.installation_id | column | migrations; coverage_mirror | G02 | TEXT, PK1, NOT NULL |
| AP-D1-120 | coverage_mirror.org_id | column | migrations; coverage_mirror | G08 | TEXT, NOT NULL |
| AP-D1-121 | coverage_mirror.binding_epoch | column | migrations; coverage_mirror | G08 | INTEGER, NOT NULL |
| AP-D1-122 | coverage_mirror.clinic_seq | column | migrations; coverage_mirror | G08 | INTEGER, NOT NULL |
| AP-D1-123 | coverage_mirror.state | column | migrations; coverage_mirror | G08 | TEXT, NOT NULL |
| AP-D1-124 | coverage_mirror.suspended | column | migrations; coverage_mirror | G20 | INTEGER, NOT NULL |
| AP-D1-125 | coverage_mirror.hard_stop_at | column | migrations; coverage_mirror | G08 | TEXT |
| AP-D1-126 | coverage_mirror.term_snapshot | column | migrations; coverage_mirror | G08 | TEXT, NOT NULL |
| AP-D1-127 | deletion_command | table | migrations | G20 | Accepted installation-deletion commands and their phases (accepted\|frozen\|completed). |
| AP-D1-128 | deletion_command.assertion_sha256 | column | migrations; deletion_command | G19 | TEXT, PK1, NOT NULL |
| AP-D1-129 | deletion_command.freeze_id | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-130 | deletion_command.org_id | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-131 | deletion_command.installation_id | column | migrations; deletion_command | G02 | TEXT, NOT NULL |
| AP-D1-132 | deletion_command.binding_epoch | column | migrations; deletion_command | G08 | INTEGER, NOT NULL |
| AP-D1-133 | deletion_command.reason | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-134 | deletion_command.accepted_actor | column | migrations; deletion_command | G13 | TEXT, NOT NULL |
| AP-D1-135 | deletion_command.signer_credential_id | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-136 | deletion_command.accepted_command | column | migrations; deletion_command | G13 | TEXT, NOT NULL |
| AP-D1-137 | deletion_command.phase | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-138 | deletion_command.freeze_inventory | column | migrations; deletion_command | G08 | TEXT |
| AP-D1-139 | deletion_command.freeze_ack_at | column | migrations; deletion_command | G08 | TEXT |
| AP-D1-140 | deletion_command.retained_term_ids | column | migrations; deletion_command | G08 | TEXT |
| AP-D1-141 | deletion_command.held | column | migrations; deletion_command | G08 | INTEGER |
| AP-D1-142 | deletion_command.alert_due | column | migrations; deletion_command | G15 | INTEGER, NOT NULL, default 0 |
| AP-D1-143 | deletion_command.purge_state | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-144 | deletion_command.completion_detail | column | migrations; deletion_command | G08 | TEXT |
| AP-D1-145 | deletion_command.due_at | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-146 | deletion_command.lease_until | column | migrations; deletion_command | G06 | TEXT |
| AP-D1-147 | deletion_command.created_at | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-148 | deletion_command.updated_at | column | migrations; deletion_command | G08 | TEXT, NOT NULL |
| AP-D1-149 | fallback_admission | table | migrations | G11 | Durable record of admissions made while the Durable Object was unavailable (outage fallback). |
| AP-D1-150 | fallback_admission.installation_id | column | migrations; fallback_admission | G11 | TEXT, PK1, NOT NULL |
| AP-D1-151 | fallback_admission.idempotency_key | column | migrations; fallback_admission | G04 | TEXT, PK2, NOT NULL |
| AP-D1-152 | fallback_admission.term_id | column | migrations; fallback_admission | G11 | TEXT, NOT NULL |
| AP-D1-153 | fallback_admission.request_id | column | migrations; fallback_admission | G11 | TEXT, NOT NULL |
| AP-D1-154 | fallback_admission.weight | column | migrations; fallback_admission | G11 | INTEGER, NOT NULL |
| AP-D1-155 | fallback_admission.admitted_at | column | migrations; fallback_admission | G11 | TEXT, NOT NULL |
| AP-D1-156 | fallback_admission.state | column | migrations; fallback_admission | G11 | TEXT, NOT NULL |
| AP-D1-157 | fallback_admission.jti | column | migrations; fallback_admission | G03 | TEXT |
| AP-D1-158 | fallback_admission.actor_id | column | migrations; fallback_admission | G11 | TEXT |
| AP-D1-159 | fallback_admission.branch_id | column | migrations; fallback_admission | G11 | TEXT |
| AP-D1-160 | fallback_admission.capability_id | column | migrations; fallback_admission | G08 | TEXT |
| AP-D1-161 | fallback_admission.request_fingerprint | column | migrations; fallback_admission | G11 | TEXT |
| AP-D1-162 | fallback_admission.plan_snapshot | column | migrations; fallback_admission | G11 | TEXT |
| AP-D1-163 | feed_consumer | table | migrations | G07 | Last pull time and cursor of the coverage feed consumer (consumer 'backend-feed'). |
| AP-D1-164 | feed_consumer.consumer | column | migrations; feed_consumer | G08 | TEXT, PK1, NOT NULL |
| AP-D1-165 | feed_consumer.last_pull_at | column | migrations; feed_consumer | G08 | TEXT |
| AP-D1-166 | feed_consumer.last_cursor | column | migrations; feed_consumer | G08 | INTEGER |
| AP-D1-167 | grant_claim | table | migrations | G06 | Global grant identity, route, accepted command and lease state (state pending\|completed\|disputed; command_state none\|accepted\|completed\|rejected). |
| AP-D1-168 | grant_claim.grant_id | column | migrations; grant_claim | G06 | TEXT, PK1, NOT NULL |
| AP-D1-169 | grant_claim.org_id | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-170 | grant_claim.source_kind | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-171 | grant_claim.envelope | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-172 | grant_claim.envelope_sha256 | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-173 | grant_claim.installation_id | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-174 | grant_claim.binding_epoch | column | migrations; grant_claim | G06 | INTEGER, NOT NULL |
| AP-D1-175 | grant_claim.route_generation | column | migrations; grant_claim | G06 | INTEGER, NOT NULL |
| AP-D1-176 | grant_claim.state | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-177 | grant_claim.receipt | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-178 | grant_claim.created_at | column | migrations; grant_claim | G06 | TEXT, NOT NULL |
| AP-D1-179 | grant_claim.completed_at | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-180 | grant_claim.accepted_command | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-181 | grant_claim.accepted_actor | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-182 | grant_claim.signer_credential_id | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-183 | grant_claim.assertion_sha256 | column | migrations; grant_claim | G19 | TEXT |
| AP-D1-184 | grant_claim.override_assertion_sha256 | column | migrations; grant_claim | G19 | TEXT |
| AP-D1-185 | grant_claim.accepted_contract_version | column | migrations; grant_claim | G06 | INTEGER |
| AP-D1-186 | grant_claim.accepted_ceiling_policy_version | column | migrations; grant_claim | G19 | INTEGER |
| AP-D1-187 | grant_claim.plan_snapshot | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-188 | grant_claim.accepted_at | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-189 | grant_claim.due_at | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-190 | grant_claim.lease_token | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-191 | grant_claim.lease_until | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-192 | grant_claim.dispatch_attempts | column | migrations; grant_claim | G06 | INTEGER, NOT NULL, default 0 |
| AP-D1-193 | grant_claim.command_state | column | migrations; grant_claim | G06 | TEXT, NOT NULL, default 'none' |
| AP-D1-194 | grant_claim.terminal_code | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-195 | grant_claim.terminal_detail | column | migrations; grant_claim | G06 | TEXT |
| AP-D1-196 | grant_claim_backfill | table | migrations | G06 | Marker that an org's grant claims were reconciled. |
| AP-D1-197 | grant_claim_backfill.org_id | column | migrations; grant_claim_backfill | G06 | TEXT, PK1, NOT NULL |
| AP-D1-198 | grant_claim_backfill.completed_at | column | migrations; grant_claim_backfill | G06 | TEXT, NOT NULL |
| AP-D1-199 | grant_claim_dispute | table | migrations | G06 | Counter of disputed claims per grant. |
| AP-D1-200 | grant_claim_dispute.grant_id | column | migrations; grant_claim_dispute | G06 | TEXT, PK1, NOT NULL |
| AP-D1-201 | grant_claim_dispute.org_id | column | migrations; grant_claim_dispute | G06 | TEXT, NOT NULL |
| AP-D1-202 | grant_claim_dispute.reason | column | migrations; grant_claim_dispute | G06 | TEXT, NOT NULL |
| AP-D1-203 | grant_claim_dispute.first_at | column | migrations; grant_claim_dispute | G06 | TEXT, NOT NULL |
| AP-D1-204 | grant_claim_dispute.last_at | column | migrations; grant_claim_dispute | G06 | TEXT, NOT NULL |
| AP-D1-205 | grant_claim_dispute.count | column | migrations; grant_claim_dispute | G06 | INTEGER, NOT NULL |
| AP-D1-206 | grant_ledger | table | migrations | G06 | Applied-grant ledger shipped from the Durable Object (no update/delete). |
| AP-D1-207 | grant_ledger.grant_id | column | migrations; grant_ledger | G06 | TEXT, PK1, NOT NULL |
| AP-D1-208 | grant_ledger.origin_grant_id | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-209 | grant_ledger.org_id | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-210 | grant_ledger.installation_id | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-211 | grant_ledger.kind | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-212 | grant_ledger.source_kind | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-213 | grant_ledger.operator_credential_id | column | migrations; grant_ledger | G17 | TEXT, NOT NULL |
| AP-D1-214 | grant_ledger.envelope_sha256 | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-215 | grant_ledger.receipt | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-216 | grant_ledger.applied_at | column | migrations; grant_ledger | G06 | TEXT, NOT NULL |
| AP-D1-217 | grant_ledger.operator_email | column | migrations; grant_ledger | G06 | TEXT |
| AP-D1-218 | grant_tombstone | table | migrations | G16 | Tombstone and export payload for a reversed grant (no update/delete). |
| AP-D1-219 | grant_tombstone.grant_id | column | migrations; grant_tombstone | G06 | TEXT, PK1, NOT NULL |
| AP-D1-220 | grant_tombstone.reversal_id | column | migrations; grant_tombstone | G16 | TEXT, NOT NULL |
| AP-D1-221 | grant_tombstone.request_sha256 | column | migrations; grant_tombstone | G06 | TEXT, NOT NULL |
| AP-D1-222 | grant_tombstone.receipt | column | migrations; grant_tombstone | G06 | TEXT, NOT NULL |
| AP-D1-223 | grant_tombstone.export_payload | column | migrations; grant_tombstone | G06 | TEXT, NOT NULL |
| AP-D1-224 | grant_tombstone.created_at | column | migrations; grant_tombstone | G06 | TEXT, NOT NULL |
| AP-D1-225 | grant_void | table | migrations | G06 | Void records for grants (no update/delete). |
| AP-D1-226 | grant_void.grant_id | column | migrations; grant_void | G21 | TEXT, PK1, NOT NULL |
| AP-D1-227 | grant_void.reason | column | migrations; grant_void | G06 | TEXT, NOT NULL |
| AP-D1-228 | grant_void.source | column | migrations; grant_void | G06 | TEXT, NOT NULL |
| AP-D1-229 | grant_void.evidence_sha256 | column | migrations; grant_void | G06 | TEXT, NOT NULL |
| AP-D1-230 | grant_void.at | column | migrations; grant_void | G06 | TEXT, NOT NULL |
| AP-D1-231 | installation | table | migrations | G08 | Enrolled installation (created lazily on first valid AI token for an org, or by control plane). |
| AP-D1-232 | installation.installation_id | column | migrations; installation | G02 | TEXT, PK1, NOT NULL |
| AP-D1-233 | installation.org_id | column | migrations; installation | G02 | TEXT, NOT NULL |
| AP-D1-234 | installation.display_name | column | migrations; installation | G02 | TEXT, NOT NULL |
| AP-D1-235 | installation.status | column | migrations; installation | G13 | TEXT, NOT NULL |
| AP-D1-236 | installation.region | column | migrations; installation | G02 | TEXT, NOT NULL |
| AP-D1-237 | installation.enrolled_at | column | migrations; installation | G02 | TEXT, NOT NULL |
| AP-D1-238 | issuer_key | table | migrations | G17 | Public keys (kid) used to verify AI tokens and feed JWTs; status active\|retiring\|revoked. |
| AP-D1-239 | issuer_key.kid | column | migrations; issuer_key | G17 | TEXT, PK1, NOT NULL |
| AP-D1-240 | issuer_key.issuer | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-241 | issuer_key.public_key | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-242 | issuer_key.status | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-243 | issuer_key.not_before | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-244 | issuer_key.not_after | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-245 | issuer_key.registered_by | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-246 | issuer_key.assertion_sha256 | column | migrations; issuer_key | G17 | TEXT, NOT NULL |
| AP-D1-247 | kill_switch | table | migrations | G23 | Kill switch rows keyed by scope (global\|capability\|installation\|provider) and target. |
| AP-D1-248 | kill_switch.scope | column | migrations; kill_switch | G23 | TEXT, PK1, NOT NULL |
| AP-D1-249 | kill_switch.target | column | migrations; kill_switch | G23 | TEXT, PK2, NOT NULL |
| AP-D1-250 | kill_switch.active | column | migrations; kill_switch | G23 | INTEGER, NOT NULL |
| AP-D1-251 | kill_switch.changed_at | column | migrations; kill_switch | G23 | TEXT, NOT NULL |
| AP-D1-252 | kill_switch.changed_by | column | migrations; kill_switch | G23 | TEXT, NOT NULL |
| AP-D1-253 | live_value_route | table | migrations | G06 | Current route state of a grant's value: stable\|moving\|voiding\|retired. |
| AP-D1-254 | live_value_route.grant_id | column | migrations; live_value_route | G06 | TEXT, PK1, NOT NULL |
| AP-D1-255 | live_value_route.org_id | column | migrations; live_value_route | G11 | TEXT, NOT NULL |
| AP-D1-256 | live_value_route.installation_id | column | migrations; live_value_route | G11 | TEXT, NOT NULL |
| AP-D1-257 | live_value_route.binding_epoch | column | migrations; live_value_route | G11 | INTEGER, NOT NULL |
| AP-D1-258 | live_value_route.generation | column | migrations; live_value_route | G11 | INTEGER, NOT NULL |
| AP-D1-259 | live_value_route.state | column | migrations; live_value_route | G11 | TEXT, NOT NULL |
| AP-D1-260 | live_value_route.transfer_id | column | migrations; live_value_route | G17 | TEXT |
| AP-D1-261 | live_value_route.reversal_id | column | migrations; live_value_route | G16 | TEXT |
| AP-D1-262 | live_value_route.updated_at | column | migrations; live_value_route | G11 | TEXT, NOT NULL |
| AP-D1-263 | operator_credential | table | migrations | G17 | Operator WebAuthn credentials (public_key_cose, status, activation). |
| AP-D1-264 | operator_credential.credential_id | column | migrations; operator_credential | G17 | TEXT, PK1, NOT NULL |
| AP-D1-265 | operator_credential.operator_email | column | migrations; operator_credential | G17 | TEXT, NOT NULL |
| AP-D1-266 | operator_credential.public_key_cose | column | migrations; operator_credential | G17 | TEXT, NOT NULL |
| AP-D1-267 | operator_credential.alg | column | migrations; operator_credential | G17 | TEXT, NOT NULL |
| AP-D1-268 | operator_credential.status | column | migrations; operator_credential | G17 | TEXT, NOT NULL |
| AP-D1-269 | operator_credential.activates_at | column | migrations; operator_credential | G17 | TEXT, NOT NULL |
| AP-D1-270 | operator_credential.approved_by | column | migrations; operator_credential | G17 | TEXT |
| AP-D1-271 | operator_credential.revoked_by | column | migrations; operator_credential | G17 | TEXT |
| AP-D1-272 | plan_version | table | migrations | G19 | Published plan versions (capabilities, limits, status). |
| AP-D1-273 | plan_version.plan_id | column | migrations; plan_version | G19 | TEXT, PK1, NOT NULL |
| AP-D1-274 | plan_version.version | column | migrations; plan_version | G19 | INTEGER, PK2, NOT NULL |
| AP-D1-275 | plan_version.display_name | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-276 | plan_version.capabilities | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-277 | plan_version.max_cost_class | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-278 | plan_version.concurrency_limit | column | migrations; plan_version | G19 | INTEGER, NOT NULL |
| AP-D1-279 | plan_version.max_allowance_per_month | column | migrations; plan_version | G19 | INTEGER, NOT NULL |
| AP-D1-280 | plan_version.status | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-281 | plan_version.published_by | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-282 | plan_version.assertion_sha256 | column | migrations; plan_version | G19 | TEXT, NOT NULL |
| AP-D1-283 | platform_alert | table | migrations | G06 | Durable platform alerts with leased email delivery and backoff state. |
| AP-D1-284 | platform_alert.alert_key | column | migrations; platform_alert | G15 | TEXT, PK1, NOT NULL |
| AP-D1-285 | platform_alert.code | column | migrations; platform_alert | G15 | TEXT, NOT NULL |
| AP-D1-286 | platform_alert.severity | column | migrations; platform_alert | G15 | TEXT, NOT NULL |
| AP-D1-287 | platform_alert.first_at | column | migrations; platform_alert | G15 | TEXT, NOT NULL |
| AP-D1-288 | platform_alert.last_at | column | migrations; platform_alert | G15 | TEXT, NOT NULL |
| AP-D1-289 | platform_alert.count | column | migrations; platform_alert | G15 | INTEGER, NOT NULL |
| AP-D1-290 | platform_alert.send_state | column | migrations; platform_alert | G15 | TEXT, NOT NULL |
| AP-D1-291 | platform_alert.next_send_at | column | migrations; platform_alert | G15 | TEXT |
| AP-D1-292 | platform_alert.resolved_at | column | migrations; platform_alert | G15 | TEXT |
| AP-D1-293 | platform_alert.body_json | column | migrations; platform_alert | G15 | TEXT |
| AP-D1-294 | platform_alert.body_state | column | migrations; platform_alert | G15 | TEXT, NOT NULL, default 'incomplete' |
| AP-D1-295 | platform_alert.channel_version | column | migrations; platform_alert | G15 | INTEGER |
| AP-D1-296 | platform_alert.origin_event_id | column | migrations; platform_alert | G15 | TEXT |
| AP-D1-297 | platform_alert.attempts | column | migrations; platform_alert | G15 | INTEGER, NOT NULL, default 0 |
| AP-D1-298 | platform_alert.lease_token | column | migrations; platform_alert | G06 | TEXT |
| AP-D1-299 | platform_alert.lease_expires_at | column | migrations; platform_alert | G06 | TEXT |
| AP-D1-300 | platform_counter | table | migrations | G08 | Guard rejection counters per time bucket and dimension set. |
| AP-D1-301 | platform_counter.counter_id | column | migrations; platform_counter | G08 | TEXT, PK1, NOT NULL |
| AP-D1-302 | platform_counter.dimension_set | column | migrations; platform_counter | G08 | TEXT, NOT NULL |
| AP-D1-303 | platform_counter.time_bucket | column | migrations; platform_counter | G08 | TEXT, NOT NULL |
| AP-D1-304 | platform_counter.count | column | migrations; platform_counter | G08 | INTEGER, NOT NULL |
| AP-D1-305 | reversal_command | table | migrations | G16 | Idempotent reversal commands, receipt and R2 export state (state due\|terminal). |
| AP-D1-306 | reversal_command.reversal_id | column | migrations; reversal_command | G16 | TEXT, PK1, NOT NULL |
| AP-D1-307 | reversal_command.grant_id | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-308 | reversal_command.request_sha256 | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-309 | reversal_command.request_body | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-310 | reversal_command.route_installation_id | column | migrations; reversal_command | G16 | TEXT |
| AP-D1-311 | reversal_command.route_epoch | column | migrations; reversal_command | G16 | INTEGER |
| AP-D1-312 | reversal_command.route_generation | column | migrations; reversal_command | G16 | INTEGER |
| AP-D1-313 | reversal_command.state | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-314 | reversal_command.receipt | column | migrations; reversal_command | G16 | TEXT |
| AP-D1-315 | reversal_command.export_payload | column | migrations; reversal_command | G16 | TEXT |
| AP-D1-316 | reversal_command.export_state | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-317 | reversal_command.created_at | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-318 | reversal_command.updated_at | column | migrations; reversal_command | G16 | TEXT, NOT NULL |
| AP-D1-319 | routing_policy | table | migrations | G24 | Routing policy versions; content in R2; status published\|canary\|active\|superseded |
| AP-D1-320 | routing_policy.policy_id | column | migrations; routing_policy | G24 | TEXT, PK1, NOT NULL |
| AP-D1-321 | routing_policy.version | column | migrations; routing_policy | G24 | TEXT, PK2, NOT NULL |
| AP-D1-322 | routing_policy.content_pointer | column | migrations; routing_policy | G24 | TEXT, NOT NULL |
| AP-D1-323 | routing_policy.active_from | column | migrations; routing_policy | G24 | TEXT, NOT NULL |
| AP-D1-324 | routing_policy.activated_by | column | migrations; routing_policy | G24 | TEXT, NOT NULL |
| AP-D1-325 | routing_policy.canary_installation_ids | column | migrations; routing_policy | G24 | TEXT |
| AP-D1-326 | routing_policy.status | column | migrations; routing_policy | G24 | TEXT, NOT NULL, default 'published' |
| AP-D1-327 | routing_policy.content_sha256 | column | migrations; routing_policy | G24 | TEXT |
| AP-D1-328 | routing_policy_activation | table | migrations | G24 | Activation generation and predecessor per policy_id. |
| AP-D1-329 | routing_policy_activation.policy_id | column | migrations; routing_policy_activation | G24 | TEXT, PK1 |
| AP-D1-330 | routing_policy_activation.generation | column | migrations; routing_policy_activation | G24 | INTEGER, NOT NULL, default 0 |
| AP-D1-331 | routing_policy_activation.active_version | column | migrations; routing_policy_activation | G24 | TEXT |
| AP-D1-332 | routing_policy_activation.predecessor_version | column | migrations; routing_policy_activation | G24 | TEXT |
| AP-D1-333 | routing_policy_activation.predecessor_state | column | migrations; routing_policy_activation | G24 | TEXT, NOT NULL, default 'unknown' |
| AP-D1-334 | service_key | table | migrations | G17 | Public keys for service callers (e.g. the ABO); status and validity window. |
| AP-D1-335 | service_key.kid | column | migrations; service_key | G17 | TEXT, PK1, NOT NULL |
| AP-D1-336 | service_key.service | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-337 | service_key.public_key | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-338 | service_key.status | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-339 | service_key.not_before | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-340 | service_key.not_after | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-341 | service_key.registered_by | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-342 | service_key.assertion_sha256 | column | migrations; service_key | G17 | TEXT, NOT NULL |
| AP-D1-343 | sqlite_sequence | table | migrations | G08 | SQLite internal AUTOINCREMENT bookkeeping (not application schema). |
| AP-D1-344 | sqlite_sequence.name | column | migrations; sqlite_sequence | G08 | untyped |
| AP-D1-345 | sqlite_sequence.seq | column | migrations; sqlite_sequence | G08 | untyped |
| AP-D1-346 | stranded_term_recovery | table | migrations | G06 | D1 copy of stranded-term recovery actions (also mirrored in the Durable Object). |
| AP-D1-347 | stranded_term_recovery.action_id | column | migrations; stranded_term_recovery | G08 | TEXT, PK1, NOT NULL |
| AP-D1-348 | stranded_term_recovery.org_id | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-349 | stranded_term_recovery.installation_id | column | migrations; stranded_term_recovery | G02 | TEXT, NOT NULL |
| AP-D1-350 | stranded_term_recovery.binding_epoch | column | migrations; stranded_term_recovery | G08 | INTEGER, NOT NULL |
| AP-D1-351 | stranded_term_recovery.target_term_id | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-352 | stranded_term_recovery.source_grant_id | column | migrations; stranded_term_recovery | G06 | TEXT, NOT NULL |
| AP-D1-353 | stranded_term_recovery.expected_clinic_seq | column | migrations; stranded_term_recovery | G08 | INTEGER, NOT NULL |
| AP-D1-354 | stranded_term_recovery.reason | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-355 | stranded_term_recovery.request_sha256 | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-356 | stranded_term_recovery.evidence_sha256 | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-357 | stranded_term_recovery.actor_email | column | migrations; stranded_term_recovery | G01 | TEXT, NOT NULL |
| AP-D1-358 | stranded_term_recovery.credential_id | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-359 | stranded_term_recovery.assertion_sha256 | column | migrations; stranded_term_recovery | G19 | TEXT, NOT NULL |
| AP-D1-360 | stranded_term_recovery.recovered_at | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-361 | stranded_term_recovery.result_json | column | migrations; stranded_term_recovery | G08 | TEXT, NOT NULL |
| AP-D1-362 | tenant_binding | table | migrations | G17 | Org to installation binding by epoch; status active\|held_for_transfer\|retired; first-tenant (epoch 1) creation capped by trigger. |
| AP-D1-363 | tenant_binding.org_id | column | migrations; tenant_binding | G02 | TEXT, PK1, NOT NULL |
| AP-D1-364 | tenant_binding.installation_id | column | migrations; tenant_binding | G02 | TEXT, NOT NULL |
| AP-D1-365 | tenant_binding.epoch | column | migrations; tenant_binding | G02 | INTEGER, PK2, NOT NULL |
| AP-D1-366 | tenant_binding.status | column | migrations; tenant_binding | G13 | TEXT, NOT NULL |
| AP-D1-367 | tenant_binding.retired_at | column | migrations; tenant_binding | G02 | TEXT |
| AP-D1-368 | tenant_binding.reason | column | migrations; tenant_binding | G02 | TEXT |
| AP-D1-369 | tenant_binding.created_at | column | migrations; tenant_binding | G02 | TEXT, NOT NULL |
| AP-D1-370 | token_contract | table | migrations | G24 | Accepted AAT 'ver' values; retired_at marks retired. |
| AP-D1-371 | token_contract.ver | column | migrations; token_contract | G24 | TEXT, PK1, NOT NULL |
| AP-D1-372 | token_contract.added_at | column | migrations; token_contract | G24 | TEXT, NOT NULL |
| AP-D1-373 | token_contract.retired_at | column | migrations; token_contract | G24 | TEXT |
| AP-D1-374 | token_contract.changed_by | column | migrations; token_contract | G24 | TEXT, NOT NULL |
| AP-D1-375 | transfer | table | migrations | G17 | Installation transfer record with package. |
| AP-D1-376 | transfer.transfer_id | column | migrations; transfer | G17 | TEXT, PK1, NOT NULL |
| AP-D1-377 | transfer.org_id | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-378 | transfer.from_installation_id | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-379 | transfer.to_installation_id | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-380 | transfer.reason | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-381 | transfer.assertion_sha256 | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-382 | transfer.package | column | migrations; transfer | G17 | TEXT |
| AP-D1-383 | transfer.created_at | column | migrations; transfer | G17 | TEXT, NOT NULL |
| AP-D1-384 | transfer_preparation | table | migrations | G17 | Transfer preparation phases accepted\|destination_ready\|source_frozen\|published\|completed. |
| AP-D1-385 | transfer_preparation.transfer_id | column | migrations; transfer_preparation | G17 | TEXT, PK1, NOT NULL |
| AP-D1-386 | transfer_preparation.org_id | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-387 | transfer_preparation.from_installation_id | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-388 | transfer_preparation.source_epoch | column | migrations; transfer_preparation | G17 | INTEGER, NOT NULL |
| AP-D1-389 | transfer_preparation.to_installation_id | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-390 | transfer_preparation.destination_epoch | column | migrations; transfer_preparation | G17 | INTEGER, NOT NULL |
| AP-D1-391 | transfer_preparation.reason | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-392 | transfer_preparation.assertion_sha256 | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-393 | transfer_preparation.accepted_actor | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-394 | transfer_preparation.accepted_signer_credential_id | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-395 | transfer_preparation.accepted_command | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-396 | transfer_preparation.phase | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-397 | transfer_preparation.due_at | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-398 | transfer_preparation.lease_token | column | migrations; transfer_preparation | G17 | TEXT |
| AP-D1-399 | transfer_preparation.lease_until | column | migrations; transfer_preparation | G17 | TEXT |
| AP-D1-400 | transfer_preparation.created_at | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-401 | transfer_preparation.updated_at | column | migrations; transfer_preparation | G17 | TEXT, NOT NULL |
| AP-D1-402 | transfer_route_manifest | table | migrations | G17 | Pinned source epoch/generation per grant in a transfer export. |
| AP-D1-403 | transfer_route_manifest.transfer_id | column | migrations; transfer_route_manifest | G17 | TEXT, PK1, NOT NULL |
| AP-D1-404 | transfer_route_manifest.grant_id | column | migrations; transfer_route_manifest | G17 | TEXT, PK2, NOT NULL |
| AP-D1-405 | transfer_route_manifest.source_epoch | column | migrations; transfer_route_manifest | G17 | INTEGER, NOT NULL |
| AP-D1-406 | transfer_route_manifest.source_generation | column | migrations; transfer_route_manifest | G17 | INTEGER, NOT NULL |
| AP-D1-407 | transfer_route_quarantine | table | migrations | G17 | Quarantined transfer routes with bounded reason. |
| AP-D1-408 | transfer_route_quarantine.transfer_id | column | migrations; transfer_route_quarantine | G17 | TEXT, PK1, NOT NULL |
| AP-D1-409 | transfer_route_quarantine.grant_id | column | migrations; transfer_route_quarantine | G17 | TEXT, PK2, NOT NULL, default '' |
| AP-D1-410 | transfer_route_quarantine.reason | column | migrations; transfer_route_quarantine | G17 | TEXT, NOT NULL |
| AP-D1-411 | transfer_route_quarantine.created_at | column | migrations; transfer_route_quarantine | G17 | TEXT, NOT NULL |
| AP-D1-412 | transfer_step | table | migrations | G17 | Transfer step receipts keyed by (transfer_id, step). |
| AP-D1-413 | transfer_step.transfer_id | column | migrations; transfer_step | G17 | TEXT, PK1, NOT NULL |
| AP-D1-414 | transfer_step.step | column | migrations; transfer_step | G17 | TEXT, PK2, NOT NULL |
| AP-D1-415 | transfer_step.receipt | column | migrations; transfer_step | G17 | TEXT, NOT NULL |
| AP-D1-416 | transfer_step.applied_at | column | migrations; transfer_step | G17 | TEXT, NOT NULL |
| AP-D1-417 | usage_event | table | migrations | G06 | Usage ledger events per term (quota_weight, tokens, cost, accounting_seq). |
| AP-D1-418 | usage_event.usage_event_id | column | migrations; usage_event | G12 | TEXT, PK1, NOT NULL |
| AP-D1-419 | usage_event.installation_id | column | migrations; usage_event | G12 | TEXT, NOT NULL |
| AP-D1-420 | usage_event.term_id | column | migrations; usage_event | G12 | TEXT, NOT NULL |
| AP-D1-421 | usage_event.request_id | column | migrations; usage_event | G12 | TEXT |
| AP-D1-422 | usage_event.quota_weight | column | migrations; usage_event | G12 | INTEGER, NOT NULL |
| AP-D1-423 | usage_event.tokens | column | migrations; usage_event | G12 | INTEGER, NOT NULL |
| AP-D1-424 | usage_event.cost | column | migrations; usage_event | G12 | REAL, NOT NULL |
| AP-D1-425 | usage_event.recorded_at | column | migrations; usage_event | G12 | TEXT, NOT NULL |
| AP-D1-426 | usage_event.origin_request_id | column | migrations; usage_event | G12 | TEXT |
| AP-D1-427 | usage_event.accounting_seq | column | migrations; usage_event | G12 | INTEGER |
| AP-D1-428 | usage_rollup | table | migrations | G06 | Usage rollup rows keyed by dimensions JSON (period, term, capability...). |
| AP-D1-429 | usage_rollup.rollup_id | column | migrations; usage_rollup | G15 | TEXT, PK1, NOT NULL |
| AP-D1-430 | usage_rollup.dimensions | column | migrations; usage_rollup | G15 | TEXT, NOT NULL |
| AP-D1-431 | usage_rollup.request_count | column | migrations; usage_rollup | G15 | INTEGER, NOT NULL |
| AP-D1-432 | usage_rollup.tokens | column | migrations; usage_rollup | G15 | INTEGER, NOT NULL |
| AP-D1-433 | usage_rollup.cost | column | migrations; usage_rollup | G15 | REAL, NOT NULL |
| AP-D1-434 | usage_rollup.quota_weight | column | migrations; usage_rollup | G15 | INTEGER, NOT NULL, default 0 |
| AP-D1-435 | usage_term_retention | table | migrations | G06 | Per-term state checkpoint used to decide usage_event retention. |
| AP-D1-436 | usage_term_retention.installation_id | column | migrations; usage_term_retention | G15 | TEXT, PK1, NOT NULL |
| AP-D1-437 | usage_term_retention.term_id | column | migrations; usage_term_retention | G15 | TEXT, PK2, NOT NULL |
| AP-D1-438 | usage_term_retention.term_state | column | migrations; usage_term_retention | G15 | TEXT, NOT NULL |
| AP-D1-439 | usage_term_retention.ended_at | column | migrations; usage_term_retention | G15 | TEXT |
| AP-D1-440 | usage_term_retention.clinic_seq | column | migrations; usage_term_retention | G15 | INTEGER, NOT NULL |
| AP-D1-441 | usage_term_retention.snapshot_sha256 | column | migrations; usage_term_retention | G15 | TEXT, NOT NULL |
| AP-D1-442 | idx_ai_attempt_request_id | index | migrations; ai_attempt | G08 | Index on ai_attempt |
| AP-D1-443 | ai_request_pending_accounting | index | migrations; ai_request | G08 | Index on ai_request |
| AP-D1-444 | idx_ai_request_conversation | index | migrations; ai_request | G08 | Index on ai_request |
| AP-D1-445 | idx_ai_request_created_at | index | migrations; ai_request | G08 | Index on ai_request |
| AP-D1-446 | idx_ai_request_installation_id | index | migrations; ai_request | G02 | Index on ai_request |
| AP-D1-447 | idx_ai_request_request_reference | index | migrations; ai_request | G08 | Index on ai_request |
| AP-D1-448 | idx_capability_grant_live_installation | index | migrations; capability_grant | G06 | Index on capability_grant |
| AP-D1-449 | idx_capability_grant_live_plan | index | migrations; capability_grant | G06 | Index on capability_grant |
| AP-D1-450 | complimentary_ceiling_claim_org_status_time | index | migrations; complimentary_ceiling_claim | G20 | Index on complimentary_ceiling_claim |
| AP-D1-451 | deletion_command_due | index | migrations; deletion_command | G08 | Index on deletion_command |
| AP-D1-452 | deletion_command_open_org | index | migrations; deletion_command | G08 | Index on deletion_command |
| AP-D1-453 | fallback_admission_installation_jti | index | migrations; fallback_admission | G03 | Index on fallback_admission |
| AP-D1-454 | fallback_admission_installation_state | index | migrations; fallback_admission | G11 | Index on fallback_admission |
| AP-D1-455 | fallback_admission_request_id | index | migrations; fallback_admission | G11 | Index on fallback_admission |
| AP-D1-456 | fallback_admission_state | index | migrations; fallback_admission | G11 | Index on fallback_admission |
| AP-D1-457 | grant_claim_due_commands | index | migrations; grant_claim | G06 | Index on grant_claim |
| AP-D1-458 | grant_claim_org_route | index | migrations; grant_claim | G06 | Index on grant_claim |
| AP-D1-459 | grant_ledger_operator_applied_at | index | migrations; grant_ledger | G06 | Index on grant_ledger |
| AP-D1-460 | grant_ledger_org_applied_at | index | migrations; grant_ledger | G06 | Index on grant_ledger |
| AP-D1-461 | grant_ledger_origin_grant_id | index | migrations; grant_ledger | G06 | Index on grant_ledger |
| AP-D1-462 | live_value_route_installation | index | migrations; live_value_route | G11 | Index on live_value_route |
| AP-D1-463 | platform_alert_due_idx | index | migrations; platform_alert | G15 | Index on platform_alert |
| AP-D1-464 | idx_platform_counter_installation | index | migrations; platform_counter | G02 | Index on platform_counter |
| AP-D1-465 | tenant_binding_one_live_org | index | migrations; tenant_binding | G02 | Index on tenant_binding |
| AP-D1-466 | transfer_preparation_due | index | migrations; transfer_preparation | G17 | Index on transfer_preparation |
| AP-D1-467 | transfer_preparation_open_source_epoch | index | migrations; transfer_preparation | G17 | Index on transfer_preparation |
| AP-D1-468 | transfer_preparation_reserved_epoch | index | migrations; transfer_preparation | G17 | Index on transfer_preparation |
| AP-D1-469 | idx_usage_event_accounting_seq | index | migrations; usage_event | G12 | Index on usage_event |
| AP-D1-470 | idx_usage_event_installation_id | index | migrations; usage_event | G12 | Index on usage_event |
| AP-D1-471 | idx_usage_event_origin_request | index | migrations; usage_event | G12 | Index on usage_event |
| AP-D1-472 | idx_usage_event_request_id | index | migrations; usage_event | G12 | Index on usage_event |
| AP-D1-473 | idx_usage_rollup_term_id | index | migrations; usage_rollup | G15 | Index on usage_rollup |
| AP-D1-474 | ceiling_policy_command_immutable | trigger | migrations; ceiling_policy_command | G19 | Trigger on ceiling_policy_command |
| AP-D1-475 | ceiling_policy_command_no_delete | trigger | migrations; ceiling_policy_command | G19 | Trigger on ceiling_policy_command |
| AP-D1-476 | complimentary_ceiling_claim_identity_immutable | trigger | migrations; complimentary_ceiling_claim | G20 | Trigger on complimentary_ceiling_claim |
| AP-D1-477 | complimentary_ceiling_claim_no_delete_guard | trigger | migrations; complimentary_ceiling_claim | G20 | Trigger on complimentary_ceiling_claim |
| AP-D1-478 | complimentary_ceiling_claim_reserve_guard | trigger | migrations; complimentary_ceiling_claim | G20 | Trigger on complimentary_ceiling_claim |
| AP-D1-479 | coverage_event_no_delete | trigger | migrations; coverage_event | G08 | Trigger on coverage_event |
| AP-D1-480 | coverage_event_no_update | trigger | migrations; coverage_event | G08 | Trigger on coverage_event |
| AP-D1-481 | grant_claim_identity_immutable | trigger | migrations; grant_claim | G06 | Trigger on grant_claim |
| AP-D1-482 | grant_claim_no_delete | trigger | migrations; grant_claim | G06 | Trigger on grant_claim |
| AP-D1-483 | grant_ledger_no_delete | trigger | migrations; grant_ledger | G06 | Trigger on grant_ledger |
| AP-D1-484 | grant_ledger_no_update | trigger | migrations; grant_ledger | G06 | Trigger on grant_ledger |
| AP-D1-485 | grant_tombstone_no_delete | trigger | migrations; grant_tombstone | G06 | Trigger on grant_tombstone |
| AP-D1-486 | grant_tombstone_no_update | trigger | migrations; grant_tombstone | G06 | Trigger on grant_tombstone |
| AP-D1-487 | grant_void_no_delete | trigger | migrations; grant_void | G06 | Trigger on grant_void |
| AP-D1-488 | grant_void_no_update | trigger | migrations; grant_void | G06 | Trigger on grant_void |
| AP-D1-489 | live_value_route_identity_immutable | trigger | migrations; live_value_route | G11 | Trigger on live_value_route |
| AP-D1-490 | live_value_route_no_delete | trigger | migrations; live_value_route | G11 | Trigger on live_value_route |
| AP-D1-491 | reversal_command_identity_immutable | trigger | migrations; reversal_command | G16 | Trigger on reversal_command |
| AP-D1-492 | reversal_command_no_delete | trigger | migrations; reversal_command | G16 | Trigger on reversal_command |
| AP-D1-493 | tenant_creation_cap_guard | trigger | migrations; tenant_binding | G02 | Trigger on tenant_binding |
| AP-D1-494 | harness_test_clock | table (not in migrations) | clock | G08 | Read only when TEST_CLOCK=1: column now_iso, row id 'default'; absent in production schema. |
| AP-D1-495 | harness_admission_fault | table (not in migrations) | worker | G10 | Read only when TEST_CLOCK=1: columns id, mode (throw\|hold), hold_until; absent in production schema. |
| AP-D1-496 | grace_admission_queue | dropped table | migrations | G10 | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-497 | invoice | dropped table | migrations | G08 | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-498 | credit_price | dropped table | migrations | G08 | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-499 | plan | dropped table | migrations | G08 | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-500 | entitlement | dropped table | migrations | G06 | Created by an earlier migration and dropped by a later one; not in the final schema. |
| AP-D1-501 | installation_key | dropped table | migrations | G02 | Created by an earlier migration and dropped by a later one; not in the final schema. |

## AP-MIG (40)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-MIG-001 | 20260731120000_platform_schema.sql | D1 migration | migrations | G00 | Platform D1 schema (§7.3): forward-only additive migration for slice A5. |
| AP-MIG-002 | 20260802100000_capability_grant_lifecycle.sql | D1 migration | migrations | G06 | J1: additive lifecycle overlay columns on capability_grant (global-scope overlay rows). |
| AP-MIG-003 | 20260803100000_routing_policy_canary.sql | D1 migration | migrations | G23 | J3: additive canary_installation_ids on routing_policy for cohort-scoped policy activation. |
| AP-MIG-004 | 20260803120000_token_contract.sql | D1 migration | migrations | G24 | J4: platform-global accepted AAT ver set (token_contract). |
| AP-MIG-005 | 20260805120000_f3_retention_indexes.sql | D1 migration | migrations | G07 | F3: detach ledger FK so journal purge can expire ai_request + ai_attempt at 90d |
| AP-MIG-006 | 20260805180000_h3_conversation_index.sql | D1 migration | migrations | G00 | A5 follow-up (H3-R4): index for one ordered conversation query (§7.3). |
| AP-MIG-007 | 20260805190000_routing_policy_status.sql | D1 migration | migrations | G24 | J3 review: explicit routing-policy activation status so publish is non-serving, |
| AP-MIG-008 | 20260807120000_kill_switch.sql | D1 migration | migrations | G23 | I2: durable kill-switch rows (§7.3). |
| AP-MIG-009 | 20260821120000_grace_admission_queue.sql | D1 migration | migrations | G10 | Durable grace-admission queue + cap (audit 1.4). Same D1 as the platform |
| AP-MIG-010 | 20260821130000_entitlement_installation_unique.sql | D1 migration | migrations | G06 | One entitlement row per installation (audit 5.9). |
| AP-MIG-011 | 20260911120000_plan_catalogue.sql | D1 migration | migrations | G00 | CREATE TABLE plan ( |
| AP-MIG-012 | 20260911180000_usage_rollup_quota_weight.sql | D1 migration | migrations | G15 | ALTER TABLE usage_rollup ADD COLUMN quota_weight INTEGER NOT NULL DEFAULT 0; |
| AP-MIG-013 | 20260911200000_invoice.sql | D1 migration | migrations | G00 | CREATE TABLE invoice ( |
| AP-MIG-014 | 20261003120000_operator_credential_and_platform_alert.sql | D1 migration | migrations | G17 | P3.1: operator credentials, assertion replay guard, platform alerts, control_audit extensions. |
| AP-MIG-015 | 20261003130000_issuer_key_tenant_binding.sql | D1 migration | migrations | G17 | CREATE TABLE issuer_key ( |
| AP-MIG-016 | 20261003140000_plan_version_paid_grant_coverage.sql | D1 migration | migrations | G17 | CREATE TABLE service_key ( |
| AP-MIG-017 | 20261006120000_usage_term.sql | D1 migration | migrations | G06 | P3.4: usage_event.term_id replaces period; rollup keyed by term_id. |
| AP-MIG-018 | 20261006130000_ceiling_policy.sql | D1 migration | migrations | G19 | CREATE TABLE ceiling_policy ( |
| AP-MIG-019 | 20261006140000_grant_void.sql | D1 migration | migrations | G06 | CREATE TABLE grant_void ( |
| AP-MIG-020 | 20261006150000_transfer.sql | D1 migration | migrations | G17 | CREATE TABLE transfer ( |
| AP-MIG-021 | 20261006160000_fallback_admission_feed.sql | D1 migration | migrations | G07 | P3.9: mirror fallback admission + coverage feed consumer; drop grace queue. |
| AP-MIG-022 | 20261006170000_drop_invoicing.sql | D1 migration | migrations | G00 | DROP TABLE IF EXISTS invoice; |
| AP-MIG-023 | 20261006170100_drop_plan_entitlement.sql | D1 migration | migrations | G06 | P3.10: drop transitional plan catalogue and entitlement rows. |
| AP-MIG-024 | 20261014120000_ai_request_idempotency_fingerprint.sql | D1 migration | migrations | G04 | Bind durable request idempotency to the validated request shape. |
| AP-MIG-025 | 20261018120000_r1_c3_malformed_issuer_key_cleanup.sql | D1 migration | migrations | G17 | R1-C3: legacy issuer keys whose validity bounds are malformed (unparseable |
| AP-MIG-026 | 20261018120100_r1_c2_tenant_creation_cap_trigger.sql | D1 migration | migrations | G01 | R1-C2: the authoritative first-tenant-creation cap (50 epoch-1 bindings in |
| AP-MIG-027 | 20261019120000_r4_pg1_global_grant_claims.sql | D1 migration | migrations | G06 | R4-PG1: global, immutable grant identity and mutable route metadata. |
| AP-MIG-028 | 20261019130000_r4_pg3_accepted_grant_commands.sql | D1 migration | migrations | G20 | R4-PG3: persist a verified complimentary command with its assertion claims. |
| AP-MIG-029 | 20261019140000_rm18_complimentary_ceiling_claims.sql | D1 migration | migrations | G20 | RM18: durable, org-scoped complimentary ceiling reservations and accepted |
| AP-MIG-030 | 20261019150000_r6_pt1_reversal_routes.sql | D1 migration | migrations | G16 | R6-PT1: durable routing/idempotency control records. |
| AP-MIG-031 | 20261019160000_r6_pt1_transfer_route_manifest.sql | D1 migration | migrations | G17 | R6-PT1: pin the exact source route generation and epoch included in an export. |
| AP-MIG-032 | 20261019170000_r4_d2_stranded_recovery.sql | D1 migration | migrations | G00 | CREATE TABLE IF NOT EXISTS stranded_term_recovery ( |
| AP-MIG-033 | 20261020120000_rm24_fallback_admission_identity.sql | D1 migration | migrations | G03 | RM24: durable fallback JTI and request binding for outage admissions. |
| AP-MIG-034 | 20261020130000_rm25_fallback_settlement.sql | D1 migration | migrations | G11 | RM25: retain the original settlement intent until the DO and D1 usage fact agree. |
| AP-MIG-035 | 20261020140000_r6_rm26_transfer_preparation.sql | D1 migration | migrations | G17 | Upgrade procedure for transfers accepted before this table existed: |
| AP-MIG-036 | 20261020150000_rm27_durable_deletion.sql | D1 migration | migrations | G00 | CREATE TABLE deletion_command ( |
| AP-MIG-037 | 20261021120000_rm30_usage_accounting_identity.sql | D1 migration | migrations | G18 | RM30: keep usage identity across snapshot recovery and journal erasure. |
| AP-MIG-038 | 20261021130000_rm31_alert_delivery.sql | D1 migration | migrations | G06 | RM31 (R9-PAL1): durable alert bodies, leased delivery and bounded retry state. |
| AP-MIG-039 | 20261021140000_rm33_routing_configuration_integrity.sql | D1 migration | migrations | G24 | RM33 (R8-ROUTE1): routing policy content integrity. |
| AP-MIG-040 | 20261021150000_rm33_routing_activation_generation.sql | D1 migration | migrations | G00 | RM33 (R8-ROLLBACK1): routing activation generation and predecessor record. |

## AP-R2 (5)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-R2-001 | request/{request_id}/envelope | R2 object prefix (JSON envelope) | journal; retention; support | G06 | Written by journal (writePostResponseDetail) with context, prompt, attempts raw bodies; ai_request.payload_pointer holds the key; deleted by retention (diagnostic horizon, 90 d journal purge, installation purge); read by support lookup. |
| AP-R2-002 | grant-ledger/{grant_id}.ndjson | R2 object (one NDJSON line) | quota-do/coverage outbox ship; vendor entrypoint | G18 | Grant ledger copy (grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, operator_email, envelope_sha256, applied_at, receipt). Written on outbox ship if absent (head check); read by rebuildGrantLedger / recovery. |
| AP-R2-003 | grant-ledger/{grant_id}.void.ndjson | R2 object (one NDJSON line) | quota-do/coverage; vendor entrypoint reversal export | G18 | Void proof line (grant_id, reason, source, evidence_sha256, at, receipt). Written on grant_void outbox ship and by shipDueReversalExports; read during rebuild_clinic_do recovery. |
| AP-R2-004 | grant-ledger/{grant_id}.recovery-v1.ndjson | R2 object (one NDJSON line) | quota-do/coverage | G18 | Grant recovery capsule (canonical JSON) written when a grant ledger row ships; compared byte-for-byte on rewrite (conflict throws grant_recovery_capsule_conflict); skipped when listing in rebuild. |
| AP-R2-005 | control/routing-policy/{policy_id}/{version}/sha256-{digest}.json | R2 object (application/json) | control/routing-policy | G24 | Immutable routing policy document published by publishRoutingPolicy; routing_policy.content_pointer and content_sha256 point at it; read and digest-verified by the config cache and promote/canary/rollback. |

## AP-DO (117)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-DO-001 | hot | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G12 | Singleton row of per-clinic hot state. |
| AP-DO-002 | hot.suspended | Durable Object SQLite column | quota-do/index.ts | G20 | suspended INTEGER NN default 0 |
| AP-DO-003 | hot.transferred_out_to | Durable Object SQLite column | quota-do/index.ts | G17 | transferred_out_to TEXT |
| AP-DO-004 | hot.awaiting_transfer | Durable Object SQLite column | quota-do/index.ts | G17 | awaiting_transfer INTEGER NN default 0 |
| AP-DO-005 | hot.awaiting_transfer_id | Durable Object SQLite column | quota-do/index.ts | G17 | awaiting_transfer_id TEXT |
| AP-DO-006 | hot.transfer_pending | Durable Object SQLite column | quota-do/index.ts | G17 | transfer_pending INTEGER NN default 0 |
| AP-DO-007 | hot.transfer_pending_id | Durable Object SQLite column | quota-do/index.ts | G17 | transfer_pending_id TEXT |
| AP-DO-008 | hot.active_term_id | Durable Object SQLite column | quota-do/index.ts | G12 | active_term_id TEXT |
| AP-DO-009 | hot.used | Durable Object SQLite column | quota-do/index.ts | G12 | used INTEGER NN default 0 |
| AP-DO-010 | hot.reserved | Durable Object SQLite column | quota-do/index.ts | G12 | reserved INTEGER NN default 0 |
| AP-DO-011 | hot.grace_base_used | Durable Object SQLite column | quota-do/index.ts | G12 | grace_base_used INTEGER NN default 0 |
| AP-DO-012 | hot.reservations | Durable Object SQLite column | quota-do/index.ts | G12 | reservations TEXT NN default '[]' |
| AP-DO-013 | hot.replay | Durable Object SQLite column | quota-do/index.ts | G12 | replay TEXT NN default '{}' |
| AP-DO-014 | hot.idempotency | Durable Object SQLite column | quota-do/index.ts | G04 | idempotency TEXT NN default '{}' |
| AP-DO-015 | hot.band_emitted | Durable Object SQLite column | quota-do/index.ts | G12 | band_emitted TEXT NN default '{}' |
| AP-DO-016 | hot.binding_epoch | Durable Object SQLite column | quota-do/index.ts | G12 | binding_epoch INTEGER NN default 0 |
| AP-DO-017 | hot.clinic_seq | Durable Object SQLite column | quota-do/index.ts | G12 | clinic_seq INTEGER NN default 0 |
| AP-DO-018 | hot.accounting_seq | Durable Object SQLite column | quota-do/index.ts | G12 | accounting_seq INTEGER NN default 0 |
| AP-DO-019 | hot.next_alarm_at | Durable Object SQLite column | quota-do/index.ts | G15 | next_alarm_at TEXT |
| AP-DO-020 | term | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G06 | Coverage terms. |
| AP-DO-021 | term.term_id | Durable Object SQLite column | quota-do/index.ts | G06 | term_id TEXT PK |
| AP-DO-022 | term.grant_id | Durable Object SQLite column | quota-do/index.ts | G06 | grant_id TEXT NN |
| AP-DO-023 | term.origin_grant_id | Durable Object SQLite column | quota-do/index.ts | G06 | origin_grant_id TEXT NN |
| AP-DO-024 | term.position | Durable Object SQLite column | quota-do/index.ts | G06 | position INTEGER NN |
| AP-DO-025 | term.state | Durable Object SQLite column | quota-do/index.ts | G06 | state TEXT NN |
| AP-DO-026 | term.end_reason | Durable Object SQLite column | quota-do/index.ts | G06 | end_reason TEXT |
| AP-DO-027 | term.plan_snapshot | Durable Object SQLite column | quota-do/index.ts | G06 | plan_snapshot TEXT |
| AP-DO-028 | term.allowance | Durable Object SQLite column | quota-do/index.ts | G06 | allowance INTEGER |
| AP-DO-029 | term.used_final | Durable Object SQLite column | quota-do/index.ts | G06 | used_final INTEGER |
| AP-DO-030 | term.duration_unit | Durable Object SQLite column | quota-do/index.ts | G06 | duration_unit TEXT |
| AP-DO-031 | term.duration_count | Durable Object SQLite column | quota-do/index.ts | G06 | duration_count INTEGER |
| AP-DO-032 | term.grace_days | Durable Object SQLite column | quota-do/index.ts | G06 | grace_days INTEGER |
| AP-DO-033 | term.grace_cap | Durable Object SQLite column | quota-do/index.ts | G06 | grace_cap TEXT |
| AP-DO-034 | term.calendar_start | Durable Object SQLite column | quota-do/index.ts | G06 | calendar_start TEXT |
| AP-DO-035 | term.starts_at | Durable Object SQLite column | quota-do/index.ts | G06 | starts_at TEXT |
| AP-DO-036 | term.ends_at | Durable Object SQLite column | quota-do/index.ts | G06 | ends_at TEXT |
| AP-DO-037 | term.grace_ends_at | Durable Object SQLite column | quota-do/index.ts | G06 | grace_ends_at TEXT |
| AP-DO-038 | term.ended_at | Durable Object SQLite column | quota-do/index.ts | G06 | ended_at TEXT |
| AP-DO-039 | grant | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G06 | Applied grants held in the Durable Object. |
| AP-DO-040 | grant.grant_id | Durable Object SQLite column | quota-do/index.ts | G06 | grant_id TEXT PK |
| AP-DO-041 | grant.kind | Durable Object SQLite column | quota-do/index.ts | G06 | kind TEXT NN |
| AP-DO-042 | grant.source_kind | Durable Object SQLite column | quota-do/index.ts | G06 | source_kind TEXT NN |
| AP-DO-043 | grant.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | G06 | envelope_sha256 TEXT NN |
| AP-DO-044 | grant.envelope | Durable Object SQLite column | quota-do/index.ts | G06 | envelope TEXT NN |
| AP-DO-045 | grant.evidence | Durable Object SQLite column | quota-do/index.ts | G06 | evidence TEXT NN |
| AP-DO-046 | grant.receipt | Durable Object SQLite column | quota-do/index.ts | G06 | receipt TEXT |
| AP-DO-047 | grant.applied_at | Durable Object SQLite column | quota-do/index.ts | G06 | applied_at TEXT NN |
| AP-DO-048 | grant.voided_at | Durable Object SQLite column | quota-do/index.ts | G06 | voided_at TEXT |
| AP-DO-049 | grant.void_reason | Durable Object SQLite column | quota-do/index.ts | G06 | void_reason TEXT |
| AP-DO-050 | outbox | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G07 | Pending rows to ship to D1/R2 by alarm. |
| AP-DO-051 | outbox.seq | Durable Object SQLite column | quota-do/index.ts | G12 | seq INTEGER PK AUTOINCREMENT |
| AP-DO-052 | outbox.kind | Durable Object SQLite column | quota-do/index.ts | G12 | kind TEXT NN |
| AP-DO-053 | outbox.payload | Durable Object SQLite column | quota-do/index.ts | G12 | payload TEXT NN |
| AP-DO-054 | grant_route_seal | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G06 | Route seal per grant. |
| AP-DO-055 | grant_route_seal.grant_id | Durable Object SQLite column | quota-do/index.ts | G06 | grant_id TEXT PK |
| AP-DO-056 | grant_route_seal.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | G06 | envelope_sha256 TEXT NN |
| AP-DO-057 | grant_route_seal.route_generation | Durable Object SQLite column | quota-do/index.ts | G06 | route_generation INTEGER NN |
| AP-DO-058 | grant_route_seal.sealed_at | Durable Object SQLite column | quota-do/index.ts | G06 | sealed_at TEXT NN |
| AP-DO-059 | transfer_replay | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G17 | Replay store per transfer step. |
| AP-DO-060 | transfer_replay.transfer_id | Durable Object SQLite column | quota-do/index.ts | G17 | transfer_id TEXT NN |
| AP-DO-061 | transfer_replay.step | Durable Object SQLite column | quota-do/index.ts | G17 | step TEXT NN CHECK transfer_out\|transfer_in |
| AP-DO-062 | transfer_replay.request_sha256 | Durable Object SQLite column | quota-do/index.ts | G17 | request_sha256 TEXT NN |
| AP-DO-063 | transfer_replay.response_json | Durable Object SQLite column | quota-do/index.ts | G17 | response_json TEXT NN |
| AP-DO-064 | transfer_replay.created_at | Durable Object SQLite column | quota-do/index.ts | G17 | created_at TEXT NN |
| AP-DO-065 | transfer_replay.PK(transfer_id, | Durable Object SQLite column | quota-do/index.ts | G17 | PK(transfer_id, step) |
| AP-DO-066 | grant_ceiling_claim | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G19 | Ceiling claim per grant. |
| AP-DO-067 | grant_ceiling_claim.grant_id | Durable Object SQLite column | quota-do/index.ts | G19 | grant_id TEXT PK |
| AP-DO-068 | grant_ceiling_claim.org_id | Durable Object SQLite column | quota-do/index.ts | G19 | org_id TEXT NN |
| AP-DO-069 | grant_ceiling_claim.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | G19 | envelope_sha256 TEXT NN |
| AP-DO-070 | grant_ceiling_claim.plan_id | Durable Object SQLite column | quota-do/index.ts | G19 | plan_id TEXT NN |
| AP-DO-071 | grant_ceiling_claim.plan_version | Durable Object SQLite column | quota-do/index.ts | G19 | plan_version INTEGER NN |
| AP-DO-072 | grant_ceiling_claim.allowance_denominator | Durable Object SQLite column | quota-do/index.ts | G19 | allowance_denominator INTEGER NN |
| AP-DO-073 | grant_ceiling_claim.day_contribution | Durable Object SQLite column | quota-do/index.ts | G19 | day_contribution INTEGER NN |
| AP-DO-074 | grant_ceiling_claim.allowance_contribution | Durable Object SQLite column | quota-do/index.ts | G19 | allowance_contribution INTEGER NN |
| AP-DO-075 | grant_ceiling_no_effect_seal | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G19 | No-effect seal for a ceiling claim. |
| AP-DO-076 | grant_ceiling_no_effect_seal.grant_id | Durable Object SQLite column | quota-do/index.ts | G19 | grant_id TEXT PK |
| AP-DO-077 | grant_ceiling_no_effect_seal.org_id | Durable Object SQLite column | quota-do/index.ts | G19 | org_id TEXT NN |
| AP-DO-078 | grant_ceiling_no_effect_seal.envelope_sha256 | Durable Object SQLite column | quota-do/index.ts | G19 | envelope_sha256 TEXT NN |
| AP-DO-079 | grant_ceiling_no_effect_seal.route_generation | Durable Object SQLite column | quota-do/index.ts | G19 | route_generation INTEGER NN |
| AP-DO-080 | grant_ceiling_no_effect_seal.sealed_at | Durable Object SQLite column | quota-do/index.ts | G19 | sealed_at TEXT NN |
| AP-DO-081 | grant_ceiling_no_effect_seal.receipt | Durable Object SQLite column | quota-do/index.ts | G19 | receipt TEXT NN |
| AP-DO-082 | stranded_term_recovery | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G12 | Recovery actions applied to stranded terms. |
| AP-DO-083 | stranded_term_recovery.action_id | Durable Object SQLite column | quota-do/index.ts | G12 | action_id TEXT PK |
| AP-DO-084 | stranded_term_recovery.target_term_id | Durable Object SQLite column | quota-do/index.ts | G12 | target_term_id TEXT NN UNIQUE |
| AP-DO-085 | stranded_term_recovery.reason | Durable Object SQLite column | quota-do/index.ts | G12 | reason TEXT NN |
| AP-DO-086 | stranded_term_recovery.request_sha256 | Durable Object SQLite column | quota-do/index.ts | G12 | request_sha256 TEXT NN |
| AP-DO-087 | stranded_term_recovery.result_json | Durable Object SQLite column | quota-do/index.ts | G12 | result_json TEXT NN |
| AP-DO-088 | stranded_term_recovery.recorded_at | Durable Object SQLite column | quota-do/index.ts | G12 | recorded_at TEXT NN |
| AP-DO-089 | usage_settlement_receipt | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G06 | Usage settlement receipts per request. |
| AP-DO-090 | usage_settlement_receipt.request_id | Durable Object SQLite column | quota-do/index.ts | G06 | request_id TEXT PK |
| AP-DO-091 | usage_settlement_receipt.installation_id | Durable Object SQLite column | quota-do/index.ts | G06 | installation_id TEXT NN |
| AP-DO-092 | usage_settlement_receipt.term_id | Durable Object SQLite column | quota-do/index.ts | G06 | term_id TEXT NN |
| AP-DO-093 | usage_settlement_receipt.weight | Durable Object SQLite column | quota-do/index.ts | G06 | weight INTEGER NN |
| AP-DO-094 | usage_settlement_receipt.outcome | Durable Object SQLite column | quota-do/index.ts | G06 | outcome TEXT NN CHECK consumed\|released |
| AP-DO-095 | usage_settlement_receipt.charged_weight | Durable Object SQLite column | quota-do/index.ts | G06 | charged_weight INTEGER NN >=0 |
| AP-DO-096 | usage_settlement_receipt.acknowledged | Durable Object SQLite column | quota-do/index.ts | G06 | acknowledged INTEGER NN default 0 (0\|1) |
| AP-DO-097 | usage_settlement_receipt.accounting_seq | Durable Object SQLite column | quota-do/index.ts | G06 | accounting_seq INTEGER |
| AP-DO-098 | usage_settlement_receipt.recorded_at | Durable Object SQLite column | quota-do/index.ts | G06 | recorded_at TEXT NN |
| AP-DO-099 | recovery_state | Durable Object SQLite table | quota-do/index.ts COVERAGE_DO_SCHEMA_STATEMENTS | G12 | Singleton recovery marker. |
| AP-DO-100 | recovery_state.singleton | Durable Object SQLite column | quota-do/index.ts | G12 | singleton INTEGER PK CHECK =1 |
| AP-DO-101 | recovery_state.generation | Durable Object SQLite column | quota-do/index.ts | G12 | generation TEXT NN |
| AP-DO-102 | recovery_state.installation_id | Durable Object SQLite column | quota-do/index.ts | G02 | installation_id TEXT NN |
| AP-DO-103 | recovery_state.org_id | Durable Object SQLite column | quota-do/index.ts | G12 | org_id TEXT NN |
| AP-DO-104 | recovery_state.binding_epoch | Durable Object SQLite column | quota-do/index.ts | G12 | binding_epoch INTEGER NN |
| AP-DO-105 | recovery_state.anchor_event_id | Durable Object SQLite column | quota-do/index.ts | G12 | anchor_event_id TEXT NN |
| AP-DO-106 | recovery_state.status | Durable Object SQLite column | quota-do/index.ts | G13 | status TEXT NN CHECK building\|blocked\|complete |
| AP-DO-107 | recovery_state.updated_at | Durable Object SQLite column | quota-do/index.ts | G12 | updated_at TEXT NN |
| AP-DO-108 | GatewayObject | Durable Object class (SQLite-backed) | worker; wrangler.toml | G17 | Binding DO; migration tag v1 new_sqlite_classes GatewayObject; one object per installation id (idFromName). Tables created on every fetch with CREATE TABLE IF NOT EXISTS plus ALTER TABLE ADD COLUMN for hot.awaiting_transfer_id, hot.transfer_pending_id, hot.accounting_seq and usage_settlement_receipt.accounting_seq. |
| AP-DO-109 | state (storage key) | Durable Object KV storage key | quota-do/index.ts | G12 | Legacy key-value record QuotaDoState. |
| AP-DO-110 | state.periodCounters | Durable Object KV state field | quota-do/index.ts QuotaDoState | G10 | requestsUsed, tokensUsed, costUsed, creditsUsed, inFlight |
| AP-DO-111 | state.periodBounds | Durable Object KV state field | quota-do/index.ts QuotaDoState | G12 | optional {period_start, period_end} |
| AP-DO-112 | state.jtiReplay | Durable Object KV state field | quota-do/index.ts QuotaDoState | G03 | map jti to {expiresAt} |
| AP-DO-113 | state.idempotency | Durable Object KV state field | quota-do/index.ts QuotaDoState | G04 | map key to {expiresAt, requestReference, state admitted\|completed\|failed\|cancelled, requestId, terminalErrorCode?, binding?, traceId?} |
| AP-DO-114 | state.creditedRequests | Durable Object KV state field | quota-do/index.ts QuotaDoState | G12 | map requestId to {expiresAt} |
| AP-DO-115 | state.admittedRequests | Durable Object KV state field | quota-do/index.ts QuotaDoState | G06 | map to {requestReference, admittedAt, entitlement snapshot} |
| AP-DO-116 | state.boundInstallationId | Durable Object KV state field | quota-do/index.ts QuotaDoState | G02 | optional string |
| AP-DO-117 | DO alarm | Durable Object alarm | quota-do/coverage.ts | G06 | Single alarm: earliest of active term ends_at, grace term grace_ends_at, or now when outbox is non-empty (scaled/delayed by physicalAlarmAt, min 5 s ahead); handler ships outbox. |

## AP-OUTBOX (7)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-OUTBOX-001 | coverage_event | outbox kind | quota-do/coverage | G07 | Shipped to D1 coverage_event (INSERT OR IGNORE) then coverage_mirror updated. |
| AP-OUTBOX-002 | grant_ledger | outbox kind | quota-do/coverage | G06 | Shipped to D1 grant_ledger, R2 grant-ledger/{id}.ndjson and recovery capsule. |
| AP-OUTBOX-003 | grant_void | outbox kind | quota-do/coverage | G06 | Shipped to D1 grant_void and R2 grant-ledger/{id}.void.ndjson. |
| AP-OUTBOX-004 | stranded_term_recovery | outbox kind | quota-do/coverage | G21 | Shipped to D1 stranded_term_recovery (INSERT OR IGNORE). |
| AP-OUTBOX-005 | usage_adjustment | outbox kind | quota-do/coverage | G12 | Shipped to D1 usage_event (id installation:accounting_seq); mismatch throws usage_accounting_identity_conflict. |
| AP-OUTBOX-006 | alert | outbox kind | quota-do/coverage | G15 | Persisted to D1 platform_alert via persistCommittedAlertBody then delivered. |
| AP-OUTBOX-007 | paid_velocity_observation | outbox kind | quota-do/coverage | G06 | Counts paid grants in last hour; if more than 20 globally raises AL-17 (alert_key AL-17:global). |

## AP-EVENT (10)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-EVENT-001 | term_activated | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-002 | grace_started | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-003 | term_ended | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-004 | term_held | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-005 | term_released | coverage event kind | quota-do/coverage | G06 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-006 | grant_applied | coverage event kind | quota-do/coverage | G06 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-007 | grant_voided | coverage event kind | quota-do/coverage | G06 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-008 | transfer | coverage event kind | quota-do/coverage | G17 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-009 | suspension_changed | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |
| AP-EVENT-010 | snapshot | coverage event kind | quota-do/coverage | G07 | Emitted into outbox as coverage_event; snapshot attached. |

## AP-ALERT (10)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ALERT-001 | AL-10 | alert code | vendor/entrypoint | G06 | Grant claim dispute (alert_key AL-10:grant-claim:{grant_id}). |
| AP-ALERT-002 | AL-11 | alert code | alert; quota-do/coverage | G17 | Grant/transfer related (keys AL-11:{grant_id}, AL-11:transfer:{transfer_id}). |
| AP-ALERT-003 | AL-12 | alert code | alert; quota-do/coverage | G06 | Grant related (key AL-12:{grant_id}). |
| AP-ALERT-004 | AL-13 | alert code | alert; vendor/entrypoint | G17 | Credential/key lifecycle: operator credential bootstrap\|register\|revoke; issuer key register\|retire\|revoke; service key register\|revoke. |
| AP-ALERT-005 | AL-17 | alert code | alert; quota-do/coverage | G06 | Paid-grant velocity (keys AL-17:clinic:{org_id}, AL-17:global); retried by five-minute cron. |
| AP-ALERT-006 | AL-18 | alert code | alert | G15 | Held binding (key AL-18:{installation_id}); sent daily by 03:00 cron. |
| AP-ALERT-007 | AL-19 | alert code | alert; kill-switch; quota-do/coverage | G23 | Kill switch arm/disarm and suspension toggles. |
| AP-ALERT-008 | AL-20 | alert code | alert; identity | G15 | First-tenant creation cap reached (50 epoch-1 bindings per 24 h); key AL-20; retried by five-minute cron. |
| AP-ALERT-009 | do_rebuild_mismatch | alert code | alert | G18 | Durable Object rebuild mismatch (key do-rebuild:{installation_id}[:{reason}]). |
| AP-ALERT-010 | scheduled_job_failed | alert code | alert | G15 | Five-minute cron job failure for job alert_retry or heartbeat (key scheduled_job_failed:{job}). |

## AP-CRON (19)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-CRON-001 | 0 3 * * * | cron schedule | wrangler.toml; worker.scheduled | G15 | Daily 03:00 UTC: flush rejection counters, then runRetentionPurge, then sendDailyAl18ForHeldBindings. |
| AP-CRON-002 | 0 4 * * * | cron schedule | wrangler.toml; worker.scheduled | G15 | Daily 04:00 UTC: flush rejection counters, then runRollupAndReconciliation (usage_rollup + reconciliation report). |
| AP-CRON-003 | */5 * * * * | cron schedule | wrangler.toml; worker.scheduled | G15 | Every 5 minutes: flush counters, then the jobs listed below in order. |
| AP-CRON-004 | flushRejectionCounters | scheduled job (every cron) | rate-limit | G15 | Writes in-isolate guard rejection tallies to platform_counter (lower bound). |
| AP-CRON-005 | runRetentionPurge | scheduled job (03:00) | retention | G06 | Checkpoints usage_term_retention from latest coverage_event; deletes diagnostic R2 envelopes by capability retention class (baseline 7 d, band 1..90 d); journal ai_request/ai_attempt and R2 envelopes at 90 d; usage_event/usage_rollup/control_audit/capability_grant at 2555 d; platform_counter at 90 d. |
| AP-CRON-006 | sendDailyAl18ForHeldBindings | scheduled job (03:00) | alert | G15 | Raises/sends AL-18 for held bindings. |
| AP-CRON-007 | runRollupAndReconciliation | scheduled job (04:00) | rollup | G15 | Writes usage_rollup; reconciliation of missing attempt rows / missing usage credit over a window; logs report (no alert row). |
| AP-CRON-008 | dispatchAcceptedGrantCommands | scheduled job (5-min) | vendor/entrypoint via VENDOR binding | G06 | Dispatches accepted grant_claim commands (due_at, lease, up to 25). |
| AP-CRON-009 | dispatchAcceptedTransferPreparations | scheduled job (5-min) | coverage/transfer via VENDOR | G17 | Advances transfer_preparation phases (up to 25). |
| AP-CRON-010 | dispatchDeletionCommands | scheduled job (5-min) | coverage/transfer via VENDOR | G15 | Advances deletion_command phases and purge (up to 25). |
| AP-CRON-011 | shipDueReversalExports | scheduled job (5-min) | vendor/entrypoint via VENDOR | G16 | Ships reversal_command exports to R2 (up to 25). |
| AP-CRON-012 | reconcileGraceUsage | scheduled job (5-min) | credit | G06 | Drains pending fallback_admission rows (outage-time admissions) by settling and acknowledging usage with the Durable Object (settleFallback / ackUsageReceipt). |
| AP-CRON-013 | runFiveMinuteCron: alert_retry | scheduled job (5-min) | alert | G15 | retryUnsentPlatformAlerts, retryDueAl20Alerts, retryDueAl17Alerts; on failure writes scheduled_job_failed alert. |
| AP-CRON-014 | runFiveMinuteCron: heartbeat | scheduled job (5-min) | alert | G15 | pingPlatformHeartbeat: GET HEARTBEAT_URL_PLATFORM (or HEARTBEAT_URL fallback); non-OK throws and raises scheduled_job_failed. |
| AP-CRON-015 | Durable Object alarm (coverage boundary and outbox) | Durable Object alarm | quota-do/coverage | G15 | One alarm per installation object; see AP-DO. |
| AP-CRON-016 | Alert delivery lease/backoff | timing constant | alert | G06 | Lease 2 minutes; backoff base 5 min, doubling, cap 60 min. |
| AP-CRON-017 | Rate-limit windows | platform rate limit bindings | wrangler.toml | G08 | RATE_LIMITER_INSTALLATION 600/60 s; RATE_LIMITER_INSTALLATION_ACTOR 120/60 s; RATE_LIMITER_INSTALLATION_CAPABILITY 300/60 s. |
| AP-CRON-018 | Heartbeat cadence of SSE stream | timing constant | worker; stream | G11 | HEARTBEAT_INTERVAL_MS = 15 000 ms. |
| AP-CRON-019 | Config cache TTL | timing constant | config-cache | G00 | CONFIG_CACHE_TTL_MS (30 000 staging/production, 100 development). |

## AP-MANIFEST (14)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-MANIFEST-001 | manifests/published/clinic.visit_summary@1.0.0.json | published capability manifest | manifests | G08 | capabilityId clinic.visit_summary v1.0.0, lifecycleState active, scope ai.visit_summary, minimumPlanTier standard, roles administrator\|clinician\|nurse, single_shot, prose output, maxChars 8000, en, context requirement visit.chief_complaint@v1 (max 4096), routing ref routing/standard, maxInputTokens 8000, maxOutputTokens 1024, quotaWeight 1, acceptanceMode advisory_display, retentionClass diagnostic_30d, evalSuiteRef evals/visit-summary@v1. Bundled at build into worker. |
| AP-MANIFEST-002 | manifest sections (Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance) | manifest structure | manifest/index.ts | G08 | Sections validated by manifest load(). |
| AP-MANIFEST-003 | manifests/published-registry.json | manifest hash pin registry | manifests | G08 | Maps clinic.visit_summary@1.0.0 to a SHA-256 hash. |
| AP-MANIFEST-004 | prompts/clinic.visit_summary/system.md | prompt artifact | prompts; prompt/registry | G10 | Ref clinic.visit_summary/system@v1. |
| AP-MANIFEST-005 | prompts/clinic.visit_summary/rules-visit-summary.md | prompt artifact | prompts; prompt/registry | G10 | Ref clinic.visit_summary/rules-visit-summary@v1 (business rule fragment). |
| AP-MANIFEST-006 | prompts/clinic.visit_summary/template-visit-summary.md | prompt artifact | prompts; prompt/registry | G10 | Ref clinic.visit_summary/template-visit-summary@v1 (context rendering template with {{visit.chief_complaint@v1}}). |
| AP-MANIFEST-007 | prompts/clinic.visit_summary/registry.json | prompt hash pin registry | prompts | G10 | Maps the three artifact refs to short hashes (8 hex chars each). |
| AP-MANIFEST-008 | context/shapes/published/visit.chief_complaint@v1.json | context shape | context | G10 | Fields visit_id (string, required, uuid), complaint (string, max length 10000), recorded_at (string, optional, iso8601). |
| AP-MANIFEST-009 | control/routing-policy/platform-default/1.json | bundled default routing policy | control | G24 | policy_id standard, version 1, one rule platform-default-fallback; targets deepseek/deepseek-v4-flash then gemini/gemini-3.5-flash, max_attempts 2, timeout 30000 ms each. |
| AP-MANIFEST-010 | control/pricing/platform-default/1.json | bundled pricing table | control; pricing/index.ts | G11 | per_1k_tokens price for deepseek-v4-flash, gemini-3.5-flash, fake-v1 and a default. |
| AP-MANIFEST-011 | Capability registry (installed at boot) | in-memory registry | worker boot; capability/index.ts | G08 | Created from visitSummaryPublished; setCapabilityRegistry at module init. |
| AP-MANIFEST-012 | Config cache entity kinds | cache kinds | config-cache/index.ts | G17 | installations, issuer_keys, tenant_bindings, entitlements, grants, kill_switches, active_routing_policy, token_contracts, plans (read from D1/R2). |
| AP-MANIFEST-013 | PLAN_TIERS | vocabulary | platform-vocabulary.ts | G09 | starter, standard, professional, enterprise. |
| AP-MANIFEST-014 | Routing policy status values | vocabulary | control/routing-policy | G24 | published (after publish), canary, active (after promote), superseded (prior active/canary). |

## AP-OUT (10)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-OUT-001 | DeepSeek chat completions: POST https://api.deepseek.com/chat/completions | outbound HTTPS (provider) | provider/deepseek.ts | G11 | Authorization Bearer DEEPSEEK_API_KEY; default model deepseek-v4-flash; streaming and non-streaming. |
| AP-OUT-002 | Gemini: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent or :streamGenerateContent?alt=sse | outbound HTTPS (provider) | provider/gemini.ts | G11 | Header x-goog-api-key from GEMINI_API_KEY; default model gemini-3.5-flash. |
| AP-OUT-003 | Cloudflare Access certs: GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs | outbound HTTPS | vendor/entrypoint | G19 | Fetched per Access JWT verification unless ACCESS_CERTS_JSON is set. |
| AP-OUT-004 | Heartbeat ping: GET HEARTBEAT_URL_PLATFORM (fallback HEARTBEAT_URL) | outbound HTTPS | alert/index.ts | G11 | Every 5 minutes; non-OK response throws. |
| AP-OUT-005 | SEND_EMAIL.send({from,to,subject,text}) | outbound email binding | alert/email.ts | G15 | from and to both ALERT_EMAIL_TO; subject is alert code; text is alert body JSON. |
| AP-OUT-006 | Durable Object stub fetch: POST https://quota-do.internal/rpc | internal binding call | pipeline; admission; credit; coverage-read; coverage/transfer; vendor/entrypoint; quota-do/coverage | G12 | Callers use env.DO.get(idFromName(installationId)); see AP-DORPC. |
| AP-OUT-007 | VENDOR service binding (self): dispatchAcceptedGrantCommands, dispatchAcceptedTransferPreparations, dispatchDeletionCommands, shipDueReversalExports | internal service binding call | worker.scheduled | G17 | Binding VENDOR points to this same Worker's VendorEntrypoint (per-environment service name). |
| AP-OUT-008 | R2 reads/writes | internal binding | see AP-R2 | G07 |  |
| AP-OUT-009 | D1 reads/writes | internal binding | see AP-D1 | G11 |  |
| AP-OUT-010 | Calls to ABO or Supabase | none found | whole ai-platform/src | G17 | The AP code makes no outbound call to the ABO or Supabase; the ABO calls the AP (VendorEntrypoint methods via service binding, GET /v1/feed/coverage over HTTP); Supabase issues the AI/feed tokens that the AP verifies against issuer_key rows. |

## AP-SSE (10)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-SSE-001 | accepted | SSE event | adapter | G07 | First event. data: request_reference, trace_id, degraded_notice (true only when set). |
| AP-SSE-002 | heartbeat | SSE event | stream/index.ts; stream/structured.ts | G11 | Every 15 s (and reset on activity). data: trace_id. |
| AP-SSE-003 | text_delta | SSE event | stream/index.ts | G11 | Prose mode. data: text, sequence, provisional true. |
| AP-SSE-004 | regenerating | SSE event | stream/index.ts; stream/structured.ts | G11 | Discards prior assembled text. data: trace_id. |
| AP-SSE-005 | progress | SSE event | stream/structured.ts | G11 | structured_atomic mode. data: trace_id, bytesReceived. |
| AP-SSE-006 | partial_structured | SSE event | stream/structured.ts | G11 | structured mode. data: sequence, provisional true, document, committed false, committable false. |
| AP-SSE-007 | completed | SSE event (terminal) | adapter; stream; worker | G11 | data: result (prose: finalContent {text, authoritative true}), trace_id. |
| AP-SSE-008 | failed | SSE event (terminal) | adapter; stream; worker | G11 | data: taxonomy error body {code, request_reference, trace_id, retry_safe}. |
| AP-SSE-009 | cancelled | SSE event (terminal) | adapter; stream | G11 | data: trace_id. |
| AP-SSE-010 | context_requested | SSE event (terminal; conversational only) | adapter | G08 | data: context_request, trace_id. Throws if emitted for non-conversational capability. |

## AP-ERR (265)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ERR-001 | unauthenticated | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 401; retryable: After re-mint; consumes quota: No. |
| AP-ERR-002 | installation_suspended | taxonomy error code (errors.ts) | errors.ts | G20 | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-003 | suspended | taxonomy error code (errors.ts) | errors.ts | G20 | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-004 | forbidden_capability | taxonomy error code (errors.ts) | errors.ts | G08 | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-005 | rate_limited | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 429; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-006 | quota_exhausted | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 429; retryable: Not until period reset; consumes quota: No. Supplementary field period_reset. |
| AP-ERR-007 | allowance_exhausted | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 403; retryable: No; consumes quota: No. |
| AP-ERR-008 | coverage_lapsed | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 403; retryable: No; consumes quota: No. Supplementary field coverage_reason. |
| AP-ERR-009 | concurrency_limited | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 429; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-010 | coverage_unknown | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 503; retryable: Yes, after retry_after; consumes quota: No. Supplementary field retry_after. |
| AP-ERR-011 | request_too_large | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 413; retryable: No; consumes quota: No. |
| AP-ERR-012 | context_required | taxonomy error code (errors.ts) | errors.ts | G08 | HTTP 422; retryable: Yes, after resolving; consumes quota: No. Body adds missing_keys, shapes, manifest_version, manifest_capability_id. |
| AP-ERR-013 | context_invalid | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 422; retryable: No; consumes quota: No. |
| AP-ERR-014 | conversation_budget_exhausted | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 409; retryable: No, within this conversation; consumes quota: No. |
| AP-ERR-015 | idempotency_conflict | taxonomy error code (errors.ts) | errors.ts | G04 | HTTP 409; retryable: No; consumes quota: No. |
| AP-ERR-016 | capability_unknown | taxonomy error code (errors.ts) | errors.ts | G08 | HTTP 404; retryable: No; consumes quota: No. |
| AP-ERR-017 | capability_retired | taxonomy error code (errors.ts) | errors.ts | G08 | HTTP 404; retryable: No; consumes quota: No. |
| AP-ERR-018 | capability_disabled | taxonomy error code (errors.ts) | errors.ts | G08 | HTTP 503; retryable: Later; consumes quota: No. |
| AP-ERR-019 | provider_unavailable | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 503; retryable: Yes; consumes quota: Partially, recorded. |
| AP-ERR-020 | provider_rejected | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 422; retryable: No; consumes quota: Yes. |
| AP-ERR-021 | validation_failed | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 422; retryable: Yes, at user discretion; consumes quota: Yes. |
| AP-ERR-022 | cancelled | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 499; retryable: -; consumes quota: Partially, recorded. cancelled has no live HTTP status (SSE only). |
| AP-ERR-023 | timeout | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 504; retryable: Yes; consumes quota: Partially, recorded. |
| AP-ERR-024 | internal_error | taxonomy error code (errors.ts) | errors.ts | G11 | HTTP 500; retryable: Yes; consumes quota: No. |
| AP-ERR-025 | coverage_reason: none | coverage_lapsed coverage_reason value | errors.ts | G13 | Supplementary field on coverage_lapsed body. |
| AP-ERR-026 | coverage_reason: expired | coverage_lapsed coverage_reason value | errors.ts | G13 | Supplementary field on coverage_lapsed body. |
| AP-ERR-027 | coverage_reason: grace_exhausted | coverage_lapsed coverage_reason value | errors.ts | G13 | Supplementary field on coverage_lapsed body. |
| AP-ERR-028 | coverage_reason: reversed | coverage_lapsed coverage_reason value | errors.ts | G16 | Supplementary field on coverage_lapsed body. |
| AP-ERR-029 | coverage_reason: transferred | coverage_lapsed coverage_reason value | errors.ts | G17 | Supplementary field on coverage_lapsed body. |
| AP-ERR-030 | coverage_reason: transfer_pending | coverage_lapsed coverage_reason value | errors.ts | G17 | Supplementary field on coverage_lapsed body. |
| AP-ERR-031 | contract_version_unsupported | channel negotiation code | vendor-contracts negotiate; vendor/contract-version.ts; worker | G03 | Returned with accepted_versions on Aip-Contract-Version, feed, DO and VendorEntrypoint negotiation failures (HTTP 400 on HTTP routes; result rejected on RPC). |
| AP-ERR-032 | unauthorized | support-lookup HTTP handler error (control/index.ts) | control/index.ts | G11 | HTTP 401. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-033 | missing_reference | support-lookup HTTP handler error (control/index.ts) | control/index.ts | G11 | HTTP 400. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-034 | invalid_reference | support-lookup HTTP handler error (control/index.ts) | control/index.ts | G11 | HTTP 400. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-035 | not_found | support-lookup HTTP handler error (control/index.ts) | control/index.ts | G11 | HTTP 404. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-036 | storage_error | support-lookup HTTP handler error (control/index.ts) | control/index.ts | G11 | HTTP 500. handleSupportLookup is exported but not wired to any route in worker.ts. |
| AP-ERR-037 | invalid_payload | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-038 | invalid_policy_identity | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-039 | invalid_ver | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-040 | missing_installation_ids | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-041 | missing_successor_id | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-042 | not_deprecated | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-043 | overlap_window_active | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-044 | unknown_successor | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 400 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-045 | capability_not_found | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-046 | installation_not_found | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-047 | policy_version_not_found | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-048 | ver_not_found | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 404 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-049 | activation_state_missing | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-050 | already_deprecated | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-051 | already_published | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-052 | already_retired | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-053 | generation_conflict | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-054 | illegal_installation_transition | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-055 | illegal_kill_switch_transition | control-plane action error (ControlActionResult) | control/*.ts | G23 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-056 | illegal_policy_transition | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-057 | no_rotation_open | control-plane action error (ControlActionResult) | control/*.ts | G17 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-058 | not_deprecated | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-059 | rollback_predecessor_unknown | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-060 | rotation_already_open | control-plane action error (ControlActionResult) | control/*.ts | G17 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-061 | ver_already_exists | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-062 | ver_already_retired | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 409 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-063 | invalid_policy_document | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 422 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-064 | missing_r2_binding | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 500 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-065 | storage_error | control-plane action error (ControlActionResult) | control/*.ts | G06 | Status 500 in action result; surfaced by VendorEntrypoint as rejected/conflict envelope code. |
| AP-ERR-066 | actor_email_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-067 | approvals_required | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-068 | assertion_expired | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-069 | assertion_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-070 | assertion_required | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-071 | assertion_used | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-072 | bad_assertion | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-073 | bad_request | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-074 | bad_signature | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-075 | binding_route_pending | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-076 | coverage_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-077 | coverage_unknown | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-078 | credential_not_active | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-079 | credential_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-080 | credential_revoked | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-081 | exceeds_ceiling | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-082 | exceeds_plan_bound | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-083 | grant_route_claim_race | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-084 | grant_voided | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-085 | kid_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-086 | kid_revoked | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-087 | limit_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-088 | missing_document | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-089 | missing_installation_id | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-090 | missing_installation_ids | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-091 | missing_lookup_key | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-092 | not_found | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-093 | partial_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-094 | partial_void | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-095 | placement_not_supported | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-096 | plan_not_published | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-097 | plan_version_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-098 | plan_version_not_found | VendorEntrypoint result code | vendor/entrypoint.ts | G19 | Code in rejected/conflict/transient envelope. |
| AP-ERR-099 | public_key_cose_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-100 | public_key_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-101 | public_key_mismatch | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-102 | recovery_audit_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-103 | recovery_blocked | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-104 | recovery_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-105 | recovery_evidence_required | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-106 | recovery_history_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-107 | recovery_identity_conflict | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-108 | reversal_commit_pending | VendorEntrypoint result code | vendor/entrypoint.ts | G16 | Code in rejected/conflict/transient envelope. |
| AP-ERR-109 | reversal_due | VendorEntrypoint result code | vendor/entrypoint.ts | G16 | Code in rejected/conflict/transient envelope. |
| AP-ERR-110 | reversal_receipt_unavailable | VendorEntrypoint result code | vendor/entrypoint.ts | G16 | Code in rejected/conflict/transient envelope. |
| AP-ERR-111 | storage_error | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-112 | transfer_pending | VendorEntrypoint result code | vendor/entrypoint.ts | G17 | Code in rejected/conflict/transient envelope. |
| AP-ERR-113 | transfer_route_quarantined | VendorEntrypoint result code | vendor/entrypoint.ts | G17 | Code in rejected/conflict/transient envelope. |
| AP-ERR-114 | unauthenticated | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-115 | unavailable | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-116 | unit_not_allowed | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-117 | unknown_kid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-118 | voided | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-119 | window_invalid | VendorEntrypoint result code | vendor/entrypoint.ts | G06 | Code in rejected/conflict/transient envelope. |
| AP-ERR-120 | deletion_pending | VendorEntrypoint transient detail | vendor/entrypoint.ts | G09 | Appears as detail with result transient and empty code. |
| AP-ERR-121 | transfer_preparation_pending | VendorEntrypoint transient detail | vendor/entrypoint.ts | G17 | Appears as detail with result transient and empty code. |
| AP-ERR-122 | harness_drain_unavailable | harness-only error | vendor/entrypoint.ts | G15 | Raised only by drainDurableObjectsForHarness. |
| AP-ERR-123 | harness_drain_invalid_installations | harness-only error | vendor/entrypoint.ts | G15 | Raised only by drainDurableObjectsForHarness. |
| AP-ERR-124 | awaiting_transfer_out | transfer workflow code | coverage/transfer.ts | G17 | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-125 | reversal_or_transfer_in_progress | transfer workflow code | coverage/transfer.ts | G17 | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-126 | transfer_accounting_pending | transfer workflow code | coverage/transfer.ts | G17 | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-127 | value_route_manifest_pending | transfer workflow code | coverage/transfer.ts | G17 | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-128 | value_route_publish_pending | transfer workflow code | coverage/transfer.ts | G17 | Code/detail in transfer or deletion result envelopes (transfer_route_quarantined and transfer_pending listed above). |
| AP-ERR-129 | result: ok | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-130 | result: rejected | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-131 | result: conflict | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-132 | result: applied | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-133 | result: already_applied | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-134 | result: transient | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-135 | result: blocked | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-136 | result: sealed | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-137 | result: sealed_no_effect | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-138 | result: not_found | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-139 | result: bad_request | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-140 | result: exceeds_ceiling | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G19 | Top-level result field value. |
| AP-ERR-141 | result: accepted | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-142 | result: drained | result value in RPC envelope | vendor/entrypoint; quota-do/coverage; coverage/transfer | G06 | Top-level result field value. |
| AP-ERR-143 | DO: invalid_json | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-144 | DO: unknown_kind | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-145 | DO: internal_error | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-146 | DO: bad_request | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-147 | DO: recovery_blocked | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-148 | DO: invalid_settle_fallback_args | Durable Object RPC error/result | worker GatewayObject.fetch | G11 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-149 | DO: invalid_ack_usage_receipt_args | Durable Object RPC error/result | worker GatewayObject.fetch | G06 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-150 | DO: invalid_admission_args | Durable Object RPC error/result | worker GatewayObject.fetch | G10 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-151 | DO: invalid_admission_binding | Durable Object RPC error/result | worker GatewayObject.fetch | G10 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-152 | DO: invalid_journaled_answer | Durable Object RPC error/result | worker GatewayObject.fetch | G10 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-153 | DO: invalid_journaled_conflict | Durable Object RPC error/result | worker GatewayObject.fetch | G10 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-154 | DO: invalid_credit_args | Durable Object RPC error/result | worker GatewayObject.fetch | G09 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-155 | DO: invalid_release_args | Durable Object RPC error/result | worker GatewayObject.fetch | G06 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-156 | DO: installation_id_mismatch | Durable Object RPC error/result | worker GatewayObject.fetch | G02 | error or result field of DO fetch (see AP-DORPC). |
| AP-ERR-157 | DO outcome: admitted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-158 | DO outcome: idempotent | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G04 | Outcome field value. |
| AP-ERR-159 | DO outcome: replay | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-160 | DO outcome: deferred | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-161 | DO outcome: concurrency_exhausted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-162 | DO outcome: coverage_lapsed | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-163 | DO outcome: quota_exhausted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-164 | DO outcome: forbidden_capability | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G08 | Outcome field value. |
| AP-ERR-165 | DO outcome: idempotency_conflict | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G04 | Outcome field value. |
| AP-ERR-166 | DO outcome: suspended | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G20 | Outcome field value. |
| AP-ERR-167 | DO outcome: conflict | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-168 | DO outcome: settled | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-169 | DO outcome: already_accounted | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-170 | DO outcome: consumed | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-171 | DO outcome: acknowledged | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-172 | DO outcome: already_acknowledged | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-173 | DO outcome: unknown_request | Durable Object admission/credit/settle outcome | quota-do/index.ts; coverage.ts | G12 | Outcome field value. |
| AP-ERR-174 | admission/credit result: allowance_exhausted | admission/credit module result code | admission/index.ts; credit/index.ts | G13 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-175 | admission/credit result: client_error | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-176 | admission/credit result: concurrency_limited | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-177 | admission/credit result: contract_rejected | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-178 | admission/credit result: coverage_lapsed | admission/credit module result code | admission/index.ts; credit/index.ts | G13 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-179 | admission/credit result: coverage_unknown | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-180 | admission/credit result: forbidden_capability | admission/credit module result code | admission/index.ts; credit/index.ts | G08 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-181 | admission/credit result: idempotency_conflict | admission/credit module result code | admission/index.ts; credit/index.ts | G04 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-182 | admission/credit result: internal_error | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-183 | admission/credit result: suspended | admission/credit module result code | admission/index.ts; credit/index.ts | G20 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-184 | admission/credit result: unauthenticated | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-185 | admission/credit result: unavailable | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-186 | admission/credit result: unknown_request | admission/credit module result code | admission/index.ts; credit/index.ts | G10 | Mapped from Durable Object responses before taxonomy mapping. |
| AP-ERR-187 | router exclusion: context_window_too_small | routing candidate exclusion reason | router/index.ts | G11 | Reason a provider/model target is excluded. |
| AP-ERR-188 | router exclusion: cost_class_excluded | routing candidate exclusion reason | router/index.ts | G11 | Reason a provider/model target is excluded. |
| AP-ERR-189 | router exclusion: feature_unsupported | routing candidate exclusion reason | router/index.ts | G11 | Reason a provider/model target is excluded. |
| AP-ERR-190 | router exclusion: installation_excluded | routing candidate exclusion reason | router/index.ts | G11 | Reason a provider/model target is excluded. |
| AP-ERR-191 | router exclusion: kill_switch | routing candidate exclusion reason | router/index.ts | G23 | Reason a provider/model target is excluded. |
| AP-ERR-192 | router exclusion: language_unsupported | routing candidate exclusion reason | router/index.ts | G11 | Reason a provider/model target is excluded. |
| AP-ERR-193 | context_request invalid: element_not_object | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-194 | context_request invalid: invalid_arguments_type | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-195 | context_request invalid: invalid_key_type | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-196 | context_request invalid: missing_arguments | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-197 | context_request invalid: missing_key | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-198 | context_request invalid: root_not_list | context_requested payload validation reason | context/context-request.ts | G10 | Used in the error thrown when a context request is non-conforming. |
| AP-ERR-199 | coverage_mirror_miss | capability guard reason | capability/index.ts | G06 | Internal reason in capability/entitlement check. |
| AP-ERR-200 | no_reask_port | validation reason | validate/index.ts | G09 | Internal validation reason. |
| AP-ERR-201 | grant_recovery_capsule_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-202 | grant_recovery_capsule_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-203 | grant_recovery_capsule_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-204 | grant_recovery_capsule_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-205 | grant_recovery_capsule_schema_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-206 | grant_recovery_ceiling_claim_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-207 | grant_recovery_ceiling_claim_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-208 | grant_recovery_ceiling_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-209 | grant_recovery_claim_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-210 | grant_recovery_claim_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-211 | grant_recovery_command_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-212 | grant_recovery_command_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-213 | grant_recovery_command_metadata_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-214 | grant_recovery_command_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-215 | grant_recovery_command_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-216 | grant_recovery_command_provenance_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-217 | grant_recovery_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-218 | grant_recovery_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-219 | grant_recovery_evidence_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-220 | grant_recovery_identity_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-221 | grant_recovery_override_link_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-222 | grant_recovery_override_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-223 | grant_recovery_paid_metadata_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-224 | grant_recovery_plan_snapshot_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-225 | grant_recovery_receipt_identity_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-226 | grant_recovery_receipt_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-227 | grant_recovery_route_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-228 | grant_recovery_signing_key_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-229 | grant_recovery_signing_key_unavailable | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-230 | grant_recovery_signing_key_unknown | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-231 | grant_recovery_source_kind_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-232 | grant_recovery_transfer_claim_fields_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-233 | grant_recovery_transfer_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-234 | grant_recovery_transfer_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-235 | grant_recovery_transfer_evidence_required | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-236 | grant_recovery_transfer_request_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-237 | grant_void_recovery_command_provenance_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-238 | grant_void_recovery_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-239 | grant_void_recovery_evidence_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-240 | grant_void_recovery_evidence_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-241 | grant_void_recovery_evidence_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-242 | grant_void_recovery_grant_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-243 | grant_void_recovery_ledger_missing | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-244 | grant_void_recovery_receipt_conflict | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-245 | grant_void_recovery_source_invalid | Durable Object recovery blocked_reason / thrown error | quota-do/coverage.ts | G18 | Reason string when rebuild_clinic_do / rebuildGrantLedger blocks (result blocked, blocked_reason) or throws. |
| AP-ERR-246 | grant_route_seal_evidence_missing | Durable Object coverage code/reason | quota-do/coverage.ts | G06 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-247 | transfer_replay_evidence_missing | Durable Object coverage code/reason | quota-do/coverage.ts | G17 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-248 | usage_accounting_identity_conflict | Durable Object coverage code/reason | quota-do/coverage.ts | G12 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-249 | usage_accounting_identity_unknown | Durable Object coverage code/reason | quota-do/coverage.ts | G12 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-250 | usage_accounting_sequence_gap | Durable Object coverage code/reason | quota-do/coverage.ts | G12 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-251 | usage_accounting_snapshot_invalid | Durable Object coverage code/reason | quota-do/coverage.ts | G12 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-252 | usage_accounting_term_identity_conflict | Durable Object coverage code/reason | quota-do/coverage.ts | G12 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-253 | ceiling_claim_sealed | Durable Object coverage code/reason | quota-do/coverage.ts | G19 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-254 | route_sealed | Durable Object coverage code/reason | quota-do/coverage.ts | G11 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-255 | complimentary_ceiling_claim_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | G20 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-256 | complimentary_ceiling_claim_required | Durable Object coverage code/reason | quota-do/coverage.ts | G20 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-257 | complimentary_ceiling_claim_route_mismatch | Durable Object coverage code/reason | quota-do/coverage.ts | G20 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-258 | grant_ceiling_claim_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | G19 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-259 | grant_term_reconciliation_required | Durable Object coverage code/reason | quota-do/coverage.ts | G06 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-260 | reservation_state_unknown | Durable Object coverage code/reason | quota-do/coverage.ts | G09 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-261 | reservations_pending | Durable Object coverage code/reason | quota-do/coverage.ts | G09 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-262 | coverage_outbox_ship_failed | Durable Object coverage code/reason | quota-do/coverage.ts | G09 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-263 | grant_storage_unavailable | Durable Object coverage code/reason | quota-do/coverage.ts | G06 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-264 | invalid_platform_signing_key | Durable Object coverage code/reason | quota-do/coverage.ts | G09 | Reason/code string in coverage RPC results or thrown errors. |
| AP-ERR-265 | complimentary_ceiling_exceeded | Durable Object coverage code/reason | quota-do/coverage.ts | G20 | Reason/code string in coverage RPC results or thrown errors. |

## AP-ENV (33)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-ENV-001 | DB | D1 database binding | wrangler.toml | G11 | ai-platform-development / -staging / -production; required at boot (assertRequiredBindings). |
| AP-ENV-002 | R2 | R2 bucket binding | wrangler.toml | G07 | ai-platform-{development,staging,production}; required at boot. |
| AP-ENV-003 | DO | Durable Object namespace binding | wrangler.toml | G00 | class GatewayObject; required at boot. |
| AP-ENV-004 | VENDOR | service binding | wrangler.toml | G00 | Service ai-platform-gateway[-env], entrypoint VendorEntrypoint (self-binding; top-level and per env). |
| AP-ENV-005 | SEND_EMAIL | send_email binding | wrangler.toml | G15 | destination_address alerts@clinic.invalid in every env. |
| AP-ENV-006 | RATE_LIMITER_INSTALLATION | rate limit binding | wrangler.toml | G09 | limit 600 per 60 s; namespace 1001/2001/3001. Falls back to allow-all if unbound. |
| AP-ENV-007 | RATE_LIMITER_INSTALLATION_ACTOR | rate limit binding | wrangler.toml | G09 | limit 120 per 60 s; namespace 1002/2002/3002. |
| AP-ENV-008 | RATE_LIMITER_INSTALLATION_CAPABILITY | rate limit binding | wrangler.toml | G08 | limit 300 per 60 s; namespace 1003/2003/3003. |
| AP-ENV-009 | BUILD_SHA | environment var | wrangler.toml | G00 | 'local' in every env; returned by /health. |
| AP-ENV-010 | ENVIRONMENT | environment var | wrangler.toml | G00 | development \|staging \|production; also gates harness paths and signing-key checks. |
| AP-ENV-011 | LOG_VERBOSITY | environment var | wrangler.toml | G00 | development 2, staging 1, production 0; default 2 in development else 0. |
| AP-ENV-012 | CONFIG_CACHE_TTL_MS | environment var | wrangler.toml | G00 | 100 development, 30000 staging/production. |
| AP-ENV-013 | ISSUER_ID | environment var | wrangler.toml | G08 | 'issuer-test' in all envs; expected iss of AI tokens and feed JWTs. |
| AP-ENV-014 | ACCESS_TEAM_DOMAIN | environment var | wrangler.toml | G00 | 'access.test' in all envs (placeholder); Cloudflare Access issuer domain. |
| AP-ENV-015 | ACCESS_AUD | environment var | wrangler.toml | G19 | 'vendor-access-aud' in all envs; Access JWT audience. |
| AP-ENV-016 | WEBAUTHN_RP_ID | environment var | wrangler.toml | G19 | 'ops.vendor.test' in all envs; relying-party id for operator assertions. |
| AP-ENV-017 | WEBAUTHN_ORIGIN | environment var | wrangler.toml | G19 | 'https://ops.vendor.test' in all envs. |
| AP-ENV-018 | HEARTBEAT_URL | environment var | wrangler.toml | G11 | 'https://heartbeat.test/ping' in all envs; fallback heartbeat URL. |
| AP-ENV-019 | ALERT_EMAIL_TO | environment var | wrangler.toml | G15 | 'alerts@clinic.invalid' in all envs; sender and recipient of alert emails. |
| AP-ENV-020 | DURATION_SCALE | environment var | wrangler.toml | G06 | Set to 'staging' only in env.staging; scales term durations when equal to 'staging'. |
| AP-ENV-021 | PLATFORM_SIGNING_KEY | secret / var | wrangler.toml; vendor entrypoint; quota-do | G00 | JSON {kid, pkcs8, public_key}. A development fixture is in env.development vars; staging/production values not in wrangler.toml (secret). Rejected if missing, malformed or the published development key (outside development). |
| AP-ENV-022 | DEEPSEEK_API_KEY | secret (dynamic binding) | provider/deepseek.ts; worker resolveProviderPort | G11 | Looked up by name from env at call time; not declared in wrangler.toml. |
| AP-ENV-023 | GEMINI_API_KEY | secret (dynamic binding) | provider/gemini.ts; worker resolveProviderPort | G11 | Looked up by name from env at call time; not declared in wrangler.toml. |
| AP-ENV-024 | HEARTBEAT_URL_PLATFORM | optional environment var | alert/index.ts | G11 | Overrides HEARTBEAT_URL for the platform 5-minute stream; not set in wrangler.toml. |
| AP-ENV-025 | ACCESS_CERTS_JSON | optional environment var | vendor/entrypoint.ts | G00 | Local test override of Access certificates JSON; when set, no network fetch. |
| AP-ENV-026 | TEST_CLOCK | optional environment var (harness) | clock.ts; worker | G00 | '1' enables D1 harness clock (harness_test_clock) and harness DO hooks; not set in wrangler.toml. |
| AP-ENV-027 | TEST_DO_ALARM_DELIVERY_DELAY_MS | optional environment var (harness) | quota-do/coverage.ts | G15 | Delays alarm delivery for tests (capped); not set in wrangler.toml. |
| AP-ENV-028 | OPERATOR_BEARER_TOKEN | local dev var file only | ai-platform/.dev.vars, .dev.vars.development | G00 | Present in local dev vars files; not read by any file under src. |
| AP-ENV-029 | [triggers] crons | wrangler trigger config | wrangler.toml | G15 | 0 3 * * *, 0 4 * * *, */5 * * * * (declared once at top level, not repeated per environment). |
| AP-ENV-030 | [[migrations]] tag v1 | Durable Object migration | wrangler.toml | G11 | new_sqlite_classes = [GatewayObject]. |
| AP-ENV-031 | [[rules]] Text **/prompts/**/*.md | bundler rule | wrangler.toml | G10 | Markdown prompt files imported as text. |
| AP-ENV-032 | compatibility_date 2026-05-03; observability enabled; workers_dev false; preview_urls false | worker settings | wrangler.toml | G01 | Worker name ai-platform-gateway; per-env names -development, -staging, -production. |
| AP-ENV-033 | Environments | wrangler environments | wrangler.toml | G07 | development, staging, production, each with own vars, D1, R2, DO binding, rate limiters, VENDOR service binding. |

## AP-HDR (7)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| AP-HDR-001 | Aip-Contract-Version (request and response) | HTTP header | vendor/contract-version.ts; worker | G07 | Required on /v1/capabilities, /v1/requests (POST and GET), /v1/coverage, /v1/feed/coverage. Response echoes negotiated version; JSON object bodies gain contract_version. |
| AP-HDR-002 | Authorization: Bearer | HTTP header | identity; worker | G08 | AI token (AAT) or feed JWT. |
| AP-HDR-003 | x-idempotency-key | HTTP request header | adapter | G04 | Required on POST /v1/requests. |
| AP-HDR-004 | x-capability-version | HTTP request header | adapter | G08 | Required on POST /v1/requests. |
| AP-HDR-005 | x-trace-id | HTTP request header | adapter; trace.ts | G13 | Optional; any non-empty value accepted; otherwise ULID generated. |
| AP-HDR-006 | If-None-Match / ETag / Cache-Control | HTTP headers | capability/index.ts | G08 | Capability discovery caching (private, must-revalidate). |
| AP-HDR-007 | query after, limit | query parameters | worker feed handler | G07 | Feed cursor and page size on /v1/feed/coverage. |

## SB-RPC (15)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-RPC-001 | `public.issue_billing_token(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER, search_path public+auth_internal | 20261007180000_issuer_key_custody (wrapper); body in SB-INT-001 | G03 | Callable by `authenticated` only (anon/PUBLIC revoked). Rejects NULL or version not in (0,1) with CONTRACT_VERSION_UNSUPPORTED, data `accepted_versions [0,1]`, contract_version 1. Then calls the internal minter. Only an administrator membership gets a token. |
| SB-RPC-002 | `public.issue_ai_token(p_contract_version integer DEFAULT NULL)` returns text | RPC wrapper, SECURITY DEFINER | 20261007180000_issuer_key_custody (wrapper); body in SB-INT-002 | G08 | Callable by `authenticated` only. Returns the raw signed token text (not rpc_result). Bad version raises exception CONTRACT_VERSION_UNSUPPORTED with DETAIL `{"accepted_versions":[0,1]}`. Other failures are raised exceptions (see error table). |
| SB-RPC-003 | `public.get_ai_status(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20261008010000_read_time_status_notices | G03 | Callable by `authenticated`. Any member of the active org (no role check). Version guard (0,1) as above. Returns read-time status from the coverage projection (SB-INT-011). |
| SB-RPC-004 | `public.get_ai_billing_status(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC, SECURITY DEFINER (no internal twin; logic is in the public function) | 20261008010000_read_time_status_notices | G07 | Callable by `authenticated`. Administrator membership only (FORBIDDEN_ROLE otherwise). Returns the get_ai_status data plus plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, queued_count, held_count, subscription_ref, abo_base_url. subscription_ref = `AIC-` + first 8 chars of a base32 (Crockford alphabet) encoding of sha256('sub-ref:' + org id). |
| SB-RPC-005 | `public.request_ai_status_refresh(p_contract_version integer DEFAULT NULL)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20261007230000_coverage_feed_puller_status (wrapper); body 20261022130000_rm36_status_refresh_claim (SB-INT-012) | G06 | EXECUTE granted to `authenticated` AND `anon` (PUBLIC revoked). Anonymous callers are stopped inside the body by the session check (returns UNAUTHENTICATED). Administrator only. Throttled per org to one accepted request per 10 seconds, then runs the feed pull once. |
| SB-RPC-006 | `public.record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb)` returns rpc_result | RPC wrapper, SECURITY DEFINER | 20260805150000_f2_review_resolution | G13 | Callable by `authenticated`. Records that a clinician accepted an AI output and runs the registered domain RPC in the same transaction. Body in SB-INT-014. |
| SB-RPC-007 | `public.get_visit_chief_complaint(p_visit_id uuid)` returns rpc_result | RPC wrapper, SECURITY INVOKER | 20260805120000_e3_review_recorded_at_created_at; ACL fixed in 20260905120500_revoke_get_visit_chief_complaint_public_anon | G11 | Callable by `authenticated` (PUBLIC and anon revoked). Context provider for the AI (visit chief complaint). Body in SB-INT-016. |
| SB-RPC-008 | `public.set_active_organization(p_organization_id uuid)` returns rpc_result | RPC, SECURITY DEFINER | 20261014170300_r1_sql03_live_staff_context | G01 | Callable by `authenticated`. Writes ai_internal.user_active_organization if the caller holds a membership in that org and is live staff. Error FORBIDDEN otherwise. The next token refresh carries the new `active_org` claim. |
| SB-RPC-009 | `public.current_org_id()` returns uuid | Helper function, SECURITY DEFINER, STABLE | 20261014170300_r1_sql03_live_staff_context | G13 | Callable by `authenticated`. Resolves the tenant: JWT `active_org` claim (if the claim key is present) else `organization_id` claim; must be a membership of the JWT sub and the sub must be live (non-deleted, active) staff; else NULL. Used by every token mint and status read. |
| SB-RPC-010 | `public.current_membership_role()` returns public.staff_role | Helper function, SECURITY DEFINER, STABLE | 20261002120000_membership_active_org | G08 | Callable by `authenticated`. Role from ai_internal.membership for (JWT sub, current_org_id()); NULL if no org. This is the role authority for billing and AI tokens. |
| SB-RPC-011 | `public.get_custom_claims(event jsonb)` returns jsonb | Auth hook function, SECURITY INVOKER | 20261002120000_membership_active_org | G11 | Registered in config.toml as the `custom_access_token` hook (`pg-functions://postgres/public/get_custom_claims`). Merges build_staff_claims output and sets or removes the `active_org` claim from sync_active_organization. An older overload `get_custom_claims(p_user_id uuid)` also exists from 20260521110000_auth_rbac_definer_internal_schema. |
| SB-RPC-012 | `public.jwt_organization_id()` returns uuid | Helper, SECURITY INVOKER, STABLE | 20261002120000_membership_active_org | G11 | Now just returns public.current_org_id(). Used by RLS policies. |
| SB-RPC-013 | `public.jwt_branch_ids()` returns uuid[] | Helper, SECURITY INVOKER, STABLE | 20261002150000_tenant_scoping | G11 | Reads the `branch_ids` claim. Used by the ai_accepted_output policy. |
| SB-RPC-014 | `public.request_jwt_claims()` returns jsonb | Helper, STABLE | 20260516100200_auth_rbac_rls (original) | G01 | Reads `request.jwt.claims` setting; used by current_org_id and set_active_organization. |
| SB-RPC-015 | `public.rpc_success(p_data jsonb DEFAULT '{}', p_contract_version integer DEFAULT NULL)` and `public.rpc_error(p_code text, p_message text, p_contract_version integer DEFAULT NULL)` | Helper constructors for rpc_result, IMMUTABLE | 20261007180000_issuer_key_custody | G03 | The two-argument forms were dropped and replaced by these with an optional contract version. |

## SB-INT (28)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-INT-001 | `auth_internal.issue_billing_token(p_contract_version integer)` returns rpc_result | SECURITY DEFINER, internal minter | 20261014170900_r2_c2_billing_token_error_versions | G17 | Steps: valid session; role must be administrator (current_membership_role); org from current_org_id; live active staff row for the caller; primary active branch of the org; the `signing` issuer key and its secret from the vault; per-staff advisory lock (key 87201402, text `<staff id>:abo`); rate limit 20 per 10 minutes counted on ai_token_issuance rows with aud 'abo'; token claims iss (setting ai.issuer_id), aud `abo`, sub staff id, org, branch, role `administrator`, jti, iat, exp = iat+300, ver `2`; header alg EdDSA, kid, typ JWT; both parts canonical JSON (RFC 8785 style) via SB-INT-006; signed with Ed25519; ledger row inserted with aud `abo`. Returns data token, abo_base_url (setting ai.abo_base_url, default http://127.0.0.1:8788), expires_at. Every error carries the negotiated contract_version. |
| SB-INT-002 | `auth_internal.issue_ai_token(p_contract_version integer)` returns text | SECURITY DEFINER, internal minter | 20261014170600_r1_sql06_issue_ai_token_rate_limit | G17 | Steps: valid session; org from current_org_id (else exception FORBIDDEN); live active staff; primary branch of the org; per-staff advisory lock (key 87201401, staff id); rate limit from settings ai.issuer.rate_limit.ceiling (default 100) per ai.issuer.rate_limit.window_seconds (default 3600) counted on rows with aud 'ai-platform'; signing issuer key + vault secret; scopes = all granted `ai.%` permission keys of (org, membership role) from roles_permissions, at least one required (else AI_ACCESS_DENIED). Claims: iss, aud `ai-platform`, sub staff id, org, branch, role (membership role), scopes (sorted array), jti, iat, exp = iat+600, ver `2`. Header alg EdDSA, kid, typ JWT. This token's JSON uses plain jsonb text (NOT the canonical function). Ledger row inserted with aud `ai-platform`. The p_contract_version argument is not used inside the body. |
| SB-INT-003 | `auth_internal.issue_feed_token()` returns text | SECURITY DEFINER, internal minter | 20261014170100_canonical_feed_jwt_json | G17 | Mints a token for the coverage feed pull: aud `ai-platform-feed`, sub `backend-feed`, jti, iat, exp = iat+120, ver `2`, iss from ai.issuer_id, canonical JSON. No ledger row. Raises ISSUER_KEY_NOT_CONFIGURED if no signing key or secret. EXECUTE revoked from everyone including service_role. |
| SB-INT-004 | `auth_internal.insert_issuer_kid()` returns table(kid, public_key, status, not_before, not_after) | SECURITY DEFINER, key generator | 20261007180000_issuer_key_custody | G17 | Returns the existing `next` key if one exists. Otherwise generates an Ed25519 keypair (pgsodium), stores the private key in the vault (secret name `issuer-key-<kid>`, description 'Ed25519 issuer private key'), inserts a row with status `signing` if no signing key yet else `next`, not_before now, not_after now + 13 months. The migration calls it once at install, so a first `signing` key exists after migration. |
| SB-INT-005 | `auth_internal.switch_issuer_signing_kid(p_kid text)` returns void | SECURITY DEFINER, rotation switch | 20261007180000_issuer_key_custody | G17 | If the given kid has status `next`: current `signing` becomes `retired`, the given kid becomes `signing`. Otherwise silently returns. EXECUTE revoked from all client roles and service_role. |
| SB-INT-006 | `auth_internal.canonical_issuer_jwt_json(p_value jsonb)` returns text | IMMUTABLE STRICT helper | 20261014170000_canonical_billing_jwt_json | G08 | Produces RFC 8785 canonical JSON: keys sorted bytewise, no whitespace, ASCII keys only, integers only (safe integer range). Exceptions: 'issuer JWT JSON keys must be ASCII', 'issuer JWT numbers must be safe integers', 'unsupported issuer JWT JSON value: <kind>'. Used by billing and feed tokens, not the AI token. |
| SB-INT-007 | `auth_internal.base64url_encode(bytea)` and `auth_internal.base64url_decode(text)` | IMMUTABLE helpers | 20260801120000_ai_keystore_schema (re-defined 20260801120200) | G01 | Base64url without padding. EXECUTE revoked from client roles. |
| SB-INT-008 | `auth_internal.ai_app_setting_numeric(p_key text, p_default numeric)` and `auth_internal.ai_app_setting_text(p_key text, p_default text)` | STABLE SECURITY DEFINER readers | 20260801120200_ai_token_issuer_rpc | G01 | Read ai_internal.app_settings by key where is_deleted = false, falling back to the default. Text reader strips surrounding double quotes. |
| SB-INT-009 | `auth_internal.assert_valid_ai_session()` returns uuid | STABLE SECURITY DEFINER | 20260801120200_ai_token_issuer_rpc | G11 | Requires auth.uid() and a `sub` claim (else exception UNAUTHENTICATED); if `exp` claim is in the past raises SESSION_EXPIRED. Returns the user id. |
| SB-INT-010 | `auth_internal.verify_aat(p_token text)` returns boolean | STABLE SECURITY DEFINER, self-test verifier | 20261007180000_issuer_key_custody | G17 | Verifies a token's Ed25519 signature against ai_internal.issuer_key by header kid (rejects retired or unknown kid, wrong alg, wrong iss vs ai.issuer_id). Does not check exp. Returns true/false, never raises. EXECUTE revoked from client roles. |
| SB-INT-011 | `auth_internal.get_ai_status(p_contract_version integer)` returns rpc_result | STABLE SECURITY DEFINER | 20261008010000_read_time_status_notices | G20 | Computes at read time from clinic_ai_coverage plus feed_state. Output fields: available, state, reason, days_left, band, notices, next_change_at, as_of, stale, platform_base_url (setting ai.platform_base_url, default http://127.0.0.1:8787). `stale` = feed never succeeded or last success older than 2 minutes. State values produced: none, suspended, active, grace, lapsed, or the stored state text (e.g. exhausted, reversed, others). Notice codes: ends_soon (days_left 7, 3, or <=1 and no queued terms), in_grace (with grace_days_left), allowance_low (band 75 or 90), allowance_exhausted, lapsed, ended_reversed, suspended, status_stale. Each notice has audience `member` and channel `in_app`. No coverage row gives state `none` and reason `none`. Requires an org (FORBIDDEN otherwise). |
| SB-INT-012 | `auth_internal.request_ai_status_refresh(p_contract_version integer)` returns rpc_result | SECURITY DEFINER | 20261022130000_rm36_status_refresh_claim | G07 | Session check, administrator role (FORBIDDEN_ROLE), org (FORBIDDEN). Claims the 10-second window with one conditional insert/upsert on ai_internal.status_refresh (accepts when last request is at least 10 s old). If not claimed, RATE_LIMITED. Then runs pull_coverage_feed once and returns requested_at. UNAUTHENTICATED / SESSION_EXPIRED are returned as rpc_error with the same text as code and message. |
| SB-INT-013 | `auth_internal.pull_coverage_feed()` returns void | SECURITY DEFINER | 20261007230000_coverage_feed_puller_status | G20 | The feed puller. Locks the singleton feed_state row. If a pending HTTP request id exists: reads the response from the pg_net response table (net._http_response); no response and pending under 5 minutes = return; older than 5 minutes = clear pending and add one failure. A valid page needs status 200, JSON body, body contract_version equal to the platformFeed current version from ai.contract_versions, header `aip-contract-version` equal to it, body `after` equal to the stored cursor, and strictly increasing event feed_seq. Valid page: upsert each event's snapshot into clinic_ai_coverage (only if the new binding_epoch is higher, or equal epoch with higher clinic_seq), set cursor to `next_after`, last_success_at now, failures 0. Invalid page or timeout: failures + 1. Then sends a new GET `<ai.platform_base_url>/v1/feed/coverage?after=<cursor>&limit=200` with headers `Authorization: Bearer <feed token>` and `Aip-Contract-Version`; localhost / 127.0.0.1 in the URL is rewritten to host.docker.internal; stores the request id and pending_since. Event fields read: feed_seq, org_id, installation_id, binding_epoch, clinic_seq, at, snapshot{state, reason, term{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}, queued_count, held_count, suspended}. For states active and grace the stored reason is NULL. |
| SB-INT-014 | `auth_internal.record_ai_acceptance(p_request_reference text, p_target_key text, p_target_args jsonb)` returns rpc_result | SECURITY DEFINER | 20260805150000_f2_review_resolution | G13 | Order: validate reference format (4+4 Crockford characters with a dash, e.g. XXXX-XXXX) else INVALID_INPUT; look up target in acceptance_targets else INVALID_INPUT; reject if the same reference was already accepted for the same table_name (INVALID_INPUT, 'already accepted'); org required (FORBIDDEN); run the domain RPC (SB-INT-015); if it fails return its error; take record id from data record_id, visit_id or id (else raises an exception so the whole transaction rolls back); branch from visits; insert audit_log row (action `ai.acceptance_record`, new_data_json ai_request_reference + acceptance_id); insert ai_accepted_output row. Returns the domain data plus acceptance_id, table_name, record_id, audit_log_id. |
| SB-INT-015 | `auth_internal.invoke_acceptance_domain_rpc(p_domain_function text, p_target_args jsonb)` returns rpc_result | SECURITY DEFINER, dynamic dispatch | 20261007180000_issuer_key_custody | G03 | Only runs a function listed in acceptance_targets.domain_function. Finds the public function by name returning rpc_result, builds a call that pulls each argument by its parameter name from the JSON object and casts to the parameter type, executes it, re-wraps the result with contract_version NULL. INTERNAL_ERROR 'Domain function is not configured.' when not registered, not found, or no arguments. |
| SB-INT-016 | `auth_internal.get_visit_chief_complaint(p_visit_id uuid)` returns rpc_result | SECURITY DEFINER | 20260805120000_e3_review_recorded_at_created_at | G01 | Checks visit branch scope (NOT_FOUND) and clinical access permission (FORBIDDEN). Returns visit_id, complaint (if any), recorded_at (UTC ISO string from visit_clinical_notes.created_at). |
| SB-INT-017 | `ai_internal.launch_state()` returns jsonb | STABLE SECURITY DEFINER, read-only | 20261022120000_rm35_launch_state_reader | G03 | Returns keys database_name, contract_versions (value of ai.contract_versions), set_ai_availability_present (whether any function named set_ai_availability exists). Executable only by role `launch_check_reader`. |
| SB-INT-018 | `auth_internal.sync_active_organization(p_user_id uuid)` returns uuid | VOLATILE SECURITY DEFINER | 20261014170300_r1_sql03_live_staff_context | G06 | Called by the token hook. Returns NULL for non-live staff. Keeps the stored active org while membership exists, else picks the first membership (by created_at, organization_id), else deletes the stored row and returns NULL. EXECUTE granted to `supabase_auth_admin` (if the role exists). |
| SB-INT-019 | `auth_internal.upsert_organization_membership(p_user_id uuid, p_organization_id uuid, p_role public.staff_role)` returns void | SECURITY DEFINER | 20261009120000_fix_staff_membership_session_rls | G01 | Writes ai_internal.membership (conflict updates the role). Called by bootstrap and staff provisioning RPCs. |
| SB-INT-020 | `auth_internal.update_staff_member(...)` | SECURITY DEFINER | 20261014170400_r1_sql02_update_staff_member_membership_sync | G03 | Staff update RPC that also updates ai_internal.membership.role for the current org in the same transaction (so a demoted administrator can no longer mint billing tokens). Error codes seen in it: INVALID_INPUT, STAFF_NOT_FOUND, CROSS_ORG_DENIED, MEMBERSHIP_NOT_FOUND, LAST_ADMINISTRATOR, INVALID_BRANCH, FORBIDDEN. |
| SB-INT-021 | `auth_internal.assert_owner_or_administrator()` returns staff_members row | SECURITY DEFINER | 20261014170700_r1_sql04_membership_role_authority | G11 | Requires live active staff and membership role administrator (a bootstrap admin passes only while no organization exists). Raises FORBIDDEN. |
| SB-INT-022 | `auth_internal.build_staff_claims(p_user_id uuid)` returns jsonb | STABLE SECURITY DEFINER | 20260611150000_remove_owner_role | G01 | Claims for the Supabase session token: staff_member_id, staff_role, organization_id (earliest non-deleted org; omitted while setup is required), branch_ids (comma list), setup_required. Administrators get all active branches of that org, others their assigned branches. |
| SB-INT-023 | `auth_internal.assert_permission(p_permission_key text)` and `auth_internal.staff_has_membership_permissions(...)` | SECURITY DEFINER | 20261014170700_r1_sql04_membership_role_authority | G11 | Permission check against roles_permissions for (current org, membership role). Raises FORBIDDEN. |
| SB-INT-024 | `auth_internal.seed_roles_permissions_defaults(p_organization_id uuid)` and trigger function `auth_internal.trg_seed_roles_permissions_defaults()` | SECURITY DEFINER | 20261002150000_tenant_scoping | G01 | Copies the default permission template (which includes the `ai.access` / `ai.visit_summary` keys) into roles_permissions for a new organization. |
| SB-INT-025 | `auth_internal.update_role_permission(...)` and `auth_internal.update_role_permissions(p_changes jsonb)` | SECURITY DEFINER | 20261002150000_tenant_scoping | G08 | Administrator-facing changes to per-org permission rows; these decide which `ai.*` scopes later appear in the AI token. |
| SB-INT-026 | `auth_internal.user_has_organization_membership(p_user_id uuid, p_organization_id uuid)` | SECURITY DEFINER | 20261002150000_tenant_scoping | G06 | Used by the staff_members select policy. EXECUTE granted to `authenticated`. |
| SB-INT-027 | `auth_internal.delete_clinic_test_fixtures(p_preserve_staff_ids uuid[])` | SECURITY DEFINER, test helper | 20261007180000_issuer_key_custody | G18 | Deletes all ai_token_issuance rows and all ai_accepted_output rows (plus staff, branches, organizations, audit_log, public app_settings, subscription_cache) when present. Not an erasure feature; a test/dev reset helper. |
| SB-INT-028 | `public.save_visit_documentation(p_visit_id uuid, p_expected_updated_at timestamptz, p_complaint text, p_history text, p_examination text, p_diagnosis text, p_plan text)` | Domain RPC used as the only registered acceptance target | 20260711120000_coderabbit_review_fixes | G13 | Registered in acceptance_targets under key `visit_clinical_notes`. Requires permission `visits.edit_soap`. Listed here because record_ai_acceptance dispatches to it by argument names p_visit_id, p_expected_updated_at, p_complaint, p_history, p_examination, p_diagnosis, p_plan. |

## SB-TABLE (19)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TABLE-001 | `ai_internal.app_settings` | Table, RLS on, deny-all policy | 20260801120000_ai_keystore_schema | G01 | Global key/value config for AI and billing. No client access. Keys in section 9. |
| SB-TABLE-002 | `ai_internal.ai_token_issuance` | Table, RLS on | 20261007180000_issuer_key_custody (aud added, installation_id dropped); 20261002150000_tenant_scoping (organization_id, select policy) | G06 | One row per minted token (both aud values). Authenticated users may SELECT rows of their own active org (policy SB-RLS-002). No insert/update/delete grant. |
| SB-TABLE-003 | `ai_internal.issuer_key` | Table, RLS on, deny-all policy | 20261007180000_issuer_key_custody | G17 | Issuer signing key registry. Private key is not in the table; secret_ref points to a vault secret. |
| SB-TABLE-004 | `ai_internal.acceptance_targets` | Table (registry), no RLS, all privileges revoked from client roles; SELECT granted to postgres | 20260802150000_ai_acceptance_recording | G06 | One seed row: target_key `visit_clinical_notes`, domain_function `save_visit_documentation`, table_name `visit_clinical_notes`. |
| SB-TABLE-005 | `public.ai_accepted_output` | Table, RLS on | 20260802150000_ai_acceptance_recording | G13 | One row per accepted AI output. Authenticated SELECT only, via policy SB-RLS-003. Rows are written only by record_ai_acceptance. |
| SB-TABLE-006 | `ai_internal.clinic_ai_coverage` | Table, RLS on, deny-all | 20261007230000_coverage_feed_puller_status | G07 | Per-organization projection of the coverage feed; one row per org. |
| SB-TABLE-007 | `ai_internal.feed_state` | Table, RLS on, deny-all, singleton | 20261007230000_coverage_feed_puller_status | G01 | Single row (singleton = true) holding the feed cursor and pending request. Seeded with cursor 0 and 0 failures. |
| SB-TABLE-008 | `ai_internal.status_refresh` | Table, RLS on, deny-all | 20261007230000_coverage_feed_puller_status | G13 | Throttle record, one row per org. |
| SB-TABLE-009 | `ai_internal.membership` | Table, RLS on, deny-all | 20261002120000_membership_active_org | G01 | (user, organization, role). The role authority for tokens. Backfilled from staff_members at creation. |
| SB-TABLE-010 | `ai_internal.user_active_organization` | Table, RLS on, deny-all | 20261002120000_membership_active_org | G01 | The organization the session acts in. |
| SB-TABLE-011 | `ai_internal.membership_role_repair_mapping` | Table, RLS on, deny-all | 20261014170500_r1_sql02_membership_role_repair | G01 | Approved per-org roles used by a one-time data repair; check constraint forbids approved_role administrator. The repair migration raises MEMBERSHIP_ROLE_REPAIR_HELD_ROWS if unresolved rows remain. |
| SB-TABLE-012 | `auth_internal.roles_permissions_default_template` | Table, RLS on, deny-all | 20261002150000_tenant_scoping | G01 | Default permission matrix copied to each new organization. |
| SB-TABLE-013 | `public.roles_permissions` | Table, RLS on | 20261002150000_tenant_scoping | G08 | Per-organization role/permission rows. The `ai.%` keys here become the AI token scopes. |
| SB-TABLE-014 | `public.staff_members` | Table, RLS on | 20260516100000_auth_rbac_schema (+ later column additions) | G01 | The token subject (`sub` = staff_members.id). |
| SB-TABLE-015 | `public.staff_branch_assignments` | Table, RLS on | 20260516100000_auth_rbac_schema | G01 | Source of the token `branch` claim (primary active branch). |
| SB-TABLE-016 | `public.organizations` | Table, RLS on | 20260516100000_auth_rbac_schema | G07 | Token `org` claim comes from here via membership. Has legacy columns subscription_tier and subscription_valid_until. |
| SB-TABLE-017 | `public.branches` | Table, RLS on | 20260516100000_auth_rbac_schema (+ working_schedule) | G01 | Branch must be active and in the org. |
| SB-TABLE-018 | `public.audit_log` | Table, RLS on | 20260516100000_auth_rbac_schema (column renamed in 20260524150000) | G13 | Receives the `ai.acceptance_record` row. Direct INSERT/UPDATE/DELETE denied to clients (20260524140100). |
| SB-TABLE-019 | `public.subscription_cache` | Table, RLS on | 20260516100000_auth_rbac_schema | G07 | Legacy: comment says cached subscription status from an external billing system (future). No function reads it in the latest state; only cleanup helpers delete from it. Select policy by org; client writes denied. |

## SB-COL (95)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-COL-001 | ai_internal.app_settings.key | text, primary key | SB-TABLE-001 | G01 | Setting name. |
| SB-COL-002 | ai_internal.app_settings.value_json | jsonb, not null | SB-TABLE-001 | G01 | Setting value. |
| SB-COL-003 | ai_internal.app_settings.created_at | timestamptz, default now() | SB-TABLE-001 | G01 |  |
| SB-COL-004 | ai_internal.app_settings.created_by | uuid, FK auth.users | SB-TABLE-001 | G01 |  |
| SB-COL-005 | ai_internal.app_settings.updated_at | timestamptz | SB-TABLE-001 | G01 |  |
| SB-COL-006 | ai_internal.app_settings.updated_by | uuid, FK auth.users | SB-TABLE-001 | G01 |  |
| SB-COL-007 | ai_internal.app_settings.is_deleted | boolean, default false | SB-TABLE-001 | G01 | Soft delete; readers filter on it. |
| SB-COL-008 | ai_internal.app_settings.deleted_at | timestamptz | SB-TABLE-001 | G01 |  |
| SB-COL-009 | ai_internal.app_settings.deleted_by | uuid, FK auth.users | SB-TABLE-001 | G01 |  |
| SB-COL-010 | ai_internal.ai_token_issuance.issuance_id | uuid, primary key, default gen_random_uuid() | SB-TABLE-002 | G08 |  |
| SB-COL-011 | ai_internal.ai_token_issuance.jti | uuid, not null, unique | SB-TABLE-002 | G08 | Token id placed in the token. |
| SB-COL-012 | ai_internal.ai_token_issuance.actor_staff_id | uuid, not null, FK staff_members | SB-TABLE-002 | G08 | Who minted. |
| SB-COL-013 | ai_internal.ai_token_issuance.iat | timestamptz, not null | SB-TABLE-002 | G08 | Issued-at; used by the rate-limit count. |
| SB-COL-014 | ai_internal.ai_token_issuance.created_at | timestamptz, default now() | SB-TABLE-002 | G08 |  |
| SB-COL-015 | ai_internal.ai_token_issuance.created_by | uuid, FK auth.users | SB-TABLE-002 | G08 | Set to the caller's user id by the minters. |
| SB-COL-016 | ai_internal.ai_token_issuance.updated_at | timestamptz | SB-TABLE-002 | G08 |  |
| SB-COL-017 | ai_internal.ai_token_issuance.updated_by | uuid, FK auth.users | SB-TABLE-002 | G08 |  |
| SB-COL-018 | ai_internal.ai_token_issuance.is_deleted | boolean, default false | SB-TABLE-002 | G08 |  |
| SB-COL-019 | ai_internal.ai_token_issuance.deleted_at | timestamptz | SB-TABLE-002 | G08 |  |
| SB-COL-020 | ai_internal.ai_token_issuance.deleted_by | uuid, FK auth.users | SB-TABLE-002 | G08 |  |
| SB-COL-021 | ai_internal.ai_token_issuance.aud | text, not null | SB-TABLE-002 | G08 | `ai-platform` or `abo`. Old rows were back-filled to `ai-platform`. |
| SB-COL-022 | ai_internal.ai_token_issuance.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-002 | G08 |  |
| SB-COL-023 | ai_internal.issuer_key.kid | text, primary key, default gen_random_uuid()::text | SB-TABLE-003 | G17 |  |
| SB-COL-024 | ai_internal.issuer_key.public_key | text, not null | SB-TABLE-003 | G17 | Base64url Ed25519 public key. |
| SB-COL-025 | ai_internal.issuer_key.secret_ref | uuid, not null | SB-TABLE-003 | G17 | Id of the vault secret holding the private key (base64). |
| SB-COL-026 | ai_internal.issuer_key.status | text, not null, check in (signing, next, retired) | SB-TABLE-003 | G17 | At most one `signing` and one `next` (partial unique indexes). |
| SB-COL-027 | ai_internal.issuer_key.not_before | timestamptz, not null | SB-TABLE-003 | G17 |  |
| SB-COL-028 | ai_internal.issuer_key.not_after | timestamptz, not null | SB-TABLE-003 | G17 | Set to creation + 13 months. No code reads it. |
| SB-COL-029 | ai_internal.acceptance_targets.target_key | text, primary key | SB-TABLE-004 | G13 |  |
| SB-COL-030 | ai_internal.acceptance_targets.domain_function | text, not null | SB-TABLE-004 | G13 | Name of the public function to run. |
| SB-COL-031 | ai_internal.acceptance_targets.table_name | text, not null | SB-TABLE-004 | G13 | Provenance table name recorded in ai_accepted_output. |
| SB-COL-032 | public.ai_accepted_output.id | uuid, primary key | SB-TABLE-005 | G13 |  |
| SB-COL-033 | public.ai_accepted_output.organization_id | uuid, not null, FK organizations | SB-TABLE-005 | G13 |  |
| SB-COL-034 | public.ai_accepted_output.branch_id | uuid, FK branches | SB-TABLE-005 | G13 | From the visit; may be NULL. |
| SB-COL-035 | public.ai_accepted_output.table_name | text, not null | SB-TABLE-005 | G13 |  |
| SB-COL-036 | public.ai_accepted_output.record_id | uuid, not null | SB-TABLE-005 | G13 | The domain row written. |
| SB-COL-037 | public.ai_accepted_output.ai_request_reference | text, not null, check format `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$` | SB-TABLE-005 | G12 | The AI request's support reference. |
| SB-COL-038 | public.ai_accepted_output.accepted_by | uuid, not null, FK auth.users | SB-TABLE-005 | G13 |  |
| SB-COL-039 | public.ai_accepted_output.accepted_at | timestamptz, not null, default now() | SB-TABLE-005 | G13 |  |
| SB-COL-040 | public.ai_accepted_output.audit_log_id | uuid, not null, FK audit_log | SB-TABLE-005 | G13 |  |
| SB-COL-041 | ai_internal.clinic_ai_coverage.organization_id | uuid, primary key | SB-TABLE-006 | G07 |  |
| SB-COL-042 | ai_internal.clinic_ai_coverage.installation_id | uuid, not null | SB-TABLE-006 | G07 | From the feed event. |
| SB-COL-043 | ai_internal.clinic_ai_coverage.binding_epoch | bigint, not null | SB-TABLE-006 | G07 | Ordering key (higher wins). |
| SB-COL-044 | ai_internal.clinic_ai_coverage.clinic_seq | bigint, not null | SB-TABLE-006 | G07 | Ordering key within an epoch. |
| SB-COL-045 | ai_internal.clinic_ai_coverage.state | text, not null | SB-TABLE-006 | G07 | Snapshot state text. |
| SB-COL-046 | ai_internal.clinic_ai_coverage.reason | text | SB-TABLE-006 | G07 | NULL for states active and grace. |
| SB-COL-047 | ai_internal.clinic_ai_coverage.term_ref | text | SB-TABLE-006 | G06 | term.ref |
| SB-COL-048 | ai_internal.clinic_ai_coverage.plan_display_name | text | SB-TABLE-006 | G07 |  |
| SB-COL-049 | ai_internal.clinic_ai_coverage.starts_at | timestamptz | SB-TABLE-006 | G07 |  |
| SB-COL-050 | ai_internal.clinic_ai_coverage.ends_at | timestamptz | SB-TABLE-006 | G07 |  |
| SB-COL-051 | ai_internal.clinic_ai_coverage.grace_ends_at | timestamptz | SB-TABLE-006 | G07 |  |
| SB-COL-052 | ai_internal.clinic_ai_coverage.allowance | integer | SB-TABLE-006 | G07 |  |
| SB-COL-053 | ai_internal.clinic_ai_coverage.used | integer | SB-TABLE-006 | G07 |  |
| SB-COL-054 | ai_internal.clinic_ai_coverage.band | text | SB-TABLE-006 | G07 | Used-allowance band; notices react to '75' and '90'. |
| SB-COL-055 | ai_internal.clinic_ai_coverage.queued_count | integer, not null | SB-TABLE-006 | G07 |  |
| SB-COL-056 | ai_internal.clinic_ai_coverage.held_count | integer, not null | SB-TABLE-006 | G07 |  |
| SB-COL-057 | ai_internal.clinic_ai_coverage.suspended | boolean, not null | SB-TABLE-006 | G20 |  |
| SB-COL-058 | ai_internal.clinic_ai_coverage.event_at | timestamptz, not null | SB-TABLE-006 | G07 | Event `at`. |
| SB-COL-059 | ai_internal.clinic_ai_coverage.applied_at | timestamptz, not null | SB-TABLE-006 | G06 | now() at apply time. |
| SB-COL-060 | ai_internal.feed_state.singleton | boolean, primary key, check singleton | SB-TABLE-007 | G01 | Always true. |
| SB-COL-061 | ai_internal.feed_state.cursor | bigint, not null | SB-TABLE-007 | G01 | Last applied feed position. |
| SB-COL-062 | ai_internal.feed_state.pending_request_id | bigint | SB-TABLE-007 | G01 | pg_net request id in flight. |
| SB-COL-063 | ai_internal.feed_state.pending_since | timestamptz | SB-TABLE-007 | G01 |  |
| SB-COL-064 | ai_internal.feed_state.last_success_at | timestamptz | SB-TABLE-007 | G01 | Drives `stale`. |
| SB-COL-065 | ai_internal.feed_state.consecutive_failures | integer, not null | SB-TABLE-007 | G01 |  |
| SB-COL-066 | ai_internal.status_refresh.organization_id | uuid, primary key | SB-TABLE-008 | G13 |  |
| SB-COL-067 | ai_internal.status_refresh.requested_at | timestamptz, not null | SB-TABLE-008 | G13 |  |
| SB-COL-068 | ai_internal.membership.user_id | uuid, FK auth.users ON DELETE CASCADE, part of PK | SB-TABLE-009 | G01 |  |
| SB-COL-069 | ai_internal.membership.organization_id | uuid, FK organizations ON DELETE CASCADE, part of PK | SB-TABLE-009 | G01 |  |
| SB-COL-070 | ai_internal.membership.role | public.staff_role, not null | SB-TABLE-009 | G01 |  |
| SB-COL-071 | ai_internal.membership.created_at | timestamptz, default now() | SB-TABLE-009 | G01 |  |
| SB-COL-072 | ai_internal.user_active_organization.user_id | uuid, primary key, FK auth.users ON DELETE CASCADE | SB-TABLE-010 | G01 |  |
| SB-COL-073 | ai_internal.user_active_organization.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-010 | G01 |  |
| SB-COL-074 | ai_internal.user_active_organization.updated_at | timestamptz, default now() | SB-TABLE-010 | G01 |  |
| SB-COL-075 | ai_internal.membership_role_repair_mapping.user_id | uuid, part of PK | SB-TABLE-011 | G01 |  |
| SB-COL-076 | ai_internal.membership_role_repair_mapping.organization_id | uuid, part of PK | SB-TABLE-011 | G01 |  |
| SB-COL-077 | ai_internal.membership_role_repair_mapping.approved_role | staff_role, not null | SB-TABLE-011 | G01 | Cannot be administrator. |
| SB-COL-078 | ai_internal.membership_role_repair_mapping.approved_by | text, not null | SB-TABLE-011 | G01 |  |
| SB-COL-079 | ai_internal.membership_role_repair_mapping.approved_note | text | SB-TABLE-011 | G01 |  |
| SB-COL-080 | ai_internal.membership_role_repair_mapping.approved_at | timestamptz, default now() | SB-TABLE-011 | G01 |  |
| SB-COL-081 | auth_internal.roles_permissions_default_template.role | staff_role, part of PK | SB-TABLE-012 | G01 |  |
| SB-COL-082 | auth_internal.roles_permissions_default_template.permission_key | text, part of PK | SB-TABLE-012 | G01 |  |
| SB-COL-083 | auth_internal.roles_permissions_default_template.is_granted | boolean, not null | SB-TABLE-012 | G06 |  |
| SB-COL-084 | public.roles_permissions.id | uuid, primary key | SB-TABLE-013 | G01 |  |
| SB-COL-085 | public.roles_permissions.role | staff_role, not null | SB-TABLE-013 | G01 |  |
| SB-COL-086 | public.roles_permissions.permission_key | text, not null | SB-TABLE-013 | G01 | `ai.%` keys become token scopes. |
| SB-COL-087 | public.roles_permissions.is_granted | boolean, not null | SB-TABLE-013 | G06 |  |
| SB-COL-088 | public.roles_permissions.created_at / created_by / updated_at / updated_by / is_deleted / deleted_at / deleted_by | standard audit and soft-delete columns | SB-TABLE-013 | G01 | Seven columns. |
| SB-COL-089 | public.roles_permissions.organization_id | uuid, not null, FK organizations ON DELETE CASCADE | SB-TABLE-013 | G01 | Unique with (role, permission_key). |
| SB-COL-090 | public.staff_members.id, auth_user_id, full_name, role, phone, is_active, is_bootstrap_admin, must_change_password | main columns (id PK; auth_user_id unique FK auth.users; role staff_role; is_active default true; is_bootstrap_admin default false; must_change_password default false added in 20260524110400) | SB-TABLE-014 | G01 | Plus the standard created_at, created_by, updated_at, updated_by, is_deleted, deleted_at, deleted_by. Other columns (e.g. username) may have been added by later staff migrations outside this inventory's scope. |
| SB-COL-091 | public.staff_branch_assignments.id, staff_member_id, branch_id, is_primary | main columns | SB-TABLE-015 | G01 | Unique (staff_member_id, branch_id); plus the standard audit and soft-delete columns. `is_primary` orders branch choice for the token. |
| SB-COL-092 | public.organizations.id, name, logo_url, currency_code, timezone, subscription_tier, subscription_valid_until, settings_json | main columns | SB-TABLE-016 | G07 | Plus the standard audit and soft-delete columns. |
| SB-COL-093 | public.branches.id, organization_id, name, code, address, phone, maps_url, is_active, working_schedule | main columns | SB-TABLE-017 | G15 | Plus the standard audit and soft-delete columns. |
| SB-COL-094 | public.audit_log.id, user_id, organization_id, action, table_name, record_id, old_data_json, new_data_json, ip_address, created_at | all columns (the original `timestamp` column was renamed `created_at`) | SB-TABLE-018 | G01 |  |
| SB-COL-095 | public.subscription_cache.organization_id, tier, valid_until, last_checked_at | all columns | SB-TABLE-019 | G07 | organization_id is primary key, FK organizations ON DELETE CASCADE. |

## SB-TRIG (3)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TRIG-001 | `seed_roles_permissions_defaults` on `public.organizations` | AFTER INSERT, per row, runs auth_internal.trg_seed_roles_permissions_defaults | 20261002150000_tenant_scoping | G01 | Creates the default permission rows (including the `ai.*` keys) for each new organization. |
| SB-TRIG-002 | `fill_tenant_organization_id` on appointments, visits, visit_clinical_notes, visit_vital_signs, visit_investigations, visit_attachments, treatment_plans, invoice_items, payments, invoice_number_sequences, patient_allergies, patient_medications, patient_chronic_conditions, service_branches, shift_assignments | Tenant fill triggers (function auth_internal.trg_fill_tenant_organization_id) | 20261002150000_tenant_scoping | G07 | Not AI-specific; listed because the AI acceptance target and context provider read visit_clinical_notes and visits, which carry this trigger. |
| SB-TRIG-003 | `installation_keys_single_installation` on `ai_internal.installation_keys` | BEFORE INSERT OR UPDATE | created 20260801120000_ai_keystore_schema; DROPPED in 20261007180000_issuer_key_custody | G02 | Dropped. Raised SINGLE_INSTALLATION_VIOLATION when a second installation id appeared. See Dropped category. |

## SB-RLS (19)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-RLS-001 | `app_settings_deny_all` on ai_internal.app_settings | FOR ALL USING (false) | 20260801120000_ai_keystore_schema | G01 |  |
| SB-RLS-002 | `ai_token_issuance_select` on ai_internal.ai_token_issuance | FOR SELECT TO authenticated USING is_deleted = false AND organization_id = current_org_id() | 20261002150000_tenant_scoping | G06 | Replaced the deny-all policy. Schema USAGE and table SELECT are granted to authenticated. |
| SB-RLS-003 | `ai_accepted_output_select` on public.ai_accepted_output | FOR SELECT TO authenticated USING organization_id = jwt_organization_id() AND (branch_id IS NULL OR branch_id = ANY(jwt_branch_ids())) | 20260802150000_ai_acceptance_recording | G06 | No insert/update/delete policy or grant (SELECT only granted). |
| SB-RLS-004 | `issuer_key_deny_all` on ai_internal.issuer_key | FOR ALL USING (false) | 20261007180000_issuer_key_custody | G17 |  |
| SB-RLS-005 | `clinic_ai_coverage_deny_all` on ai_internal.clinic_ai_coverage | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | G07 |  |
| SB-RLS-006 | `feed_state_deny_all` on ai_internal.feed_state | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | G01 |  |
| SB-RLS-007 | `status_refresh_deny_all` on ai_internal.status_refresh | FOR ALL USING (false) | 20261007230000_coverage_feed_puller_status | G13 |  |
| SB-RLS-008 | `membership_deny_all` on ai_internal.membership | FOR ALL USING (false) | 20261002120000_membership_active_org | G01 |  |
| SB-RLS-009 | `user_active_organization_deny_all` on ai_internal.user_active_organization | FOR ALL USING (false) | 20261002120000_membership_active_org | G01 |  |
| SB-RLS-010 | `membership_role_repair_mapping_deny_all` on ai_internal.membership_role_repair_mapping | FOR ALL USING (false) | 20261014170500_r1_sql02_membership_role_repair | G01 |  |
| SB-RLS-011 | `roles_permissions_default_template_deny_all` on auth_internal.roles_permissions_default_template | FOR ALL USING (false) | 20261002150000_tenant_scoping | G01 |  |
| SB-RLS-012 | `roles_permissions_select` on public.roles_permissions | FOR SELECT TO authenticated USING is_deleted = false AND organization_id = current_org_id() AND (is_granted OR membership role administrator) | 20261002150000_tenant_scoping | G06 |  |
| SB-RLS-013 | `staff_members_select` on public.staff_members | FOR SELECT TO authenticated: own row, or a member of the same current org | 20261009120000_fix_staff_membership_session_rls | G06 | The earlier `staff_members_update` policy and the table UPDATE grant were removed in 20261014170200_r1_sql01_staff_update_grant_closure. |
| SB-RLS-014 | `staff_branch_assignments_select` on public.staff_branch_assignments | FOR SELECT TO authenticated | 20261009120000_fix_staff_membership_session_rls | G01 | Setup-required path or own assignments in the current org. |
| SB-RLS-015 | `organizations_select`, `organizations_insert`, `organizations_update`; `branches_select`, `branches_insert`, `branches_update` | Tenant policies using jwt_organization_id() | 20260516100200_auth_rbac_rls | G01 | jwt_organization_id() now delegates to current_org_id(), so these follow the membership-based tenant. |
| SB-RLS-016 | `audit_log_select` plus `audit_log_deny_insert`, `audit_log_deny_update`, `audit_log_deny_delete` on public.audit_log | Select policy plus deny policies | 20260516100200_auth_rbac_rls; 20260524140100_fix_audit_log_write_protection | G01 |  |
| SB-RLS-017 | `subscription_cache_select` plus `subscription_cache_deny_insert`, `subscription_cache_deny_update`, `subscription_cache_deny_delete` | Select by org plus deny policies | 20260516100200_auth_rbac_rls; 20260524140100_fix_audit_log_write_protection | G07 |  |
| SB-RLS-018 | Tenant `*_org` policies on appointments, visits, visit_clinical_notes, etc. | `<table>_org` policies using current_org_id() | 20261002150000_tenant_scoping | G11 | Not AI-specific; listed for the tables the AI context provider reads. |
| SB-RLS-019 | `installation_keys_deny_all` on ai_internal.installation_keys | FOR ALL USING (false) | created 20260801120000; table DROPPED 20261007180000 | G02 | Dropped with its table. |

## SB-FN (1)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-FN-001 | None | There is no `functions` folder under backend/supabase and no edge function code in the repo | backend/supabase | G15 | config.toml has `[edge_runtime] enabled = true`, policy per_worker, inspector_port 8083, deno_version 2, and no secrets configured. The coverage pull is done in SQL via pg_net (see SB-CRON-001), not by an edge function. |

## SB-TYPE (2)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-TYPE-001 | `public.rpc_result` | Composite type: success boolean, data jsonb, error_code text, error_message text, contract_version integer | 20260516100000_auth_rbac_schema; contract_version attribute added in 20261007180000_issuer_key_custody | G06 | Return envelope of nearly every RPC. |
| SB-TYPE-002 | `public.staff_role` | Enum: administrator, doctor, receptionist, lab_staff | 20260611150000_remove_owner_role | G01 | `owner` was removed. Role stored in membership and staff_members. |

## SB-EXT (5)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-EXT-001 | `pgsodium` | Extension | 20260801120000_ai_keystore_schema | G06 | Used for Ed25519 key generation, signing and verification (crypto_sign_new_keypair, crypto_sign_detached, crypto_sign_verify_detached). `pgsodium_keymaker` granted to postgres. |
| SB-EXT-002 | `pg_cron` | Extension | 20261007230000_coverage_feed_puller_status | G15 | Runs the feed pull job. |
| SB-EXT-003 | `pg_net` | Extension | 20261007230000_coverage_feed_puller_status | G01 | Sends the feed GET request; responses read from net._http_response. |
| SB-EXT-004 | Supabase Vault (`vault` schema) | Used, not created in a migration | 20261007180000_issuer_key_custody | G17 | Stores issuer private keys (vault.create_secret, vault.decrypted_secrets). |
| SB-EXT-005 | `extensions.digest` (pgcrypto) | Used by get_ai_billing_status for sha256 | 20261008010000_read_time_status_notices | G07 |  |

## SB-ROLE (2)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-ROLE-001 | `launch_check_reader` | NOLOGIN role | 20261022120000_rm35_launch_state_reader | G06 | Only privilege: schema USAGE on ai_internal and EXECUTE on ai_internal.launch_state(). The operator creates a LOGIN role outside the repo and grants this role to it. |
| SB-ROLE-002 | `supabase_auth_admin` grant | EXECUTE on auth_internal.sync_active_organization(uuid) | 20261014170300_r1_sql03_live_staff_context (originally 20261002120000) | G06 | Granted only if the role exists. |

## SB-SCH (1)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-SCH-001 | Schemas `ai_internal`, `auth_internal` | Internal schemas | 20260801120000_ai_keystore_schema (ai_internal) | G01 | Neither is exposed through the REST API (config.toml api.schemas = public, graphql_public). |

## SB-HOOK (2)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-HOOK-001 | Auth hook `custom_access_token` | config.toml `[auth.hook.custom_access_token]` enabled, uri `pg-functions://postgres/public/get_custom_claims` | config.toml | G01 | Populates claims staff_member_id, staff_role, organization_id, branch_ids, setup_required (build_staff_claims) and active_org. |
| SB-HOOK-002 | Auth settings that affect tokens | config.toml `[auth]` jwt_expiry = 3600, enable_refresh_token_rotation = true, refresh_token_reuse_interval = 10, enable_signup = true, minimum_password_length = 6 | config.toml | G17 | Session lifetime seen by `assert_valid_ai_session` (it checks the `exp` claim). |

## SB-CRON (1)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-CRON-001 | `ai_coverage_feed_pull` | pg_cron job, schedule `30 seconds`, command `SELECT auth_internal.pull_coverage_feed()` | 20261007230000_coverage_feed_puller_status | G07 | The only cron job found in the migrations. Also invoked on demand by request_ai_status_refresh. Not unscheduled by any later migration. |

## SB-ENV (16)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-ENV-001 | `ai.issuer_id` | app_settings key, JSON string, seed `"issuer-test"` | 20261007180000_issuer_key_custody | G08 | Becomes the `iss` claim of AI, billing and feed tokens; also checked by verify_aat. |
| SB-ENV-002 | `ai.platform_base_url` | app_settings key, seed `"http://127.0.0.1:8787"` | 20261007180000_issuer_key_custody | G13 | Base URL of the AI platform. Returned as platform_base_url in get_ai_status; used by the feed puller. |
| SB-ENV-003 | `ai.abo_base_url` | app_settings key, seed `"http://127.0.0.1:8788"` | 20261007180000_issuer_key_custody | G03 | Returned as abo_base_url in the billing token and billing status. |
| SB-ENV-004 | `ai.contract_versions` | app_settings key, JSON object | 20261007180000_issuer_key_custody | G05 | Seed: aboClinic, aboConsole, backendRpc, platformClinic, platformFeed, vendorEntrypoint, platformDo, paymobReturn, paymobAdapter, each {current 1, minimum 0}. Only platformFeed.current is read by the feed puller; launch_state returns the whole object. |
| SB-ENV-005 | `ai.issuer.rate_limit.ceiling` | app_settings key, seed `100` | 20260801120000_ai_keystore_schema | G19 | AI token mints allowed per window per staff member. |
| SB-ENV-006 | `ai.issuer.rate_limit.window_seconds` | app_settings key, seed `3600` | 20260801120000_ai_keystore_schema | G09 |  |
| SB-ENV-007 | `ai.aat.lifetime_minutes` | app_settings key, value updated to `10` | 20260905120000_fix_aat_lifetime_minutes_seed | G08 | Still present in the table; the latest AI minter uses a fixed 600 seconds and does not read it. |
| SB-ENV-008 | `ai.aat.audience` | app_settings key, seed `"ai-platform"` | 20260801120000_ai_keystore_schema | G08 | Still present; latest minter hard-codes aud `ai-platform` and does not read it. |
| SB-ENV-009 | `ai.aat.ver` | app_settings key, seed `"1"` | 20260801120000_ai_keystore_schema | G08 | Still present; latest minters hard-code ver `2`. |
| SB-ENV-010 | `ai.availability` | app_settings key | created 20260802140000_ai_availability_flag | G07 | DELETED in 20261007230000_coverage_feed_puller_status. |
| SB-ENV-011 | Vault secret `issuer-key-<kid>` | Vault secret (base64 Ed25519 private key), description 'Ed25519 issuer private key' | 20261007180000_issuer_key_custody | G17 | One per issuer key; referenced by issuer_key.secret_ref. |
| SB-ENV-012 | Advisory lock keys 87201401 (AI mint) and 87201402 (billing mint) | pg_advisory_xact_lock namespaces | 20261014170600_r1_sql06 / 20261014170900_r2_c2 | G09 | Serialize per-staff rate-limit counting. |
| SB-ENV-013 | Session settings read: `request.jwt.claims`; `app.environment` | Postgres settings | 20260801120200_ai_token_issuer_rpc; seed.sql | G01 | seed.sql defines `public.local_dev_pre_request()` setting `app.environment = development` for local dev only, wired to the `authenticator` role as pgrst.db_pre_request. Not AI-specific. |
| SB-ENV-014 | config.toml `[studio] openai_api_key = env(OPENAI_API_KEY)` | config environment reference | config.toml | G08 | Supabase Studio's own AI assistant; unrelated to the clinic AI platform. Listed to avoid confusion. |
| SB-ENV-015 | Hard-coded limits in SQL | Constants | issue_billing_token / issue_ai_token / request_ai_status_refresh / pull_coverage_feed / get_ai_status | G17 | Billing token life 300 s; billing rate limit 20 per 10 minutes; AI token life 600 s; feed token life 120 s; issuer key validity 13 months; status refresh throttle 10 s; feed pending timeout 5 minutes; stale threshold 2 minutes; feed page limit 200; accepted contract versions (0, 1). |
| SB-ENV-016 | Permission keys relevant to AI | Rows in roles_permissions / default template | 20260516100400_auth_rbac_seed; 20260903180000_grant_ai_visit_summary_administrator | G06 | `ai.access` for administrator, doctor (owner row existed before the owner role was removed); `ai.visit_summary` for administrator. Seeded for each organization from the default template. The scopes in the AI token are whichever `ai.%` keys are granted for the caller's membership role. Also relevant: `visits.edit_soap` (needed by the acceptance target). |

## SB-ERR (18)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-ERR-001 | CONTRACT_VERSION_UNSUPPORTED | returned (rpc_result with data accepted_versions [0,1], contract_version 1, message 'Contract version is not supported.') by get_ai_status, get_ai_billing_status, request_ai_status_refresh, issue_billing_token; raised exception with DETAIL `{"accepted_versions":[0,1]}` by issue_ai_token | 20261007180000_issuer_key_custody, 20261007230000, 20261008010000 | G07 | NULL version is also unsupported. |
| SB-ERR-002 | FORBIDDEN_ROLE | returned | issue_billing_token, request_ai_status_refresh, get_ai_billing_status | G03 | Caller's membership role is not administrator. Messages: 'Only administrators can issue billing tokens.', 'Only administrators can request status refresh.', 'Only administrators can view billing status.' |
| SB-ERR-003 | FORBIDDEN | returned by rpc_error in billing/status/acceptance/active-org functions ('Organization context is required.'; 'You do not have a membership in that organisation.'); raised as exception by issue_ai_token | issue_billing_token, get_ai_status, request_ai_status_refresh, record_ai_acceptance, set_active_organization, issue_ai_token | G08 | Also used inside assert_* helpers. |
| SB-ERR-004 | STAFF_NOT_FOUND | returned by issue_billing_token ('Staff member was not found.'); raised by issue_ai_token |  | G08 | No live active staff row for the caller. |
| SB-ERR-005 | BRANCH_NOT_FOUND | returned by issue_billing_token ('No active branch is assigned for this organization.'); raised by issue_ai_token |  | G08 |  |
| SB-ERR-006 | ISSUER_KEY_NOT_CONFIGURED | returned by issue_billing_token ('Issuer signing key is not configured.'); raised by issue_ai_token and issue_feed_token |  | G17 | No `signing` key row, or its vault secret missing. |
| SB-ERR-007 | RATE_LIMITED | returned by issue_billing_token ('Billing token rate limit exceeded.') and request_ai_status_refresh ('Refresh was requested recently.'); raised by issue_ai_token |  | G08 |  |
| SB-ERR-008 | AI_ACCESS_DENIED | raised by issue_ai_token |  | G06 | Role has no granted `ai.%` permission in the org. |
| SB-ERR-009 | UNAUTHENTICATED | raised by assert_valid_ai_session; converted to rpc_error (code = message = UNAUTHENTICATED) in billing token and refresh |  | G03 |  |
| SB-ERR-010 | SESSION_EXPIRED | raised by assert_valid_ai_session when the `exp` claim is past; converted like UNAUTHENTICATED |  | G11 |  |
| SB-ERR-011 | INVALID_INPUT | returned by record_ai_acceptance (bad reference format 'Request reference must use the standard format.'; unregistered target 'Acceptance target is not registered.'; duplicate 'This AI output was already accepted for this record.') | 20260805150000_f2_review_resolution | G13 | Also by dropped set_ai_availability / revoke_installation_key. |
| SB-ERR-012 | INTERNAL_ERROR | returned by invoke_acceptance_domain_rpc ('Domain function is not configured.') |  | G11 |  |
| SB-ERR-013 | NOT_FOUND, FORBIDDEN | returned by get_visit_chief_complaint ('Visit was not found.', 'You do not have permission to view this visit clinical data.') | 20260805120000 | G08 |  |
| SB-ERR-014 | Exception 'Domain write did not return a record id.' | raised in record_ai_acceptance (rolls the whole transaction back) |  | G13 |  |
| SB-ERR-015 | Exceptions from canonical_issuer_jwt_json | 'issuer JWT JSON keys must be ASCII'; 'issuer JWT numbers must be safe integers'; 'unsupported issuer JWT JSON value: <kind>' | 20261014170000 | G12 |  |
| SB-ERR-016 | MEMBERSHIP_ROLE_REPAIR_HELD_ROWS | raised by the one-time repair DO block when unresolved rows remain | 20261014170500 | G01 | Migration-time only. |
| SB-ERR-017 | Staff update codes in update_staff_member | INVALID_INPUT, STAFF_NOT_FOUND, CROSS_ORG_DENIED, MEMBERSHIP_NOT_FOUND, LAST_ADMINISTRATOR, INVALID_BRANCH, FORBIDDEN | 20261014170400 | G13 | Listed because this function keeps membership role (token authority) in step. |
| SB-ERR-018 | ALREADY_ENROLLED, INSTALLATION_NOT_ENROLLED, KEY_NOT_FOUND, CANNOT_REVOKE_LAST_ACTIVE_KEY, SINGLE_INSTALLATION_VIOLATION | historic codes of the dropped installation keystore | see Dropped category | G17 | Not reachable in the latest state. |

## SB-DROP (8)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| SB-DROP-001 | `public.enroll_installation_keypair()` and `auth_internal.enroll_installation_keypair()` | RPC, dropped | created 20260801120100_ai_installation_keypair_routines; last body 20260902120000_enroll_installation_keypair_already_enrolled_guard; DROPPED 20261007180000_issuer_key_custody | G09 | Administrator only. Generated an Ed25519 keypair in the database (private key stored in installation_keys.secret_key), created or reused the single installation id, returned kid, installation_id and a public JWK (kty OKP, crv Ed25519, x, kid). Rejected with ALREADY_ENROLLED if an active key existed. |
| SB-DROP-002 | `public.rotate_installation_key()` and internal twin | RPC, dropped | 20260801120100; DROPPED 20261007180000 | G17 | Added a new key under the same installation id; INSTALLATION_NOT_ENROLLED if none. |
| SB-DROP-003 | `public.revoke_installation_key(p_kid text)` and internal twin | RPC, dropped | last body 20260905120600_revoke_fresh_return_stored_revoked_at; DROPPED 20261007180000 | G04 | Set revoked_at; idempotent for already revoked; refused to revoke the last active key (CANNOT_REVOKE_LAST_ACTIVE_KEY); KEY_NOT_FOUND. |
| SB-DROP-004 | `ai_internal.installation_keys` | Table, dropped | created 20260801120000_ai_keystore_schema; DROPPED 20261007180000 | G02 | Columns were: kid (PK), installation_id, public_key, secret_key, algorithm default 'EdDSA', valid_from, revoked_at, created_at, created_by, updated_at, updated_by, is_deleted, deleted_at, deleted_by. Plus trigger function `ai_internal.enforce_single_installation()` (also dropped). |
| SB-DROP-005 | Old `issue_ai_token(p_scopes text[])` public and internal | RPC, dropped | last body 20261002150000_tenant_scoping; DROPPED 20261007180000 | G08 | Signed with the installation key; iss was the installation id; ver from setting ai.aat.ver; had lifetime/rate-limit settings. Replaced by the integer-versioned function. Also the column ai_token_issuance.installation_id was dropped. |
| SB-DROP-006 | `public.set_ai_availability(p_enrolled boolean, p_platform_base_url text DEFAULT NULL)` and internal twin | RPC, dropped | created 20260905120100_set_ai_availability_rpc; created-by fix 20260905120400; DROPPED 20261007230000_coverage_feed_puller_status | G02 | Administrator-only writer for app_settings key `ai.availability` ({enrolled, platform_base_url}); required a URL when enrolled = true. |
| SB-DROP-007 | `public.get_ai_availability()` and internal twin | RPC, dropped | created 20260802140000_ai_availability_flag; DROPPED 20261007230000 | G13 | Returned the `ai.availability` JSON for any authenticated caller. Replaced by get_ai_status. |
| SB-DROP-008 | Two-argument `public.rpc_success(jsonb)` and `public.rpc_error(text, text)` | Helpers, dropped | 20261007180000_issuer_key_custody | G03 | Replaced by versions with an optional contract version. |

## FL-CALL (21)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CALL-001 | RPC `get_ai_status` (param `p_contract_version`) | Supabase RPC | features/ai/availability reader | G03 | Called by the shell status notifier refresh, the host bootstrap when no live status is pushed, the host admin-coverage refresh, and the live-host composer. Reply is a versioned rpc_result. |
| FL-CALL-002 | RPC `issue_ai_token` (param `p_contract_version`) | Supabase RPC | core/ai AAT mint port | G08 | Returns a bare JWS string; client checks the `ver` claim equals "2". Callers: SDK token acquisition, discovery manifest refresh, composer discovery step, host coverage fetch. |
| FL-CALL-003 | RPC `issue_billing_token` (param `p_contract_version`) | Supabase RPC | features/ai/billing token client | G03 | Returns token, abo_base_url, expires_at in rpc_result data. Called on billing page bootstrap and on renewal. |
| FL-CALL-004 | RPC `get_ai_billing_status` (param `p_contract_version`) | Supabase RPC | features/ai/billing subscription summary | G16 | Read together with GET /v1/subscription on each summary load. Notices list inside it is scanned for `ended_reversed`. |
| FL-CALL-005 | RPC `request_ai_status_refresh` (param `p_contract_version`) | Supabase RPC | features/ai/billing administrator page | G05 | Called when a checkout reaches Active (projection pull). Only success flag is used. |
| FL-CALL-006 | RPC `record_ai_acceptance` (params `p_request_reference`, `p_target_key`, `p_target_args`) | Supabase RPC | features/ai/acceptance client | G13 | Client and controller exist. No screen was found that constructs them (see doubts). |
| FL-CALL-007 | RPC `get_visit_chief_complaint` (param `p_visit_id`) | Supabase RPC | core/ai context provider port | G08 | Sole context resolver backend. Reply is rpc_result; no contract-version parameter is sent. |
| FL-CALL-008 | AP `GET {platformBaseUrl}/health` | HTTP | features/ai/availability reachability port | G02 | 5 second timeout; any 2xx is reachable; no token sent. Called by host bootstrap unless probe is skipped. |
| FL-CALL-009 | AP `GET /v1/capabilities` | HTTP | core/ai discovery client | G08 | Bearer AAT, header Aip-Contract-Version, optional If-None-Match. Called by composer and by manifest refresh (self-heal). |
| FL-CALL-010 | AP `GET /v1/coverage` | HTTP | core/ai usage summary client | G08 | Bearer AAT, Aip-Contract-Version. Only for administrators, from the host bootstrap and admin-coverage refresh. |
| FL-CALL-011 | AP `POST /v1/requests` (SSE reply) | HTTP | core/ai https submit port | G04 | Bearer AAT, idempotency, trace, capability-version, accept event-stream, Aip-Contract-Version headers. Body fields listed in FL-HDR section. |
| FL-CALL-012 | ABO `GET /v1/offers` | HTTP | features/ai/billing abo client | G03 | Called by the offers screen on load and retry. |
| FL-CALL-013 | ABO `GET /v1/billing-contact` | HTTP | abo client | G04 | 404 with code `not_found` is read as "contact missing". Called by billing contact form on load. |
| FL-CALL-014 | ABO `PUT /v1/billing-contact` | HTTP | abo client | G04 | Body client_request_id, name, email, phone. Called on Save contact. |
| FL-CALL-015 | ABO `POST /v1/checkouts` | HTTP | abo client | G19 | Body client_request_id, offer_id, offer_version, terms_version. Called on Pay now. |
| FL-CALL-016 | ABO `GET /v1/checkouts/{checkoutId}` | HTTP | abo client | G05 | Polling read; concurrent refreshes for the same id are shared. |
| FL-CALL-017 | ABO `GET /v1/checkouts?open=1` | HTTP | abo client | G20 | Used on billing page bootstrap to resume an open checkout, and by checkout screen when only a reference is known. |
| FL-CALL-018 | ABO `GET /v1/subscription` | HTTP | abo client | G07 | Called by the subscription summary and by the commercial notices widget. |
| FL-CALL-019 | ABO `GET /v1/payments` and `?cursor=` | HTTP | abo client | G07 | Payment history first page and next pages. |
| FL-CALL-020 | Payment page launch (`redirect_url` from checkout create) | External URL open | features/ai/billing checkout screen | G05 | Opens the external application (browser) via the URL launcher; this is the hand-off to Paymob. |
| FL-CALL-021 | Local fixture HTTP for `/v1/coverage` inside the host | Mock client in production file | features/ai/host | G02 | When a network spy is injected, host builds a mock http client that answers /v1/coverage with fixed figures; used by tests/harness. |

## FL-PROV (25)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-PROV-001 | `aiShellStatusNotifierProvider` (notifier of AiStatusSnapshot) | Riverpod notifier | app/providers | G11 | One status source for the whole app shell; timers: next_change_at timer and 5 minute periodic; resets on identity change or sign-out. |
| FL-PROV-002 | `aiShellStatusReaderProvider` | Riverpod provider | app/providers | G11 | Supplies the get_ai_status reader (Supabase). Override point. |
| FL-PROV-003 | `aiShellStatusRefreshProvider` | Riverpod provider | app/providers | G20 | Exposes the notifier refresh function; shared by app start, resume, AI page host. |
| FL-PROV-004 | `aiStatusIdentityFor` (user id, organization id, role) | Helper | app/providers | G13 | Identity is null when not authenticated or clinic setup is needed. |
| FL-PROV-005 | `AiStatusSnapshot` (identity, availability, updateRequired, refreshFailed) | State object | features/ai/availability | G13 | Published state of the shell notifier. |
| FL-PROV-006 | `AiStatusFetchGate` | Ordering helper | features/ai/availability | G13 | Generation counter so late reads cannot overwrite newer state. |
| FL-PROV-007 | `planAiStatusApply` / `AiStatusApplyPlan` (awaitStatus, updateRequired, noticesOnly, retainDenial, recomposeHost) | Decision function and enum | features/ai/availability | G06 | Decides how an open host reacts to a new status. |
| FL-PROV-008 | `aiStatusContextKey` (update-required, unknown, unavailable, ready | baseUrl) | Helper | G13 | |Readiness key used to detect recomposition. |
| FL-PROV-009 | App lifecycle hooks in the app root (start, resume, became-ready) | Lifecycle code | app/app.dart | G20 | Triggers shell status refresh; starts periodic refresh once; resume also reloads auth context. |
| FL-PROV-010 | `authSessionProvider` (consumed) | Riverpod provider | app/providers | G11 | Source of identity and administrator role for AI status and AI page. |
| FL-PROV-011 | `supabaseClientProvider` (consumed) | Riverpod provider | core/config | G11 | Client passed into AI composition. |
| FL-PROV-012 | `AiFeatureHostPage` state (mode, resolver, resolverEpoch, contextKey, denialRetained, notices, credits, subscriptionRef, planDisplayName, denial wire code and retry-after, request and bootstrap generations) | Widget state | features/ai/host | G07 | Holds degraded mode, resolver lifetime, administrator commercial fields. |
| FL-PROV-013 | `AiFeatureHostDependencies` | Dependency bundle | features/ai/host | G08 | Reader, reachability port, SDK, context provider, manifest refresh port, visit id, required keys, mint port, usage client, flags (skipReachabilityProbe, autoInvoke, staffIsAdministrator), onStatusRefresh. |
| FL-PROV-014 | `LiveVisitSummaryComposition` and `buildLiveVisitSummaryComposition` / `composeLiveVisitSummaryHost` | Composer | features/ai/presentation ai_page | G08 | Reads status, mints AAT, runs discovery, builds SDK and ports. Flags contractVersionUnsupported and discovery failure code/reference. Default platform base URL placeholder is an example workers.dev address; invalid placeholder `https://ai.invalid` used when no base URL. |
| FL-PROV-015 | `LiveVisitHostIdentity` and `liveVisitHostIdentityFor` | Identity key | ai_page | G09 | Key over user, organization, administrator flag, visit id; changes dispose the host. |
| FL-PROV-016 | `_LiveVisitSummaryHost` state (composition, load generation) | Widget state | ai_page | G15 | Loads composition; watches shell status and passes it as liveStatus only when identity matches. |
| FL-PROV-017 | `FirstAiFeatureSurface` state (phase idle/loading/streaming/completed/failed/localFailed/acknowledged/discarded; provisional text; terminal text; request reference; session) | Widget state | features/ai/surface | G11 | Drives invoke, stream listening, terminal handling. |
| FL-PROV-018 | `AdministratorBillingPage` state (step loading/offers/contact/checkout/appUpdate; selection; resumed checkout; billing generation; projection status idle/pending/pullFailed/caughtUp; epoch; reread count; baseline summary; timer) | Widget state | features/ai/billing | G20 | Owns sibling-read generation and the post-Active projection catch-up chain (pull, then up to 4 rereads 30 seconds apart). |
| FL-PROV-019 | `SubscriptionSummary` state, `CommercialNotices` state, `PaymentHistory` state, `OffersScreen` state, `BillingContactForm` state, `CheckoutScreen` state | Widget state | features/ai/billing | G03 | Each uses a request sequence and generation to drop stale replies. Checkout screen holds poll timer, poll failure count, client request id. |
| FL-PROV-020 | `ClinicalAcceptController` (staged request reference, staged complaint) | Controller | features/ai/acceptance | G13 | Accept calls the port with target key `visit_clinical_notes`; discard clears staging only. |
| FL-PROV-021 | `ConversationLoop` and `ConversationStore` (conversation id, transcript, pending user turn, leg ordinal) | Controller and local state | core/ai | G10 | Conversational legs; no UI caller found (see doubts). Transcript kinds: user, model, context_requested, context_resolved. |
| FL-PROV-022 | `ContextRequiredSelfHeal` | Orchestrator | core/ai | G08 | One refresh, resolve, resubmit round for single-shot capabilities. |
| FL-PROV-023 | `AiClientSdk` and `AiInvokeSession` | SDK class | core/ai | G04 | Token cache, in-flight mint sharing, remint once on unauthenticated, transport retry, idempotency key, trace id, last request reference. |
| FL-PROV-024 | `DiscoveryManifestRefreshPort` (cached manifests, interaction mode lookup) | Port implementation | core/ai | G08 | Keeps manifests in memory; mode conversational vs single-shot. |
| FL-PROV-025 | `InMemoryAiPersistenceProbe`, `InMemoryAiExportProbe`, `InMemoryPlatformNetworkSpy` | Probe classes in production files | features/ai | G11 | Observation helpers; no real persistence. |

## FL-CLIENT (14)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CLIENT-001 | `AboClient` | HTTP client | features/ai/billing | G03 | All ABO clinic calls; reserves a billing token per request; one retry on GET after 429 with code rate_limited or token_use_limit. |
| FL-CLIENT-002 | `BillingTokenClient` | Token client | features/ai/billing | G03 | See token section. |
| FL-CLIENT-003 | `SupabaseAiAvailabilityReader` (port `AiAvailabilityReader`) | RPC reader | features/ai/availability | G13 | get_ai_status; null data means not enrolled. |
| FL-CLIENT-004 | `HttpPlatformReachabilityPort` (port `PlatformReachabilityPort`) | HTTP probe | features/ai/availability | G08 | GET /health. |
| FL-CLIENT-005 | `SupabaseAatMintPort` (port `AatMintPort`) | RPC port | core/ai | G08 | issue_ai_token. |
| FL-CLIENT-006 | `PlatformHttpsSubmitPort` (port `HttpsSubmitPort`) | HTTP+SSE port | core/ai | G11 | POST /v1/requests; pre-stream error mapping; SSE connection. |
| FL-CLIENT-007 | `DiscoveryClient` | HTTP client | core/ai | G08 | GET /v1/capabilities; keeps last ETag in memory. |
| FL-CLIENT-008 | `UsageSummaryClient` | HTTP client | core/ai | G12 | GET /v1/coverage. |
| FL-CLIENT-009 | `SupabaseContextProviderPort` (port `ContextProviderPort`) | RPC port | core/ai | G11 | One per visit; get_visit_chief_complaint. |
| FL-CLIENT-010 | `ClinicalAcceptanceClient` (port `ClinicalAcceptancePort`) | RPC client | features/ai/acceptance | G13 | record_ai_acceptance with local error mapping (see errors). |
| FL-CLIENT-011 | `ContextResolver` | Resolver | core/ai | G08 | Key to resolver registry with per-screen cache. |
| FL-CLIENT-012 | `RpcResult` and `RpcFailure` | Shared RPC reply model | core/rpc | G03 | Fields success, data, error_code, error_message, contract_version. |
| FL-CLIENT-013 | Contract version guard (`echoesContractVersion`, `requireEchoedRpcContractVersion`, `isKnownContractVersion`) | Validation helper | core/contract_version_guard | G03 | Accepts sent version only if it is current or current minus 1, and the reply echoes it. |
| FL-CLIENT-014 | Test seams (rpc injection, debugAboContractVersionOverride) | Injection points | various | G03 | Present in production files; listed for completeness. |

## FL-TOKEN (9)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-TOKEN-001 | AI token (AAT) cache in the SDK | Memory cache | core/ai AiClientSdk | G08 | One cached token string; cleared once on `unauthenticated` then reminted; concurrent mints share one in-flight future. Never persisted. |
| FL-TOKEN-002 | AAT `ver` claim check ("2") | Validation | core/ai mint port | G08 | Decodes the JWS payload without verifying the signature; mismatch raises contract-version-unsupported. |
| FL-TOKEN-003 | AAT used as Bearer on AP routes | Header | core/ai | G08 | Used by submit, discovery, coverage. |
| FL-TOKEN-004 | Billing token session (token, abo_base_url, expires_at) | Memory object | features/ai/billing | G03 | In memory only for the page lifetime; disposed with the page. |
| FL-TOKEN-005 | Billing token renewal rule | Logic | billing token client | G03 | Renew when within 30 seconds of expiry. |
| FL-TOKEN-006 | Billing token local use cap | Logic | billing token client | G03 | Max local uses 59 per token; then a new token is minted. Counter reserved before each ABO call. |
| FL-TOKEN-007 | Billing token invalidation on server 429 | Logic | abo client | G03 | GET only: on rate_limited or token_use_limit the session is dropped and one fresh token is used for one retry. |
| FL-TOKEN-008 | Mint error handling for both token RPCs | Logic | both mint paths | G03 | Postgrest message containing CONTRACT_VERSION_UNSUPPORTED becomes contract-version-unsupported; billing mint also validates echoed version, requires data, token, abo_base_url, expires_at. |
| FL-TOKEN-009 | Supabase session / anon key handling | Config and session | core/config | G01 | Not AI-specific; supplies the authenticated session under which the RPCs run. |

## FL-SSE (14)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-SSE-001 | Line parser (UTF-8 stateful decode, line splitting on LF, CRLF, CR) | Parser | core/ai https submit port | G11 | Blank line ends a block; lines starting `event:` and `data:` only; other lines (id:, comments) ignored; multiple data lines are concatenated without separator. |
| FL-SSE-002 | Wire event `accepted` | Event mapping | https submit port | G13 | Needs `request_reference`, else dropped. |
| FL-SSE-003 | Wire event `heartbeat` | Event mapping | https submit port | G11 | Ignored by consumers. |
| FL-SSE-004 | Wire events `text_delta`, `partial_structured`, `usage`, `provider_note` | Event mapping | https submit port | G11 | All become content chunks keeping kind and payload; only `text_delta` text is shown by the surface. |
| FL-SSE-005 | Wire event `completed` | Event mapping | https submit port | G11 | Result is `result` field or whole data. |
| FL-SSE-006 | Wire event `failed` | Event mapping | https submit port | G11 | Fields code, request_reference, trace_id, retry_safe; unknown code becomes internal error. |
| FL-SSE-007 | Wire event `cancelled` | Event mapping | https submit port | G09 | Defensive parse; SDK synthesizes its own cancelled on local cancel. |
| FL-SSE-008 | Wire event `context_requested` | Event mapping | https submit port | G10 | Field `context_request` list; used by conversational loop. |
| FL-SSE-009 | Unknown event type, bad JSON, non-object data | Drop rule | https submit port | G11 | Silently dropped. |
| FL-SSE-010 | Terminal state model (completed, failed, cancelled, stream-dropped, context-requested) | Model | core/ai sse_events and SDK | G11 | Stream end or error without terminal and without local cancel is stream-dropped (retry-safe). Local cancel closes the connection. |
| FL-SSE-011 | Stream response gate (status 2xx and content-type text/event-stream, header Aip-Contract-Version echo) | Check | https submit port | G03 | Non-SSE or non-2xx goes to pre-stream error mapping; missing echo closes the stream unread. |
| FL-SSE-012 | Provisional vs terminal prose extraction (`provisionalChunkText`, `terminalProseText`) | Helpers | features/ai/surface | G11 | Terminal prose read from `final content`.`text` or `text`. |
| FL-SSE-013 | Transport retry policy | Policy | core/ai SDK | G04 | 3 attempts, backoff base 100 ms doubling capped at 800 ms with jitter; same idempotency key; then retry-exhausted. |
| FL-SSE-014 | Event relay (single-subscription source rebroadcast) | Mechanism | core/ai SDK | G07 | Allows surface and terminal consumer to listen together. |

## FL-CTX (11)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CTX-001 | `contextRegistration` map (closed static) | Registry | core/ai context_registration | G08 | Single entry: key `visit.chief_complaint@v1` mapped to chief complaint fetch. |
| FL-CTX-002 | `visit.chief_complaint@v1` | Context key | core/ai | G10 | Resolved through RPC get_visit_chief_complaint with the active visit id. |
| FL-CTX-003 | `ContextResolver.resolve` / `resolveRequests` | Resolver | core/ai | G08 | Unknown key gives failure code `unknown_context_key`; resolver exception gives `resolution_failed`; results cached per resolver instance; disposed resolver throws. |
| FL-CTX-004 | Context requirement extraction from manifests (`requiredContextKeysFromManifests`) | Helper | core/ai discovery client | G08 | Reads Identity capabilityId and Context requirements (key, required flag) by either spelling; default key list used if none found. |
| FL-CTX-005 | Default required keys for the first capability | Constant | features/ai/surface | G08 | List containing only visit.chief_complaint@v1. |
| FL-CTX-006 | Self-heal on `context_required` | Behaviour | core/ai context_required_self_heal | G04 | Only for single-shot capabilities; needs missing_keys; refresh manifests, resolve, resubmit once with same idempotency key and same capability version; second rejection surfaces; unhealable if no missing keys. |
| FL-CTX-007 | Heal abort exception (`ContextHealResolveException`) | Exception | core/ai | G10 | Carries resolve failure and request reference. |
| FL-CTX-008 | Interaction mode lookup (conversational vs single-shot) | Logic | discovery manifest refresh port | G12 | Reads Interaction.interactionMode; default single-shot. |
| FL-CTX-009 | Initial context sent with first invoke | Behaviour | first surface | G11 | Context = visit_id plus resolved payload; resolved before submit; failure shows local failure. |
| FL-CTX-010 | Conversational context loop (`context_requested` handling) | Behaviour | core/ai conversation loop | G10 | Resolves requested keys with arguments, appends transcript turns, submits continuation leg; resolve failure becomes internal-error failed terminal. |
| FL-CTX-011 | Capability constants (id `clinic.visit_summary`, version `1.0.0`, intent `generate`) | Constants | features/ai/surface | G08 | Hard-coded first capability. |

## FL-ERR (32)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-ERR-001 | Taxonomy set: unauthenticated, installation_suspended, forbidden_capability, rate_limited, quota_exhausted, request_too_large, context_required, context_invalid, conversation_budget_exhausted, capability_unknown, capability_retired, capability_disabled, provider_unavailable, provider_rejected, validation_failed, cancelled, timeout, internal_error, allowance_exhausted, coverage_lapsed, coverage_unknown, suspended, concurrency_limited, contract_version_unsupported, status_stale | Wire code enum (25) | core/ai taxonomy | G20 | Unknown wire code maps to internal_error. |
| FL-ERR-002 | Pre-stream denial rules: allowance_exhausted (403), coverage_lapsed (403, coverage_reason), coverage_unknown (503, retry_after), suspended (403), concurrency_limited (429, retry_after), rate_limited (429, retry_after), contract_version_unsupported (400, accepted_versions) | Status+code pairing | core/ai taxonomy | G20 | A code with a non-matching status is not treated as denial and falls to the generic mapping. |
| FL-ERR-003 | Pre-stream generic error body mapping | Mapping | https submit port | G08 | Reads code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id; unparsable body becomes transport failure (retried). |
| FL-ERR-004 | `unauthenticated` at submit | Behaviour | core/ai SDK | G11 | One remint and retry; second surfaces. |
| FL-ERR-005 | `contract_version_unsupported` (platform, 400 or missing header echo) | Behaviour | https submit port, discovery, coverage | G03 | Raises contract-version-unsupported exception; host shows app-update mode. |
| FL-ERR-006 | Transport failure / retries exhausted | Behaviour | SDK and surface | G13 | Surface reports coverage_unknown with network-failure flag, giving "unreachable" mode, plus failure view. |
| FL-ERR-007 | Discovery auth failure (taxonomy code and body) | Behaviour | discovery client, composer | G20 | Composer stores failure code and request reference; `installation_suspended` shows suspended view; reference shown otherwise; autoInvoke is off. |
| FL-ERR-008 | Coverage auth failure | Behaviour | usage summary client, host | G01 | Returns null silently; no gauge. |
| FL-ERR-009 | Coverage response shape errors (not object, missing snapshot, term not object, used/allowance not numeric) | Format errors | usage summary client | G06 | Raise format error; host swallows and logs. |
| FL-ERR-010 | Terminal failure to degraded mode mapping | Mapping | features/ai/degraded ai_degraded_mode | G20 | installation_suspended and suspended to installationSuspended; forbidden_capability to forbiddenCapability; quota_exhausted, allowance_exhausted, coverage_lapsed to quotaExhausted; coverage_unknown and status_stale to unreachable; concurrency_limited and rate_limited to safetyLimited; contract_version_unsupported, capability_unknown, capability_retired to appUpdate; provider_unavailable to providerUnavailable; capability_disabled to aiUnavailable; network failure to unreachable; other codes leave mode unchanged. |
| FL-ERR-011 | Coverage denial wire codes that trigger a status refresh: allowance_exhausted, coverage_lapsed, coverage_unknown | Set | features/ai/availability | G13 | Host calls onStatusRefresh and retains denial when status-fed. |
| FL-ERR-012 | Stream failed terminal handling in surface | Behaviour | first surface | G11 | Notifies host with code and wire code, shows request reference or "No request reference" text. |
| FL-ERR-013 | Stream dropped terminal handling | Behaviour | first surface | G11 | Reports internal_error to host, shows failure with last reference. |
| FL-ERR-014 | Local failures (resolve failure, unexpected exception, unexpected context_requested terminal) | Behaviour | first surface | G10 | Shows "could not be started on this device" text with any real reference. |
| FL-ERR-015 | Cancelled / invoke cancelled | Behaviour | first surface | G11 | Returns to idle. |
| FL-ERR-016 | ABO error codes: offer_unavailable (with current_version), idempotency_conflict, billing_contact_required, terms_not_accepted, provider_unavailable (with checkout_id), rate_limited, contract_version_unsupported (with accepted_versions), invalid_request, other/unknown (code or `abo_error`) | Exception classes | abo client | G03 | Mapped from body `code` on any non-2xx; each carries contract_version. |
| FL-ERR-017 | ABO 2xx version echo failure | Behaviour | abo client | G03 | Header Abo-Contract-Version and body contract_version must echo; else contract-version-unsupported with accepted versions [current-1, current]. |
| FL-ERR-018 | ABO 404 `not_found` on billing contact | Behaviour | abo client | G04 | Read as "no contact yet". |
| FL-ERR-019 | Checkout screen reactions | UI mapping | checkout_screen | G03 | offer_unavailable returns to offers; billing_contact_required returns to contact step; terms_not_accepted returns to offers; provider_unavailable shows provider-unavailable message and keeps checkout id; rate_limited shows rate-limited message (and in polling backs off); contract_version_unsupported shows app-update view; any other shows raw error text. |
| FL-ERR-020 | Offers screen reactions | UI mapping | offers_screen | G03 | contract_version_unsupported calls parent to app-update; terms_not_accepted unchecks terms; other error shows "plans could not be loaded" with retry. |
| FL-ERR-021 | Billing contact form reactions | UI mapping | billing_contact_form | G04 | billing_contact_required shows message; contract_version_unsupported goes to app-update; other error shows raw text. |
| FL-ERR-022 | Billing page bootstrap reactions | UI mapping | administrator_billing_page | G03 | Version errors give app-update step; other errors give offers step with load error. |
| FL-ERR-023 | Summary / notices / payment-history failure reactions | UI mapping | billing widgets | G07 | Summary: "coverage details could not be loaded" with retry; notices: raw error text with retry; history: "payment history could not be loaded" with retry. |
| FL-ERR-024 | Payment launch failure | UI mapping | checkout_screen | G05 | Shows hard-coded English text "Could not open payment page". |
| FL-ERR-025 | Checkout poll backoff | Behaviour | checkout_screen | G05 | Poll every 1 second normally; on failures 2 to 15 seconds (power of two clamp); polls while Waiting, Paid or Failed; stops on Active or Abandoned. |
| FL-ERR-026 | RPC failure codes: `CONTRACT_VERSION_UNSUPPORTED` (error_code) and echoed-version mismatch | Mapping | RPC readers | G03 | Becomes contract-version-unsupported exception; other failures raise RpcFailure with code and message. |
| FL-ERR-027 | Acceptance client local codes: `AUTH_ERROR`, `RPC_NOT_APPLIED` (PGRST202 or function missing), `RPC_NOT_CONFIGURED` (42501 or permission denied), passthrough postgrest code or `POSTGREST_ERROR` | Mapping | acceptance client | G13 | Wrapped into RpcResult with failure flag. |
| FL-ERR-028 | Context provider failures: `EMPTY_DATA`, RpcFailure | Mapping | context provider port | G11 | Resolver turns any throw into resolution_failed. |
| FL-ERR-029 | Shell status failure handling | Behaviour | ai_shell_status_provider | G03 | Contract-version-unsupported sets updateRequired; other failures keep last valid data and set refreshFailed. |
| FL-ERR-030 | Host bootstrap failure handling | Behaviour | host | G03 | Contract-version-unsupported gives app-update mode; any other error is fail-closed to not-enrolled (no AI chrome). |
| FL-ERR-031 | Enum parse errors (checkout shown_state unknown, payment classification unknown, reversal kind unknown, expires_at/datetime invalid) | Format errors | abo client | G16 | Raise format error; shown as generic failure. |
| FL-ERR-032 | Billing mint format errors (no data, incomplete session, invalid expires_at) | Errors | billing token client | G03 | State/format errors. |

## FL-NOTICE (21)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-NOTICE-001 | Status notices from `get_ai_status` `notices[]` (fields code, audience, channel, grace_days_left) | Notice record | features/ai/availability | G07 | Rendered by the host banner list. |
| FL-NOTICE-002 | `ends_soon` | Status notice code | host banner | G07 | Separate wording for administrator and staff. |
| FL-NOTICE-003 | `in_grace` (uses grace_days_left; zero shows "less than one day"; missing or negative gives neutral text) | Status notice code | host banner | G07 | Plural-aware localized text; administrator and staff variants. |
| FL-NOTICE-004 | `allowance_low` | Status notice code | host banner | G07 | Admin and staff variants. |
| FL-NOTICE-005 | `allowance_exhausted` | Status notice code | host banner | G07 | Admin and staff variants. |
| FL-NOTICE-006 | `lapsed` | Status notice code | host banner | G07 | Admin and staff variants. |
| FL-NOTICE-007 | `ended_reversed` | Status notice code | host banner and commercial notices and summary | G16 | Admin and staff variants in banner; admin text in commercial notices; summary shows a separate "recent plan ending reversed" line. |
| FL-NOTICE-008 | `suspended` | Status notice code | host banner | G20 | Admin and staff variants. |
| FL-NOTICE-009 | `status_stale` | Status notice code | host banner | G07 | Admin and staff variants. |
| FL-NOTICE-010 | Unknown status code | Fallback | host banner | G11 | Neutral "status information is unavailable" text; wire code never printed. |
| FL-NOTICE-011 | Banner audience behaviour | UI rule | host banner | G07 | Administrator banner has a Renew button to the billing page (hard-coded English "Renew"); staff banner appends "ask your administrator". The notice's audience and channel fields are parsed but not used to choose text. |
| FL-NOTICE-012 | Commercial notices from `GET /v1/subscription` `notices` (list of strings): `duplicate_payment` | Commercial notice code | features/ai/billing commercial_notices | G07 | Shown only on the administrator billing page. |
| FL-NOTICE-013 | `late_payment_honoured` | Commercial notice code | commercial_notices | G07 |  |
| FL-NOTICE-014 | `payment_withheld` | Commercial notice code | commercial_notices | G07 |  |
| FL-NOTICE-015 | `reversal_recorded` | Commercial notice code | commercial_notices | G16 |  |
| FL-NOTICE-016 | `terms_held` | Commercial notice code | commercial_notices | G07 |  |
| FL-NOTICE-017 | `ended_reversed` in commercial notices; unknown commercial code fallback to neutral text | Commercial notice rule | commercial_notices | G16 |  |
| FL-NOTICE-018 | `notices` inside RPC `get_ai_billing_status` (only `ended_reversed` is read) | Notice use | subscription_summary | G16 | Others ignored. |
| FL-NOTICE-019 | Projection notices: pending ("coverage update requested ...") and pull-failed | UI notice | administrator_billing_page | G05 | Shown after checkout reaches Active. |
| FL-NOTICE-020 | Starts-after-current-term notice | UI notice | checkout_screen | G06 | Shown when create response `starts` is `after_current`; user presses Pay to continue. |
| FL-NOTICE-021 | Localization keys defined but not referenced: `aiBillingErrorOfferUnavailable`, `aiBillingErrorTermsNotAccepted` | Unused strings | l10n | G03 | See doubts. |

## FL-DEG (20)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-DEG-001 | Mode `nonEnrolled` | Degraded mode | ai_degraded_mode / view | G07 | No AI chrome; only status notices if any. Also the fail-closed outcome of bootstrap errors and when available is false. |
| FL-DEG-002 | Mode `unreachable` | Degraded mode | degraded view | G13 | Text "AI service unreachable". Triggered by health probe failure, network failure, coverage_unknown, status_stale. |
| FL-DEG-003 | Mode `quotaExhausted` | Degraded mode | degraded view | G12 | Text depends on wire code: allowance_exhausted or coverage_lapsed show "AI not available, contact your administrator"; otherwise "AI quota exhausted. Contact your administrator." |
| FL-DEG-004 | Mode `aiUnavailable` | Degraded mode | degraded view | G08 | "AI temporarily unavailable" (capability_disabled). |
| FL-DEG-005 | Mode `appUpdate` | Degraded mode | degraded view | G08 | "Update the app to use AI". Triggers: contract-version failures, capability_unknown or retired, shell updateRequired, billing page version errors. |
| FL-DEG-006 | Mode `providerUnavailable` | Degraded mode | degraded view | G11 | "AI temporarily unavailable" with Retry button that re-enables the surface. |
| FL-DEG-007 | Mode `installationSuspended` | Degraded mode | degraded view | G20 | wire `suspended`: "AI not available, contact your administrator"; otherwise "AI features are suspended for this installation." Administrator with `suspended` also sees "Contact support" plus the subscription reference. |
| FL-DEG-008 | Mode `forbiddenCapability` | Degraded mode | degraded view | G08 | "Not included in your clinic's AI plan"; administrator may also see plan display name. |
| FL-DEG-009 | Mode `safetyLimited` | Degraded mode | degraded view | G11 | "AI busy, try again shortly" plus retry_after text when present. |
| FL-DEG-010 | Mode `ready` | Normal mode | degraded view | G13 | Wraps the child surface. |
| FL-DEG-011 | "Renew or buy" button for administrators on allowance_exhausted or coverage_lapsed | Action | degraded view | G11 | Navigates to the administrator billing route. |
| FL-DEG-012 | Surface-hiding rule (all modes except ready hide the surface and show "Clinical workflows remain available.") | Rule | host | G13 | Resolver disposed when hidden. |
| FL-DEG-013 | Denial retention (coverage denial stays until fresh status shows recovery) | Rule | host and snapshot plan | G15 | Only for status-fed hosts. |
| FL-DEG-014 | Status-driven recomposition never auto-invokes | Rule | host | G11 | User must press to run again. |
| FL-DEG-015 | Discovery-failure views (installation_suspended view; request reference line for other discovery failures) | Pre-host states | ai_page liveVisitSummaryHostBody | G20 | Contract-version failure at compose time shows app-update view. |
| FL-DEG-016 | Administrator-only usage gauge hidden for non-administrators; commercial fields masked at render for non-administrators | Rule | host | G07 | Role loss clears credits, plan name and subscription reference immediately. |
| FL-DEG-017 | Surface phases: loading text, streaming provisional prose, completed, failed (with/without reference), local failure, acknowledged, discarded, idle | Surface states | first surface | G11 | Texts are hard-coded English. |
| FL-DEG-018 | Billing page app-update step | Degraded state | administrator_billing_page | G13 | Replaces page body with app-update view. |
| FL-DEG-019 | Billing widgets' loading/refreshing/error/empty states | UI states | billing widgets | G03 | Offers: loading, error, empty, list; summary: no active plan vs active plan; history: empty, error, load more. |
| FL-DEG-020 | Route redirect for non-administrators on billing route | Access rule | router | G11 | Non-administrator is sent to home. |

## FL-UI (20)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-UI-001 | AI page (`/ai`) | Screen | features/ai/presentation/pages/ai_page | G13 | Hub: administrator billing entry card, live visit-summary host (visit id field + Load surface), surface primitives demo, degraded-mode demo, and design-system demos (mode toggle, thinking indicator, message bubbles, inline suggestion, proposed action, AI panel). |
| FL-UI-002 | Administrator billing page (`/ai/administrator-billing`) | Screen | features/ai/billing | G03 | Steps offers, contact, checkout; siblings summary, notices, history; Refresh billing button. Administrator-only via redirect. |
| FL-UI-003 | Offers screen | Widget | billing | G03 | Offer cards (localized name/summary, price), terms text, accept checkbox, Continue; empty/error states. |
| FL-UI-004 | Billing contact form | Widget | billing | G04 | Name, email, phone, Save contact; idempotency id per payload. |
| FL-UI-005 | Checkout screen | Widget | billing | G05 | Reference, price, shown state label (Waiting, Failed, Paid, Active, Abandoned), Pay now, queued-term line. |
| FL-UI-006 | Subscription summary | Widget | billing | G16 | Plan name, started, ends, grace ends, credits included/used, clinic support reference, ended-reversed line. Also parsed (queued_count, held_count) but not displayed. |
| FL-UI-007 | Commercial notices | Widget | billing | G07 | List of localized commercial notice lines. |
| FL-UI-008 | Payment history | Widget | billing | G16 | Plan name, date, reference, raw amount minor + currency, Load more. Reversals and classification are parsed but not displayed. |
| FL-UI-009 | Billing money formatter | Helper | billing | G02 | Minor units divided by 100 with 2 decimals. |
| FL-UI-010 | AI feature host page (`/ai/feature-host`, route extra) | Screen | features/ai/host | G11 | Standalone host requiring dependencies via route extra; otherwise a text message. Also used embedded in AI page. |
| FL-UI-011 | First AI feature surface | Widget | features/ai/surface | G11 | Auto-invokes on mount; Accept (local acknowledgement only) and Discard. |
| FL-UI-012 | Provisional prose view | Widget | surface | G11 | Draft styling with semantics label "AI draft content". |
| FL-UI-013 | Request reference view | Widget | surface | G02 | "Reference: <id>". |
| FL-UI-014 | Usage gauge, gate marker, unreachable marker | Widgets | surface | G12 | Credits used vs budget bar. |
| FL-UI-015 | AI degraded view | Widget | degraded | G13 | See degraded section; keyed widgets per mode. |
| FL-UI-016 | Status notice banner list | Widget | host | G07 | Admin Renew button or staff note. |
| FL-UI-017 | Shell nav entry `ai` and route meta text | Navigation | app/shell navigation | G11 | Route `/ai` in shell nav config. |
| FL-UI-018 | Routes: `/ai`, `/ai/administrator-billing`, `/ai/feature-host` | Route constants | app/app_routes, router | G11 | Billing route has administrator redirect. |
| FL-UI-019 | Design-system AI showcase and core UI components (AI panel, message bubble, suggestion, thinking indicator, proposed action card, mode toggle) | Components | core/ui and design_system | G02 | Visual demos; no backend calls found. |
| FL-UI-020 | Localization strings with prefix `aiBilling` and `aiNotice` (English and Arabic) | Strings | l10n | G07 | Count of English keys with these prefixes is 74 in each of English and Arabic; hard-coded English strings also exist in degraded view and surface. |

## FL-STORE (5)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-STORE-001 | No AI or billing data is written to local storage, secure storage or key store | Finding of absence | whole frontend/lib | G22 | Searched for shared preferences, secure storage and key store use: only unrelated settings, setup draft, workspace mode, idle timeout, deployment profile. No clinic keypair or private key handling found in the Flutter code. |
| FL-STORE-002 | AI token and billing token are memory-only | Fact | core/ai, billing | G08 | See token section. |
| FL-STORE-003 | Conversation transcript is memory-only and cleared on close | Fact | core/ai conversation store | G08 |  |
| FL-STORE-004 | ETag for discovery is memory-only | Fact | discovery client | G08 | Kept per client instance. |
| FL-STORE-005 | Deployment profile file/store (contains optional `ai_service_url`) | Config store | core/config | G13 | `ai_service_url` is parsed into the config but no AI code reads it (platform base URL comes from get_ai_status). |

## FL-CFG (17)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-CFG-001 | `ABO_CONTRACT_VERSION_OVERRIDE` | Process environment variable | abo client | G03 | Overrides the Abo-Contract-Version header value (desktop platforms). |
| FL-CFG-002 | `ABO_BILLING_HOST` | Process environment variable | abo client | G08 | Overrides the Host header sent to the ABO. |
| FL-CFG-003 | Local billing host constant `billing.vendor.test` | Constant | abo client | G08 | Host header used when the ABO base URL host is 127.0.0.1 or localhost. |
| FL-CFG-004 | Contract version constants: aboClinic 1, aboConsole 1, backendRpc 1, platformClinic 1, platformFeed 1, vendorEntrypoint 1, platformDo 1, paymobReturn 1, paymobAdapter 1 | Constants | core/contract_versions | G05 | backendRpc sent as `p_contract_version`; platformClinic as Aip-Contract-Version; aboClinic as Abo-Contract-Version; the rest are not used by Flutter AI code. |
| FL-CFG-005 | `expectedTokenVer` "2" | Constant | mint port | G08 | AAT `ver` claim. |
| FL-CFG-006 | `kDefaultMaxTransportAttempts` 3 and backoff constants | Constant | SDK | G08 |  |
| FL-CFG-007 | Billing token constants: renew-before-expiry 30 seconds, max local uses 59 | Constants | billing token client | G03 |  |
| FL-CFG-008 | Projection constants: reread interval 30 seconds, max rereads 4 | Constants | billing page | G08 |  |
| FL-CFG-009 | Shell status constants: periodic interval 5 minutes | Constant | shell notifier | G13 | Also next_change_at timer. |
| FL-CFG-010 | Health probe timeout 5 seconds | Constant | reachability port | G08 |  |
| FL-CFG-011 | Checkout poll interval 1 second and backoff cap 15 seconds | Constants | checkout screen | G05 |  |
| FL-CFG-012 | Default platform base URL placeholder (example workers.dev) and invalid placeholder `https://ai.invalid` | Constants | ai_page composer | G08 | Placeholder when no real base URL is known. |
| FL-CFG-013 | Platform base URL source: `platform_base_url` field of `get_ai_status` | Config source | availability model | G13 | The only runtime source of the AP address. |
| FL-CFG-014 | ABO base URL source: `abo_base_url` field of `issue_billing_token` | Config source | billing token client | G03 |  |
| FL-CFG-015 | Deployment profile keys: `deployment_mode`, `supabase_url`, `supabase_anon_key`, `ai_service_url`, `source_device_role` | Config keys | core/config | G01 | Only `ai_service_url` is AI-related and appears unused. |
| FL-CFG-016 | Client request id format (`billing-checkout-<microseconds>`, `billing-contact-<microseconds>`) | Generated id | checkout screen, contact form | G04 | Reused across retries until contact payload changes; checkout id stable per screen. |
| FL-CFG-017 | SDK idempotency key and trace id generation (32 hex chars, secure random) | Generated id | SDK and self-heal | G04 | Self-heal pins one key across both submits; conversation legs pass an optional key factory. |

## FL-HDR (10)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-HDR-001 | `Authorization: Bearer <AAT>` on AP routes | Header | core/ai | G08 |  |
| FL-HDR-002 | `Aip-Contract-Version` (sent 1; response must echo) | Header | core/ai | G08 | Checked on submit, discovery (including 304) and coverage. |
| FL-HDR-003 | `x-idempotency-key`, `x-trace-id`, `x-capability-version`, `accept: text/event-stream`, `content-type: application/json` | Headers | https submit port | G04 |  |
| FL-HDR-004 | Submit body: capability_id, capability_version, user_intent, context, conversation_id, turn_ordinal, transcript | Body fields | https submit port | G08 | The last three only for conversational legs. |
| FL-HDR-005 | `if-none-match` and response `etag` | Headers | discovery client | G08 | 304 requires version echo, keeps cached manifests. |
| FL-HDR-006 | `Authorization: Bearer <billing token>` on ABO routes | Header | abo client | G03 |  |
| FL-HDR-007 | `Abo-Contract-Version` (sent 1; response header and body field contract_version must echo) | Header | abo client | G03 |  |
| FL-HDR-008 | `Host` header override on ABO calls | Header | abo client | G03 | See FL-CFG-002 and FL-CFG-003. |
| FL-HDR-009 | `content-type: application/json` on PUT/POST to ABO | Header | abo client | G03 |  |
| FL-HDR-010 | RPC param `p_contract_version` | RPC field | all versioned RPCs | G03 |  |

## FL-DTO (15)

| ID | Item | Kind | Source area | Assigned group | Notes |
|---|---|---|---|---|---|
| FL-DTO-001 | `get_ai_status` data: available (or enrolled), state, reason, days_left, band, notices[], next_change_at, as_of, stale, platform_base_url | DTO | availability model | G07 | `enrolled` kept as legacy gate; `state`, `band`, `days_left`, `as_of`, `stale` are parsed and kept but not read by UI. `reason` is compared with coverage denial codes. |
| FL-DTO-002 | `issue_billing_token` data: token, abo_base_url, expires_at | DTO | billing token client | G03 |  |
| FL-DTO-003 | Offers: contract_version, offers[] (offer_id, version, plan_display_name, term_unit, term_count, price_minor, currency, allowance_credits, grace_days, copy{locale:{name,summary}}, terms{version,text}) | DTO | abo client | G03 | Locale picks device language then `en` then plan name. |
| FL-DTO-004 | Billing contact: contract_version, version, name, email, phone | DTO | abo client | G03 |  |
| FL-DTO-005 | Checkout create: contract_version, checkout_id, reference, redirect_url, expires_at, starts (`now` or `after_current`), projected_start | DTO | abo client | G05 | projected_start kept only for after_current; not displayed. |
| FL-DTO-006 | Checkout read: contract_version, reference, shown_state (Waiting, Failed, Paid, Active, Abandoned), offer{offer_id, version, term_unit, term_count, charged_price_minor, currency}, updated_at | DTO | abo client | G03 |  |
| FL-DTO-007 | Open checkouts: contract_version, checkouts[] | DTO | abo client | G20 | First open checkout is resumed. |
| FL-DTO-008 | Payments: contract_version, payments[] (reference, paid_at, amount_minor, currency, plan_display_name, offer_version, term_unit, term_count, classification normal/likely_duplicate/late, reversals[] reference/amount_minor/kind refund/void/chargeback/unknown/is_full), next_cursor, has_more | DTO | abo client | G21 |  |
| FL-DTO-009 | Subscription: contract_version, subscription_ref, snapshot (free map), notices[] | DTO | abo client | G07 | Snapshot is kept as a raw map; the summary widget does not read it (display fields come from get_ai_billing_status). |
| FL-DTO-010 | `get_ai_billing_status` data: plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, queued_count, held_count, subscription_ref, notices[{code}] | DTO | subscription_summary | G07 |  |
| FL-DTO-011 | Coverage: subscription_ref, snapshot{term{used, allowance, plan_display_name}}, queued_terms, recent_terms | DTO | usage_summary_client | G06 | Only subscription_ref and term used/allowance/plan name are read. |
| FL-DTO-012 | Capabilities: manifests[] (Identity, Context requirements, Interaction), response contract_version | DTO | discovery client | G08 | Keys read by two spellings (capitalised phrase or snake case). |
| FL-DTO-013 | `get_visit_chief_complaint` data (map passed through as context value) | DTO | context provider port | G11 |  |
| FL-DTO-014 | `record_ai_acceptance` target args for key `visit_clinical_notes`: p_visit_id, p_complaint, p_history, p_examination, p_diagnosis, p_plan, p_expected_updated_at | DTO | acceptance controller | G13 |  |
| FL-DTO-015 | Failed event / pre-stream error body: code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id, retry_after, coverage_reason, accepted_versions | DTO | https submit port | G08 |  |

## Unassigned

None.
